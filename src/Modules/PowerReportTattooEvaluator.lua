-- Path of Building
--
-- Module: Power Report Tattoo Evaluator
-- Builds tattoo and runegraft power report options.
--

local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert
local t_sort = table.sort
local t_concat = table.concat

local powerReportTattooEvaluator = { }

local function isSmallAttributeNode(node)
	return node and node.type == "Normal"
		and (node.dn == "Strength" or node.dn == "Dexterity" or node.dn == "Intelligence")
end

local function isAttributeNotableNode(node)
	local firstStatLine = node and node.sd and node.sd[1]
	return node and node.type == "Notable" and firstStatLine and (
		firstStatLine:match("%+30 to Dexterity")
		or firstStatLine:match("%+30 to Strength")
		or firstStatLine:match("%+30 to Intelligence")
	)
end

local function isTattooEditableNode(node)
	return node and (
		node.isTattoo
		or isSmallAttributeNode(node)
		or isAttributeNotableNode(node)
		or node.type == "Keystone"
		or node.type == "Mastery"
	)
end

local function makeTattooGroupKey(node)
	if isSmallAttributeNode(node) then
		return "SmallAttribute:" .. node.dn
	end
	return "Node:" .. node.id
end

local function isRunegraftTattoo(tattoo)
	return tattoo and (
		tattoo.overrideType == "AlternateMastery"
		or (tattoo.dn and tattoo.dn:find("Runegraft", 1, true) ~= nil)
	)
end

local function getTattooCategory(tattoo)
	if isRunegraftTattoo(tattoo) then
		return "Runegraft"
	end
	if tattoo and (
		tattoo.overrideType == "KeystoneTattoo"
		or tattoo.ks
		or tattoo.targetType == "Keystone"
	) then
		return "Keystone"
	end
	if tattoo and (tattoo["not"] or tattoo.targetType == "Notable") then
		return "Notable"
	end
	if tattoo and tattoo.targetType == "Small Attribute" then
		return "SmallAttribute"
	end
	return "Tattoo"
end

local function getTattooCategoryLabel(category)
	if category == "Runegraft" then
		return "Runegraft"
	end
	if category == "Keystone" then
		return "Keystone Tattoo"
	end
	if category == "Notable" then
		return "Notable Tattoo"
	end
	if category == "SmallAttribute" then
		return "Small Attribute Tattoo"
	end
	return "Tattoo"
end

local function getTattooMaxCount(category)
	if category == "Keystone" then
		return 1
	end
	if category == "Notable" then
		return 3
	end
	return 1
end

local function countKeys(tbl)
	local count = 0
	for _ in pairs(tbl or { }) do
		count = count + 1
	end
	return count
end

local function getTattooCandidatesForNode(spec, node, candidateTattoos)
	local candidates = { }
	local baseNode = spec.tree.nodes[node.id] or node
	local nodeName = baseNode.dn or ""
	local nodeValue = (baseNode.sd and baseNode.sd[1]) or ""
	local numLinkedNodes = baseNode.linkedId and #baseNode.linkedId or 0
	for _, tattoo in ipairs(candidateTattoos) do
		local matchesTarget = (
			(nodeName:match((tattoo.targetType or ""):gsub("^Small ", "")))
			or ((tattoo.targetValue or "") ~= "" and nodeValue:match(tattoo.targetValue))
			or (
				tattoo.targetType == "Small Attribute"
				and (nodeName == "Intelligence" or nodeName == "Strength" or nodeName == "Dexterity")
			)
			or (tattoo.targetType == "Keystone" and baseNode.type == "Keystone")
			or (tattoo.targetType == "Mastery" and baseNode.type == "Mastery")
		)
		if matchesTarget and tattoo.MinimumConnected <= numLinkedNodes then
			t_insert(candidates, tattoo)
		end
	end
	return candidates
end

local function makeTattooReplacementNode(baseNode, tattoo)
	return {
		id = baseNode.id,
		type = baseNode.type,
		name = baseNode.name,
		dn = tattoo.dn,
		sd = tattoo.sd,
		modList = tattoo.modList,
		modKey = tattoo.modKey,
		isTattoo = true,
		overrideType = tattoo.overrideType,
		reminderText = tattoo.reminderText or { },
	}
