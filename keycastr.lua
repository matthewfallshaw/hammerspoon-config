-- Keycastr replacement: Show typed keys onscreen
--
-- icon attribution: click by Numero Uno from the Noun Project (https://thenounproject.com/search/?q=click&i=975277)

local M = {}

-- Metadata
M.name = "Keycastr"
M.version = "0.1"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.license = "MIT - https://opensource.org/licenses/MIT"
-- M.homepage = "https://github.com/matthewfallshaw/Keycastr.spoon"

local fun = require('fun')

local logger = hs.logger.new(M.name)
M._logger = logger
logger.i("Loading "..M.name)

M.hotkeys = {}
M.hotkeys.mapping = { toggle = {{"cmd", "shift", "ctrl"}, 'P'} }  -- Default <C-⌘-⇧-p>

M.display_buffer = nil
M.alert_container = nil
M.alert_position = {  -- use negatives for offset
  x = 100,
  y = -100,
}

local duration = 1.5  -- popup duration
M.duration = duration

function M:alert(msg)
  local buffer = self.display_buffer
  buffer:setString(buffer .. msg)
  local c_size = hs.drawing.getTextDrawingSize(buffer)
  c_size.width = (c_size.width or 0) + 10
  local container = self.alert_container
  container:setSize(c_size)
  local screen_frame = hs.screen.mainScreen():frame()
  container:setTopLeft({
    x = (self.alert_position.x > 0) and self.alert_position.x or screen_frame.w + self.alert_position.x,
    y = (self.alert_position.y > 0) and self.alert_position.y or screen_frame.h + self.alert_position.y,
  })
  container:setString(buffer)
  container:show()
  self._hide_timer:start()
  hs.timer.doAfter(self.duration, function() self:_clearStringFromBuffer(msg) end)
end

function M:hideAlert()
  self.alert_container:hide()
end

function M:_clearStringFromBuffer(text)
  local old_string = self.display_buffer:getString()
  local new_string = old_string:gsub('^'..(text or ''), '')
  self.display_buffer:setString(new_string)
end

-- we only want to read special characters via getKeyCode, so we
-- use this subset of hs.keycodes.map
local special_chars = fun.tomap(
  fun.zip(
    {
      "f1"  , "f2"  , "f3"  , "f4"  , "f5"  , "f6"  , "f7"  , "f8"  , "f9"  , "f10" ,
      "f11" , "f12" , "f13" , "f14" , "f15" , "f16" , "f17" , "f18" , "f19" , "f20" ,
      "pad", "pad*", "pad+", "pad-", "pad/", "pad=", "padclear", "padenter",
      "pad1", "pad2", "pad3", "pad4", "pad5", "pad6", "pad7", "pad8", "pad9", "pad0",
      "return", "tab", "space",
      "delete", "forwarddelete", "escape", "help",
      "home", "end", "pageup", "pagedown", "left", "right", "up", "down",
    },
    fun.duplicate(true)
  )
)
M._special_chars = special_chars

local special_symbols = {
  ['return'] = "⏎",
  delete     = "⌫",
  escape     = "⎋",
  space      = "␣",
  up         = "↑",
  down       = "↓",
  left       = "←",
  right      = "→"
}
M._special_symbols = special_symbols

function M:showKeyPress(tap_event)
  local flags = tap_event:getFlags()
  local character = hs.keycodes.map[tap_event:getKeyCode()]

  -- if we have a simple character (no modifiers), we want a shorter popup duration.
  if (not flags.shift and not flags.cmd and not flags.alt and not flags.ctrl) then
    duration = 0.3
  end

  -- we want to get regular characters via getCharacters as it "cleans" the key for us
  -- (e.g. for a "⇧-5" keypress we want to show "⇧-%").
  if special_chars[character] == nil then
    character = tap_event:getCharacters(true)
    if flags.shift then character = string.lower(character) end
  end

  -- make some known special characters look good
  character = special_symbols[character] or character

  -- get modifiers' string representation
  local modifiers = ""  -- key modifiers string representation
  if flags.ctrl  then modifiers = modifiers .. "C-" end
  if flags.cmd   then modifiers = modifiers .. "⌘-" end
  if flags.shift then modifiers = modifiers .. "⇧-" end
  if flags.alt   then modifiers = modifiers .. "⌥-" end

  -- actually show the popup
  self:alert(modifiers .. character)

  return nil  -- don't delete the event
end

function M:showMouseClick(click_event)
  logger.w(hs.inspect(click_event:location()))
  self:alert(hs.inspect(click_event:location()))  -- TODO

  return nil  -- don't delete the event
end


function M:bindHotkeys(mapping)
  -- Default
  if not mapping or #mapping == 0 then
    mapping = self.hotkeys.mapping
  else
    self.hotkeys.mapping = mapping
  end

  local key_tap = hs.eventtap.new(
    { hs.eventtap.event.types.keyDown },
    function(tap_event)
      local status, err = pcall(function() self:showKeyPress(tap_event) end)
      if not status then logger.e(err) end
      return nil
    end)
  self.key_tap = key_tap

  local mouse_click = hs.eventtap.new(
    { hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown },
    function(mouse_event)
      local status, err = pcall(function() self:showMouseClick(mouse_event) end)
      if not status then logger.e(err) end
      return nil
    end)
  self.mouse_click = mouse_click

  local modal = hs.hotkey.modal.new(mapping.toggle[1], mapping.toggle[2])
  self.hotkeys.modal = modal

  local parent = self
  function modal:entered()
    parent:alert("Enabling Keypress Show Mode")
    key_tap:start()
    mouse_click:start()
  end
  function modal:exited()
    parent:alert("Disabling Keypress Show Mode")
  end

  modal:bind(mapping.toggle[1], mapping.toggle[2], function()
    key_tap:stop()
    mouse_click:stop()
    modal:exit()
  end)
  spoon.CaptureHotkeys:capture(self.name, "Toggle 'cast mode", mapping.toggle[1], mapping.toggle[2])
  return self
end

function M:init()
  local buffer = hs.styledtext.new('', {backgroundColor = {0,0,0}})
  M.display_buffer = buffer
  local c_size = hs.drawing.getTextDrawingSize(buffer)
  M.alert_container = hs.drawing.text(
    { x = 100, y = 100,
      w = c_size.w,
      h = c_size.h },
    buffer)
  M._hide_timer = hs.timer.delayed.new(duration, function() self:hideAlert() end)
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

M:init()  -- TODO: remove if Spoonifying

return M
