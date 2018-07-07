package.path = '/Applications/Hammerspoon.app/Contents/Resources/extensions/hs/?/init.lua;'..package.path

_G.hs = {}
_G.hs.logger = require 'logger'
_G.hs.fnutils = require 'fnutils'
_G.hs.inspect = require 'inspect'
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
consts = require 'configConsts'
