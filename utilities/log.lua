--- === Log utilities ===
--- Ulitities for logging

local log = {}

-- Metadata
log.name = "Log"
log.version = "1.0"
log.author = "Matthew Fallshaw <m@fallshaw.me>"
log.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
log.license = "MIT - https://opensource.org/licenses/MIT"

log._logger = hs.logger.new("Log")
local logger = log._logger
logger.i("Loading Log")

function log.new(logger)
  l = { logger = logger }
  setmetatable(l, { __index = log })
  return l
end

local levels = {
  ['error'] = 'e', e = 'e',
  warning   = 'w', w = 'w',
  info      = 'i', i = 'i',
  debug     = 'd', d = 'd',
  verbose   = 'v', v = 'v',
}
local level_words = {
  e = 'Error', w = 'Warning', i = 'Info', d = 'Debug', v = 'Verbose'
}
function log:and_alert(message, level)
  level = level or 'info'
  local level = levels[level]
  self.logger[level](message)
  hs.alert.show(level_words[level] ..": ".. message)
end
function log:warning_and_alert(message) log:and_alert(message, 'warning') end
function log:error_and_alert(message) log:and_alert(message, 'error') end

return log
