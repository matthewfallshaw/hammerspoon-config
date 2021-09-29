--- === Log utilities ===
--- Ulitities for logging

local log = {}

-- Metadata
log.name = "Log"
log.version = "1.0"
log.author = "Matthew Fallshaw <m@fallshaw.me>"
log.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
log.license = "MIT - https://opensource.org/licenses/MIT"

log.ERROR,log.WARNING,log.INFO,log.DEBUG,log.VERBOSE=1,2,3,4,5

log._logger = hs.logger.new("Log")
local logger = log._logger
logger.i("Loading Log")

function log.new(logger)
  l = { logger = logger }
  setmetatable(l, { __index = log })
  return l
end

local levels = {
  ['error'] = 'e', e = 'e', [log.ERROR] = 'e',
  warning   = 'w', w = 'w', [log.WARNING] = 'w',
  info      = 'i', i = 'i', [log.INFO] = 'i',
  debug     = 'd', d = 'd', [log.DEBUG] = 'd',
  verbose   = 'v', v = 'v', [log.VERBOSE] = 'v',
}
local level_words = {
  e = 'Error', w = 'Warning', i = 'Info', d = 'Debug', v = 'Verbose'
}
function log:and_alert(message, level)
  assert(self, "Sorry, I should be called as a method rather than a function (with ':', not '.').")
  level = level or 'info'
  level = levels[level]
  self.logger[level](message)
  hs.alert.show(level_words[level] ..": ".. message)
end
function log:warning_and_alert(message) log:and_alert(message, 'warning') end
function log:error_and_alert(message) log:and_alert(message, 'error') end

function log.log_to_file(message, file)
  hs.fs.mkdir(os.getenv("HOME").."/log")
  local file_path = file or os.getenv("HOME").."/log/com.matthewfallshaw.activities.log"

  local output_file = assert(io.open(file_path, "a+"))

  output_file:write(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. tostring(message) .."\n")

  output_file:close()
  return true
end

return log
