--- === FuzzyMatch ===
--- A fuzzy string-matching library, suitable for autocompletion.
---
--- Notes:
---   * This module was *very* heavily influenced by jQuery.fuzzyMatch.js
---     https://github.com/rapportive-oss/jquery-fuzzymatch/blob/master/jquery.fuzzymatch.js
---
--- Licensed under the MIT license: http://www.opensource.org/licenses/mit-license.php

local M = {}

-- The scores are arranged so that a continuous match of characters will result
-- in a total score of 1.
--
-- The best case, this character is a match, and either this is the start of the
-- string, or the previous character was also a match.
M.SCORE_CONTINUE_MATCH = 1

-- A new match at the start of a word scores better than a new match elsewhere
-- as it's more likely that the user will type the starts of fragments.
-- (Our notion of word includes CamelCase and hypen-separated, etc.)
M.SCORE_START_WORD = 0.9

-- Any other match isn't ideal, but it's probably ok.
M.SCORE_OK = 0.8

-- The goodness of a match should decay slightly with each missing character.
--
-- i.e. "bad" is more likely than "bard" when "bd" is typed.
--
-- This will not change the order of suggestions based on SCORE_* until 100
-- characters are inserted between matches.
M.PENALTY_SKIPPED = 0.999

-- The goodness of an exact-case match should be higher than a case-insensitive
-- match by a small amount.
--
-- i.e. "HTML" is more likely than "haml" when "HM" is typed.
--
-- This will not change the order of suggestions based on SCORE_* until 1000
-- characters are inserted between matches.
M.PENALTY_CASE_MISMATCH = 0.9999

-- If the word has more characters than the user typed, it should be penalised
-- slightly.
--
-- i.e. "html" is more likely than "html5" if I type "html".
--
-- However, it may well be the case that there's a sensible secondary ordering
-- (like alphabetical) that it makes sense to rely on when there are many prefix
-- matches, so we don't make the penalty increase with the number of tokens.
M.PENALTY_NOT_COMPLETE = 0.99

--- fuzzyMatch.allCaseInsensitiveSplits(str, chr) -> list
--- Function
--- Generates all possible split objects by splitting a string around a 
--- character in as many ways as possible.
---
--- Parameters:
---   * str - The string to split.
--    * char - A character on which to split the string.
--
--- Returns:
---   * list - a list of records, each including:
---     * before: The fragment of the string before this occurance of the
---       character.
---     * char: The original coy of this character (which may differ in case
---       from the "char" parameter).
---     * after: The fragment of the string after the occurance of the
---       character.
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

--- fuzzyMatch.htmlEscape(str) -> string
--- Function
--- Escapes '&', '<' and '>' characters in its input string.
---
--- Parameters:
---   * str, the string to escape.
---
--- Returns:
---   * str, the escaped input string.
function M.htmlEscape(str)
  return (str:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

--- fuzzyMatch.fuzzyMatch(str, abbreviation) -> record
--- Function
--- Generates a case-insensitive match of the abbreviation against the string.
---
--- Parameters:
---   * string, a canonical string to be matched against.
---   * abbreviation, an abbreviation that a user may have typed in order to
---     specify that string.
---
--- Returns:
---   * record including:
---     * score: A score (0 <= score <= 1) that indicates how likely it is that
---       the abbreviation matches the string.
---       The score is 0 if the characters in the abbreviation do not all appear
---       in order in the string.
---       The score is 1 if the user typed the exact string.
---       Scores are designed to be comparable when many different strings are
---       matched against the same abbreviation, for example for autocompleting.
---     * html: A copy of the input string html-escaped, with matching letters
---       surrounded by <b> and </b>.
function M.fuzzyMatch(str, abbreviation)
  if type(str) ~= "string" then str = tostring(str) end

  if (abbreviation == "") then
    local r = {
      score = str == "" and M.SCORE_CONTINUE_MATCH or M.PENALTY_NOT_COMPLETE,
      html  = M.htmlEscape(str),
-- TODO: debug
-- score_elements = str == "" and {'SCORE_CONTINUE_MATCH'} or {'PENALTY_NOT_COMPLETE'},
    }
    return r
  end

  local splits = M.allCaseInsensitiveSplits(str, abbreviation:sub(1,1))
  if (#splits == 0) then
    -- No matches for the next character in the abbreviation, abort!
    local r = {
      score = 0,  -- This 0 will multiply up to the top, giving a total of 0
      html  = M.htmlEscape(str),
-- TODO: debug
-- score_elements = {'MISS'},
    }
    return r
  end

  local results = {}
  for _,split in pairs(splits) do
    local result = M.fuzzyMatch(split.after, abbreviation:sub(2))

    local preceding_char_pos = split.before:len()
    local preceding_char = split.before:sub(preceding_char_pos,preceding_char_pos)
    if (split.before == "") then
      -- start of string
      result.score = result.score * M.SCORE_CONTINUE_MATCH
-- TODO: debug
-- table.insert(result.score_elements, 'SCORE_CONTINUE_MATCH')
    elseif (preceding_char:match('[\\/%-_%+%.# \t"@%[%({&]') or
        ( split.chr:lower() ~= split.chr and
          preceding_char:lower() == preceding_char)) then
      -- start of word
      result.score = result.score * M.SCORE_START_WORD
-- TODO: debug
-- table.insert(result.score_elements, 'SCORE_START_WORD')
    else
      -- matched character after a non-match gap
      result.score = result.score * M.SCORE_OK
-- TODO: debug
-- table.insert(result.score_elements, 'SCORE_OK')
    end

    if (split.chr ~= abbreviation:sub(1,1)) then
      -- extra case mismatch penalty
      result.score = result.score * M.PENALTY_CASE_MISMATCH
-- TODO: debug
-- table.insert(result.score_elements, 'PENALTY_CASE_MISMATCH')
    end

    -- extra penalty for a longer string of missed characters
    result.score = result.score * M.PENALTY_SKIPPED^split.before:len()
    result.html  =
        M.htmlEscape(split.before)..
        '<b>'..M.htmlEscape(split.chr)..'</b>'..
        result.html
-- TODO: debug
-- table.insert(result.score_elements, 'PENALTY_SKIPPED^'..split.before:len())

    table.insert(results, result)
  end

  table.sort(results, function(a, b) return a.score > b.score end)
  -- return the best match
  return results[1]
end

--- fuzzyMatch.fuzzySort(list, key, abbreviation) -> list
--- Function
--- Returns list sorted by key's fuzzyMatch score for abbreviation.
--- 
--- Parameters:
---   * list: a list of records
---   * key: the key field to sort the list by
---   * abbreviation: the search string to score each key field against.
---
--- Returns:
---   * list: the input list sorted, with extra fields `_score` and `_html`
---     added for each field's score and the matching characters contributing to
---     that score.
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
