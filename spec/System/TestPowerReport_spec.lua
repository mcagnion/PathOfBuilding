describe("TestPowerReport", function()
	before_each(function()
		newBuild()
	end)

	local powerReportOptions = LoadModule("Modules/PowerReportOptions")

	local function findStat(statName)
		for _, stat in ipairs(data.powerStatList) do
			if stat.stat == statName then
				return stat
			end
		end
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

	local function setAllOptions(value)
		for _, key in ipairs(powerReportOptions.getKeys()) do
			build.treeTab[key] = value
		end
	end

	local function buildReport(stat)
		return build.treeTab:BuildPowerReportList(stat or findStat("Life"))
	end

	-- Vérifie qu'aucun item du rapport n'a le type donné
	local function assertNoItemOfType(report, itemType)
		for _, item in ipairs(report) do
			assert.is_not.equal(itemType, item.type,
				"Report should not contain type '" .. itemType .. "' but found: " .. item.name)
		end
	end

	-- Basic sanity ----------------------------------------------------------

	it("powerMax is initialized when all options are disabled", function()
		setAllOptions(false)
		drainPowerBuild()
		assert.is_not_nil(build.calcsTab.powerMax)
		assert.is_true(build.calcsTab.powerBuilderInitialized)
	end)

	it("powerMax fields are zero when all options are disabled", function()
		setAllOptions(false)
		drainPowerBuild()
		local powerMax = build.calcsTab.powerMax
		assert.are.equal(0, powerMax.singleStat)
		assert.are.equal(0, powerMax.offence)
		assert.are.equal(0, powerMax.defence)
	end)

	it("powerTattooOptions is empty when all options are disabled", function()
		setAllOptions(false)
		drainPowerBuild()
		assert.are.equal(0, #build.calcsTab.powerTattooOptions)
	end)

	it("powerMax is initialized when all options are enabled", function()
		setAllOptions(true)
		drainPowerBuild()
		assert.is_not_nil(build.calcsTab.powerMax)
		assert.is_true(build.calcsTab.powerBuilderInitialized)
	end)

	it("powerMax is initialized with default options", function()
		drainPowerBuild()
		assert.is_not_nil(build.calcsTab.powerMax)
		assert.is_true(build.calcsTab.powerBuilderInitialized)
	end)

	-- Test 1 : filtrage par type de nœud ------------------------------------

	it("report excludes Normal nodes when includeNormals is disabled", function()
		build.treeTab.includePowerReportNormals = false
		drainPowerBuild()
		local report = buildReport()
		assertNoItemOfType(report, "Normal")
	end)

	it("report excludes Notable nodes when includeNotables and includeAscNotables are disabled", function()
		build.treeTab.includePowerReportNotables = false
		build.treeTab.includePowerReportAscNotables = false
		build.treeTab.includePowerReportForbiddenAscendancy = false
		drainPowerBuild()
		local report = buildReport()
		assertNoItemOfType(report, "Notable")
	end)

	it("report excludes Keystone nodes when includeKeystones and includeAscKeystones are disabled", function()
		build.treeTab.includePowerReportKeystones = false
		build.treeTab.includePowerReportAscKeystones = false
		build.treeTab.includePowerReportForbiddenAscendancy = false
		drainPowerBuild()
		local report = buildReport()
		assertNoItemOfType(report, "Keystone")
	end)

	-- Test 2 : nodePowerMaxDepth=0 ne crashe pas ----------------------------

	it("no crash with nodePowerMaxDepth=0 and tattoos enabled", function()
		build.calcsTab.nodePowerMaxDepth = 0
		build.treeTab.includePowerReportTattoos = true
		build.treeTab.includePowerReportRunegrafts = true
		drainPowerBuild()
		assert.is_not_nil(build.calcsTab.powerMax)
		assert.is_true(build.calcsTab.powerBuilderInitialized)
	end)

	it("no crash with nodePowerMaxDepth=0 and all options enabled", function()
		build.calcsTab.nodePowerMaxDepth = 0
		setAllOptions(true)
		drainPowerBuild()
		assert.is_not_nil(build.calcsTab.powerMax)
		assert.is_true(build.calcsTab.powerBuilderInitialized)
	end)

	-- Test 3 : filtrage partiel des tattoos ---------------------------------

	it("powerTattooOptions has no Runegraft when includeRunegrafts is disabled", function()
		build.treeTab.includePowerReportRunegrafts = false
		build.treeTab.includePowerReportTattoos = true
		drainPowerBuild()
		for _, option in ipairs(build.calcsTab.powerTattooOptions) do
			assert.is_false(option.isRunegraft,
				"powerTattooOptions should not contain Runegraft option: " .. (option.displayName or "?"))
		end
	end)

	it("powerTattooOptions has no non-Runegraft when includeTattoos is disabled", function()
		build.treeTab.includePowerReportTattoos = false
		build.treeTab.includePowerReportRunegrafts = true
		drainPowerBuild()
		for _, option in ipairs(build.calcsTab.powerTattooOptions) do
			assert.is_true(option.isRunegraft,
				"powerTattooOptions should not contain Tattoo option: " .. (option.displayName or "?"))
		end
	end)

	-- Test 4 : une seule option active --------------------------------------

	it("completes with only keystones enabled", function()
		setAllOptions(false)
		build.treeTab.includePowerReportKeystones = true
		drainPowerBuild()
		assert.is_not_nil(build.calcsTab.powerMax)
		assert.is_true(build.calcsTab.powerBuilderInitialized)
	end)

	it("completes with only normals enabled", function()
		setAllOptions(false)
		build.treeTab.includePowerReportNormals = true
		drainPowerBuild()
		assert.is_not_nil(build.calcsTab.powerMax)
		assert.is_true(build.calcsTab.powerBuilderInitialized)
	end)

	it("completes with only masteries enabled", function()
		setAllOptions(false)
		build.treeTab.includePowerReportMasteries = true
		drainPowerBuild()
		assert.is_not_nil(build.calcsTab.powerMax)
		assert.is_true(build.calcsTab.powerBuilderInitialized)
	end)
end)
