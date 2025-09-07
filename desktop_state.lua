-- Desktop State Query Functions
-- Centralized module for all window, space, and display state queries
-- Extracted from move_spaces.lua and stay/init.lua to improve reliability

local M = {}

local logger = hs.logger.new('DesktopState', 'debug')
M._logger = logger

-- State tracking for stability checks
M._window_stability_state = {}

-- Dependencies
local desktop_space_numbers = require('desktop_space_numbers')
local spaces = require("hs.spaces")

-- === WINDOW STATE QUERIES ===

-- Get the frontmost (focused) window
function M.getFrontmostWindow()
  return hs.window.frontmostWindow()
end

-- Get the focused window of the frontmost application
function M.getFocusedWindow()
  local app = hs.application.frontmostApplication()
  return app and app:focusedWindow() or nil
end

-- Check if a specific window is currently focused
function M.isWindowFocused(win)
  if not win then return false end
  local frontmost = hs.window.frontmostWindow()
  return frontmost and frontmost:id() == win:id()
end

-- Get the current space ID that contains a window
function M.getWindowSpaceId(win)
  if not win then return nil end
  local win_spaces = spaces.windowSpaces(win)
  return win_spaces and win_spaces[1] or nil
end

-- Get the current space number that contains a window
function M.getWindowSpaceNumber(win)
  if not win then return nil end
  return desktop_space_numbers.getWindowSpaceNumber(win)
end

-- Check if a window is on a specific display
function M.isWindowOnDisplay(win, target_display)
  if not win or not target_display then return false end
  return win:screen():id() == target_display:id()
end

-- Check if window is stable and ready for interaction after a move
function M.isWindowStableOnDisplay(win, target_display)
  if not win or not target_display then
    return false
  end

  -- Basic checks first
  if not M.isWindowOnDisplay(win, target_display) then
    return false
  end

  -- Check if window is focused (required for drag operations)
  if not M.isWindowFocused(win) then
    return false
  end

  -- Get current state
  local frame = win:frame()
  local zoom_rect = win:zoomButtonRect()
  local window_space = M.getWindowSpaceNumber(win)

  -- Expected relative position: zoom should be approximately frame + (59, 12)
  local expected_zoom_x = frame.x + 59
  local expected_zoom_y = frame.y + 12
  local zoom_x_diff = math.abs(zoom_rect.x - expected_zoom_x)
  local zoom_y_diff = math.abs(zoom_rect.y - expected_zoom_y)

  -- Check if zoom coordinates are within 5px of expected relative position
  local zoom_position_correct = zoom_x_diff <= 5 and zoom_y_diff <= 5

  -- Use window ID as key for stability tracking
  local win_key = tostring(win:id())
  local current_state = {
    frame_x = frame.x,
    frame_y = frame.y,
    zoom_x = zoom_rect.x,
    zoom_y = zoom_rect.y,
    window_space = window_space,
    zoom_position_correct = zoom_position_correct,
    timestamp = os.time()
  }

  -- Get previous state
  local previous_state = M._window_stability_state[win_key]

  -- Store current state for next check
  M._window_stability_state[win_key] = current_state

  logger.d(string.format("isWindowStableOnDisplay: display=%s, frame=(%.0f,%.0f), zoom=(%.0f,%.0f), space=%s",
    target_display:name(), frame.x, frame.y, zoom_rect.x, zoom_rect.y, tostring(window_space)))
  logger.d(string.format("  expected_zoom=(%.0f,%.0f), diff=(%.1f,%.1f), zoom_correct=%s",
    expected_zoom_x, expected_zoom_y, zoom_x_diff, zoom_y_diff, tostring(zoom_position_correct)))

  if not previous_state then
    logger.d("  stability=false (no previous state)")
    return false
  end

  -- Check if frame position is stable (same as previous check)
  local frame_stable = (current_state.frame_x == previous_state.frame_x and
                       current_state.frame_y == previous_state.frame_y)

  local stable = frame_stable and
                 current_state.zoom_position_correct and
                 previous_state.zoom_position_correct

  logger.d(string.format("  frame_stable=%s, zoom_correct_now=%s, zoom_correct_prev=%s, overall_stable=%s",
    tostring(frame_stable), tostring(current_state.zoom_position_correct),
    tostring(previous_state.zoom_position_correct), tostring(stable)))

  return stable
end

-- === SPACE STATE QUERIES ===

-- Get the currently active space ID
function M.getCurrentSpaceId()
  return spaces.focusedSpace()
end

-- Get the currently active space number
function M.getCurrentSpaceNumber()
  return desktop_space_numbers.getCurrentSpaceNumber()
