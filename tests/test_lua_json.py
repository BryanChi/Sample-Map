"""Round-trip tests for the browser's JSON encoder/decoder (browser/03_json.lua)."""
import os

from lupa import lua54

ROOT = os.path.join(os.path.dirname(__file__), "..")


def _runtime():
    L = lua54.LuaRuntime()
    L.execute("reaper = setmetatable({}, {__index = function() return function() end end})")
    L.execute("log = function() end")
    with open(os.path.join(ROOT, "browser", "03_json.lua"), "rb") as fh:
        L.execute(fh.read())
    return L


def test_decode_tricky_strings_and_nulls():
    L = _runtime()
    check = L.eval(r'''function(src)
      local t = json_decode(src)
      return t.a, t.b, t.c, t.list[1], t.list[2], t.list[3], t.u
    end''')
    a, b, c, l1, l2, l3, u = check(r'{"a": "Kick ]}", "b": "C:\\path\\", "c": "x\\ny", '
                                   r'"list": [1, null, 3], "u": "\u00e9\ud83d\ude00"}')
    assert a == "Kick ]}"
    assert b == "C:\\path\\"
    assert c == "x\\ny"
    assert (l1, l2, l3) == (1, None, 3)
    assert u == "é😀"


def test_decode_rejects_truncated_input():
    L = _runtime()
    decode = L.eval('function(s) local t, err = json_decode(s) return t == nil, err ~= nil end')
    assert tuple(decode('{"folders": ["a", "b"')) == (True, True)
    assert tuple(decode('{"a": 1} trailing')) == (True, True)


def test_round_trip():
    L = _runtime()
    rt = L.eval(r'''function()
      local src = { name = 'q"uote\\back\nline', n = 1.5, flag = true, list = { "x", "y" } }
      local t = json_decode(json_encode(src))
      return t.name == src.name and t.n == 1.5 and t.flag == true and t.list[2] == "y"
    end''')
    assert rt()
