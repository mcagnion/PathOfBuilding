describe("TreeTab", function()
	local originalClusterNodeMap
	local originalMasteryEffects

	before_each(function()
		newBuild()
		originalClusterNodeMap = build.spec.tree.clusterNodeMap
		originalMasteryEffects = build.spec.tree.masteryEffects
	end)

	after_each(function()
		build.spec.tree.clusterNodeMap = originalClusterNodeMap
		build.spec.tree.masteryEffects = originalMasteryEffects
	end)

	it("adds separate power report entries for mastery effects", function()
		local treeTab = build.treeTab
		treeTab.includePowerReportMasteries = true
		local parentNode = { id = 2 }
		local masteryNode = {
			id = 1,
			type = "Mastery",
			dn = "Two Hand Mastery",
			power = {
				masteryEffects = {
					[101] = { singleStat = 10, pathPower = 10 },
					[102] = { singleStat = 20, pathPower = 20 },
				},
			},
			masteryEffects = {
				{ effect = 101 },
				{ effect = 102 },
			},
			path = { parentNode, false },
			x = 10,
			y = 20,
		}
		masteryNode.path[2] = masteryNode

		treeTab.build.displayStats = {
			{ stat = "Damage", label = "Damage", fmt = ".1f" },
		}
		treeTab.build.spec.nodes = {
			[masteryNode.id] = masteryNode,
		}
		treeTab.build.spec.masterySelections = { }
		treeTab.build.spec.tree.clusterNodeMap = { }
		treeTab.build.spec.tree.masteryEffects = {
			[101] = { id = 101, sd = { "Gain 10 Damage" }, stats = { "Gain 10 Damage" } },
			[102] = { id = 102, sd = { "Gain 20 Damage" }, stats = { "Gain 20 Damage" } },
		}
		treeTab.build.calcsTab.mainEnv = { grantedPassives = { } }

		local report = treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" })

		assert.are.same(2, #report)
		assert.are.same("Mastery", report[1].type)
		assert.are.same("Two Hand Mastery: Gain 20 Damage", report[1].name)
		assert.are.same(20, report[1].power)
		assert.are.same(2, report[1].pathDist)
		assert.are.same(10, report[2].power)
		assert.are.same("Two Hand Mastery: Gain 10 Damage", report[2].name)

		treeTab.includePowerReportMasteries = false
		assert.are.same(0, #treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" }))
	end)

	it("adds tattoo and runegraft power report entries", function()
		local treeTab = build.treeTab
		treeTab.build.displayStats = {
			{ stat = "Damage", label = "Damage", fmt = ".1f" },
		}
		treeTab.build.spec.nodes = { }
		treeTab.build.spec.tree.clusterNodeMap = { }
		treeTab.build.calcsTab.mainEnv = { grantedPassives = { } }
		treeTab.build.calcsTab.powerTattooOptions = {
			{
				displayName = "Tattoo of Physical Damage (Tattoo, nearest)",
				tattooName = "Tattoo of Physical Damage",
				stats = { "5% increased Physical Damage" },
				singleStat = 10,
				pathPower = 20,
				pathDist = 2,
				allocated = false,
				baseNodeId = 1,
				baseNodeX = 10,
				baseNodeY = 20,
				isRunegraft = false,
			},
			{
				displayName = "Runegraft of the Sinistral (Runegraft, nearest)",
				tattooName = "Runegraft of the Sinistral",
				stats = { "10% more Attack Speed with Off Hand" },
				singleStat = 20,
				pathPower = 40,
				pathDist = 2,
				allocated = false,
				baseNodeId = 2,
				baseNodeX = 30,
				baseNodeY = 40,
				isRunegraft = true,
			},
		}

		local report = treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" })

		assert.are.same(2, #report)
		assert.are.same("Runegraft", report[1].type)
		assert.are.same(20, report[1].power)
		assert.are.same("Tattoo", report[2].type)
		assert.are.same(10, report[2].power)
		assert.are.same(10, report[2].pathPower)

		treeTab.includePowerReportTattoos = false
		treeTab.includePowerReportRunegrafts = false
		assert.are.same(0, #treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" }))
	end)

	it("filters normal, notable, keystone and cluster report entries", function()
		local treeTab = build.treeTab
		local normalNode = { id = 1, type = "Normal", dn = "Strength", power = { singleStat = 10 }, path = { }, x = 10, y = 10 }
		local notableNode = { id = 2, type = "Notable", dn = "Strong Arm", power = { singleStat = 20 }, path = { }, x = 20, y = 20 }
		local keystoneNode = { id = 3, type = "Keystone", dn = "Resolute Technique", power = { singleStat = 30 }, path = { }, x = 30, y = 30 }
		local clusterNode = { id = 65536, type = "Notable", dn = "Cluster Power", power = { singleStat = 40 }, expansionSkill = true, x = 40, y = 40 }

		treeTab.build.displayStats = {
			{ stat = "Damage", label = "Damage", fmt = ".1f" },
		}
		treeTab.build.spec.nodes = {
			[normalNode.id] = normalNode,
			[notableNode.id] = notableNode,
			[keystoneNode.id] = keystoneNode,
			[clusterNode.id] = clusterNode,
		}
		treeTab.build.spec.tree.clusterNodeMap = { }
		treeTab.build.calcsTab.mainEnv = { grantedPassives = { } }
		treeTab.build.calcsTab.powerTattooOptions = { }

		treeTab.includePowerReportNormals = false
		treeTab.includePowerReportNotables = false
		treeTab.includePowerReportKeystones = false
		treeTab.includePowerReportClusters = false
		assert.are.same(0, #treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" }))

		treeTab.includePowerReportNormals = true
		local report = treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" })
		assert.are.same(1, #report)
		assert.are.same("Normal", report[1].type)

		treeTab.includePowerReportNormals = false
		treeTab.includePowerReportNotables = true
		report = treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" })
		assert.are.same(1, #report)
		assert.are.same("Notable", report[1].type)

		treeTab.includePowerReportNotables = false
		treeTab.includePowerReportKeystones = true
		report = treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" })
		assert.are.same(1, #report)
		assert.are.same("Keystone", report[1].type)

		treeTab.includePowerReportKeystones = false
		treeTab.includePowerReportClusters = true
		report = treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" })
		assert.are.same(1, #report)
		assert.are.same("Cluster Power", report[1].name)
	end)

	it("marks the build modified when a power report option changes", function()
		local treeTab = build.treeTab
		treeTab.modFlag = false

		treeTab:SetPowerReportOption("includePowerReportNormals", false)

		assert.is_false(treeTab.includePowerReportNormals)
		assert.is_true(treeTab.modFlag)
	end)
end)
