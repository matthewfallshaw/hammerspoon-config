-- Mission Control Hotkeys
mission_control = {}
function mission_control.missionControlThenRestoreFrontmost(app_windows)
  print("Launching MC. Frontmost: ".. hs.window.frontmostWindow():title())
  hs.execute('"/Applications/Mission Control.app/Contents/MacOS/Mission Control"' .. (app_windows and " 2" or ""))
  print("MC returned. Frontmost: ".. hs.window.frontmostWindow():title())
  local wf = hs.window.filter.new()
  wf:subscribe(hs.window.filter.windowFocused, function()
    if wf.frontmost then
      if wf.frontmost ~= hs.window.frontmostWindow() then print("Wrong window has focus, should be '".. wf.frontmost:title() .."' but is '".. hs.window.frontmostWindow():title() .. "'.")
        wf.frontmost:focus()
      end
    else
      wf.frontmost = hs.window.frontmostWindow()
      print("Window received focus: ".. wf.frontmost:title())
    end
  end)
  hs.timer.doAfter(8, function() wf:unsubscribeAll(); wf = nil; print("wf removed") end)
end
mission_control.hotkeys = {}
mission_control.hotkeys.f9 = hs.hotkey.bind({}, "f9", function() mission_control.missionControlThenRestoreFrontmost() end)
mission_control.hotkeys.f10 = hs.hotkey.bind({}, "f10", function() mission_control.missionControlThenRestoreFrontmost(true) end)
