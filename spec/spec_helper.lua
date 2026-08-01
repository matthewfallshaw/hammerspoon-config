-- Config paths first, then Hammerspoon's bundled extensions — the same order
-- the app itself uses (Hammerspoon.app/Contents/Resources/setup.lua). It
-- matters: the app ships an `hs/notify.lua`, so searching extensions first
-- would shadow this config's own `notify/` module in specs but not at runtime.
package.path = './?.lua;\z
    ./?/init.lua;\z
    /Applications/Hammerspoon.app/Contents/Resources/extensions/hs/?.lua;\z
    /Applications/Hammerspoon.app/Contents/Resources/extensions/hs/?/init.lua;\z
    ' .. package.path

_G.hs = {}
_G.hs.logger = {
  new = function(name, loglevel)
    return {
      setLogLevel = function() end,
      d = function() end,
      i = function() end,
      w = function() end,
      e = function() end,
      f = function() end
    }
  end,
  setGlobalLogLevel = function() end,
  defaultLogLevel = 'warning'
}
_G.hs.fnutils = require 'fnutils'
_G.hs.inspect = require 'inspect'
_G.hs.timer = {
  delayed = { new = function() end },
  _timers = {},
  _now = 0,
  doAfter = function(seconds, fn)
    local timer = {
      seconds = seconds,
      fn = fn,
      stopped = false,
      stop = function(self)
        self.stopped = true
        return self
      end,
      running = function(self)
        return not self.stopped
      end,
    }
    table.insert(_G.hs.timer._timers, timer)
    return timer
  end,
  secondsSinceEpoch = function()
    return _G.hs.timer._now
  end,
  _reset = function()
    _G.hs.timer._timers = {}
    _G.hs.timer._now = 0
  end,
}
_G.hs.chooser = {
  new = function(completionFn) 
    local chooser = {
      choices = function(self) return self end,
      queryChangedCallback = function(self) return self end,
      query = function() return "" end,
      searchSubText = function(self) return self end,
    }
    return chooser
  end,
}
_G.hs.osascript = function() end
_G.hs.execute = function() return "" end
_G.hs.hotkey = { setLogLevel = function() end }
_G.hs.window = {
  filter = {
    setLogLevel = function() end
  }
}
_G.hs.filter = {}
_G.hs.doc = {
    hsdocs = {
      forceExternalBrowser = function() end,
      moduleEntitiesInSidebar = function() end
    }
  }
_G.hs.application = { enableSpotlightForNameSearches = function() end }
_G.hs.allowAppleScript = function() end
_G.hs.watchable = {
  new = function() return {
    change = function() end
  } end,
  watch = function() return {} end
}
_G.hs.spaces = {
  allSpaces = function() return {} end,
  moveWindowToSpace = function() end
}
-- Mock the hs.spaces module for require()
package.preload["hs.spaces"] = function()
  return _G.hs.spaces
