-- Tests for PowerBuilder node power calculation:
-- allocated nodes, unallocated nodes, and jewel-dependent nodes
-- (Intuitive Leap / Impossible Escape pattern).

local function runPowerBuilder(powerStat)
	build.calcsTab.powerStat = powerStat
	build.calcsTab.powerBuildFlag = true
	local co = coroutine.create(build.calcsTab.PowerBuilder)
	while coroutine.status(co) ~= "dead" do
		local ok, err = coroutine.resume(co, build.calcsTab)
		assert.truthy(ok, tostring(err))
	end
end

local function findPowerStat(statName)
	for _, stat in ipairs(data.powerStatList) do
		if stat.stat == statName then return stat end
	end
end

-- Load a build that has many allocated nodes.
local testBuild = LoadModule("../spec/TestBuilds/3.13/OccVortex.lua")

describe("PowerBuilder — allocated nodes (Show Allocated)", function()
	before_each(function()
		loadBuildFromXML(testBuild.xml, "OccVortex")
	end)

	-- Pass: allocated node with real mods contributes to a stat, so singleStat != 0
	-- Fail: if allocated nodes are skipped (not node.alloc guard), power stays nil/0
	it("allocated node has non-zero singleStat for Life stat", function()
		local powerStat = findPowerStat("Life")
		assert.is_not_nil(powerStat, "Life must be in powerStatList")
		runPowerBuilder(powerStat)

		local found = nil
		for id, node in pairs(build.spec.allocNodes) do
			if node.modKey ~= "" and node.type ~= "ClassStart" and node.type ~= "Socket"
			and #node.intuitiveLeapLikesAffecting == 0
			and node.power and node.power.singleStat and node.power.singleStat ~= 0 then
				found = node
				break
			end
		end
		assert.is_not_nil(found, "Expected at least one allocated node with non-zero power.singleStat")
	end)

	-- Pass: allocated node that buffs Life scores negative (removing it hurts)
	-- Fail: sign inversion would give positive scores for allocated beneficial nodes
	it("allocated Life node scores negative (removal reduces Life)", function()
		local powerStat = findPowerStat("Life")
		assert.is_not_nil(powerStat)
		runPowerBuilder(powerStat)

		local negative = nil
		for id, node in pairs(build.spec.allocNodes) do
			if node.modKey ~= "" and node.type ~= "ClassStart" and node.type ~= "Socket"
			and #node.intuitiveLeapLikesAffecting == 0
			and node.power and node.power.singleStat and node.power.singleStat < 0 then
				negative = node
				break
			end
		end
		assert.is_not_nil(negative, "Expected at least one allocated node with negative singleStat (removal hurts)")
	end)
end)

describe("PowerBuilder — unallocated nodes", function()
	before_each(function()
		loadBuildFromXML(testBuild.xml, "OccVortex")
	end)

	-- Pass: nearby unallocated node with real mods gets a positive score
	-- Fail: if the distance filter incorrectly skips close nodes
	it("unallocated node near tree has non-zero singleStat for Life stat", function()
		local powerStat = findPowerStat("Life")
		assert.is_not_nil(powerStat)
		runPowerBuilder(powerStat)

		local found = nil
		for id, node in pairs(build.spec.nodes) do
			if not node.alloc and node.modKey ~= "" and node.type ~= "Socket"
			and node.pathDist and node.pathDist <= 3
			and node.power and node.power.singleStat and node.power.singleStat ~= 0 then
				found = node
				break
			end
		end
		assert.is_not_nil(found, "Expected at least one nearby unallocated node with non-zero power.singleStat")
	end)

	-- Pass: unallocated Life node scores positive (adding it helps)
	-- Fail: if CalcPowerStat arg order is inverted, adding a beneficial node would score negative
	it("unallocated Life node scores positive (allocating it increases Life)", function()
		local powerStat = findPowerStat("Life")
		assert.is_not_nil(powerStat)
		runPowerBuilder(powerStat)

		local positive = nil
		for id, node in pairs(build.spec.nodes) do
			if not node.alloc and node.modKey ~= "" and node.type ~= "Socket"
			and node.pathDist and node.pathDist <= 5
			and node.power and node.power.singleStat and node.power.singleStat > 0 then
				positive = node
				break
			end
		end
		assert.is_not_nil(positive, "Expected at least one unallocated node with positive singleStat (allocation helps)")
	end)
end)

