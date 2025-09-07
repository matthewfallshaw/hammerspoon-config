-- Move windows between spaces
-- # Usage
-- local move_spaces = require 'move_spaces'
--
-- -- Initialize with configuration and bind hotkeys
-- -- Because Apple doesn't provide a proper API for spaces, we cause the moves by
-- -- sending macOS's keyboard shortcuts and mouse events. The space_jump_modifiers
-- -- config parameter specifies which modifier keys are configured on your OS to
-- -- jump between spaces
-- -- (e.g., {"ctrl"} for ctrl+number, or {"ctrl", "shift"} for ctrl+shift+number).
-- ```
-- move_spaces:start({
--   space_jump_modifiers = {"ctrl"},
--   hotkeys = {  -- double-tap to return after move
--     left  = {{"⌘", "⌥", "⌃", "⇧"}, "h"},
--     right = {{"⌘", "⌥", "⌃", "⇧"}, "l"},
--     toSpace = {{"⌘", "⌥", "⌃", "⇧"}},
--   }
-- })
-- ```


-- luacheck: globals hs spoon

local M = { hotkeys = {}, _config = {} }

-- Configuration constants
-- Default modifier keys for space-switching keyboard shortcuts sent to macOS
local DEFAULT_SPACE_JUMP_MODIFIERS = {"ctrl"}

-- Get configuration constants including timing
local consts = require('configConsts')
local TIMING = consts.timing

-- Utilities
require('utilities.table')

M._logger = hs.logger.new("Move spaces")
local logger = M._logger
-- logger.setLogLevel('warning')
logger.setLogLevel('debug')

local desktop_space_numbers = require('desktop_space_numbers')
local desktop_state = require('desktop_state')

-- Helper: find space ID and display ID for a given space number
local function findSpaceIdAndDisplayId(target_space_number)
  -- Use translation helpers from desktop_space_numbers
  local target_space_id = desktop_space_numbers.getSpaceId(target_space_number)

  if not target_space_id then
    logger.e('Could not find space number ' .. target_space_number)
    return nil, nil, "Could not find target space"
  end

  local target_display = desktop_space_numbers.getSpaceDisplay(target_space_id)

  if not target_display then
    logger.e('Could not find display for space ' .. target_space_number)
    return nil, nil, "Could not find target display"
  end

  logger.d(string.format('For space number %d, found: space ID=%s, display ID=%s',
           target_space_number, tostring(target_space_id), target_display:name()))

  return target_space_id, target_display, nil
end

-- === BASIC SYSTEM ACTIONS ===
-- Fundamental atomic operations that other commands can use

-- Basic action: Focus a window
local function actionFocusWindow(win)
  logger.d(string.format('actionFocusWindow: focusing window on %s', win:screen():name()))
  win:focus()
  return true
end

-- Basic action: Jump to a specific space (changes active space)
local function actionJumpToSpace(target_space_number)
  local config = M._config
  local space_jump_modifiers = config.space_jump_modifiers or DEFAULT_SPACE_JUMP_MODIFIERS

  logger.d(string.format('actionJumpToSpace: jumping to space %d', target_space_number))
  local key = desktop_state.spaceNumberToKey(target_space_number)
  logger.d(string.format('Pressing %s+%s to jump to space %d', table.concat(space_jump_modifiers, "+"), key, target_space_number))
  hs.eventtap.keyStroke(space_jump_modifiers, key, 0)
  return true
end

-- Basic action: Perform drag+keystroke operation to move window to space
local function actionDragWindowToSpace(target_space_number, win)
  logger.d(string.format('actionDragWindowToSpace: dragging window to space %d', target_space_number))

  -- Get zoom button location and adjust slightly for safety
  local zoomPoint = hs.geometry(win:zoomButtonRect())
  local clickPoint = zoomPoint:move({-1,-1}).topleft

  logger.d(string.format('actionDragWindowToSpace: using click point (%.0f,%.0f)', clickPoint.x, clickPoint.y))

  -- Save mouse position to restore later
  local currentCursor = hs.mouse.getRelativePosition()

  -- Use try/ensure to guarantee cleanup
  local try_catch = require('utilities.try_catch')

  local result = try_catch.try {
    function()
      -- Click and hold the titlebar
      hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, clickPoint):post()

      -- Jump to target space while dragging
      actionJumpToSpace(target_space_number)

      return true
    end,
    try_catch.ensure {
      function()
        -- Always release the drag and restore mouse position
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, clickPoint):post()
        hs.mouse.setRelativePosition(currentCursor)
      end
    }
  }

  return result or false
