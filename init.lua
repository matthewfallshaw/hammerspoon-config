hs.logger.setGlobalLogLevel('warning')
hs.logger.defaultLogLevel = 'warning'
hs.hotkey.setLogLevel('warning')  -- 'cos it ignores global defaults
local logger = hs.logger.new("Init")

hs.console.clearConsole()
hs.application.enableSpotlightForNameSearches(true)
hs.allowAppleScript(true)
i = hs.inspect.inspect


-- Capture spoon (and other) hotkeys
hs.loadSpoon("CaptureHotkeys")
spoon.CaptureHotkeys:bindHotkeys({show = {{ "⌘", "⌥", "⌃", "⇧" }, "k"}})
spoon.CaptureHotkeys:start()

-- Load spoon.Hammer early, since it gives us config reload & etc.
hs.loadSpoon("Hammer")
spoon.Hammer:bindHotkeys({
  config_reload ={{"⌘", "⌥", "⌃", "⇧"}, "r"},
  toggle_console={{"⌘", "⌥", "⌃", "⇧"}, "h"},
})
spoon.Hammer:start()
hammer_plus = {
  hotkeys = {
    clear = spoon.CaptureHotkeys:bind("Hammer+", "Clear console", {"⌘", "⌥", "⌃", "⇧"}, "c",
                                      function() hs.console.clearConsole() end)
  }
}


local log = require('utilities.log').new(logger)


-- Control Plane replacement: Actions on change of location
control_plane = require 'control-plane'
control_plane:start()


-- Stay replacement: Keep App windows in their places
stay = require 'stay'
stay:start()
spoon.CaptureHotkeys:capture("Stay", "Toggle layout engine or report frontmost window",
  {"⌘", "⌥", "⌃", "⇧"}, "s")


-- Move windows between spaces
move_spaces = require "move-spaces"
move_spaces.hotkeys.right = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Right",
  {"⌘", "⌥", "⌃", "⇧"}, "right", function() move_spaces.moveWindowOneSpace("right") end)
move_spaces.hotkeys.left  = spoon.CaptureHotkeys:bind("WindowSpacesLeftAndRight", "Left",
  {"⌘", "⌥", "⌃", "⇧"}, "left",  function() move_spaces.moveWindowOneSpace("left") end)


-- Jettison replacement: Eject ejectable drives on sleep
jettison = require 'jettison'
jettison:start()


-- ScanSnap: Start ScanSnap manager when scanner attached
logger.i("Loading ScanSnap USB watcher")
function usbDeviceCallback(data)
  if (data["productName"]:match("^ScanSnap")) then
    if (data["eventType"] == "added") then
      log.and_alert(data["productName"].. " added, launching ScanSnap Manager")
      hs.application.launchOrFocus("ScanSnap Manager")
    elseif (data["eventType"] == "removed") then
      local app = hs.application.find("ScanSnap Manager")
      if app then
        log.and_alert(data["productName"].. " removed, closing ScanSnap Manager")
        app:kill()
      end
      if hs.application.get("AOUMonitor") then hs.application.get("AOUMonitor"):kill9() end
    end
  end
end
usbWatcher = hs.usb.watcher.new(usbDeviceCallback)
logger.i("Starting ScanSnap USB watcher")
usbWatcher:start()


-- Transmission safety: Keep VPN running when Transmission is running
logger.i("Loading Transmission VPN Guard")
function applicationWatcherCallback(appname, event, app)
  if appname == "Transmission" and event == hs.application.watcher.launching then
    if not hs.application.get("Private Internet Access") then
      log.and_alert("Transmission launch detected… launching PIA")
      hs.application.open("Private Internet Access")
    else
      log.and_alert("Transmission launch detected… but PIA already running")
    end
  elseif appname == "Private Internet Access" and event == hs.application.watcher.terminated then
    if hs.application.get("Transmission") then
      log.and_alert("PIA termination detected… killing Transmission")
      hs.application.get("Transmission"):kill9()
    else
      log.and_alert("PIA termination detected… Transmission not running, so no action")
    end
  end
end
applicationWatcher = hs.application.watcher.new(applicationWatcherCallback)
logger.i("Starting Transmission VPN Guard")
applicationWatcher:start()


