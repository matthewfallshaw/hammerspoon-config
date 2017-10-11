local logger = hs.logger.new("ControlPlane")
logger.i("Loading ControlPlane")

local obj = {}

obj.cachedLocation = ''
obj.locationFacts = {}

function obj.killApp(appname)
  local app, other_app = hs.application.find(appname)
    -- Should check for other_app, but this happens lots, so … we're going to ignore it
  if app then
    logger.i("Closing " .. appname)
    app:kill()
    hs.timer.doAfter(15, function()
      -- sometimes apps are hard to kill, so we try several times
      if app:isRunning() then app:kill9() end
      app = hs.application.find(appname); if app then app:kill9() end
      if hs.application.find(appname) then logger.e("Failed to kill " .. appname) end
    end):start()
  else
    logger.i(appname .. " wasn't open, so I didn't close it")
  end
end

function obj.resumeApp(appname, alt_appname)
  -- optional alt_appname
  local app = hs.application.find(appname)
  if app and app:isRunning() then
    logger.i(appname .. " is already running")
  else
    if hs.application.open(appname) then
      logger.i("Resuming " .. appname)
    elseif alt_appname and hs.application.open(alt_appname) then
      logger.i("Resuming " .. alt_appname)
    else
      hs.timer.doAfter(15, function()
        if (not hs.application.find(appname)) and (not hs.application.find(alt_appname)) then
          logger.e("Couldn't resume '" .. appname .. (alt_appname and ("' or '" .. alt_appname) or "'"))
        end
      end)
    end
  end
end

function obj.location()
  if obj.locationFacts['network'] and obj.locationFacts['network'] == 'iPhone' then
    -- At top because iPhone network is expensive; other network inferences below
    logger.i("Inferring iPhone from network")
    return obj.locationFacts['network']
  elseif obj.locationFacts['monitor'] then
    logger.i("Inferring ".. obj.locationFacts['monitor'] .." from monitor")
    return obj.locationFacts['monitor']
  elseif obj.locationFacts['psu'] then
    logger.i("Inferring ".. obj.locationFacts['psu'] .." from psu")
    return obj.locationFacts['psu']
  else
    logger.i("Inferring … well, failing to infer, so falling back to 'Roaming'")
    return 'Roaming'
  end
end

function obj.queueActions()
  obj.actionTimer:start()
end

function obj.actions()
  local newLocation = obj.location()
  if obj.cachedLocation ~= newLocation then
    logger.i("Actions for cachedLocation: ".. obj.cachedLocation ..", newLocation: ".. newLocation)
    if obj.cachedLocation ~= '' then
      logger.i(obj.cachedLocation .. " Exit")
      if obj[obj.cachedLocation .. 'ExitActions'] then
        obj[obj.cachedLocation .. 'ExitActions']()  -- Exit actions for current location
      end
    end
    logger.i(newLocation .. " Entry")
    if obj[newLocation .. 'EntryActions'] then
      obj[newLocation .. 'EntryActions']()     -- Entry actions for new location
    end
    obj.cachedLocation = newLocation
  else
    logger.i("(location unchanged: ".. obj.cachedLocation ..")")
  end
end
obj.actionTimer = hs.timer.delayed.new(5, obj.actions)

function obj:start()
  for k,v in pairs(obj) do
    -- Run all callback functions to initialise obj.locationFacts
    if type(v) == 'function' and string.find(k, "Callback$") then
      v()
    end
    if type(v) == 'userdata' and string.find(k, "Watcher$") then
      -- Start all watchers
      logger.i("Starting " .. k)
      v:start()
    end
  end
  obj.queueActions()
  return obj
end

-- ## Watchers & Callbacks ##

-- On certain events update locationFacts and trigger a location check

-- Network configuration change (iPhone)
function obj.networkConfCallback(_, keys)
  logger.i("Network config changed (" .. hs.inspect(keys) .. ")")
  local old_network = obj.locationFacts['network']
  -- Work out which network we're on
  if (hs.network.reachability.internet():status() & hs.network.reachability.flags.reachable) > 0 then
    local pi4, pi6 = hs.network.primaryInterfaces() -- use pi4, ignore pi6
    if pi4 then
      logger.i("Primary interface is ".. pi4)
    else
      logger.w("hs.network.reachability.internet():status() == ".. hs.network.reachability.internet():status() .." but hs.network.primaryInterfaces() == false… which is confusing")
    end
    if hs.network.interfaceDetails(pi4).Link and hs.network.interfaceDetails(pi4).Link.Expensive then
      obj.locationFacts['network'] = 'iPhone'
    elseif hs.fnutils.contains({'blacknode5', 'blacknode2.4'}, hs.wifi.currentNetwork()) then
      obj.locationFacts['network'] = 'Canning'
    elseif hs.wifi.currentNetwork() == 'bellroy' then
      obj.locationFacts['network'] = 'Fitzroy'
    else
      logger.i("Unknown network")
      obj.locationFacts['network'] = nil
    end
  else
    logger.i("No primary interface")
    obj.locationFacts['network'] = nil
  end
  if obj.locationFacts['network'] ~= old_network then
    logger.i("recording network = " .. tostring(obj.locationFacts['network']))
    obj.queueActions()
  end
