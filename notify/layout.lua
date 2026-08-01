--- === notify.layout ===
--- Pure-Lua layout core for the notify module: word wrapping, truncation,
--- overflow footers, card-height and stack-frame arithmetic.
---
--- Deliberately has **no reference to `hs.*` anywhere** in this file, so it
--- runs and is fully testable under plain `busted`, without the Hammerspoon
--- application or any of its API mocks. `notify.lua`'s canvas renderer calls
--- this module for every measurement so it needs no layout arithmetic of its
--- own; see notify.compose.

local M = {}

-- Metadata
M.name = "NotifyLayout"
M.version = "1.0"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
M.license = "MIT - https://opensource.org/licenses/MIT"

--------------------------------------------------------------------------------
-- UTF-8 helpers
--
-- Card text is arbitrary clipboard content: em-dashes, emoji, CJK. Column
-- counting must be per-codepoint, not per-byte, or a 3-byte em-dash would be
-- (wrongly) charged as 3 columns of a fixed-width card.
--
-- Simplification (documented per the spec): every codepoint is treated as
-- exactly 1 column. A real monospace terminal renders many emoji at 2
-- columns, but measuring true display width needs a Unicode East-Asian-Width
-- table this module doesn't have; 1-column-per-codepoint is close enough for
-- a notification card and is cheap to compute.
--------------------------------------------------------------------------------

--- Returns the UTF-8 byte length of the codepoint starting at byte `b`
--- (1, 2, 3 or 4). A stray/invalid continuation byte is treated as a
--- 1-byte codepoint so callers can never stall walking malformed input.
local function utf8CharLen(b)
  if b < 0x80 then return 1
  elseif b >= 0xF0 then return 4
  elseif b >= 0xE0 then return 3
  elseif b >= 0xC0 then return 2
  else return 1
  end
end

--- Counts the number of UTF-8 codepoints (== display columns, see the
--- simplification note above) in `s`.
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

--- Splits `s` after its first `n` codepoints, never cutting a multi-byte
--- codepoint in half. Returns `head, tail` such that `head .. tail == s`.
--- If `n <= 0`, `head` is `""`. If `n >= utf8Len(s)`, `tail` is `""`.
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

--------------------------------------------------------------------------------
-- Wrapping helpers (local; not part of the public API)
--------------------------------------------------------------------------------

