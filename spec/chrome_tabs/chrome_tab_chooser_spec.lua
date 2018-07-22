require 'spec.spec_helper'

_G.chrome_tabs = require('chrome_tabs')

describe("chrome_tab_chooser", function()
  chrome_tabs.chooser = require('chrome_tabs.chrome_tab_chooser')

  fixture = {
    choices = {
      { text = 'Original window: Tab One',
        subText = 'http://example.org/tab_one/index.html',
        uuid = 1,
        chromeWindowId = 1001,
        chromeTabId = 101,
      },
      { text = 'Original window: Tab Two',
        subText = 'http://example.org/tab_two/index.html',
        uuid = 2,
        chromeWindowId = 1001,
        chromeTabId = 102,
      },
      { text = 'Original window: Tab Three',
        subText = 'http://example.org/tab_three/index.html',
        uuid = 3,
        chromeWindowId = 1001,
        chromeTabId = 103,
      },
    },
    chrome_window_applescript = {
      windowId = 1001,
      windowIndex = 1,
      activeTabIndex = 2,
      windowTabs = {
        { tabId = 101,
          windowId = 1001,
          tabIndex = 1,
          tabTitle = "Original window: Tab One",
          tabURL = "http://example.org/tab_one/index.html" },
        { tabId = 102,
          windowId = 1001,
          tabIndex = 2,
          tabTitle = "Original window: Tab Two",
          tabURL = "http://example.org/tab_two/index.html" },
        { tabId = 103,
          windowId = 1001,
          tabIndex = 3,
          tabTitle = "Original window: Tab Three",
          tabURL = "http://example.org/tab_three/index.html" },
      },
    },
  }

  describe("choices_fn", function()
    setup(function()
      ChromeWindow:createOrUpdate(fixture.chrome_window_applescript)
    end)
  
    describe("with no query", function()
      it("should return our choices fixture", function()
        assert.same(
          fixture.choices,
          chrome_tabs.chooser._choices_fn()
        )
      end)
    end)
    describe("with a query", function()
      it("should return our choices fixture, sorted appropriately", function()
        chrome_tabs.chooser.chooser.query = function() return "two" end
        assert.same(
          {fixture.choices[2]},
          chrome_tabs.chooser._choices_fn()
        )
      end)
    end)
  end)
  describe("completion_fn(choice)", function()
    it("should focus the chosen tab", function()
      local s = spy.new(function() end)
      chrome_tabs.chromeWindows = {[1] = {chromeTabs = {[1] = {focus = s}}}}

      chrome_tabs.chooser._completion_fn({chromeWindowId = 1, chromeTabId = 1})
      assert.spy(s).was.called()
    end)
  end)

end)
