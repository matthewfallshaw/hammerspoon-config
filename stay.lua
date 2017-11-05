-- Keep App windows in their places
local logger = hs.logger.new("Stay")
logger.i("Loading Stay")
hs.window.filter.setLogLevel(1)  -- wfilter is very noisy

local M = {}

M.window_layouts = {} -- see bottom of file
M.window_layouts_enabled = false

function M:report_frontmost_window()
  local window = hs.application.frontmostApplication():focusedWindow()
  local filter_string
  if window:subrole() == 'AXStandardWindow' then
    filter_string = string.format("'%s'", window:application():name())            
  else
    filter_string = string.format("{['%s']={allowRoles='%s'}}", window:application():name(), window:subrole())            
  end
  local unit_rect = window:screen():toUnitRect(window:frame())
  local unit_rect_string = string.format("[%.0f,%.0f>%.0f,%.0f]",
            unit_rect.x1*100,unit_rect.y1*100,unit_rect.x2*100,unit_rect.y2*100)
  local screen_position_string = string.format("%i,%i", window:screen():position())
  local action_string
  if unit_rect_string == "[0,0>100,100]" then
    action_string = string.format("'maximize 1 oldest %s'", screen_position_string)
  else
    action_string = string.format("'move 1 oldest %s %s'", unit_rect_string, screen_position_string)
  end
  local layout_rule = string.format("{%s, %s}", filter_string, action_string)
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


app_tabs = require "app-tabs"
chrome_gmail_window_filter = app_tabs.window_filter.new({['Google Chrome'] = {
    tab1 = {url_pattern = "^https://mail%.google%.com/mail/u/0/"} }})
chrome_docs_window_filter = app_tabs.window_filter.new({['Google Chrome' ]= {
    tab1 = {url_pattern = "^https://drive%.google%.com/drive/u/0/"} }})
safari_gmail_window_filter = app_tabs.window_filter.new({Safari = {
    tab1 = {url_pattern = "^https://mail%.google%.com/mail/u/0/"} }})
safari_docs_window_filter = app_tabs.window_filter.new({Safari = {
    tab1 = {url_pattern = "^https://drive%.google%.com/drive/u/0/"} }})

M.window_layouts = {
  shared = hs.window.layout.new({
    {'Morty', 'move 1 oldest [0,0>70,100] 0,0'},
    {'GitX', 'max all 0,0'},
    {{['nvALT']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [63,0>100,79] 0,0'},
    {'Finder','move 1 oldest [40,44>94,92] 0,0'},
    {'Skype', 'move 1 oldest [56,0>100,70] 0,0'},
    {'Messages', 'move 1 oldest [53,0>100,71] 0,0'},
    {'Activity Monitor', 'move 1 oldest [0,42>61,100] 0,0'},
    {'Slack', 'move 1 oldest [40,0>100,100] 0,0'},
    {{['Quicksilver']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [24,12>84,86] 0,0'},
  },'SHARED'),
  laptop = hs.window.layout.new({
    screens={['Color LCD']='0,0',['-1,0']=false,['0,-1']=false,['1,0']=false,['0,1']=false}, -- when no external screens
    {chrome_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    {chrome_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
    {safari_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    {safari_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
    {'MacVim', 'move 1 oldest [0,0>65,100] 0,0'},
    {{'Terminal', 'iTerm2'}, 'move 1 oldest [50,0>100,100] 0,0'},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,0'},
    {{'PivotalTracker','Asana','Google Calendar','Calendar','FreeMindStarter'},
      'max all 0,0'},
    {'Greenhouse', 'maximize 1 oldest 0,0'},
  },'LAPTOP'),
  dualleft = hs.window.layout.new({
    screens={['-1,0']=true,['0,-1']=false,['1,0']=false,['0,1']=false},
    {chrome_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    {chrome_docs_window_filter, 'move 1 oldest [20,0>80,100] -1,0'},
    {safari_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    {safari_docs_window_filter, 'move 1 oldest [20,0>80,100] -1,0'},
    {'MacVim', 'move 1 oldest [0,0>50,100] -1,0'},
    {{'Terminal', 'iTerm2'}, 'move 1 oldest [50,0>100,100] -1,0'},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,0'},
    {'PivotalTracker', 'max 1 oldest -1,0'},
    {'Asana', 'move 1 oldest [0,0>66,100] -1,0'},
    {'Google Calendar', 'max 2 oldest -1,0'},
    {'Calendar', 'max 1 oldest -1,0'},
    {'FreeMindStarter', 'move 1 oldest [50,0>100,100] -1,0'},
    {'Greenhouse', 'maximize 1 oldest -1,0'},
  },'DUALLEFT'),
  dualtop = hs.window.layout.new({
    screens={['-1,0']=false,['0,-1']=true,['1,0']=false,['0,1']=false},
    {chrome_gmail_window_filter, 'move 1 oldest [0,0>60,100] 0,-1'},
    {chrome_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
    {safari_gmail_window_filter, 'move 1 oldest [0,0>60,100] 0,-1'},
    {safari_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
    {'MacVim', 'move 1 oldest [0,0>50,100] 0,-1'},
    {{'Terminal', 'iTerm2'}, 'move 1 oldest [50,0>100,100] 0,-1'},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,-1'},
    {'PivotalTracker', 'max 1 oldest 0,-1'},
    {'Asana', 'move 1 oldest [0,0>66,100] 0,-1'},
    {'Google Calendar', 'max 2 oldest 0,-1'},
    {'Calendar', 'max 1 oldest 0,-1'},
    {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 0,-1'},
    {'Greenhouse', 'maximize 1 oldest -1,0'},
  },'DUALTOP'),
}

return M
