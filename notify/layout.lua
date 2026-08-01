--- === notify.layout ===
--- Pure-Lua layout core for the notify module: word wrapping, truncation,
--- overflow footers, card-height and stack-frame arithmetic.
---
--- Has no reference to `hs.*` anywhere, so it runs and is fully testable
--- under plain `busted`. `notify.card` paints what `compose` returns and does
--- no arithmetic of its own.

local M = {}

-- Metadata
M.name = "NotifyLayout"
M.version = "1.0"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
M.license = "MIT - https://opensource.org/licenses/MIT"

-- Card text is arbitrary clipboard content (em-dashes, emoji, CJK), so columns
-- are counted per-codepoint, not per-byte. Every codepoint counts as exactly 1
-- column: true display width would need a Unicode East-Asian-Width table, and
-- 1-per-codepoint is close enough for a notification card.

-- Byte length (1-4) of the UTF-8 codepoint starting at byte `b`. A stray
-- continuation byte counts as 1, so malformed input can never stall a walk.
local function utf8CharLen(b)
  if b < 0x80 then return 1
  elseif b >= 0xF0 then return 4
  elseif b >= 0xE0 then return 3
  elseif b >= 0xC0 then return 2
  else return 1
  end
end

local function utf8Len(s)
  local len = 0
  local i = 1
  local n = #s
  while i <= n do
    i = i + utf8CharLen(s:byte(i))
    len = len + 1
  end
  return len
end

-- Splits after the first `n` codepoints, never mid-codepoint. `head .. tail == s`.
local function utf8SplitAt(s, n)
  local i = 1
  local len = #s
  local count = 0
  while i <= len and count < n do
    i = i + utf8CharLen(s:byte(i))
    count = count + 1
  end
  return s:sub(1, i - 1), s:sub(i)
end

-- Splits on "\n" keeping empty fields, which `utilities/string.lua`'s
-- `:split()` drops -- consecutive newlines must survive as empty lines.
-- `text == ""` returns `{""}`.
local function splitLines(text)
  local lines = {}
  local start = 1
  while true do
    local nlPos = text:find("\n", start, true)
    if nlPos then
      table.insert(lines, text:sub(start, nlPos - 1))
      start = nlPos + 1
    else
      table.insert(lines, text:sub(start))
      break
    end
  end
  return lines
end

-- One paragraph (no "\n") to an ordered array of
-- `{ kind = "word"|"space", text = string }`. Scanning bytes for " " is
-- UTF-8-safe: lead and continuation bytes are always >= 0x80.
local function tokenize(paragraph)
  local tokens = {}
  local i = 1
  local n = #paragraph
  while i <= n do
    local isSpace = paragraph:sub(i, i) == " "
    local j = i
    while j <= n and (paragraph:sub(j, j) == " ") == isSpace do
      j = j + 1
    end
    table.insert(tokens, { kind = isSpace and "space" or "word", text = paragraph:sub(i, j - 1) })
    i = j
  end
  return tokens
end

-- Greedy wrap of one paragraph at `maxChars` columns. Trailing whitespace on a
-- produced line is dropped; a run of spaces mid-line survives when it fits. A
-- word longer than `maxChars` is hard-split at exactly `maxChars` columns.
local function wrapParagraph(paragraph, maxChars)
  local tokens = tokenize(paragraph)
  local lines = {}
  local current = {}
  local currentLen = 0

  local function flush()
    while #current > 0 and current[#current].kind == "space" do
      table.remove(current)
    end
    local parts = {}
    for _, tok in ipairs(current) do
      table.insert(parts, tok.text)
    end
    table.insert(lines, table.concat(parts))
    current = {}
    currentLen = 0
  end

  for _, tok in ipairs(tokens) do
    local tokLen = utf8Len(tok.text)
    if tok.kind == "word" and tokLen > maxChars then
      if currentLen > 0 then flush() end
      local remaining = tok.text
      while utf8Len(remaining) > maxChars do
        local chunk, rest = utf8SplitAt(remaining, maxChars)
        table.insert(lines, chunk)
        remaining = rest
      end
      current = { { kind = "word", text = remaining } }
      currentLen = utf8Len(remaining)
    elseif currentLen + tokLen <= maxChars then
      table.insert(current, tok)
      currentLen = currentLen + tokLen
    else
      flush()
      if tok.kind == "word" then
        current = { tok }
        currentLen = tokLen
      end
      -- A space token at a forced wrap point is separator whitespace: drop it
      -- rather than start the next line indented.
    end
  end
  if currentLen > 0 or #lines == 0 then
    flush()
  end
  return lines
end

