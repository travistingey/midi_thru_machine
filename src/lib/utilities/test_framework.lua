-- test_framework.lua - Simple test framework for Norns
-- Import this in your test files: local tf = require('lib/test_framework')

local TestFramework = {
  tests = {},
  passed = 0,
  failed = 0,
  current_suite = nil,
  before_each_fn = nil,
  after_each_fn = nil,
  cleanup_fns = {}
}

function TestFramework.describe(name, fn)
  TestFramework.current_suite = name
  print("📋 " .. name)
  fn()
  TestFramework.current_suite = nil
end

function TestFramework.before_each(fn)
  TestFramework.before_each_fn = fn
end

function TestFramework.after_each(fn)
  TestFramework.after_each_fn = fn
end

function TestFramework.add_cleanup(fn)
  table.insert(TestFramework.cleanup_fns, fn)
end

function TestFramework.it(name, fn)
  -- Run before_each if set
  if TestFramework.before_each_fn then
    TestFramework.before_each_fn()
  end
  
  local status, err = pcall(fn)
  if status then
    print("  ✅ " .. name)
    TestFramework.passed = TestFramework.passed + 1
  else
    print("  ❌ " .. name .. " - " .. tostring(err))
    TestFramework.failed = TestFramework.failed + 1
  end
  
  -- Run after_each if set
  if TestFramework.after_each_fn then
    TestFramework.after_each_fn()
  end
  
  -- Run any cleanup functions
  for _, cleanup_fn in ipairs(TestFramework.cleanup_fns) do
    local ok, cleanup_err = pcall(cleanup_fn)
    if not ok then
      print("  ⚠️  Cleanup error: " .. tostring(cleanup_err))
    end
  end
  TestFramework.cleanup_fns = {}
end

-- ---------------------------------------------------------------------------
-- Simple, unified assertion library
-- ---------------------------------------------------------------------------
--  • Core primitives live in table `core`
--  • `assert` is the single public table exposing every core primitive.
--  • Added helpers: deep_equal, near, throws
-- ---------------------------------------------------------------------------

local core = {}

local function fmt(a, b)
  return string.format("expected %s, got %s", tostring(a), tostring(b))
end

-- Strict equality
function core.equal(expected, actual, message)
  if expected ~= actual then
    error(message or fmt(expected, actual))
  end
end

-- Recursive table equivalence
function core.deep_equal(expected, actual, message, visited)
  visited = visited or {}
  if expected == actual then return true end
  if type(expected) ~= "table" or type(actual) ~= "table" then
    error(message or fmt(expected, actual))
  end
  if visited[expected] and visited[expected] == actual then return true end
  visited[expected] = actual
  for k, v in pairs(expected) do
    if not core.deep_equal(v, actual[k], message, visited) then
      error(message or "tables not deeply equal")
    end
  end
  for k in pairs(actual) do
    if expected[k] == nil then
      error(message or "tables not deeply equal")
    end
  end
  return true
end

-- Truthiness
function core.is_true(value, message)
  if not value then error(message or "expected true, got " .. tostring(value)) end
end

function core.is_false(value, message)
  if value then error(message or "expected false, got " .. tostring(value)) end
end

-- Nil checks
function core.is_nil(value, message)
  if value ~= nil then error(message or "expected nil, got " .. tostring(value)) end
end

function core.is_not_nil(value, message)
  if value == nil then error(message or "expected not nil, got nil") end
end

-- Type checks
function core.is_table(value, message)
  if type(value) ~= "table" then error(message or "expected table, got " .. type(value)) end
end

function core.is_number(value, message)
  if type(value) ~= "number" then error(message or "expected number, got " .. type(value)) end
end

-- Numeric proximity
function core.near(actual, expected, delta, message)
  delta = delta or 1e-6
  if math.abs(actual - expected) > delta then
    error(message or string.format("expected %s to be within %s of %s", tostring(actual), delta, tostring(expected)))
  end
end

-- Expect function to throw (optionally match pattern)
function core.throws(fn, pattern, message)
  local ok, err = pcall(fn)
  if ok then
    error(message or "expected error, none thrown")
  end
  if pattern and not tostring(err):match(pattern) then
    error(message or ("error message does not match pattern '" .. pattern .. "': " .. tostring(err)))
  end
end

-- ---------------------------------------------------------------------------
-- Public assert table (single entry‑point, no grammar sugar)
-- ---------------------------------------------------------------------------
local proxy_mt = { __index = core }

-- Single entry‑point.  No fancy grammar sugar (`are.equal`, `is.true`, etc.)
-- Everything is available directly: assert.equal, assert.deep_equal, assert.near …
local assert = setmetatable({}, proxy_mt)

return {
  describe = TestFramework.describe,
  it = TestFramework.it,
  before_each = TestFramework.before_each,
  after_each = TestFramework.after_each,
  add_cleanup = TestFramework.add_cleanup,
  assert = assert,
  get_stats = function()
    return {
      passed = TestFramework.passed,
      failed = TestFramework.failed,
      total = TestFramework.passed + TestFramework.failed
    }
  end
}