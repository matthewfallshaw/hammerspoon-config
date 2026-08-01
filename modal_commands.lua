--[=[
Notes:
- Use caps lock as hyper (via Karabiner-Elements)
]=]--

local Modal = {
  -- Registry of all created categories
  categories = {}
}

-- Category constructor
function Modal.createCategory(mods, key, name, description)
  local category = {
      name = name,
      description = description,
      commands = {},
      modal = hs.hotkey.modal.new(mods, key)
  }

  -- Ordered list of preferred default keys by ergonomic reach
  local defaultKeys = {
      -- Home row (left to right)
      'a', 's', 'd', 'f', 'j', 'k', 'l', ';',
      -- Upper row
      'q', 'w', 'e', 'r', 'u', 'i', 'o', 'p',
      -- Lower row
      'z', 'x', 'c', 'v', 'n', 'm', ',', '.',
      -- Numbers (if we somehow need more)
      '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'
  }

  -- Store in our registry
  table.insert(Modal.categories, category)

  -- Set up escape to exit this modal
  category.modal:bind({}, 'escape', function()
      category.modal:exit()
  end)

  -- Show commands when entering modal
  function category.modal:entered()
      local screen = hs.screen.mainScreen():frame()
      local margin = 20
      local cardWidth = 200
      local cardHeight = 80
      local cardsPerRow = math.floor((screen.w - 2 * margin) / (cardWidth + margin))

      -- Create a single canvas for all cards
      category.canvas = hs.canvas.new{
          x = screen.x,
          y = screen.y,
          w = screen.w,
          h = screen.h
      }

      local row = 0
      local col = 0
      for key, cmd in pairs(category.commands) do
          -- Calculate position
          local x = margin + col * (cardWidth + margin)
          local y = margin + row * (cardHeight + margin)

          -- Add card elements to canvas
          category.canvas:appendElements({
              -- Background rounded rect
              {
                  type = "rectangle",
                  action = "fill",
                  fillColor = { red = 0.2, green = 0.2, blue = 0.2, alpha = 0.9 },
                  strokeColor = { white = 1, alpha = 0.2 },
                  strokeWidth = 1,
                  roundedRectRadii = { xRadius = 10, yRadius = 10 },
                  frame = { x = x, y = y, w = cardWidth, h = cardHeight }
              },
              -- Key (prominent, top right)
              {
                  type = "text",
                  text = key,
                  textFont = "SFMono-Bold",
                  textSize = 20,
                  textColor = { white = 1, alpha = 1 },
                  frame = { x = x + cardWidth - 40, y = y + 10, w = 30, h = 20 }
              },
              -- Short name (left side, bold)
              {
                  type = "text",
                  text = cmd.shortName or "",
                  textFont = "SFMono-Bold",
                  textSize = 14,
                  textColor = { white = 1, alpha = 0.9 },
                  frame = { x = x + 10, y = y + 10, w = cardWidth - 60, h = 20 }
              },
              -- Description (bottom, smaller)
              {
                  type = "text",
                  text = cmd.description,
                  textFont = "SFMono-Regular",
                  textSize = 12,
                  textColor = { white = 1, alpha = 0.7 },
                  frame = { x = x + 10, y = y + 35, w = cardWidth - 20, h = 35 }
              }
          })

          -- Update grid position
          col = col + 1
          if col >= cardsPerRow then
              col = 0
              row = row + 1
          end
      end

      -- Show the canvas and set its behavior
      category.canvas:level(hs.canvas.windowLevels.overlay)
      category.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces +
                             hs.canvas.windowBehaviors.stationary)
      category.canvas:show()
  end

  function category.modal:exited()
      if category.canvas then
          category.canvas:delete()
          category.canvas = nil
      end
  end

  -- Method to add commands to this category
  function category:addCommand(shortName, description, fnOrCategory, key)
      -- If key is explicitly provided, verify it's not already in use
      if key and self.commands[key] then
          error(string.format("Key '%s' is already bound in category '%s'", key, self.name))
      end

      -- If no key provided, find first available ergonomic key
      if not key then
          for _, defaultKey in ipairs(defaultKeys) do
              if not self.commands[defaultKey] then
                  key = defaultKey
                  break
              end
          end

          if not key then
              error(string.format("No available keys left in category '%s'", self.name))
          end
      end

      if type(fnOrCategory) == "table" and fnOrCategory.modal then
          -- It's a nested category
          self.commands[key] = {
              shortName = shortName,
              description = description,
              isCategory = true
          }

          -- Bind the key to enter the nested category
          self.modal:bind({}, key, function()
              self.modal:exit()  -- exited() will handle alert cleanup
              fnOrCategory.modal:enter()
          end)

          -- Modify the nested category's escape to return to parent
          local originalEscape = fnOrCategory.modal.keys.escape[1]
          fnOrCategory.modal:bind({}, 'escape', function()
              originalEscape.fn()
              self.modal:enter()
          end)
      else
          -- It's a regular command
          self.commands[key] = {
              shortName = shortName,
              description = description,
              fn = fnOrCategory
          }

          self.modal:bind({}, key, function()
              self.modal:exit()  -- exited() will handle alert cleanup
              fnOrCategory()
          end)
      end

      return self
  end

  return category
end

return Modal