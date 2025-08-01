-- Report space numbers in menubar

-- luacheck: globals hs

local M = {}

M._logger = hs.logger.new("Space #s")
local logger = M._logger
logger.i("Loading Desktop Space Numbers")

-- Configuration constants
local SPACES_MAP_CACHE_TTL = 5.0 -- Cache for 5 seconds

-- # Usage
-- desktop_space_numbers = require('desktop_space_numbers')
-- desktop_space_numbers:start()

local spaces = require "hs.spaces" -- https://github.com/asmagill/hs._asm.spaces

-- ## Convenience functions

-- map(function, table)
 -- e.g: map(double, {1,2,3})    -> {2,4,6}
local function map(func, tbl)
  local newtbl = {}
  for i,v in pairs(tbl) do
    newtbl[i] = func(v)
  end
  return newtbl
end
M.map = map

-- filter(function, table)
-- e.g: filter(is_even, {1,2,3,4}) -> {2,4}
local function filter(func, tbl)
  local newtbl= {}
  for i,v in pairs(tbl) do
    if func(v) then
      newtbl[i]=v
    end
  end
  return newtbl
end
M.filter = filter

-- head(table)
-- e.g: head({1,2,3}) -> 1
local function head(tbl)
  return tbl[1]
end
M.head = head

-- tail(table)
-- e.g: tail({1,2,3}) -> {2,3}
--
-- XXX This is a BAD and ugly implementation.
-- should return the address to next porinter, like in C (arr+1)
local function tail(tbl)
  if #tbl < 1 then
    return nil
  else
    local newtbl = {}
    local tblsize = #tbl
    local i = 2
    while (i <= tblsize) do
      table.insert(newtbl, i-1, tbl[i])
      i = i + 1
    end
    return newtbl
  end
end
M.tail = tail

-- foldr(function, default_value, table)
-- e.g: foldr(operator.mul, 1, {1,2,3,4,5}) -> 120
local function foldr(func, val, tbl)
  for i,v in pairs(tbl) do
    val = func(val, v)
  end
  return val
end
M.foldr = foldr

-- reduce(function, table)
-- e.g: reduce(operator.add, {1,2,3,4}) -> 10
local function reduce(func, tbl)
logger.e(i({in_function = "reduce", h = head(tbl), t = tail(tbl)}))
  return foldr(func, head(tbl), tail(tbl))
end
M.reduce = reduce

-- ## Utility functions

-- Helper: build spaces map data
local function buildSpacesMap()
  local spaces_map = {}
  local allSpaces = spaces.allSpaces()
  local spaceNumber = 1

  -- Get the primary screen
  local primaryScreen = hs.screen.primaryScreen()

  -- Get all screens
  local screens = hs.screen.allScreens()

  -- Sort the screens based on their position
  table.sort(screens, function(a, b)
    local aPos_x, aPos_y = a:position()
    local bPos_x, bPos_y = b:position()
    if aPos_x == bPos_x then
      return aPos_y < bPos_y
    else
      return aPos_x < bPos_x
    end
  end)

  -- Iterate over the sorted screens
  for _, screen in ipairs(screens) do
    local screenID = screen:getUUID()
    local screen_spaces = allSpaces[screenID]

    -- Ensure the primary screen comes first
    if screen == primaryScreen then
      screen_spaces = allSpaces[screenID]
    end

    if screen_spaces then
      for spaceNumberOnScreen, spaceID in pairs(screen_spaces) do
        if spaceID ~= nil then
          spaces_map[spaceID] = {
            spaceNumberOnScreen = spaceNumberOnScreen,
            spaceNumber = spaceNumber,
            spaceID = spaceID,
            type = spaces.spaceType(spaceID),
            screenID = screenID,
          }
          spaceNumber = spaceNumber + 1
        end
      end
    end
  end

  return spaces_map
end

-- Helper: build translation tables from spaces map
local function buildTranslationTables(spaces_map)
  local space_number_to_id = {}
  local space_id_to_number = {}
  local space_id_to_display = {}

  for space_id, space_info in pairs(spaces_map) do
    if space_info.spaceNumber then
      space_number_to_id[space_info.spaceNumber] = space_id
      space_id_to_number[space_id] = space_info.spaceNumber

      -- Find which display contains this space
      for _, screen in ipairs(hs.screen.allScreens()) do
        local screen_spaces = spaces.spacesForScreen(screen)
        for _, screen_space_id in ipairs(screen_spaces) do
          if screen_space_id == space_id then
            space_id_to_display[space_id] = screen
            break
          end
        end
        if space_id_to_display[space_id] then break end
      end
    end
  end

  return space_number_to_id, space_id_to_number, space_id_to_display
end

