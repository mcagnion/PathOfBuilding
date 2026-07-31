describe("PowerReportTattooEvaluator", function()
	local evaluator = LoadModule("Modules/PowerReportTattooEvaluator")

	local function makeContext(options)
		local rootNode = { id = 0 }
		local strengthNode = {
			id = 1,
			type = "Normal",
			dn = "Strength",
			sd = { "+10 to Strength" },
			alloc = options.allocated,
			linkedId = { 2 },
			x = 10,
			y = 20,
			path = { rootNode },
			pathDist = 2,
		}
		local tattoo = {
			id = 100,
			dn = "Tattoo of Physical Damage",
			sd = { "5% increased Physical Damage" },
			modKey = "test:tattoo",
			targetType = "Small Attribute",
			MinimumConnected = 0,
		}
		local calls = 0
		local yields = 0
		return {
			spec = {
				nodes = { [strengthNode.id] = strengthNode },
				tree = {
					nodes = { [strengthNode.id] = strengthNode },
					tattoo = { nodes = { [tattoo.id] = tattoo } },
				},
			},
			grantedPassives = { },
			canUsePathPower = function()
				return true
			end,
			calcWithPowerReportAssumptions = function(override)
				calls = calls + 1
				return { score = override.removeNodes and 20 or 10 }
			end,
			calculatePowerScore = function(output)
				return output.score
			end,
			yieldIfNeeded = function()
				yields = yields + 1
			end,
			includeTattoos = options.includeTattoos,
			includeRunegrafts = options.includeRunegrafts,
			nodePowerMaxDepth = options.nodePowerMaxDepth,
			getCalls = function()
				return calls
			end,
			getYields = function()
				return yields
			end,
		}
	end

	it("skips calculation when tattoos and runegrafts are both disabled", function()
		local context = makeContext({
			allocated = true,
			includeTattoos = false,
			includeRunegrafts = false,
		})

		local options = evaluator.buildOptions(context)

		assert.are.same(0, #options)
		assert.are.same(0, context.getCalls())
		assert.are.same(0, context.getYields())
	end)

	it("evaluates allocated tattoo replacements and reachable tattoo nodes", function()
		local allocatedContext = makeContext({
			allocated = true,
			includeTattoos = true,
			includeRunegrafts = false,
			nodePowerMaxDepth = 5,
		})
		local allocatedOptions = evaluator.buildOptions(allocatedContext)

		assert.are.same(1, #allocatedOptions)
		assert.is_true(allocatedOptions[1].allocated)
		assert.are.same(20, allocatedOptions[1].singleStat)
		assert.are.same("Tattoo of Physical Damage", allocatedOptions[1].tattooName)
		assert.are.same(1, allocatedContext.getYields())

		local nearestContext = makeContext({
			allocated = false,
			includeTattoos = true,
			includeRunegrafts = false,
			nodePowerMaxDepth = 5,
		})
		local nearestOptions = evaluator.buildOptions(nearestContext)

		assert.are.same(1, #nearestOptions)
		assert.is_false(nearestOptions[1].allocated)
		assert.are.same(10, nearestOptions[1].singleStat)
		assert.are.same(2, nearestOptions[1].pathDist)
		assert.are.same(2, nearestContext.getYields())
	end)

	it("swaps an allocated runegraft before evaluating another one", function()
		local rootNode = { id = 0 }
		local allocatedRunegraft = {
			id = 1,
			type = "Mastery",
			dn = "Runegraft of the Existing",
			sd = { "Existing runegraft effect" },
			modKey = "test:existing-runegraft",
			isTattoo = true,
			overrideType = "AlternateMastery",
			alloc = true,
			linkedId = { 2 },
			x = 10,
			y = 20,
		}
		local reachableMastery = {
			id = 2,
			type = "Mastery",
			dn = "Attack Mastery",
			sd = { "Attack mastery effect" },
			modKey = "test:nearby-mastery",
			alloc = false,
			linkedId = { 1 },
			path = { rootNode },
			pathDist = 2,
			x = 30,
			y = 40,
		}
		local candidateRunegraft = {
			id = 100,
			dn = "Runegraft of the Candidate",
			sd = { "Candidate runegraft effect" },
			modKey = "test:candidate-runegraft",
			overrideType = "AlternateMastery",
			targetType = "Mastery",
			MinimumConnected = 0,
		}
		local overrides = { }
		local context = {
			spec = {
				nodes = {
					[allocatedRunegraft.id] = allocatedRunegraft,
					[reachableMastery.id] = reachableMastery,
				},
				tree = {
					nodes = {
						[allocatedRunegraft.id] = {
							id = allocatedRunegraft.id,
							type = "Mastery",
							dn = "Attack Mastery",
							sd = { "Attack mastery effect" },
							linkedId = { 2 },
						},
						[reachableMastery.id] = reachableMastery,
					},
					tattoo = { nodes = { [candidateRunegraft.id] = candidateRunegraft } },
				},
			},
			grantedPassives = { },
			canUsePathPower = function()
				return true
			end,
			calcWithPowerReportAssumptions = function(override)
				overrides[#overrides + 1] = override
				local candidateAdded = false
				for node in pairs(override.addNodes or { }) do
					candidateAdded = candidateAdded or node.modKey == candidateRunegraft.modKey
				end
				return { score = candidateAdded and override.removeNodes and override.removeNodes[allocatedRunegraft] and 20 or 100 }
			end,
			calculatePowerScore = function(output)
				return output.score
			end,
			includeTattoos = false,
			includeRunegrafts = true,
			nodePowerMaxDepth = 5,
		}

		local options = evaluator.buildOptions(context)

		assert.are.same(2, #options)
		for _, option in ipairs(options) do
			assert.is_true(option.isRunegraft)
			assert.are.same(20, option.singleStat)
		end
		for _, override in ipairs(overrides) do
			assert.is_true(override.removeNodes[allocatedRunegraft])
		end
	end)

	it("integrates tattoo options into the power builder", function()
		newBuild()
		local calcsTab = build.calcsTab
		local treeTab = build.treeTab
		local originalSpecNodes = build.spec.nodes
		local originalTreeNodes = build.spec.tree.nodes
		local originalClusterNodeMap = build.spec.tree.clusterNodeMap
		local originalTattooNodes = build.spec.tree.tattoo.nodes
		local strengthNode = {
			id = 1,
			type = "Normal",
			dn = "Strength",
			sd = { "+10 to Strength" },
			modKey = "test:strength",
			power = { },
			alloc = true,
			linkedId = { 2 },
			path = { },
			pathDist = 1,
		}
		build.spec.nodes = { [strengthNode.id] = strengthNode }
		build.spec.tree.nodes = { [strengthNode.id] = strengthNode }
		build.spec.tree.clusterNodeMap = { }
		build.spec.tree.tattoo.nodes = {
			[100] = {
				id = 100,
				dn = "Tattoo of Physical Damage",
				sd = { "5% increased Physical Damage" },
				modKey = "test:tattoo",
				targetType = "Small Attribute",
				MinimumConnected = 0,
			},
		}
		treeTab.includePowerReportTattoos = true
		treeTab.includePowerReportRunegrafts = false
		calcsTab.nodePowerMaxDepth = 0
		calcsTab.powerStat = { stat = "Test" }
		calcsTab.GetMiscCalculator = function()
			return function(override)
				return { score = override and override.addNodes and 20 or 0 }
			end, { score = 0 }
		end
		calcsTab.CalculatePowerStat = function(_, _, original, modified)
			return original.score - modified.score
		end

		local builder = coroutine.create(function()
			calcsTab:PowerBuilder()
		end)
		repeat
			local ok, err = coroutine.resume(builder)
			assert.is_true(ok, err)
		until coroutine.status(builder) == "dead"
		build.spec.nodes = originalSpecNodes
		build.spec.tree.nodes = originalTreeNodes
		build.spec.tree.clusterNodeMap = originalClusterNodeMap
		build.spec.tree.tattoo.nodes = originalTattooNodes

		assert.are.same(1, #calcsTab.powerTattooOptions)
		assert.is_true(calcsTab.powerTattooOptions[1].allocated)
		assert.are.same(20, calcsTab.powerTattooOptions[1].singleStat)
	end)
end)
