-- Keep App windows in their places
local logger = hs.logger.new("Stay")
logger.i("Loading Stay")
hs.window.filter.setLogLevel(1)  -- wfilter is very noisy

local M = {}

M.window_layouts = {} -- see bottom of file
M.window_layouts_enabled = false


local function escape_for_regexp(str)
  return (str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1"))
end

local CHROME_TITLE_REPLACE_STRING = "AEDA6OHZOOBOO4UL8OHH" -- an arbitrary string
local chrome_tab_list_applescript = [[
tell application "Google Chrome"
	set the_tabs to {}
	repeat with the_tab in (tabs of (the first window whose title is "]].. CHROME_TITLE_REPLACE_STRING ..[["))
		set end of the_tabs to {URL of the_tab, title of the_tab}
	end repeat
	return the_tabs
end tell
]]
local function chrome_window_first_tab(window)
  local window_title_escaped_for_applescript_and_regexp = window:title():gsub("\"","\\\""):gsub("%%","%%%%")
  local success, applescript_text = pcall(string.gsub, chrome_tab_list_applescript, CHROME_TITLE_REPLACE_STRING, window_title_escaped_for_applescript_and_regexp)
  if not success then error("Bad strings: ".. hs.inspect({applescript_text,window:title(),chrome_tab_list_applescript,CHROME_TITLE_REPLACE_STRING})) end
  local out, window_tabs_raw, err = hs.osascript.applescript(applescript_text)
  if out and window_tabs_raw and window_tabs_raw[1] then
    local first_tab = window_tabs_raw[1]  -- assume the first tab is the interesting one
    local url, title = first_tab[1], first_tab[2]
    return url, title
  else
    -- If tabs change too fast handoff between HS & applescript can fail
    return nil, nil
  end
end

local function chrome_window_with_first_tab_matching(window, url_start_target)
  if window and (window:role() == "AXWindow") and (window:application():name() == "Google Chrome") then
    local url,_= chrome_window_first_tab(window)
    local found = url and url:match("^".. escape_for_regexp(url_start_target))
    return found and true
  else
    return false
  end
end

local chrome_gmail_window_filter = hs.window.filter.new(function(window)
  return chrome_window_with_first_tab_matching(window, "https://mail.google.com/mail/u/0/")
end)
chrome_docs_window_filter = hs.window.filter.new(function(window)
  return chrome_window_with_first_tab_matching(window, "https://drive.google.com/drive/u/0/")
end)


function M:report_frontmost_window()
  local window = hs.application.frontmostApplication():focusedWindow()
  local unit_rect = window:screen():toUnitRect(window:frame())
  local unit_rect_string = string.format("[%.0f,%.0f>%.0f,%.0f]",
            unit_rect.x1*100,unit_rect.y1*100,unit_rect.x2*100,unit_rect.y2*100)
  local screen_position_string = string.format("%i,%i", window:screen():position())
  local layout_rule
  if unit_rect_string == "[0,0>100,100]" then
    layout_rule = string.format("{{['%s']={allowScreens='%s'}}, 'maximize 1 oldest %s'},",
      window:application():name(),screen_position_string,screen_position_string)
  else
    layout_rule = string.format("{{['%s']={allowScreens='%s'}}, 'move 1 oldest %s %s'},",
      window:application():name(),screen_position_string,unit_rect_string,screen_position_string)
  end
  hs.pasteboard.setContents(layout_rule)
  logger.w("Active window position:\n".. layout_rule)
  hs.alert.show("Stay: Active window position in clipboard\n".. layout_rule)
  return layout_rule
end

function M:toggle_window_layouts_enabled()
  if self.window_layouts_enabled then
    self:window_layouts_disable()
  else
    self:window_layouts_enable()
  end
  return self
end

function M:window_layouts_enable()
  if not self.window_layouts_enabled then
    for _,layout in pairs(self.window_layouts) do layout:start() end
    self.window_layouts_enabled = true
    if self.disable_startup_alert then
      self.disable_startup_alert = nil -- no alert at startup
    else
      hs.alert.show("Stay: Window auto-layout engine started")
    end
  end
  return self
end

function M:window_layouts_disable()
  if self.window_layouts_enabled then
    for _,layout in pairs(self.window_layouts) do layout:stop() end
    self.window_layouts_enabled = false
    hs.alert.show("Stay: Window auto-layout engine paused")
  end
  return self
end

function M:toggle_or_report()
  if not self.double_tap_timer then
    -- If called once, toggle_window_layouts_enabled
    self.double_tap_timer = {
      name = "toggle",
      timer = hs.timer.doAfter(0.5, function()
        self.double_tap_timer = nil
        self:toggle_window_layouts_enabled()
      end)
    }
  elseif self.double_tap_timer.name == "toggle" then
    -- If called twice quickly, report_frontmost_window
    self.double_tap_timer.timer:stop()
    self.double_tap_timer = {
      name = "report",
      timer = hs.timer.doAfter(0.5, function()
        self.double_tap_timer = nil
        self:report_frontmost_window()
      end)
    }
  else
    -- If called thrice quickly, report_frontmost_window & open this file
    self.double_tap_timer.timer:stop()
    self.double_tap_timer = nil
    self:report_frontmost_window()
    hs.execute("/usr/bin/open ".. debug.getinfo(1).short_src)
  end
  return self
end

function M:start()
  self.disable_startup_alert = true
  self:window_layouts_enable()
  self.disable_startup_alert = nil

  self.hotkey = self.hotkey or hs.hotkey.new({"⌘", "⌥", "⌃", "⇧"}, "s", function() M:toggle_or_report() end)
  self.hotkey:enable() 
  return self
end
function M:stop()
  self:window_layouts_disable()
  if self.hotkey then self.hotkey:disable() end
  return self
end


M.window_layouts = {
  shared = hs.window.layout.new({
    {{['Morty']={allowScreens='0,0'}}, 'move 1 oldest [0,0>70,100] 0,0'},
    -- allowScreens='0,0' so that it only applies to windows on the main screen, 
    -- so in desk mode I can temporarily "tear off" windows to the side screens
    -- for manual management
    {{['GitX']={allowRoles='AXStandardWindow'}}, 'max all 0,0'},
    {{['nvALT']={allowRoles='AXStandardWindow', allowScreens='0,0'}}, 'move 1 oldest [63,0>100,79] 0,0'},
    {{['Finder']={allowScreens='0,0'}},'move 1 oldest [40,44>94,92] 0,0'},
    {{['Skype']={allowScreens='0,0'}}, 'move 1 oldest [56,0>100,70] 0,0'},
    {{['Messages']={allowScreens='0,0'}}, 'move 1 oldest [53,0>100,71] 0,0'},
    {{['Activity Monitor']={allowScreens='0,0'}}, 'move 1 oldest [0,42>61,100] 0,0'},
    {{['Slack']={allowScreens='0,0'}}, 'move 1 oldest [40,0>100,100] 0,0'},
  },'SHARED'),
  laptop = hs.window.layout.new({
    screens={['Color LCD']='0,0',['-1,0']=false,['0,-1']=false,['1,0']=false,['0,1']=false}, -- when no external screens
    {chrome_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    {chrome_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
    {'MacVim', 'move 1 oldest [0,0>65,100] 0,0'},
    {{'Terminal', 'iTerm2'}, 'move 1 oldest [50,0>100,100] 0,0'},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,0'},
    {{'PivotalTracker','Asana','Google Calendar','Calendar','FreeMindStarter'},
      'max all 0,0'},
    {'greenhouse', 'maximize 1 oldest 0,0'},
  },'LAPTOP'),
  dualleft = hs.window.layout.new({
    screens={['-1,0']=true,['0,-1']=false,['1,0']=false,['0,1']=false},
    {chrome_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    {chrome_docs_window_filter, 'move 1 oldest [20,0>80,100] -1,0'},
    {'MacVim', 'move 1 oldest [0,0>50,100] -1,0'},
    {{'Terminal', 'iTerm2'}, 'move 1 oldest [50,0>100,100] -1,0'},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,0'},
    {'PivotalTracker', 'max 1 oldest -1,0'},
    {'Asana', 'move 1 oldest [0,0>66,100] -1,0'},
    {'Google Calendar', 'max 2 oldest -1,0'},
    {'Calendar', 'max 1 oldest -1,0'},
    {'FreeMindStarter', 'move 1 oldest [50,0>100,100] -1,0'},
    {'greenhouse', 'maximize 1 oldest -1,0'},
  },'DUALLEFT'),
  dualtop = hs.window.layout.new({
    screens={['-1,0']=false,['0,-1']=true,['1,0']=false,['0,1']=false},
    {chrome_gmail_window_filter, 'move 1 oldest [0,0>60,100] 0,-1'},
    {chrome_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
    {'MacVim', 'move 1 oldest [0,0>50,100] 0,-1'},
    {{'Terminal', 'iTerm2'}, 'move 1 oldest [50,0>100,100] 0,-1'},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,-1'},
    {'PivotalTracker', 'max 1 oldest 0,-1'},
    {'Asana', 'move 1 oldest [0,0>66,100] 0,-1'},
    {'Google Calendar', 'max 2 oldest 0,-1'},
    {'Calendar', 'max 1 oldest 0,-1'},
    {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 0,-1'},
    {'greenhouse', 'maximize 1 oldest -1,0'},
  },'DUALTOP'),
}

return M
