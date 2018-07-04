package.path = '/Applications/Hammerspoon.app/Contents/Resources/extensions/hs/?/init.lua;'..package.path

_G.hs = {
  logger = {
    setGlobalLogLevel = function() end,
    new = function() end,
  },
  hotkey = { setLogLevel = function() end },
  window = {},
  doc = {
    hsdocs = {
      forceExternalBrowser = function() end
    }
  },
  application = { enableSpotlightForNameSearches = function() end },
  allowAppleScript = function() end,
  fnutils = require 'fnutils',
}
consts = require 'configConsts'
