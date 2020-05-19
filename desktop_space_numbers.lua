-- Report space numbers in menubar

-- luacheck: globals hs

local M = {}

M._logger = hs.logger.new("Space #s")
local logger = M._logger
logger.i("Loading Desktop Space Numbers")

-- # Usage
-- require 'desktop_space_numbers'
-- move_spaces:start()

hs.settings.set("_ASMundocumentedSpacesRaw", true)
local spaces = require "hs._asm.undocumented.spaces" -- https://github.com/asmagill/hs._asm.undocumented.spaces

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
        space_id = screen["Current Space"].ManagedSpaceID,
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
M.spaces_map = spaces_map

local function clear_space_labels()
  if M.space_labels then
    hs.fnutils.each(M.space_labels, function(l) if l then l:delete() end end)
  end
  M.space_labels = {}
end
M.clear_space_labels = clear_space_labels

function M.showDesktopSpaceNumbers()
  local map = spaces_map()
  clear_space_labels()

  for _,screen in pairs(hs.screen.allScreens()) do
    if screen:spacesUUID() and screen:frame() and map.active_spaces[screen:spacesUUID()] then
      local label = tostring(map.active_spaces[screen:spacesUUID()].space_number)
      local text_size = hs.drawing.getTextDrawingSize(label)
      M.space_labels[screen:spacesUUID()] = hs.drawing.text(
        hs.geometry.rect(
          screen:frame().x + 4,
          screen:frame().y - 15,
          text_size.w, text_size.h
        ),
        label
      ):
        setBehavior(hs.drawing.windowBehaviors['stationary']):
        setLevel('assistiveTechHigh'):
        setTextSize(8):
        setAlpha(0.7):
        show()
    else
      if not screen:spacesUUID() then
        logger.w('No :spacesUUID() for screen '.. hs.inspect(screen))
      elseif not screen:frame() then
        logger.w('No :frame() for screen '.. hs.inspect(screen))
      elseif not map.active_spaces[screen:spacesUUID()] then
        logger.w('spacesUUID '..screen:spacesUUID()..' not in `spaces_map.active_spaces` '..
          hs.inspect(map.active_spaces))
      end
    end
  end
end

M.watchers = {
  spaces  = hs.spaces.watcher.new(M.showDesktopSpaceNumbers),
  screens = hs.screen.watcher.new(M.showDesktopSpaceNumbers),
}

function M:start()
  hs.fnutils.each(self.watchers, function(w) w:start() end)
  self.showDesktopSpaceNumbers()
end

function M:stop()
  hs.fnutils.each(self.watchers, function(w) w:stop() end)
  clear_space_labels()
end

return M
