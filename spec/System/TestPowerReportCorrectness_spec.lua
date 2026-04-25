-- Correctness check: capture node.power.singleStat for all nodes after a
-- PowerBuilder run, write to a file. Run on each worktree (vanilla / feature /
-- ourscodeur / combined), then diff the output files.
-- The values should match within floating-point tolerance regardless of which
-- code path produces them.
--
-- Run: busted --lua=luajit -r benchmark --filter=Correctness
-- Output: /tmp/pob_powers_<worktree-name>_<build>_<stat>.txt
--
-- Compare in shell:
--   diff /tmp/pob_powers_vanilla_micka_Life.txt /tmp/pob_powers_combined_micka_Life.txt

describe("TestPowerReportCorrectness", function()
	before_each(function()
		newBuild()
	end)

	local powerReportOptions
	do
		local ok, mod = pcall(LoadModule, "Modules/PowerReportOptions")
		if ok then powerReportOptions = mod end
	end

	local function findStat(statName)
		for _, stat in ipairs(data.powerStatList) do
			if stat.stat == statName then return stat end
		end
	end

	local function setAllOptions(value)
		if not powerReportOptions then return end
		for _, key in ipairs(powerReportOptions.getKeys()) do
			build.treeTab[key] = value
		end
	end

	local function drainPowerBuild(stat)
		build.calcsTab.powerBuildFlag = true
		build.calcsTab.powerStat = stat
		repeat
			build.calcsTab:BuildPower()
		until not build.calcsTab.powerBuilder
	end

	-- Returns true if loaded, false if file missing (graceful skip for user XMLs).
	local function loadXmlAt(path, name)
		local f = io.open(path, "r")
		if not f then return false end
		local xml = f:read("*a")
		f:close()
		loadBuildFromXML(xml, name)
		return true
	end

	local function loadTestBuildModule(modPath, name)
		local m = LoadModule(modPath)
		loadBuildFromXML(m.xml, name)
		return true
	end

	-- Worktree identity for output filename: busted CWD is src/, so basename of
	-- its PARENT gives the worktree directory name (e.g. PathOfBuilding-vanilla-baseline).
	local function worktreeId()
		local p = io.popen("cd .. && pwd 2>/dev/null")
		local parent = p and p:read("*l") or ""
		if p then p:close() end
		return parent:match("([^/\\]+)[/\\]?$") or "unknown"
	end

	local function captureAndWrite(buildLabel, statName)
		setAllOptions(true)
		local stat = findStat(statName)
		if not stat then
			print(string.format("\n  [correctness] %s [%s]: SKIP (stat absent)", buildLabel, statName))
			return
		end
		drainPowerBuild(stat)
		-- Collect: id, dn, alloc, singleStat, pathPower
		local rows = {}
		for id, node in pairs(build.spec.nodes) do
			if node.power and node.power.singleStat ~= nil then
				rows[#rows+1] = string.format("%d\t%s\t%s\t%.6f\t%.6f",
					id,
					tostring(node.dn or "?"):gsub("[\t\n]", " "),
					node.alloc and "alloc" or "free",
					node.power.singleStat or 0,
					node.power.pathPower or 0)
			end
		end
		table.sort(rows)
		local wt = worktreeId()
		local outPath = string.format("/tmp/pob_powers_%s_%s_%s.txt", wt, buildLabel, statName)
		local f = assert(io.open(outPath, "w"), "cannot write "..outPath)
		f:write("# worktree=", wt, "\n# build=", buildLabel, "\n# stat=", statName, "\n# rows=", #rows, "\n")
		f:write("# id\tname\talloc\tsingleStat\tpathPower\n")
		for _, row in ipairs(rows) do
			f:write(row, "\n")
		end
		f:close()
		print(string.format("\n  [correctness] %s [%s]: %d node powers -> %s", buildLabel, statName, #rows, outPath))
	end

	it("Correctness Generals Perforate Zerker [Life] #benchmark", function()
		loadTestBuildModule("../spec/TestBuilds/3.13/Generals Perforate Zerker.lua", "GeneralsPerforate")
		captureAndWrite("generals", "Life")
	end)

	it("Correctness MickaShadow [Life] #benchmark", function()
		if loadXmlAt("/mnt/d/GitHub/PathOfBuilding/src/Builds/3.28 - Mirage/mrtiz - MickaMirageShadow.xml", "MickaShadow") == false then
			print("\n  [correctness] MickaShadow [Life]: SKIP (build XML not available)")
			return
		end
		captureAndWrite("micka", "Life")
	end)

	it("Correctness MickaShadow [TotalEHP] #benchmark", function()
		if loadXmlAt("/mnt/d/GitHub/PathOfBuilding/src/Builds/3.28 - Mirage/mrtiz - MickaMirageShadow.xml", "MickaShadow") == false then
			print("\n  [correctness] MickaShadow [TotalEHP]: SKIP (build XML not available)")
			return
		end
		captureAndWrite("micka", "TotalEHP")
	end)
end)
