--- Fuzzel
-- A collection of methods for finding edit distance between strings
--
-- original post:
-- https://gmod.facepunch.com/f/gmoddev/nwdd/Fuzzel-lua-Fuzzy-string-matching-Never-write-concommand-autocomplete-code-again/1/
--
-- then found at:
-- https://github.com/z-hunter/ade/blob/master/fuzzel.lua
-- with a public domain notice
--
-- extended by Matt Fallshaw
-- https://github.com/matthewfallshaw/fuzzel/

local Fuzzel = {}
Fuzzel._VERSION = "1.5"

-- locals to avoid global lookup of library functions
local math_min = math.min
local string_len, string_byte, string_sub = string.len, string.byte, string.sub
local table_insert, table_sort, table_unpack = table.insert, table.sort, table.unpack

--- Calculates the Damerau-Levenshtein Distance between two strings, with custom
-- values for edit operations
-- The minimum number of additions, deletions, substitutions, or transpositions
-- to turn str1 into str2 with the given weights
-- @function DamerauLevenshteinDistance_extended
-- @string str1 the first string
-- @string str2 the second string
-- @number addcost the cost of insterting a character
-- @number subcost the cost of substituting one character for another
-- @number delcost the cost of removing a character
-- @number trncost the cost of transposing two adjacent characters.
-- @return the edit distance between the two strings
-- @usage DamerauLevenshteinDistance_extended("berry","bury",0,1,2,1)
function Fuzzel.DamerauLevenshteinDistance_extended(
    string_first, string_second,
    number_addcost, number_substituecost, number_deletecost,
    number_transpositioncost)

  local length_of_first_string,length_of_second_string =
      string_len(string_first), string_len(string_second)

  -- Create a 0 matrix the size of len(a) x len(b)
  local V = {}
  for i = 0,length_of_first_string do
    V[i] = {}
    for j = 0,length_of_second_string do V[i][j] = 0 end
  end

  -- Initalize the matrix
  for i = 1,length_of_first_string do V[i][0] = i end
  for i = 1,length_of_second_string do V[0][i] = i end

  -- And build up the matrix based on costs-so-far
  for i = 1,length_of_second_string do
    for j = 1,length_of_first_string do
      local char_code_first_j = string_byte(string_first, j)
      local char_code_second_i = string_byte(string_second, i)
      V[j][i] = math_min(
          V[j-1][i] + number_deletecost,  -- deletion
          V[j][i-1] + number_addcost,  -- insertion
          V[j-1][i-1] +
              (char_code_first_j == char_code_second_i and
              0 or number_substituecost))  -- substitution
      if number_transpositioncost and
          j>1 and
          i>1 and
          char_code_first_j == string_byte(string_second, i-1) and
          string_byte(string_first, j-1) == char_code_second_i then
        V[j][i] = math_min(
            V[j][i],
            V[j-2][i-2]+
                (char_code_first_j == char_code_second_i and 0 or
                  number_transpositioncost))  -- transposition
      end
    end
  end
  return V[length_of_first_string][length_of_second_string]
end
Fuzzel.dld_e = Fuzzel.DamerauLevenshteinDistance_extended

--- Calculates the Damerau-Levenshtein Distance between two strings
-- The minimum number of additions, deletions, substitutions, or transpositions
-- to turn str1 into str2
-- @function DamerauLevenshteinDistance
-- @string str1 the fist string
-- @string str2 the second string
-- @return the minimum number of additions, deletions, substitutions, or
--   transpositions to turn str1 into str2
-- @usage fuzzel.DamerauLevenshteinDistance("tree","trap")
function Fuzzel.DamerauLevenshteinDistance(string_first, string_second)
  return Fuzzel.dld_e(string_first, string_second, 1,1,1,1)
end
Fuzzel.dld = Fuzzel.DamerauLevenshteinDistance

--- Calculates the Damerau-Levenshtein Distance between two strings divided by
-- the first string's length
-- @function DamerauLevenshteinRatio
-- @string str1 the fist string
-- @string str2 the second string
-- @return the minimum number of additions, deletions, substitutions, or
--   transpositions to turn str1 into str2, divided by the first string's length
-- @usage fuzzel.DamerauLevenshteinRatio("tree","trap")
function Fuzzel.DamerauLevenshteinRatio(string_first, string_second)
  return Fuzzel.dld(string_first, string_second)/string_len(string_first)
end
Fuzzel.dlr = Fuzzel.DamerauLevenshteinRatio

