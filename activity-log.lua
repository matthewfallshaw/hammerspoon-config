local M = {}

local caffeinate_events = {
  "screensaverDidStart",
  "screensaverDidStop",
  "screensaverWillStop",
  "screensDidLock",
  "screensDidSleep",
  "screensDidUnlock",
  "screensDidWake",
  "sessionDidBecomeActive",
  "sessionDidResignActive",
  "systemDidWake",
  "systemWillPowerOff",
  "systemWillSleep",
}
for _,event in pairs(caffeinate_events) do
  caffeinate_events[hs.caffeinate.watcher[event]] = event
end

M.watchers = {
  caffeinate = hs.caffeinate.watcher.new(function(event)
    -- write event to log
    u.log_to_file("Activity: ".. tostring(caffeinate_events[event]))
  end),
}

function M:start()
  for _,watcher in pairs(M.watchers) do
    watcher:start()
  end
end
function M:stop()
  for _,watcher in pairs(M.watchers) do
    watcher:stop()
  end
end

return M
