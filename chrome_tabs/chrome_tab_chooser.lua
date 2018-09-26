local M = {}

local fuzzy_match = require 'utilities.fuzzy.fuzzy_match'

local function choices_fn()
  local query = M.chooser:query()
  local query_length = query:len()
  local query_is_lowercase = query == query:lower()

  local choices, choice, ii = {}, {}, 0
  for _,chromeWindow in pairs(chrome_tabs.chromeWindows) do
    for _,chromeTab in pairs(chromeWindow.chromeTabs) do
      ii = ii + 1
      choice = {
        text = chromeTab.tabTitle == '' and chromeTab.tabURL or chromeTab.tabTitle,
        subText = (string.gsub(chromeTab.tabURL, '^chrome%-extension.*uri=http', 'http')),
        uuid = ii,
        chromeWindowId = chromeWindow.windowId,
        chromeTabId = chromeTab.tabId,
      }
      if query ~= '' then
        local title_search_text = query_is_lowercase and chromeTab.tabTitle:lower() or chromeTab.tabTitle
        local title_match = fuzzy_match.fuzzyMatch(title_search_text, query)
        local url_search_text = query_is_lowercase and chromeTab.tabURL:lower() or chromeTab.tabURL
        local url_match = fuzzy_match.fuzzyMatch(url_search_text, query)
        choice._match = {}
        choice._match.title = title_match
        choice._match.url = url_match
        choice._match.best = title_match.score >= url_match.score and title_match or url_match
        if choice._match.best.score > 0 then
          choices[#choices+1] = choice
        end
      else
        choices[#choices+1] = choice
      end
    end
  end

  if query ~= '' then
    table.sort(choices, function(a,b) return a._match.best.score > b._match.best.score end)
  end
  return choices
end
M._choices_fn = choices_fn

local function completion_fn(choice)
  if choice == nil then return nil end

  local chromeWindow = chrome_tabs.chromeWindows[choice.chromeWindowId]
  local chromeTab = chromeWindow.chromeTabs[choice.chromeTabId]
  chromeTab:focus()
end
M._completion_fn = completion_fn


M.chooser = hs.chooser.new(completion_fn)
M.chooser:choices(choices_fn)
M.chooser:queryChangedCallback(function(query) M.timer:start() end)
M.timer = hs.timer.delayed.new(0.2, function() M.chooser:refreshChoicesCallback() end)
-- M.chooser:searchSubText(true)

return M
