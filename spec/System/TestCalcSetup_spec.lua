describe("TestCalcSetup", function()
	before_each(function()
		newBuild()
	end)

	it("removeNodes with node object key removes granted passive", function()
		-- Equip an amulet that grants "Allocates Heart of the Warrior"
		-- Heart of the Warrior: +20 to Strength, 10% increased maximum Life
		build.itemsTab:CreateDisplayItemFromRaw([[
		New Item
		Coral Amulet
		Allocates Heart of the Warrior
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		-- Verify the granted passive is active
		local grantedPassives = build.calcsTab.mainEnv.grantedPassives
		local grantedNodeId
		for nodeId in pairs(grantedPassives) do
			grantedNodeId = nodeId
			break
		end
		assert.truthy(grantedNodeId, "Expected a granted passive from the anoint")

		-- notableMap uses lowercased name — this is the object CalcSetup looks up
		local notableNode = build.spec.tree.notableMap["heart of the warrior"]
		assert.truthy(notableNode, "Expected the notable to exist in notableMap")

		-- Compute a baseline
		local calcFunc, baseOutput = build.calcsTab:GetMiscCalculator()
		local baseLife = baseOutput.Life
		assert.truthy(baseLife > 0, "Expected positive base Life")

		-- Remove using the notableMap node object as key (power report convention)
		local removedOutput = calcFunc({ removeNodes = { [notableNode] = true } })
		assert.is_not.equals(baseLife, removedOutput.Life,
			"Removing a granted passive with node-object key should change Life")
	end)

	it("removeNodes with node.id key removes granted passive", function()
		-- Same test but using node.id as key (PassiveTreeView tooltip convention)
		build.itemsTab:CreateDisplayItemFromRaw([[
		New Item
		Coral Amulet
		Allocates Heart of the Warrior
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		local grantedPassives = build.calcsTab.mainEnv.grantedPassives
		local grantedNodeId
		for nodeId in pairs(grantedPassives) do
			grantedNodeId = nodeId
			break
		end
		assert.truthy(grantedNodeId)

		-- Compute a baseline
		local calcFunc, baseOutput = build.calcsTab:GetMiscCalculator()
		local baseLife = baseOutput.Life

		-- Remove using node.id as key (PassiveTreeView convention)
		local removedOutput = calcFunc({ removeNodes = { [grantedNodeId] = true } })
		assert.is_not.equals(baseLife, removedOutput.Life,
			"Removing a granted passive with node.id key should change Life")
	end)

	it("power builder computes non-zero power for granted passives with nodePowerMaxDepth", function()
		-- Granted passives have no pathDist (distance 1000 by default).
		-- With nodePowerMaxDepth set, the distance filter must not skip them.
		build.itemsTab:CreateDisplayItemFromRaw([[
		New Item
		Coral Amulet
		Allocates Heart of the Warrior
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		local powerStat
		for _, stat in ipairs(data.powerStatList) do
			if stat.stat == "Life" then
				powerStat = stat
				break
			end
		end
		assert.truthy(powerStat, "Expected to find Life in powerStatList")
		build.calcsTab.powerStat = powerStat
		build.calcsTab.nodePowerMaxDepth = 5

		build.calcsTab.powerBuildFlag = true
		local co = coroutine.create(build.calcsTab.PowerBuilder)
		while coroutine.status(co) ~= "dead" do
			local ok, err = coroutine.resume(co, build.calcsTab)
			assert.truthy(ok, err)
		end

		local grantedNodeId
		for nodeId in pairs(build.calcsTab.mainEnv.grantedPassives) do
			grantedNodeId = nodeId
			break
		end
		assert.truthy(grantedNodeId)

		local node = build.spec.nodes[grantedNodeId]
		assert.truthy(node, "Expected granted node in spec.nodes")
		assert.truthy(node.power and node.power.singleStat and node.power.singleStat ~= 0,
			"Expected non-zero power.singleStat for granted passive with nodePowerMaxDepth=5, got: " .. tostring(node.power and node.power.singleStat))
	end)

	it("power builder computes non-zero power for granted passives", function()
		-- Equip an amulet that grants a notable
		build.itemsTab:CreateDisplayItemFromRaw([[
		New Item
		Coral Amulet
		Allocates Heart of the Warrior
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		-- Set up power stat to Full DPS (or Life-related)
		local powerStat
		for _, stat in ipairs(data.powerStatList) do
			if stat.stat == "Life" then
				powerStat = stat
				break
			end
		end
		assert.truthy(powerStat, "Expected to find Life in powerStatList")
		build.calcsTab.powerStat = powerStat

		-- Run the power builder to completion
		build.calcsTab.powerBuildFlag = true
		local co = coroutine.create(build.calcsTab.PowerBuilder)
		while coroutine.status(co) ~= "dead" do
			local ok, err = coroutine.resume(co, build.calcsTab)
			assert.truthy(ok, err)
		end

		-- Find the granted node and check its power
		local grantedNodeId
		for nodeId in pairs(build.calcsTab.mainEnv.grantedPassives) do
			grantedNodeId = nodeId
			break
		end
		assert.truthy(grantedNodeId)

		local node = build.spec.nodes[grantedNodeId]
		assert.truthy(node, "Expected granted node in spec.nodes, id=" .. tostring(grantedNodeId))
		assert.truthy(node.modKey and node.modKey ~= "",
			"Expected non-empty modKey, got: " .. tostring(node.modKey))
		assert.truthy(node.power, "Expected power table on the granted node")
		assert.truthy(node.power.singleStat and node.power.singleStat ~= 0,
			"Expected non-zero power.singleStat for a granted passive (anoint), got: " .. tostring(node.power.singleStat))
	end)
end)