-- Google Play Music Desktop Player Hotkeys
gpmdp = require 'gpmdp'
gpmdp.hotkeys = {}
local gpmdphotkeymap = {
  playpause  = {{"⌥", "⌃", "⇧"},      "f8"},
  next       = {{"⌥", "⌃", "⇧"},      "f9"},
  previous   = {{"⌥", "⌃", "⇧"},      "f7"},
  like       = {{"⌥", "⌃", "⇧"},      "l"},
  dislike    = {{"⌥", "⌃", "⇧"},      "d"},
  hide       = {{"⌥", "⌃", "⇧"},      "h"},
  quit       = {{"⌥", "⌃", "⇧"},      "q"},
  mute       = {{"⌥", "⌃", "⇧"},      "f10"},
  volumeDown = {{"⌥", "⌃", "⇧"},      "f11"},
  volumeUp   = {{"⌥", "⌃", "⇧"},      "f12"},
  ff         = {{"⌥", "⌃", "⇧", "⌘"}, "f9"},
  rw         = {{"⌥", "⌃", "⇧", "⌘"}, "f7"},
  displayCurrentTrack = {{"⌥", "⌃", "⇧"}, "t"},
}
for fn_name, map in pairs(gpmdphotkeymap) do
  gpmdp.hotkeys[fn_name] = hs.hotkey.bind(map[1], map[2], function() gpmdp[fn_name]() end)
end
spoon.CaptureHotkeys:capture("GPMDP", gpmdphotkeymap)


-- URLs from hammerspoon:// schema
local escape, unescape = require('utilities.string_escapes')()
function URLDispatcherCallback(eventName, params)
  local fullUrl = unescape.url(params.uri)
  local parts = hs.http.urlParts(fullUrl)
  spoon.URLDispatcher:dispatchURL(parts.scheme, parts.host, parts.parameterString, fullUrl)
end
url_dispatcher = hs.urlevent.bind("URLDispatcher", URLDispatcherCallback)


-- Trash recent downloads
trash_recent = require 'trash-recent'


-- Spoons (other than spoon.Hammer)
-- ## All hosts
hs.loadSpoon("URLDispatcher")
spoon.URLDispatcher.default_handler = "com.google.Chrome"
spoon.URLDispatcher.url_patterns = {
  -- { <url pattern>, <application bundle ID> },
  { "https?://www.pivotaltracker.com/.*", "com.fluidapp.FluidApp.PivotalTracker" },
  { "https?://app.asana.com/.*",          "org.epichrome.app.Asana" },
  { "https?://morty.trikeapps.com/.*",    "org.epichrome.app.Morty" },
  { "https?://app.greenhouse.io/.*",      "org.epichrome.app.Greenhouse" },
  { "https?://workflowy.com/.*",          "com.fluidapp.FluidApp.Workflowy" },
  { "https?://calendar.google.com/.*",    "org.epichrome.app.GoogleCalend" },
  { "https?://www.google.com/calendar/.*", "org.epichrome.app.GoogleCalend" },
}
spoon.URLDispatcher:start()

hs.loadSpoon("Emojis")
spoon.Emojis:bindHotkeys({ toggle = {{"⌘", "⌥", "⌃", "⇧"}, "space"}})

hs.loadSpoon("MouseCircle")
spoon.MouseCircle:bindHotkeys({ show = {{"⌘", "⌥", "⌃", "⇧"}, "m"}})

hs.loadSpoon("Caffeine")
spoon.Caffeine:bindHotkeys({ toggle = {{"⌥", "⌃", "⇧"}, "c"}})
spoon.Caffeine:start()

hs.loadSpoon("HeadphoneAutoPause")
spoon.HeadphoneAutoPause.control['vox'] = false
spoon.HeadphoneAutoPause.control['deezer'] = false
spoon.HeadphoneAutoPause.control['Google Play Music Desktop Player'] = true
spoon.HeadphoneAutoPause.controlfns['Google Play Music Desktop Player'] = {
  appname = 'Google Play Music Desktop Player',
  isPlaying = gpmdp.isPlaying,
  play = gpmdp.play,
  pause = gpmdp.pause
}
spoon.HeadphoneAutoPause:start()

hs.loadSpoon("AppHotkeys")
local hotkeys = spoon.AppHotkeys.hotkeys
-- Terminal ⌘1-9 to tab focus
logger.i("Terminal hotkeys for switching ⌘1-9 to Tab focus")
for i=1,8 do
  table.insert(hotkeys["Terminal"], hs.hotkey.new('⌘', tostring(i), function()
    hs.osascript.applescript('tell application "Terminal" to set selected of tab ' .. i .. ' of first window to true')
  end))
