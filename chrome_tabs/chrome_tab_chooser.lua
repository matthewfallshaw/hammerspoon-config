-- local MAX_CHOOSER_OPTIONS = 10

local M = {}

local fuzzy_match = require 'utilities.fuzzy.fuzzy_match'

local function choices_fn()
  local query = M.chooser:query()
  local query_length = query:len()
  local is_lower = query == query:lower()

  local choices, search_choices, ii = {}, {}, 0
  for _,chromeWindow in pairs(chrome_tabs.chromeWindows) do
    for _,chromeTab in pairs(chromeWindow.chromeTabs) do
      ii = ii + 1
      choices[#choices+1] = {
          text = chromeTab.tabTitle == '' and chromeTab.tabURL or chromeTab.tabTitle,
          subText = (string.gsub(chromeTab.tabURL, '^chrome%-extension.*uri=http', 'http')),
          uuid = ii,
          chromeWindowId = chromeWindow.windowId,
          chromeTabId = chromeTab.tabId,
        }
      search_choices[#search_choices+1] = {
        uuid = ii,
        search_text = is_lower and chromeTab.tabTitle:lower() or chromeTab.tabTitle,
      }
      search_choices[#search_choices+1] = {
        uuid = ii,
        search_text = is_lower and chromeTab.tabURL:lower() or chromeTab.tabURL,
      }
    end
  end

  if query ~= '' then
    local sort_key = fuzzy_match.fuzzySort(search_choices, 'search_text', query)
    local sorted, taken = {}, {}
    local ii = 0
    for k,v in ipairs(sort_key) do
      ii = ii + 1
      -- if ii > MAX_CHOOSER_OPTIONS then break end
      if (not taken[v.uuid]) and (not (v._score == 0)) then
        sorted[#sorted+1] = choices[v.uuid]
        taken[v.uuid] = true
      end
    end
    return sorted
  else
    return choices
  end
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
