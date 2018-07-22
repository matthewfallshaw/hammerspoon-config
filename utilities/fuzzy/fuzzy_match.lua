--- FuzzyMatch
-- A fuzzy string-matching library for autocompleting in lua.
-- based on
--   LiquidMetal
--     http://github.com/rmm5t/liquidmetal/blob/master/liquidmetal.js
--   quicksilver.js
--     http://code.google.com/p/rails-oceania/source/browse/lachiecox/qs_score/trunk/qs_score.js
--   QuickSilver
--     http://code.google.com/p/blacktree-alchemy/source/browse/trunk/Crucible/Code/NSString_BLTRExtensions.m#61
--   FuzzyString
--     https://github.com/dcparker/jquery_plugins/blob/master/fuzzy-string/fuzzy-string.js
--   jQuery.fuzzyMatch.js
--     https://github.com/rapportive-oss/jquery-fuzzymatch/blob/master/jquery.fuzzymatch.js
--
-- Licensed under the MIT: http://www.opensource.org/licenses/mit-license.php

local M = {}

-- The scores are arranged so that a continuous match of characters will
-- result in a total score of 1.
--
-- The best case, this character is a match, and either this is the start
-- of the string, or the previous character was also a match.
M.SCORE_CONTINUE_MATCH = 1

-- A new match at the start of a word scores better than a new match
-- elsewhere as it's more likely that the user will type the starts
-- of fragments.
-- (Our notion of word includes CamelCase and hypen-separated, etc.)
M.SCORE_START_WORD = 0.9

-- Any other match isn't ideal, but it's probably ok.
M.SCORE_OK = 0.8

-- The goodness of a match should decay slightly with each missing
-- character.
--
-- i.e. "bad" is more likely than "bard" when "bd" is typed.
--
-- This will not change the order of suggestions based on SCORE_* until
-- 100 characters are inserted between matches.
M.PENALTY_SKIPPED = 0.999

-- The goodness of an exact-case match should be higher than a
-- case-insensitive match by a small amount.
--
-- i.e. "HTML" is more likely than "haml" when "HM" is typed.
--
-- This will not change the order of suggestions based on SCORE_* until
-- 1000 characters are inserted between matches.
M.PENALTY_CASE_MISMATCH = 0.9999

-- If the word has more characters than the user typed, it should
-- be penalised slightly.
--
-- i.e. "html" is more likely than "html5" if I type "html".
--
-- However, it may well be the case that there's a sensible secondary
-- ordering (like alphabetical) that it makes sense to rely on when
-- there are many prefix matches, so we don't make the penalty increase
-- with the number of tokens.
M.PENALTY_NOT_COMPLETE = 0.99

--- Generates all possible split objects by splitting a string around a 
-- character in as many ways as possible.
--
-- @param str The string to split
-- @param char   A character on which to split it.
--
-- @return [{
--   before: The fragment of the string before this occurance of the
--           character.
--
--   char: The original coy of this character (which may differ in case
--         from the "char" parameter).
--
--   after: The fragment of the string after the occurance of the character.
-- }]
function M.allCaseInsensitiveSplits(str, chr)
  local lower = str:lower()
  local lchr  = chr:lower()

  local ii = lower:find(lchr) or -1
  local result = {}

  while (ii > -1) do
    table.insert(result, {
      before = str:sub(1, ii - 1),
      chr = str:sub(ii, ii),
      after = str:sub(ii + 1, -1),
    })

    ii = lower:find(lchr, ii + 1) or -1
  end
  return result
end

--- Escapes a string so that it can be interpreted as HTML node content.
--
-- @param str, the string to escape
-- @return str, the escaped version.
function M.htmlEscape(str)
  return (str:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

--- Generates a case-insensitive match of the abbreviation against the string
--
-- @param string, a canonical string to be matched against.
-- @param abbreviation, an abbreviation that a user may have typed
--                      in order to specify that string.
--
-- @cache (private), a cache that reduces the expected running time of the
--                   algorithm in the case there are many repeated characters.
--
-- @return {
--    score:  A score (0 <= score <= 1) that indicates how likely it is that
--            the abbreviation matches the string.
--
--            The score is 0 if the characters in the abbreviation do not
--            all appear in order in the string.
--
--            The score is 1 if the user typed the exact string.
--
--            Scores are designed to be comparable when many different
--            strings are matched against the same abbreviation, for example
--            for autocompleting.
--
--    html:   A copy of the input string html-escaped, with matching letters
--            surrounded by <b> and </b>.
--
function M.fuzzyMatch(str, abbreviation, cache)
  if (abbreviation == "") then
    local r = {
      score = str == "" and M.SCORE_CONTINUE_MATCH or M.PENALTY_NOT_COMPLETE,
      html  = M.htmlEscape(str),
    }
    return r
  end

  if (cache and cache[str] and cache[str][abbreviation]) then
    return cache[str][abbreviation]
  end

  local splits = M.allCaseInsensitiveSplits(str, abbreviation:sub(1,1))
  if (#splits == 0) then
    -- No matches for the next character in the abbreviation, abort!
    local r = {
      score = 0,  -- This 0 will multiply up to the top, giving a total of 0
      html  = M.htmlEscape(str)
    }
    return r
  end

  cache = cache or {}
  cache[str] = cache[str] or {}

  local results = {}
  for _,split in pairs(splits) do
    local result = M.fuzzyMatch(split.after, abbreviation:sub(2), cache)

    local preceding_char_pos = split.before:len()
    local preceding_char = split.before:sub(preceding_char_pos,preceding_char_pos)
    if (split.before == "") then
      -- start of string
      result.score = result.score * M.SCORE_CONTINUE_MATCH
    elseif (preceding_char:match('[\\/%-_%+%.# \t"@%[%({&]') or
        ( split.chr:lower() ~= split.chr and
          preceding_char:lower() == preceding_char)) then
      -- start of word
      result.score = result.score * M.SCORE_START_WORD
    else
      -- matched character after a non-match gap
      result.score = result.score * M.SCORE_OK
    end

    if (split.chr ~= abbreviation:sub(1,1)) then
      -- extra case mismatch penalty
      result.score = result.score * M.PENALTY_CASE_MISMATCH
    end

    -- extra penalty for a longer string of missed characters
    result.score = result.score * M.PENALTY_SKIPPED^split.before:len()
    result.html  =
        M.htmlEscape(split.before)..
        '<b>'..M.htmlEscape(split.chr)..'</b>'..
        result.html

    table.insert(results, result)
  end

  table.sort(results, function(a, b) return a.score > b.score end)
  cache[str][abbreviation] = results[1]  -- cache the result
  -- return the best match
  return results[1]
end

function M.fuzzySort(list, key, abbreviation)
  local out = {}

  for _,v in pairs(list) do
    local match = M.fuzzyMatch(v[key], abbreviation)
    local row = {}
    for k,v in pairs(v) do
      row[k] = v
    end
    row._score = match.score
    row._match = match.html
    table.insert(out, row)
  end

  table.sort(out, function(a,b)
    if a._score == b._score then
      return (a[key] < b[key])
    else
      return (a._score > b._score)
    end
  end)

  return out
end

return M
