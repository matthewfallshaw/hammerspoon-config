local fuzzy_match = require "utilities.fuzzy.fuzzy_match"
local M = fuzzy_match

describe("fuzzy_match:", function()
  describe("allCaseInsensitiveSplits()", function()
    it("should return the correct splits", function()
      assert.same(
        {
          {before = "abc", chr = "d", after = "efgdhij"},
          {before = "abcdefg", chr = "d", after = "hij"},
        },
        M.allCaseInsensitiveSplits("abcdefgdhij", "d")
      )
    end)
  end)

  describe("htmlEscape()", function()
    it("should return escaped html", function()
      assert.equal(
        "escaped &lt;b&gt;html&lt;/b&gt; &amp; stuff",
        M.htmlEscape("escaped <b>html</b> & stuff")
      )
      assert.equal(
        "plain text",
        M.htmlEscape("plain text")
      )
    end)
  end)

  describe("fuzzyMatch()", function()
    setup(function()
      doors     = "There are so <b>many</b> doors to open"
      doors_esc = "There are so &lt;b&gt;many&lt;/b&gt; doors to open"
    end)

    it("should, on an empty string and an empty abbr, return score SCORE_CONTINUE_MATCH",
      function()
        assert.same(
          {score=M.SCORE_CONTINUE_MATCH, html=''},
          M.fuzzyMatch("", "")
        )
      end
    )
    it("should, on an empty abbr, return score PENALTY_NOT_COMPLETE", function()
      assert.same(
        {score=M.PENALTY_NOT_COMPLETE, html=doors_esc},
        M.fuzzyMatch(doors, "")
      )
    end)
    it("should, on no match, return score 0", function()
      assert.same(
        {score=0, html=doors_esc},
        M.fuzzyMatch(doors, "Q")
      )
    end)
    it("should, on a complete match, return score SCORE_CONTINUE_MATCH^len", function()
      assert.same(
        {score=M.SCORE_CONTINUE_MATCH^4, html="<b>t</b><b>h</b><b>i</b><b>s</b>"},
        M.fuzzyMatch("this", "this")
      )
    end)
    it("should, on a matching first character, return score PENALTY_NOT_COMPLETE",
      function()
        assert.same(
          {score=M.PENALTY_NOT_COMPLETE, html="<b>t</b>his"},
          M.fuzzyMatch("this", "t")
        )
      end
    )
    it("should, on matching first two characters, return score PENALTY_NOT_COMPLETE",
      -- TODO: matching more characters should get a higher score
      function()
        assert.same(
          {score=M.PENALTY_NOT_COMPLETE, html="<b>t</b><b>h</b>is"},
          M.fuzzyMatch("this", "th")
        )
      end
    )
    it("should, on the matching first character of the second word,\z
        return score PENALTY_NOT_COMPLETE*SCORE_START_WORD*PENALTY_SKIPPED^before",
      function()
        assert.same(
          {
            score=M.PENALTY_NOT_COMPLETE*M.SCORE_START_WORD*M.PENALTY_SKIPPED^5,
            html="this <b>g</b>oat"
          },
          M.fuzzyMatch("this goat", "g")
        )
      end
    )
    describe("for a bunch of other matches...", function()
      fix = {
        { 'Harry', 'ry',
          M.SCORE_CONTINUE_MATCH*M.SCORE_OK*M.PENALTY_SKIPPED^3},
        { 'Harry', 'rr',
          M.PENALTY_NOT_COMPLETE*M.SCORE_CONTINUE_MATCH*M.SCORE_OK*M.PENALTY_SKIPPED^2},
        { 'Harry', 'arr',
          M.PENALTY_NOT_COMPLETE*M.SCORE_CONTINUE_MATCH^2*M.SCORE_OK*M.PENALTY_SKIPPED^1},
        { 'Harry', 'Har',
          M.PENALTY_NOT_COMPLETE*M.SCORE_CONTINUE_MATCH^2},
        { 'Harry', 'har',
          M.PENALTY_NOT_COMPLETE*M.PENALTY_CASE_MISMATCH*M.SCORE_CONTINUE_MATCH^2},
        { 'Harry', 'rry',
          M.SCORE_CONTINUE_MATCH^2*M.SCORE_OK*M.PENALTY_SKIPPED^2},
        { 'Harry and', ' ',
          M.PENALTY_NOT_COMPLETE*M.SCORE_OK*M.PENALTY_SKIPPED^5},
        { 'Harry or', 'y or',
          M.SCORE_CONTINUE_MATCH^3*M.SCORE_OK*M.PENALTY_SKIPPED^4},
      }
      for _,v in pairs(fix) do
        it("should, for '"..v[1].."' with '"..v[2].."', return the score "..v[3], function()
          assert.equal(v[3], M.fuzzyMatch(v[1], v[2]).score)
        end)
      end
    end)
  end)

  describe("fuzzySort()", function()
    setup(function()
      list = {
        { name = "Lucius", role = "Mastermind", level = 10 },
        { name = "Harry", role = "Hero", level = 3 },
        { name = "Hermione", role = "Brain", level = 7 },
      }
      sorted_list = M.fuzzySort(list, 'name', 'rr')
    end)

    it("should decorate the list with scores", function()
      assert.is_true(type(sorted_list[1]._score) == 'number')
    end)
  end)
end)
