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
  if M.space_label_backgrounds then
    hs.fnutils.each(M.space_label_backgrounds, function(l) if l then l:delete() end end)
  end
  M.space_label_backgrounds = {}
end
M.clear_space_labels = clear_space_labels

function M.showDesktopSpaceNumbers()
  local map = spaces_map()
  clear_space_labels()

  for _,screen in pairs(hs.screen.allScreens()) do
    if screen:spacesUUID() and screen:frame() and map.active_spaces[screen:spacesUUID()] then
      local labeltext = tostring(map.active_spaces[screen:spacesUUID()].space_number)
      local styledtextformat = { color = { white=0, alpha=1 },
        shadow = { offset=0, blurRadius=4, color={ white=1, alpha=1 } },
        font = { size=10 },
        paragraphStyle = { alignment = 'center' },
      }
      local labelstyledtext = hs.styledtext.new(labeltext, styledtextformat)
      local text_size = hs.drawing.getTextDrawingSize(hs.styledtext.new('00', styledtextformat))
      local offsets = { x=4, y=-24 }
      M.space_labels[screen:spacesUUID()] = hs.drawing.text(
        hs.geometry.rect(
          screen:frame().x + offsets.x,
          screen:frame().y + offsets.y,
          text_size.w, text_size.h
        ),
        labelstyledtext
      ):setBehavior(hs.drawing.windowBehaviors['stationary'])
       :setLevel('help')
       :show()
      M.space_label_backgrounds[screen:spacesUUID()] = hs.drawing.ellipticalArc(
        hs.geometry.rect(
          screen:frame().x + offsets.x - 3,
          screen:frame().y + offsets.y - 1,
          text_size.w + 2 * 3, text_size.h + 2
        )
      ):setBehavior(hs.drawing.windowBehaviors['stationary'])
       :setLevel('overlay')
       :setFillColor({white=1, alpha=0.7})
       :setStroke(false)
       :show()
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
