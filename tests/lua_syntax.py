"""Syntax-check Lua files with Lua 5.4's load() (via lupa). usage: lua_syntax.py FILE..."""
import sys
from lupa import lua54

L = lua54.LuaRuntime()
check = L.eval('function(src, name) local _, err = load(src, "@" .. name, "t") return err end')
failed = 0
for path in sys.argv[1:]:
    with open(path, "rb") as fh:
        err = check(fh.read(), path)
    if err:
        print("FAIL", err)
        failed += 1
sys.exit(1 if failed else 0)