end

-- Basic action: Move window to different display using WindowScreenLeftAndRight
local function actionMoveWindowToDisplay(target_display, win)
  local win_screen = win:screen()

  logger.d(string.format('actionMoveWindowToDisplay: moving window from %s to %s', win_screen:name(), target_display:name()))

  if win_screen:id() == target_display:id() then
    logger.d('actionMoveWindowToDisplay: already on target display')
    return true
  end

  -- Use WindowScreenLeftAndRight spoon to move between displays
  local target_is_left = target_display:frame().x < win_screen:frame().x

  if target_is_left then
    spoon.WindowScreenLeftAndRight.moveCurrentWindowToScreen("left")
  else
    spoon.WindowScreenLeftAndRight.moveCurrentWindowToScreen("right")
  end

  return true
end

-- === COMMAND ARCHITECTURE ===
-- Commands with pre-check, prerequisite injection, execute, and post-check phases

-- Result constants
local COMMAND_RESULT = {
  PASS = "pass",     -- Command is not needed (already satisfied)
  FAIL = "fail",     -- Command cannot be executed (error condition)
  SUCCESS = "success", -- Command executed successfully
  RETRY = "retry"    -- Command should be retried
}

-- Enhanced command definitions
local COMMAND_TYPES = {
  FOCUS_WINDOW = {
    pre_check = function(cmd)
      local focused = desktop_state.isWindowFocused(cmd.window)
      logger.d(string.format("FOCUS_WINDOW pre_check: focused=%s", tostring(focused)))
      if focused then
        return COMMAND_RESULT.PASS
      else
        return true  -- Ready to execute
      end
    end,
    prerequisite_achiever = function(cmd)
      -- No prerequisites for focusing
      return {}
    end,
    execute = function(cmd)
      return actionFocusWindow(cmd.window)
    end,
    post_check = function(cmd)
      local focused = desktop_state.isWindowFocused(cmd.window)
      logger.d(string.format("FOCUS_WINDOW post_check: focused=%s", tostring(focused)))
      return focused
    end,
    post_check_timeout = 0.5  -- 500ms in seconds
  },

  MOVE_WINDOW_TO_DISPLAY = {
    pre_check = function(cmd)
      -- Check if already on target display
      if desktop_state.isWindowOnDisplay(cmd.window, cmd.target_display) then
        logger.d("MOVE_WINDOW_TO_DISPLAY pre_check: already on target display")
        return COMMAND_RESULT.PASS
      end

      -- Check if focused and stable
      local focused = desktop_state.isWindowFocused(cmd.window)
      local stable = desktop_state.isWindowStableOnDisplay(cmd.window, cmd.window:screen())

      logger.d(string.format("MOVE_WINDOW_TO_DISPLAY pre_check: focused=%s, stable=%s",
                           tostring(focused), tostring(stable)))
      if focused and stable then
        return true  -- Ready to execute
      else
        return false  -- Prerequisites needed
      end
    end,
    prerequisite_achiever = function(cmd)
      local prereqs = {}

      -- Ensure window is focused
      if not desktop_state.isWindowFocused(cmd.window) then
        table.insert(prereqs, {
          type = "FOCUS_WINDOW",
          window = cmd.window
        })
      end

      return prereqs
    end,
    execute = function(cmd)
      return actionMoveWindowToDisplay(cmd.target_display, cmd.window)
    end,
    post_check = function(cmd)
      local stable = desktop_state.isWindowStableOnDisplay(cmd.window, cmd.target_display)
      logger.d(string.format("MOVE_WINDOW_TO_DISPLAY post_check: stable=%s", tostring(stable)))
      return stable
    end,
    post_check_timeout = TIMING.DISPLAY_MOVE_WAIT
  },

  MOVE_WINDOW_TO_SPACE = {
    pre_check = function(cmd)
      -- Check if already on target space
      local window_space_number = desktop_state.getWindowSpaceNumber(cmd.window)
      if window_space_number == cmd.target_space_number then
        logger.d("MOVE_WINDOW_TO_SPACE pre_check: already on target space")
        return COMMAND_RESULT.PASS
      end

      -- Check if window is on target display (if so, can execute)
      local target_space_id, target_display = findSpaceIdAndDisplayId(cmd.target_space_number)
      if not target_space_id then
        logger.e("MOVE_WINDOW_TO_SPACE pre_check: invalid target space")
        return COMMAND_RESULT.FAIL
      end

      if desktop_state.isWindowOnDisplay(cmd.window, target_display) then
        -- Window is on target display, check if ready to execute
        local focused = desktop_state.isWindowFocused(cmd.window)
        local stable = desktop_state.isWindowStableOnDisplay(cmd.window, target_display)

        logger.d(string.format("MOVE_WINDOW_TO_SPACE pre_check: on target display, focused=%s, stable=%s",
                             tostring(focused), tostring(stable)))
        return focused and stable
      else
        -- Window is on wrong display - need prerequisites
        logger.d("MOVE_WINDOW_TO_SPACE pre_check: window on wrong display, need prerequisites")
        return false
      end
    end,
    prerequisite_achiever = function(cmd)
      local prereqs = {}

      -- Check if cross-display move needed (stateful check)
      local target_space_id, target_display = findSpaceIdAndDisplayId(cmd.target_space_number)
      if target_display and not desktop_state.isWindowOnDisplay(cmd.window, target_display) then
        logger.d(string.format("MOVE_WINDOW_TO_SPACE prerequisite: cross-display move needed to %s", target_display:name()))
        table.insert(prereqs, {
          type = "MOVE_WINDOW_TO_DISPLAY",
          window = cmd.window,
          target_display = target_display
        })
      end

      -- Ensure window is focused
      if not desktop_state.isWindowFocused(cmd.window) then
        table.insert(prereqs, {
          type = "FOCUS_WINDOW",
          window = cmd.window
        })
      end

      return prereqs
    end,
    execute = function(cmd)
      return actionDragWindowToSpace(cmd.target_space_number, cmd.window)
    end,
    post_check = function(cmd)
      local window_space_number = desktop_state.getWindowSpaceNumber(cmd.window)
      local success = window_space_number == cmd.target_space_number
      logger.d(string.format("MOVE_WINDOW_TO_SPACE post_check: window space=%s, target=%s, success=%s",
                           tostring(window_space_number), tostring(cmd.target_space_number), tostring(success)))
      return success
    end,
    post_check_timeout = TIMING.SPACE_MOVE_TIMEOUT
  },

  JUMP_TO_SPACE = {
    pre_check = function(cmd)
      -- Skip spaces beyond direct keyboard shortcuts (temporary workaround)
      if cmd.target_space_number > 10 then
        logger.w(string.format("JUMP_TO_SPACE pre_check: space %d beyond keyboard range, skipping", cmd.target_space_number))
        return COMMAND_RESULT.PASS
      end
      
      local already_on_space = desktop_state.isDisplayOnSpace(cmd.target_display, cmd.target_space_number)
      logger.d(string.format("JUMP_TO_SPACE pre_check: display=%s, target space=%s, already_there=%s",
                           cmd.target_display:name(), tostring(cmd.target_space_number), tostring(already_on_space)))
      return already_on_space and COMMAND_RESULT.PASS or true
    end,
    prerequisite_achiever = function(cmd)
      -- No prerequisites for jumping to space
      return {}
    end,
    execute = function(cmd)
      return actionJumpToSpace(cmd.target_space_number)
    end,
    post_check = function(cmd)
      local success = desktop_state.isDisplayOnSpace(cmd.target_display, cmd.target_space_number)
      logger.d(string.format("JUMP_TO_SPACE post_check: display=%s, target space=%s, success=%s",
                           cmd.target_display:name(), tostring(cmd.target_space_number), tostring(success)))
      return success
    end,
    post_check_timeout = TIMING.SPACE_MOVE_TIMEOUT
  },

  LAMBDA = {
    pre_check = function(cmd)
      logger.d(string.format("LAMBDA pre_check: %s", cmd.description or "custom operation"))
      -- Custom pre-check function provided in command
      if cmd.pre_check_fn then
        return cmd.pre_check_fn(cmd)
      end
      return true -- Ready to execute by default
    end,
    prerequisite_achiever = function(cmd)
      -- Custom prerequisite function or empty
      if cmd.prerequisite_fn then
        return cmd.prerequisite_fn(cmd)
      end
      return {}
    end,
    execute = function(cmd)
      logger.d(string.format("LAMBDA execute: %s", cmd.description or "custom operation"))
      -- Execute custom function
      if cmd.execute_fn then
        local success = cmd.execute_fn(cmd)
        logger.d(string.format("LAMBDA execute result: %s", tostring(success)))
        return success
      end
      logger.w("LAMBDA execute: no execute_fn provided, assuming success")
      return true
    end,
    post_check = function(cmd)
      -- Custom validation function
      if cmd.post_check_fn then
        local success = cmd.post_check_fn(cmd)
        logger.d(string.format("LAMBDA post_check: %s, result=%s", cmd.description or "custom operation", tostring(success)))
        return success
      end
      -- Assume success if no validation provided
      logger.d(string.format("LAMBDA post_check: %s (no validation, assuming success)", cmd.description or "custom operation"))
      return true
    end,
    post_check_timeout = function(cmd)
      return cmd.timeout or 1.0 -- Default 1 second
    end
  }
}

