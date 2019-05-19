-- Keycastr replacement: Show typed keys onscreen

local M = {}

-- Metadata
M.name = "Keycastr"
M.version = "0.1"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.license = "MIT - https://opensource.org/licenses/MIT"
-- M.homepage = "https://github.com/matthewfallshaw/Keycastr.spoon"

local logger = hs.logger.new(M.name)
M._logger = logger
logger.i("Loading "..M.name)

M.hotkeys = {}
M.hotkeys.mapping = { toggle = {{"cmd", "shift", "ctrl"}, 'P'} }  -- Default <C-⌘-⇧-p>

local duration = 1.5  -- popup duration
-- we only want to read special characters via getKeyCode, so we
-- use this subset of hs.keycodes.map
local special_chars = {
  ["f1"] = true, ["f2"] = true, ["f3"] = true, ["f4"] = true,
  ["f5"] = true, ["f6"] = true, ["f7"] = true, ["f8"] = true,
  ["f9"] = true, ["f10"] = true, ["f11"] = true, ["f12"] = true,
  ["f13"] = true, ["f14"] = true, ["f15"] = true, ["f16"] = true,
  ["f17"] = true, ["f18"] = true, ["f19"] = true, ["f20"] = true,
  ["pad"] = true, ["pad*"] = true, ["pad+"] = true, ["pad/"] = true,
  ["pad-"] = true, ["pad="] = true, ["pad0"] = true, ["pad1"] = true,
  ["pad2"] = true, ["pad3"] = true, ["pad4"] = true, ["pad5"] = true,
  ["pad6"] = true, ["pad7"] = true, ["pad8"] = true, ["pad9"] = true,
  ["padclear"] = true, ["padenter"] = true, ["return"] = true,
  ["tab"] = true, ["space"] = true, ["delete"] = true, ["escape"] = true,
  ["help"] = true, ["home"] = true, ["pageup"] = true,
  ["forwarddelete"] = true, ["end"] = true, ["pagedown"] = true,
  ["left"] = true, ["right"] = true, ["down"] = true, ["up"] = true
}

local function showKeyPress(tap_event)
  local flags = tap_event:getFlags()
  local character = hs.keycodes.map[tap_event:getKeyCode()]

  -- if we have a simple character (no modifiers), we want a shorter
  -- popup duration.
  if (not flags.shift and not flags.cmd and
        not flags.alt and not flags.ctrl) then
    duration = 0.3
  end

  -- we want to get regular characters via getCharacters as it
  -- "cleans" the key for us (e.g. for a "⇧-5" keypress we want
  -- to show "⇧-%").
  if special_chars[character] == nil then
    character = tap_event:getCharacters(true)
    if flags.shift then
      character = string.lower(character)
    end
  end

  -- make some known special characters look good
  if character == "return" then
    character = "⏎"
  elseif character == "delete" then
    character = "⌫"
  elseif character == "escape" then
    character = "⎋"
  elseif character == "space" then
    character = "SPC"
  elseif character == "up" then
    character = "↑"
  elseif character == "down" then
    character = "↓"
  elseif character == "left" then
    character = "←"
  elseif character == "right" then
    character = "→"
  end

  -- get modifiers' string representation
  local modifiers = ""  -- key modifiers string representation
  if flags.ctrl then
    modifiers = modifiers .. "C-"
  end
  if flags.cmd then
    modifiers = modifiers .. "⌘-"
  end
  if flags.shift then
    modifiers = modifiers .. "⇧-"
  end
  if flags.alt then
    modifiers = modifiers .. "⌥-"
  end

  -- actually show the popup
  hs.alert.show(modifiers .. character, duration)
end


function M:bindHotkeys(mapping)
  -- Default
  if not mapping or #mapping == 0 then
    mapping = self.hotkeys.mapping
  else
    self.hotkeys.mapping = mapping
  end

  self:stop()

  local key_tap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, showKeyPress)
  self.key_tap = key_tap

  local modal = hs.hotkey.modal.new(mapping.toggle[1], mapping.toggle[2])
  self.hotkeys.modal = modal

  function modal:entered()
    hs.alert.show("Enabling Keypress Show Mode", 1.5)
    key_tap:start()
  end
  function modal:exited()
    hs.alert.show("Disabling Keypress Show Mode", 1.5)
  end

  modal:bind(mapping.toggle[1], mapping.toggle[2], function()
    key_tap:stop()
    modal:exit()
  end)
  spoon.CaptureHotkeys:capture(self.name, "Toggle 'cast mode", mapping.toggle[1], mapping.toggle[2])
  return self
end

function M:start()
  self:bindHotkeys()
  return self
end
function M:stop()
  if self.key_tap then self.key_tap:stop() end
  if self.hotkeys.modal then self.hotkeys.modal:exit():delete() end
  return self
end

return M
