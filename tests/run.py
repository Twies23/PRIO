#!/usr/bin/env python
"""Headless test runner for the PRIO engine.

Loads the real Engine.lua / Spec_Windwalker.lua under a mocked WoW API (via lupa's
embedded Lua) and runs the Lua test suite. Exit code 0 = all passed, 1 = failures.

    python tests/run.py
"""
import os
import sys

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit("lupa is required: python -m pip install lupa")

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS_DIR = os.path.join(ADDON_DIR, "tests")

lua = LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.ADDON_DIR = ADDON_DIR
g.TESTS_DIR = TESTS_DIR

main = os.path.join(TESTS_DIR, "main.lua")
loadfile = lua.eval("function(p) return assert(loadfile(p)) end")
try:
    loadfile(main)()
except Exception as e:  # noqa: BLE001
    print("Lua error while running tests:\n", e)
    sys.exit(2)

failures = g.__TEST_FAILURES or 0
sys.exit(1 if failures and failures > 0 else 0)
