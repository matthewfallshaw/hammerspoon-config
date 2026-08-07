hs.logger.setGlobalLogLevel('warning')
hs.logger.defaultLogLevel = 'warning'
hs.hotkey.setLogLevel('warning') -- 'cos it ignores global defaults
hs.window.animationDuration = 0.1
-- hs.doc.hsdocs.forceExternalBrowser(true)
hs.doc.hsdocs.moduleEntitiesInSidebar(true)
hs.application.enableSpotlightForNameSearches(true)
hs.allowAppleScript(true)

return {
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

  -- notify: Growl-replacement notification cards (see TODO.md). This is the
  -- whole module's tuning: notify/init.lua merges it over its own fallback
  -- defaults and hands the result to notify.card and notify.gesture, neither
  -- of which keeps defaults of its own. The merge is shallow, so the `swipe`
  -- and `palettes` sub-tables below are taken whole and must stay complete.
  notify = {
    -- Layout (pixels unless noted)
    card_width = 320,
    max_lines = 12,
    stack_gap = 8,
    margin_top = 8,
    margin_right = 8,
    padding = 12,
    title_height = 18,
    title_gap = 6,
    line_height = 16,
    min_height = 48,
    icon_width = 32,
    icon_gap = 8,
    tab_width = 4,
    close_size = 14,
    corner_radius = 8,

    -- Menlo, not SFMono-Regular: SFMono-Regular is not installed on this machine.
    -- char_width is Menlo's measured advance at body_font_size; wrapping is
    -- arithmetic rather than repeated measurement, so it must match the font.
    -- Emoji are ~2.2x this wide and will overrun the card; they clip, not re-wrap.
    char_width = 7.2246,

    body_font = 'Menlo',
    body_font_size = 12,
    title_font = '.AppleSystemUIFont',
    title_font_size = 13,

    -- Timing (seconds)
    default_duration = 5,
    fade_in = 0.15,  -- matches hs.alert's fade
    fade_out = 0.15,
    pulse_duration = 0.4,

    -- Grace period between a card's last mouseExit and treating the card as
    -- un-hovered. Moving between elements of the same card (body -> close
    -- glyph) emits the old element's exit before the new element's enter, so
    -- without this gap the countdown would resume mid-card. The events arrive
    -- in the same run loop pass, so this only has to be non-zero.
    hover_exit_grace = 0.05,

    -- hs.settings key the persisted (sticky/non-private) stack is written to.
    settings_key = 'notify.persisted',

    -- Swipe-to-dismiss (right, single-finger trackpad gesture; see TODO.md
    -- "Swipe is a real trackpad gesture"). All thresholds are provisional,
    -- pending live feel -- a human will need to tune these once he can
    -- swipe an actual card.
    swipe = {
      -- Instant off-switch: when false, notify/init.lua never creates the
      -- eventtap at all, regardless of the values below.
      enabled = true,

      -- Rightward travel, in normalized trackpad-surface units (0-1 across
      -- the whole pad), the swipe must clear to count as intentional.
      -- 0.15 is roughly a third of a typical trackpad's usable width.
      min_distance = 0.15,

      -- Travel beyond this looks like a re-grip or a long drag, not a
      -- snap dismiss; 0.9 only excludes near-full-pad sweeps.
      max_distance = 0.9,

      -- Seconds from touch-began to touch-ended. A real flick is fast; a
      -- slow drag isn't a swipe.
      max_duration = 0.6,

      -- Largest jump in signed x-velocity (normalized units/second)
      -- allowed between consecutive samples before it's treated as a
      -- stutter/re-grip and the gesture is aborted.
      max_velocity_change = 2.0,

      -- Backward (leftward) x-velocity, in normalized units/second,
      -- tolerated as finger jitter before a direction reversal aborts
      -- the gesture.
      direction_tolerance = 0.05,
    },

    -- Palettes selected at paint time from hs.host.interfaceStyle().
    -- Dark is anchored on hs.alert's own defaults ({white=0, alpha=0.75}
    -- fill, white stroke) so a card looks like part of the config.
    palettes = {
      dark = {
        background = { white = 0, alpha = 0.75 },
        border = { white = 1, alpha = 1 },
        title = { white = 1, alpha = 1 },
        body = { white = 1, alpha = 0.9 },
        footer = { white = 1, alpha = 0.6 },
        close = { white = 1, alpha = 0.6 },
        close_hover = { white = 1, alpha = 1 },
        pulse = { white = 1, alpha = 1 },
      },
      light = {
        background = { white = 1, alpha = 0.92 },
        border = { white = 0, alpha = 0.3 },
        title = { white = 0, alpha = 1 },
        body = { white = 0, alpha = 0.85 },
        footer = { white = 0, alpha = 0.5 },
        close = { white = 0, alpha = 0.5 },
        close_hover = { white = 0, alpha = 1 },
        pulse = { white = 0, alpha = 1 },
      },
    },
  },
}