end

local function getReachablePathDist(node)
	if not (node and node.path) then
		return nil
	end
	local pathDist = node.pathDist
	if not pathDist or pathDist <= 0 then
		pathDist = #node.path
	end
	if not pathDist or pathDist <= 0 or pathDist >= 1000 then
		return nil
	end
	return pathDist
end

local function makeTattooOverrideForNodes(baseNodes, tattoo)
	local addNodes = { }
	local removeNodes = { }
	local tattooByBaseId = { }
	for _, baseNode in ipairs(baseNodes) do
		local tattooNode = makeTattooReplacementNode(baseNode, tattoo)
		addNodes[tattooNode] = true
		removeNodes[baseNode] = true
		tattooByBaseId[baseNode.id] = tattooNode
	end
	return { addNodes = addNodes, removeNodes = removeNodes }, tattooByBaseId
end

local function makeTattooNearestOverrideForNodes(baseNodes, tattoo)
	local addNodes = { }
	local tattooByBaseId = { }
	for _, baseNode in ipairs(baseNodes) do
		local tattooNode = makeTattooReplacementNode(baseNode, tattoo)
		addNodes[tattooNode] = true
		tattooByBaseId[baseNode.id] = tattooNode
	end
	return { addNodes = addNodes }, tattooByBaseId
end

local function makeTattooNearestPathOverride(baseNodes, tattooByBaseId)
	local pathNodes = { }
	for _, baseNode in ipairs(baseNodes) do
		local tattooNode = tattooByBaseId[baseNode.id]
		for _, pathNode in pairs(baseNode.path or { }) do
			local replacement = tattooByBaseId[pathNode.id]
			if replacement then
				pathNodes[replacement] = true
			else
				pathNodes[pathNode] = true
			end
		end
		if tattooNode then
			pathNodes[tattooNode] = true
		end
	end
	return { addNodes = pathNodes }, countKeys(pathNodes)
end

local function getAllocatedRunegraftNodes(spec)
	local runegrafts = { }
	for _, node in pairs(spec.nodes) do
		if node.alloc and node.isTattoo and isRunegraftTattoo(node) then
			t_insert(runegrafts, node)
		end
	end
	return runegrafts
end

local function removeAllocatedRunegrafts(override, runegrafts)
	if #runegrafts == 0 then
		return override
	end
	override.removeNodes = override.removeNodes or { }
	for _, node in ipairs(runegrafts) do
		override.removeNodes[node] = true
	end
	return override
end