end
-- hs.canvas: recording mock. Records every operation so specs can assert on
-- geometry/text without pixels. Chainable methods return the canvas itself.
_G.hs.canvas = {
  _instances = {},
  windowLevels = {
    desktop = 0,
    desktopIcon = 1,
    normal = 3,
    floating = 4,
    tornOffMenu = 5,
    modalPanel = 8,
    utility = 19,
    dock = 20,
    mainMenu = 24,
    overlay = 25,
    help = 26,
    dragging = 27,
    screenSaver = 1000,
  },
  windowBehaviors = {
    default = 0,
    canJoinAllSpaces = 1,
    moveToActiveSpace = 2,
    transient = 3,
    stationary = 16,
    participatesInCycle = 32,
    ignoresCycle = 64,
    fullScreenPrimary = 128,
    fullScreenAuxiliary = 256,
  },
  compositeTypes = {
    clear = 1,
    copy = 2,
    sourceOver = 3,
    sourceIn = 4,
    sourceOut = 5,
    sourceAtop = 6,
  },
}
_G.hs.canvas.new = function(frame)
  local canvas = {
    _elements = {},
    _frame = frame,
    _calls = {},
    _visible = false,
    _deleted = false,
    _mouseCallback = nil,
    _level = nil,
    _behavior = nil,
    _clickActivating = nil,
    _canvasMouseEvents = nil,
    _alpha = nil,
    _wantsLayer = nil,
  }
  local mt = {}

  local function recordCall(self, name, ...)
    table.insert(self._calls, { name = name, args = { ... } })
  end

  function canvas:appendElements(...)
    local args = { ... }
    for _, el in ipairs(args) do
      table.insert(self._elements, el)
    end
    recordCall(self, 'appendElements', ...)
    return self
  end

  function canvas:replaceElements(...)
    self._elements = { ... }
    recordCall(self, 'replaceElements', ...)
    return self
  end

  function canvas:insertElement(el, idx)
    if idx then
      table.insert(self._elements, idx, el)
    else
      table.insert(self._elements, el)
    end
    recordCall(self, 'insertElement', el, idx)
    return self
  end

  function canvas:removeElement(idx)
    if idx then
      table.remove(self._elements, idx)
    else
      table.remove(self._elements)
    end
    recordCall(self, 'removeElement', idx)
    return self
  end

  function canvas:frame(f)
    if f == nil then
      return self._frame
    end
    self._frame = f
    recordCall(self, 'frame', f)
    return self
  end

  function canvas:topLeft(p)
    if p == nil then
      return self._topLeft
    end
    self._topLeft = p
    recordCall(self, 'topLeft', p)
    return self
  end

  function canvas:size(s)
    if s == nil then
      return self._size
    end
    self._size = s
    recordCall(self, 'size', s)
    return self
  end

  function canvas:show(fade)
    self._visible = true
    recordCall(self, 'show', fade)
    return self
  end

  function canvas:hide(fade)
    self._visible = false
    recordCall(self, 'hide', fade)
    return self
  end

  function canvas:delete(fade)
    self._deleted = true
    self._visible = false
    recordCall(self, 'delete', fade)
    return self
  end

  function canvas:level(l)
    if l == nil then
      return self._level
    end
    self._level = l
    recordCall(self, 'level', l)
    return self
  end

  function canvas:behavior(b)
    if b == nil then
      return self._behavior
    end
    self._behavior = b
    recordCall(self, 'behavior', b)
    return self
  end

  function canvas:behaviorAsLabels(t)
    if t == nil then
      return self._behaviorAsLabels
    end
    self._behaviorAsLabels = t
    recordCall(self, 'behaviorAsLabels', t)
    return self
  end

  function canvas:clickActivating(bool)
    if bool == nil then
      return self._clickActivating
    end
    self._clickActivating = bool
    recordCall(self, 'clickActivating', bool)
    return self
  end

  function canvas:mouseCallback(fn)
    if fn == nil then
      return self._mouseCallback
    end
    self._mouseCallback = fn
    recordCall(self, 'mouseCallback', fn)
    return self
  end

  function canvas:canvasMouseEvents(...)
    self._canvasMouseEvents = { ... }
    recordCall(self, 'canvasMouseEvents', ...)
    return self
  end

  function canvas:alpha(a)
    if a == nil then
      return self._alpha
    end
    self._alpha = a
    recordCall(self, 'alpha', a)
    return self
  end

  function canvas:wantsLayer(b)
    if b == nil then
      return self._wantsLayer
    end
    self._wantsLayer = b
    recordCall(self, 'wantsLayer', b)
    return self
  end

  -- Indexing/assignment by element index: canvas[1] = {...}, canvas[1].frame
  mt.__index = function(t, key)
    if type(key) == 'number' then
      return rawget(t, '_elements')[key]
    end
    return rawget(canvas, key)
  end
  mt.__newindex = function(t, key, value)
    if type(key) == 'number' then
      rawget(t, '_elements')[key] = value
    else
      rawset(t, key, value)
    end
  end
  setmetatable(canvas, mt)

  table.insert(_G.hs.canvas._instances, canvas)
  return canvas
end
_G.hs.canvas._reset = function()
  _G.hs.canvas._instances = {}
end

-- hs.eventtap: records start/stop state; specs invoke stored callbacks directly.
_G.hs.eventtap = {
  _instances = {},
  event = {
    types = {
      gesture = 29,
      keyDown = 10,
      keyUp = 11,
      leftMouseDown = 1,
      leftMouseUp = 2,
      mouseMoved = 5,
      flagsChanged = 12,
      scrollWheel = 22,
    },
  },
}
_G.hs.eventtap.new = function(types, fn)
  local tap = {
    _types = types,
    _fn = fn,
    _started = false,
  }
  function tap:start()
    self._started = true
    return self
  end
  function tap:stop()
    self._started = false
    return self
  end
  function tap:isEnabled()
    return self._started
  end
  table.insert(_G.hs.eventtap._instances, tap)
  return tap
end
_G.hs.eventtap._reset = function()
  _G.hs.eventtap._instances = {}
