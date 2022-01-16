-- Enable this to do live debugging in ZeroBrane Studio
 -- local ZBS = "/Applications/ZeroBraneStudio.app/Contents/ZeroBraneStudio"
 -- package.path = package.path .. ";" .. ZBS .. "/lualibs/?/?.lua;" .. ZBS .. "/lualibs/?.lua"
 -- package.cpath = package.cpath .. ";" .. ZBS .. "/bin/?.dylib;" .. ZBS .. "/bin/clibs53/?.dylib"
 -- require("mobdebug").start()

-- nix makes global luarocks hard, use local
package.path = package.path ..
  ";" .. os.getenv("HOME") .. "/.luarocks/share/lua/5.3/?.lua" ..
  ";" .. os.getenv("HOME") .. "/.luarocks/share/lua/5.3/?/init.lua" ..
  ";" .. os.getenv("HOME") .. "/.nix-profile/share/lua/5.3/?.lua" ..
  ";" .. os.getenv("HOME") .. "/.nix-profile/share/lua/5.3/?/init.lua"
package.cpath = package.cpath ..
  ";" .. os.getenv("HOME") .. "/.luarocks/lib/lua/5.3/?.so"

profile = {
  start = function()
    p = require 'utilities.profile'
    p:start()
  end,
  stop = function()
    p:stop()
    p:writeReport('build/profile.'..os.date('%Y-%m-%d_%H-%M-%S')..'.txt')
  end
}
-- profile.start()

-- luacheck: allow defined top
-- luacheck: globals hs spoon

local _ENV = require 'std.strict' (_G) -- luacheck: no unused
local fun = require 'fun'

init = {}  -- watchers & etc.

-- Auto-reload config
init.auto_reload_or_test = require 'auto_reload_or_test'
init.auto_reload_or_test:start()

init.consts = require 'configConsts'

local logger = hs.logger.new("Init")
init.logger = logger
hs.console.clearConsole()

i = hs.inspect.inspect  -- luacheck: no global

-- # Setup for everything else #
--
-- Capture spoon (and other) hotkeys
hs.loadSpoon("CaptureHotkeys")
spoon.CaptureHotkeys:bindHotkeys({show = {{ "⌘", "⌥", "⌃", "⇧" }, "k"}}):start()

local log = require('utilities.log').new(logger)

-- # / Setup #

-- # HS config #
--
-- Clear console hotkey
init.clearConsoleHotkey = {
  clear = spoon.CaptureHotkeys:bind("Hammer+", "Clear console",
      {"⌘", "⌥", "⌃", "⇧"}, "c",
      function() hs.console.clearConsole() end)
}


hs.loadSpoon('Hammer')
spoon.Hammer.auto_reload_config = false
spoon.Hammer:bindHotkeys({
  config_reload ={{"⌘", "⌥", "⌃", "⇧"}, "r"},
  toggle_console={{"⌘", "⌥", "⌃", "⇧"}, "d"},
})
spoon.Hammer:start()

-- # / HS config #


-- Control Plane replacement: Actions on change of location
control_plane = require('control_plane'):start()  -- luacheck: no global
control_plane._logger.setLogLevel('info')
local function is_trusted_network()
  local trusted_open_networks = init.consts.trusted_open_networks
  return not not (fun.index(trusted_open_networks,
                            require('control_plane').locationFacts.wifi_ssid))
end
local function insecure_network_actions(security_mode)
  if security_mode == 'None' and not hs.application('Private Internet Access') then
    if is_trusted_network() then
      hs.alert.show("WARNING: Insecure WiFi connection",{textSize=48},hs.screen.mainScreen(),1.8)
      hs.alert.show("*not* locking you down since '"..
        tostring(require('control_plane').locationFacts.wifi_ssid).. "' is a trusted network")
    else
      hs.alert.show("WARNING: Insecure WiFi connection",{textSize=48},hs.screen.mainScreen(),1.8)
      local launch_button = 'Launch VPN'
      hs.focus()
      hs.dialog.alert(
        300, 300,  -- location x,y
        function(result)
          if result == launch_button then
            hs.application.open("Private Internet Access")
            logger.i('Launching PVN')
          else
            logger.i('Doing nothing; leaving our undergarments exposed')
          end
        end,  -- callback
        'Launch VPN?',  -- message
        'WARNING: Insecure WiFi connection',  -- informative text
        launch_button, 'Cancel',  -- buttons
        'warning'  -- style
      )
    end
  else  -- luacheck: ignore 542
    -- do nothing
  end