end

-- Get current space numbers for all displays
function M.getCurrentSpaceNumbers()
  return desktop_space_numbers.getCurrentSpaceNumbers()
end

-- Get space ID from space number
function M.getSpaceId(space_number)
  return desktop_space_numbers.getSpaceId(space_number)
end

-- Get space number from space ID
function M.getSpaceNumber(space_id)
  return desktop_space_numbers.getSpaceNumber(space_id)
end

-- Get the display that contains a specific space
function M.getSpaceDisplay(space_id)
  return desktop_space_numbers.getSpaceDisplay(space_id)
end

-- Get active space ID for a specific display
function M.getActiveSpaceOnDisplay(display)
  if not display then return nil end
  local current_spaces = M.getCurrentSpaceNumbers()
  local space_number = current_spaces.spaces[display:id()]
  return space_number and M.getSpaceId(space_number) or nil
end

-- Check if a specific display is showing a target space number
function M.isDisplayOnSpace(display, target_space_number)
  if not display or not target_space_number then return false end
  local current_spaces = M.getCurrentSpaceNumbers()
  local display_current_space = current_spaces.spaces[display:id()]
  return display_current_space == target_space_number
end

-- Get all user spaces for a display (excluding fullscreen, dashboard, etc.)
function M.getUserSpacesForDisplay(display)
  if not display then return nil end

  local uuid = display:getUUID()
  local allSpaces = spaces.allSpaces()
  local userSpaces = allSpaces[uuid]

  if not userSpaces then return nil end

  -- Filter out non-user spaces
  local filteredSpaces = {}
  for _, space_id in ipairs(userSpaces) do
    if spaces.spaceType(space_id) == "user" then
      table.insert(filteredSpaces, space_id)
    end
  end

  return filteredSpaces
end

-- Get space mapping (space ID to space info)
function M.getSpacesMap()
  return desktop_space_numbers.spaces_map()
end

-- === WINDOW VALIDATION QUERIES ===

-- Check if window is suitable for moving between spaces
function M.isMoveableWindow(win)
  if not win then
    return false, "Window is nil"
  elseif not win:isStandard() then
    return false, "Window is not standard"
  elseif win:isFullScreen() then
    return false, "Window is fullscreen"
  elseif win:isMinimized() then
    return false, "Window is minimized"
  end
  return true, nil
end

-- === SPACE NAVIGATION QUERIES ===

-- Find adjacent space in a direction on the same display
function M.getAdjacentSpaceNumber(current_space_number, direction, display)
  if not current_space_number or not direction or not display then
    return nil, "Invalid parameters"
  end

  local userSpaces = M.getUserSpacesForDisplay(display)
  if not userSpaces then
    return nil, "No user spaces found for display"
  end

  -- Find current space in the list
  local current_space_id = M.getSpaceId(current_space_number)
  local current_index = nil

  for i, space_id in ipairs(userSpaces) do
    if space_id == current_space_id then
      current_index = i
      break
    end
  end

  if not current_index then
    return nil, "Could not find current space in user spaces list"
  end

  -- Calculate target index
  local target_index
  if direction == "right" then
    target_index = current_index + 1
  elseif direction == "left" then
    target_index = current_index - 1
  else
    return nil, "Invalid direction: " .. tostring(direction)
  end

  -- Check bounds
  if target_index < 1 or target_index > #userSpaces then
    return nil, "No adjacent space in that direction"
  end

  -- Get target space number
  local target_space_id = userSpaces[target_index]
  local target_space_number = M.getSpaceNumber(target_space_id)

  if not target_space_number then
    return nil, "Could not determine target space number"
  end

  return target_space_number, nil
end

-- === SPACE NAVIGATION FUNCTIONS ===

-- Get all spaces for a specific screen
function M.getSpacesForScreen(screen)
  return spaces.spacesForScreen(screen)
end

-- Switch to a specific space
function M.gotoSpace(space_id)
  return spaces.gotoSpace(space_id)
end

-- Get all windows on a specific space
function M.getWindowsForSpace(space_id)
  return spaces.windowsForSpace(space_id)
end

-- Get the type of a space (user, fullscreen, etc.)
function M.getSpaceType(space_id)
  return spaces.spaceType(space_id)
end

-- Get the active space on a specific screen
function M.getActiveSpaceOnScreen(screen)
  return spaces.activeSpaceOnScreen(screen)
end

-- === UTILITY FUNCTIONS ===

-- Convert space number to keyboard key (space 10 uses "0")
function M.spaceNumberToKey(space_number)
  return space_number == 10 and "0" or tostring(space_number)
end

return M