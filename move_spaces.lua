-- Move windows between spaces

-- luacheck: globals hs spoon

local M = { hotkeys = {}, _config = {} }

-- Configuration constants
-- Default modifier keys for space-switching keyboard shortcuts sent to macOS
local DEFAULT_SPACE_JUMP_MODIFIERS = {"ctrl"}

-- Timing constants (in microseconds)
local TIMING = {
  WINDOW_FOCUS_WAIT = 200000,      -- 0.2 seconds
  DISPLAY_MOVE_WAIT = 200000,      -- 0.2 seconds
  SPACE_MOVE_TIMEOUT = 200000,     -- 0.2 seconds (reduced from 2.0s)
  ADJACENT_MOVE_TIMEOUT = 50000,   -- 0.05 seconds
  RETURN_DELAY = 100000,           -- 0.1 seconds
  DOUBLE_TAP_WINDOW = 250000,      -- 0.25 seconds
}

M._logger = hs.logger.new("Move spaces", 'debug')
local logger = M._logger
logger.setLogLevel('debug')
logger.i("Loading Move spaces tools")


-- # Usage
-- local move_spaces = require 'move_spaces'
--
-- -- Initialize with configuration and bind hotkeys
-- move_spaces:start({
--   space_jump_modifiers = {"ctrl"},  -- macOS space switching modifiers
--   hotkeys = {
--     left  = {{"⌘", "⌥", "⌃", "⇧"}, "h"},  -- double-tap to return
--     right = {{"⌘", "⌥", "⌃", "⇧"}, "l"},  -- double-tap to return
--     toSpace = {{"⌘", "⌥", "⌃", "⇧"}},     -- double-tap to return
--   }
-- })
--
-- # Architecture Note
-- Due to macOS limitations, window movement between spaces requires simulating
-- keyboard shortcuts and mouse events. The space_jump_modifiers config parameter
-- specifies which modifier keys to use when sending the space-switching shortcut
-- to macOS (e.g., {"ctrl"} for ctrl+number, or {"ctrl", "shift"} for ctrl+shift+number).
--
-- # Public API
-- move_spaces:moveWindow(space_number, should_return, win)          -- Move window to specific space
-- move_spaces:nudgeWindow(direction, should_return, win)            -- Move window to adjacent space
-- move_spaces:nudgeOrMove(direction)                                -- Double-tap behavior

local spaces = require "hs.spaces" -- https://github.com/asmagill/hs._asm.spaces

-- Get desktop_space_numbers module for space translation helpers
local desktop_space_numbers = require('desktop_space_numbers')

-- Helper: check if window is moveable
local function isMoveableWindow(win)
  if not win then
    logger.e('Window is not suitable for moving: win is nil')
    return false, "Window is not moveable"
  elseif not win:isStandard() then
    logger.e('Window is not suitable for moving: not standard')
    return false, "Window is not moveable"
  elseif win:isFullScreen() then
    logger.e('Window is not suitable for moving: is fullscreen')
    return false, "Window is not moveable"
  end
  return true, nil
end

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

  logger.d(string.format('Found target space: ID=%s, number=%d, display=%s',
           tostring(target_space_id), target_space_number, target_display:name()))

  return target_space_id, target_display, nil
end

-- Helper: convert space number to key (space 10 uses "0")
local function spaceNumberToKey(space_number)
  return space_number == 10 and "0" or tostring(space_number)
end


-- === BASIC COMMANDS ===
-- These are the fundamental state-changing operations

-- Command: Focus a specific window (may trigger space jump if window not on active space)
local function commandFocusWindow(win)
  logger.d(string.format('Command: Focus window %s', win:title():len() > 30 and (win:title():sub(1, 30) .. "...") or win:title()))
  win:focus()
  return true
end

-- Command: Move window to a different display (to the active space on that display)
local function commandMoveWindowToDisplay(target_display, win)
  local win_screen = win:screen()
  if win_screen:id() == target_display:id() then
    return true -- Already on correct display
  end

  logger.d(string.format('Command: Move window to display %s', target_display:name()))

  -- Use WindowScreenLeftAndRight spoon to move between displays
  local target_is_left = target_display:frame().x < win_screen:frame().x

  -- Focus the window first
  win:focus()

  -- Move to target display using WindowScreenLeftAndRight public methods
  if target_is_left then
    spoon.WindowScreenLeftAndRight:moveCurrentWindowToScreen("left")
  else
    spoon.WindowScreenLeftAndRight:moveCurrentWindowToScreen("right")
  end

  return true
end

