-- Stay replacement: Keep App windows in their places

-- luacheck: globals hs

-- Configuration constants
local DEFAULT_SPACE_JUMP_MODIFIERS = {"ctrl", "shift"}

local hs_geometry = hs.geometry
local fun = require 'fun'

local M = {}

-- Timing constants for window operations
local TIMING = {
  SPACE_CHANGE_WAIT = 300000,  -- 0.3 seconds
  WINDOW_FOCUS_WAIT = 200000,  -- 0.2 seconds
  SCREEN_ACTIVATION_WAIT = 200000,  -- 0.2 seconds
  MOVE_COMPLETION_WAIT = 1000000,  -- 1.0 second
}

local logger = hs.logger.new('Stay')
M._logger = logger
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
  local window = hs.application.frontmostApplication():focusedWindow()

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
  alert('Active window position in clipboard\n\n'..res)
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

-- Detect which profile a window belongs to based on profile rules
function M.detect_profile(win, profile_rules)
  for profile_name, profile_rule in pairs(profile_rules) do
    if M.evaluate_matcher(profile_rule, win) then
      return profile_name
    end
  end
  return nil
end

-- Determine what space a window should be in based on profile rules
function M.get_target_space_for_window(win, profile_rules)
  local profile = M.detect_profile(win, profile_rules)
  if not profile then return nil end

  local profile_rule = profile_rules[profile]
  if not profile_rule then return nil end

  return profile_rule.target_space
end

