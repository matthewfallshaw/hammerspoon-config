package.path = '/Applications/Hammerspoon.app/Contents/Resources/extensions/hs/?/init.lua;\z
    ../?/?.lua;'.. package.path

_G.hs = {}
_G.hs.logger = require 'logger'
_G.hs.fnutils = require 'fnutils'
_G.hs.inspect = require 'inspect'
_G.hs.timer = { delayed = { new = function() end } }
_G.hs.chooser = {
  new = function() return {
        choices = function() end,
        queryChangedCallback = function() end,
        query = function() return "" end,
      } end,
}
_G.hs.osascript = function() end
_G.hs.hotkey = { setLogLevel = function() end }
_G.hs.window = {}
_G.hs.doc = {
    hsdocs = {
      forceExternalBrowser = function() end
    }
  }
_G.hs.application = { enableSpotlightForNameSearches = function() end }
_G.hs.allowAppleScript = function() end
_G.hs.configdir = os.getenv("HOME").."/.hammerspoon"
consts = require 'configConsts'
