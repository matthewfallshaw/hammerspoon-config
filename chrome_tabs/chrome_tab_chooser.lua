local M = {}

local fuzzy_match = require 'utilities.fuzzy.fuzzy_match'

local function is_empty(tbl)
  return next(tbl) == nil
end

local function generate_choices()
  local choices = M.choices  -- speed
  local ii = 0
  for _,chromeWindow in pairs(chrome_tabs.chromeWindows) do
    for _,chromeTab in pairs(chromeWindow.chromeTabs) do
      ii = ii + 1
      local choice = {
        text = chromeTab.tabTitle == '' and chromeTab.tabURL or chromeTab.tabTitle,
        subText = (string.gsub(chromeTab.tabURL, '^chrome%-extension.*uri=http', 'http')),
        uuid = ii,
        chromeWindowId = chromeWindow.windowId,
        chromeTabId = chromeTab.tabId,
        _match = {},
      }
      choices[#choices+1] = choice
    end
  end
  return choices
end
M._generate_choices = generate_choices

local function score_choices(choices, query)
  local query_is_lowercase = query == query:lower()
  hs.fnutils.each(choices, function(choice)
    if query ~= '' then
      local title_search_text = query_is_lowercase and chromeTab.tabTitle:lower() or chromeTab.tabTitle
      local title_match = fuzzy_match.fuzzyMatch(title_search_text, query)
      local url_search_text = query_is_lowercase and chromeTab.tabURL:lower() or chromeTab.tabURL
      local url_match = fuzzy_match.fuzzyMatch(url_search_text, query)
      choice._match.title = title_match
      choice._match.url = url_match
      choice._match.best = title_match.score >= url_match.score and title_match or url_match
    else
      choice._match.title = ''
      choice._match.url = ''
      choice._match.best = 0
    end
  end)
  return choices
end

local function choices_fn()
  local query = M.chooser:query()
  local query_length = query:len()

  local choices
  if is_empty(M.choices) then
    choices = generate_choices()
  end

  choices = score_choices(choices, query)

  if query ~= '' then
    table.sort(choices, function(a,b) return a._match.best.score > b._match.best.score end)
  end
  return choices
end
M._choices_fn = choices_fn

local function completion_fn(choice)
  if choice ~= nil then
    local chromeWindow = chrome_tabs.chromeWindows[choice.chromeWindowId]
    local chromeTab = chromeWindow.chromeTabs[choice.chromeTabId]
    chromeTab:focus()
  end
  M.choices = {}  -- clear past choices
  return nil
end
M._completion_fn = completion_fn


M.chooser = hs.chooser.new(completion_fn)
M.chooser:choices(choices_fn)
M.chooser:queryChangedCallback(function(_) M.timer:start() end)
M.timer = hs.timer.delayed.new(0.2, function() M.chooser:refreshChoicesCallback() end)

-- Show the tab chooser
function M.show()
  M.chooser:show()
end
-- M.chooser:searchSubText(true)

return M
