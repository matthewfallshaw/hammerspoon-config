-- Assertions

expect = {}

function expect.argument_to_be_in_table(argument, to_be_in)
  assert( hs.fnutils.contains(to_be_in, argument),
    'Expected "'.. hs.inspect(argument) ..'" to be one of '.. hs.inspect(to_be_in)
  )
end
function expect.argument_to_be_in_table_or_nil(argument, to_be_in)
  assert( hs.fnutils.contains(to_be_in, argument) or argument == nil,
    'Expected "'.. hs.inspect(argument) ..'" to be one of '.. hs.inspect(to_be_in)
  )
end
function expect.truthy(argument, expression)
  assert( argument,
    'Expected truthyness from '.. hs.inspect(expression)
  )
end
function expect.file_to_exist(filepath, source)
  if not fileExists(filepath) then
    error("I can't find ".. filepath .." which I need to function. Install `"..
    source .."` there.")
  end
end

-- Private
local function fileExists(filepath)
  return hs.fs.attributes(filepath, 'mode') == 'file'
end

return expect