end
init.control_plane_wifi_security_watcher = hs.watchable.watch(
  'control_plane', 'wifi_security',
  function(_, _, _, _, new_value)
    logger.i('WiFi network changed, checking WiFi security')
    hs.timer.doAfter(1, function() insecure_network_actions(new_value) end)
  end
)
insecure_network_actions(hs.wifi.interfaceDetails().security)  -- run on startup


-- Stay replacement: Keep App windows in their places
stay = require('stay'):start()  -- luacheck: no global
spoon.CaptureHotkeys:capture(
  "Stay", "Once, toggle layout engine; twice, report screens; thrice, report frontmost window; "..
    "four times, report frontmost & open stay.lua for editing",
  {"⌘", "⌥", "⌃", "⇧"}, "s")


-- Desktop organisation
logger.i("Reorganising Desktop")
local function reorganise_desktop()
  hs.osascript.applescript([[
    tell application "Finder"
      set keybaseFolder to first disk whose name begins with "Keybase"
      set desktop position of keybaseFolder to {1493, 399}
    end tell
  ]])
end
init.volumeWatcher = hs.fs.volume.new(function(event, info)
  if (event == hs.fs.volume.didMount) and (info.path:match('^/Volumes/Keybase')) then
    -- Move Keybase volume into position
    hs.timer.doAfter(3, reorganise_desktop)
end
end):start()


local mwm = hs.loadSpoon("MiroWindowsManager")
mwm.sizes = init.consts.mwm.sizes
mwm.fullScreenSizes = init.consts.mwm.fullScreenSizes
mwm.GRID = init.consts.mwm.GRID
mwm.stickySides = true
mwm:bindHotkeys(init.consts.mwm.hotkeys)


hs.loadSpoon("WindowScreenLeftAndRight")
spoon.WindowScreenLeftAndRight:bindHotkeys({
   screen_left  = { {"ctrl", "alt", "cmd"}, "h" },
   screen_right = { {"ctrl", "alt", "cmd"}, "l" },
})


-- Move windows between spaces
move_spaces = require('move_spaces')
move_spaces:bindHotkeys({
  left  = {{"⌘", "⌥", "⌃", "⇧"}, "h"},
  right = {{"⌘", "⌥", "⌃", "⇧"}, "l"},
})


-- Desktop space numbers
desktop_space_numbers = require('desktop_space_numbers')
desktop_space_numbers:start()


-- Jettison replacement: Eject ejectable drives on sleep
-- jettison = require('jettison')
-- jettison:start()