-- === ATOMIC QUEUE OPERATIONS ===
-- Commands are decomposed into atomic operations for cleaner processing

-- Operation types for queue items
local OPERATION_TYPES = {
  PRE_CHECK = "PRE_CHECK",     -- Check if command is ready to execute
  EXECUTE = "EXECUTE",         -- Perform the actual command
  VALIDATE = "VALIDATE"        -- Validate command succeeded with timeout
}


-- Helper: Create atomic operations triplet for a command
local function createOperationTriplet(command)
  -- Generate unique ID for this command instance
  local command_id = hs.host.uuid()

  return {
    {
      type = OPERATION_TYPES.PRE_CHECK,
      command = command,
      command_id = command_id
    },
    {
      type = OPERATION_TYPES.EXECUTE,
      command = command,
      command_id = command_id
    },
    {
      type = OPERATION_TYPES.VALIDATE,
      command = command,
      command_id = command_id
    }
  }
end


-- === PURE FUNCTIONAL TAIL RECURSION ARCHITECTURE ===

-- Pure functional failure strategy: 3 retries then abort (synchronous queue modifier)
local function default_failure_strategy(failed_command, failure_context, queue, context)
  -- Initialize retry count if not present
  if not failed_command.retry_count then failed_command.retry_count = 0 end
  failed_command.retry_count = failed_command.retry_count + 1
  
  local max_retries = 3
  local failure_desc = string.format("%s %s", failure_context.operation_type, failed_command.type)
  
  if failed_command.retry_count < max_retries then
    logger.w(string.format("Command failed: %s (%s) - retry %d/%d", 
      failure_desc, failure_context.failure_reason, failed_command.retry_count, max_retries))
    
    -- Clear stability state for fresh retry validation
    local desktop_state = require('desktop_state')
    desktop_state._window_stability_state = {}
    
    -- Re-insert command at front of queue for retry
    table.insert(queue, 1, failed_command)
    return queue -- Return modified queue for continued processing
  else
    logger.e(string.format("Command failed after %d attempts: %s (%s) - aborting queue", 
      max_retries, failure_desc, failure_context.failure_reason))
    
    -- Signal failure via callback
    if context.callback then
      context.callback(false, "Command failed after retries: " .. failed_command.type)
    end
    return nil -- Signal abort
  end
