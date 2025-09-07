-- Stay replacement: Keep App windows in their places

-- luacheck: globals hs

local hs_geometry = hs.geometry
local fun = require 'fun'
local desktop_state = require('desktop_state')
require('utilities.table')

local M = { _config = {} }

-- Get configuration constants including timing
local consts = require('configConsts')
local TIMING = consts.timing

-- Window behavior constants
local HS_DRAWING_WINDOW_BEHAVIOURS = {
  canJoinAllSpaces = 1,
}

local logger = hs.logger.new('Stay')
M._logger = logger
logger.setLogLevel('debug')
logger.i('Loading Stay')
hs.window.filter.setLogLevel(1)  -- GLOBAL!! wfilter is very noisy

M.window_layouts = {} -- see bottom of file
M.window_layouts_enabled = false

local function alert(message)
  local log_level = logger.getLogLevel()
  logger.setLogLevel('info')
  -- hs.alert.closeAll()
  logger.i(message)
  if not M.starting then
    hs.alert.show('Stay: '.. message)
  end
  logger.setLogLevel(log_level)
end

M.watchable = hs.watchable.new('stay')
function M.activeLayoutChangeCallback(_, _, _, _, new)
  alert('I would have been storing or restoring window positions now (active layouts: '..new..')')
end
M.watchable_watcher = hs.watchable.watch('stay.activeLayouts', M.activeLayoutChangeCallback)

function M:report_frontmost_window()  --luacheck: no self
  local window = desktop_state.getFocusedWindow()

  local filter_string
  if window:subrole() == 'AXStandardWindow' then
    filter_string = string.format("'%s'", window:application():name())
  else
    filter_string = string.format("{['%s']={allowRoles='%s'}}", window:application():name(), window:subrole())
  end

  local rect = window:frame()
  local rect_string = string.format('[%.0f,%.0f>%.0f,%.0f]',
                                    rect.x1,rect.y1,rect.x2,rect.y2)

  local unit_rect = window:screen():toUnitRect(rect)
  local unit_rect_string = string.format('[%.0f,%.0f>%.0f,%.0f]',
                                         unit_rect.x1*100,unit_rect.y1*100,unit_rect.x2*100,unit_rect.y2*100)
  local screen_position_string = string.format('%i,%i', window:screen():position())

  local action_string, abs_action_string
  if unit_rect_string == '[0,0>100,100]' then
    action_string = string.format("'maximize 1 oldest %s'", screen_position_string)
    abs_action_string = action_string
  else
    action_string = string.format("'move 1 oldest %s %s'", unit_rect_string, screen_position_string)
    abs_action_string = string.format("'move 1 oldest %s'", rect_string)
  end

  local layout_rule = string.format('{%s, %s}', filter_string, action_string)
  local abs_layout_rule = string.format('{%s, %s}', filter_string, abs_action_string)

  local res = 'Active layouts: '..self:activeLayouts():tostring()..'\n'..layout_rule..'\n'..abs_layout_rule
  hs.pasteboard.setContents(res)
  alert('Active window position in clipboard\n\n'..res..'\n\ntitle:'..window:title())
  return res
end

function M:report_screens()  --luacheck: no self
  local screens = fun.totable(
    fun.map(function(screen) return {name = screen:name(), id = screen:id()} end,
      hs.screen.allScreens()
    )
  )
  local screens_string = hs.inspect(screens)
  hs.pasteboard.setContents(screens_string)
  alert('Screens in clipboard\n'.. screens_string)
  local log_level = logger.getLogLevel()
  logger.setLogLevel('info')
  logger.i(screens_string)
  logger.setLogLevel(log_level)
  return screens
end

function M:toggle_window_layouts_enabled()
  if self.window_layouts_enabled then
    self:window_layouts_disable()
  else
    self:window_layouts_enable()
  end
  return self
end

function M:window_layouts_enable()
  if not self.window_layouts_enabled then
    for _,layout in pairs(self.window_layouts) do
      layout:start()
    end
    self.window_layouts_enabled = true
  end
  return self
end