-- Spotify controls
-- spotify = { hotkeys = {}, volume = hs.spotify.getVolume(), mute = false }
-- local spotify_hotkeymap = {
--   playpause  = {{"⌥", "⌃", "⇧"},      "f8"},
--   next       = {{"⌥", "⌃", "⇧"},      "f9"},
--   previous   = {{"⌥", "⌃", "⇧"},      "f7"},
--   hide       = {{"⌥", "⌃", "⇧"},      "h"},
--   quit       = {{"⌥", "⌃", "⇧"},      "q"},
--   mute       = {{"⌥", "⌃", "⇧"},      "f10"},
--   volumeDown = {{"⌥", "⌃", "⇧"},      "f11"},
--   volumeUp   = {{"⌥", "⌃", "⇧"},      "f12"},
--   ff         = {{"⌥", "⌃", "⇧", "⌘"}, "f9"},
--   rw         = {{"⌥", "⌃", "⇧", "⌘"}, "f7"},
--   displayCurrentTrack = {{"⌥", "⌃", "⇧"}, "t"},
-- }
-- local spotify_app = hs.application.get("Spotify")
-- local fns = {
--   hide = function() if spotify_app then return spotify_app:isHidden()
--     and (spotify_app:activate() or true)
--     or spotify_app:hide() end end,
--   quit = function() if spotify_app then spotify_app:kill() end end,
--   mute = function() if spotify_app then
--     if spotify.mute then
--       spotify.mute = false
--       hs.spotify.setVolume(spotify.volume)
--     else
--       spotify.mute = true
--       spotify.volume = hs.spotify.getVolume()
--       hs.spotify.setVolume(0)
--     end
--   end end
-- }
-- for fn_name, map in pairs(spotify_hotkeymap) do
--   spotify.hotkeys[fn_name] = spoon.CaptureHotkeys:bind("Spotify", fn_name ,map[1], map[2],
--     type(hs.spotify[fn_name])=='function' and
--       function() return hs.spotify[fn_name]() end or
--       function() return fns[fn_name]() end
--     -- function()
--     --   if type(hs.spotify[fn_name])~='function' then
--     --     return hs.spotify[fn_name]()
--     --   end
--     --   local fns = {
--     --     hide = function() if spotify_app then return spotify_app:hide() end end,
--     --     quit = function() if spotify_app then spotify_app:kill() end end,
--     --     mute = function() if spotify_app then
--     --       if spotify.mute then
--     --         spotify.mute = false
--     --         hs.spotify.setVolume(spotify.volume)
--     --       else
--     --         spotify.mute = true
--     --         spotify.volume = hs.spotify.getVolume()
--     --         hs.spotify.setVolume(0)
--     --       end
--     --     end end
--     --   }
--     --   return fns[fn_name]()
--     -- end
--   )
-- end


-- Trash recent downloads
trash_recent = require('trash_recent')
trash_recent.hotkey = spoon.CaptureHotkeys:bind(
  "Trash recent download", "trashRecentDownload", {"⌥", "⌃", "⇧", "⌘"}, "t",
  trash_recent.trashRecentDownload)


-- ScanSnap: Start ScanSnap's horrendous array of apps when scanner attached, and kill them when detatched
logger.i("Loading USB watcher")
local function usbDeviceCallback(data)
  logger.d(data['productName']..' '..data['eventType'])
  -- ScanSnap
  -- ScanSnap Home's apps are not properly registered (named) and there are several of them, so matches and arrays…
  if (data["productName"]:match("^ScanSnap")) then
    if (data['eventType'] == 'added') then
      log:and_alert(data['productName'].. ' added, launching ScanSnap Home')
      hs.application.launchOrFocus('ScanSnap Manager')
    elseif (data['eventType'] == 'removed') then
      local scansnaps = table.pack(hs.application.find("ScanSnap"))
      if scansnaps.n > 0 then
        fun.each(function(app)
                   app:kill()
                   log:and_alert(data['productName'].. ' removed, closing '.. app:name())
                 end,
                 scansnaps)
      else  -- luacheck: ignore 542
        -- do nothing
      end
      local aou_mon = hs.application.get('AOUMonitor')
      if aou_mon then aou_mon:kill9() end
    end
  end
end
logger.i("Starting USB watcher")
init.usbWatcher = hs.usb.watcher.new(usbDeviceCallback)
init.usbWatcher:start()


-- Transmission safety: Keep VPN running when Transmission is running
logger.i("Loading Transmission VPN Guard")
local function applicationWatcherCallback(appname, event, _)
  if appname == "Transmission" and event == hs.application.watcher.launching then
    if not hs.application.get("Private Internet Access") then
      log:and_alert("Transmission launch detected… launching PIA")
      hs.application.open("Private Internet Access")
    else
      log:and_alert("Transmission launch detected… but PIA already running")
    end
  elseif appname == "Private Internet Access" and event == hs.application.watcher.terminated then
    if hs.application.get("Transmission") then
      log:and_alert("PIA termination detected… killing Transmission")
      hs.application.get("Transmission"):kill9()
    else
      log:and_alert("PIA termination detected… Transmission not running, so no action")
    end
  end