end
obj.networkConfWatcher = hs.network.configuration.open():setCallback( function(_, keys) obj.networkConfCallback(_, keys) end ):monitorKeys({
  "State:/Network/Interface",
  "State:/Network/Global/IPv4",
  "State:/Network/Global/IPv6",
  "State:/Network/Global/DNS",
})

-- Attached power supply change (Canning, Fitzroy)
function obj.powerCallback()
  logger.i("Power changed")
  local old_power = obj.locationFacts['psu']
  if hs.battery.psuSerial() == 3136763 then
    obj.locationFacts['psu'] = 'Canning'
  elseif hs.battery.psuSerial() == 7411505 then
    obj.locationFacts['psu'] = 'Fitzroy'
  else
    obj.locationFacts['psu'] = nil
  end
  if obj.locationFacts['psu'] ~= old_power then
    logger.i("recording psu = " .. tostring(obj.locationFacts['psu']))
    obj.queueActions()
  end
end
obj.batteryWatcher = hs.battery.watcher.new( function() obj.powerCallback() end )

-- Attached monitor change (Canning, Fitzroy)
function obj.screenCallback()
  logger.i("Monitor changed")
  local old_monitor = obj.locationFacts['monitor']
  if hs.screen.find(188814579) then
    obj.locationFacts['monitor'] = 'Canning'
  elseif hs.screen.find(724061396) then
    obj.locationFacts['monitor'] = 'Fitzroy'
  elseif hs.screen.find(69992768) then
    obj.locationFacts['monitor'] = "CanningServer"
  else
    obj.locationFacts['monitor'] = nil
  end
  if obj.locationFacts['monitor'] ~= old_monitor then
    logger.i("recording monitor = " .. tostring(obj.locationFacts['monitor']))
    obj.queueActions()
  end
end
obj.screenWatcher = hs.screen.watcher.new( function() obj.screenCallback() end )


-- ## Utility functions ##
function obj.slackStatus(location)
  if location == "" then
    logger.i("Slack status -")
  else
    logger.i("Slack status " .. location)
  end
  result = hs.task.new("~/bin/slack-status", obj.slackStatusRetry, function(...) return false end, {location}):start()
end

function obj.slackStatusRetry(exitCode, stdOut, stdErr)
  if exitCode ~= 0 then  -- if task fails, try again after 30s
    logger.w("Stack status failed - exitCode:" .. tostring(exitCode) .. " stdOut:" .. tostring(stdOut) .. " stdErr:" .. tostring(stdErr))
    hs.timer.doAfter(30, function() hs.task.new("~/bin/slack-status", obj.slackStatusRetry, function(...) return false end, {obj.cachedLocation}) end):start()
  end
end


-- ##########################
-- ## Entry & Exit Actions ##
-- ##########################

-- iPhone
function obj.iPhoneEntryActions()
  logger.i("Pausing Crashplan, closing Dropbox & GBackup")
  local output, status = hs.execute("/Users/matt/bin/crashplan-pause")
  if not status then
    logger.e("Crashplan may have failed to exit")
  end
  obj.killApp("Dropbox")
  obj.killApp("Backup and Sync from Google")
  obj.killApp("Transmission")
end

function obj.iPhoneExitActions()
  logger.i("Resuming Crashplan, opening Dropbox & GDrive")
  local output, status = hs.execute("/Users/matt/bin/crashplan-resume")
  if not status then
    logger.e("Crashplan may have failed to resume")
  end
  obj.resumeApp("Dropbox")
  obj.resumeApp("Backup and Sync from Google", "Backup and Sync")
end

-- Fitzroy
function obj.FitzroyEntryActions()
  obj.killApp("Transmission")

  obj.slackStatus("Fitzroy")

  hs.execute("~/code/utils/Scripts/mount-external-drives", true)
end

function obj.FitzroyExitActions()
  logger.i("Wifi On")
  hs.wifi.setPower(true)
end

-- Canning
function obj.CanningEntryActions()
  obj.slackStatus("Canning")

  hs.execute("~/code/utils/Scripts/mount-external-drives", true)
end

function obj.CanningExitActions()
  obj.killApp("Transmission")

  logger.i("Wifi On")
  hs.wifi.setPower(true)

  obj.slackStatus("")
end

-- Roaming
function obj.RoamingEntryActions()
  obj.killApp("Transmission")
end

return obj