-- Create cache table with metatable for lazy loading
local spaces_cache = setmetatable({
  map = nil,
  space_number_to_id = nil,
  space_id_to_number = nil,
  space_id_to_display = nil,
  invalidation_timer = nil
}, {
  __index = function(t, key)
    -- Check if this is a cache field we need to populate
    if key == "map" or key == "space_number_to_id" or key == "space_id_to_number" or key == "space_id_to_display" then
      -- Build the cache data
      local spaces_map_data = buildSpacesMap()
      local space_number_to_id, space_id_to_number, space_id_to_display = buildTranslationTables(spaces_map_data)

      -- Populate all cache fields
      t.map = setmetatable(spaces_map_data, {
        __index = function(map_t, map_key)
          if map_key == "active_spaces" then
            -- Compute active spaces on demand
            local active_spaces = {}
            for _, screen in ipairs(hs.screen.allScreens()) do
              local activeSpaceId = spaces.activeSpaceOnScreen(screen)
              if map_t[activeSpaceId] then
                active_spaces[activeSpaceId] = map_t[activeSpaceId]
              end
            end
            return active_spaces
          end
          return nil
        end
      })
      t.space_number_to_id = space_number_to_id
      t.space_id_to_number = space_id_to_number
      t.space_id_to_display = space_id_to_display

      -- Set up delayed invalidation
      if not t.invalidation_timer then
        t.invalidation_timer = hs.timer.delayed.new(SPACES_MAP_CACHE_TTL, function()
          t.map = nil
          t.space_number_to_id = nil
          t.space_id_to_number = nil
          t.space_id_to_display = nil
        end)
      end
      t.invalidation_timer:start()

      return rawget(t, key)
    end

    -- For other keys, just return nil (let Lua handle it)
    return nil
  end
})

-- Helper: get space ID from space number
local function getSpaceId(space_number)
  return spaces_cache.space_number_to_id[space_number]
end

-- Helper: get space number from space ID
local function getSpaceNumber(space_id)
  return spaces_cache.space_id_to_number[space_id]
end

-- Helper: get display for space ID
local function getSpaceDisplay(space_id)
  return spaces_cache.space_id_to_display[space_id]
end

-- Helper: get current space number
local function getCurrentSpaceNumber()
  local current_space_id = spaces.focusedSpace()
  return getSpaceNumber(current_space_id)
end

local function spaces_map()
  return spaces_cache.map
end
M.spaces_map = spaces_map

-- Public helper functions for space translation
M.getSpaceId = getSpaceId
M.getSpaceNumber = getSpaceNumber
M.getSpaceDisplay = getSpaceDisplay
M.getCurrentSpaceNumber = getCurrentSpaceNumber

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

-- ## Workhorse functions

function M.showDesktopSpaceNumbers()
  local spaces_map = spaces_map()
  clear_space_labels()

  for _,screen in pairs(hs.screen.allScreens()) do
    local activeSpaceOnScreen = spaces.activeSpaceOnScreen(screen)
    if screen:frame() and spaces_map.active_spaces[activeSpaceOnScreen] then
      -- local labeltext = tostring(spaces_map.active_spaces[activeSpaceOnScreen].spaceNumberOnScreen) --OnScreen)
      local labeltext = tostring(spaces_map.active_spaces[activeSpaceOnScreen].spaceNumber)
      local styledtextformat = { color = { white=0, alpha=1 },
        shadow = { offset=0, blurRadius=4, color={ white=1, alpha=1 } },
        font = { size=10 },
        paragraphStyle = { alignment = 'center' },
      }
      local labelstyledtext = hs.styledtext.new(labeltext, styledtextformat)
      local text_size = hs.drawing.getTextDrawingSize(hs.styledtext.new('00', styledtextformat))
      local offsets = { x=4, y=-24 }
      M.space_labels[activeSpaceOnScreen] = hs.drawing.text(
        hs.geometry.rect(
          screen:frame().x + offsets.x,
          screen:frame().y + offsets.y,
          text_size.w, text_size.h
        ),
        labelstyledtext
      ):setBehavior(hs.drawing.windowBehaviors['stationary'])
       :setLevel('help')
       :show()
      M.space_label_backgrounds[activeSpaceOnScreen] = hs.drawing.ellipticalArc(
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
      if not activeSpaceOnScreen then
        logger.w('No active space for screen '.. hs.inspect(screen))
      elseif not screen:frame() then
        logger.w('No :frame() for screen '.. hs.inspect(screen))
      elseif not spaces_map.active_spaces[activeSpaceOnScreen] then
        logger.w('activeSpaceOnScreen '..activeSpaceOnScreen..' not in `spaces_map.active_spaces` '..
          hs.inspect(spaces_map.active_spaces))
      end
    end
  end
end

-- ## Administrivia

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

-- Public method to invalidate spaces cache
-- Call this when spaces are added/removed/reordered
function M:invalidateSpacesMapCache()
  -- Stop any pending invalidation timer
  if spaces_cache.invalidation_timer then
    spaces_cache.invalidation_timer:stop()
  end

  -- Clear all cache data
  spaces_cache.map = nil
  spaces_cache.space_number_to_id = nil
  spaces_cache.space_id_to_number = nil
  spaces_cache.space_id_to_display = nil

  logger.d('Invalidated spaces cache')
end

return M
