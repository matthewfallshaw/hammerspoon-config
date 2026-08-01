-- Exercises bin/notify end-to-end as a real subprocess, without a live
-- Hammerspoon: `hs`, `pgrep` and `osascript` are all stubbed by fake
-- executables dropped into a per-test temp dir, so nothing here ever
-- reaches the real Hammerspoon instance or draws a real notification.

-- POSIX single-quote a string for safe embedding in a shell command line --
-- handles any byte sequence (quotes, backslashes, newlines, emoji) losslessly.
local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Real base64 codec: prefer spec_helper's hs.base64 (another module's spec
-- mocks add it); fall back to shelling out to `base64`/`base64 -d` if it's
-- ever absent, so this spec doesn't depend on load order.
local function b64_encode(s)
  if _G.hs and _G.hs.base64 and _G.hs.base64.encode then
    return _G.hs.base64.encode(s)
  end
  local tmp = os.tmpname()
  local f = assert(io.open(tmp, "wb"))
  f:write(s)
  f:close()
  local p = io.popen("base64 < " .. shell_quote(tmp))
  local out = p:read("*a")
  p:close()
  os.remove(tmp)
  return (out:gsub("%s+", ""))
end

local function b64_decode(s)
  if _G.hs and _G.hs.base64 and _G.hs.base64.decode then
    return _G.hs.base64.decode(s)
  end
  local p = io.popen("printf '%s' " .. shell_quote(s) .. " | base64 -d")
  local out = p:read("*a")
  p:close()
  return out
end

-- Locate bin/notify relative to this spec file, not to busted's cwd.
local spec_source = debug.getinfo(1, "S").source:sub(2)
local spec_dir = spec_source:match("^(.*)/[^/]+$")
local pwd_handle = io.popen("cd " .. shell_quote(spec_dir .. "/..") .. " && pwd")
local build_dir = pwd_handle:read("*l")
pwd_handle:close()
local notify_bin = build_dir .. "/bin/notify"

local function write_file(path, content, executable)
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
  if executable then
    os.execute("chmod +x " .. shell_quote(path))
  end
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return "" end
  local c = f:read("*a")
  f:close()
  return c
end

-- Sets up fake hs/pgrep/osascript in a temp dir, runs bin/notify with
-- `args`, and returns { code, stdout, stderr, hs_log, osa_log, dir }.
-- hs_log is what the fake `hs` was invoked with (its -c argument, one line
-- per invocation); osa_log records fake osascript invocations. Neither
-- fake ever touches the real Hammerspoon or draws a real notification.
local function run_notify(args, opts)
  opts = opts or {}
  local pgrep_ok = opts.pgrep_ok
  if pgrep_ok == nil then pgrep_ok = true end

  local dir = io.popen("mktemp -d"):read("*l")

  write_file(dir .. "/hs", "#!/bin/sh\necho \"$2\" >> " .. shell_quote(dir .. "/hs.log") .. "\n", true)
  write_file(dir .. "/pgrep", "#!/bin/sh\nexit " .. (pgrep_ok and "0" or "1") .. "\n", true)
  write_file(dir .. "/osascript",
    "#!/bin/sh\necho \"OSASCRIPT $*\" >> " .. shell_quote(dir .. "/osa.log") .. "\n", true)
  write_file(dir .. "/hs.log", "", false)
  write_file(dir .. "/osa.log", "", false)

  local quoted_args = {}
  for _, a in ipairs(args) do
    table.insert(quoted_args, shell_quote(a))
  end

  -- Prepend the fake dir so bare `pgrep` finds the fake first; keep the
  -- real PATH after it so bin/notify's own use of base64/sed/printf still
  -- resolves to real system tools.
  local path_env = dir .. ":" .. (os.getenv("PATH") or "")

  local cmd = "HS_BIN=" .. shell_quote(dir .. "/hs")
    .. " OSASCRIPT_BIN=" .. shell_quote(dir .. "/osascript")
    .. " PATH=" .. shell_quote(path_env)
    .. " " .. shell_quote(notify_bin)
    .. " " .. table.concat(quoted_args, " ")
    .. " >" .. shell_quote(dir .. "/stdout")
    .. " 2>" .. shell_quote(dir .. "/stderr")
    .. "; echo EXIT:$?"

  local p = io.popen(cmd)
  local out = p:read("*a")
  p:close()
  local code = tonumber(out:match("EXIT:(%d+)"))

  -- bin/notify fires hs/osascript in the background and returns
  -- immediately, so the fake's log write can trail behind this process by
  -- an unpredictable amount (observed: sometimes >1s under load). Poll for
  -- up to 3s rather than a fixed sleep, so this isn't flaky under load but
  -- also isn't needlessly slow when the write lands fast -- or, for tests
  -- that expect NO invocation, still gives a real chance for a spurious
  -- one to show up before we conclude the log is empty.
  for _ = 1, 30 do
    if slurp(dir .. "/hs.log") ~= "" or slurp(dir .. "/osa.log") ~= "" then break end
    os.execute("sleep 0.1")
  end

  local result = {
    code = code,
    stdout = slurp(dir .. "/stdout"),
    stderr = slurp(dir .. "/stderr"),
    hs_log = (slurp(dir .. "/hs.log"):gsub("\n$", "")),
    osa_log = slurp(dir .. "/osa.log"),
    dir = dir,
  }

  os.execute("rm -rf " .. shell_quote(dir))

  return result
