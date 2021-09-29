-- Log screen & power events

local fun = require 'fun'

local M = {}

local LOGDIR = os.getenv("HOME").."/log"
local LOGFILE = LOGDIR.."/activities.log"
M.LOGDIR = LOGDIR
M.LOGFILE = LOGFILE

local caffeinate_watcher = hs.caffeinate.watcher


local function dirExists(filepath)
  return hs.fs.attributes(filepath, 'mode') == 'directory'
end

if not dirExists(LOGDIR) then hs.fs.mkdir(LOGDIR) end

local function log_activity(message)
  local output_file = assert(io.open(LOGFILE, "a+"))

  output_file:write(os.date("%Y-%m-%d %H:%M:%S") ..' '.. M.host ..' activity-log '.. tostring(message) .."\n")

  output_file:close()
  return true
end

local caffeinate_events = {
  "screensaverDidStart", "screensaverDidStop", "screensaverWillStop",
  "screensDidLock", "screensDidUnlock",
  "screensDidSleep", "screensDidWake",
  "sessionDidBecomeActive", "sessionDidResignActive",
  "systemWillSleep", "systemWillPowerOff", "systemDidWake",
}
for _,event in pairs(caffeinate_events) do
  caffeinate_events[caffeinate_watcher[event]] = event
end

M.watchers = {
  caffeinate = caffeinate_watcher.new(function(event)
    -- write event to log
    log_activity(tostring(caffeinate_events[event]))
  end),
}

function M:start()
  M.host = hs.host.localizedName()
  for _,watcher in pairs(self.watchers) do
    watcher:start()
  end
  log_activity('Start:'..
    fun.reduce(function(acc,k) return acc == '' and k or acc..','..k end, '', self.watchers))
end
function M:stop()
  for _,watcher in pairs(self.watchers) do
    watcher:stop()
  end
  log_activity('Stop:'..
    fun.reduce(function(acc,k) return acc == '' and k or acc..','..k end, '', self.watchers))
end


return M
