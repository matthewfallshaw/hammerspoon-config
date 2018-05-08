-- Move windows between spaces
local logger = hs.logger.new("Move spaces")
logger.i("Loading Move spaces tools")

-- # Usage
-- require 'move-spaces'
-- move_spaces.hotkeys.right = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Right",
--   {"⌘", "⌥", "⌃", "⇧"}, "right", function() move_spaces.moveWindowOneSpace("right") end)
-- move_spaces.hotkeys.left  = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Left",
--   {"⌘", "⌥", "⌃", "⇧"}, "left",  function() move_spaces.moveWindowOneSpace("left") end)

M = { hotkeys = {} }

spaces = require "hs._asm.undocumented.spaces" -- https://github.com/asmagill/hs._asm.undocumented.spaces

function M.changeSpace(direction)
  hs.eventtap.keyStroke({"ctrl"}, direction)
end

function M.moveWindowOneSpace(direction)
  local direction_map = {
    left = "left",
    ["←"] = "left",
    right = "right",
    ["→"] = "right",
  }
  direction = direction_map[direction:lower()]

  local win = hs.window.frontmostWindow()

  if #win:spaces() > 1 then
    u.log_and_alert(logger, "Frontmost window present on multiple spaces so just taking you ".. direction)
    hs.eventtap.keyStroke({"ctrl"}, direction)
  else
    local screen = win:screen()
    local screenUUID = screen:spacesUUID()
    local currentSpaceUUID = spaces.spacesByScreenUUID(spaces.masks.currentSpaces)[screenUUID][1]

    local spacesForScreen = spaces.layout()[screenUUID]
    local currentSpaceIndex = hs.fnutils.indexOf(spacesForScreen, tonumber(currentSpaceUUID))

    if (direction == "left" and currentSpaceIndex == 1) or
      (direction == "right" and currentSpaceIndex == #spacesForScreen) then
      -- already at end of spaces
      return nil
    end

    local targetSpaceUUID = spacesForScreen[direction == "left" and currentSpaceIndex - 1 or currentSpaceIndex + 1]
    win:spacesMoveTo(targetSpaceUUID)
  end

  win:focus()  -- focusing the window will change the active space
  hs.fnutils.each({ 0.2, 0.4, 0.6 }, function(delay) hs.timer.doAfter(delay, function() win:focus() end) end)
end

return M