--- Splits `text` on "\n", preserving empty lines (including leading,
--- trailing and consecutive newlines). Unlike `utilities/string.lua`'s
--- `:split()` — which is a character-class split built on `gsub("[^%s]+")`
--- and silently drops empty fields — this never collapses runs of the
--- separator, which the spec requires ("consecutive newlines producing
--- empty lines"). `text == ""` returns `{""}`.
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

--- Tokenizes a single paragraph (no "\n") into an ordered array of
--- `{ kind = "word"|"space", text = string }`. The split point (ASCII
--- 0x20) is safe against UTF-8 multi-byte sequences: continuation and
--- lead bytes are always >= 0x80, so a plain byte-wise scan for `" "`
--- never lands inside a codepoint.
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

--- Greedily word-wraps one paragraph (no "\n" inside it) at `maxChars`
--- columns. Trailing whitespace on a produced line is dropped; a run of
--- spaces mid-line survives as-is when it fits. A word longer than
--- `maxChars` is hard-split at exactly `maxChars` columns, UTF-8 aware.
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
      -- Over-long word: finish whatever's pending, then hard-split it.
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
      -- Doesn't fit on the current line.
      flush()
      if tok.kind == "word" then
        current = { tok }
        currentLen = tokLen
      end
      -- A space token that doesn't fit is pure separator whitespace at a
      -- forced wrap point: drop it rather than starting the next line
      -- with leading spaces.
    end
  end
  if currentLen > 0 or #lines == 0 then
    flush()
  end
  return lines
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- notify.layout.wrap(text, maxChars, opts) -> lines
--- Function
--- Word-wraps `text` to `maxChars` columns per line.
---
--- Parameters:
---  * text - (string) the text to wrap. Hard line breaks ("\n") are
---    preserved as line breaks before word-wrapping is applied to each
---    resulting paragraph.
---  * maxChars - (integer) columns available per line. Clamped to a
---    minimum of 1 (a `maxChars` of 0 or less would otherwise make an
---    over-long word impossible to hard-split).
---  * opts - (table or nil) `{ tabWidth = integer }`; `tabWidth` defaults
---    to 4 and is the fixed number of spaces each "\t" expands to (no
---    tab-stop alignment — a flat substitution, done once, before
---    splitting on "\n").
---
--- Returns:
---  * lines - ({string}) one entry per output line. An empty `text`
---    yields `{""}`, never `{}`.
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
--- Function
--- Caps an array of lines at `maxLines` entries.
---
--- Parameters:
---  * lines - ({string}) the lines to cap.
---  * maxLines - (integer or nil) the limit. 0 or nil means no limit.
---
--- Returns:
---  * keptLines - ({string}) `lines` unchanged if it already fits,
---    otherwise its first `maxLines` entries.
---  * overflow - (integer) `0` if nothing was cut, otherwise the number
---    of lines dropped from the end.
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
--- Function
--- Builds the "N more lines" footer text for a truncated card.
---
--- Parameters:
---  * overflow - (integer or nil) number of lines cut by `truncate`.
---
--- Returns:
---  * footer - (string or nil) `nil` when `overflow` is `0` or `nil`;
---    otherwise `"… (+1 more line)"` (singular) or `"… (+N more lines)"`
---    (plural) as appropriate.
function M.overflowFooter(overflow)
  if not overflow or overflow == 0 then
    return nil
  end
  local word = (overflow == 1) and "line" or "lines"
  return string.format("… (+%d more %s)", overflow, word)
end

--- notify.layout.cardHeight(spec, cfg) -> integer
--- Function
--- Computes the pixel height of a card from its content, deterministically.
---
--- Parameters:
---  * spec - (table) `{ title = string or nil, lines = {string},
---    overflow = integer, hasIcon = boolean }`. `hasIcon` is accepted for
---    shape-compatibility with `compose`'s output but does not affect the
---    height formula below.
---  * cfg - (table) `{ padding, titleHeight, titleGap, lineHeight,
---    minHeight }`, all integers (pixels).
---
--- Returns:
---  * height - (integer) `padding*2 + (title and titleHeight+titleGap or
---    0) + #lines*lineHeight + (overflow>0 and lineHeight or 0)`, floored
---    at `cfg.minHeight`.
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
--- Function
--- Computes top-right-anchored, non-overlapping card frames for a stack.
--- Recomputing from a shortened `heights` list (i.e. calling this again
--- after a card is removed from the middle) is how gaps close on
--- dismissal — cards above the gap keep their `y`, cards below it move up.
---
--- Parameters:
---  * heights - ({integer}) card heights in stack order; index 1 is the
---    oldest card (topmost).
---  * screenFrame - (table) `{ x, y, w, h }`, the target screen's frame.
---  * cfg - (table) `{ cardWidth, stackGap, marginTop, marginRight }`,
---    all integers (pixels).
---
--- Returns:
---  * frames - ({table}) one `{ x, y, w, h }` per input height, same
---    order.
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
--- Function
--- Computes how many monospace columns of body text fit in a card.
---
--- Parameters:
---  * cardWidth - (integer) card width in pixels.
---  * charWidth - (integer) width of one monospace character, in pixels.
---  * cfg - (table) `{ padding, hasIcon, iconWidth, iconGap }`. `padding`
---    is charged on both sides. When `hasIcon` is truthy, `iconWidth +
---    iconGap` is also subtracted; `iconWidth`/`iconGap` are ignored
---    (and may be omitted) when `hasIcon` is falsy.
---
--- Returns:
---  * columns - (integer) `floor((cardWidth - padding*2 - (hasIcon and
---    iconWidth+iconGap or 0)) / charWidth)`, floored at a minimum of 1.
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
--- Function
--- The single entry point the canvas renderer calls: wraps, truncates,
--- builds the overflow footer and computes height, so the renderer needs
--- no layout arithmetic of its own.
---
--- Parameters:
---  * input - (table) `{ message = string, title = string or nil, icon =
---    any or nil }`. `icon` is only tested for presence (`~= nil`); its
---    value is opaque to this module.
---  * cfg - (table) union of the `cfg` shapes above: `{ padding,
---    titleHeight, titleGap, lineHeight, minHeight, cardWidth, stackGap,
---    marginTop, marginRight, charWidth, maxLines, iconWidth, iconGap,
---    tabWidth }`. `tabWidth` is optional (see `wrap`); the rest are
---    required by the functions this composes.
---
--- Returns:
---  * card - (table) `{ title = string or nil, lines = {string},
---    overflow = integer, footer = string or nil, height = integer,
---    hasIcon = boolean }`.
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
  local height = M.cardHeight({
    title = input.title,
    lines = kept,
    overflow = overflow,
    hasIcon = hasIcon,
  }, cfg)

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
