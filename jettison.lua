-- Jettison replacement: Eject ejectable drives on sleep
local logger = hs.logger.new("Jettison")
logger.i("Loading Jettison sleep watcher")

M = {}

log = require('utilities.log').new(logger)

M._jettison_causing_sleep = false

function M.isAnExternalDrivePresent()
  local output, status, return_type, return_code =
    hs.execute("diskutil list | grep external")
  return status == true
end
function M.isAnExternalDriveMounted()
  local output, status, return_type, return_code =
    hs.execute("for i in $(diskutil list | grep 'external, virtual' | \z
      cut -d' ' -f1); do diskutil info $i | \z
      grep -q 'Mounted.*Yes' && echo $i; done")
  return output ~= ""
end

function M.ejectExternalDrivesAndSleep()
  if M._jettison_causing_sleep == true then
    log.and_alert("Asked to sleep while Jettison still trying to cause sleep… aborting.")
    return nil
  end
  log.and_alert("Ejecting drives before sleep…")
  local output, status, return_type, return_code =
    hs.execute("~/code/utilities/Scripts/eject-external-drives")
  if status then
    log.and_alert("… drives ejected.")
    M._jettison_causing_sleep = true
    hs.caffeinate.systemSleep()
    M._jettison_causing_sleep = false
  else
    log.warning_and_alert("… but the drives didn't eject: ".. tostring(output) ..
      " - return code: " .. tostring(return_code))
  end
end

function M.mountExternalDrives()
  if M.isAnExternalDrivePresent() then
    local output, status, return_type, return_code =
      hs.execute("~/code/utilities/Scripts/mount-external-drives")
    if status then
      log.and_alert("Drives remounted after sleep.")
    else
      log.warning_and_alert("Drives failed to remount after sleep: "..
        tostring(output) .." - return code: " .. tostring(return_code))
    end
  end
end

function M.sleepWatcherCallback(event)
  if (event == hs.caffeinate.watcher.systemWillSleep) and
    (not M._jettison_causing_sleep) then
    if M.isAnExternalDriveMounted() then
      hs.caffeinate.declareUserActivity()  -- prevent sleep to give us time to eject drives
      M.ejectExternalDrivesAndSleep()
    end
  elseif event == hs.caffeinate.watcher.systemDidWake then
    M.mountExternalDrives()
  -- else do nothing
  end
end
M.sleepWatcher = hs.caffeinate.watcher.new(M.sleepWatcherCallback)

function M:start()
  logger.i("Starting Jettison sleep watcher")
  self.sleepWatcher:start()
end

return M
