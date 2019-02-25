-- Move windows between spaces

local M = { hotkeys = {}, hotkey_timer = nil }

M._logger = hs.logger.new("Move spaces")
local logger = M._logger
logger.i("Loading Move spaces tools")

-- # Usage
-- require 'move_spaces'
-- move_spaces:bindHotkeys({
--   left  = {{"⌘", "⌥", "⌃", "⇧"}, "h"},
--   right = {{"⌘", "⌥", "⌃", "⇧"}, "l"},
-- })

hs.settings.set("_ASMundocumentedSpacesRaw", true)
local spaces = require "hs._asm.undocumented.spaces" -- https://github.com/asmagill/hs._asm.undocumented.spaces

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
    logger.i("Frontmost window present on multiple spaces so just taking you ".. direction)
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

  return win
end

function M.moveWindowOneSpaceAndFocus(direction)
  local win = M.moveWindowOneSpace(direction)

  if win then
    win:focus()  -- focusing the window will change the active space
    hs.fnutils.each({ 0.2, 0.4, 0.6 }, function(delay) hs.timer.doAfter(delay, function() win:focus() end) end)
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

local function spaces_map()
  local space_number = 0
  local screen_number = 0
  local map = { active_spaces = {} }
  for _, screen in pairs(spaces.raw.details()) do
    screen_number = screen_number + 1
    for _, space in pairs(screen.Spaces) do
      space_number = space_number + 1
      map[space.ManagedSpaceID] = {
        space_number = space_number,
        uuid = space.uuid,
        type = space.type,
      }
    end
    map.active_spaces[screen["Display Identifier"]] = {
      screen_number = screen_number,
      space_number = map[screen["Current Space"].ManagedSpaceID].space_number,
      space_id = screen["Current Space"].ManagedSpaceID,
      display_identifier = screen["Display Identifier"]
    }
  end
  return map
end

function M.showDesktopSpaceNumbers()
  local map = spaces_map()

  if M.space_labels then
    hs.fnutils.each(M.space_labels, function(l) l:delete() end)
  else
    M.space_labels = {}
  end

  for _,screen in pairs(hs.screen.allScreens()) do
    M.space_labels[screen:spacesUUID()] = hs.drawing.text(
      hs.geometry.rect(
        screen:frame().x + 2,
        screen:frame().y - 21,
        11, 11
      ),
      map.active_spaces[screen:spacesUUID()].space_number
    ):
      setBehavior(hs.drawing.windowBehaviors['stationary']):
      setLevel('assistiveTechHigh'):
      setTextSize(8):
      setAlpha(0.7):
      show()
  end
end

M.spacesWatcher = hs.spaces.watcher.new(M.showDesktopSpaceNumbers)
M.screensWatcher = hs.screen.watcher.new(M.showDesktopSpaceNumbers)

function M:bindHotkeys(mapping)
  self.hotkeys.right = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Right",
    mapping.right[1], mapping.right[2], function() self:nudgeOrMove("right") end)
  self.hotkeys.left  = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Left",
    mapping.left[1], mapping.left[2],  function() self:nudgeOrMove("left") end)
  return self
end

function M:start()
  self.spacesWatcher:start()
  self.screensWatcher:start()
  self.showDesktopSpaceNumbers()
end

return M
