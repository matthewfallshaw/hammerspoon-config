-- Log screen & power events

local M = {}

local LOGDIR = os.getenv("HOME").."/log"
local LOGFILE = LOGDIR.."/activities.log"

function M:start()
  M.host = hs.host.localizedName()
  for _,watcher in pairs(M.watchers) do
    watcher:start()
  end
end
function M:stop()
  for _,watcher in pairs(M.watchers) do
    watcher:stop()
  end
end


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
  caffeinate_events[hs.caffeinate.watcher[event]] = event
end

M.watchers = {
  caffeinate = hs.caffeinate.watcher.new(function(event)
    -- write event to log
    log_activity(tostring(caffeinate_events[event]))
  end),
}


return M
