hs.logger.setGlobalLogLevel('warning')
hs.logger.defaultLogLevel = 'warning'
local logger = hs.logger.new("Init")
hs.console.clearConsole()

-- Capture spoon (and other) hotkeys
hs.loadSpoon("CaptureHotkeys")
spoon.CaptureHotkeys:bindHotkeys({show = {{ "⌘", "⌥", "⌃", "⇧" }, "k"}})
spoon.CaptureHotkeys:start()

-- Load spoon.Hammer first, since it gives us config reload & etc.
hs.loadSpoon("Hammer")
spoon.Hammer:bindHotkeys({
  config_reload ={{"⌘", "⌥", "⌃", "⇧"}, "r"},
  toggle_console={{"⌘", "⌥", "⌃", "⇧"}, "h"},
})
spoon.Hammer:start()
hs.hotkey.bind({"⌘", "⌥", "⌃", "⇧"}, "c", function() hs.console.clearConsole() end)
spoon.CaptureHotkeys:capture("Clear console", {["Clear console"] = { {"⌘", "⌥", "⌃", "⇧"}, "c" }})

hs.application.enableSpotlightForNameSearches(true)
hs.allowAppleScript(true)


u = require 'utilities'


-- Control Plane replacement: Actions on change of location
control_plane = require 'control-plane'
control_plane:start()


-- Stay replacement: Keep App windows in their places
stay = require 'stay'
stay:start()
spoon.CaptureHotkeys:capture("Stay", {
  ["Toggle layout engine or report frontmost window"] = { {"⌘", "⌥", "⌃", "⇧"}, "s" },
})


-- ScanSnap: Start ScanSnap manager when scanner attached
logger.i("Loading ScanSnap USB watcher")
function usbDeviceCallback(data)
  if (data["productName"]:match("^ScanSnap")) then
    if (data["eventType"] == "added") then
      u.log_and_alert(logger, data["productName"].. " added, launching ScanSnap Manager")
      hs.application.launchOrFocus("ScanSnap Manager")
    elseif (data["eventType"] == "removed") then
      local app = hs.application.find("ScanSnap Manager")
      if app then
        u.log_and_alert(logger, data["productName"].. " removed, closing ScanSnap Manager")
        app:kill()
      end
      if hs.application.get("AOUMonitor") then hs.application.get("AOUMonitor"):kill9() end
    end
  end
end
usbWatcher = hs.usb.watcher.new(usbDeviceCallback)
logger.i("Starting ScanSnap USB watcher")
usbWatcher:start()


-- Jettison replacement: Eject ejectable drives on sleep
logger.i("Loading Jettison sleep watcher")
function sleepWatcherCallback(event)
  if event == hs.caffeinate.watcher.systemWillSleep then
    local result, output = hs.osascript.applescript('tell application "Finder" to return (URL of every disk whose ejectable is true)')
    if output then
      hs.caffeinate.declareUserActivity()  -- prevent sleep to give us time to eject drives
      u.log_and_alert(logger, "Ejecting drives before sleep…")
      hs.osascript.applescript('tell application "Finder" to eject (every disk whose ejectable is true)')
      u.log_and_alert(logger, "… drives ejected.")
      hs.caffeinate.systemSleep()
    end
  end
end
sleepWatcher = hs.caffeinate.watcher.new(sleepWatcherCallback)
logger.i("Starting Jettison sleep watcher")
sleepWatcher:start()


-- Transmission safety: Keep VPN running when Transmission is running
logger.i("Loading Transmission VPN Guard")
function applicationWatcherCallback(appname, event, app)
  if appname == "Transmission" and event == hs.application.watcher.launching then
    if not hs.application.get("Private Internet Access") then
      u.log_and_alert(logger, "Transmission launch detected… launching PIA")
      hs.application.open("Private Internet Access")
    else
      u.log_and_alert(logger, "Transmission launch detected… but PIA already running")
    end
  elseif appname == "Private Internet Access" and event == hs.application.watcher.terminated then
    if hs.application.get("Transmission") then
      u.log_and_alert(logger, "PIA termination detected… killing Transmission")
      hs.application.get("Transmission"):kill9()
    else
      u.log_and_alert(logger, "PIA termination detected… Transmission not running, so no action")
    end
  end
end
applicationWatcher = hs.application.watcher.new(applicationWatcherCallback)
logger.i("Starting Transmission VPN Guard")
applicationWatcher:start()


-- Garmin auto ejector
logger.i("Loading Garmin volume auto-ejector")
function garminEjectWatcherCallback(event, info)
  if event == hs.fs.volume.didMount and info.path:match("/Volumes/GARMIN") then
    u.log_and_alert(logger, "Garmin volume mounted… go away pesky Garmin volume")
    hs.fs.volume.eject(info.path)
  end
