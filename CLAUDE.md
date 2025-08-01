# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
- `busted` - Run all tests (requires Lua busted framework)
- `busted spec/<module>_spec.lua` - Run tests for specific module
- `busted spec/` - Run all tests in spec directory
- Guard file monitoring: `guard` - Auto-runs tests when files change (Ruby Guard + Guardfile)

### Development Workflow
- Configuration auto-reloads via `auto_reload_or_test.lua`
- Files listed in `configConsts.modules_under_test` trigger spec tests instead of reload
- All other changes trigger `hs.reload()`

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

**auto_reload_or_test.lua** - Development automation:
- Watches config directory for changes
- Modules under test → run specs
- Other modules → reload configuration
- Supports TDD workflow

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
- Modules can be marked for testing vs reload in `configConsts.modules_under_test`

### Configuration Management

**configConsts.lua patterns**:
- Screen/monitor specific window layouts
- Application-specific hotkeys and behaviors
- URL routing patterns for browser management
- Location-specific automation rules
- API keys retrieved from macOS keychain

The configuration demonstrates enterprise-level automation while maintaining modularity, testability, and extensive customization options.