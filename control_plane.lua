-- # Control Plane replacement: Actions on change of location
--
-- Watch for location changes with
--   ``` lua
--   hs.watchable.watch(
--     'control-plane.location',
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

obj._logger = hs.logger.new('ControlPlane')
local logger = obj._logger
logger.i('Loading ControlPlane')

local ACTION_DELAY = 5 -- seconds
local KILL_APP_RETRY_DELAY = 30 -- seconds

obj.watchers = {}

obj.locationFactsPriority = { 'monitor', 'network', 'psu'}
local locationFactsPriority = obj.locationFactsPriority

local application = hs.application

obj.locationFacts = hs.watchable.new('control-plane', true)
local locationFacts = obj.locationFacts
locationFacts.location = ''
obj.locationFactsWatcher = hs.watchable.watch('control-plane.*',
  function(_, _, key, _, new_value)
    logger.i('Updating '.. key ..' = ' .. tostring(new_value))
    if key ~= 'location' then
      obj.actionTimer:start()
    end
  end)
obj.actionTimer = hs.timer.delayed.new(ACTION_DELAY, function() obj.updateLocation() end)
obj.locationWatcher = hs.watchable.watch('control-plane.location',
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
  logger.i('Network config changed (' .. hs.inspect(keys) .. ')')
  -- Work out which network we're on
  if (hs.network.reachability.internet():status() &
        hs.network.reachability.flags.reachable) > 0 then
    local pi4, _ = hs.network.primaryInterfaces() -- use pi4, ignore pi6
    if pi4 then
      logger.i('Primary interface is '.. pi4)
    else
      logger.w('hs.network.reachability.internet():status() == '..
               hs.network.reachability.internet():status() ..
               ' but hs.network.primaryInterfaces() == false… which is confusing')
    end
    if hs.network.interfaceDetails(pi4) and
       hs.network.interfaceDetails(pi4).Link and
       hs.network.interfaceDetails(pi4).Link.Expensive then
      locationFacts.network = 'Expensive'
    elseif hs.wifi.currentNetwork() == 'United_Wi-Fi' then
      locationFacts.network = 'Expensive'
    elseif hs.wifi.currentNetwork() == 'blacknode' then
      locationFacts.network = 'Canning'
    elseif hs.wifi.currentNetwork() == 'bellroy' then
      locationFacts.network = 'Fitzroy'
    elseif hs.wifi.currentNetwork() == 'MIRICFAR UniFi' then
      locationFacts.network = 'MIRI'
    else
      logger.i('Unknown network')
      locationFacts.network = nil
    end
  else
    logger.i('No primary interface')
    locationFacts.network = nil
  end
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

-- Attached power supply change (Canning, Fitzroy)
function obj.powerCallback()
  logger.i('Power changed')
  if hs.battery.psuSerial() == 7411505 then
    locationFacts.psu = 'Fitzroy'
  else
    locationFacts.psu = nil
  end
end
obj.batteryWatcher = hs.battery.watcher.new( function() obj.powerCallback() end )

-- Attached monitor change (Canning, Fitzroy)
function obj.screenCallback()
  logger.i('Monitor changed')
  if hs.screen.find(724044049) then
    locationFacts.monitor = 'Canning'
  elseif hs.screen.find(724061396) then
    locationFacts.monitor = 'Fitzroy'
  elseif hs.screen.find(69992768) then
    locationFacts.monitor = 'CanningServer'
  else
    locationFacts.monitor = nil
  end
end
obj.screenWatcher = hs.screen.watcher.new( function() obj.screenCallback() end )


-- ##########################
-- ## Entry & Exit Actions ##
-- ##########################

local slack = require 'utilities.slack'
local network_hungry_apps = {
  kill = {
    'Transmission'
  },
  kill_and_resume = {
  -- These moved to being blocked by Little Snitch
  --   'Dropbox',
  --   'Google Drive File Stream',
  --   {'Backup and Sync from Google', 'Backup and Sync'},
  }
}

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
  killApp('Transmission')
  slack.setStatus('Fitzroy')
  hs.execute('~/code/utilities/Scripts/mount-external-drives', true)
end

function obj.FitzroyExitActions()
  logger.i('Wifi On')
  hs.wifi.setPower(true)
end

-- Canning
function obj.CanningEntryActions()
  slack.setStatus('Canning')
  hs.execute('~/code/utilities/Scripts/mount-external-drives', true)
  if not hs.application('Lights Switch') then hs.application.open('Lights Switch') end
end

function obj.CanningExitActions()
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
