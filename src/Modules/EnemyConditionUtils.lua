-- Path of Building
--
-- Module: Enemy Condition Utils
-- Shared helpers for enemy-condition assumptions, source formatting, and list operations.
--

local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_sort = table.sort
local t_concat = table.concat
local tonumber = tonumber

local enemyConditionUtils = { }

function enemyConditionUtils.formatConditionSource(build, source, sourceLabels)
	if not source then
		return source
	end
	if sourceLabels and sourceLabels[source] then
		return sourceLabels[source]
	end
	local sourceType = source:match("[^:]+")
	if sourceType == "Tree" then
		local nodeId = source:match("Tree:(%d+)")
		if nodeId then
			local nodeIdNumber = tonumber(nodeId)
			local node = build.spec.nodes[nodeIdNumber]
				or build.spec.tree.nodes[nodeIdNumber]
				or (
					build.latestTree
					and build.latestTree.nodes
					and build.latestTree.nodes[nodeIdNumber]
				)
			if node and node.dn then
				return "Tree: " .. StripEscapes(node.dn)
			end
		end
		local tattooNodeId = source:match("Tree:(%w+)")
		local tattooMap = build.spec.tree
			and build.spec.tree.tattoo
			and build.spec.tree.tattoo.idMap
		if tattooNodeId and tattooMap and tattooMap[tattooNodeId] then
			return "Tree: " .. StripEscapes(tattooMap[tattooNodeId])
		end
	elseif sourceType == "Item" then
		local itemId = source:match("Item:(%d+):.+")
		local item = itemId and build.itemsTab.items[tonumber(itemId)]
		if item and item.name then
			return "Item: " .. StripEscapes(item.name)
		end
	elseif sourceType == "Skill" then
		local skillId = source:match("Skill:(.+)")
		local skill = skillId and build.data.skills[skillId]
		if skill and skill.name then
			return "Skill: " .. StripEscapes(skill.name)
		end
	elseif sourceType == "Pantheon" then
		local godName = source:match("Pantheon:(.+)")
		if godName then
			return "Pantheon: " .. StripEscapes(godName)
		end
	end
	return source
end

function enemyConditionUtils.collectConditionSources(build, mods, sourceLabels)
	local sourceSeen = { }
	local sourceList = { }
	for _, mod in ipairs(mods or { }) do
		local source = mod and enemyConditionUtils.formatConditionSource(build, mod.source, sourceLabels)
		if source and source ~= "Base" and not sourceSeen[source] then
			sourceSeen[source] = true
			t_insert(sourceList, source)
		end
	end
	t_sort(sourceList)
	return sourceList
end

function enemyConditionUtils.buildEnemyConditionSourceMap(build, enemyConditionsUsed, sourceLabels)
	local sourceMap = { }
	for condition, mods in pairs(enemyConditionsUsed or { }) do
		local sourceList = enemyConditionUtils.collectConditionSources(build, mods, sourceLabels)
		if #sourceList > 0 then
			sourceMap[condition] = sourceList
		end
	end
	return sourceMap
end

function enemyConditionUtils.conditionKey(conditionList)
	return conditionList and t_concat(conditionList, ",") or ""
end

function enemyConditionUtils.unionConditionLists(...)
	local set = { }
	for i = 1, select("#", ...) do
		local list = select(i, ...)
		if list then
			for _, condition in ipairs(list) do
				set[condition] = true
			end
		end
	end
	if not next(set) then
		return nil
	end
	local out = { }
	for condition in pairs(set) do
		t_insert(out, condition)
	end
	t_sort(out)
	return out
end

function enemyConditionUtils.subtractConditionLists(conditionList, baseConditionList)
	if not conditionList then
		return nil
	end
	local baseSet = { }
	for _, condition in ipairs(baseConditionList or { }) do
		baseSet[condition] = true
	end
	local seen = { }
	local out = { }
	for _, condition in ipairs(conditionList) do
		if not baseSet[condition] and not seen[condition] then
			seen[condition] = true
			t_insert(out, condition)
		end
	end
	if #out == 0 then
		return nil
	end
	t_sort(out)
	return out
end

return enemyConditionUtils
