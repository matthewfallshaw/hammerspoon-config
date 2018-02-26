-- Jettison replacement: Eject ejectable drives on sleep
local logger = hs.logger.new("Jettison")
logger.i("Loading Jettison sleep watcher")

M = {}

M._jettison_causing_sleep = false

function M.isAnExternalDrivePresent()
  local output, status, return_type, return_code = hs.execute("diskutil list | grep external")
  return status
end
function M.isAnExternalDriveMounted()
  local output, status, return_type, return_code = hs.execute("for i in $(diskutil list | grep 'external, virtual' | cut -d' ' -f1); do diskutil info $i | grep -q 'Mounted.*Yes' && echo $i; done")
  return output ~= ""
end
function M.ejectExternalDrivesAndSleep()
  u.log_and_alert(logger, "Ejecting drives before sleep…")
  local output, status, return_type, return_code = hs.execute("~/code/utilities/Scripts/eject-external-drives")
  if status then
    u.log_and_alert(logger, "… drives ejected.")
    M._jettison_causing_sleep = true
    hs.caffeinate.systemSleep()
    M._jettison_causing_sleep = false
  else
    u.log_and_alert(logger, "… but the drives didn't eject: " .. tostring(output), " - return code: " .. tostring(return_code))
  end
end

function M.mountExternalDrives()
  if M.isAnExternalDrivePresent then
    local output, status, return_type, return_code = hs.execute("~/code/utilities/Scripts/mount-external-drives")
    if status then
      u.log_and_alert(logger, "Drives remounted after sleep.")
    else
      u.log_and_alert(logger, "Drives failed to remount after sleep: " .. tostring(output) .. " - return code: " .. tostring(return_code))
    end
  end
end

function M.sleepWatcherCallback(event)
  if event == hs.caffeinate.watcher.systemWillSleep and not M._jettison_causing_sleep then
    if M.isAnExternalDriveMounted() then
      hs.caffeinate.declareUserActivity()  -- prevent sleep to give us time to eject drives
      M.ejectExternalDrivesAndSleep()
    end
  elseif event == hs.caffeinate.watcher.systemDidWake then
    M.mountExternalDrives()
  end
end
M.sleepWatcher = hs.caffeinate.watcher.new(M.sleepWatcherCallback)

function M:start()
  logger.i("Starting Jettison sleep watcher")
  M.sleepWatcher:start()
end

return M
