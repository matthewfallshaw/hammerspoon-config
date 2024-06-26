--- === Seal Config ===
---
--- http://www.hammerspoon.org/Spoons/Seal.html

local M = {}

-- Metadata
M.name = 'SealConfig'
M.version = "0.1"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.license = "MIT - https://opensource.org/licenses/MIT"
M.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"

hs.loadSpoon("Seal")
local seal = spoon.Seal
M.seal = seal
local asana = require('asana')
M.asana = asana

seal:loadPlugins({'calc', 'useractions'})
seal.plugins.useractions.actions = {
  ["New Asana task in " .. init.consts.asanaWorkWorkspaceName] = {
    fn = function(x)
      asana.newTask(x, init.consts.asanaWorkWorkspaceName)
    end,
    keyword = "awork"
  },
  ["New Asana task in " .. init.consts.asanaPersonalWorkspaceName] = {
    fn = function(x)
      asana.newTask(x, init.consts.asanaPersonalWorkspaceName)
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
  -- Audio devices commands
  ["Connect AirPods"]    = { fn = function() changeAudioDevice("AirPod") end },
  ["Connect Built-in"]   = { fn = function() changeAudioDevice("MacBook Pro") end },
  Clock = {
    fn = function()
      spoon.AClock:toggleShowPersistent()
    end
  },
  ["Reorganise Desktop"] = {
    fn = reorganise_desktop
  },
  ["Bundle Id"] = {
    fn = function()
      local _, id = hs.osascript.applescript(
        'id of app "'.. hs.application.frontmostApplication():name() ..'"')
      hs.pasteboard.setContents(id)
      hs.alert.show("BundleId: ".. id)
    end
  },
  ["Activity log"] = {
    fn = function()
      local ms = hs.screen.mainScreen():frame()
      local voffset, hoffset = 30, ms.w / 4
      local rect = hs.geometry.rect(
        ms.x + hoffset, ms.y + voffset, ms.w - 2 * hoffset, ms.h - 2 * voffset)
      local logview = hs.webview.newBrowser(rect):closeOnEscape(true)
      local html = [[
<!doctype html>
<html lang="en">
  <head>
    <!-- Required meta tags -->
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">

    <!-- Bootstrap CSS -->
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css" integrity="sha384-ggOyR0iXCbMQv3Xipma34MD+dH/1fQ784/j6cY/iJTQUOhcWr7x9JvoRxT2MZw1T" crossorigin="anonymous">
    <style>
      pre { margin-left: 2em; }
    </style>
    <title>Activity Log</title>
  </head>
  <body>
    <pre><code>
]].. hs.execute("tail -n50 ~/log/activities.log") ..[[
    </code></pre>

    <!-- Optional JavaScript -->
    <!-- jQuery first, then Popper.js, then Bootstrap JS -->
    <script src="https://code.jquery.com/jquery-3.3.1.slim.min.js" integrity="sha384-q8i/X+965DzO0rT7abK41JStQIAqVgRVzpbzo5smXKp4YfRvH+8abtTE1Pi6jizo" crossorigin="anonymous"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.7/umd/popper.min.js" integrity="sha384-UO2eT0CpHqdSJQ6hJty5KVphtPhzWj9WO1clHTMGa3JDZwrnQq4sF86dIHNDz0W1" crossorigin="anonymous"></script>
    <script src="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/js/bootstrap.min.js" integrity="sha384-JjSmVgyd0p3pXB1rRibZUAYoIIy6OrQ6VrjIEaFf/nJGzIxFDsf4x0xIM+B07jRM" crossorigin="anonymous"></script>
  </body>
</html>
      ]]
      logview:html(html)
      logview:bringToFront()
      logview:show(0.5)
      logview:hswindow():focus()
    end
  },
  ["Diff Texts"] = {
    fn = function()
      local diff_webview
      local usercontent = hs.webview.usercontent.new("compareHandler")
        :setCallback(function(message)
          local text1 = message.body.text1
          local text2 = message.body.text2

          local tmpPath = hs.fs.temporaryDirectory()
          local file1Path = tmpPath .. "text1.txt"
          local file2Path = tmpPath .. "text2.txt"

          local file1 = io.open(file1Path, "w")
          file1:write(text1)
          file1:close()

          local file2 = io.open(file2Path, "w")
          file2:write(text2)
          file2:close()

          -- Use hs.task to run opendiff in the background
          local task = hs.task.new("/usr/bin/opendiff", nil, {file1Path, file2Path})
          task:start()

          -- Close and clean up webview
          if diff_webview then
            diff_webview:delete()
            diff_webview = nil
          end
        end)

      diff_webview = hs.webview.newBrowser({x=100, y=100, w=600, h=350}, {developerExtrasEnabled = true}, usercontent)
        :windowCallback(function(action, webview, state)
          if action == "closing" then
            if diff_webview then
              diff_webview:delete()
              diff_webview = nil
            end
          end
        end)
        :windowStyle("utility") -- Optional: set as utility window
        :level(hs.drawing.windowLevels.floating) -- Make sure it floats above other apps

      diff_webview:html([[
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body { font-family: Arial, sans-serif; padding: 20px; }
                textarea { width: 95%; height: 100px; margin-bottom: 10px; padding: 8px; font-size: 14px; }
                button { padding: 10px 20px; font-size: 16px; cursor: pointer; }
            </style>
        </head>
        <body>
            <textarea id="text1" placeholder="Enter text 1 here"></textarea><br>
            <textarea id="text2" placeholder="Enter text 2 here"></textarea><br>
            <button onclick="submitForm()">Compare</button>

            <script>
                function submitForm() {
                    var text1 = document.getElementById('text1').value;
                    var text2 = document.getElementById('text2').value;
                    try {
                        webkit.messageHandlers.compareHandler.postMessage({text1: text1, text2: text2});
                    } catch(error) {
                        console.error('Error:', error);
                    }
                }
            </script>
        </body>
        </html>
      ]])
      diff_webview:show()
    end,
    keyword = "diff"
  }
}

local chrome_tabs_seal = {
  ['https://drive.google.com/drive/*'] = {
    default = {
      name = 'Docs',
      title = '* - Google Drive',
      keyword = 'gd',
    },
    bellroy = {
      name = 'Docs Bellroy',
      title = '* - Google Drive',
      keyword = 'gdb',
    },
    miri = {
      name = 'Docs MIRI',
      title = '* - Google Drive',
      keyword = 'gdm',
    },
  },
  ['https://mail.google.com/mail/*'] = {
    default = {
      name = 'Gmail',
      title = '* - matthew.fallshaw@gmail.com - Gmail',
      keyword = 'gm',
    },
    bellroy = {
      name = 'Gmail Bellroy',
      title = '* - matt@bellroy.com - Bellroy Mail',
      keyword = 'gmb',
    },
    miri = {
      name = 'Gmail MIRI',
      title = '* - matt@intelligence.org - Machine Intelligence Research Institute Mail',
      keyword = 'gmm',
    },
  },
}
M.chrome_tabs_seal = chrome_tabs_seal
for url, p in pairs(chrome_tabs_seal) do
  for profile, props in pairs(p) do
    seal.plugins.useractions.actions[props.name] = {
      fn = function()
        chrome_tabs.sendCommand({
          focus = {
            profile = profile,
            title = props.title,
            url = url,
          }
        })
      end,
      keyword = props.keyword,
    }
  end
end

local chrome_windows_seal = {
  Default = {
    name = 'Chrome Window Personal',
    keyword = 'cwp',
  },
  Bellroy = {
    name = 'Chrome Window Bellroy',
    keyword = 'cwb',
  },
  MIRI = {
    name = 'Chrome Window MIRI',
    keyword = 'cwm',
  },
}
M.chrome_windows_seal = chrome_windows_seal
for profile, props in pairs(chrome_windows_seal) do
  seal.plugins.useractions.actions[props.name] = {
    fn = function()
      local result
      result = hs.execute('~/.nix-profile/bin/fish -c "~/bin/gchrome '..profile..'"')
      if not string.match(result,'^ *$') then
        logger.e('Seal '..props.name..' had problems creating a new window for profile '..profile': '..result)
        print('bad stuff')
      end
    end,
    keyword = props.keyword,
  }
end

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

return M