end

-- hs.settings: in-memory key/value store.
_G.hs.settings = {
  _store = {},
}
_G.hs.settings.set = function(key, value)
  _G.hs.settings._store[key] = value
end
_G.hs.settings.get = function(key)
  return _G.hs.settings._store[key]
end
_G.hs.settings.clear = function(key)
  _G.hs.settings._store[key] = nil
end
_G.hs.settings.getKeys = function()
  local keys = {}
  for k, _ in pairs(_G.hs.settings._store) do
    table.insert(keys, k)
  end
  return keys
end
_G.hs.settings._reset = function()
  _G.hs.settings._store = {}
end

-- hs.mouse
_G.hs.mouse = {
  _position = { x = 0, y = 0 },
}
_G.hs.mouse.absolutePosition = function()
  return _G.hs.mouse._position
end

-- hs.screen
_G.hs.screen = {
  _primaryFrame = { x = 0, y = 0, w = 1920, h = 1080 },
}
local function makeMockScreen()
  return {
    frame = function() return _G.hs.screen._primaryFrame end,
    fullFrame = function() return _G.hs.screen._primaryFrame end,
    name = function() return "Mock Screen" end,
  }
end
_G.hs.screen.primaryScreen = function()
  return makeMockScreen()
end
_G.hs.screen.mainScreen = function()
  return makeMockScreen()
end

-- hs.base64: real, working standard base64 codec (round-trips arbitrary bytes).
_G.hs.base64 = {}
do
  local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local charToIndex = {}
  for i = 1, #alphabet do
    charToIndex[alphabet:sub(i, i)] = i - 1
  end

  _G.hs.base64.encode = function(data)
    data = data or ''
    local result = {}
    local len = #data
    local i = 1
    while i <= len do
      local b1 = data:byte(i)
      local b2 = data:byte(i + 1)
      local b3 = data:byte(i + 2)

      local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)

      local c1 = math.floor(n / 262144) % 64
      local c2 = math.floor(n / 4096) % 64
      local c3 = math.floor(n / 64) % 64
      local c4 = n % 64

      table.insert(result, alphabet:sub(c1 + 1, c1 + 1))
      table.insert(result, alphabet:sub(c2 + 1, c2 + 1))
      table.insert(result, b2 and alphabet:sub(c3 + 1, c3 + 1) or '=')
      table.insert(result, b3 and alphabet:sub(c4 + 1, c4 + 1) or '=')

      i = i + 3
    end
    return table.concat(result)
  end

  _G.hs.base64.decode = function(data)
    data = data or ''
    data = data:gsub('[^' .. alphabet .. '=]', '')
    local result = {}
    local i = 1
    local len = #data
    while i <= len do
      local c1 = data:sub(i, i)
      local c2 = data:sub(i + 1, i + 1)
      local c3 = data:sub(i + 2, i + 2)
      local c4 = data:sub(i + 3, i + 3)

      local n1 = charToIndex[c1] or 0
      local n2 = charToIndex[c2] or 0
      local n3 = charToIndex[c3]
      local n4 = charToIndex[c4]

      local n = n1 * 262144 + n2 * 4096 + (n3 or 0) * 64 + (n4 or 0)

      local b1 = math.floor(n / 65536) % 256
      local b2 = math.floor(n / 256) % 256
      local b3 = n % 256

      table.insert(result, string.char(b1))
      if c3 ~= '' and c3 ~= '=' then
        table.insert(result, string.char(b2))
      end
      if c4 ~= '' and c4 ~= '=' then
        table.insert(result, string.char(b3))
      end

      i = i + 4
    end
    return table.concat(result)
  end
end

-- hs.host
_G.hs.host = {
  _interfaceStyle = nil,
}
_G.hs.host.interfaceStyle = function()
  return _G.hs.host._interfaceStyle
end

-- hs.drawing / hs.styledtext
_G.hs.drawing = _G.hs.drawing or {}
_G.hs.drawing.getTextDrawingSize = function(text, _style)
  return { w = #text * 7, h = 15 }
end
_G.hs.styledtext = _G.hs.styledtext or {}

-- hs.image
_G.hs.image = {}
_G.hs.image.imageFromPath = function(p)
  if p == nil then return nil end
  return { _path = p }
end
_G.hs.image.imageFromName = function(n)
  if n == nil then return nil end
  return { _name = n }
end

_G.hs.configdir = os.getenv("HOME").."/.hammerspoon"
consts = require 'configConsts'
