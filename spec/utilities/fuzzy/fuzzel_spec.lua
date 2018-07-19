package.path = package.path .. ';../spec/?.lua'

describe("Fuzzel", function()
  describe(variant, function()
    fuzzel = require('utilities.fuzzy.fuzzel')

    setup(function()
      a = "abcdefg"
      b = "lbcedfg"
      c = "badcfeh"
      d = "hijklmn"
    end)

    describe("DamerauLevenshtein_extended", function()
      -- string_first, string_second,
      -- number_addcost, number_substituecost, number_deletecost,
      -- number_transpositioncost
      it("should return the right Distance", function()
        assert.are.equal(5, fuzzel.dld_e("abcdef","baefgh",1,1,1,1))
      end)
      it("should cost one less when transpositions are free", function()
        assert.are.equal(4, fuzzel.dld_e("abcdef","baefgh",1,1,1,0))
      end)
      it("should cost two less when deletes are free", function()
        assert.are.equal(3, fuzzel.dld_e("abcdef","baefgh",1,1,0,1))
      end)
      it("should cost nothing when substitutions are free", function()
        assert.are.equal(0, fuzzel.dld_e("abcdef","baefgh",1,0,1,1))
      end)
      it("should cost two less when additions are free", function()
        assert.are.equal(3, fuzzel.dld_e("abcdef","baefgh",0,1,1,1))
      end)
      it("should work well as a fuzzy search algorithm with free additions", function()
        assert.are.equal(0, fuzzel.dld_e("abndo","abner doon",0,1,1,1))
        assert.are.equal(3, fuzzel.dld_e("abndo","jason worthing",0,1,1,1))
        assert.are.equal(2, fuzzel.dld_e("abndo","abner quinn",0,1,1,1))
      end)
    end)

    describe("DamerauLevenshtein", function()
      it("should return the right Distance", function()
        assert.are.equal(2, fuzzel.DamerauLevenshteinDistance(a,b))
        assert.are.equal(3, fuzzel.DamerauLevenshteinDistance(a,b..'h'))
      end)
      it("should return the right Ratio", function()
        assert.are.equal(2/7, fuzzel.DamerauLevenshteinRatio(a,b))
        assert.are.equal(3/7, fuzzel.DamerauLevenshteinRatio(a,b..'h'))
      end)
    end)

    describe("Levenshtein", function()
      it("should return the right Distance", function()
        assert.are.equal(3, fuzzel.LevenshteinDistance(a,b))
        assert.are.equal(4, fuzzel.LevenshteinDistance(a,b..'h'))
      end)
      it("should return the right Ratio", function()
        assert.are.equal(3/7, fuzzel.LevenshteinRatio(a,b))
      end)
    end)

    describe("Hamming", function()
      it("should return the right Distance", function()
        assert.are.equal(3, fuzzel.HammingDistance(a,b))
        assert.has_error(function() fuzzel.HammingDistance(a,b..'h') end)
      end)
      it("should return the right Ratio", function()
        assert.are.equal(3/7, fuzzel.HammingRatio(a,b))
        assert.has_error(function() fuzzel.HammingRatio(a,b..'h') end)
      end)
    end)

    describe("FuzzyFind", function()
      describe("with multiple arguments", function()
        it("should return the right Distance", function()
          closest, distance = fuzzel.FuzzyFindDistance(a,b,c,d)
          assert.are.equal(b, closest)
          assert.are.equal(2, distance)
        end)
        it("should return the right Ratio", function()
          closest, ratio = fuzzel.FuzzyFindRatio(a,b,c,d)
          assert.are.equal(b, closest)
          assert.are.equal(2/7, ratio)
        end)
      end)

      describe("with multiple arguments", function()
        it("should return the right Distance", function()
          closest, distance = fuzzel.FuzzyFindDistance(a, {b,c,d})
          assert.are.equal(b, closest)
          assert.are.equal(2, distance)
        end)
        it("should return the right Ratio", function()
          closest, ratio = fuzzel.FuzzyFindRatio(a, {b,c,d})
          assert.are.equal(b, closest)
          assert.are.equal(2/7, ratio)
        end)
      end)
    end)

    describe("FuzzySort", function()
      describe("with multiple arguments", function()
        it("should return the right Distances", function()
          assert.are.same({b, c, d}, fuzzel.FuzzySortDistance(a,d,c,b))
        end)
      end)

      describe("with multiple arguments", function()
        it("should return the right Distance", function()
          assert.are.same({b, c, d}, fuzzel.FuzzySortDistance(a, {d,c,b}))
        end)
      end)
    end)

    describe("FuzzySortTableByKey", function()
      it("should return the right Distances", function()
        local input = {
          { key = d, extra = "extra", other = "other" },
          { key = c, extra = "extra", other = "other" },
          { key = b, extra = "extra", other = "other" },
        }
        assert.are.same(
          {input[3], input[2], input[1]},
          fuzzel.FuzzySortTableByKeyDistance(a,'key',input)
        )
      end)
    end)

    describe("FuzzyAutocomplete", function()
      describe("with multiple arguments", function()
        it("should return the right Distances", function()
          assert.are.same({b, c, d}, fuzzel.FuzzyAutocompleteDistance(a,d,c,b))
        end)
      end)

      describe("with multiple arguments", function()
        it("should return the right Distance", function()
          assert.are.same({b, c, d}, fuzzel.FuzzyAutocompleteDistance(a, {d,c,b}))
        end)
      end)
    end)
  end)
end)