end
logger.i("Starting Transmission VPN Guard")
init.applicationWatcher = hs.application.watcher.new(applicationWatcherCallback)
init.applicationWatcher:start()

hs.loadSpoon("URLDispatcher")
spoon.URLDispatcher.default_handler = init.consts.URLDispatcher.default_handler
spoon.URLDispatcher.url_patterns = init.consts.URLDispatcher.url_patterns
spoon.URLDispatcher:start()
-- URLs from hammerspoon:// schema
local _, unescape = require('utilities.string_escapes')()
local function URLDispatcherCallback(_, params)
  local fullUrl = unescape.url(params.uri)
  local parts = hs.http.urlParts(fullUrl)
  spoon.URLDispatcher:dispatchURL(parts.scheme, parts.host, parts.parameterString, fullUrl)
end
spoon.URLDispatcher.url_dispatcher = hs.urlevent.bind("URLDispatcher", URLDispatcherCallback)
spoon.URLDispatcher.logger.setLogLevel('debug')  -- to track redirections, which often fail


hs.loadSpoon("MouseCircle")
spoon.MouseCircle:bindHotkeys({ show = {{"⌘", "⌥", "⌃", "⇧"}, "m"}})


hs.loadSpoon("Caffeine")
spoon.Caffeine:bindHotkeys({ toggle = {{"⌥", "⌃", "⇧"}, "c"}})
spoon.Caffeine:start()
-- Turn off Caffeine if screen is locked or system sent to sleep
init.caffeine_screen_lock_watcher = hs.caffeinate.watcher.new(function(event)
  if spoon.Caffeine and
    (event == hs.caffeinate.watcher["screensDidLock"] or
     event == hs.caffeinate.watcher["systemWillSleep"]) then

    if hs.caffeinate.get("displayIdle") then
      spoon.Caffeine.clicked()
      logger.i(hs.caffeinate.watcher[event] .. " and spoon.Caffeine on; turning it off")
    end
  end
end):start()


-- hs.loadSpoon("HeadphoneAutoPause")
-- spoon.HeadphoneAutoPause.control['vox'] = false
-- spoon.HeadphoneAutoPause.control['deezer'] = false
-- spoon.HeadphoneAutoPause.control['Google Play Music Desktop Player'] = true
-- spoon.HeadphoneAutoPause.controlfns['Google Play Music Desktop Player'] =
--   gpmdp.spoons.HeadphoneAutoPause.controlfns['Google Play Music Desktop Player']
-- spoon.HeadphoneAutoPause:start()


hs.loadSpoon("AppHotkeys")
local hks = spoon.AppHotkeys.hotkeys
-- Terminal ⌘1-9 to tab focus
logger.i("Terminal hotkeys for switching ⌘1-9 to Tab focus")
hks.Terminal = fun.map(
  function(hotkey)
    if hotkey == 9 then
      return hs.hotkey.new('⌘',
                           tostring(hotkey),
                           function()
                             hs.osascript.applescript('tell application "Terminal" to set selected of last tab '..
                                                      'of first window to true')
                           end)
    else
      return hs.hotkey.new('⌘',
                           tostring(hotkey),
                           function()
                             hs.osascript.applescript('tell application "Terminal" to set selected of tab '..
                                                      hotkey .. ' of first window to true')
                           end)
    end
  end,
  fun.range(9))
