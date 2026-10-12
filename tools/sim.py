#!/usr/bin/env python
"""Headless rotation simulator for PRIO.

Loads the real Engine.lua and spec files under the test harness's mocked WoW API,
then runs tools/sim.lua, which drives Engine:Evaluate() through a modelled fight and
reports how the shipped priority list behaves (uptimes, combo-point waste, energy
stalls, and casts/min against the reference Mythic+ logs).

    python tools/sim.py
"""
import os
import sys

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit("lupa is required: python -m pip install lupa")

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS_DIR = os.path.join(ADDON_DIR, "tests")
TOOLS_DIR = os.path.join(ADDON_DIR, "tools")

lua = LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.ADDON_DIR = ADDON_DIR
g.TESTS_DIR = TESTS_DIR

loadfile = lua.eval("function(p) return assert(loadfile(p)) end")
try:
    loadfile(os.path.join(TOOLS_DIR, "sim.lua"))()
except Exception as e:  # noqa: BLE001
    print("Lua error while running the simulation:\n", e)
    sys.exit(2)
