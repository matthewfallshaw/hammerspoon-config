describe('hs.base64', function()
  it('matches known vectors', function()
    assert.are.equal('', hs.base64.encode(''))
    assert.are.equal('Zg==', hs.base64.encode('f'))
    assert.are.equal('Zm8=', hs.base64.encode('fo'))
    assert.are.equal('Zm9v', hs.base64.encode('foo'))
    assert.are.equal('Zm9vYg==', hs.base64.encode('foob'))
    assert.are.equal('Zm9vYmE=', hs.base64.encode('fooba'))
    assert.are.equal('Zm9vYmFy', hs.base64.encode('foobar'))
  end)

  it('round-trips a string with quotes, backslashes, ]], newline, em-dash and emoji', function()
    local original = "it's \"quoted\", a\\backslash, ]] closer,\na newline, an em-dash — and an emoji 🎉"
    local encoded = hs.base64.encode(original)
    local decoded = hs.base64.decode(encoded)
    assert.are.equal(original, decoded)
    assert.are.equal(#original, #decoded)
  end)

  it('round-trips arbitrary binary bytes including nulls', function()
    local bytes = {}
    for i = 0, 255 do
      table.insert(bytes, string.char(i))
    end
    local original = table.concat(bytes)
    local decoded = hs.base64.decode(hs.base64.encode(original))
    assert.are.equal(original, decoded)
  end)
end)

describe('hs.canvas', function()
  before_each(function()
    hs.canvas._reset()
  end)

  it('records instances and geometry', function()
    local c = hs.canvas.new({ x = 1, y = 2, w = 3, h = 4 })
    assert.are.equal(1, #hs.canvas._instances)
    assert.are.same({ x = 1, y = 2, w = 3, h = 4 }, c:frame())

    c:frame({ x = 10, y = 20, w = 30, h = 40 })
    assert.are.same({ x = 10, y = 20, w = 30, h = 40 }, c:frame())
    assert.are.same({ x = 10, y = 20, w = 30, h = 40 }, c._frame)
  end)

  it('records appended and indexed elements', function()
    local c = hs.canvas.new({ x = 0, y = 0, w = 100, h = 100 })
    c:appendElements({ type = 'rectangle' }, { type = 'text', text = 'hi' })
    assert.are.equal(2, #c._elements)
    assert.are.equal('rectangle', c[1].type)
    assert.are.equal('hi', c[2].text)

    c[1].fillColor = { red = 1 }
    assert.are.equal(1, c._elements[1].fillColor.red)
  end)

  it('records show/hide/delete calls and visibility state', function()
    local c = hs.canvas.new({ x = 0, y = 0, w = 10, h = 10 })
    c:show(0.2)
    assert.is_true(c._visible)
    c:hide(0.1)
    assert.is_false(c._visible)
    c:delete()
    assert.is_true(c._deleted)

    assert.are.equal('show', c._calls[1].name)
    assert.are.equal(0.2, c._calls[1].args[1])
    assert.are.equal('hide', c._calls[2].name)
    assert.are.equal('delete', c._calls[3].name)
  end)

  it('stores the mouse callback and supports chaining', function()
    local c = hs.canvas.new({ x = 0, y = 0, w = 10, h = 10 })
    local called = false
    local fn = function() called = true end
    local result = c:mouseCallback(fn):level(hs.canvas.windowLevels.overlay):show()
    assert.are.equal(c, result)
    assert.are.equal(fn, c._mouseCallback)
    c._mouseCallback()
    assert.is_true(called)
    assert.are.equal(hs.canvas.windowLevels.overlay, c._level)
  end)
end)

describe('hs.timer.doAfter', function()
  before_each(function()
    hs.timer._reset()
  end)

  it('records created timers', function()
    local fn = function() end
    local t = hs.timer.doAfter(5, fn)
    assert.are.equal(1, #hs.timer._timers)
    assert.are.equal(5, hs.timer._timers[1].seconds)
    assert.are.equal(fn, hs.timer._timers[1].fn)
    assert.is_false(hs.timer._timers[1].stopped)

    t:stop()
    assert.is_true(t.stopped)
    assert.is_false(t:running())
  end)

  it('secondsSinceEpoch is settable and deterministic', function()
    hs.timer._now = 1000
    assert.are.equal(1000, hs.timer.secondsSinceEpoch())
    hs.timer._now = 2000
    assert.are.equal(2000, hs.timer.secondsSinceEpoch())
  end)
end)

describe('hs.settings', function()
  before_each(function()
    hs.settings._reset()
  end)

  it('round-trips values', function()
    hs.settings.set('foo', 'bar')
    assert.are.equal('bar', hs.settings.get('foo'))
  end)

  it('clear removes a key', function()
    hs.settings.set('foo', 'bar')
    hs.settings.clear('foo')
    assert.is_nil(hs.settings.get('foo'))
  end)

  it('getKeys lists stored keys', function()
    hs.settings.set('a', 1)
    hs.settings.set('b', 2)
    local keys = hs.settings.getKeys()
    table.sort(keys)
    assert.are.same({ 'a', 'b' }, keys)
  end)
end)
