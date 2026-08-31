-- main.lua --------------------------------------------------------------------
-- Test entrypoint: loads the harness + a tiny assert framework, runs every test
-- file, prints a summary, and sets _G.__TEST_FAILURES for the Python runner.
-- ADDON_DIR / TESTS_DIR are injected by run.py.
--------------------------------------------------------------------------------

dofile(TESTS_DIR .. "\\harness.lua")

local pass, fail = 0, 0
local fails = {}

function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1
    else fail = fail + 1; fails[#fails + 1] = name .. "  ->  " .. tostring(err) end
end

local function fmt(v) return type(v) == "string" and ("\"" .. v .. "\"") or tostring(v) end

function eq(a, b, msg)
    if a ~= b then error((msg or "eq") .. ": expected " .. fmt(b) .. ", got " .. fmt(a), 2) end
end
function truthy(v, msg) if not v then error((msg or "expected truthy") .. ", got " .. fmt(v), 2) end end
function falsy(v, msg) if v then error((msg or "expected falsy") .. ", got " .. fmt(v), 2) end end

-- Convenience: evaluate a single clause against the current state.
function evalClause(cl) return H.Cond.EvalClause(cl, H.Engine:CurrentState(), nil) end

-- Test files.
dofile(TESTS_DIR .. "\\test_conditions.lua")
dofile(TESTS_DIR .. "\\test_hero.lua")
dofile(TESTS_DIR .. "\\test_arms_hero.lua")
dofile(TESTS_DIR .. "\\test_arms_stacks.lua")
dofile(TESTS_DIR .. "\\test_outlaw_stage.lua")
dofile(TESTS_DIR .. "\\test_outlaw_opportunity.lua")
dofile(TESTS_DIR .. "\\test_outlaw_supercharge.lua")
dofile(TESTS_DIR .. "\\test_queue.lua")
dofile(TESTS_DIR .. "\\test_devourer_cdreset.lua")
dofile(TESTS_DIR .. "\\test_devourer_souls.lua")
dofile(TESTS_DIR .. "\\test_devourer_meta.lua")
dofile(TESTS_DIR .. "\\test_bm.lua")
dofile(TESTS_DIR .. "\\test_mm.lua")

print(string.format("\n=== PRIO tests: %d passed, %d failed ===", pass, fail))
for _, f in ipairs(fails) do print("  FAIL  " .. f) end
_G.__TEST_FAILURES = fail
