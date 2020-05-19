hs.logger.setGlobalLogLevel('warning')
hs.logger.defaultLogLevel = 'warning'
hs.hotkey.setLogLevel('warning')  -- 'cos it ignores global defaults
hs.window.animationDuration = 0.1
-- hs.doc.hsdocs.forceExternalBrowser(true)
hs.doc.hsdocs.moduleEntitiesInSidebar(true)
hs.application.enableSpotlightForNameSearches(true)
hs.allowAppleScript(true)

return {
  -- modules under test
  modules_under_test = {},

  -- spoon.URLDispatcher
  URLDispatcher = {
    url_patterns = {
      -- { <url pattern>, <application bundle ID> },
       { "https?://www.pivotaltracker.com/n/.*",        "com.fluidapp.FluidApp2.PivotalTracker" },
       { "https?://www.pivotaltracker.com/story/.*",    "com.fluidapp.FluidApp2.PivotalTracker" },
       { "https?://www.pivotaltracker.com/dashboard",   "com.fluidapp.FluidApp2.PivotalTracker" },
       { "https?://www.pivotaltracker.com/reports/.*",  "com.fluidapp.FluidApp2.PivotalTracker" },
       { "https?://www.pivotaltracker.com/projects/.*", "com.fluidapp.FluidApp2.PivotalTracker" },
       { "https?://www.pivotaltracker.com/epic/.*",     "com.fluidapp.FluidApp2.PivotalTracker" },
       { "https?://app.asana.com/.*",                   "org.epichrome.eng.Asana" },
       { "https?://morty.trikeapps.com/.*",             "org.epichrome.eng.Morty" },
       { "https?://app.greenhouse.io/.*",               "org.epichrome.eng.Greenhouse" },
       { "https?://calendar.google.com/.*",             "org.epichrome.eng.GoogleCalend " },
       { "https?://www.google.com/calendar/.*",         "org.epichrome.eng.GoogleCalend" },
    },
    default_handler = "com.google.Chrome"
  },

  -- asana
  -- API key
  -- Generated in My Profile Settings -> Apps -> Manage Developer Apps -> Create New Personal Access Token
  asanaApiKey = hs.execute("security find-generic-password -a ${USER} -s Asana -w | tr -d '\n'"),
  -- Names for Asana workspaces used for work and personal
  asanaWorkWorkspaceName = "bellroy.com",
  asanaPersonalWorkspaceName = "Matt & Lina",

  -- stay

  -- chrome_tabs = require 'chrome_tabs'
  -- chrome_gmail_window_filter = hs.window.filter.new()

  -- app_tabs = require 'app_tabs'
  -- chrome_gmail_window_filter = app_tabs.window_filter.new({['Google Chrome'] = {
      -- tab1 = {url_pattern = '^https://mail%.google%.com/mail/u/0/#'} }})
  -- chrome_docs_window_filter = app_tabs.window_filter.new({['Google Chrome' ]= {
      -- tab1 = {url_pattern = '^https://drive%.google%.com/drive/..[^0]'} }})
  -- safari_gmail_window_filter = app_tabs.window_filter.new({Safari = {
  --     tab1 = {url_pattern = '^https://mail%.google%.com/mail/u/0/'} }})
  -- safari_docs_window_filter = app_tabs.window_filter.new({Safari = {
  --     tab1 = {url_pattern = '^https://drive%.google%.com/drive/u/0/'} }})

  window_layouts = {
    Shared = {
      {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 closest [50,0>100,90] 0,0'},
      -- {'Superhuman', 'move 1 oldest [0,0>90,100] 0,0'},
      {'MailMate', 'move 1 oldest [0,0>60,100] 0,0'},
      {'Morty', 'move 1 oldest [0,0>70,100] 0,0'},
      {'GitX', 'max 1 oldest 0,0'},
      {{['nvALT']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [60,0>100,100] 0,0'},
      {'Notable', 'move 1 oldest [33,0>100,100] 0,0'},
      {{['Finder']={currentSpace=true}},'move 1 closest [35,37>87,80] 0,0'},
      {'Skype', 'move 1 oldest [60,0>100,86] 0,0'},
      {'Messages', 'move 1 oldest [53,0>100,71] 0,0'},
      {'Activity Monitor', 'move 1 oldest [0,42>61,100] 0,0'},
      {'Slack', 'move 1 oldest [40,0>100,100] 0,0'},
      {{['Quicksilver']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [24,12>84,86] 0,0'},
      {'Lights Switch', 'move 1 oldest [59,0>87,67] 0,0'},
    },
    Laptop = {
      screens={['Color LCD']='0,0',
      ['-1,0']=false,['0,-1']=false,['1,0']=false,['0,1']=false}, -- when no external screens
      -- {chrome_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
      -- {chrome_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
      -- {safari_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
      -- {safari_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
      -- {'VimR', 'move 1 closest [0,0>65,100] 0,0'},
      {'iTerm2', 'move 1 oldest [0,0>100,100] 0,0'},
      {'kitty', 'move 1 oldest [0,0>100,100] 0,0'},
      {{'PivotalTracker','Asana','Google Calendar'}, 'max 1 oldest 0,0'},
    },
    MelbourneDesk = {
      screens={['DELL U2718Q']=true, ['1,0']=true},
      -- {'VimR', 'move 1 closest [0,0>35,100] 1,0'},
      {'iTerm2', 'move 1 oldest [30,0>100,100] 1,0'},
      {'PivotalTracker', 'max 1 oldest 1,0'},
      {'Asana', 'move 1 oldest [0,0>50,100] 1,0'},
      {'Google Calendar', 'move 1 oldest [0,8>100,100] 1,0'},
      {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 1,0'},
    },
    MiriDesk1 = {  -- left monitor sometimes detects as '-1,-1'
      screens={['HP Z27']=true, ['DELL U2713HM']=true, ['1,-1']=true},
      -- {'VimR', 'move 1 closest [30,0>65,100] 0,-1'},
      {'iTerm2', 'move 1 oldest [0,0>100,100] 0,-1'},
      {'PivotalTracker', 'max 1 oldest 0,-1'},
      {'Asana', 'move 1 oldest [0,10>100,100] 1,-1'},
      {'Google Calendar', 'move 1 oldest [0,8>100,100] 0,-1'},
      {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 0,-1'},
    },
    MiriDesk2 = {  -- left monitor sometimes detects as '-1,0'
      screens={['HP Z27']=true, ['DELL U2713HM']=true, ['1,0']=true},
      -- {'VimR', 'move 1 closest [30,0>65,100] 0,-1'},
      {'iTerm2', 'move 1 oldest [0,0>100,100] 0,-1'},
      {'PivotalTracker', 'max 1 oldest 0,-1'},
      {'Asana', 'move 1 oldest [0,10>100,100] 1,0'},
      {'Google Calendar', 'move 1 oldest [0,8>100,100] 0,-1'},
      {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 0,-1'},
    },
    BerkeleyDesk = {
      screens={['LG HDR 5K']=true, ['1,0']=true},
      -- {'VimR', 'move 1 closest [36,0>64,100] 1,0'},
      {'iTerm2', 'move 1 oldest [0,0>60,100] 1,0'},
      {'PivotalTracker', 'max 1 oldest 1,0'},
      {'Asana', 'move 1 oldest [0,0>33,100] 1,0'},
      {'Google Calendar', 'move 1 oldest [0,8>100,100] 1,0'},
      {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 1,0'},
    },
    DualLeft = {
      screens={['DELL U2718Q']=false,
      ['-1,0']=true,['0,-1']=false,['1,0']=false,['0,1']=false},
      -- {'VimR', 'move 1 closest [0,0>50,100] -1,0'},
      {'iTerm2', 'move 1 oldest [0,0>100,100] -1,0'},
      {'PivotalTracker', 'max 1 oldest -1,0'},
      {'Asana', 'move 1 oldest [0,0>66,100] -1,0'},
      {'Google Calendar', 'max 2 oldest -1,0'},
      {'FreeMindStarter', 'move 1 oldest [50,0>100,100] -1,0'},
      {'Snagit 2018', 'move 1 oldest [15,12>85,88] -1,0'}
    },
    DualTop = {
      screens={['0,-1']=true,
        ['DELL U2718Q']=false,['DELL U2713HM']=false,['LG HDR 5K']=false,
      ['-1,0']=false,['1,0']=false,['0,1']=false,['-1,-1']=false},
      -- {'VimR', 'move 1 closest [0,0>50,100] 0,-1'},
      {'iTerm2', 'move 1 oldest [0,0>100,100] 0,-1'},
      {'PivotalTracker', 'max 1 oldest 0,-1'},
      {'Asana', 'move 1 oldest [0,0>67,100] 0,-1'},
      {'Google Calendar', 'move 1 oldest [0,8>100,100] 0,-1'},
      {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 0,-1'},
    },
  },

  -- control_plane_wifi_security_watcher
  trusted_open_networks = {"Blackthorne"}
}
