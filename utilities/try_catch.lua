local help = [[
-- That didn't work. Are you doing something like this?
require "try_catch"
try {
  function()
    -- Do your thing here
    error('oops')
    -- Code after an error never executed
  end,
  catch {  -- optional
    function(error)
      print('caught error: ' .. error)
    end
  },
  ensure {  -- optional
    function()
      -- This will always run (with any return value ignored)
    end
  }
}
]]

function catch(what)
  assert(type(what) == 'table' and type(what[1]) == 'function', help)

  return {'catch', what[1]}
end
function ensure(what)
  assert(type(what) == 'table' and type(what[1]) == 'function', help)

  return {'ensure', what[1]}
end

function try(what)
  assert(type(what) == 'table' and type(what[1]) == 'function', help)
  local lcatch, lensure
  if what[2] then
    assert(type(what[2]) == 'table' and
        (what[2][1] == 'catch' or what[2][1] == 'ensure') and
        type(what[2][2]) == 'function', help)
    if what[2][1] == 'catch' then
      lcatch = what[2][2]
      if what[3] then
        assert(type(what[3]) == 'table' and
            what[3][1] == 'ensure' and type(what[3][2]) == 'function', help)
        lensure = what[3][2]
      end
    else
      lensure = what[2][2]
    end
  end

  local status, result = pcall(what[1])

  if not status and lcatch then
    result = lcatch(result)
  end

  if lensure then
    lensure()
  end

  return result
end

local module = {
  try = try,
  catch = catch,
  ensure = ensure,
}

return module