--- Calculates the Levenshtein Distance between two strings, with custom
-- values for edit operations
-- The minimum number of additions, deletions, or substitutions to turn str1
-- into str2 with the given weights
-- @function LevenshteinDistance_extended
-- @string str1 the first string
-- @string str2 the second string
-- @number addcost the cost of insterting a character
-- @number subcost the cost of substituting one character for another
-- @number delcost the cost of removing a character
-- @return the edit distance between the two strings
-- @usage LevenshteinDistance_extended("berry","bury",0,1,2)
function Fuzzel.LevenshteinDistance_extended(
    string_first, string_second,
    number_addcost, number_substituecost, number_deletecost)
  return Fuzzel.DamerauLevenshteinDistance_extended(
      string_first, string_second,
      number_addcost, number_substituecost, number_deletecost,
      nil)  -- transpositions not allowed
end
Fuzzel.ld_e = Fuzzel.LevenshteinDistance_extended

--- Calculates the Levenshtein Distance between two strings
-- The minimum number of additions, deletions, or substitutions to turn str1
-- into str2
-- @function LevenshteinDistance
-- @string str1 the fist string
-- @string str2 the second string
-- @return the minimum number of additions, deletions, or substitutions to turn
-- str1 into str2
-- @usage fuzzel.LevenshteinDistance("tree","trap")
function Fuzzel.LevenshteinDistance(string_first, string_second)
  return Fuzzel.ld_e(string_first, string_second, 1,1,1)
end
Fuzzel.ld = Fuzzel.LevenshteinDistance

--- Calculates the Levenshtein Distance between two strings divided by the first
-- string's length.  Using a ratio is a decent way to determine if a spelling is
-- "close enough"
-- @function LevenshteinDistance
-- @string str1 the fist string
-- @string str2 the second string
-- @return the minimum number of additions, deletions, or substitutions to turn
-- str1 into str2
-- @usage fuzzel.LevenshteinRatio("tree","trap")
function Fuzzel.LevenshteinRatio(string_first, string_second)
  return Fuzzel.ld(string_first, string_second)/string_len(string_first)
end
Fuzzel.lr = Fuzzel.LevenshteinRatio