describe("PowerBuilder — jewel-dependent nodes (intuitiveLeapLikesAffecting)", function()
	before_each(function()
		loadBuildFromXML(testBuild.xml, "OccVortex")
	end)

	-- Helper: find an allocated node that has mods affecting Life, then inject
	-- intuitiveLeapLikesAffecting to simulate a node taken via Intuitive Leap or Impossible Escape.
	-- We force pathDist=0 to reproduce the exact case that pathDist==1000 alone would miss:
	-- a keystone that is also reachable via a normal tree path.
	local function injectIntuitiveLeapNode()
		local calcFunc = build.calcsTab:GetMiscCalculator()
		local baseLife = calcFunc().Life or 0
		local target = nil
		for id, node in pairs(build.spec.allocNodes) do
			if node.modKey ~= "" and node.type ~= "ClassStart" and node.type ~= "Socket"
			and not node.ascendancyName
			and #node.intuitiveLeapLikesAffecting == 0 then
				-- Check this node actually affects Life
				local removedLife = calcFunc({ removeNodes = { [node] = true } }).Life or 0
				if removedLife ~= baseLife then
					target = node
					break
				end
			end
		end
		assert.is_not_nil(target, "Need an allocated node that affects Life to inject intuitiveLeapLikesAffecting")

		-- Simulate jewel-dependency: add a dummy entry so #intuitiveLeapLikesAffecting > 0
		-- and force pathDist=0 (as if the node is also reachable via normal tree path).
		target.intuitiveLeapLikesAffecting = { target }
		target.pathDist = 0

		return target
	end

	-- Pass: node with intuitiveLeapLikesAffecting gets its power calculated (singleStat is set)
	-- Fail: old code (pathDist==1000 only) would skip this node → power.singleStat stays nil
	it("allocated node with intuitiveLeapLikesAffecting gets singleStat set by PowerBuilder", function()
		local target = injectIntuitiveLeapNode()
		target.power = {}

		local powerStat = findPowerStat("Life")
		assert.is_not_nil(powerStat)
		runPowerBuilder(powerStat)

		assert.is_not_nil(target.power, "power table must exist after PowerBuilder")
		assert.is_not_nil(target.power.singleStat,
			"power.singleStat must be set (not nil) for a jewel-dependent allocated node — nil means PowerBuilder skipped it")
		assert.is_true(target.power.singleStat ~= 0,
			"power.singleStat must be non-zero for a node that affects Life")
	end)

	-- Pass: intuitiveLeap node with pathDist==0 is still processed even with tight nodePowerMaxDepth
	-- Fail: if only grantedPassives path runs, nodes with pathDist!=1000 fall into
	--       distanceMap and are skipped by the "not node.alloc" guard
	it("jewel-dependent node with pathDist=0 is not skipped by nodePowerMaxDepth", function()
		local target = injectIntuitiveLeapNode()
		target.power = {}

		local powerStat = findPowerStat("Life")
		assert.is_not_nil(powerStat)
		build.calcsTab.nodePowerMaxDepth = 1

		runPowerBuilder(powerStat)

		assert.is_not_nil(target.power.singleStat,
			"jewel-dependent node must bypass nodePowerMaxDepth (singleStat is nil → node was skipped)")
		assert.is_true(target.power.singleStat ~= 0,
			"singleStat must be non-zero even with tight nodePowerMaxDepth")
	end)
end)