-- Command: Move window to specific space on same display using titlebar drag + keystroke
local function commandMoveWindowToSpace(target_space_number, win)
  local config = M._config
  local space_jump_modifiers = config.space_jump_modifiers or DEFAULT_SPACE_JUMP_MODIFIERS

  logger.d(string.format('Command: Move window to space %d', target_space_number))

  -- Get zoom button location and adjust slightly for safety
  local zoomPoint = hs.geometry(win:zoomButtonRect())
  local clickPoint = zoomPoint:move({-1,-1}).topleft

  -- Save mouse position to restore later
  local currentCursor = hs.mouse.getRelativePosition()

  -- Click and hold the titlebar
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, clickPoint):post()

  -- Jump directly to target space using configured shortcut
  local key = spaceNumberToKey(target_space_number)
  logger.d(string.format('Pressing %s+%s to jump to space %d', table.concat(space_jump_modifiers, "+"), key, target_space_number))
  hs.eventtap.keyStroke(space_jump_modifiers, key, 0)

  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, clickPoint):post()
  hs.mouse.setRelativePosition(currentCursor)

  return true
end

-- Command: Jump to specific space (changes active space)
local function commandJumpToSpace(target_space_number)
  local config = M._config
  local space_jump_modifiers = config.space_jump_modifiers or DEFAULT_SPACE_JUMP_MODIFIERS

  logger.d(string.format('Command: Jump to space %d', target_space_number))

  local key = spaceNumberToKey(target_space_number)
  logger.d(string.format('Pressing %s+%s to jump to space %d', table.concat(space_jump_modifiers, "+"), key, target_space_number))
  hs.eventtap.keyStroke(space_jump_modifiers, key, 0)

  return true
end

-- === COMMAND QUEUE ARCHITECTURE ===
-- Timing-aware command execution with state checking and retry logic

-- Command definitions with state checkers and executors
local COMMAND_TYPES = {
  FOCUS_WINDOW = {
    check = function(cmd)
      local frontmost = hs.window.frontmostWindow()
      return frontmost and frontmost:id() == cmd.window:id()
    end,
    execute = function(cmd)
      return commandFocusWindow(cmd.window)
    end,
    timeout = TIMING.WINDOW_FOCUS_WAIT
  },

  MOVE_WINDOW_TO_DISPLAY = {
    check = function(cmd)
      return cmd.window:screen():id() == cmd.target_display:id()
    end,
    execute = function(cmd)
      return commandMoveWindowToDisplay(cmd.target_display, cmd.window)
    end,
    timeout = TIMING.DISPLAY_MOVE_WAIT
  },

  MOVE_WINDOW_TO_SPACE = {
    check = function(cmd)
      -- Check if window is on the target space
      local window_space_number = desktop_space_numbers.getWindowSpaceNumber(cmd.window)
      return window_space_number == cmd.target_space_number
    end,
    execute = function(cmd)
      return commandMoveWindowToSpace(cmd.target_space_number, cmd.window)
    end,
    timeout = TIMING.SPACE_MOVE_TIMEOUT
  },

  JUMP_TO_SPACE = {
    check = function(cmd)
      -- Check if the specific display is on the target space
      local current_spaces = desktop_space_numbers.getCurrentSpaceNumbers()
      local display_current_space = current_spaces.spaces[cmd.target_display:id()]
      return display_current_space == cmd.target_space_number
    end,
    execute = function(cmd)
      return commandJumpToSpace(cmd.target_space_number)
    end,
    timeout = TIMING.SPACE_MOVE_TIMEOUT
  }
}

-- Command queue processor with timing and retry logic
function M:executeCommandQueue(commands, attempts_remaining)
  attempts_remaining = attempts_remaining or 10

  if #commands == 0 then
    logger.i("Command queue completed successfully")
    return true
  end

  if attempts_remaining <= 0 then
    logger.e("Command queue failed - too many attempts")
    return false, "Command execution timeout"
  end

  local cmd = commands[1]
  local cmd_def = COMMAND_TYPES[cmd.type]

  if not cmd_def then
    logger.e("Unknown command type: " .. tostring(cmd.type))
    return false, "Unknown command type"
  end

  -- Check if desired state is already achieved
  if cmd_def.check(cmd) then
    logger.d("Command " .. cmd.type .. " already satisfied, skipping")
    table.remove(commands, 1)
    return self:executeCommandQueue(commands, attempts_remaining)
  end

  -- Execute the command
  logger.d("Executing command: " .. cmd.type)
  local success = cmd_def.execute(cmd)

  if not success then
    logger.e("Command execution failed: " .. cmd.type)
    return false, "Command execution failed"
  end

  -- Schedule retry after timeout
  hs.timer.doAfter(cmd_def.timeout / 1000000, function()
    self:executeCommandQueue(commands, attempts_remaining - 1)
  end)

  return true
end


