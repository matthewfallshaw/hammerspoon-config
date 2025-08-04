## Implementation Status

### Configuration Refactoring 🔄 In Progress
- Rename `config.chrome_profile_rules` to `config.target_space_rules`
- Update code to not filter out non-Chrome windows by default
- Make window matching system generic rather than Chrome-specific
- **CRITICAL**: Convert from named-key rules to array-based rules
  - Change from `{ ruleName = { ... } }` to `{ { name = "ruleName", ... } }`
  - Use `ipairs()` instead of `pairs()` for predictable priority order
  - Support optional `name` field for debugging/maintenance
  - Update all rule processing logic to handle array format

### Phase 1: Title-Only Matching ✅ Ready to Implement
- `window_title_matcher` support
- Window detection via window titles (not limited to Chrome profiles)
- Basic space assignment logic

### Phase 2: Tab Inspection 🚧 Planned
- `tab_index_matcher` support
- Chrome tab URL/title inspection
- Gmail main window detection

### Phase 3: Advanced Matchers 💭 Future
- `any_tab_matcher` - search all tabs in window
- `window_size_matcher` - classify by window dimensions
- `window_count_matcher` - classify by number of windows per profile

## Configuration Guidelines

### Lua Regex Patterns
- Use `%` for escaping special characters (not `\`)
- Common escapes: `%(` `)` `%-` `%.` `%[` `%]` `%^` `%$`
- Anchors: `^` (start), `$` (end)
- Example: `" %- Google Chrome – Matthew %(personal%)$"`

### Space Numbers
- Use desktop space numbers as defined by `desktop_space_numbers.lua`
- Numbers are 1-based and correspond to macOS Mission Control space ordering

### Exception Keys
- Exception keys (e.g., `gmail_main`) are arbitrary and used only for configuration maintainability
- Choose descriptive names that explain the exception's purpose
- Keys have no semantic meaning in the application logic

## Tidy Implementation Plan

The `tidy()` function organizes all windows according to their target space rules using a systematic 3-phase approach:

### Phase 1: Discovery and Planning
- Page through every space on every display
- Collect a todo list of windows that need to move
- Record each window's current space and intended target space
- Skip windows that are already in their correct

### Phase 2: Window Movement Execution
For each window in the todo list:
- Focus the window (automatically moves user to that space)
- Confirm the correct window is focused
- Click and drag the window's title bar
- Use keyboard shortcut to jump to target space
- Release the mouse to complete the move
- Verify the window arrived at the correct space

### Phase 3: User Return Navigation
- Return all displays to their original spaces

### Key Implementation Details

**Space Discovery**: Use `hs.spaces` API to enumerate all user spaces across displays. Needed because we couldn't discover all windows without visiting all spaces.

**Window Identification**: Apply target space rules to each window found, using `is_window_home()` to determine if movement is needed.

**Movement Mechanism**: Use title bar dragging approach via `moveWindowToSpaceAndReturn()` for reliable cross-display window movement.

**State Preservation**: Track original focused spaces per display to enable complete state restoration after tidying.

## Processing Logic Implementation

### Window Classification Process

1. **Rule Iteration**: Process rules in array order using `ipairs()` (first to last)
2. **Rule Matching**: For each rule, evaluate window against the rule's matcher
3. **Exception Processing**: If rule matches, check if any exception also matches
4. **Space Assignment**: If rule matches and no exceptions match, assign `target_space` and stop processing
5. **Continue or Fallback**: If rule doesn't match or exception blocks it, continue to next rule

### Exception Processing

- Exceptions are negative filters - they prevent rules from applying
- If any exception matches, skip the entire rule (no space assignment)
- Exceptions don't have their own target spaces
- Process all rules independently - multiple rules can match different aspects

### Matcher Evaluation Function

The system uses a flexible matcher evaluation function that handles any matcher type:

```lua
function evaluate_matcher(rule, win)
  for matcher_type, matcher_params in pairs(rule) do
    if matcher_type == "window_title_matcher" then
      return win:title():match(matcher_params.pattern)

    elseif matcher_type == "tab_index_matcher" then
      -- Phase 2 - Requires Chrome tab inspection API
      local tab_url = get_tab_url(win, matcher_params.index)
      local tab_title = get_tab_title(win, matcher_params.index)

      -- Check required conditions (url OR title must be specified)
      local url_match = not matcher_params.url or tab_url:match(matcher_params.url)
      local title_match = not matcher_params.title or tab_title:match(matcher_params.title)

      -- Check exclusion conditions (if specified, must NOT match)
      local url_excluded = matcher_params.exclude_url and tab_url:match(matcher_params.exclude_url)
      local title_excluded = matcher_params.exclude_title and tab_title:match(matcher_params.exclude_title)

      return (url_match or title_match) and not url_excluded and not title_excluded

    elseif matcher_type == "any_tab_matcher" then
      -- Phase 3 - Search all tabs in window
      local all_tabs = get_all_tabs(win)
      for _, tab in ipairs(all_tabs) do
        local url_match = not matcher_params.url or tab.url:match(matcher_params.url)
        local title_match = not matcher_params.title or tab.title:match(matcher_params.title)
        local url_excluded = matcher_params.exclude_url and tab.url:match(matcher_params.exclude_url)
        local title_excluded = matcher_params.exclude_title and tab.title:match(matcher_params.exclude_title)

        if (url_match or title_match) and not url_excluded and not title_excluded then
          return true
        end
      end
      return false

    -- Skip non-matcher keys like target_space, exceptions
    elseif matcher_type == "target_space" or matcher_type == "exceptions" then
      -- continue to next key
    else
      error("Unknown matcher type: " .. matcher_type)
    end
  end
  return false
end
```

## Testing Strategy

### Unit Tests
- Individual matcher evaluation with mock window objects
- Window detection with realistic window titles
- Exception precedence with multiple matching rules

### Integration Tests
- End-to-end window organization with mock windows
- Space assignment verification
- Error handling for missing spaces or invalid patterns