function powerReportTattooEvaluator.buildOptions(context)
	if not context.includeTattoos and not context.includeRunegrafts then
		return { }
	end
	local spec = context.spec
	local grantedPassives = context.grantedPassives or { }
	local canUsePathPower = context.canUsePathPower
	local calcWithPowerReportAssumptions = context.calcWithPowerReportAssumptions
	local calculatePowerScore = context.calculatePowerScore
	local yieldIfNeeded = context.yieldIfNeeded or function() end
	local function calculateCandidate(override, cacheKey)
		local output, assumedEnemyConditions = calcWithPowerReportAssumptions(override, cacheKey)
		yieldIfNeeded()
		return output, assumedEnemyConditions
	end

	local powerTattooOptions = { }
	local tattooCases = { }
	local candidateTattoos = { }
	local allocatedRunegrafts = getAllocatedRunegraftNodes(spec)
	local noNearestCandidates = context.nodePowerMaxDepth and context.nodePowerMaxDepth <= 0
	for _, tattoo in pairs(spec.tree.tattoo.nodes) do
		if tattoo and not tattoo.legacy then
			local isRunegraft = isRunegraftTattoo(tattoo)
			local tattooCategory = getTattooCategory(tattoo)
			local includeTattoo = (isRunegraft and context.includeRunegrafts)
				or ((not isRunegraft) and context.includeTattoos)
			if includeTattoo and tattooCategory ~= "Keystone" then
				t_insert(candidateTattoos, tattoo)
			end
		end
	end
	if #candidateTattoos == 0 then
		return powerTattooOptions
	end
	for _, node in pairs(spec.nodes) do
		local canBeReplacement = node.alloc
		local canBeNearest = not noNearestCandidates and not node.alloc
		if isTattooEditableNode(node) and not grantedPassives[node.id] and (canBeReplacement or canBeNearest) then
			for _, tattoo in ipairs(getTattooCandidatesForNode(spec, node, candidateTattoos)) do
				-- Skip no-op replacement (same underlying mod set)
				if not (node.isTattoo and node.modKey == tattoo.modKey) then
					local case = tattooCases[tattoo.id]
					if not case then
						case = {
							tattoo = tattoo,
							category = getTattooCategory(tattoo),
							replacementByKey = { },
							replacementCandidates = { },
							nearestCandidates = { },
						}
						tattooCases[tattoo.id] = case
					end
					if canBeReplacement then
						local groupKey = makeTattooGroupKey(node)
						if not case.replacementByKey[groupKey] then
							case.replacementByKey[groupKey] = node
							t_insert(case.replacementCandidates, node)
						end
					else
						local pathDist = getReachablePathDist(node)
						if pathDist and (not context.nodePowerMaxDepth or pathDist <= context.nodePowerMaxDepth) and canUsePathPower(node) then
							t_insert(case.nearestCandidates, { node = node, pathDist = pathDist })
						end
					end
				end
			end
		end
	end

	for tattooId, case in pairs(tattooCases) do
		local tattoo = case.tattoo
		local isRunegraftOption = isRunegraftTattoo(tattoo)
		local category = case.category
		local maxTattooCount = getTattooMaxCount(category)
		local categoryLabel = getTattooCategoryLabel(category)
		t_sort(case.replacementCandidates, function(a, b)
			return a.id < b.id
		end)
		t_sort(case.nearestCandidates, function(a, b)
			if a.pathDist == b.pathDist then
				return a.node.id < b.node.id
			end
			return a.pathDist < b.pathDist
		end)

		local replacementMaxCount = maxTattooCount
		if replacementMaxCount > #case.replacementCandidates then
			replacementMaxCount = #case.replacementCandidates
		end
		local selectedReplacement = { }
		local selectedReplacementById = { }
		-- Scores recorded at count=1 to rank candidates in subsequent passes
		local candidateScores = { }
		for count = 1, replacementMaxCount do
			local bestCandidate
			local bestAssumedEnemyConditions
			local bestSingleStat
			-- For count > 1, prune to top-3 candidates by their count=1 score.
			-- Tattoo effects are largely independent, so the count=1 ranking is a
			-- reliable proxy and avoids O(N * maxCount) calc calls when N is large.
			local candidatesToTest = case.replacementCandidates
			if count > 1 and #case.replacementCandidates > 3 then
				local ranked = { }
				for _, c in ipairs(case.replacementCandidates) do
					if not selectedReplacementById[c.id] then
						t_insert(ranked, c)
					end
				end
				t_sort(ranked, function(a, b)
					return (candidateScores[a.id] or 0) > (candidateScores[b.id] or 0)
				end)
				if #ranked > 3 then
					candidatesToTest = { ranked[1], ranked[2], ranked[3] }
				else
					candidatesToTest = ranked
				end
			end
			for _, candidate in ipairs(candidatesToTest) do
				if not selectedReplacementById[candidate.id] then
					local testNodes = { }
					for i = 1, #selectedReplacement do
						testNodes[i] = selectedReplacement[i]
					end
					t_insert(testNodes, candidate)
					local replaceOverride = makeTattooOverrideForNodes(testNodes, tattoo)
					if isRunegraftOption then
						removeAllocatedRunegrafts(replaceOverride, allocatedRunegrafts)
					end
					local testNodeKey = { }
					for _, node in ipairs(testNodes) do
						t_insert(testNodeKey, tostring(node.id))
					end
					t_sort(testNodeKey)
					local output, assumedEnemyConditions = calculateCandidate(
						replaceOverride,
						"tattooReplace:" .. tattooId .. ":" .. count .. ":" .. t_concat(testNodeKey, ",")
					)
					local singleStat = calculatePowerScore(output)
					if count == 1 then
						candidateScores[candidate.id] = singleStat or 0
					end
					if bestSingleStat == nil or singleStat > bestSingleStat then
						bestCandidate = candidate
						bestAssumedEnemyConditions = assumedEnemyConditions
						bestSingleStat = singleStat
					end
				end
			end
			if not bestCandidate then
				break
			end
			t_insert(selectedReplacement, bestCandidate)
			selectedReplacementById[bestCandidate.id] = true
			local firstNode = selectedReplacement[1]
			local countLabel = count > 1 and (" x" .. count) or ""
			t_insert(powerTattooOptions, {
				baseNodeId = firstNode.id,
				baseNodeName = firstNode.dn,
				baseNodeX = firstNode.x,
				baseNodeY = firstNode.y,
				tattooName = tattoo.dn,
				displayName = tattoo.dn .. " (" .. categoryLabel .. countLabel .. ", replace allocated)",
				stats = tattoo.sd,
				singleStat = bestSingleStat,
				pathPower = nil,
				pathDist = 0,
				allocated = true,
				isRunegraft = isRunegraftOption,
				tattooCategory = category,
				assumedEnemyConditions = bestAssumedEnemyConditions,
				pathAssumedEnemyConditions = nil,
			})
			if maxTattooCount > 1 and count == 1 and (bestSingleStat or 0) <= 0 then
				break
			end
		end

		local nearestMaxCount = maxTattooCount
		if nearestMaxCount > #case.nearestCandidates then
			nearestMaxCount = #case.nearestCandidates
		end
		for count = 1, nearestMaxCount do
			local nearestNodes = { }
			for i = 1, count do
				nearestNodes[i] = case.nearestCandidates[i].node
			end
			local addOverride, tattooByBaseId = makeTattooNearestOverrideForNodes(nearestNodes, tattoo)
			if isRunegraftOption then
				removeAllocatedRunegrafts(addOverride, allocatedRunegrafts)
			end
			local nearestNodeKey = { }
			for _, node in ipairs(nearestNodes) do
				t_insert(nearestNodeKey, tostring(node.id))
			end
			t_sort(nearestNodeKey)
			local output, assumedEnemyConditions = calculateCandidate(
				addOverride,
				"tattooNearestNode:" .. tattooId .. ":" .. count .. ":" .. t_concat(nearestNodeKey, ",")
			)
			local pathOverride, pathDist = makeTattooNearestPathOverride(nearestNodes, tattooByBaseId)
			if isRunegraftOption then
				removeAllocatedRunegrafts(pathOverride, allocatedRunegrafts)
			end
			local pathOutput, pathAssumedEnemyConditions = calculateCandidate(
				pathOverride,
				"tattooNearestPath:" .. tattooId .. ":" .. count .. ":" .. t_concat(nearestNodeKey, ",")
			)
			local nearestSingleStat = calculatePowerScore(output)
			local firstNode = nearestNodes[1]
			local countLabel = count > 1 and (" x" .. count) or ""
			t_insert(powerTattooOptions, {
				baseNodeId = firstNode.id,
				baseNodeName = firstNode.dn,
				baseNodeX = firstNode.x,
				baseNodeY = firstNode.y,
				tattooName = tattoo.dn,
				displayName = tattoo.dn .. " (" .. categoryLabel .. countLabel .. ", nearest)",
				stats = tattoo.sd,
				singleStat = nearestSingleStat,
				pathPower = calculatePowerScore(pathOutput),
				pathDist = pathDist,
				allocated = false,
				isRunegraft = isRunegraftOption,
				tattooCategory = category,
				assumedEnemyConditions = assumedEnemyConditions,
				pathAssumedEnemyConditions = pathAssumedEnemyConditions,
			})
			if maxTattooCount > 1 and count == 1 and (nearestSingleStat or 0) <= 0 then
				break
			end
		end
	end

	return powerTattooOptions
end

return powerReportTattooEvaluator
