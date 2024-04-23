-- Hyper keybindings
--
-- Karabiner to bind something (I use right-option) to one of the unused function keys

-- luacheck: globals hs

local M = { hotkeys={} }

M._logger = hs.logger.new("Hyper hotkeys")
local logger = M._logger
logger.i("Loading Hyper hotkeys")

-- # Usage
-- hyper = require('hyper')
-- hyper:start()

HOTKEY = 'F18'
HOTKEY_VIRTUAL = 'F17'

M.hyperMode = hs.hotkey.modal.new({}, HOTKEY_VIRTUAL)

function M.bindKey(mods, key, handler)
  M.hyperMode:bind(mods, key, handler)
end

local mods = {'⌃', '⇧', '⌥', '⌘'}
local function combinations(n, p)
  if p == 0 then
    return {{}}
  end
  local ii = 1
  local combos = {}
  local combo = {}
  while #combo < p do
    if ii <= n then
      table.insert(combo, ii)
      ii = ii + 1
    else
      if #combo == 0 then
        break
      else
        ii = table.remove(combo, #combo) + 1
      end
    end

    if #combo == p then
      table.insert(combos, {table.unpack(combo)})
      ii = table.remove(combo, #combo) + 1
    end
  end
  return combos
end
M.combinations = combinations

local function map(tbl, f)
  local t = {}
  for k,v in pairs(tbl) do
    t[k] = f(v)
  end
  return t
end

local modifier_combos = {}
for n=0,4 do
  for _, v in ipairs(combinations(4, n)) do
    -- print(mods[v[1]], mods[v[2]], mods[v[3]])
    -- print(table.unpack(v))
    table.insert(modifier_combos, map(v, function(x) return mods[x] end))
  end
end

function M.enter()
  M.hyperMode:enter()
end

function M.exit()
  M.hyperMode:exit()
end

function M:start()
  for _, mm in ipairs(modifier_combos) do
    table.insert(M.hotkeys, hs.hotkey.bind(mm, HOTKEY, M.enter, M.exit))
  end
end

function M:stop()
  for _, mm in ipairs(M.hotkeys) do
    mm:delete()
  end
end

return M
