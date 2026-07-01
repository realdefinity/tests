local clock, sqrt, ceil, sort, concat, char = os.clock, math.sqrt, math.ceil, table.sort, table.concat, string.char
local wait = task and task.wait or wait
local create = table.create or function(n, v) local t = {} for i = 1, n do t[i] = v end return t end

local SAMPLES, WARMUP, YIELDS = 64, 8, 24
local sink = 0

local function fmt(s)
	if s >= 1 then return ("%.3fs"):format(s) end
	if s >= 1e-3 then return ("%.3fms"):format(s * 1e3) end
	if s >= 1e-6 then return ("%.3fus"):format(s * 1e6) end
	return ("%.3fns"):format(s * 1e9)
end

local function executor()
	local ok, name, ver = pcall(identifyexecutor or function() end)
	return ok and name and (name .. (ver and " " .. ver or "")) or "Unknown"
end

local function mem()
	local ok, v = pcall(collectgarbage, "count")
	return ok and v / 1024 or 0
end

local function clamp(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

local function stat(a)
	sort(a)
	local n, total = #a, 0
	for i = 1, n do total = total + a[i] end
	local function p(x) return a[clamp(ceil(n * x), 1, n)] end
	return { avg = total / n, min = a[1], max = a[n], p50 = p(0.5), p95 = p(0.95) }
end

local tests = {
	{ name = "Math", label = "Number crunching (loops, sqrt, arithmetic)", inner = 6000, fn = function(n)
		local x = 0
		for i = 1, n do x = x + sqrt(i) + (i % 19) * 0.125 end
		return x
	end },
	{ name = "Tables", label = "Reading and writing table values", inner = 6000, fn = function(n)
		local t, x = create(128, 0), 0
		for i = 1, n do local j = (i % 128) + 1 t[j] = t[j] + i x = x + t[j] end
		return x
	end },
	{ name = "Strings", label = "Building and joining strings", inner = 1200, fn = function(n)
		local t, x = create(48), 0
		for i = 1, 48 do t[i] = char(65 + (i % 26)) end
		for i = 1, n do x = x + #concat(t) end
		return x
	end },
	{ name = "Calls", label = "Calling functions repeatedly", inner = 9000, fn = function(n)
		local x = 0
		local function f(v) return v * 3 - 1 end
		for i = 1, n do x = x + f(i) end
		return x
	end },
	{ name = "Closures", label = "Creating functions that capture outer variables", inner = 4000, fn = function(n)
		local x = 0
		for i = 1, n do
			local captured = i
			local f = function() return captured * 2 end
			x = x + f()
		end
		return x
	end },
	{ name = "Metatables", label = "Indexing through __index / __newindex", inner = 4000, fn = function(n)
		local store = {}
		local proxy = setmetatable({}, {
			__index = function(_, k) return store[k] or 0 end,
			__newindex = function(_, k, v) store[k] = v end,
		})
		local x = 0
		for i = 1, n do
			proxy[i % 64] = (proxy[i % 64] or 0) + i
			x = x + proxy[i % 64]
		end
		return x
	end },
	{ name = "Instances", label = "Creating and destroying Roblox Instances", inner = 160, fn = function(n)
		local f, x = Instance.new("Folder"), 0
		for i = 1, n do local v = Instance.new("IntValue") v.Value = i v.Parent = f x = x + v.Value end
		f:Destroy()
		return x
	end },
}

local function bench(t)
	local samples = create(SAMPLES, 0)
	for i = 1, WARMUP do sink = sink + t.fn(t.inner) end
	for i = 1, SAMPLES do
		local s = clock()
		sink = sink + t.fn(t.inner)
		samples[i] = clock() - s
	end
	return stat(samples)
end

local function row(t, r)
	local ops = t.inner / math.max(r.avg, 1e-12)
	print(("%-11s %s"):format(t.name, t.label))
	print(("            avg %-10s typical %-10s worst-case %-10s  ->  %.0f ops/sec"):format(
		fmt(r.avg), fmt(r.p50), fmt(r.p95), ops))
	print("")
	return ops
end

local ok, err = pcall(function()
	pcall(collectgarbage, "collect")

	for i = 1, 10 do print("") end

	print("=========================================")
	print("        Luau Runtime Benchmark 2026")
	print("=========================================")
	print("Executor: " .. executor())
	print(("Each test runs %d times back to back."):format(SAMPLES))
	print("Reading the numbers: lower time = faster, higher ops/sec = faster.")
	print("'typical' is the normal-case time, 'worst-case' is what happens under load.")
	print("=========================================\n")

	local totalOps, opsCount = 0, 0
	for _, t in ipairs(tests) do
		totalOps = totalOps + row(t, bench(t))
		opsCount = opsCount + 1
		wait()
	end

	local y = create(YIELDS, 0)
	for i = 1, YIELDS do
		local s = clock()
		wait()
		y[i] = clock() - s
	end
	local yr = stat(y)

	print("=========================================")
	print("SUMMARY")
	print("=========================================")
	print(("Average speed across all tests: %.0f ops/sec"):format(totalOps / opsCount))
	print(("Scheduler responsiveness (delay to resume after a wait):"))
	print(("  usually %s, worst-case %s"):format(fmt(yr.avg), fmt(yr.p95)))
	print(("Memory currently in use: %.2f MB"):format(mem()))
	print("=========================================")
	print("Benchmark complete.")
end)

if not ok then warn("Benchmark failed: " .. tostring(err)) end
