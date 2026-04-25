-- Portable cross-solution power-stat matrix bench.
-- Works on vanilla origin/dev, OursCodeur, feature, integration: pcall around
-- PowerReportOptions so worktrees without that module still run (defaults =
-- all options ON in vanilla anyway).
-- Run: busted --lua=luajit -r benchmark --filter=PortableMatrix

describe("TestPowerReportPortableMatrix", function()
	before_each(function()
		newBuild()
	end)

	local powerReportOptions
	do
		local ok, mod = pcall(LoadModule, "Modules/PowerReportOptions")
		if ok then
			powerReportOptions = mod
		end
	end

	local function findStat(statName)
		for _, stat in ipairs(data.powerStatList) do
			if stat.stat == statName then return stat end
		end
	end

	local function setAllOptions(value)
		if not powerReportOptions then return end
		for _, key in ipairs(powerReportOptions.getContentKeys()) do
			build.treeTab[key] = value
		end
	end

	local function isEnvEnabled(name)
		local value = os.getenv(name)
		return value == "1" or value == "true"
	end

	local function drainPowerBuild(stat)
		build.calcsTab.powerBuildFlag = true
		build.calcsTab.powerStat = stat or findStat("Life")
		local maxIter = 100000
		local iter = 0
		repeat
			build.calcsTab:BuildPower()
			iter = iter + 1
		until not build.calcsTab.powerBuilder or iter >= maxIter
	end

	-- Returns true if the build was loaded, false if the file is missing
	-- (e.g. user-specific XML not committed in the repo). Allows graceful skip.
	local function loadXmlAt(path, name)
		if not path or path == "" then return false end
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

	local function measure(label, statName)
		setAllOptions(true)
		if isEnvEnabled("POB_POWER_REPORT_EXCLUDE_CLUSTERS") then
			build.treeTab.includePowerReportClusters = false
		end
		local stat = findStat(statName)
		if not stat then
			-- Stat absent on this branch (e.g. WeightedScore on vanilla/OursCodeur).
			-- Skip rather than fail so the matrix runs to completion across worktrees.
			print(string.format("\n  [matrix] %s [%s]: SKIP (stat not in powerStatList on this branch)", label, statName))
			return
		end
		local t0 = os.clock()
		drainPowerBuild(stat)
		local elapsed = os.clock() - t0
		print(string.format("\n  [matrix] %s [%s]: %.2fs CPU", label, statName, elapsed))
		assert.is_not_nil(build.calcsTab.powerMax)
	end

	local probeBuilds = {
		{ label = "3.13 OccVortex (light)", load = function() return loadTestBuildModule("../spec/TestBuilds/3.13/OccVortex.lua", "OccVortex") end },
		{ label = "3.13 Generals Perforate Zerker (medium)", load = function() return loadTestBuildModule("../spec/TestBuilds/3.13/Generals Perforate Zerker.lua", "GeneralsPerforate") end },
		{ label = "external heavy build from POB_POWER_REPORT_HEAVY_XML", load = function() return loadXmlAt(os.getenv("POB_POWER_REPORT_HEAVY_XML"), "HeavyPowerReportBuild") end },
	}
	local probeStats = { "Life", "FullDPS", "TotalEHP", "WeightedScore" }

	for _, b in ipairs(probeBuilds) do
		for _, statName in ipairs(probeStats) do
			it(string.format("PortableMatrix %s [%s] #benchmark", b.label, statName), function()
				if b.load() == false then
					print(string.format("\n  [matrix] %s [%s]: SKIP (build XML not available)", b.label, statName))
					return
				end
				measure(b.label, statName)
			end)
		end
	end
end)
