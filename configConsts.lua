hs.logger.setGlobalLogLevel('warning')
hs.logger.defaultLogLevel = 'warning'
hs.hotkey.setLogLevel('warning') -- 'cos it ignores global defaults
hs.window.animationDuration = 0.1
-- hs.doc.hsdocs.forceExternalBrowser(true)
hs.doc.hsdocs.moduleEntitiesInSidebar(true)
hs.application.enableSpotlightForNameSearches(true)
hs.allowAppleScript(true)

return {
  -- modules under test
  modules_under_test = {},

  -- Timing constants (in seconds) for window/space operations
  timing = {
    WINDOW_FOCUS_WAIT = 0.8,      -- 0.2 seconds - time to wait after focusing a window
    DISPLAY_MOVE_WAIT = 0.8,      -- 0.2 seconds - time to wait after moving window to different display
    SPACE_MOVE_TIMEOUT = 0.8,     -- 0.2 seconds - timeout for space move operations
    SPACE_CHANGE_WAIT = 1.2,      -- 0.3 seconds - time to wait after space change
    SCREEN_ACTIVATION_WAIT = 0.8, -- 0.2 seconds - time to wait after activating a screen
    ADJACENT_MOVE_TIMEOUT = 0.5,  -- 0.05 seconds - timeout for adjacent space moves
    RETURN_DELAY = 0.1,           -- 0.1 seconds - delay before returning to original space
    DOUBLE_TAP_WINDOW = 0.25,     -- 0.25 seconds - double-tap detection window
    MOVE_COMPLETION_WAIT = 1.0,   -- 1.0 second - time to wait for move completion (stay module)
  },

  -- spoon.URLDispatcher
  URLDispatcher = {
    url_patterns = {
      -- { <url pattern>, <application bundle ID> },
      { "https?://www.google.com/url%?sa=j&url=https%%3A%%2F%%2Fapp.asana.com%%2F.*", "com.webcatalog.juli.asana" },
      --  { "https?://app.asana.com/%-/login.*",           "com.google.Chrome" },
      --  { "https?://app.asana.com/.*",                   "com.electron.asana" },
      { "https?://calendar.google.com/.*",                                            "com.webcatalog.juli.google-calendar" },
      { "https?://www.google.com/calendar/.*",                                        "com.webcatalog.juli.google-calendar" },
      -- { "https?://meet.google.com/.*",                 "com.webcatalog.juli.hangouts-meet" },
      { "https?://meet.google.com/.*",                                                "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan" },
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

  -- miro window manager
  mwm = {
    sizes = { 2, 3 / 2, 3, 4, 4 / 3 },
    -- 0.5, 0.66, 0.33, 0.25, 0.75
    -- 6,   8,    4,    3,    9
    fullScreenSizes = { 1, 4 / 3, 2, 'c' },
    GRID = { w = 24, h = 12 },
    stickySides = true,
    hotkeys = {
      up         = { { '⌥', '⌘' }, 'k' },
      down       = { { '⌥', '⌘' }, 'j' },
      left       = { { '⌥', '⌘' }, 'h' },
      right      = { { '⌥', '⌘' }, 'l' },
      fullscreen = { { '⌥', '⌘' }, 'f' },
      center     = { { '⌥', '⌘' }, 'c' },
      move       = { { '⌥', '⌘' }, "v" },
      resize     = { { '⌥', '⌘' }, "d" },
    },
  },

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

  stay = {
    target_space_rules = {
      {
        name = "personal",
        target_space = 6,
        window_title_matcher = {
          pattern = " %- Google Chrome – Matthew %(personal%)$",
        },
        exceptions = {
          gmail = {
            window_title_matcher = {
              pattern = "@gmail.com - Gmail",
            },
          }
        },
      },
      {
        name = "bellroy",
        target_space = 7,
        window_title_matcher = {
          pattern = " %- Google Chrome – Matthew %(bellroy%)$",
        },
        exceptions = {
          gmail = {
            window_title_matcher = {
              pattern = "@bellroy.com - Bellroy Mail",
            },
          }
        },
      },
      {
        name = "miri",
        target_space = 10,
        window_title_matcher = {
          pattern = " %- Google Chrome – Matt %(miri%)$",
        },
        exceptions = {
          gmail = {
            window_title_matcher = {
              pattern = "@intelligence.org - Machine Intelligence Research Institute Mail",
            },
          }
        },
      },
      {
        name = "personal Gmail",
        target_space = 8,
        window_title_matcher = {
          pattern = "@gmail.com - Gmail",
        },
      },
      {
        name = "bellroy Gmail",
        target_space = 8,
        window_title_matcher = {
          pattern = "@bellroy.com - Bellroy Mail",
        },
      },
      {
        name = "miri Gmail",
        target_space = 8,
        window_title_matcher = {
          pattern = "@intelligence.org - Machine Intelligence Research Institute Mail",
        },
      },
    },
    -- Each group applies independently (externally inclusive)
    -- Within each group, first matching layout wins (internally exclusive)
    window_layout_groups = {
      shared = {
        layouts = {
          {
            name = "Shared",
            config = {
              { { ['Hammerspoon'] = { allowRoles = 'AXStandardWindow' } }, 'move 1 closest [50,0>100,90] 0,0' },
              { { ['Finder'] = { currentSpace = true } },                  'move 1 closest [45,55>97,97] 0,0' },
              { 'Skype',                                                   'move 1 oldest [60,0>100,86] 0,0' },
              { 'Messages',                                                'move 1 oldest [53,0>100,71] 0,0' },
              { 'Signal',                                                  'move 1 oldest [50,0>100,83] 0,0' },
              { 'Slack',                                                   'move 1 oldest [40,0>100,100] 0,0' },
              { 'Google Meet',                                             'move all oldest [12,0>88,67] 0,0' },
              { 'Activity Monitor',                                        'move 1 oldest [0,42>61,100] 0,0' },
              { { ['Quicksilver'] = { allowRoles = 'AXStandardWindow' } }, 'move 1 oldest [24,12>84,86] 0,0' },
              { 'Discord',                                                 'move 1 oldest [50,0>100,85] 0,0' },
            },
          },
        }
      },
      screen_setups = (function()
        -- Factory function to generate dual screen layouts with consistent app rules
        local function makeDualScreenLayout(name, screen_position)
          return {
            name = name,
            config = {
              screens = { [screen_position] = true },
              { 'iTerm2',          'move 1 oldest [30,0>100,100] ' .. screen_position },
              { 'Asana',           'move 1 oldest [0,0>60,100] ' .. screen_position },
              { 'Google Calendar', 'move all oldest [0,25>100,100] ' .. screen_position },
              { 'Obsidian',        'move 1 oldest [0,0>29,60] ' .. screen_position },
            },
          }
        end

        return {
          layouts = {
            makeDualScreenLayout("DualLeft", "-1,0"),
            makeDualScreenLayout("DualRight", "1,0"),
            makeDualScreenLayout("DualTop", "0,-1"),
            {
              name = "Laptop",
              config = {
                { 'iTerm2', 'move 1 oldest [0,0>100,100] 0,0' },
              },
            },
          }
        }
      end)(),
      --[[
      desk_setups = {
        layouts = {
          {
            name = "FitzroyDesk",
            config = {
              screens = { ['DELL U2718Q'] = true, ['1,0'] = true },
              -- {{['Finder']={currentSpace=true,allowRegions=hs.geometry({x1=3609,y1=395,x2=4838,y2=993})}},'move 1 closest [35,37>87,80] 1,0'},
            },
          },
          {
            name = "MelbourneDesk",
            config = {
              screens = { ['DELL U2720Q'] = true, ['1,0'] = true },
              -- {{['Finder']={currentSpace=true,allowRegions=hs.geometry({x1=3609,y1=395,x2=4838,y2=993})}},'move 1 closest [35,37>87,80] 1,0'},
            },
          },
          {
            name = "MiriDesk1",
            config = {
              screens = { ['DELL U3223QE'] = true, ['0,-1'] = true },
            },
          },
          {
            name = "MiriDesk2",
            config = {
              screens = { ['Studio Display'] = true, ['0,-1'] = true },
            },
          },
        }
      },
      --]]
    },
  },

  -- WIP: Stay modal control to throw apps to an alternate position
  --   Offer [Apps → Default
  --               → <option name>]
  window_layouts_alt = {
    ['Google Meet Right'] = {
      Shared = {
        { 'Google Meet', 'move 1 oldest [23,0>79,63] 1,0' },
      },
    },
  },

  -- control_plane
  control_plane = {
    -- wifi_security_watcher
    trusted_open_networks = {},

    locationFacts = {
      network = {
        ['United_Wi-Fi'] = 'Expensive',
        ['blacknode'] = 'Wright',
        ['TheBarn'] = 'Fitzroy',
        ['🤖'] = 'MIRI',
      },
      monitor = {
        [69992768] = 'WrightServer',
      },
    },

    network_hungry_apps = {
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
  },
}