--- notify.layout.wrap(text, maxChars, opts) -> lines
--- Word-wraps `text` to `maxChars` columns, preserving hard "\n" breaks.
--- `maxChars` is clamped to 1 (0 would make an over-long word unsplittable).
--- `opts.tabWidth` (default 4) is a flat substitution, not tab stops.
--- An empty `text` yields `{""}`, never `{}`.
function M.wrap(text, maxChars, opts)
  opts = opts or {}
  local tabWidth = opts.tabWidth or 4
  if tabWidth < 1 then tabWidth = 1 end
  if maxChars < 1 then maxChars = 1 end

  local expanded = text:gsub("\t", string.rep(" ", tabWidth))
  local paragraphs = splitLines(expanded)

  local lines = {}
  for _, paragraph in ipairs(paragraphs) do
    for _, line in ipairs(wrapParagraph(paragraph, maxChars)) do
      table.insert(lines, line)
    end
  end
  return lines
end

--- notify.layout.truncate(lines, maxLines) -> keptLines, overflow
--- Caps `lines` at `maxLines` entries; `nil` or `0` means no limit.
--- `overflow` is the number of lines dropped from the end, `0` if none.
function M.truncate(lines, maxLines)
  if maxLines == nil or maxLines == 0 or #lines <= maxLines then
    return lines, 0
  end
  local kept = {}
  for i = 1, maxLines do
    kept[i] = lines[i]
  end
  return kept, #lines - maxLines
end

--- notify.layout.overflowFooter(overflow) -> string or nil
--- The "… (+N more lines)" footer for a truncated card; `nil` when nothing
--- was cut.
function M.overflowFooter(overflow)
  if not overflow or overflow == 0 then
    return nil
  end
  local word = (overflow == 1) and "line" or "lines"
  return string.format("… (+%d more %s)", overflow, word)
end

--- notify.layout.cardHeight(spec, cfg) -> integer
--- Pixel height of a card from `spec` (`{ title, lines, overflow }`) and `cfg`
--- (`{ padding, titleHeight, titleGap, lineHeight, minHeight }`), floored at
--- `cfg.minHeight`.
function M.cardHeight(spec, cfg)
  local height = cfg.padding * 2
  if spec.title then
    height = height + cfg.titleHeight + cfg.titleGap
  end
  height = height + (#spec.lines * cfg.lineHeight)
  if spec.overflow and spec.overflow > 0 then
    height = height + cfg.lineHeight
  end
  if cfg.minHeight and height < cfg.minHeight then
    height = cfg.minHeight
  end
  return height
end

--- notify.layout.stackFrames(heights, screenFrame, cfg) -> frames
--- Top-right-anchored, non-overlapping `{x, y, w, h}` frames, one per height,
--- in stack order (index 1 is the oldest card, topmost). `cfg` is
--- `{ cardWidth, stackGap, marginTop, marginRight }`. Recomputing from a
--- shortened `heights` list is how gaps close on dismissal: cards above the
--- gap keep their `y`, cards below it move up.
function M.stackFrames(heights, screenFrame, cfg)
  local x = screenFrame.x + screenFrame.w - cfg.marginRight - cfg.cardWidth
  local y = screenFrame.y + cfg.marginTop
  local frames = {}
  for i, h in ipairs(heights) do
    frames[i] = { x = x, y = y, w = cfg.cardWidth, h = h }
    y = y + h + cfg.stackGap
  end
  return frames
end

--- notify.layout.bodyColumns(cardWidth, charWidth, cfg) -> integer
--- Monospace columns of body text that fit in a card, floored at 1. `cfg` is
--- `{ padding, hasIcon, iconWidth, iconGap }`; `iconWidth`/`iconGap` are read
--- only when `hasIcon` is truthy.
function M.bodyColumns(cardWidth, charWidth, cfg)
  local iconSpace = 0
  if cfg.hasIcon then
    iconSpace = (cfg.iconWidth or 0) + (cfg.iconGap or 0)
  end
  local columns = math.floor((cardWidth - cfg.padding * 2 - iconSpace) / charWidth)
  if columns < 1 then
    columns = 1
  end
  return columns
end

--- notify.layout.compose(input, cfg) -> card
--- The single entry point the renderer calls. `input` is
--- `{ message, title, icon }` (`icon` is only tested for presence; its value
--- is opaque here); `cfg` is the union of the shapes above, plus the optional
--- `tabWidth`. Returns `{ title, lines, overflow, footer, height, hasIcon }`.
function M.compose(input, cfg)
  local hasIcon = input.icon ~= nil
  local maxChars = M.bodyColumns(cfg.cardWidth, cfg.charWidth, {
    padding = cfg.padding,
    hasIcon = hasIcon,
    iconWidth = cfg.iconWidth,
    iconGap = cfg.iconGap,
  })
  local wrapped = M.wrap(input.message or "", maxChars, { tabWidth = cfg.tabWidth })
  local kept, overflow = M.truncate(wrapped, cfg.maxLines)
  local footer = M.overflowFooter(overflow)
  local height = M.cardHeight({ title = input.title, lines = kept, overflow = overflow }, cfg)

  return {
    title = input.title,
    lines = kept,
    overflow = overflow,
    footer = footer,
    height = height,
    hasIcon = hasIcon,
  }
end

return M
