-- p = require 'utilities.profile'
-- p:start()

--luacheck: allow defined top

local consts = require 'configConsts'

init = {}  -- watchers & etc.

local logger = hs.logger.new("Init")
init.logger = logger
hs.console.clearConsole()

i = hs.inspect.inspect  -- luacheck: ignore

-- # Setup for everything else #
--
-- Capture spoon (and other) hotkeys
hs.loadSpoon("CaptureHotkeys")
spoon.CaptureHotkeys:bindHotkeys({show = {{ "⌘", "⌥", "⌃", "⇧" }, "k"}}):start()

local log = require('utilities.log').new(logger)

-- Auto-reload config
init.auto_reload_or_test = require 'auto_reload_or_test'
init.auto_reload_or_test:start()

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
control_plane = require('control_plane'):start()  -- luacheck: ignore


-- Stay replacement: Keep App windows in their places
stay = require('stay'):start()  -- luacheck: ignore
spoon.CaptureHotkeys:capture(
  "Stay", "Toggle layout engine or report frontmost window",
  {"⌘", "⌥", "⌃", "⇧"}, "s")


-- Jettison replacement: Eject ejectable drives on sleep
-- jettison = require('jettison')
-- jettison:start()


-- Google Play Music Desktop Player Hotkeys
gpmdp = require('gpmdp')
gpmdp.hotkeys = {}
local gpmdp_hotkeymap = {
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
for fn_name, map in pairs(gpmdp_hotkeymap) do
  gpmdp.hotkeys[fn_name] = hs.hotkey.bind(map[1], map[2], function() gpmdp[fn_name]() end)
end
spoon.CaptureHotkeys:capture("GPMDP", gpmdp_hotkeymap)


-- Trash recent downloads
trash_recent = require('trash_recent')
trash_recent.hotkey = spoon.CaptureHotkeys:bind(
  "Trash recent download", "trashRecentDownload", {"⌥", "⌃", "⇧", "⌘"}, "t",
  trash_recent.trashRecentDownload)


-- ScanSnap: Start ScanSnap's horrendous array of apps when scanner attached, and kill them when detatched
logger.i("Loading ScanSnap USB watcher")
local function usbDeviceCallback(data)
  logger.d(data['productName']..' '..data['eventType'])
  -- ScanSnap Home's apps are not properly registered (named) and there are several of them, so matches and arrays…
  if (data["productName"]:match("^ScanSnap")) then
    if (data['eventType'] == 'added') then
      log:and_alert(data['productName'].. ' added, launching ScanSnap Home')
      hs.application.launchOrFocus('ScanSnapHomeMain')
    elseif (data['eventType'] == 'removed') then
      hs.fnutils.ieach(table.pack(hs.application.find("ScanSnap")), function(app)
        log:and_alert(data['productName'].. ' removed, closing '.. app:name())
        app:kill()
      end)
      if hs.application.get('AOUMonitor') then hs.application.get('AOUMonitor'):kill9() end
    end
  end
end
logger.i("Starting ScanSnap USB watcher")
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
spoon.URLDispatcher.default_handler = consts.URLDispatcher.default_handler
spoon.URLDispatcher.url_patterns = consts.URLDispatcher.url_patterns
spoon.URLDispatcher.logger.setLogLevel('debug')
spoon.URLDispatcher:start()
-- URLs from hammerspoon:// schema
local _, unescape = require('utilities.string_escapes')()
local function URLDispatcherCallback(_, params)
  local fullUrl = unescape.url(params.uri)
  local parts = hs.http.urlParts(fullUrl)
  spoon.URLDispatcher:dispatchURL(parts.scheme, parts.host, parts.parameterString, fullUrl)
end
spoon.URLDispatcher.url_dispatcher = hs.urlevent.bind("URLDispatcher", URLDispatcherCallback)


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


hs.loadSpoon("HeadphoneAutoPause")
spoon.HeadphoneAutoPause.control['vox'] = false
spoon.HeadphoneAutoPause.control['deezer'] = false
spoon.HeadphoneAutoPause.control['Google Play Music Desktop Player'] = true
spoon.HeadphoneAutoPause.controlfns['Google Play Music Desktop Player'] =
  gpmdp.spoons.HeadphoneAutoPause.controlfns['Google Play Music Desktop Player']
spoon.HeadphoneAutoPause:start()


hs.loadSpoon("AppHotkeys")
local hks = spoon.AppHotkeys.hotkeys
-- Terminal ⌘1-9 to tab focus
logger.i("Terminal hotkeys for switching ⌘1-9 to Tab focus")
for i=1,8 do
  table.insert(hks["Terminal"], hs.hotkey.new('⌘', tostring(i), function()
    hs.osascript.applescript('tell application "Terminal" to set selected of tab ' .. i .. ' of first window to true')
  end))
end
table.insert(hks["Terminal"], hs.hotkey.new('⌘', "9", function()
  hs.osascript.applescript('tell application "Terminal" to set selected of last tab of first window to true')
end))
spoon.CaptureHotkeys:capture("Terminal", {
  ["Select tab n"] = { {"⌘"}, "n" },
  ["Select last tab"] = { {"⌘"}, "9" },
})
-- Slack usability improvements
logger.i("Slack usability hotkeys")
table.insert(hks["Slack"], hs.hotkey.new('⌘', 'w', function()
  hs.eventtap.keyStrokes("/leave ")
  hs.timer.doAfter(0.3, function() hs.application.get("Slack"):activate(); hs.eventtap.keyStroke({}, "return") end)
end))
table.insert(hks["Slack"],
             hs.hotkey.new('⌘⇧', ']', function() hs.eventtap.keyStroke({'alt'}, 'down') end))
table.insert(hks["Slack"],
             hs.hotkey.new('⌘⇧', '[', function() hs.eventtap.keyStroke({'alt'}, 'up') end))
spoon.CaptureHotkeys:capture("Slack", {
  ["Close Channel"] = { {"⌘"}, "w" },
  ["Next Channel"] = { {"⌘", "⇧"}, "]" },
  ["Previous Channel"] = { {"⌘", "⇧"}, "[" },
})
-- VimR tab switching
logger.i("VimR hotkeys for switching tabs")
local function slowkeys(keys)
  -- Hack: `hs.eventtap.keyStrokes` causes random dups & omissions (':tapprrvious')
  local delay = 5000
  local mt = {__index=function(_,c) return {{},c,delay} end}
  local codes = setmetatable({[':']={{'shift'},';',delay}}, mt)
  for c in string.gmatch(keys,'.') do
    hs.eventtap.keyStroke(table.unpack(codes[c]))
  end
  hs.eventtap.keyStrokes("\n")
end
table.insert(hks["VimR"], hs.hotkey.new({'⌘', '⇧'}, '[', function()
  slowkeys(":tabprevious")
end))
table.insert(hks["VimR"], hs.hotkey.new({'⌘', '⇧'}, ']', function()
  slowkeys(':tabNext')
end))
spoon.AppHotkeys:start()


-- ChromeTabs
chrome_tabs = require('chrome_tabs')
-- chrome_tabs.chooser = require('chrome_tabs.chrome_tab_chooser')
-- chrome_tabs.chooser.hotkey = spoon.CaptureHotkeys:bind("ChromeTabs", "Find & focus a Chrome tab",
--     {'⌘','⇧','⌃'}, 'n', function() chrome_tabs.chooser.show() end)


local mwm = hs.loadSpoon("MiroWindowsManager")
mwm.sizes = {2, 3/2, 3}
mwm.fullScreenSizes = {1, 4/3, 2, 'c'}
mwm.GRID = {w = 24, h = 12}
mwm.stickySides = true
mwm:bindHotkeys({
  up          = {{    '⌥',    '⌘'}, 'k'},
  down        = {{    '⌥',    '⌘'}, 'j'},
  left        = {{    '⌥',    '⌘'}, 'h'},
  right       = {{    '⌥',    '⌘'}, 'l'},
  fullscreen  = {{    '⌥',    '⌘'}, 'f'},
  center      = {{    '⌥',    '⌘'}, 'c'},
  move        = {{    '⌥',    '⌘'}, "v"},
  resize      = {{    '⌥',    '⌘'}, "d" },
})


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
move_spaces:start()


hs.loadSpoon("Seal")
local seal = spoon.Seal
seal:loadPlugins({'apps', 'calc', 'useractions'})
seal.plugins.useractions.actions = {
  ["New Asana task in " .. consts.asanaWorkWorkspaceName] = {
    fn = function(x)
      newAsanaTask(x, consts.asanaWorkWorkspaceName)
      refocusAfterUserAction()
    end,
    keyword = "awork"
  },
  ["New Asana task in " .. consts.asanaPersonalWorkspaceName] = {
    fn = function(x)
      newAsanaTask(x, consts.asanaPersonalWorkspaceName)
      refocusAfterUserAction()
    end,
    keyword = "ahome"
  },
  -- System commands
  ["Restart/Reboot"] = {
    fn = function()
      hs.caffeinate.restartSystem()
    end
  },
  ["Shutdown"] = {
    fn = function()
      hs.caffeinate.shutdownSystem()
    end
  },
  ["Lock"] = {
    fn = function()
      hs.eventtap.keyStroke({"cmd", "ctrl"}, "q")
    end
  },
  ["Hammerspoon Docs"] = {
    fn = function(x)
      if x ~= '' then
        hs.doc.hsdocs.help(x)
      else
        hs.doc.hsdocs.help()
      end
    end,
    keyword = "hsdocs"
  },
  Gmail = {
    fn = function()
      chrome_tabs.sendCommand( { focus = {
        title="* - matthew.fallshaw@gmail.com - Gmail",
        url="https://mail.google.com/mail/u/0/*" }})
    end,
    keyword = "gm"
  },
  Docs = {
    fn = function()
      chrome_tabs.sendCommand( { focus = {
        title="* - Google Drive",
        url="https://drive.google.com/drive/*",
        not_url="^https://drive.google.com/drive/u" }})
    end,
    keyword = "docs"
  },
  ["Bellroy Docs"] = {
    fn = function()
      chrome_tabs.sendCommand( { focus = {
        title="* - Google Drive",
        url="https://drive.google.com/drive/u/1/*" }})
    end,
    keyword = "bdocs"
  },
  ["MIRI Docs"] = {
    fn = function()
      chrome_tabs.sendCommand( { focus = {
        title="* - Google Drive",
        url="https://drive.google.com/drive/u/2/*" }})
    end,
    keyword = "mdocs"
  },
}
seal:refreshAllCommands()
seal:bindHotkeys({ toggle = {{'⌃','⌥','⌘'}, 'space'}, })
seal:start()
-- asana plugin
-- remember keys used for choices
-- fuzzy search
-- help
-- gpmdp commands
-- pass queryChangedCallback function for second level results
-- tab command completion
-- faster Chrome tab search (see how Vimium 'T' does it)


-- # notnux only #
--
if hs.host.localizedName() == "notnux2" then

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
  activity_log = require('activity_log')
  activity_log:start()

  -- mission_control_hotkeys = require('mission_control_hotkeys')
end

-- p:stop()
-- p:writeReport('build/profile.txt')

hs.loadSpoon("FadeLogo"):start()