--- Calculates the Hamming Distance between two strings
-- The minimum number of substitutions to turn str1 into str2.
-- Hamming distance can only be calculated on two strings of equal length.
-- @function HammingDistance
-- @string str1 the fist string
-- @string str2 the second string
-- @return the minimum number of substitutions to turn str1 into str2
-- @usage fuzzel.HammingDistance("tree","trap")
function Fuzzel.HammingDistance(string_first, string_second)
  local length_of_first_string, out = string_len(string_first), 0
  assert(length_of_first_string == string_len(string_second),
    'Hamming Distance cannot be calculated on two strings of different lengths:\z
    "'..string_first..'" "'..string_second..'"')
  for i = 1,length_of_first_string do
    out = out+(string_byte(string_first, i) ~= string_byte(string_second, i) and 1 or 0)
  end
  return out
end
Fuzzel.hd = Fuzzel.HammingDistance

--- Calculates the Hamming Distance between two strings divided by the first
-- string's length.
-- Hamming distance can only be calculated on two strings of equal length.
-- @function HammingRatio
-- @string str1 the fist string
-- @string str2 the second string
-- @return the minimum number of substitutions to turn str1 into str2
-- @usage fuzzel.HammingRatio("tree","trap")
-- @usage fuzzel.HammingRatio("seven","ten") -- Will throw an error, since
-- "seven" is 5 characters long while "ten" is 3 characters long
function Fuzzel.HammingRatio(string_first, string_second)
  return Fuzzel.hd(string_first, string_second)/string_len(string_first)
end
Fuzzel.hr = Fuzzel.HammingRatio


local function fuzzy_search(string_needle, distance_fn, ...)
  local arg = {...}

  -- Allow varargs, or a table
  local search_in = type(arg[1]) == "table" and arg[1] or arg

  -- Find the string with the shortest distance to the string we were supplied
  local cost_of_closest, closest = distance_fn(search_in[1], string_needle), search_in[1]
  for k,v in pairs(search_in) do
    local cost_of_next = distance_fn(v, string_needle)
    if cost_of_next<=cost_of_closest then cost_of_closest, closest = cost_of_next, k end
  end
  return search_in[closest], cost_of_closest
end

--- Finds the closest argument to the first argument.
-- Finds the closest argument to the first argument using Damerau-Levenshtein
-- distance. If multiple options have the same distance, it will return the
-- first one encountered (this may not be in any sort of order!)
-- @function FuzzyFindDistance
-- @string str the string to compare to
-- @param ... A 1-indexed array of strings, or a list of strings to compare str
-- against
-- @usage fuzzel.FuzzyFindDistance("tap","tape","strap","tab")
-- @usage fuzzel.FuzzyFindDistance("tap",{"tape","strap","tab"})
function Fuzzel.FuzzyFindDistance(string_needle, ...)
  return table_unpack{fuzzy_search(string_needle, Fuzzel.dld, ...)}
end
Fuzzel.ffd = Fuzzel.FuzzyFindDistance

--- Finds the closest argument to the first argument.
-- Finds the closest argument to the first argument using Damerau-Levenshtein
-- ratio. If multiple options have the same distance, it will return the
-- first one encountered (this may not be in any sort of order!)
-- @function FuzzyFindRatio
-- @string str the string to compare to
-- @param ... A 1-indexed array of strings, or a list of strings to compare str
-- against
-- @usage fuzzel.FuzzyFindRatio("tap","tape","strap","tab")
-- @usage fuzzel.FuzzyFindRatio("tap",{"tape","strap","tab"})
function Fuzzel.FuzzyFindRatio(string_needle, ...)
  return table_unpack{fuzzy_search(string_needle, Fuzzel.dlr, ...)}
end
Fuzzel.ffr = Fuzzel.FuzzyFindRatio

function Fuzzel.FuzzySort(string_needle, distance_fn, short, key, ...)
  local arg = {...}

  -- allow varargs, or a table
  local search_in = type(arg[1]) == "table" and arg[1] or arg

  -- Roughly sort everything by it's distance to the string
  local unsorted,sorted,otbl,length_of_needle = {},{},{},string_len(string_needle)
  for _,item in pairs(search_in) do
    local val = key and item[key] or item
    local sstr = short and string_sub(val, 0, length_of_needle) or val
    local dist = distance_fn(string_needle, sstr)
    if unsorted[dist] == nil then
      unsorted[dist] = {}
      table_insert(sorted, dist)
    end
    table_insert(unsorted[dist], item)
  end

  -- Actually sort them into something can can be iterated with ipairs
  table_sort(sorted)

  -- Then build our output table
  for _,dist in ipairs(sorted) do
    for _,item in pairs(unsorted[dist]) do
      if key then item._dist = dist end
      table_insert(otbl, item)
    end
  end
  return otbl
end

--- Sorts input strings by distance.
-- Finds the Damerau-Levenshtein distance of each string to the first argument,
-- and sorts them into a table accordingly
-- @function FuzzySortDistance
-- @string str the string to compare each result to
-- @param ... either a 1-indexed table, or a list of strings to sort
-- @return a 1-indexed table of the input strings, in the order of closest-to
-- str to farthest-from str
-- @usage fuzzel.FuzzySortDistance("tub","toothpaste","stub","tube")
-- @usage fuzzel.FuzzySortDistance("tub",{"toothpaste","stub","tube"})
function Fuzzel.FuzzySortDistance(string_needle, ...)
  return Fuzzel.FuzzySort(string_needle, Fuzzel.dld, false, nil, ...)
end
Fuzzel.fsd = Fuzzel.FuzzySortDistance

--- Sorts input strings by distance ratio.
-- Finds the Damerau-Levenshtein ratio of each string to the first argument,
-- and sorts them into a table accordingly
-- @function FuzzySortRatio
-- @string str the string to compare each result to
-- @param ... either a 1-indexed table, or a list of strings to sort
-- @return a 1-indexed table of the input strings, in the order of closest-to
-- str to farthest-from str
-- @usage fuzzel.FuzzySortRatio("tub","toothpaste","stub","tube")
-- @usage fuzzel.FuzzySortRatio("tub",{"toothpaste","stub","tube"})
function Fuzzel.FuzzySortRatio(string_needle, ...)
  return Fuzzel.FuzzySort(string_needle, Fuzzel.dlr, false, nil, ...)
end
Fuzzel.fsr = Fuzzel.FuzzySortRatio

--- Sorts truncated input strings by distance.
-- Truncates strings to the length of the input string, then finds the
-- Damerau-Levenshtein distance of each string to the truncated first argument,
-- and sorts them into a table accordingly
-- @function FuzzyAutocompleteDistance
-- @string str the string to compare each result to
-- @param ... either a 1-indexed table, or a list of strings to sort
-- @return a 1-indexed table of the input strings, in the order of closest-to
-- str to farthest-from str
-- @usage fuzzel.FuzzyAutocompleteDistance("tub","toothpaste","stub","tube")
-- @usage fuzzel.FuzzyAutocompleteDistance("tub",{"toothpaste","stub","tube"})
function Fuzzel.FuzzyAutocompleteDistance(string_needle, ...)
  return Fuzzel.FuzzySort(string_needle, Fuzzel.dld, true, nil, ...)
end
Fuzzel.fad = Fuzzel.FuzzyAutocompleteDistance

--- Sorts truncated input strings by distance ratio.
-- Truncates strings to the length of the input string, then finds the
-- Damerau-Levenshtein ratio of each string to the first argument,
-- and sorts them into a table accordingly
-- @function FuzzyAutocompleteRatio
-- @string str the string to compare each result to
-- @param ... either a 1-indexed table, or a list of strings to sort
-- @return a 1-indexed table of the input strings, in the order of closest-to
-- str to farthest-from str
-- @usage fuzzel.FuzzyAutocompleteRatio("tub","toothpaste","stub","tube")
-- @usage fuzzel.FuzzyAutocompleteRatio("tub",{"toothpaste","stub","tube"})
function Fuzzel.FuzzyAutocompleteRatio(string_needle, ...)
  return Fuzzel.FuzzySort(string_needle, Fuzzel.dlr, true, nil, ...)
end
Fuzzel.far = Fuzzel.FuzzyAutocompleteRatio

--- Sorts a table by a key field's distance to a supplied string.
-- @function FuzzySortTableByKeyDistance
-- @string str the string to compare each result to
-- @string key the field containing the strings str should be compared to
-- @param ... a 1-indexed table
-- @return the supplied 1-indexed table, in the order of closest-to
-- str to farthest-from str by the key field
-- @usage fuzzel.FuzzySortTableByKeyDistance("bestm", "key_field",
--    {
--      {key_field='best_match',other_field='something'},
--      {key_field='second_best_match',other_field='something else'},
--      ...
--    })
function Fuzzel.FuzzySortTableByKeyDistance(string_needle, key, ...)
  return Fuzzel.FuzzySort(string_needle, Fuzzel.dld, false, key, ...)
end
Fuzzel.fstbyd = Fuzzel.FuzzySortTableByKeyDistance

return Fuzzel




--[[
    Original documentation from v1.4

    Fuzzel v1.4 - Alexander "Apickx" Pickering
    Entered into the public domain June 2, 2016
    You are not required to, but consider putting a link to the source in your file's comments!

    Example:
        Returns a function that will return the closest string to the string it was passed
        -----------------FuzzelExample.lua------------------
        --Include the module
        local fuzzel = require("fuzzel.lua")

        --A couple of options
        local options = {
            "Fat Cat",
            "Lazy Dog",
            "Brown Fox",
        }

        --And use it, to see what option closest matches "Lulzy Cat"
        local close,distance = fuzzel.FuzzyFindDistance("Lulzy Cat", options)
        print("\"Lulzy Cat\" is close to \"" .. close .. "\", distance:" .. distance)

        --Sort the options to see the order in which they most closely match "Frag God"
        print("\"Frag God\" is closest to:")
        for k,v in ipairs(fuzzel.FuzzySortRatio("Frag God",options)) do
            print(k .. "\t:\t" .. v)
        end
        -------------End FuzzelExample.lua------------------
        Outputs:
            "Lulzy Cat" is close to "Fat Cat"
            "Frag God" is closest to:
            1       :       Fat Cat
            2       :       Lazy Dog
            3       :       Brown Fox

    Some easy-to-use mnemonics
        fuzzel.ld_e = fuzzel.LevenshteinDistance_extended
        fuzzel.ld = fuzzel.LevenshteinDistance
        fuzzel.lr = fuzzel.LevensteinRatio
        fuzzel.dld_e = fuzzel.DamerauLevenshteinDistance_extended
        fuzzel.dld = fuzzel.DamerauLevenshteinDistance
        fuzzel.dlr = fuzzel.DamerauLevenshteinRatio
        fuzzel.hd = fuzzel.HammingDistance
        fuzzel.hr = fuzzel.HammingRatio
        fuzzel.ffd = fuzzel.FuzzyFindDistance
        fuzzel.ffr = fuzzel.FuzzyFindRatio
        fuzzel.fsd = fuzzel.FuzzySortDistance
        fuzzel.fsr = fuzzel.FuzzySortRatio
        fuzzel.fad = fuzzel.FuzzyAutocompleteDistance
        fuzzel.far = fuzzel.FuzzyAutocompleteRatio

]]
