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

function M.changeSpace(direction)
  -- this fails to work for reasons I do not understand (or 'cos the OS doesn't allow it)
  hs.eventtap.keyStroke({"ctrl"}, direction)
end

function M.moveWindowOneSpace(direction)
  logger.i('MoveWindowOneSpace '..direction)

  local direction_map = {
    left = "left",
    ["←"] = "left",
    right = "right",
    ["→"] = "right",
  }
  direction = direction_map[direction:lower()]

  local win = hs.window.frontmostWindow()

  local screen = win:screen()
  local screenUUID = screen:getUUID()
  local spacesForScreen = spaces.spacesForScreen(screenUUID)
  local activeSpace = spaces.activeSpaceOnScreen(screenUUID)
  local currentSpaceIndex = hs.fnutils.indexOf(spacesForScreen, activeSpace)

  logger.i(i({
    screen = screen,
    screenUUID = screenUUID,
    spacesForScreen = spacesForScreen,
    activeSpace = activeSpace,
    currentSpaceIndex = currentSpaceIndex
  }))

  if (direction == 'left' and currentSpaceIndex == 1) or
    (direction == 'right' and currentSpaceIndex == #spacesForScreen) then
    -- already at end of spaces
    logger.i('… already at end of spaces; doing nothing')
    return nil
  end

  local targetSpaceID = spacesForScreen[direction == "left" and currentSpaceIndex - 1 or currentSpaceIndex + 1]
  logger.d('screen='..i(screen).. ' screenUUID='..i(screenUUID)..
    ' activeSpace='..i(activeSpace).. ' spacesForScreen='..i(spacesForScreen)..
    ' currentSpaceIndex='..i(currentSpaceIndex).. ' targetSpaceID='..i(targetSpaceID))

  spaces.moveWindowToSpace(win:id(), targetSpaceID)

  return win
end

function M.moveWindowOneSpaceAndFocus(direction)
  local win = M.moveWindowOneSpace(direction)
  logger.i('…AndFocus ')

  if win then
    local windowSpaces = spaces.windowSpaces(win:id())

    if #windowSpaces > 1 then
      logger.i('Frontmost window present on multiple spaces so just taking you '.. direction)
      M.changeSpace(direction)
    else
      win:focus()  -- focusing the window will change the active space
      hs.fnutils.each({ 0.2, 0.4, 0.6 }, function(delay) hs.timer.doAfter(delay, function() win:focus() end) end)
    end
  end
end

function M:nudgeOrMove(direction)
  if not self.double_tap_timer then
    -- If called once, move and follow focus to the new space
    self.double_tap_timer = hs.timer.doAfter(0.25,
      function()
        self.double_tap_timer = nil
        self.moveWindowOneSpaceAndFocus(direction)
      end)
  else
    -- If called twice, nudge without following the window to the new space
    self.double_tap_timer:stop()
    self.double_tap_timer = nil
    self.moveWindowOneSpace(direction)
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
