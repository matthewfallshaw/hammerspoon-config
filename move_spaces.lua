-- Move windows between spaces

-- luacheck: globals hs spoon

local M = { hotkeys = {}, hotkey_timer = nil }

M._logger = hs.logger.new("Move spaces", 'debug')
local logger = M._logger
logger.i("Loading Move spaces tools")

local i = hs.inspect

-- # Usage
-- require 'move_spaces'
-- move_spaces:bindHotkeys({
--   left  = {{"⌘", "⌥", "⌃", "⇧"}, "h"},
--   right = {{"⌘", "⌥", "⌃", "⇧"}, "l"},
-- })

-- hs.settings.set("_ASMundocumentedSpacesRaw", true)
-- local spaces = require "hs._asm.undocumented.spaces" -- https://github.com/asmagill/hs._asm.undocumented.spaces
local spaces = require "hs.spaces" -- https://github.com/asmagill/hs._asm.spaces

-- Core implementation: moves window and stays there
function M.moveWindowWithFocus(win, direction)
  if not win or not win:isStandard() or win:isFullScreen() then
    logger.e('No suitable window found')
    return nil
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
    logger.e('No user spaces found')
    return nil
  end

  -- Filter out non-user spaces
  for i = #userSpaces, 1, -1 do
    if spaces.spaceType(userSpaces[i]) ~= "user" then
      table.remove(userSpaces, i)
    end
  end

  -- Get current space
  local initialSpace = spaces.windowSpaces(win)
  if not initialSpace then
    logger.e('Could not determine window space')
    return nil
  end
  initialSpace = initialSpace[1]

  -- Check if we're at the edge of available spaces
  if (direction == "right" and initialSpace == userSpaces[#userSpaces]) or
     (direction == "left" and initialSpace == userSpaces[1]) then
    logger.i('At edge of spaces, cannot move further')
    return nil
  end

  -- Save mouse position
  local currentCursor = hs.mouse.getRelativePosition()

  -- Get zoom button location and adjust slightly for safety
  local zoomPoint = hs.geometry(win:zoomButtonRect())
  local clickPoint = zoomPoint:move({-1,-1}).topleft

  -- Click and hold the titlebar
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, clickPoint):post()

  -- Move to next space
  hs.eventtap.keyStroke({"ctrl", "fn"}, direction, 0)

  -- Wait for space change and release click
  local moveSucceeded = false
  hs.timer.waitUntil(
    function()
      local newSpaces = spaces.windowSpaces(win)
      return newSpaces and newSpaces[1] ~= initialSpace
    end,
    function()
      hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, clickPoint):post()
      hs.mouse.setRelativePosition(currentCursor)
      moveSucceeded = true
      logger.i('Space change completed')
    end,
    0.05
  )

  return moveSucceeded and {
    window = win,
    fromSpace = initialSpace,
    toSpace = spaces.windowSpaces(win)[1]
  } or nil
end

-- Move window to adjacent space but return to original space
function M.moveWindowAndReturn(direction)
  logger.i('moveWindowAndReturn '..direction)

  local win = hs.window.frontmostWindow()
  local result = M.moveWindowWithFocus(win, direction)

  if result then
    -- Return to original space
    hs.timer.doAfter(0.1, function()
      hs.eventtap.keyStroke({"ctrl", "fn"}, direction == "right" and "left" or "right", 0)
    end)
  end

  return result and result.window or nil
end

-- Move window to adjacent space and stay there
function M.moveWindowAndStay(direction)
  logger.i('moveWindowAndStay '..direction)

  local win = hs.window.frontmostWindow()
  local result = M.moveWindowWithFocus(win, direction)

  if result then
    -- Give time for the space transition to complete
    hs.timer.doAfter(0.1, function()
      if win:isVisible() then
        win:focus()
        logger.i('Window focused')
      end
    end)
  end

  return result and result.window or nil
end

function M:nudgeOrMove(direction)
  if not self.double_tap_timer then
    -- If called once, move and stay
    self.double_tap_timer = hs.timer.doAfter(0.25,
      function()
        self.double_tap_timer = nil
        self.moveWindowAndStay(direction)
      end)
  else
    -- If called twice, move but return to original space
    self.double_tap_timer:stop()
    self.double_tap_timer = nil
    self.moveWindowAndReturn(direction)
  end
end

function M:bindHotkeys(mapping)
  self.hotkeys.right = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Right",
    mapping.right[1], mapping.right[2], function() self:nudgeOrMove("right") end)
  self.hotkeys.left  = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Left",
    mapping.left[1], mapping.left[2],  function() self:nudgeOrMove("left") end)
  return self
end

return M