-- Get the current space ID for a window
function M.get_current_space_for_window(win)
  local spaces = require "hs.spaces"
  local win_spaces = spaces.windowSpaces(win)
  -- Return first space (windows can be in multiple spaces, but we'll use the first)
  return win_spaces and win_spaces[1] or nil
end

-- Check if a window is already in its correct "home" space
-- Returns TRUE if the window should NOT be moved (either no target or already correct)
-- Returns FALSE only if the window has a target and is NOT in the correct space
function M.is_window_home(win, profile_rules)
  local target_space = M.get_target_space_for_window(win, profile_rules)
  if not target_space then return true end -- No target space defined = don't move

  local current_space = M.get_current_space_for_window(win)
  if not current_space then return true end -- Can't determine current space = don't move

  -- Convert target space number to space ID using desktop_space_numbers
  local desktop_space_numbers = require('desktop_space_numbers')
  local spaces_map = desktop_space_numbers.spaces_map()

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
  -- Use moveWindowToSpace (without returning to original space)
  return move_spaces.moveWindowToSpace(win, target_space_number, config)
end

-- Manual testing function for real Chrome windows
function M:test_chrome_matchers()
  -- Use chrome_profile_rules from configuration
  local test_profile_rules = self.config.chrome_profile_rules or {}

  if not next(test_profile_rules) then
    alert("No chrome_profile_rules found in configuration")
    return
  end

  -- Get Chrome application
  local chrome_app = hs.application.get("Google Chrome")
  if not chrome_app then
    alert("Google Chrome is not running")
    return
  end

  -- Try multiple methods to find ALL Chrome windows
  local chrome_windows_all = chrome_app:allWindows()
  local chrome_windows_visible = chrome_app:visibleWindows()
  local chrome_filter = hs.window.filter.new("Google Chrome")
  local chrome_windows_filtered = chrome_filter:getWindows()

  -- Try hs.spaces approach with space switching to force window discovery
  local spaces = require "hs.spaces"
  local chrome_windows_spaces = {}
  local spaces_checked = 0
  local current_space = spaces.focusedSpace()

  alert("Starting comprehensive space scan... this will switch spaces briefly")

  for _, screen in ipairs(hs.screen.allScreens()) do
    local screen_spaces = spaces.spacesForScreen(screen)
    for _, space_id in ipairs(screen_spaces) do
      spaces_checked = spaces_checked + 1

      -- Briefly switch to each space to force window loading
      spaces.gotoSpace(space_id)
      hs.timer.usleep(100000) -- Wait 0.1 seconds

      -- Now try multiple approaches on this space
      local space_windows = spaces.windowsForSpace(space_id)
      local chrome_windows_this_space = chrome_app:allWindows()

      -- Combine both approaches
      local all_potential_windows = {}

      -- From space-specific query
      for _, win_id in ipairs(space_windows) do
        local win = hs.window.get(win_id)
        if win and win:application() and win:application():name() == "Google Chrome" then
          table.insert(all_potential_windows, win)
        end
      end

      -- From application query (now that we're in this space)
      for _, win in ipairs(chrome_windows_this_space) do
        if win:isStandard() and not win:isMinimized() then
          table.insert(all_potential_windows, win)
        end
      end

      -- Deduplicate and add to main list
      for _, win in ipairs(all_potential_windows) do
        local already_found = false
        for _, existing_win in ipairs(chrome_windows_spaces) do
          if existing_win:id() == win:id() then
            already_found = true
            break
          end
        end
        if not already_found then
          table.insert(chrome_windows_spaces, win)
        end
      end
    end
  end

  -- Return to original space
  spaces.gotoSpace(current_space)
  alert("Space scan complete")

  -- Use the method that finds the most windows
  local methods = {
    {name = "allWindows()", windows = chrome_windows_all},
    {name = "window.filter", windows = chrome_windows_filtered},
    {name = "spaces iteration", windows = chrome_windows_spaces}
  }

  local best_method = methods[1]
  for _, method in ipairs(methods) do
    if #method.windows > #best_method.windows then
      best_method = method
    end
  end

  local chrome_windows = best_method.windows
  local best_method_name = best_method.name

  -- Build comprehensive test report
  local report = {}

  -- Header with method comparison
  table.insert(report, "=== Chrome Window Detection Test Results ===")
  table.insert(report, string.format("allWindows(): %d windows", #chrome_windows_all))
  table.insert(report, string.format("visibleWindows(): %d windows", #chrome_windows_visible))
  table.insert(report, string.format("window.filter: %d windows", #chrome_windows_filtered))
  table.insert(report, string.format("spaces iteration: %d windows (checked %d spaces)", #chrome_windows_spaces, spaces_checked))
  table.insert(report, string.format("Using: %s (%d windows)", best_method_name, #chrome_windows))
  table.insert(report, "")

  -- Test each window
  local profile_counts = {personal = 0, bellroy = 0, miri = 0, none = 0}

  for i, win in ipairs(chrome_windows) do
    if win:isStandard() and not win:isMinimized() then
      local title = win:title()
      local detected_profile = M.detect_profile(win, test_profile_rules)

      table.insert(report, string.format("Window %d:", i))
      table.insert(report, string.format("  Title: %s", title:len() > 80 and (title:sub(1, 80) .. "...") or title))
      table.insert(report, string.format("  Profile: %s", detected_profile or "none"))

      -- Count profiles
      profile_counts[detected_profile or "none"] = profile_counts[detected_profile or "none"] + 1

      -- Test individual matchers for debugging
      for profile_name, profile_rule in pairs(test_profile_rules) do
        local matches = M.evaluate_matcher(profile_rule, win)
        if matches then
          table.insert(report, string.format("  ✅ Matches %s pattern", profile_name))
        end
      end
      table.insert(report, "")
    end
  end

  -- Summary
  table.insert(report, "=== Profile Detection Summary ===")
  table.insert(report, string.format("Personal: %d windows", profile_counts.personal))
  table.insert(report, string.format("Bellroy: %d windows", profile_counts.bellroy))
  table.insert(report, string.format("MIRI: %d windows", profile_counts.miri))
  table.insert(report, string.format("Unmatched: %d windows", profile_counts.none))

  local final_report = table.concat(report, "\n")

  -- Output to both console and clipboard
  print(final_report)
  hs.pasteboard.setContents(final_report)
  alert(string.format("Tested %d Chrome windows. Results in console and clipboard.", #chrome_windows))
end

-- Simple test to verify home detection logic
function M:test_home_detection()
  local profile_rules = self.config.chrome_profile_rules or {}

  if not next(profile_rules) then
    alert("No chrome_profile_rules found in configuration")
    return
  end

  local frontmost_app = hs.application.frontmostApplication()
  if not frontmost_app then
    alert("No frontmost application found")
    return
  end

  local frontmost_win = frontmost_app:focusedWindow()
  if not frontmost_win then
    alert("No focused window found")
    return
  end

  -- Test all the detection functions step by step
  local title = frontmost_win:title()
  local app_name = frontmost_app:name()
  local profile = M.detect_profile(frontmost_win, profile_rules)
  local target_space = M.get_target_space_for_window(frontmost_win, profile_rules)
  local current_space_id = M.get_current_space_for_window(frontmost_win)
  local is_home = M.is_window_home(frontmost_win, profile_rules)

  -- Convert space IDs to readable numbers
  local desktop_space_numbers = require('desktop_space_numbers')
  local spaces_map = desktop_space_numbers.spaces_map()
  local current_space_number = "unknown"
  local target_space_id = nil

  for space_id, space_info in pairs(spaces_map) do
    if space_id == current_space_id then
      current_space_number = space_info.spaceNumber
    end
    if space_info.spaceNumber == target_space and not target_space_id then
      target_space_id = space_id
    end
  end

  local report = {}
  table.insert(report, "=== HOME DETECTION LOGIC TEST ===")
  table.insert(report, string.format("App: %s", app_name))
  table.insert(report, string.format("Title: %s", title:len() > 60 and (title:sub(1, 60) .. "...") or title))
  table.insert(report, "")
  table.insert(report, "--- Step-by-step detection ---")
  table.insert(report, string.format("1. Profile detected: %s", profile or "none"))
  table.insert(report, string.format("2. Target space number: %s", target_space or "none"))
  table.insert(report, string.format("3. Target space ID: %s", target_space_id or "none"))
  table.insert(report, string.format("4. Current space ID: %s", current_space_id or "unknown"))
  table.insert(report, string.format("5. Current space number: %s", current_space_number))
  table.insert(report, string.format("6. Space ID match: %s", (target_space_id == current_space_id) and "YES" or "NO"))
  table.insert(report, "")
  table.insert(report, string.format("FINAL RESULT: is_window_home() = %s", is_home and "TRUE" or "FALSE"))

  -- Determine what the expected result should be
  local expected_home, expected_reason
  if not profile then
    expected_home = true
    expected_reason = "no profile detected = don't move"
  elseif not target_space then
    expected_home = true
    expected_reason = "no target space = don't move"
  elseif target_space_id == current_space_id then
    expected_home = true
    expected_reason = "already in correct space = don't move"
  else
    expected_home = false
    expected_reason = "has target but wrong space = needs move"
  end

  table.insert(report, string.format("EXPECTED: %s (%s)", expected_home and "TRUE" or "FALSE", expected_reason))

  if expected_home == is_home then
    table.insert(report, "✅ Home detection logic is CORRECT")
  else
    table.insert(report, "❌ Home detection logic is WRONG")
    table.insert(report, string.format("   Expected: %s, Got: %s", expected_home and "TRUE" or "FALSE", is_home and "TRUE" or "FALSE"))
  end

  local final_report = table.concat(report, "\n")
  print(final_report)
  hs.pasteboard.setContents(final_report)
  alert("Home detection test complete. Results in console and clipboard.")
end

-- Interactive test function for frontmost window
function M:test_frontmost_window()
  local profile_rules = self.config.chrome_profile_rules or {}

  if not next(profile_rules) then
    alert("No chrome_profile_rules found in configuration")
    return
  end

  -- Give user 5 seconds to focus a window
  alert("You have 5 seconds to focus the window you want to test...")

  hs.timer.doAfter(5, function()
    local frontmost_app = hs.application.frontmostApplication()
    if not frontmost_app then
      alert("No frontmost application found")
      return
    end

    local frontmost_win = frontmost_app:focusedWindow()
    if not frontmost_win then
      alert("No focused window found")
      return
    end

    -- Test the window
    local title = frontmost_win:title()
    local app_name = frontmost_app:name()
    local profile = M.detect_profile(frontmost_win, profile_rules)
    local target_space = M.get_target_space_for_window(frontmost_win, profile_rules)
    local current_space = M.get_current_space_for_window(frontmost_win)
    local is_home = M.is_window_home(frontmost_win, profile_rules)

    -- Convert space IDs to readable numbers
    local desktop_space_numbers = require('desktop_space_numbers')
    local spaces_map = desktop_space_numbers.spaces_map()
    local current_space_number = "unknown"
    for space_id, space_info in pairs(spaces_map) do
      if space_id == current_space then
        current_space_number = space_info.spaceNumber
        break
      end
    end

    local report = {}
    table.insert(report, "=== Frontmost Window Test ===")
    table.insert(report, string.format("App: %s", app_name))
    table.insert(report, string.format("Title: %s", title:len() > 60 and (title:sub(1, 60) .. "...") or title))
    table.insert(report, string.format("Profile: %s", profile or "none"))
    table.insert(report, string.format("Target space: %s", target_space or "none"))
    table.insert(report, string.format("Current space: %s (ID: %s)", current_space_number, current_space or "unknown"))
    table.insert(report, string.format("Is home: %s", is_home and "YES" or "NO"))

    if profile and target_space and not is_home then
      table.insert(report, string.format(">>> Window should be moved to Space %d", target_space))
      table.insert(report, "")
      table.insert(report, "Testing window movement...")

      local final_report = table.concat(report, "\n")
      print(final_report)
      hs.pasteboard.setContents(final_report)

      -- Automatically test movement
      local move_config = {
        space_jump_modifiers = self.config.space_jump_modifiers or DEFAULT_SPACE_JUMP_MODIFIERS
      }
      local success, msg = M.move_window_to_space(frontmost_win, target_space, move_config)
      if success then
        alert("SUCCESS: " .. msg)
      else
        alert("FAILED: " .. msg)
      end
    else
      local final_report = table.concat(report, "\n")
      print(final_report)
      hs.pasteboard.setContents(final_report)
      alert("Frontmost window test complete. Results in console and clipboard.")
    end
  end)
end

-- Discovery phase for tidy: Enumerate all Chrome windows across all spaces
function M:discover_chrome_windows_for_tidy()
  local profile_rules = self.config.chrome_profile_rules or {}

  if not next(profile_rules) then
    M._logger.e("No chrome_profile_rules found in configuration")
    return nil, "No chrome_profile_rules found"
  end

  -- Get Chrome application
  local chrome_app = hs.application.get("Google Chrome")
  if not chrome_app then
    M._logger.e("Google Chrome is not running")
    return nil, "Chrome not running"
  end

  M._logger.i("Starting comprehensive Chrome window discovery...")

  local desktop_space_numbers = require('desktop_space_numbers')
  local spaces_map = desktop_space_numbers.spaces_map()
  local spaces = require "hs.spaces"

  -- Save current space to restore later
  local original_space = spaces.focusedSpace()

  -- Track all discovered windows
  local all_chrome_windows = {}
  local spaces_visited = 0

  -- Visit EVERY space on EVERY display
  for _, screen in ipairs(hs.screen.allScreens()) do
    M._logger.d(string.format("Scanning display: %s", screen:name()))

    local screen_spaces = spaces.spacesForScreen(screen)
    for _, space_id in ipairs(screen_spaces) do
      -- Skip non-user spaces (fullscreen, dashboard, etc)
      if spaces.spaceType(space_id) == "user" then
        spaces_visited = spaces_visited + 1

        -- Switch to this space
        spaces.gotoSpace(space_id)
        hs.timer.usleep(100000) -- 0.1 second wait

        -- Get space number for logging
        local space_number = nil
        for sid, sinfo in pairs(spaces_map) do
          if sid == space_id and sinfo.spaceNumber then
            space_number = sinfo.spaceNumber
            break
          end
        end

        M._logger.d(string.format("Visiting space %s (number: %s) on %s",
                                 space_id, space_number or "unknown", screen:name()))

        -- Try multiple methods to find Chrome windows
        local space_windows = spaces.windowsForSpace(space_id)
        local chrome_windows_this_space = chrome_app:allWindows()

        -- Combine results
        local potential_windows = {}

        -- From space-specific query
        for _, win_id in ipairs(space_windows) do
          local win = hs.window.get(win_id)
          if win and win:application() and win:application():name() == "Google Chrome" then
            table.insert(potential_windows, win)
          end
        end

        -- From application query
        for _, win in ipairs(chrome_windows_this_space) do
          if win:isStandard() and not win:isMinimized() then
            table.insert(potential_windows, win)
          end
        end

        -- Deduplicate and add to main list
        for _, win in ipairs(potential_windows) do
          local already_found = false
          for _, existing_win in ipairs(all_chrome_windows) do
            if existing_win.window:id() == win:id() then
              already_found = true
              break
            end
          end

          if not already_found then
            -- Determine profile and target space
            local profile = M.detect_profile(win, profile_rules)
            local target_space = M.get_target_space_for_window(win, profile_rules)

            -- Create window info entry
            local window_info = {
              window = win,
              title = win:title(),
              profile = profile,
              target_space_number = target_space,
              current_space_id = space_id,
              current_space_number = space_number,
              screen_name = screen:name()
            }

            table.insert(all_chrome_windows, window_info)
            M._logger.d(string.format("Found: %s [%s] in space %s",
                                    win:title():sub(1, 40),
                                    profile or "no-profile",
                                    space_number or "unknown"))
          end
        end
      end
    end
  end

  -- Return to original space
  spaces.gotoSpace(original_space)

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

-- Main function to tidy all Chrome windows by profile
function M:tidy()
  M._logger.i("Starting Chrome window tidy...")

  -- PHASE 1: Discovery - enumerate all Chrome windows and build todo list
  local todo_list, summary = self:discover_chrome_windows_for_tidy()

  if not todo_list then
    M._logger.e(summary or "Discovery failed")
    return
  end

  -- If no windows need moving, we're done
  if summary.needs_move == 0 then
    M._logger.i(string.format("All %d Chrome windows are already in correct spaces!", summary.total_windows))
    alert(string.format("All %d Chrome windows are already in correct spaces!", summary.total_windows))
    return
  end

  M._logger.i(string.format("Found %d windows needing moves. Starting execution...", summary.needs_move))

  -- For now, just report what we would do
  M._logger.i("=== TIDY EXECUTION WOULD MOVE ===")
  for i, win_info in ipairs(todo_list) do
    M._logger.i(string.format("%d. '%s' from space %s to %s",
                             i,
                             win_info.title:sub(1, 50),
                             win_info.current_space_number or "?",
                             win_info.target_space_number or "?"))
  end

  M._logger.i(string.format("Discovery complete: %d windows need moving (execution not yet implemented)", summary.needs_move))
  alert(string.format("Discovery complete: %d windows need moving (see console)", summary.needs_move))

  -- TODO: PHASE 2: Execute moves
  -- TODO: PHASE 3: Restore original display state
end


-- Helper function to restore display state
function M:restore_display_state(original_state, space_jump_modifiers)
  local spaces = require "hs.spaces"
  M._logger.i("Restoring original display state...")

  for _, state in ipairs(original_state) do
    if state.space_number then
      -- Make this screen active by focusing a window on it, or using mouse as fallback
      local screen_windows = {}
      for _, win in ipairs(hs.window.allWindows()) do
        if win:screen():id() == state.screen:id() and win:isStandard() and not win:isMinimized() then
          table.insert(screen_windows, win)
        end
      end

      if #screen_windows > 0 then
        -- Focus a window on this screen to make it active
        screen_windows[1]:focus()
        hs.timer.usleep(TIMING.WINDOW_FOCUS_WAIT)
      else
        -- Fallback to mouse movement
        local screen_frame = state.screen:frame()
        hs.mouse.setAbsolutePosition({x = screen_frame.x + 100, y = screen_frame.y + 100})
        hs.timer.usleep(TIMING.SCREEN_ACTIVATION_WAIT)
      end

      -- Jump back to original space
      local key = state.space_number == 10 and "0" or tostring(state.space_number)
      hs.eventtap.keyStroke(space_jump_modifiers, key, 0)
      hs.timer.usleep(TIMING.SPACE_CHANGE_WAIT)

      -- Verify restoration worked
      local current_space, err = spaces.activeSpaceOnScreen(state.screen)
      if current_space == state.space_id then
        M._logger.i(string.format("✅ Restored %s to space %d", state.screen_name, state.space_number))
      else
        M._logger.e(string.format("❌ Failed to restore %s to space %d. Current: %s, Error: %s",
                                 state.screen_name, state.space_number, current_space or "unknown", err or "none"))
      end
    end
  end
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


-- Decorating a global!
function hs.window.layout:active()
  if self.screens then
    for hint,test in pairs(self.screens) do
      local screen = hs.screen.find(hint)
      if screen then
        if type(test) == 'boolean' then
          if not test then return false end
        else
          local x,y = screen:position()
          local test_geometry = hs_geometry.new(test)
          if not x == test_geometry.x or not y == test_geometry.y then
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
    if layout:active() then
      active_layouts[#active_layouts+1] = layout.logname
    end
  end)
  setmetatable(active_layouts, { __tostring = function(t) return table.concat(t, '|') end, })
  function active_layouts:tostring() return tostring(self) end  -- luacheck: no redefined
  return active_layouts
end


function M:start(config)
  self.config = config or {}

  -- Load window layouts from configuration
  if self.config.window_layouts then
    for layout_name, layout in pairs(self.config.window_layouts) do
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