spoon.CaptureHotkeys:capture("Terminal", {
  ["Select tab n"] = { {"⌘"}, "n" },
  ["Select last tab"] = { {"⌘"}, "9" },
})
-- Slack usability improvements
logger.i("Slack usability hotkeys")
hks.Slack = {
  hs.hotkey.new('⌘', 'w', function()
    hs.eventtap.keyStrokes("/leave ")
    hs.timer.doAfter(0.3, function() hs.application.get("Slack"):activate(); hs.eventtap.keyStroke({}, "return") end)
  end),
  hs.hotkey.new('⌘⇧', ']', function() hs.eventtap.keyStroke({'alt'}, 'down') end),
  hs.hotkey.new('⌘⇧', '[', function() hs.eventtap.keyStroke({'alt'}, 'up') end),
}
spoon.CaptureHotkeys:capture("Slack", {
  ["Close Channel"] = { {"⌘"}, "w" },
  ["Next Channel"] = { {"⌘", "⇧"}, "]" },
  ["Previous Channel"] = { {"⌘", "⇧"}, "[" },
})
-- Signal usability improvements
logger.i("Signal usability hotkeys")
hks.Signal = {
  hs.hotkey.new('⌥', 'return', function() hs.eventtap.keyStroke({'⇧'}, 'return') end),
  hs.hotkey.new('⌘⇧', ']', function() hs.eventtap.keyStroke({'alt'}, 'down') end),
  hs.hotkey.new('⌘⇧', '[', function() hs.eventtap.keyStroke({'alt'}, 'up') end),
}
spoon.CaptureHotkeys:capture("Signal", {
  ["New line"] = { {"⌥"}, "⏎" },
  ["Next Conversation"] = { {"⌘", "⇧"}, "]" },
  ["Previous Conversation"] = { {"⌘", "⇧"}, "[" },
})
spoon.AppHotkeys:start()


local clock = hs.loadSpoon("AClock")
clock.format = "%H:%M:%S"
clock.textColor = {hex="#00c403"}
clock.textFont = "Menlo Bold"
clock.height = 160
clock.width = 675
clock:init()


-- ChromeTabs
chrome_tabs = require('chrome_tabs')
-- chrome_tabs.chooser = require('chrome_tabs.chrome_tab_chooser')
-- chrome_tabs.chooser.hotkey = spoon.CaptureHotkeys:bind("ChromeTabs", "Find & focus a Chrome tab",
--     {'⌘','⇧','⌃'}, 'n', function() chrome_tabs.chooser.show() end)


-- Keycastr
keycastr = require('keycastr')
keycastr:bindHotkeys({
  toggle = { toggle = {{"cmd", "shift", "ctrl"}, 'P'} }
})
keycastr:start()


-- Remember & restore active spaces per screen layout
-- TODO

----------------------------
-- Audio device functions --
----------------------------

-- Switches audio input/output device
-- For some Bluetooth devices like AirPods they don't show up in list of available devices
-- For these devices, if not found in device list, Applescript is used to manipulate Volume menu item to connect them
function changeAudioDevice(deviceName)
  fun.each(function(x) logger.e(x:name()); x:setDefaultInputDevice() end,
           fun.filter(function(x) return x:name():match(deviceName) end,
                      hs.audiodevice.allInputDevices()))
  fun.each(function(x) logger.e(x:name()); x:setDefaultOutputDevice() end,
           fun.filter(function(x) return x:name():match(deviceName) end,
                      hs.audiodevice.allOutputDevices()))

  -- hs.audiodevice.findInputByName(deviceName):setDefaultInputDevice()
  -- hs.audiodevice.findOutputByName(deviceName):setDefaultOutputDevice()

  if hs.audiodevice.defaultOutputDevice():name():match(deviceName) then
    hs.notify.show("Audio Device", "",
                   hs.audiodevice.defaultOutputDevice():name() .. " connected")
  else
    hs.notify.show("Audio Device", "", "Failed to conncet to " .. deviceName)
  end
end


-- Seal
seal = require('seal_config')