-- Level 3: Core orchestrator - determines strategy and composes command queue
function M:performSpaceMove(target_space_number, return_to_spaces_for_displays, win)
  logger.i(string.format('performSpaceMove to space %d, return_to_spaces=%s',
           target_space_number, return_to_spaces_for_displays and "yes" or "no"))

  -- Validate window
  local valid, err = isMoveableWindow(win)
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

  -- Always focus window first
  table.insert(commands, {
    type = "FOCUS_WINDOW",
    window = win
  })

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
  return self:executeCommandQueue(commands)
end


-- Level 2: Window commands - nudge to adjacent space on same display
function M:nudgeWindow(direction, should_return, win)
  logger.i(string.format('nudgeWindow %s, should_return=%s', direction, tostring(should_return)))

  -- Calculate target space number from direction
  local current_space_number = desktop_space_numbers.getCurrentSpaceNumber()
  if not current_space_number then
    logger.e('Could not determine current space number')
    return false, "Could not determine current space"
  end

  local screen = win:screen()
  local uuid = screen:getUUID()

  -- Get list of user spaces for this screen
  local userSpaces = nil
  for k, v in pairs(spaces.allSpaces()) do
    if k == uuid then
      userSpaces = v
      break
    end
  end

  if not userSpaces then
    logger.e('No user spaces found for current display')
    return false, "No user spaces found"
  end

  -- Filter out non-user spaces
  for i = #userSpaces, 1, -1 do
    if spaces.spaceType(userSpaces[i]) ~= "user" then
      table.remove(userSpaces, i)
    end
  end

  -- Find current space in list
  local current_space_id = desktop_space_numbers.getSpaceId(current_space_number)
  local current_index = nil
  for i, space_id in ipairs(userSpaces) do
    if space_id == current_space_id then
      current_index = i
      break
    end
  end

  if not current_index then
    logger.e('Could not find current space in user spaces list')
    return false, "Could not locate current space"
  end

  -- Calculate target index
  local target_index
  if direction == "right" then
    target_index = current_index + 1
  elseif direction == "left" then
    target_index = current_index - 1
  else
    logger.e('Invalid direction: ' .. tostring(direction))
    return false, "Invalid direction"
  end

  -- Check if target is within bounds
  if target_index < 1 or target_index > #userSpaces then
    logger.i('At edge of spaces, cannot move further')
    return false, "No adjacent space in that direction"
  end

  -- Get target space number
  local target_space_id = userSpaces[target_index]
  local target_space_number = desktop_space_numbers.getSpaceNumber(target_space_id)
  if not target_space_number then
    logger.e('Could not determine target space number')
    return false, "Could not determine target space number"
  end

  -- Convert should_return to return_to_spaces_for_displays
  local return_to_spaces_for_displays = nil
  if should_return then
    local current_spaces = desktop_space_numbers.getCurrentSpaceNumbers()
    return_to_spaces_for_displays = current_spaces.spaces
    logger.d(string.format('Created return_to_spaces_for_displays: %s', hs.inspect(return_to_spaces_for_displays)))
  end

  -- Delegate to performSpaceMove
  return self:performSpaceMove(target_space_number, return_to_spaces_for_displays, win)
end

function M:nudgeFrontmostWindow(direction, should_return)
  local win = hs.window.frontmostWindow()
  if win then
    self:nudgeWindow(direction, should_return, win)
  end
end

function M:moveFrontmostWindow(space_number, should_return)
  local win = hs.window.frontmostWindow()
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
    local current_spaces = desktop_space_numbers.getCurrentSpaceNumbers()
    return_to_spaces_for_displays = current_spaces.spaces
    logger.d(string.format('Created return_to_spaces_for_displays: %s', hs.inspect(return_to_spaces_for_displays)))
  end

  -- Delegate to performSpaceMove
  return self:performSpaceMove(space_number, return_to_spaces_for_displays, win)
end

function M:nudgeOrMove(direction)
  if not self.double_tap_timer then
    -- If called once, move and stay
    self.double_tap_timer = hs.timer.doAfter(TIMING.DOUBLE_TAP_WINDOW / 1000000,
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
  if not self.space_double_tap_timer then
    -- If called once, move and stay
    self.space_double_tap_timer = hs.timer.doAfter(TIMING.DOUBLE_TAP_WINDOW / 1000000,
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

function M:bindHotkeys(mapping)
  self.hotkeys.right = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Right",
    mapping.right[1], mapping.right[2], function() self:nudgeOrMove("right") end)
  self.hotkeys.left  = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Left",
    mapping.left[1], mapping.left[2],  function() self:nudgeOrMove("left") end)

  -- Move window to specific space (single tap = follow, double tap = return)
  if mapping.toSpace then
    for i = 1, 10 do
      local key = i == 10 and "0" or tostring(i)
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