function M:window_layouts_disable()
  if self.window_layouts_enabled then
    for _,layout in pairs(self.window_layouts) do layout:stop() end
    self.window_layouts_enabled = false
  end
  return self
end

local function toggle_window_layouts_enabled_descripton()
  if not M.window_layouts_enabled then
    return 'Start window layout engine'
  else
    return 'Pause window layout engine'
  end
end
local choices_list = {
  { text = 'Toggle layout engine',
    subText = toggle_window_layouts_enabled_descripton(),
    fn = function() M:toggle_window_layouts_enabled() end
  },
  { text = 'Screens',
    subText = 'Report screen details',
    fn = function() M:report_screens() end
  },
  { text = 'Report',
    subText = 'Report frontmost window position',
    fn = function() M:report_frontmost_window() end
  },
  { text = 'Report and open',
    subText = 'Report frontmost window position and open config',
    fn = function()
      M:report_frontmost_window()
      hs.execute('/usr/bin/open -a VimR ~/.hammerspoon/configConsts.lua')
    end
  },
  { text = 'Tidy windows between spaces',
    subText = 'Send windows to their target spaces',
    fn = function() M:tidy() end
  },
}
local function completionFn(choice)
  if choice then
    choices_list[choice.index].fn()
  end
end
local function choicesFn()
  local choices = {}
  for i, choice in ipairs(choices_list) do
    table.insert(choices, {
      text = choice.text,
      subText = choice.subText,
      index = i,
    })
  end
  return choices
end
M.chooser = hs.chooser.new(completionFn):
              choices(choicesFn):
              searchSubText(true)

-- Evaluate a matcher configuration against a window
function M.evaluate_matcher(matcher_config, win)
  for matcher_type, matcher_params in pairs(matcher_config) do
    if matcher_type == "window_title_matcher" then
      return win:title():match(matcher_params.pattern) and true or false

    -- Skip non-matcher keys like target_space, exceptions
    elseif matcher_type == "target_space" or matcher_type == "exceptions" then
      -- continue to next key
    else
      -- Unknown matcher type - for now, ignore (could error in strict mode)
      -- error("Unknown matcher type: " .. matcher_type)
    end
  end
  return false
end

-- Detect which profile a window belongs to based on target space rules
function M.detect_profile(win, target_space_rules)
  for _, rule in ipairs(target_space_rules) do
    if M.evaluate_matcher(rule, win) then
      return rule.name or "unnamed_rule"
    end
  end
  return nil
end

-- Determine what space a window should be in based on target space rules
function M.get_target_space_for_window(win, target_space_rules)
  for _, rule in ipairs(target_space_rules) do
    if M.evaluate_matcher(rule, win) then
      -- Check for exceptions
      if rule.exceptions then
        for _, exception in ipairs(rule.exceptions) do
          if M.evaluate_matcher(exception, win) then
            -- Exception matched, skip this rule
            goto continue
          end
        end
      end
      return rule.target_space
    end
    ::continue::
  end
  return nil
end

-- Get the current space ID for a window
function M.get_current_space_for_window(win)
  return desktop_state.get_current_space_for_window(win)
end

-- Check if a window is already in its correct "home" space
-- Returns TRUE if the window should NOT be moved (either no target or already correct)
-- Returns FALSE only if the window has a target and is NOT in the correct space
function M.is_window_home(win, target_space_rules)
  local target_space = M.get_target_space_for_window(win, target_space_rules)
  if not target_space then return true end -- No target space defined = don't move

  local current_space = M.get_current_space_for_window(win)
  if not current_space then return true end -- Can't determine current space = don't move

  -- Convert target space number to space ID using desktop_state
  local spaces_map = desktop_state.getSpacesMap()

  for space_id, space_info in pairs(spaces_map) do
    if space_info.spaceNumber == target_space and space_id == current_space then
      return true -- Already in correct space = don't move
    end
  end

  return false -- Has target but not in correct space = needs to move
end

-- Move window to specific space using move_spaces module with direct space jumping
function M.move_window_to_space(win, target_space_number, config)
  local move_spaces = require('move_spaces')
  -- Use moveWindow (without returning to original space)
  -- The move_spaces module will use its configured space_jump_modifiers
  return move_spaces:moveWindow(target_space_number, false, win)