end

-- Pure functional tail recursion processor
local function processNextOperation(queue, context)
  -- Stop any existing timer
  if context.current_timer then
    context.current_timer:stop()
    context.current_timer = nil
  end
  
  -- Check if queue is empty (success case)
  if #queue == 0 then
    logger.i("processNextOperation: queue completed successfully")
    if context.callback then 
      context.callback(true, "Queue processing completed")
    end
    return
  end
  
  -- Get next operation/command
  local item = queue[1]
  
  -- If next item is a Command, convert to Operations and shift
  if item.type and COMMAND_TYPES[item.type] and not item.command then  -- It's a Command (not an Operation)
    logger.d(string.format('processNextOperation: converting command %s to operations', item.type))
    table.remove(queue, 1)  -- Remove Command
    local triplet = createOperationTriplet(item)  -- Convert to Operations
    -- Insert Operations at front of queue
    for i = #triplet, 1, -1 do
      table.insert(queue, 1, triplet[i])
    end
    return processNextOperation(queue, context)  -- Continue tail recursion
  end
  
  -- Handle as Operation
  local operation = item
  local cmd = operation.command
  local cmd_def = COMMAND_TYPES[cmd.type]
  
  if not cmd_def then
    logger.e("processNextOperation: Unknown command type: " .. tostring(cmd.type))
    if context.callback then
      context.callback(false, "Unknown command type: " .. tostring(cmd.type))
    end
    return
  end
  
  logger.d(string.format('processNextOperation: %s %s', operation.type, cmd.type))
  
  if operation.type == OPERATION_TYPES.PRE_CHECK then
    local pre_result = cmd_def.pre_check(cmd)
    
    if pre_result == COMMAND_RESULT.PASS then
      -- Command already satisfied, remove all operations with same command_id
      logger.d(string.format('processNextOperation: %s already satisfied, skipping entire command', cmd.type))
      local command_id = operation.command_id
      
      -- Remove all operations with this command_id
      local i = 1
      while i <= #queue do
        if queue[i].command_id == command_id then
          table.remove(queue, i)
        else
          i = i + 1
        end
      end
      processNextOperation(queue, context) -- Continue tail recursion
      
    elseif pre_result == COMMAND_RESULT.FAIL then
      logger.e(string.format('processNextOperation: %s pre-check failed', cmd.type))
      table.remove(queue, 1) -- Remove failed operation
      
      local failure_context = {
        operation_type = "PRE_CHECK",
        failure_reason = "pre_check_failed",
        attempts = 1,
        error_details = { command_type = cmd.type }
      }
      
      local new_queue = context.failure_strategy(cmd, failure_context, queue, context)
      if new_queue then
        processNextOperation(new_queue, context) -- Continue with modified queue
      end
      
    elseif not pre_result then
      -- Prerequisites needed - inject them
      local prereqs = cmd_def.prerequisite_achiever(cmd)
      
      if #prereqs > 0 then
        logger.d(string.format('processNextOperation: %s injecting %d prerequisite commands', cmd.type, #prereqs))
        
        -- Insert prerequisite commands at front of queue
        for i = #prereqs, 1, -1 do
          table.insert(queue, 1, prereqs[i])
        end
        
        processNextOperation(queue, context) -- Continue tail recursion
      else
        -- No prerequisites but pre-check failed - this is ready to execute
        table.remove(queue, 1) -- Remove PRE_CHECK
        processNextOperation(queue, context) -- Continue tail recursion
      end
    else
      -- Pre-check passed - ready to execute
      table.remove(queue, 1) -- Remove PRE_CHECK
      processNextOperation(queue, context) -- Continue tail recursion
    end
    
  elseif operation.type == OPERATION_TYPES.EXECUTE then
    local exec_success = cmd_def.execute(cmd)
    
    if exec_success then
      logger.d(string.format('processNextOperation: %s execute succeeded', cmd.type))
      table.remove(queue, 1) -- Remove EXECUTE
      processNextOperation(queue, context) -- Continue tail recursion
    else
      logger.e(string.format('processNextOperation: %s execute failed', cmd.type))
      table.remove(queue, 1) -- Remove failed operation
      
      local failure_context = {
        operation_type = "EXECUTE",
        failure_reason = "execute_failed",
        attempts = 1,
        error_details = { command_type = cmd.type }
      }
      
      local new_queue = context.failure_strategy(cmd, failure_context, queue, context)
      if new_queue then
        processNextOperation(new_queue, context) -- Continue with modified queue
      end
    end
    
  elseif operation.type == OPERATION_TYPES.VALIDATE then
    logger.d(string.format('processNextOperation: %s starting validation', cmd.type))
    
    -- Set up validation polling
    local attempts = 0
    local timeout = cmd_def.post_check_timeout
    if type(timeout) == "function" then
      timeout = timeout(cmd)
    end
    local max_attempts = timeout / 0.05 -- 50ms polls
    
    local last_logged_result = nil
    context.current_timer = hs.timer.new(0.05, function()
      attempts = attempts + 1
      local post_check_result = cmd_def.post_check(cmd)

      if post_check_result then
        context.current_timer:stop()
        context.current_timer = nil
        logger.d(string.format('processNextOperation: %s validation succeeded after %dms', cmd.type, attempts * 50))

        table.remove(queue, 1) -- Remove VALIDATE
        processNextOperation(queue, context) -- Continue tail recursion

      elseif attempts >= max_attempts then
        context.current_timer:stop()
        context.current_timer = nil
        logger.w(string.format('processNextOperation: %s validation timeout after %dms', cmd.type, attempts * 50))

        table.remove(queue, 1) -- Remove failed operation
        local failure_context = {
          operation_type = "VALIDATE",
          failure_reason = "timeout",
          attempts = attempts,
          error_details = { 
            command_type = cmd.type,
            timeout_ms = attempts * 50,
            max_timeout_ms = max_attempts * 50
          }
        }
        
        local new_queue = context.failure_strategy(cmd, failure_context, queue, context)
        if new_queue then
          processNextOperation(new_queue, context) -- Continue with modified queue
        end
      else
        -- Only log validation state changes, not every poll
        if post_check_result ~= last_logged_result then
          logger.d(string.format('processNextOperation: %s validation state changed to %s (attempt %d)', 
            cmd.type, tostring(post_check_result), attempts))
          last_logged_result = post_check_result
        end
      end
    end)

    context.current_timer:start()
  end
end

-- New pure functional entry point
function M:executeCommandQueue(commands, callback, failure_strategy)
  if #commands == 0 then
    logger.i("executeCommandQueue: empty command queue")
    if callback then callback(true, "Empty command queue") end
    return true
  end

  -- Clear window stability state for fresh validation
  desktop_state._window_stability_state = {}

  -- Create functional queue (copy of commands)
  local queue = {}
  for _, command in ipairs(commands) do
    table.insert(queue, command)
  end

  -- Create processing context
  local context = {
    callback = callback,
    failure_strategy = failure_strategy or default_failure_strategy,
    current_timer = nil
  }

  logger.i(string.format("executeCommandQueue: starting pure functional processing of %d commands", #queue))

  -- Start pure functional tail recursion
  processNextOperation(queue, context)

  return true
end


-- Level 3: Core orchestrator - determines strategy and composes command queue
function M:performSpaceMove(target_space_number, return_to_spaces_for_displays, win)
  logger.i(string.format('performSpaceMove to space %d, return_to_spaces=%s',
           target_space_number, return_to_spaces_for_displays and "yes" or "no"))

  -- Validate window
  local valid, err = desktop_state.isMoveableWindow(win)
  if not valid then
    return false, err
  end

  -- Find target space and display
  local target_space_id, target_display, lookup_err = findSpaceIdAndDisplayId(target_space_number)
  if not target_space_id then
    return false, lookup_err
  end

  -- Compose command queue based on move strategy
  local commands = {}

  -- Determine current window's display and add appropriate commands
  local win_screen = win:screen()
  local same_display = win_screen:id() == target_display:id()

  if not same_display then
    -- Need to move to other display first
    table.insert(commands, {
      type = "MOVE_WINDOW_TO_DISPLAY",
      window = win,
      target_display = target_display
    })
  end

  -- Move window to target space
  table.insert(commands, {
    type = "MOVE_WINDOW_TO_SPACE",
    window = win,
    target_space_number = target_space_number,
    target_space_id = target_space_id
  })

  -- Add return commands if requested
  if return_to_spaces_for_displays then
    logger.d(string.format('Adding return commands for spaces: %s', hs.inspect(return_to_spaces_for_displays)))

    for display_id, space_number in pairs(return_to_spaces_for_displays) do
      local display = hs.screen.find(display_id)
      if display then
        logger.d(string.format('Adding return command for display %s to space %d', display:name(), space_number))
        table.insert(commands, {
          type = "JUMP_TO_SPACE",
          target_space_number = space_number,
          target_display = display
        })
      end
    end
  end

  -- Execute the command queue
  return self:executeCommandQueue(commands, nil)
end


-- Level 2: Window commands - nudge to adjacent space on same display
function M:nudgeWindow(direction, should_return, win)
  logger.i(string.format('nudgeWindow %s, should_return=%s', direction, tostring(should_return)))

  -- Calculate target space number from direction
  local current_space_number = desktop_state.getCurrentSpaceNumber()
  if not current_space_number then
    logger.e('Could not determine current space number')
    return false, "Could not determine current space"
  end

  local screen = win:screen()
  local target_space_number, err = desktop_state.getAdjacentSpaceNumber(current_space_number, direction, screen)
  if not target_space_number then
    logger.e('Could not find adjacent space: ' .. (err or 'unknown error'))
    return false, err or "Could not find adjacent space"
  end

  -- Convert should_return to return_to_spaces_for_displays
  local return_to_spaces_for_displays = nil
  if should_return then
    local current_spaces = desktop_state.getCurrentSpaceNumbers()
    return_to_spaces_for_displays = current_spaces.spaces
    logger.d(string.format('Created return_to_spaces_for_displays: %s', hs.inspect(return_to_spaces_for_displays)))
  end

  -- Delegate to performSpaceMove
  return self:performSpaceMove(target_space_number, return_to_spaces_for_displays, win)
end

function M:nudgeFrontmostWindow(direction, should_return)
  local win = desktop_state.getFrontmostWindow()
  if win then
    self:nudgeWindow(direction, should_return, win)
  end
end

function M:moveFrontmostWindow(space_number, should_return)
  local win = desktop_state.getFrontmostWindow()
  if win then
    self:moveWindow(space_number, should_return, win)
  end
end

-- Level 2: Window commands - move to specific space
function M:moveWindow(space_number, should_return, win)
  logger.i(string.format('moveWindow to space %d, should_return=%s', space_number, tostring(should_return)))

  -- Convert should_return to return_to_spaces_for_displays
  local return_to_spaces_for_displays = nil
  if should_return then
    local current_spaces = desktop_state.getCurrentSpaceNumbers()
    return_to_spaces_for_displays = current_spaces.spaces
    logger.d(string.format('Created return_to_spaces_for_displays: %s', hs.inspect(return_to_spaces_for_displays)))
  end

  -- Delegate to performSpaceMove
  return self:performSpaceMove(space_number, return_to_spaces_for_displays, win)
end

function M:nudgeOrMove(direction)
  logger.d(string.format('nudgeOrMove: direction=%s', direction))
  if not self.double_tap_timer then
    -- If called once, move and stay
    self.double_tap_timer = hs.timer.doAfter(TIMING.DOUBLE_TAP_WINDOW,
      function()
        self.double_tap_timer = nil
        self:nudgeFrontmostWindow(direction, false)
      end)
  else
    -- If called twice, move but return to original space
    self.double_tap_timer:stop()
    self.double_tap_timer = nil
    self:nudgeFrontmostWindow(direction, true)
  end
end

function M:moveToSpaceOrReturn(space_number)
  logger.d(string.format('moveToSpaceOrReturn: space_number=%d', space_number))
  if not self.space_double_tap_timer then
    -- If called once, move and stay
    self.space_double_tap_timer = hs.timer.doAfter(TIMING.DOUBLE_TAP_WINDOW,
      function()
        self.space_double_tap_timer = nil
        self:moveFrontmostWindow(space_number, false)
      end)
  else
    -- If called twice, move but return to original space
    self.space_double_tap_timer:stop()
    self.space_double_tap_timer = nil
    self:moveFrontmostWindow(space_number, true)
  end
end

-- Public API: Execute a list of commands using the command queue architecture
function M:executeCommands(commands, callback)
  logger.i(string.format('executeCommands: received %d commands', #commands))
  return self:executeCommandQueue(commands, callback)
end

function M:bindHotkeys(mapping)
  self.hotkeys.right = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Right",
    mapping.right[1], mapping.right[2], function() self:nudgeOrMove("right") end)
  self.hotkeys.left  = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Left",
    mapping.left[1], mapping.left[2],  function() self:nudgeOrMove("left") end)

  -- Move window to specific space (single tap = follow, double tap = return)
  if mapping.toSpace then
    for i = 1, 10 do
      local key = desktop_state.spaceNumberToKey(i)
      self.hotkeys["toSpace" .. i] = spoon.CaptureHotkeys:bind("WindowSpacesToSpace", "Space " .. i .. " (Double-tap to return)",
        mapping.toSpace[1], key, function()
          self:moveToSpaceOrReturn(i)
        end)
    end
  end

  return self
end

-- Initialize the module with configuration and bind hotkeys
function M:start(config)
  config = config or {}

  -- Set space jump modifiers from config or use default
  self._config.space_jump_modifiers = config.space_jump_modifiers or DEFAULT_SPACE_JUMP_MODIFIERS

  logger.i(string.format("Move spaces initialized with modifiers: %s",
                        table.concat(self._config.space_jump_modifiers, "+")))

  -- Bind hotkeys if provided
  if config.hotkeys then
    self:bindHotkeys(config.hotkeys)
  end

  return self
end

return M