-- # notnux only #
--
if hs.host.localizedName() == "notnux5" then

  -- Export hotkeys to build/Hammerspoon.kcustom
  local kce = spoon.CaptureHotkeys.exporters.keyCue
  --
  -- local out, out_old = kce.output_file_path, kce.output_file_path .. ".old"
  -- hs.execute("mv " .. out .. " " .. out_old)
  --
  kce:export_to_file()
  --
  -- local diff_command = "/usr/bin/diff -q <(/usr/bin/sort "..out.." ) <( /usr/bin/sort "..out_old.." )"
  -- local output, status, t, rc = hs.execute(diff_command)
  -- -- TODO: if diff, open .kcustom file for import into KeyCue
  -- hs.execute("rm " .. out_old)

  -- Activity log
  init.activity_log = require('activity_log')
  init.activity_log:start()

  -- Kill Google Drive File Stream on sleep
  log._logger.level = log.DEBUG
  local function countdown(count, event)
    return function()
      local gdfs = hs.application('Google Drive File Stream')
      if gdfs then
        hs.caffeinate.declareUserActivity()  -- prevent sleep to give us time
        gdfs:kill()
        init.gd_file_stream.state = 1
        if count == 5 then
          log:and_alert('gd_file_stream watcher: Killing Google Drive File Stream',log.INFO)
        elseif count < 1 then
          log:and_alert('gd_file_stream watcher: Failed to kill Goodle Drive File Stream!',log.WARN)
          return false
        end
        if gdfs:isRunning() then
          hs.timer.doAfter(2,countdown(count - 1, event))
        else
          if event == hs.caffeinate.watcher.systemWillSleep then
            hs.caffeinate.systemSleep()
          elseif event == hs.caffeinate.watcher.screensDidLock then
            hs.caffeinate.lockScreen()
          else
            log:and_alert('Unexpected event: '..event,log.ERROR)
          end
        end
      end
    end
  end
  local fs_watcher_onsleepfn = function(event) countdown(5, event)() end
  local fs_watcher_onwakefn = function(event)
    if init.gd_file_stream.state == 1 then
      local gdfs = hs.application('Google Drive File Stream')
      if gdfs then
        log:and_alert('gd_file_stream watcher: Google Drive File Stream running on wake; should have been killed on sleep',log.WARN)
      else
        hs.application.open('Google Drive File Stream')
        log:and_alert('gd_file_stream watcher: Restarting Google Drive File Stream',log.INFO)
      end
      init.gd_file_stream.state = 0
    end
  end

  local fs_watcher_events = {
    [hs.caffeinate.watcher.systemWillSleep]  = fs_watcher_onsleepfn,
    [hs.caffeinate.watcher.systemDidWake]    = fs_watcher_onwakefn,
    [hs.caffeinate.watcher.screensDidLock]   = fs_watcher_onsleepfn,  -- Catalina: systemWillSleep does not fire
    [hs.caffeinate.watcher.screensDidUnlock] = fs_watcher_onwakefn
  }
  local fs_watcherfn = function(event)
    if fs_watcher_events[event] then
      fs_watcher_events[event](event)
    else
      --
    end
  end
  local fs_watcher = hs.caffeinate.watcher.new(fs_watcherfn)
  init.gd_file_stream = { watcher = fs_watcher
                        , state   = 0 }
  init.gd_file_stream.start = function() fs_watcher:start() end
  init.gd_file_stream.stop  = function() fs_watcher:stop()  end
  init.gd_file_stream.start()

  -- mission_control_hotkeys = require('mission_control_hotkeys')

  -- Reorganise desktop
  reorganise_desktop()
end

-- dd_timer = hs.timer.delayed.new(15, function()
--   p:stop()
--   p:writeReport('build/profile.'..os.date('%Y-%m-%d_%H-%M-%S')..'.txt')
-- end)
-- dd = hs.caffeinate.watcher.new(function(_)
--   if p.has_finished then
--     p:start()
--   end
--   dd_timer:start()
-- end):start()

-- profile.stop()

hs.loadSpoon("FadeLogo"):start()

if stay then print('Stay: Active layout is '.. tostring(stay:activeLayouts())) end