end

-- Discovery phase for tidy: Enumerate all Chrome windows across all spaces
function M:build_tidy_discovery_commands()
  local profile_rules = self._config.target_space_rules or {}

  if not next(profile_rules) then
    M._logger.e("No target_space_rules found in configuration")
    return {}
  end

  -- Get Chrome application
  local chrome_app = hs.application.get("Google Chrome")
  if not chrome_app then
    M._logger.e("Google Chrome is not running")
    return {}
  end

  M._logger.i("Building Chrome window discovery commands...")

  -- Shared state for collecting discovered windows across all LAMBDA commands
  M._discovery_state = {
    all_chrome_windows = {},
    profile_rules = profile_rules,
    spaces_visited = 0
  }

  local commands = {}
  local spaces_map = desktop_state.getSpacesMap()

  -- Visit EVERY space on EVERY display
  for _, screen in ipairs(hs.screen.allScreens()) do
    M._logger.d(string.format("Scanning display: %s", screen:name()))

    local screen_spaces = desktop_state.getSpacesForScreen(screen)
    for _, space_id in ipairs(screen_spaces) do
      -- Skip non-user spaces (fullscreen, dashboard, etc)
      if desktop_state.getSpaceType(space_id) == "user" then
        -- Get space number for logging
        local space_number = nil
        for sid, sinfo in pairs(spaces_map) do
          if sid == space_id and sinfo.spaceNumber then
            space_number = sinfo.spaceNumber
            break
          end
        end

        if space_number then
          -- Jump to space command
          table.insert(commands, {
            type = "JUMP_TO_SPACE",
            target_space_number = space_number,
            target_display = screen
          })

          -- Collect Chrome windows on this space using LAMBDA command
          table.insert(commands, {
            type = "LAMBDA",
            description = string.format("Collect Chrome windows on space %d (%s)", space_number, screen:name()),
            space_id = space_id,
            space_number = space_number,
            screen = screen,
            execute_fn = function(cmd)
              M._discovery_state.spaces_visited = M._discovery_state.spaces_visited + 1
              M._logger.d(string.format("Collecting Chrome windows on space %d (%s)", cmd.space_number, cmd.screen:name()))

              -- Get all windows on current space
              local space_windows = desktop_state.getWindowsForSpace(cmd.space_id)
              local found_count = 0

              -- Filter for Chrome windows on this space
              for _, win_id in ipairs(space_windows) do
                local win = hs.window.get(win_id)
                if win and win:application() and win:application():name() == "Google Chrome" then
                  local valid, _ = desktop_state.isMoveableWindow(win)
                  if valid then
                    -- Check for duplicates
                    local already_found = false
                    for _, existing_win in ipairs(M._discovery_state.all_chrome_windows) do
                      if existing_win.window:id() == win:id() then
                        already_found = true
                        break
                      end
                    end

                    if not already_found then
                      -- Determine profile and target space
                      local profile = M.detect_profile(win, M._discovery_state.profile_rules)
                      local target_space = M.get_target_space_for_window(win, M._discovery_state.profile_rules)

                      -- Create window info entry
                      local window_info = {
                        window = win,
                        title = win:title(),
                        profile = profile,
                        target_space_number = target_space,
                        current_space_id = cmd.space_id,
                        current_space_number = cmd.space_number,
                        screen_name = cmd.screen:name()
                      }

                      table.insert(M._discovery_state.all_chrome_windows, window_info)
                      found_count = found_count + 1
                      M._logger.d(string.format("Found: %s [%s]",
                        win:title():sub(1, 40), profile or "no-profile"))
                    end
                  end
                end
              end

              M._logger.d(string.format("Space %d: found %d new Chrome windows", cmd.space_number, found_count))
              return true
            end,
            timeout = 2.0
          })
        end
      end
    end
  end


  return commands
end

