package.path = '/Applications/Hammerspoon.app/Contents/Resources/extensions/hs/?.lua;\z
    /Applications/Hammerspoon.app/Contents/Resources/extensions/hs/?/init.lua;\z
    ./?.lua;\z
    ./?/init.lua;\z
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
_G.hs.timer = { delayed = { new = function() end } }
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
_G.hs.configdir = os.getenv("HOME").."/.hammerspoon"
consts = require 'configConsts'
