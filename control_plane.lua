-- # Control Plane replacement: Actions on change of location
--
-- Watch for location changes with
--   ``` lua
--   hs.watchable.watch(
--     "control-plane.location",
--     function(watcher, path, key, old_value, new_value)
--       -- actions
--     end
--   )
--   ```
--
-- ## Location update flow:
--
-- 1. *Callback functions set individual locationFacts
-- 2. locationFactsWatcher restarts actionTimer on change of all but locationFacts.location
--    (callbacks often fire many times when changes are happening - this delays
--    acting until they've calmed down)
-- 3. actionTimer updates locationFacts.location
-- 4. locationWatcher fires actions when locationFacts.location changes

local obj = {}  -- module

obj._logger = hs.logger.new("ControlPlane")
local logger = obj._logger
logger.i("Loading ControlPlane")

local application = hs.application

ACTION_DELAY = 5 -- seconds
KILL_APP_RETRY_DELAY = 15 -- seconds

obj.locationFacts = hs.watchable.new("control-plane", true)
local locationFacts = obj.locationFacts
locationFacts.location = ''
obj.locationFactsWatcher = hs.watchable.watch("control-plane.*",
  function(watcher, path, key, old_value, new_value)
    logger.i("Updating ".. key .." = " .. tostring(new_value))
    if key ~= 'location' then
      obj.actionTimer:start()
    end
  end)
obj.actionTimer = hs.timer.delayed.new(ACTION_DELAY, function() obj.updateLocation() end)
obj.locationWatcher = hs.watchable.watch("control-plane.location",
  function(watcher, path, key, old_value, new_value)
    if old_value ~= "" then obj.previousLocation = old_value end
    obj.actions()
  end)

-- ## Utility functions ##
local function killApp(appname)
  local app, other_app = application.find(appname)
    -- Should check for other_app, but this happens lots, so … we're going to ignore it
  if app then
    logger.i("Closing " .. appname)
    app:kill()
    hs.timer.doAfter(KILL_APP_RETRY_DELAY, function()
      -- sometimes apps are hard to kill, so we try several times
      if app:isRunning() then app:kill9() end
      app = application.find(appname); if app then app:kill9() end
      if application.find(appname) then logger.e("Failed to kill " .. appname) end
    end):start()
  else
    logger.i(appname .. " wasn't open, so I didn't close it")
  end
end
local function resumeApp(appname, alt_appname)
  local app = application.find(appname)
  if app and app:isRunning() then
    logger.i(appname .. " is already running")
  else
    if application.open(appname) then
      logger.i("Resuming " .. appname)
    elseif alt_appname and application.open(alt_appname) then
      logger.i("Resuming " .. alt_appname)
    else
      hs.timer.doAfter(KILL_APP_RETRY_DELAY, function()
        if (not application.find(appname)) and
           (not application.find(alt_appname)) then
          logger.e("Couldn't resume '" .. appname ..
                    (alt_appname and ("' or '" .. alt_appname) or "'"))
        end
      end)
    end
  end
end

-- ## Core functions ##
function obj.updateLocation()
  local inferred_location
  if locationFacts.network and locationFacts.network == 'iPhone' then
    -- At top because iPhone network is expensive; other network inferences below
    logger.i("Inferring iPhone from network")
    inferred_location = locationFacts.network
  elseif locationFacts.monitor then
    logger.i("Inferring ".. locationFacts.monitor .." from monitor")
    inferred_location = locationFacts.monitor
  elseif locationFacts.psu then
    logger.i("Inferring ".. locationFacts.psu .." from psu")
    inferred_location = locationFacts.psu
  else
    logger.i("Inferring … well, failing to infer, so falling back to 'Roaming'")
    inferred_location = 'Roaming'
  end
  locationFacts.location = inferred_location
  return inferred_location
end

function obj.actions()
  if obj.previousLocation then
    logger.i("Exit actions for Location: ".. obj.previousLocation)
    if obj[obj.previousLocation .. 'ExitActions'] then
      obj[obj.previousLocation .. 'ExitActions']()
    end
  end
  if obj[locationFacts.location .. 'EntryActions'] then
    logger.i("Entry actions for Location: ".. locationFacts.location)
    obj[locationFacts.location .. 'EntryActions']()
  end
  obj.previousLocation = nil
end

function obj.location()
  return locationFacts.location
end

-- ## Housekeeping functions ##

function obj:start()
  for k,v in pairs(obj) do
    -- Run all callback functions to initialise locationFacts
    if type(v) == 'function' and k:find("Callback$") then v() end
    -- Starting or resuming all watchers
    if type(v) == 'userdata' and k:find("Watcher$") then
      if v.start ~= nil then
        logger.i("Starting " .. k)
        v:start()
      elseif v.resume ~= nil then
        logger.i("Resuming " .. k)
        v:resume()
      else
        logger.w(k .." doesn't respond to `start()` or `resume()` - it's not active")
      end
    end
  end
  return obj
end

function obj:stop()
  -- Stopping or pausing all watchers
  for k,v in pairs(obj) do
    if type(v) == 'userdata' and k:find("Watcher$") then
      if v.stop ~= nil then
        logger.i("Stopping " .. k)
        v:stop()
      elseif v.pause ~= nil then
        logger.i("Pausing " .. k)
        v:pause()
      else
        logger.w(k .." doesn't respond to `stop()` or `pause()` - so… still doing it's thing")
      end
    end
  end
  return obj
end

-- ## Watchers & Callbacks ##

-- On certain events update locationFacts

-- Network configuration change (iPhone)
function obj.networkConfCallback(_, keys)
  logger.i("Network config changed (" .. hs.inspect(keys) .. ")")
  -- Work out which network we're on
  if (hs.network.reachability.internet():status() &
        hs.network.reachability.flags.reachable) > 0 then
    local pi4, pi6 = hs.network.primaryInterfaces() -- use pi4, ignore pi6
    if pi4 then
      logger.i("Primary interface is ".. pi4)
    else
      logger.w("hs.network.reachability.internet():status() == "..
               hs.network.reachability.internet():status() ..
               " but hs.network.primaryInterfaces() == false… which is confusing")
    end
    if hs.network.interfaceDetails(pi4) and
       hs.network.interfaceDetails(pi4).Link and
       hs.network.interfaceDetails(pi4).Link.Expensive then
      locationFacts.network = 'iPhone'
    elseif hs.fnutils.contains({'blacknode5', 'blacknode2.4'},
                               hs.wifi.currentNetwork()) then
      locationFacts.network = 'Canning'
    elseif hs.wifi.currentNetwork() == 'bellroy' then
      locationFacts.network = 'Fitzroy'
    else
      logger.i("Unknown network")
      locationFacts.network = nil
    end
  else
    logger.i("No primary interface")
    locationFacts.network = nil
  end
end
obj.networkConfWatcher =
  hs.network.configuration.open():setCallback(
    function(_, keys)
      obj.networkConfCallback(_, keys)
    end ):monitorKeys({
  "State:/Network/Interface",
  "State:/Network/Global/IPv4",
  "State:/Network/Global/IPv6",
  "State:/Network/Global/DNS",
})

-- Attached power supply change (Canning, Fitzroy)
function obj.powerCallback()
  logger.i("Power changed")
  if hs.battery.psuSerial() == 3136763 then
    locationFacts.psu = 'Canning'
  elseif hs.battery.psuSerial() == 7411505 then
    locationFacts.psu = 'Fitzroy'
  else
    locationFacts.psu = nil
  end
end
obj.batteryWatcher = hs.battery.watcher.new( function() obj.powerCallback() end )

-- Attached monitor change (Canning, Fitzroy)
function obj.screenCallback()
  logger.i("Monitor changed")
  if hs.screen.find(188814579) then
    locationFacts.monitor = 'Canning'
  elseif hs.screen.find(724061396) then
    locationFacts.monitor = 'Fitzroy'
  elseif hs.screen.find(69992768) then
    locationFacts.monitor = "CanningServer"
  else
    locationFacts.monitor = nil
  end
end
obj.screenWatcher = hs.screen.watcher.new( function() obj.screenCallback() end )


-- ##########################
-- ## Entry & Exit Actions ##
-- ##########################

slack = require 'utilities.slack'

-- iPhone
function obj.iPhoneEntryActions()
  logger.i("Closing Dropbox & GDrive")
  killApp("Dropbox")
  killApp("Backup and Sync from Google")
  killApp("Transmission")
end

function obj.iPhoneExitActions()
  logger.i("Opening Dropbox & GDrive")
  resumeApp("Dropbox")
  resumeApp("Backup and Sync from Google", "Backup and Sync")
end

-- Fitzroy
function obj.FitzroyEntryActions()
  killApp("Transmission")

  slack.setStatus("Fitzroy")

  hs.execute("~/code/utilities/Scripts/mount-external-drives", true)
end

function obj.FitzroyExitActions()
  logger.i("Wifi On")
  hs.wifi.setPower(true)
end

-- Canning
function obj.CanningEntryActions()
  slack.setStatus("Canning")

  hs.execute("~/code/utilities/Scripts/mount-external-drives", true)
end

function obj.CanningExitActions()
  killApp("Transmission")

  logger.i("Wifi On")
  hs.wifi.setPower(true)

  slack.setStatus("")
end

-- Roaming
function obj.RoamingEntryActions()
  killApp("Transmission")
end

return obj