-- Process discovery results and build todo list
function M:process_discovery_results()
  local all_chrome_windows = M._discovery_state.all_chrome_windows
  local spaces_visited = M._discovery_state.spaces_visited

  -- Build todo list
  local todo_list = {}
  local summary = {
    total_windows = #all_chrome_windows,
    needs_move = 0,
    already_home = 0,
    no_target = 0
  }

  for _, win_info in ipairs(all_chrome_windows) do
    if win_info.target_space_number and win_info.current_space_number then
      if win_info.current_space_number ~= win_info.target_space_number then
        win_info.needs_move = true
        table.insert(todo_list, win_info)
        summary.needs_move = summary.needs_move + 1
      else
        win_info.needs_move = false
        summary.already_home = summary.already_home + 1
      end
    else
      win_info.needs_move = false
      summary.no_target = summary.no_target + 1
    end
  end

  -- Log the todo list
  M._logger.i("=== DISCOVERY PHASE COMPLETE ===")
  M._logger.i(string.format("Visited %d spaces across %d displays",
                           spaces_visited, #hs.screen.allScreens()))
  M._logger.i(string.format("Found %d Chrome windows total", summary.total_windows))
  M._logger.i(string.format("  - %d need to move", summary.needs_move))
  M._logger.i(string.format("  - %d already in correct space", summary.already_home))
  M._logger.i(string.format("  - %d have no target space", summary.no_target))

  M._logger.i("=== TODO LIST ===")
  for i, win_info in ipairs(todo_list) do
    M._logger.i(string.format("%d. Move '%s' [%s] from space %s to %s on %s",
                             i,
                             win_info.title:sub(1, 40),
                             win_info.profile or "unknown",
                             win_info.current_space_number or "?",
                             win_info.target_space_number or "?",
                             win_info.screen_name))
  end

  return todo_list, summary
end

-- Floating window persistent alerts that survive space changes
-- Store window references in module for cleanup
M._tidy_windows = nil

-- Forward declaration
local updateTidyWindows

-- Create or reuse persistent floating windows on all displays
local function createTidyWindows(message)
  -- Reuse existing windows if they exist and are still valid
  if M._tidy_windows then
    local valid_windows = {}
    for _, webview in ipairs(M._tidy_windows) do
      if webview and webview:hswindow() then
        table.insert(valid_windows, webview)
      end
    end

    if #valid_windows == #hs.screen.allScreens() then
      M._logger.d("Reusing existing tidy progress windows")
      updateTidyWindows(valid_windows, message)
      return valid_windows
    else
      -- Some windows are gone, clean up and recreate
      M._logger.d("Some tidy windows missing, recreating all")
      closeTidyWindows(M._tidy_windows)
    end
  end

  local tidy_windows = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local screen_frame = screen:fullFrame()
    local window_width = 400
    local window_height = 100

    -- Position window in top-left corner of screen
    local window_frame = hs.geometry.rect(
      screen_frame.x + 20,
      screen_frame.y + 20,
      window_width,
      window_height
    )

    -- Create webview window
    local webview = hs.webview.new(window_frame)
      :windowTitle("Hammerspoon Tidy Progress")
      :closeOnEscape(false)
      :windowStyle({"utility", "HUD", "titled", "closable"})
      :level(hs.drawing.windowLevels.floating)
    
    -- Add canJoinAllSpaces behavior to existing behaviors
    webview:behavior(webview:behavior() + HS_DRAWING_WINDOW_BEHAVIOURS.canJoinAllSpaces)
    webview:html(string.format([[
        <html>
          <head>
            <style>
              body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 14px;
                background: rgba(0,0,0,0.8);
                color: white;
                margin: 0;
                padding: 20px;
                text-align: center;
                border-radius: 8px;
              }
              .title { font-weight: bold; margin-bottom: 10px; }
            </style>
          </head>
          <body>
            <div class="title">🔄 Chrome Window Tidy</div>
            <div id="status">%s</div>
          </body>
        </html>
      ]], message))
      :show()

    table.insert(tidy_windows, webview)
    M._logger.d(string.format("Created tidy progress window on %s", screen:name()))
  end

  M._tidy_windows = tidy_windows
  return tidy_windows
end

-- Update existing tidy windows with new message
updateTidyWindows = function(tidy_windows, message)
  if not tidy_windows then return end

  for _, webview in ipairs(tidy_windows) do
    if webview and webview:hswindow() then
      -- Update just the status div content - escape the string for JavaScript
      local escaped_message = message:gsub("'", "\\'"):gsub('"', '\\"'):gsub('\n', '\\n')
      webview:evaluateJavaScript(string.format(
        "document.getElementById('status').innerHTML = '%s';",
        escaped_message
      ))
    end
  end
end

-- Close all tidy windows and clear module reference
local function closeTidyWindows(tidy_windows)
  if not tidy_windows then return end

  for _, webview in ipairs(tidy_windows) do
    if webview then
      webview:delete()
    end
  end

  M._tidy_windows = nil
  M._logger.d("Closed all tidy progress windows")
end

-- Retry failure strategy: add failure_count metadata and push to end of queue for retry
-- If command fails twice, PASS it to continue processing remaining commands
local function retry_at_end_failure_strategy(failed_command, failure_context, queue, context)
  -- Initialize failure_count if not present
  if not failed_command.failure_count then
    failed_command.failure_count = 1

    M._logger.w(string.format("Command failed: %s %s (%s) - adding to end of queue for retry (attempt 1)",
      failure_context.operation_type, failed_command.type, failure_context.failure_reason))

    -- Push failed command to end of queue for retry
    table.insert(queue, failed_command)
    return queue -- Return modified queue for continued processing
  else
    -- Command has already been retried, PASS it and continue with remaining queue
    M._logger.w(string.format("Command failed after retry: %s %s (%s) - marking as PASS and continuing",
      failure_context.operation_type, failed_command.type, failure_context.failure_reason))

    -- Just return the remaining queue (skip the failed command)
    return queue
  end
end

-- Main function to tidy all Chrome windows by profile using move_spaces queue
function M:tidy()
  M._logger.i("Starting Chrome window tidy using move_spaces queue...")

  local move_spaces = require('move_spaces')
  local original_spaces = desktop_state.getCurrentSpaceNumbers()

  -- Create persistent floating windows on all displays
  local tidy_windows = createTidyWindows("Discovering windows...")

  -- PHASE 1: Build discovery commands to visit each space and collect Chrome windows
  local discovery_commands = self:build_tidy_discovery_commands()

  if #discovery_commands == 0 then
    M._logger.e("Failed to build discovery commands")
    closeTidyWindows(tidy_windows)
    alert("Failed to build discovery commands")
    return
  end

  M._logger.i(string.format("Built %d discovery commands", #discovery_commands))

  -- Execute discovery phase
  move_spaces:executeCommands(discovery_commands, function(success, message)
    if not success then
      M._logger.e("Discovery failed: " .. (message or "unknown error"))
      closeTidyWindows(tidy_windows)
      alert("Discovery failed: " .. (message or "unknown error"))
      return
    end

    M._logger.i("Discovery phase completed. Processing results...")
    updateTidyWindows(tidy_windows, "Processing results...")

    -- Process discovery results
    local todo_list, summary = M:process_discovery_results()

    -- Clean up discovery state
    M._discovery_state = nil

    -- If no windows need moving, we're done
    if summary.needs_move == 0 then
      M._logger.i(string.format("All %d Chrome windows are already in correct spaces!", summary.total_windows))
      closeTidyWindows(tidy_windows)
      alert(string.format("All %d Chrome windows are already in correct spaces!", summary.total_windows))
      return
    end

    M._logger.i(string.format("Found %d windows needing moves. Starting execution phase...", summary.needs_move))
    updateTidyWindows(tidy_windows, string.format("Moving %d windows...", summary.needs_move))

    -- PHASE 2: Build and execute move commands
    local move_commands = {}

    -- Build command list for all moves
    for _, win_info in ipairs(todo_list) do
      local target_space_id = desktop_state.getSpaceId(win_info.target_space_number)
      local target_display = desktop_state.getSpaceDisplay(target_space_id)

      if target_display then
        table.insert(move_commands, {
          type = "MOVE_WINDOW_TO_SPACE",
          window = win_info.window,
          target_space_number = win_info.target_space_number,
          target_space_id = target_space_id
        })
      else
        M._logger.e(string.format("Could not find display for space %d", win_info.target_space_number))
      end
    end

    -- Add commands to restore original display state
    for screen_id, space_number in pairs(original_spaces.spaces) do
      local screen = hs.screen.find(screen_id)
      if screen then
        table.insert(move_commands, {
          type = "JUMP_TO_SPACE",
          target_space_number = space_number,
          target_display = screen
        })
      end
    end

    M._logger.i(string.format("Built %d move commands (%d moves + %d display restores)",
                             #move_commands, #todo_list, table.length(original_spaces.spaces)))

    -- Execute move phase with retry failure strategy
    move_spaces:executeCommandQueue(move_commands, function(move_success, move_message)
      closeTidyWindows(tidy_windows)
      if move_success then
        M._logger.i("Tidy execution completed successfully")
        alert(string.format("✅ Successfully moved %d windows to their target spaces", #todo_list))
      else
        M._logger.e("Tidy execution failed: " .. (move_message or "unknown error"))
        alert("❌ Tidy execution failed: " .. (move_message or "unknown error"))
      end
    end, retry_at_end_failure_strategy)
  end)
end


-- Utility function to check if a layout is active (avoids decorating global hs.window.layout)
local function isLayoutActive(layout)
  if layout.screens then
    for hint, test in pairs(layout.screens) do
      local screen = hs.screen.find(hint)
      if screen then
        if type(test) == 'boolean' then
          if not test then return false end
        else
          local x, y = screen:position()
          local test_geometry = hs_geometry.new(test)
          -- Fixed logic: was "not x == test_geometry.x" which is always true
          if x ~= test_geometry.x or y ~= test_geometry.y then
            return false
          end
        end
      else
        if test then  -- truthy: true or hs.geometry
          return false
        end
      end
    end
  end
  return true
end

function M:activeLayouts()  -- :string
  local active_layouts = {}
  hs.fnutils.each(self.window_layouts, function(layout)
    if isLayoutActive(layout) then
      active_layouts[#active_layouts+1] = layout.logname
    end
  end)
  setmetatable(active_layouts, { __tostring = function(t) return table.concat(t, '|') end, })
  function active_layouts:tostring() return tostring(self) end  -- luacheck: no redefined
  return active_layouts
end


function M:toggle_or_choose()
  if not self.double_tap_timer then
    -- First call, set up for toggle
    hs.alert(toggle_window_layouts_enabled_descripton()..'; tap again for options.')
    self.double_tap_timer = hs.timer.doAfter(0.5, function()
      self.double_tap_timer = nil
      M:toggle_window_layouts_enabled()
    end)
  else
    -- Subsequent call, show the chooser
    hs.alert.closeAll()
    M.chooser:refreshChoicesCallback()
    self.double_tap_timer:stop()
    self.double_tap_timer = nil
    self.chooser:show()
  end
  return self
end


function M:start(config)
  config = config or {}

  -- Store configuration in M._config for consistency with move_spaces.lua pattern
  self._config = config

  -- Load window layouts from configuration
  if self._config.window_layouts then
    for layout_name, layout in pairs(self._config.window_layouts) do
      local window_layout = hs.window.layout.new(layout, layout_name)
      M.window_layouts[layout_name] = window_layout
      for _, rule in pairs(window_layout.rules) do
        rule.windowfilter:setOverrideFilter({visible=true})
      end
    end
  end

  self.starting = true
  self:window_layouts_enable()

  self.hotkey = self.hotkey or hs.hotkey.new({'⌘', '⌥', '⌃', '⇧'}, 's', function() M:toggle_or_choose() end)
  self.hotkey:enable()

  self.screenwatcher = hs.screen.watcher.new(function()
    self.watchable.active_layouts = self:activeLayouts():tostring()
  end):start()
  self.starting = nil
  return self
end
function M:stop()
  self:window_layouts_disable()
  if self.hotkey then self.hotkey:disable() end
  if self.screenwatcher then self.screenwatcher:stop() end
  return self
end


-- Window layouts are now loaded in M:start() from configuration

return M
