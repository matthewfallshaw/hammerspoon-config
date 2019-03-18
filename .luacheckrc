stds.hammerspoon = {
  globals = {
    spoon = { other_fields = true },
    hs = { other_fields = true },
  },
}
std = 'max+hammerspoon'
-- ignore = { '111', '112' }

files["/Applications/Hammerspoon.app/Contents/Resources/extensions/hs/**/*"].read_globals = { 'hs', 'spoon' }

-- vim: set filetype=lua:
