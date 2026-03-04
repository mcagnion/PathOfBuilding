-- Path of Building
--
-- Module: Power Report Builder
-- Builds the Tree power report list from current power calculations.
--

local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert
local t_sort = table.sort
local t_concat = table.concat
local m_abs = math.abs
local s_format = string.format

local enemyConditionUtils = LoadModule("Modules/EnemyConditionUtils")
local powerReportUtils = LoadModule("Modules/PowerReportUtils")

local powerReportBuilder = { }

function powerReportBuilder.build(treeTab, currentStat)
	local report = {}
	local includeMasteries = treeTab.includePowerReportMasteries
	local includeTattoos = treeTab.includePowerReportTattoos
	local includeRunegrafts = treeTab.includePowerReportRunegrafts
	local includeNormals = treeTab.includePowerReportNormals
	local includeNotables = treeTab.includePowerReportNotables
	local includeKeystones = treeTab.includePowerReportKeystones

	if not (currentStat and currentStat.stat) then
		return report
	end

	local displayStat
	for _, ds in ipairs(treeTab.build.displayStats) do
		if ds.stat == currentStat.stat then
			displayStat = ds
			break
		end
	end
	if not displayStat then
		displayStat = {
			fmt = ".1f"
		}
	end

	local statScale = (displayStat.pc or displayStat.mod) and 100 or 1
	local ascendancyContext = powerReportUtils.makeAscendancyContext(treeTab.build.spec)
	local includeAscendancyOptions = {
		includePowerReportBloodlineAscendancy = treeTab.includePowerReportBloodlineAscendancy,
		includePowerReportAscNotables = treeTab.includePowerReportAscNotables,
		includePowerReportAscKeystones = treeTab.includePowerReportAscKeystones,
		includePowerReportAscSmalls = treeTab.includePowerReportAscSmalls,
		includePowerReportForbiddenAscendancy = treeTab.includePowerReportForbiddenAscendancy,
	}
	local function isRunegraftName(name)
		return powerReportUtils.isRunegraftName(name)
	end
	local function isForbiddenAscendancyNode(node)
		return powerReportUtils.isForbiddenAscendancyNode(
			ascendancyContext,
			includeAscendancyOptions,
			node
		)
	end
	local function isIncludedAscendancyNode(node)
		return powerReportUtils.isIncludedAscendancyNode(
			ascendancyContext,
			includeAscendancyOptions,
			node
		)
	end
	local function formatSinglePowerValue(power)
		local powerStr = s_format("%"..displayStat.fmt, power)
		powerStr = formatNumSep(powerStr)
		if (power > 0 and not displayStat.lowerIsBetter) or (power < 0 and displayStat.lowerIsBetter) then
			powerStr = colorCodes.POSITIVE .. powerStr
		elseif (power < 0 and not displayStat.lowerIsBetter) or (power > 0 and displayStat.lowerIsBetter) then
			powerStr = colorCodes.NEGATIVE .. powerStr
		end
		return powerStr
	end
	local function formatPowerValues(nodePower, pathPower)
		return formatSinglePowerValue(nodePower), formatSinglePowerValue(pathPower)
	end
	local function reportTattooType(category)
		return powerReportUtils.reportTattooType(category)
	end
	local function reportNodeType(node, isForbiddenNode)
		return powerReportUtils.reportNodeType(node, isForbiddenNode)
	end
	local enemyConditionSourceMap = enemyConditionUtils.buildEnemyConditionSourceMap(
		treeTab.build,
		treeTab.build.calcsTab.mainEnv.enemyConditionsUsed
	)
	local basePowerValue = treeTab.build.calcsTab.powerBaseStatValue
	local function formatPercentPowerValue(power)
		if not basePowerValue or basePowerValue == 0 then
			return nil, "--"
		end
		local powerPct = power / m_abs(basePowerValue) * 100
		local powerPctStr = s_format("%+.2f%%", powerPct)
		if (powerPct > 0 and not displayStat.lowerIsBetter) or (powerPct < 0 and displayStat.lowerIsBetter) then
			powerPctStr = colorCodes.POSITIVE .. powerPctStr
		elseif (powerPct < 0 and not displayStat.lowerIsBetter) or (powerPct > 0 and displayStat.lowerIsBetter) then
			powerPctStr = colorCodes.NEGATIVE .. powerPctStr
		end
		return powerPct, powerPctStr
	end
	local baseAssumedEnemyConditions =
		treeTab.build.calcsTab.powerBaseAssumedEnemyConditions

	for nodeId, node in pairs(treeTab.build.spec.nodes) do
		local isAlloc = node.alloc or treeTab.build.calcsTab.mainEnv.grantedPassives[nodeId]
		local isForbiddenNode = (not isAlloc) and isForbiddenAscendancyNode(node)
		local isNormalNode = node.type == "Normal"
		local isNotableNode = node.type == "Notable"
		local isKeystoneNode = node.type == "Keystone"
		local isAscendancyNode = node.ascendancyName ~= nil
		local isRegularNode = (isNormalNode or isNotableNode or isKeystoneNode) and (
			isAscendancyNode
			or (isNormalNode and includeNormals)
			or (isNotableNode and includeNotables)
			or (isKeystoneNode and includeKeystones)
		)
		local isRunegraftMasteryNode = node.type == "Mastery" and node.isTattoo and isRunegraftName(node.dn)
		local isTattooMasteryNode = node.type == "Mastery" and node.isTattoo and not isRunegraftMasteryNode
		local isMasteryNode = node.type == "Mastery" and (
			includeMasteries
			or (includeTattoos and isTattooMasteryNode)
			or (includeRunegrafts and isRunegraftMasteryNode)
		)
		local includeNode = (isRegularNode or isMasteryNode)
			and node.type ~= "ClassStart"
			and node.type ~= "AscendClassStart"
			and isIncludedAscendancyNode(node)
		if includeNode then
			local pathDist
			if isAlloc then
				pathDist = #(node.depends or { }) == 0 and 1 or #node.depends
			elseif isForbiddenNode then
				pathDist = 1
			else
				pathDist = #(node.path or { }) == 0 and 1 or #node.path
			end
			local masteryOptions = isMasteryNode and node.power and node.power.masteryOptions
			if masteryOptions and #masteryOptions > 0 then
				for _, option in ipairs(masteryOptions) do
					local nodePower = (option.singleStat or 0) * statScale
					local pathPower = (option.pathPower or 0) / pathDist * statScale
					local nodePowerStr, pathPowerStr = formatPowerValues(nodePower, pathPower)
					local nodePowerPct, nodePowerPctStr = formatPercentPowerValue(nodePower)
					local pathPowerPct, pathPowerPctStr = formatPercentPowerValue(pathPower)
					local optionLabel = option.sd and t_concat(option.sd, " / ") or "Mastery Option"
					t_insert(report, {
						name = node.dn .. ": " .. optionLabel,
						power = nodePower,
						powerStr = nodePowerStr,
						powerPercent = nodePowerPct,
						powerPercentStr = nodePowerPctStr,
						pathPower = pathPower,
						pathPowerStr = pathPowerStr,
						pathPowerPercent = pathPowerPct,
						pathPowerPercentStr = pathPowerPctStr,
						stats = option.sd,
						assumedEnemyConditions = option.assumedEnemyConditions,
						pathAssumedEnemyConditions = option.pathAssumedEnemyConditions,
						baseAssumedEnemyConditions = baseAssumedEnemyConditions,
						enemyConditionSourceMap = enemyConditionSourceMap,
						allocated = isAlloc,
						id = node.id,
						x = node.x,
						y = node.y,
						type = reportNodeType(node, isForbiddenNode),
						pathDist = pathDist
					})
				end
			else
				local nodePower = (node.power.singleStat or 0) * statScale
				local pathPower
				if isForbiddenNode then
					pathPower = (node.power.singleStat or 0) / pathDist * statScale
				else
					pathPower = (node.power.pathPower or 0) / pathDist * statScale
				end
				local nodePowerStr, pathPowerStr = formatPowerValues(nodePower, pathPower)
				local pathPowerPct, pathPowerPctStr = formatPercentPowerValue(pathPower)
				local nodePowerPct, nodePowerPctStr = formatPercentPowerValue(nodePower)
				local reportStats = (isMasteryNode and node.power and node.power.masteryEffectSd) or node.sd
				t_insert(report, {
					name = node.dn,
					power = nodePower,
					powerStr = nodePowerStr,
					powerPercent = nodePowerPct,
					powerPercentStr = nodePowerPctStr,
					pathPower = pathPower,
					pathPowerStr = pathPowerStr,
					pathPowerPercent = pathPowerPct,
					pathPowerPercentStr = pathPowerPctStr,
					stats = reportStats,
					assumedEnemyConditions = node.power.assumedEnemyConditions,
					pathAssumedEnemyConditions = node.power.pathAssumedEnemyConditions,
					baseAssumedEnemyConditions = baseAssumedEnemyConditions,
					enemyConditionSourceMap = enemyConditionSourceMap,
					allocated = isAlloc,
					id = node.id,
					x = node.x,
					y = node.y,
					type = reportNodeType(node, isForbiddenNode),
					pathDist = pathDist
				})
			end
		end
	end

	for _, node in pairs(treeTab.build.spec.tree.clusterNodeMap) do
		local isAlloc = node.alloc
		if not isAlloc then
			local nodePower = (node.power and node.power.singleStat or 0) * statScale
			local nodePowerStr = formatSinglePowerValue(nodePower)
			local nodePowerPct, nodePowerPctStr = formatPercentPowerValue(nodePower)
			t_insert(report, {
				name = node.dn,
				power = nodePower,
				powerStr = nodePowerStr,
				powerPercent = nodePowerPct,
				powerPercentStr = nodePowerPctStr,
				pathPower = 0,
				pathPowerStr = "--",
				pathPowerPercent = nil,
				pathPowerPercentStr = "--",
				stats = node.sd,
				assumedEnemyConditions = node.power and node.power.assumedEnemyConditions,
				baseAssumedEnemyConditions = baseAssumedEnemyConditions,
				enemyConditionSourceMap = enemyConditionSourceMap,
				id = node.id,
				type = reportNodeType(node, false),
				pathDist = "Cluster",
				cluster = true
			})
		end
	end

	for _, tattooOption in ipairs(treeTab.build.calcsTab.powerTattooOptions or { }) do
		local tattooName = tattooOption.tattooName or "Tattoo"
		local isRunegraftOption = tattooOption.isRunegraft or isRunegraftName(tattooName)
		local includeOption = (isRunegraftOption and includeRunegrafts)
			or ((not isRunegraftOption) and includeTattoos)
		if includeOption then
			local tattooPower = (tattooOption.singleStat or 0) * statScale
			local tattooPowerStr = formatSinglePowerValue(tattooPower)
			local tattooPowerPct, tattooPowerPctStr = formatPercentPowerValue(tattooPower)
			local pathDist = tattooOption.pathDist
			local pathPower = tattooOption.pathPower
			local pathPowerStr = "--"
			local pathPowerPct, pathPowerPctStr = nil, "--"
			if type(pathDist) == "number" and pathDist > 0 and pathPower then
				pathPower = pathPower / pathDist * statScale
				pathPowerStr = formatSinglePowerValue(pathPower)
				pathPowerPct, pathPowerPctStr = formatPercentPowerValue(pathPower)
			else
				pathPower = 0
			end
			local displayName = tattooOption.displayName
				or (tattooName .. " (" .. (tattooOption.baseNodeName or "node") .. ")")
			t_insert(report, {
				name = displayName,
				power = tattooPower,
				powerStr = tattooPowerStr,
				powerPercent = tattooPowerPct,
				powerPercentStr = tattooPowerPctStr,
				pathPower = pathPower,
				pathPowerStr = pathPowerStr,
				pathPowerPercent = pathPowerPct,
				pathPowerPercentStr = pathPowerPctStr,
				stats = tattooOption.stats,
				assumedEnemyConditions = tattooOption.assumedEnemyConditions,
				pathAssumedEnemyConditions = tattooOption.pathAssumedEnemyConditions,
				baseAssumedEnemyConditions = baseAssumedEnemyConditions,
				enemyConditionSourceMap = enemyConditionSourceMap,
				allocated = tattooOption.allocated,
				id = tattooOption.baseNodeId,
				x = tattooOption.baseNodeX,
				y = tattooOption.baseNodeY,
				type = isRunegraftOption and "Runegraft" or reportTattooType(tattooOption.tattooCategory),
				pathDist = pathDist,
				alwaysShow = true,
				cluster = false
			})
		end
	end

	if displayStat.lowerIsBetter then
		t_sort(report, function (a,b)
			return a.power < b.power
		end)
	else
		t_sort(report, function (a,b)
			return a.power > b.power
		end)
	end

	return report
end

return powerReportBuilder
