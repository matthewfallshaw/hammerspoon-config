describe("notify.layout", function()
  local layout = require "notify.layout"

  describe(".wrap", function()
    it("does not wrap a word that ends exactly at maxChars", function()
      assert.are.same({ "hello" }, layout.wrap("hello", 5))
    end)

    it("wraps a word that is exactly one char over maxChars (hard split)", function()
      assert.are.same({ "hello", "s" }, layout.wrap("hellos", 5))
    end)

    it("does not wrap a word that is exactly one char under maxChars", function()
      assert.are.same({ "hell" }, layout.wrap("hell", 5))
    end)

    it("breaks two words at the space once maxChars is exceeded", function()
      -- "hello" (5) fits exactly; " world" would push past maxChars=5.
      assert.are.same({ "hello", "world" }, layout.wrap("hello world", 5))
    end)

    it("preserves a run of spaces mid-line when it fits", function()
      assert.are.same({ "a   b" }, layout.wrap("a   b", 10))
    end)

    it("drops trailing whitespace produced by a forced wrap", function()
      -- "ab" + "  " (2 spaces) + "cdef": "ab  " (4) + "cdef" (4) = 8 > 6,
      -- so the wrap point falls inside the spaces; they're discardable
      -- separator whitespace, not content, so both lines start clean.
      assert.are.same({ "ab", "cdef" }, layout.wrap("ab  cdef", 6))
    end)

    it("preserves hard newlines as line breaks", function()
      assert.are.same({ "one", "two", "three" }, layout.wrap("one\ntwo\nthree", 20))
    end)

    it("produces empty lines for consecutive newlines", function()
      assert.are.same({ "a", "", "b" }, layout.wrap("a\n\nb", 20))
    end)

    it("hard-splits a single over-long word across lines at exactly maxChars", function()
      assert.are.same({ "aaaaa", "aaaaa", "aa" }, layout.wrap("aaaaaaaaaaaa", 5))
    end)

    it("expands tabs to spaces using the default tabWidth of 4", function()
      assert.are.same({ "a    b" }, layout.wrap("a\tb", 20))
    end)

    it("expands tabs using a custom tabWidth", function()
      assert.are.same({ "a  b" }, layout.wrap("a\tb", 20, { tabWidth = 2 }))
    end)

    it("returns {\"\"} for an empty string", function()
      assert.are.same({ "" }, layout.wrap("", 10))
    end)

    it("returns one empty line per line-break for a string of only newlines", function()
      assert.are.same({ "", "", "" }, layout.wrap("\n\n", 10))
    end)

    it("counts an em-dash as one column, not three bytes", function()
      local dashes = string.rep("—", 5)
      local lines = layout.wrap(dashes, 5)
      assert.are.same({ dashes }, lines)
    end)

    it("counts an emoji as one column, not four bytes", function()
      local emoji = string.rep("🎉", 5)
      local lines = layout.wrap(emoji, 5)
      assert.are.same({ emoji }, lines)
    end)

    it("hard-splits em-dashes without cutting a codepoint in half", function()
      local dashes = string.rep("—", 5) -- 15 bytes, 5 columns
      local lines = layout.wrap(dashes, 3)
      assert.are.same({ string.rep("—", 3), string.rep("—", 2) }, lines)
      assert.are.equal(9, #lines[1]) -- 3 codepoints * 3 bytes, not sliced mid-codepoint
      assert.are.equal(6, #lines[2])
    end)

    it("hard-splits emoji without cutting a codepoint in half", function()
      local emoji = string.rep("🎉", 5) -- 20 bytes, 5 columns
      local lines = layout.wrap(emoji, 2)
      assert.are.same({ "🎉🎉", "🎉🎉", "🎉" }, lines)
      assert.are.equal(8, #lines[1]) -- 2 codepoints * 4 bytes
      assert.are.equal(8, #lines[2])
      assert.are.equal(4, #lines[3])
    end)
  end)

  describe(".truncate", function()
    it("returns all lines and 0 overflow when #lines == maxLines", function()
      local lines = { "a", "b", "c" }
      local kept, overflow = layout.truncate(lines, 3)
      assert.are.same({ "a", "b", "c" }, kept)
      assert.are.equal(0, overflow)
    end)

    it("cuts by 1 when #lines is one over maxLines", function()
      local lines = { "a", "b", "c", "d" }
      local kept, overflow = layout.truncate(lines, 3)
      assert.are.same({ "a", "b", "c" }, kept)
      assert.are.equal(1, overflow)
    end)

    it("treats maxLines == nil as no limit", function()
      local lines = { "a", "b", "c", "d", "e" }
      local kept, overflow = layout.truncate(lines, nil)
      assert.are.same(lines, kept)
      assert.are.equal(0, overflow)
    end)

    it("treats maxLines == 0 as no limit", function()
      local lines = { "a", "b", "c" }
      local kept, overflow = layout.truncate(lines, 0)
      assert.are.same(lines, kept)
      assert.are.equal(0, overflow)
    end)
  end)

  describe(".overflowFooter", function()
    it("returns nil at zero overflow", function()
      assert.is_nil(layout.overflowFooter(0))
    end)

    it("returns nil for nil overflow", function()
      assert.is_nil(layout.overflowFooter(nil))
    end)

    it("uses singular phrasing for 1 line of overflow", function()
      assert.are.equal("… (+1 more line)", layout.overflowFooter(1))
    end)

    it("uses plural phrasing for more than 1 line of overflow", function()
      assert.are.equal("… (+4 more lines)", layout.overflowFooter(4))
    end)
  end)

  describe(".cardHeight", function()
    local cfg = { padding = 8, titleHeight = 14, titleGap = 4, lineHeight = 16, minHeight = 0 }

    it("computes height without a title and without overflow", function()
      local spec = { title = nil, lines = { "a", "b" }, overflow = 0, hasIcon = false }
      -- 8*2 + 0 + 2*16 + 0 = 48
      assert.are.equal(48, layout.cardHeight(spec, cfg))
    end)

    it("adds titleHeight + titleGap when a title is present", function()
      local spec = { title = "Title", lines = { "a", "b" }, overflow = 0, hasIcon = false }
      -- 8*2 + (14+4) + 2*16 = 66
      assert.are.equal(66, layout.cardHeight(spec, cfg))
    end)

    it("adds one lineHeight when there is overflow", function()
      local spec = { title = nil, lines = { "a", "b" }, overflow = 3, hasIcon = false }
      -- 8*2 + 0 + 2*16 + 16 = 64
      assert.are.equal(64, layout.cardHeight(spec, cfg))
    end)

    it("adds title, lines and overflow together", function()
      local spec = { title = "Title", lines = { "a", "b" }, overflow = 3, hasIcon = false }
      -- 8*2 + 18 + 32 + 16 = 82
      assert.are.equal(82, layout.cardHeight(spec, cfg))
    end)

    it("floors at cfg.minHeight", function()
      local floored = { padding = 8, titleHeight = 14, titleGap = 4, lineHeight = 16, minHeight = 200 }
      local spec = { title = nil, lines = { "a" }, overflow = 0, hasIcon = false }
      assert.are.equal(200, layout.cardHeight(spec, floored))
    end)
  end)

  describe(".stackFrames", function()
    local cfg = { cardWidth = 300, stackGap = 10, marginTop = 20, marginRight = 20 }
    local screenFrame = { x = 0, y = 0, w = 1920, h = 1080 }

    it("returns an empty array for 0 cards", function()
      assert.are.same({}, layout.stackFrames({}, screenFrame, cfg))
    end)

    it("places a single card top-right, offset by margins", function()
      local frames = layout.stackFrames({ 100 }, screenFrame, cfg)
      assert.are.same({ { x = 1600, y = 20, w = 300, h = 100 } }, frames)
    end)

    it("stacks 3 cards downward, oldest topmost, separated by stackGap", function()
      local frames = layout.stackFrames({ 100, 50, 80 }, screenFrame, cfg)
      assert.are.same({
        { x = 1600, y = 20, w = 300, h = 100 },
        { x = 1600, y = 130, w = 300, h = 50 }, -- 20 + 100 + 10
        { x = 1600, y = 190, w = 300, h = 80 }, -- 130 + 50 + 10
      }, frames)
    end)

    it("right-aligns on a screen to the left of the primary (non-zero, negative origin)", function()
      local leftScreen = { x = -1920, y = 0, w = 1920, h = 1080 }
      local frames = layout.stackFrames({ 100 }, leftScreen, cfg)
      -- x = -1920 + 1920 - 20 - 300 = -320
      assert.are.same({ { x = -320, y = 20, w = 300, h = 100 } }, frames)
    end)

    it("closes the gap left by removing a middle card, without moving cards above it", function()
      local heights = { 100, 50, 80 }
      local before = layout.stackFrames(heights, screenFrame, cfg)

      table.remove(heights, 2) -- dismiss the middle card
      local after = layout.stackFrames(heights, screenFrame, cfg)

      -- Card 1 (was index 1) is unmoved.
      assert.are.equal(before[1].y, after[1].y)
      -- Card 3 (now index 2) moved up into card 2's old slot.
      assert.are.equal(before[2].y, after[2].y)
      assert.are_not.equal(before[3].y, after[2].y)
    end)
  end)

  describe(".bodyColumns", function()
    it("floors the division", function()
      -- (200 - 8*2) / 7 = 184/7 = 26.28...
      assert.are.equal(26, layout.bodyColumns(200, 7, { padding = 8, hasIcon = false }))
    end)

    it("subtracts icon width and gap when hasIcon is true", function()
      -- (200 - 16 - (20+6)) / 7 = 158/7 = 22.57...
      assert.are.equal(22, layout.bodyColumns(200, 7, {
        padding = 8, hasIcon = true, iconWidth = 20, iconGap = 6,
      }))
    end)

    it("floors at a minimum of 1 when the card is too narrow", function()
      assert.are.equal(1, layout.bodyColumns(10, 20, { padding = 8, hasIcon = false }))
    end)
  end)

  describe(".compose", function()
    local cfg = {
      padding = 8, titleHeight = 14, titleGap = 4, lineHeight = 16, minHeight = 40,
      cardWidth = 260, stackGap = 8, marginTop = 10, marginRight = 10,
      charWidth = 8, maxLines = 3, iconWidth = 20, iconGap = 6,
    }

    it("wraps, truncates, foots and measures a long multi-paragraph message end-to-end", function()
      local paragraph = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod"
      local message = paragraph .. "\n\n" .. paragraph
      local card = layout.compose({ message = message, title = "Clipboard", icon = nil }, cfg)

      assert.are.equal("Clipboard", card.title)
      assert.is_false(card.hasIcon)
      assert.are.equal(cfg.maxLines, #card.lines)
      assert.is_true(card.overflow > 0)
      assert.are.equal(layout.overflowFooter(card.overflow), card.footer)
      assert.are.equal(
        layout.cardHeight({
          title = card.title, lines = card.lines, overflow = card.overflow, hasIcon = card.hasIcon,
        }, cfg),
        card.height
      )
    end)

    it("sets hasIcon and narrows the wrap width when an icon is present", function()
      local card = layout.compose({ message = "hello world", title = nil, icon = "some-icon" }, cfg)
      assert.is_true(card.hasIcon)
      assert.are.same({ "hello world" }, card.lines)
      assert.are.equal(0, card.overflow)
      assert.is_nil(card.footer)
    end)

    it("handles an empty message without erroring", function()
      local card = layout.compose({ message = "", title = nil, icon = nil }, cfg)
      assert.are.same({ "" }, card.lines)
      assert.are.equal(0, card.overflow)
      assert.are.equal(cfg.minHeight, card.height)
    end)
  end)
end)
