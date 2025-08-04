# Stay Module

The Stay module provides comprehensive window management for Hammerspoon with two distinct operational modes:

1. **Persistent within-space positioning** using `config.window_layouts` - maintains window positions constantly unless paused
2. **On-demand between-space organization** using `config.target_space_rules` - moves windows to target spaces when `tidy()` is called

## Main Functions

The module's primary interface is through `choices_list`:

- **Toggle layout engine** - Enable/disable persistent window positioning
- **Screens** - Report screen configuration details
- **Report** - Show frontmost window position information
- **Report and open** - Report window position and open configuration file
- **Tidy windows between spaces** - Organize all windows according to target space rules

## Implementation Status

See [TODO.md](TODO.md) for detailed implementation roadmap and current development status.

## Dependencies

- Hammerspoon
- `move_spaces` module for cross-space window movement
- `hs.spaces` API for desktop space management

## Configuration

Configuration is passed to the module's `start(config)` method. The configuration structure includes:

### Window Layouts (`config.window_layouts`)
Standard `hs.window.layout` configuration for persistent within-space positioning that runs continuously (when enabled). See the [Hammerspoon hs.window.layout documentation](https://www.hammerspoon.org/docs/hs.window.layout.html) for configuration details.

### Target Space Rules (`config.target_space_rules`)
Flexible window matching system for organizing windows across desktop spaces. Rules run only when triggered via `tidy()`.

#### Configuration Schema

The following TypeScript definitions describe the configuration structure (note: this is a Lua project; TypeScript is used here only for documentation clarity):

```typescript
// Full configuration structure passed to start(config)
type StayConfig = {
  window_layouts: WindowLayout[]       // See hs.window.layout documentation
  target_space_rules: WindowRule[]     // Array: earlier rules have higher priority
}

// Any rule (main rule or exception) can use any matcher type
type Matcher =
  | { window_title_matcher: WindowTitleMatcher }
  | { tab_index_matcher: TabIndexMatcher }
  | { any_tab_matcher: AnyTabMatcher }
  // Future matcher types can be added here

type WindowRule = Matcher & {
  name?: string                         // Optional name for debugging/maintenance
  target_space: number
  exceptions?: {
    [exceptionName: string]: ExceptionMatcher
  }
}

// Exceptions are negative filters - if any exception matches, skip this rule
type ExceptionMatcher = Matcher

// Individual matcher type definitions
type WindowTitleMatcher = {
  pattern: string  // Lua regex pattern to match window titles
}

type TabIndexMatcherBase = {
  index: number                    // Required: 1-based tab index to inspect
  exclude_url?: string             // Optional: Lua regex pattern to exclude
  exclude_title?: string           // Optional: Lua regex pattern to exclude
}
type TabIndexMatcher =
  | (TabIndexMatcherBase & { url: string })
  | (TabIndexMatcherBase & { title: string })
  | (TabIndexMatcherBase & { url: string; title: string })
  // Note: At least one of 'url' or 'title' must be specified
  // Note: exclude_* patterns must NOT match for rule to apply

type AnyTabMatcherBase = {
  exclude_url?: string             // Optional: Lua regex pattern to exclude
  exclude_title?: string           // Optional: Lua regex pattern to exclude
}
type AnyTabMatcher =
  | (AnyTabMatcherBase & { url: string })
  | (AnyTabMatcherBase & { title: string })
  | (AnyTabMatcherBase & { url: string; title: string })
  // Note: At least one of 'url' or 'title' must be specified
```

#### Configuration Examples

```lua
-- Example target_space_rules configuration
-- Rules are processed in array order - first match wins
target_space_rules = {
  {
    name = "gmail_main",
    tab_index_matcher = {
      index = 1,
      url = "^https://mail%.google%.com/mail/u/",
      exclude_url = "^https://mail%.google%.com/mail/u/.*/popout%?"
    },
    target_space = 8
  },

  {
    name = "work_gmail_main",
    tab_index_matcher = {
      index = 1,
      url = "^https://mail%.google%.com/mail/u/.*work%.com"
    },
    target_space = 8
  },

  {
    name = "chrome_personal_main",
    window_title_matcher = {
      pattern = " %- Google Chrome – Matthew %(personal%)$"
    },
    target_space = 6,
    exceptions = {
      gmail_tabs = {
        tab_index_matcher = {
          index = 1,
          url = "^https://mail%.google%.com/mail/u/",
          exclude_url = "^https://mail%.google%.com/mail/u/.*/popout%?"
        }
      }
    }
  },

  {
    name = "chrome_work",
    window_title_matcher = {
      pattern = " %- Google Chrome – Matthew %(work%)$"
    },
    target_space = 7,
    exceptions = {
      work_gmail = {
        tab_index_matcher = {
          index = 1,
          url = "^https://mail%.google%.com/mail/u/.*work%.com"
        }
      }
    }
  },

  {
    name = "slack_browser",
    any_tab_matcher = {
      url = "^https://.*%.slack%.com"
    },
    target_space = 9,
    exceptions = {
      slack_app_windows = {
        window_title_matcher = {
          pattern = "^Slack %|"  -- Don't move actual Slack app windows
        }
      }
    }
  }
}
```

#### How Exceptions Work

Exceptions act as negative filters. For each window:

1. **Rule matching**: If the main matcher matches the window
2. **Exception checking**: Check all exceptions - if any exception also matches, skip this rule entirely
3. **Space assignment**: If no exceptions match, assign the window to the rule's `target_space`

This design works around Lua regex lacking negative lookahead. Instead of writing complex patterns, you write separate positive rules for each desired target space, using exceptions to prevent conflicts.

#### Rule Priority and Multiple Matches

Rules are processed in array order using `ipairs()` - **first match wins**. This provides predictable, easily-adjustable priority:

- **Higher priority rules** should appear earlier in the array
- **Lower priority rules** appear later and only apply if no earlier rule matched
- **To change priority**, simply reorder the rules in the array
- **Debugging**: The optional `name` field helps identify which rule matched

Example priority reasoning:
1. Gmail rules first (most specific)
2. Profile-specific rules next (more specific than general browser rules)
3. Generic browser rules last (fallback)

