-- # Control Plane replacement: Actions on change of location
--
-- Watch for location changes with
--   ``` lua
--   hs.watchable.watch(
--     'control_plane', 'location',
--     function(watcher, path, key, old_value, new_value)
--       -- actions
--     end
--   )
--   hs.watchable.watch(
--     'control_plane', 'wifi_security',
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
--
-- Publishes wifi_security and wifi_ssid in its hs.watchable since it's tracking wifi changes.

local obj = {}  -- module
local function background(launchPath, arguments)
  if arguments then hs.task.new(launchPath, nil, arguments)
  else hs.task.new(launchPath, nil)
  end
end

obj._logger = hs.logger.new('ControlPlane')
local logger = obj._logger
logger.setLogLevel('info')
logger.i('Loading ControlPlane')

local ACTION_DELAY = 5 -- seconds
local KILL_APP_RETRY_DELAY = 30 -- seconds

obj.watchers = {}

obj.locationFactsPriority = { 'monitor', 'network', 'psu'}
local locationFactsPriority = obj.locationFactsPriority

local application = hs.application

obj.locationFacts = hs.watchable.new('control_plane', true)
local locationFacts = obj.locationFacts
locationFacts.location = ''
obj.locationFactsWatcher = hs.watchable.watch('control_plane.*',
  function(_, _, key, _, new_value)
    logger.i('Updating '.. key ..' = ' .. tostring(new_value))
    if key ~= 'location' then
      obj.actionTimer:start()
    end
  end)
obj.actionTimer = hs.timer.delayed.new(ACTION_DELAY, function() obj.updateLocation() end)
obj.locationWatcher = hs.watchable.watch('control_plane.location',
  function(_, _, _, old_value, _)
    if old_value ~= '' then obj.previousLocation = old_value end
    obj.actions()
  end)

-- ## Utility functions ##
require 'utilities.table'
local function delayedRetry(delay, functions)
-- Run first of functions after delay, stop if it returns true, keep going if false
  if (#functions == 0) then return true end
  hs.timer.doAfter(delay, function()
    if (not table.head(functions)()) then
      delayedRetry(delay, table.tail(functions))
    end
  end)
end

local function killApp(app_hint)
  local apps = table.pack(application.find(app_hint))
  if apps.n == 0 then
    logger.i(app_hint .. " wasn't open, so I didn't close it")
  else
    hs.fnutils.ieach(apps, function(app)
      logger.i('Closing ' .. app_hint)
      app:kill()
      local killer = function()
        if app:isRunning() then
          app:kill9(); return false
        else
          return true
        end
      end
      -- sometimes apps are hard to kill, so we try several times
      delayedRetry(KILL_APP_RETRY_DELAY, {
        killer, killer, killer,
        function() logger.e('Failed to kill ' .. app:name()) end})
    end)
  end
end
local function resumeApp(app_hint, alt_appname)
  local app = application.find(app_hint)
  if app and app:isRunning() then
    logger.i(app_hint .. ' is already running')
  else
    if application.open(app_hint) then
      logger.i('Resuming ' .. app_hint)
    elseif alt_appname and application.open(alt_appname) then
      logger.i('Resuming ' .. alt_appname)
    else
      hs.timer.doAfter(KILL_APP_RETRY_DELAY, function()
        if (not application.find(app_hint)) and
           (not application.find(alt_appname)) then
          logger.e("Couldn't resume '" .. app_hint ..
                   (alt_appname and ("' or '" .. alt_appname) or "'"))
        end
      end)
    end
  end
end

-- ## Core functions ##
function obj.updateLocation()
  local priority, counts, winner, max = {}, {}, {}, nil
  for _,fact in ipairs(locationFactsPriority) do
    local loc = locationFacts[fact]
    if loc then
      if not priority.loc then priority.loc, priority.fact = loc, fact end
      local count = (counts[fact] or 0) + 1
      counts[fact] = count
      if max and (count > max) then
        max, winner.loc, winner.fact = count, loc, fact
      elseif count == max then
        max, winner.loc, winner.fact = nil, nil, nil
      end
    end
  end
  local loc, fact
  if winner.loc then
    -- Choose the most frequently selected
    loc, fact = winner.loc, winner.fact
  elseif priority.loc then
    -- or choose the highest priority
    loc, fact = priority.loc, priority.fact
  else
    -- or choose 'Roaming'
    loc = 'Roaming'
    logger.i("Inferring … well, failing to infer, so falling back to '"..loc.."'")
    locationFacts.location = loc
    return loc
  end
  logger.i('Inferring '.. loc ..' from '.. fact)
  locationFacts.location = loc
  return loc
end

function obj.actions()
  if obj.previousLocation then
    logger.i('Exit actions for Location: '.. obj.previousLocation)
    if obj[obj.previousLocation .. 'ExitActions'] then
      obj[obj.previousLocation .. 'ExitActions']()
    end
    if obj.watchers[obj.previousLocation] then
      for _, w in pairs(obj.watchers[obj.previousLocation]) do
        w:stop()
      end
    end
  end
  if obj[locationFacts.location .. 'EntryActions'] then
    logger.i('Entry actions for Location: '.. locationFacts.location)
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
    if type(v) == 'function' and k:find('Callback$') then v() end
    -- Starting or resuming all watchers
    if type(v) == 'userdata' and k:find('Watcher$') then
      if v.start ~= nil then
        logger.i('Starting ' .. k)
        v:start()
      elseif v.resume ~= nil then
        logger.i('Resuming ' .. k)
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
    if type(v) == 'userdata' and k:find('Watcher$') then
      if v.stop ~= nil then
        logger.i('Stopping ' .. k)
        v:stop()
      elseif v.pause ~= nil then
        logger.i('Pausing ' .. k)
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

-- Network configuration change (Expensive)
function obj.networkConfCallback(_, keys)
  logger.d('Network config changed (' .. hs.inspect(keys) .. ')')
  -- Work out which network we're on
  local inet = hs.network.reachability.internet()
  if (inet and inet:status() and
      hs.network.reachability.flags.reachable) > 0 then
    local pi4, pi6 = hs.network.primaryInterfaces() -- use pi4, ignore pi6
    if pi4 then
      logger.d('Primary interface is '.. pi4)
    else
      local interface = hs.network.interfaceDetails()
      logger.w('hs.network.reachability.internet():status() == '..
               inet:status() ..
               ' but hs.network.primaryInterfaces() is falsey… which is confusing\n'..
               'pi4: '..tostring(pi4)..' pi6:'..tostring(pi6)..'\n'..
               hs.inspect({IPv4 = interface and interface.IPv4 or "nil",
                           IPv6 = interface and interface.IPv6 or "nil"}))
    end
    if hs.network.interfaceDetails(pi4) and
       hs.network.interfaceDetails(pi4).Link and
       hs.network.interfaceDetails(pi4).Link.Expensive then
      locationFacts.network = 'Expensive'
    elseif init.consts.control_plane.locationFacts.network[hs.wifi.currentNetwork()]
      then locationFacts.network = init.consts.control_plane.locationFacts.network[hs.wifi.currentNetwork()]
    else
      logger.d('Unknown network')
      locationFacts.network = nil
    end
  else
    logger.d('No primary interface')
    locationFacts.network = nil
  end

  -- Update wifi_security key in watchable, since we have this anyway
  local wifi_interface_details = hs.wifi.interfaceDetails("en0")
  locationFacts.wifi_ssid = wifi_interface_details.ssid
  locationFacts.wifi_security = wifi_interface_details.security
end
obj.networkConfWatcher =
  hs.network.configuration.open():setCallback(
    function(_, keys)
      obj.networkConfCallback(_, keys)
    end ):monitorKeys({
  'State:/Network/Interface',
  'State:/Network/Global/IPv4',
  'State:/Network/Global/IPv6',
  'State:/Network/Global/DNS',
})

-- Attached power supply change (Wright, Fitzroy)
function obj.powerCallback()
  logger.d('Power changed')
  -- if hs.battery.psuSerial() == 7411505 then
  --   locationFacts.psu = 'Fitzroy'
  -- else
    locationFacts.psu = nil
  -- end
end
obj.batteryWatcher = hs.battery.watcher.new( function() obj.powerCallback() end )

-- Attached monitor change (Wright, Fitzroy)
function obj.screenCallback()
  logger.d('Monitor changed')
  -- if hs.screen.find(724044049) then
  --   locationFacts.monitor = 'Wright'
  -- elseif hs.screen.find(724043857) then
  --   locationFacts.monitor = 'Fitzroy'
    -- if init.consts.control_plane.locationFacts.monitor[hs.wifi.currentNetwork()]
    --   then locationFacts.network = init.consts.control_plane.locationFacts.network[hs.wifi.currentNetwork()]
  local found = false
  for _,screen in pairs(hs.screen.allScreens()) do
    if init.consts.control_plane.locationFacts.monitor[screen:id()] then
      found = true
      locationFacts.monitor = init.consts.control_plane.locationFacts.monitor[screen:id()]
    end
  end
  if not found then
    locationFacts.monitor = nil
  end
end
obj.screenWatcher = hs.screen.watcher.new( function() obj.screenCallback() end )


-- ##########################
-- ## Entry & Exit Actions ##
-- ##########################

local slack = require 'utilities.slack'
local network_hungry_apps = init.consts.control_plane.network_hungry_apps

-- Expensive
function obj.ExpensiveEntryActions()
  hs.alert('Control Plane: I hope Little Snitch is running and blocking your expensive apps!')
  logger.i('Closing network hungry apps')
  local killer = function(x)
    if type(x) == 'table' then
      killApp(x[1])
    else
      killApp(x)
    end
  end
  hs.fnutils.ieach(network_hungry_apps.kill, killer)
  hs.fnutils.ieach(network_hungry_apps.kill_and_resume, killer)
end

function obj.ExpensiveExitActions()
  logger.i('Opening network hungry apps')
  local resumer = function(x)
    if type(x) == 'table' then
      resumeApp(table.unpack(x))
    else
      resumeApp(x)
    end
  end
  hs.fnutils.ieach(network_hungry_apps.kill_and_resume, resumer)
end

-- Fitzroy
function obj.FitzroyEntryActions()
  if hs.wifi.currentNetwork() ~= 'TheBarn' then
    -- Connecting a Fitzroy monitor will force reconnection to TheBarn
    -- (Sometimes get stuck connecting to United_Wi-Fi and won't reconnect to TheBarn)
    hs.wifi.associate('TheBarn', hs.execute('security find-generic-password -a TheBarn -s AirPort -w'))
  end
  killApp('Transmission')
  slack.setStatus('Fitzroy')
  background('~/code/utilities/Scripts/mount-external-drives')
  -- Mute MacBook Pro Speakers if they're the current audio device
  local adt = hs.audiodevice.current()
  if adt.name == 'MacBook Pro Speakers' and adt.muted == false then
    adt.device:setOutputMuted(true)
  end
end

function obj.FitzroyExitActions()
  logger.i('Wifi On')
  hs.wifi.setPower(true)
end

-- Wright
function obj.WrightEntryActions()
  slack.setStatus('Wright')

  logger.i('Mount external drives')
  background('~/code/utilities/Scripts/mount-external-drives')

  -- logger.i('Set audio device')
  -- local setMacBookAudio = function()
  --   local output_device = ( hs.audiodevice.findOutputByName("Matt Fallshaw's AirPods Pro") or
  --     hs.audiodevice.findOutputByName("External Headphones") or
  --     hs.audiodevice.findOutputByName("MacBook Pro Speakers")
  --   )
  --   if output_device then output_device:setDefaultOutputDevice() end
  -- end

  -- if obj.watchers.wright == nil then obj.watchers.wright = {} end
  -- obj.watchers.wright.screens =
  --   obj.watchers.wright.screens or
  --   hs.screen.watcher.new(function()
  --     setMacBookAudio()
  --   end)
  -- obj.watchers.wright.screens:start()
  -- setMacBookAudio()
end

function obj.WrightExitActions()
  slack.setStatus('')
  killApp('Transmission')
  hs.wifi.setPower(true)
  local ls = hs.application('Lights Switch'); if ls then ls:kill() end
end

-- MIRI
function obj.MIRIEntryActions()
  slack.setStatus('MIRI')
end

function obj.MIRIExitActions()
  slack.setStatus('')
end

-- Roaming
function obj.RoamingEntryActions()
  killApp('Transmission')
end

return obj
