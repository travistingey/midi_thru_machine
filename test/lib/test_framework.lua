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

-- Simple assertion functions
local test_assert = {
  is_true = function(value, message)
    if not value then
      error(message or "expected true, got " .. tostring(value))
    end
  end,
  
  is_false = function(value, message)
    if value then
      error(message or "expected false, got " .. tostring(value))
    end
  end,
  
  are_equal = function(expected, actual, message)
    if expected ~= actual then
      error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
    end
  end,
  
  is_table = function(value, message)
    if type(value) ~= "table" then
      error(message or "expected table, got " .. type(value))
    end
  end,
  
  is_number = function(value, message)
    if type(value) ~= "number" then
      error(message or "expected number, got " .. type(value))
    end
  end,
  
  is_nil = function(value, message)
    if value ~= nil then
      error(message or "expected nil, got " .. tostring(value))
    end
  end,
  
  are = {
    same = function(expected, actual, message)
      if type(expected) ~= type(actual) then
        error(message or ("expected " .. type(expected) .. ", got " .. type(actual)))
      end
      if type(expected) == "table" then
        for k, v in pairs(expected) do
          if actual[k] ~= v then
            error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
          end
        end
        for k, v in pairs(actual) do
          if expected[k] ~= v then
            error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
          end
        end
      elseif expected ~= actual then
        error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
      end
    end,
    
    equal = function(expected, actual, message)
      if expected ~= actual then
        error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
      end
    end
  },
  
  is_equal = function(expected, actual, message)
    if expected ~= actual then
      error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
    end
  end
}

return {
  describe = TestFramework.describe,
  it = TestFramework.it,
  before_each = TestFramework.before_each,
  after_each = TestFramework.after_each,
  add_cleanup = TestFramework.add_cleanup,
  assert = test_assert,
  get_stats = function()
    return {
      passed = TestFramework.passed,
      failed = TestFramework.failed,
      total = TestFramework.passed + TestFramework.failed
    }
  end
} 