end
table.insert(hotkeys["Terminal"], hs.hotkey.new('⌘', "9", function()
  hs.osascript.applescript('tell application "Terminal" to set selected of last tab of first window to true')
end))
spoon.CaptureHotkeys:capture("Terminal", {
  ["Select tab n"] = { {"⌘"}, "n" },
  ["Select last tab"] = { {"⌘"}, "9" },
})
-- Slack usability improvements
logger.i("Slack usability hotkeys")
table.insert(hotkeys["Slack"], hs.hotkey.new('⌘', 'w', function()
  hs.eventtap.keyStrokes("/leave ")
  hs.timer.doAfter(0.3, function() hs.application.get("Slack"):activate(); hs.eventtap.keyStroke({}, "return") end)
end))
table.insert(hotkeys["Slack"], hs.hotkey.new('⌘⇧', ']', function() hs.eventtap.keyStroke({'alt'}, 'down') end))
table.insert(hotkeys["Slack"], hs.hotkey.new('⌘⇧', '[', function() hs.eventtap.keyStroke({'alt'}, 'up') end))
spoon.CaptureHotkeys:capture("Slack", {
  ["Close Channel"] = { {"⌘"}, "w" },
  ["Next Channel"] = { {"⌘", "⇧"}, "]" },
  ["Previous Channel"] = { {"⌘", "⇧"}, "[" },
})
spoon.AppHotkeys:start()

local mwm = hs.loadSpoon("MiroWindowsManager")
mwm.sizes = {2, 3/2, 3, 'c'}
mwm.fullScreenSizes = {1, 'c', 4/3, 2}
mwm.GRID = {w = 24, h = 12}
mwm:bindHotkeys({
  up          = {{    '⌥',    '⌘'}, 'up'},
  down        = {{    '⌥',    '⌘'}, 'down'},
  left        = {{    '⌥',    '⌘'}, 'left'},
  right       = {{    '⌥',    '⌘'}, 'right'},
  fullscreen  = {{    '⌥',    '⌘'}, 'f'},
  moveUp      = {{'⌃','⌥'        }, 'up'},
  moveDown    = {{'⌃','⌥'        }, 'down'},
  moveLeft    = {{'⌃','⌥'        }, 'left'},
  moveRight   = {{'⌃','⌥'        }, 'right'},
  taller      = {{'⌃','⌥','⇧'}, "down"},
  shorter     = {{'⌃','⌥','⇧'}, "up"},
  wider       = {{'⌃','⌥','⇧'}, "right"},
  thinner     = {{'⌃','⌥','⇧'}, "left"},
})

-- hs.loadSpoon("WindowHalfsAndThirds")
-- spoon.WindowHalfsAndThirds._window_moves.left_half = {"left_half", left_half = "left_60", left_60 = "left_40"}
-- spoon.WindowHalfsAndThirds._window_moves.right_half = {"right_half", right_half = "right_60", right_60 = "right_40"},
-- spoon.WindowHalfsAndThirds:bindHotkeys({
--   left_half   = { {        "alt", "cmd"}, "Left" },
--   right_half  = { {        "alt", "cmd"}, "Right" },
--   top_half    = { {        "alt", "cmd"}, "Up" },
--   bottom_half = { {        "alt", "cmd"}, "Down" },
--   third_left  = { {"ctrl", "alt"       }, "Left" },
--   third_right = { {"ctrl", "alt"       }, "Right" },
--   third_up    = { {"ctrl", "alt"       }, "Up" },
--   third_down  = { {"ctrl", "alt"       }, "Down" },
--   top_left    = { {"ctrl",        "cmd"}, "Left" },
--   bottom_left = { {"ctrl",        "cmd", "shift"}, "Left" },
--   top_right   = { {"ctrl",        "cmd"}, "Right" },
--   bottom_right= { {"ctrl",        "cmd", "shift"}, "Right" },
--   max_toggle  = { {        "alt", "cmd", "shift"}, "f" },
--   max         = { {        "alt", "cmd"}, "f" },
--   undo        = { {        "alt", "cmd"}, "z" },
--   center      = { {        "alt", "cmd"}, "c" },
--   larger      = { {        "alt", "cmd", "shift"}, "Right" },
--   smaller     = { {        "alt", "cmd", "shift"}, "Left" },
-- })

hs.loadSpoon("WindowScreenLeftAndRight")
spoon.WindowScreenLeftAndRight:bindHotkeys({
   screen_left = { {"ctrl", "alt", "cmd"}, "Left" },
   screen_right= { {"ctrl", "alt", "cmd"}, "Right" },
})


-- ## notnux only
if hs.host.localizedName() == "notnux" then

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
  activity_log = require "activity-log"
  activity_log:start()

  -- Turn off Caffeine if screen is locked or system sent to sleep
  screen_lock_watcher = hs.caffeinate.watcher.new(function(event)
    if spoon.Caffeine and
      (event == hs.caffeinate.watcher["screensDidLock"] or
      event == hs.caffeinate.watcher["systemWillSleep"]) then

      if hs.caffeinate.get("displayIdle") then
        spoon.Caffeine.clicked()
        logger.i(hs.caffeinate.watcher[event] .. " and spoon.Caffeine on; turning it off")
      end
    end
  end):start()
end

hs.loadSpoon("FadeLogo"):start()
