# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing shell commands
- `busted` - Run all tests
- `busted spec/<module>_spec.lua` - Run tests for specific module
- `busted spec/` - Run all tests in spec directory
- Guard file monitoring: `guard` - Auto-runs tests when files change (Ruby Guard + Guardfile)

**Testing Limitations**: The busted tests run in an isolated environment without access to the Hammerspoon (HS) APIs. They use mocks provided in `spec_helper.lua`. To test actual Hammerspoon functionality, ask the user to manually test the configuration. The config auto-reloads when files change (see below), so no manual reload is needed.

### Development Workflow
- Configuration auto-reloads via `Spoons/Hammer.spoon`, which watches `hs.configdir` **recursively** and calls `hs.reload()` on any changed path ending `.lua`
- `~/.hammerspoon` is a symlink to this repo, so *any* `.lua` save anywhere in the repo — including inside `.claude/worktrees/` — reloads the live config. When editing Lua here, expect a live reload on every save; develop outside the tree if that matters
- Spec-on-save comes only from the Ruby `Guardfile`, and only while `guard` is running

## Architecture Overview

### Core Structure
This is a sophisticated Hammerspoon configuration with modular architecture:

- **init.lua** - Main entry point, orchestrates all modules and spoons
- **configConsts.lua** - Centralized configuration for all modules
- **Spoons/** - Symlinked Hammerspoon spoon extensions
- **utilities/** - Shared utility libraries
- **spec/** - Test files using busted framework

### Key Architectural Patterns

**Module Pattern**: Each feature is encapsulated in modules that:
- Return a table with public methods (`local M = {}; return M`)
- Include consistent metadata (name, version, author, license)
- Use `hs.logger.new()` for module-specific logging
- Implement `:start()` and `:stop()` lifecycle methods

**Configuration-driven**: All modules reference `init.consts.*` from configConsts.lua for:
- Window layouts per screen configuration
- Application hotkeys and URL routing patterns
- API keys and trusted networks
- Module-specific settings

**Watcher-Observer Pattern**: Extensive use of Hammerspoon watchers:
- File changes (`hs.pathwatcher`)
- Network changes (`hs.wifi.watcher`)
- USB device events (`hs.usb.watcher`)
- Application lifecycle (`hs.application.watcher`)
- Power state changes (`hs.caffeinate.watcher`)

**Modal Key Bindings**:
- `hyper.lua` creates virtual hyper key system using F18/F17
- Programmatically generates all modifier combinations
- Other modules register keys via `hyper.bindKey()`
- `spoon.CaptureHotkeys` provides documentation/export

### Core Modules

**control_plane.lua** - Location-based automation:
- Detects location from network, monitors, power source
- Executes entry/exit actions per location
- Priority-based location inference with debouncing
- Publishes state via `hs.watchable` for other modules

**stay.lua** - Window management:
- Extends `hs.window.layout` with active layout tracking
- Screen-aware window positioning rules
- Configuration-driven layouts in `configConsts.window_layouts`
- Interactive chooser for layout switching

**hyper.lua** - Advanced hotkey system:
- Creates virtual hyper key for complex combinations
- Modal enter/exit states with visual feedback
- Used by other modules for consistent key binding

**move_spaces.lua** - Desktop space management:
- Moves windows between macOS spaces
- Double-tap detection for enhanced workflows
- Integrates with desktop space numbering system

**trash_recent.lua** - Download management:
- Interactive interface for trashing recent downloads
- QuickLook preview integration
- Caching and async preview generation

### Integration Points

**Spoon Integration**: Loads and configures Hammerspoon Spoons:
- `CaptureHotkeys` - Documents all hotkeys, exports to KeyCue
- `URLDispatcher` - Routes URLs to specific applications
- `MiroWindowsManager` - Grid-based window management
- `Caffeine` - Prevent system sleep with state persistence
- Various utility spoons (MouseCircle, AClock, etc.)

**External System Integration**:
- Chrome extension for tab management (`chrome_tabs/`)
- Asana API integration for task management
- VPN automation based on network security
- Audio device switching with Bluetooth support
- ScanSnap scanner lifecycle management

### Utilities Library Structure

**utilities/** contains shared libraries:
- `log.lua` - Enhanced logging with alert integration
- `fuzzy/` - Fuzzy matching for search interfaces
- `expect.lua` - Testing assertions
- `path.lua` - File path utilities
- `persistence.lua` - State saving/loading
- `profile.lua` - Performance profiling tools
- `string_escapes.lua` - URL/shell escaping utilities

### Testing Approach

- Uses busted Lua testing framework
- Tests in `spec/` mirror source structure
- `spec_helper.lua` provides Hammerspoon API mocks
- Guard integration for continuous testing

### Configuration Management

**configConsts.lua patterns**:
- Screen/monitor specific window layouts
- Application-specific hotkeys and behaviors
- URL routing patterns for browser management
- Location-specific automation rules
- API keys retrieved from macOS keychain

The configuration demonstrates enterprise-level automation while maintaining modularity, testability, and extensive customization options.

## Utility Library Usage

When implementing basic operations that "ought to exist" in Lua:

1. **Check utilities/ first**: Look in `utilities/` directory to see if the needed function already exists
2. **Use existing utilities**: If found, require the appropriate utility module and use the existing function
3. **Follow existing patterns**: If implementing new utilities, follow the style and patterns of existing utility modules (e.g., `utilities/table.lua` uses `table.functionName = function(self)` pattern)
4. **Add to utilities/ when appropriate**: For reusable functions that might be extracted to a general utility library