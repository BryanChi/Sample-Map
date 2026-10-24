-- plain-Lua runner: lua5.4 run_signals.lua <out dir>
local dir = arg[1] or '.'
local here = arg[0]:match('^(.*)/') or '.'
local S = dofile(here .. '/Bloom Study Signals.lua')
local t = os.clock()
local list = S.WriteAll(dir, function(n) io.write(n, ' ') io.flush() end)
print(('\n%d signals in %.1f s'):format(#list, os.clock() - t))