end
garminEjectWatcher = hs.fs.volume.new(garminEjectWatcherCallback)
logger.i("Starting Garmin volume auto-ejector")
garminEjectWatcher:start()


-- iTunes Hotkeys
hs.itunes = require 'extensions.itunes' -- hs.itunes with improvements
itunes_hotkeys = {}
local ituneshotkeymap = {
  playpause = {{"⌥", "⌃", "⇧"}, "p"},
  next      = {{"⌥", "⌃", "⇧"}, "n"},
  like      = {{"⌥", "⌃", "⇧"}, "l"},
  dislike   = {{"⌥", "⌃", "⇧"}, "d"},
  hide      = {{"⌥", "⌃", "⇧"}, "h"},
  quit      = {{"⌥", "⌃", "⇧"}, "q"},
  -- mute      = {{"⌥", "⌃", "⇧"}, "f10"},
  volumeDown= {{"⌥", "⌃", "⇧"}, "f11"},
  volumeUp  = {{"⌥", "⌃", "⇧"}, "f12"},
}
for fn_name, map in pairs(ituneshotkeymap) do
  itunes_hotkeys[fn_name] = hs.hotkey.bind(map[1], map[2], function() hs.itunes[fn_name]() end)
end
spoon.CaptureHotkeys:capture("iTunes", ituneshotkeymap)


-- URLs from hammerspoon:// schema
local function hex_to_char(x)
  return string.char(tonumber(x, 16))
end
local function unescape(url)
  return url:gsub("%%(%x%x)", hex_to_char)
end
function URLDispatcherCallback(eventName, params)
  local fullUrl = unescape(params.uri)
  local parts = hs.http.urlParts(fullUrl)
  spoon.URLDispatcher:dispatchURL(parts.scheme, parts.host, parts.parameterString, fullUrl)
end
url_dispatcher = hs.urlevent.bind("URLDispatcher", URLDispatcherCallback)


-- Spoons (other than spoon.Hammer)
-- ## All hosts
hs.loadSpoon("URLDispatcher")
spoon.URLDispatcher.default_handler = "com.google.Chrome"
spoon.URLDispatcher.url_patterns = {
  -- { <url pattern>, <application bundle ID> },
  { "https?://www.pivotaltracker.com/.*", "com.fluidapp.FluidApp.PivotalTracker" },
  { "https?://morty.trikeapps.com/.*",    "org.epichrome.app.Morty" },
  { "https?://app.asana.com/.*",          "org.epichrome.app.Asana" },
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
spoon.HeadphoneAutoPause.control['vox'] = nil
spoon.HeadphoneAutoPause.controlfns['vox'] = nil
spoon.HeadphoneAutoPause.control['deezer'] = nil
spoon.HeadphoneAutoPause.controlfns['deezer'] = nil
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


hs.loadSpoon("WindowHalfsAndThirds")
spoon.WindowHalfsAndThirds:bindHotkeys({
  left_half   = { {        "alt", "cmd"}, "Left" },
  right_half  = { {        "alt", "cmd"}, "Right" },
  top_half    = { {        "alt", "cmd"}, "Up" },
  bottom_half = { {        "alt", "cmd"}, "Down" },
  third_left  = { {"ctrl", "alt"       }, "Left" },
  third_right = { {"ctrl", "alt"       }, "Right" },
  third_up    = { {"ctrl", "alt"       }, "Up" },
  third_down  = { {"ctrl", "alt"       }, "Down" },
  top_left    = { {"ctrl",        "cmd"}, "Left" },
  bottom_left = { {"ctrl",        "cmd", "shift"}, "Left" },
  top_right   = { {"ctrl",        "cmd"}, "Right" },
  bottom_right= { {"ctrl",        "cmd", "shift"}, "Right" },
  max_toggle  = { {        "alt", "cmd", "shift"}, "f" },
  max         = { {        "alt", "cmd"}, "f" },
  undo        = { {        "alt", "cmd"}, "z" },
  center      = { {        "alt", "cmd"}, "c" },
  larger      = { {        "alt", "cmd", "shift"}, "Right" },
  smaller     = { {        "alt", "cmd", "shift"}, "Left" },
})

hs.loadSpoon("WindowScreenLeftAndRight")
spoon.WindowScreenLeftAndRight:bindHotkeys({
   screen_left = { {"ctrl", "alt", "cmd"}, "Left" },
   screen_right= { {"ctrl", "alt", "cmd"}, "Right" },
})


-- ## notnux only
if hs.host.localizedName() == "notnux" then

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

end

hs.loadSpoon("FadeLogo"):start()