end

describe("bin/notify", function()
  it("emits the exact expected Lua shape for a default invocation", function()
    local expected = "require('notify').show({ message = hs.base64.decode('"
      .. b64_encode("hello") .. "'), title = hs.base64.decode('"
      .. b64_encode("Notice") .. "'), sticky = false, duration = 5, private = false })"

    local result = run_notify({ "hello" })

    assert.are.equal(0, result.code)
    assert.are.equal(expected, result.hs_log)
  end)

  it("round-trips tricky characters through base64 byte-for-byte", function()
    local tricky = "it's \"quoted\" and ]] .. os.exit() .. [[ \\\nem\226\128\148dash \240\159\142\137"
    -- \226\128\148 = em dash (U+2014), \240\159\142\137 = 🎉 (U+1F389), as raw UTF-8 bytes.

    local result = run_notify({ tricky })

    assert.are.equal(0, result.code)
    local b64 = result.hs_log:match("message = hs%.base64%.decode%('([^']*)'%)")
    assert.is_not_nil(b64)
    assert.are.equal(tricky, b64_decode(b64))
  end)

  it("--sticky emits sticky = true", function()
    local result = run_notify({ "--sticky", "msg" })
    assert.is_not_nil(result.hs_log:find("sticky = true", 1, true))
  end)

  it("--duration 12 emits duration = 12", function()
    local result = run_notify({ "--duration", "12", "msg" })
    assert.is_not_nil(result.hs_log:find("duration = 12", 1, true))
  end)

  it("--sticky --duration 12 emits sticky = true with duration present (irrelevant but there)", function()
    local result = run_notify({ "--sticky", "--duration", "12", "msg" })
    assert.is_not_nil(result.hs_log:find("sticky = true", 1, true))
    assert.is_not_nil(result.hs_log:find("duration = 12", 1, true))
  end)

  it("--title overrides the default title", function()
    local result = run_notify({ "--title", "Custom Title", "msg" })
    local b64 = result.hs_log:match("title = hs%.base64%.decode%('([^']*)'%)")
    assert.are.equal("Custom Title", b64_decode(b64))
  end)

  it("omits icon and id keys when not supplied", function()
    local result = run_notify({ "msg" })
    assert.is_nil(result.hs_log:match("icon = "))
    assert.is_nil(result.hs_log:match("id = "))
  end)

  it("--icon and --id appear, correctly encoded, when supplied", function()
    local result = run_notify({ "--icon", "/tmp/some icon.png", "--id", "myid", "msg" })
    local icon_b64 = result.hs_log:match("icon = hs%.base64%.decode%('([^']*)'%)")
    local id_b64 = result.hs_log:match("id = hs%.base64%.decode%('([^']*)'%)")
    assert.are.equal("/tmp/some icon.png", b64_decode(icon_b64))
    assert.are.equal("myid", b64_decode(id_b64))
  end)

  it("private defaults to false and --private sets it true", function()
    local default_result = run_notify({ "msg" })
    assert.is_not_nil(default_result.hs_log:find("private = false", 1, true))

    local result = run_notify({ "--private", "msg" })
    assert.is_not_nil(result.hs_log:find("private = true", 1, true))
  end)

  it("joins multiple positional args with single spaces", function()
    local result = run_notify({ "hello", "world", "foo" })
    local b64 = result.hs_log:match("message = hs%.base64%.decode%('([^']*)'%)")
    assert.are.equal("hello world foo", b64_decode(b64))
  end)

  it("-- lets a message begin with a dash", function()
    local result = run_notify({ "--title", "T", "--", "-starts-with-dash" })
    assert.are.equal(0, result.code)
    local b64 = result.hs_log:match("message = hs%.base64%.decode%('([^']*)'%)")
    assert.are.equal("-starts-with-dash", b64_decode(b64))
  end)

  it("rejects an unknown option before -- with exit 2", function()
    local result = run_notify({ "--nonsense", "msg" })
    assert.are.equal(2, result.code)
    assert.are.equal("", result.hs_log)
  end)

  it("rejects an invalid --duration with exit 2", function()
    local result = run_notify({ "--duration", "abc", "msg" })
    assert.are.equal(2, result.code)
    assert.are.equal("", result.hs_log)
  end)

  describe("--duration validation", function()
    local invalid = { "1.2.3", ".", "..", "-1", "abc" }
    for _, value in ipairs(invalid) do
      it("rejects '" .. value .. "' with exit 2", function()
        local result = run_notify({ "--duration", value, "msg" })
        assert.are.equal(2, result.code)
        assert.are.equal("", result.hs_log)
      end)
    end

    local valid = { "0", "5", "0.5", ".5", "12." }
    for _, value in ipairs(valid) do
      it("accepts '" .. value .. "'", function()
        local result = run_notify({ "--duration", value, "msg" })
        assert.are.equal(0, result.code)
        assert.is_not_nil(result.hs_log:find("duration = " .. value, 1, true))
      end)
    end
  end)

  it("does not invoke hs when pgrep fails, and still exits 0", function()
    local result = run_notify({ "msg" }, { pgrep_ok = false })
    assert.are.equal(0, result.code)
    assert.are.equal("", result.hs_log)
    -- Confirms the osascript fallback (stubbed, never real) is what fired.
    assert.is_not_nil(result.osa_log:find("OSASCRIPT", 1, true))
  end)
end)
