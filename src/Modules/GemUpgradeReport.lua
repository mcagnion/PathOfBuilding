-- Path of Building
--
-- Module: Gem Upgrade Report
-- Builds gem upgrade report rows for the Skills tab.
--

local ipairs = ipairs
local t_insert = table.insert
local t_sort = table.sort
local m_abs = math.abs
local m_floor = math.floor
local m_max = math.max
local s_format = string.format
local co_running = coroutine.running
local co_yield = coroutine.yield

local alternateGemQualityPrefixMap = {
	Default = "",
	Alternate1 = "Anomalous ",
	Alternate2 = "Divergent ",
	Alternate3 = "Phantasmal ",
}

local imbuedCoinLabelByColor = {
	[1] = "CoinOfPower",
	[2] = "CoinOfSkill",
	[3] = "CoinOfKnowledge",
}

local imbuedCoinSortOrder = {
	CoinOfKnowledge = 1,
	CoinOfPower = 2,
	CoinOfSkill = 3,
}

local gemUpgradeReport = { }

local function advanceBuildState(buildState)
	if not buildState then
		return
	end
	buildState.completedGroups = (buildState.completedGroups or 0) + 1
	local batchSize = buildState.batchSize or 1
	if buildState.completedGroups % batchSize == 0 and co_running() then
		co_yield()
	end
end

local function getOutputAttr(skillsTab, output, stat)
	if output and output[stat] ~= nil then
		return output[stat]
	end
	local mainOutput = skillsTab.build and skillsTab.build.calcsTab and skillsTab.build.calcsTab.mainOutput
	if mainOutput and mainOutput[stat] ~= nil then
		return mainOutput[stat]
	end
	return 0
end

local function isLevelUpgradeUsable(skillsTab, gemInstance, grantedEffect, targetLevel, output)
	if not (gemInstance and gemInstance.gemData and grantedEffect and targetLevel) then
		return false
	end
	local levelData = grantedEffect.levels and grantedEffect.levels[targetLevel]
	if not levelData then
		return false
	end

	local reqLevel = levelData.levelRequirement or 1
	local characterLevel = skillsTab.build.characterLevel or 1
	if reqLevel > characterLevel then
		return false
	end

	local reqStr = calcLib.getGemStatRequirement(reqLevel, grantedEffect.support, gemInstance.gemData.reqStr)
	local reqDex = calcLib.getGemStatRequirement(reqLevel, grantedEffect.support, gemInstance.gemData.reqDex)
	local reqInt = calcLib.getGemStatRequirement(reqLevel, grantedEffect.support, gemInstance.gemData.reqInt)
	if gemInstance.reqOverride then
		reqStr = gemInstance.reqOverride
		reqDex = gemInstance.reqOverride
		reqInt = gemInstance.reqOverride
	end

	local modDB = skillsTab.build and skillsTab.build.calcsTab and skillsTab.build.calcsTab.mainEnv and skillsTab.build.calcsTab.mainEnv.modDB
	if modDB and modDB:Flag(nil, "OmniscienceRequirements") then
		local omniSatisfy = modDB:Sum("INC", nil, "OmniAttributeRequirements")
		if not omniSatisfy or omniSatisfy == 0 then
			omniSatisfy = 100
		end
		local highestReq = m_max(reqStr or 0, m_max(reqDex or 0, reqInt or 0))
		local omniReq = m_floor(highestReq * (100 / omniSatisfy))
		return omniReq <= getOutputAttr(skillsTab, output, "Omni")
	end

	return (reqStr or 0) <= getOutputAttr(skillsTab, output, "Str")
		and (reqDex or 0) <= getOutputAttr(skillsTab, output, "Dex")
		and (reqInt or 0) <= getOutputAttr(skillsTab, output, "Int")
end

local function isRowAllowedByFilters(reportRow, filters)
	if not filters then
		return true
	end
	if filters.impact == "POSITIVE" and reportRow.score <= 0 then
		return false
	end
	if filters.source and filters.source ~= "ALL" and reportRow.sourceType ~= filters.source then
		return false
	end
	if filters.gemType and filters.gemType ~= "ALL" and reportRow.gemCategory ~= filters.gemType then
		return false
	end
	return true
end

local function getDisplayStat(build, currentStat)
	for _, displayStat in ipairs(build.displayStats) do
		if displayStat.stat == currentStat.stat then
			return displayStat
		end
	end
	return { fmt = ".1f" }
end

local function getStatValue(output, currentStat)
	local statValue = output[currentStat.stat]
	if statValue == nil and output.Minion then
		statValue = output.Minion[currentStat.stat]
	end
	if statValue == nil then
		statValue = 0
	end
	if currentStat.transform then
		statValue = currentStat.transform(statValue)
	end
	return statValue
end

local function formatDelta(delta, displayStat, lowerIsBetter)
	local deltaValue = delta * ((displayStat.pc or displayStat.mod) and 100 or 1)
	local deltaStr = s_format("%+" .. displayStat.fmt, deltaValue)
	local number, suffix = deltaStr:match("^([%+%-]?%d+%.%d+)(%D*)$")
	if number then
		deltaStr = number:gsub("0+$", ""):gsub("%.$", "") .. suffix
	end
	deltaStr = formatNumSep(deltaStr)
	if (delta > 0 and not lowerIsBetter) or (delta < 0 and lowerIsBetter) then
		return colorCodes.POSITIVE .. deltaStr
	elseif delta ~= 0 then
		return colorCodes.NEGATIVE .. deltaStr
	end
	return "^7" .. deltaStr
end

local function isReportableImbuedSupportGem(gemData)
	if not (gemData and gemData.grantedEffect and gemData.grantedEffect.support) then
		return false
	end
	-- 3.28 imbues should not suggest legacy awakened-only supports.
	if gemData.tags and gemData.tags.awakened then
		return false
	end
	return gemData.grantedEffect.levels and gemData.grantedEffect.levels[1] ~= nil
end

local function slotHasOtherImbuedGem(skillsTab, slotName, sourceGroup, sourceGemIndex)
	if not slotName then
		return false
	end
	for _, socketGroup in ipairs(skillsTab.socketGroupList) do
		if socketGroup.slot == slotName then
			for gemIndex, gemInstance in ipairs(socketGroup.gemList) do
				if not (socketGroup == sourceGroup and gemIndex == sourceGemIndex) and gemInstance.imbuedSupport and gemInstance.imbuedSupport ~= "" then
					return true
				end
			end
		end
	end
	return false
end

local function getGemActiveSkills(socketGroup, gemInstance)
	local activeSkills = { }
	for _, activeSkill in ipairs(socketGroup.displaySkillList or {}) do
		if activeSkill.activeEffect and activeSkill.activeEffect.srcInstance == gemInstance then
			t_insert(activeSkills, activeSkill)
		end
	end
	return activeSkills
end

local function getUpgradePreviewValue(upgradeLabel, nextValue)
	if upgradeLabel == "CoinOfKnowledge" or upgradeLabel == "CoinOfPower" or upgradeLabel == "CoinOfSkill" then
		return "Lvl 1 " .. tostring(nextValue)
	end
	return nextValue
end

local function getUpgradeDisplayLabel(sourceType, upgradeLabel)
	if upgradeLabel == "Lvl" then
		if sourceType == "CORRUPTION" then
			return "Corrupt (Vaal Orb)"
		end
		return "Level Up"
	end
	if upgradeLabel == "Qual" then
		if sourceType == "CORRUPTION" then
			return "Corrupt (Vaal Orb)"
		end
		return "Quality Upgrade"
	end
	if upgradeLabel == "21/23" then
		return "Double Corrupt (Locus)"
	end
	if upgradeLabel == "Recipe" then
		return "GCP Recipe"
	end
	if upgradeLabel == "CoinOfKnowledge" then
		return "Coin of Knowledge"
	end
	if upgradeLabel == "CoinOfPower" then
		return "Coin of Power"
	end
	if upgradeLabel == "CoinOfSkill" then
		return "Coin of Skill"
	end
	return upgradeLabel
end

local function getImbuedCoinLabel(gemData)
	local grantedEffect = gemData and gemData.grantedEffect
	if grantedEffect and imbuedCoinLabelByColor[grantedEffect.color] then
		return imbuedCoinLabelByColor[grantedEffect.color]
	end
	if gemData and gemData.tags then
		if gemData.tags.intelligence then
			return "CoinOfKnowledge"
		elseif gemData.tags.strength then
			return "CoinOfPower"
		elseif gemData.tags.dexterity then
			return "CoinOfSkill"
		end
	end
	return nil
end

function gemUpgradeReport.Build(skillsTab, currentStat, filters, buildState)
	local report = buildState and buildState.report or { }
	if not (currentStat and currentStat.stat) then
		return report
	end
	if buildState then
		buildState.report = report
		buildState.totalGroups = #skillsTab.socketGroupList
	end

	local calcFunc, calcBase = skillsTab.build.calcsTab:GetMiscCalculator()
	if not calcFunc or not calcBase then
		return report
	end

	local displayStat = getDisplayStat(skillsTab.build, currentStat)
	local lowerIsBetter = displayStat.lowerIsBetter or currentStat.lowerIsBetter
	local useFullDPS = currentStat.stat == "FullDPS"
	local baseValue = getStatValue(calcBase, currentStat)
	local maxQuality = 23

	local function addUpgradeRow(gemType, gemCategory, sourceType, upgradeLabel, name, groupLabel, currentValue, nextValue, curSort, nextSort, output, socketGroup, gemIndex, targetLevel, targetQuality, targetImbuedSupport)
		local upgradedValue = getStatValue(output, currentStat)
		local delta = upgradedValue - baseValue
		local score = lowerIsBetter and -delta or delta
		local currentGem = socketGroup and socketGroup.gemList and socketGroup.gemList[gemIndex]
		local currentState = currentGem and currentGem.level and s_format("%d/%d", currentGem.level or 0, m_max(0, currentGem.quality or 0)) or tostring(currentValue)
		local improvementPct = 0
		local hasImprovementPct = false
		if baseValue ~= 0 then
			hasImprovementPct = true
			improvementPct = score / m_abs(baseValue) * 100
		end

		local reportRow = {
			type = gemType,
			gemCategory = gemCategory,
			sourceType = sourceType,
			upgradeLabel = getUpgradeDisplayLabel(sourceType, upgradeLabel),
			name = name,
			groupLabel = groupLabel,
			currentState = currentState,
			level = currentValue,
			nextLevel = getUpgradePreviewValue(upgradeLabel, nextValue),
			curSort = curSort,
			nextSort = nextSort,
			delta = delta,
			deltaStr = formatDelta(delta, displayStat, lowerIsBetter),
			score = score,
			improvementPct = improvementPct,
			hasImprovementPct = hasImprovementPct,
			socketGroup = socketGroup,
			gemIndex = gemIndex,
			targetLevel = targetLevel,
			targetQuality = targetQuality,
			targetImbuedSupport = targetImbuedSupport,
			useFullDPS = useFullDPS,
		}
		if isRowAllowedByFilters(reportRow, filters) then
			t_insert(report, reportRow)
		end
	end

	for groupIndex, socketGroup in ipairs(skillsTab.socketGroupList) do
		skillsTab:ProcessSocketGroup(socketGroup)
		local groupEnabled = socketGroup.enabled and socketGroup.slotEnabled ~= false

		for gemIndex, gemInstance in ipairs(socketGroup.gemList) do
			local grantedEffect = gemInstance.grantedEffect or (gemInstance.gemData and gemInstance.gemData.grantedEffect)
			local maxLevel = 0
			if gemInstance.gemData and grantedEffect then
				maxLevel = gemInstance.gemData.naturalMaxLevel or 0
				-- Exceptional line gems do not get the generic +1 corrupted level step.
				if not grantedEffect.plusVersionOf then
					maxLevel = maxLevel + 1
				end
			end

			local currentLevel = gemInstance.level or 0
			if gemInstance.gemData and grantedEffect and gemInstance.enabled and groupEnabled then
				local gemType = grantedEffect.support and "Support" or (grantedEffect.hasGlobalEffect and "Global" or "Active")
				local gemCategory = grantedEffect.support and "SUPPORT" or "ACTIVE"
				local gemName = (alternateGemQualityPrefixMap[gemInstance.qualityId or "Default"] or "") .. gemInstance.nameSpec
				local groupLabel = socketGroup.displayLabel or socketGroup.label or ("Socket Group " .. groupIndex)
				local currentQuality = m_max(0, gemInstance.quality or 0)
				local naturalMaxLevel = gemInstance.gemData.naturalMaxLevel or 0
				local isCorrupted = gemInstance.corrupted == true or currentLevel > naturalMaxLevel or currentQuality > 20

				if currentLevel > 0 and currentLevel < maxLevel then
					local nextLevel = currentLevel + 1
					if grantedEffect.levels[nextLevel] then
						gemInstance.level = nextLevel
						local errMsg, output = PCall(calcFunc, nil, useFullDPS)
						gemInstance.level = currentLevel
						if not errMsg and isLevelUpgradeUsable(skillsTab, gemInstance, grantedEffect, nextLevel, output) then
							addUpgradeRow(
								gemType,
								gemCategory,
								nextLevel <= naturalMaxLevel and "NATURAL" or "CORRUPTION",
								"Lvl",
								gemName,
								groupLabel,
								s_format("%d/%d", currentLevel, currentQuality),
								s_format("%d/%d", nextLevel, currentQuality),
								currentLevel * 100 + currentQuality,
								nextLevel * 100 + currentQuality,
								output,
								socketGroup,
								gemIndex,
								nextLevel,
								currentQuality
							)
						end
					end
				end

				if not isCorrupted and currentQuality < maxQuality then
					local nextQuality
					local nextOutput
					if currentQuality < 20 then
						for candidateQuality = currentQuality + 1, 20 do
							gemInstance.quality = candidateQuality
							local errMsg, output = PCall(calcFunc, nil, useFullDPS)
							gemInstance.quality = currentQuality
							if not errMsg then
								if not nextQuality then
									nextQuality = candidateQuality
									nextOutput = output
								end
								local delta = getStatValue(output, currentStat) - baseValue
								if delta ~= 0 then
									nextQuality = candidateQuality
									nextOutput = output
									break
								end
							end
						end
					else
						nextQuality = 23
						gemInstance.quality = nextQuality
						local errMsg, output = PCall(calcFunc, nil, useFullDPS)
						gemInstance.quality = currentQuality
						if not errMsg then
							nextOutput = output
						end
					end
					if nextQuality and nextOutput then
						addUpgradeRow(
							gemType,
							gemCategory,
							nextQuality <= 20 and "NATURAL" or "CORRUPTION",
							"Qual",
							gemName,
							groupLabel,
							s_format("%d/%d", currentLevel, currentQuality),
							s_format("%d/%d", currentLevel, nextQuality),
							currentLevel * 100 + currentQuality,
							currentLevel * 100 + nextQuality,
							nextOutput,
							socketGroup,
							gemIndex,
							currentLevel,
							nextQuality
						)
					end
				end

				if not isCorrupted and maxLevel == 21 and currentLevel == naturalMaxLevel and currentQuality == 20 then
					gemInstance.level = 21
					gemInstance.quality = 23
					local errMsg, output = PCall(calcFunc, nil, useFullDPS)
					gemInstance.level = currentLevel
					gemInstance.quality = currentQuality
					if not errMsg and isLevelUpgradeUsable(skillsTab, gemInstance, grantedEffect, 21, output) then
						addUpgradeRow(
							gemType,
							gemCategory,
							"CORRUPTION",
							"21/23",
							gemName,
							groupLabel,
							s_format("%d/%d", currentLevel, currentQuality),
							"21/23",
							currentLevel * 100 + currentQuality,
							2123,
							output,
							socketGroup,
							gemIndex,
							21,
							23
						)
					end
				end

				if not isCorrupted and grantedEffect.support and currentLevel == 20 and currentQuality == 0 and grantedEffect.levels[1] then
					gemInstance.level = 1
					gemInstance.quality = 20
					local errMsg, output = PCall(calcFunc, nil, useFullDPS)
					gemInstance.level = currentLevel
					gemInstance.quality = currentQuality
					if not errMsg then
						addUpgradeRow(
							gemType,
							gemCategory,
							"RECIPE",
							"Recipe",
							gemName,
							groupLabel,
							s_format("%d/%d", currentLevel, currentQuality),
							"1/20",
							currentLevel * 100 + currentQuality,
							120,
							output,
							socketGroup,
							gemIndex,
							1,
							20
						)
					end
				end

				if gemCategory == "ACTIVE"
					and not isCorrupted
					and currentLevel == 20
					and socketGroup.slot
					and not (gemInstance.imbuedSupport and gemInstance.imbuedSupport ~= "")
					and not slotHasOtherImbuedGem(skillsTab, socketGroup.slot, socketGroup, gemIndex) then
					local activeSkills = getGemActiveSkills(socketGroup, gemInstance)
					if #activeSkills > 0 then
						local imbuedSupportEntries = { }
						for _, supportGemData in pairs(skillsTab.build.data.gems) do
							local supportGrantedEffect = supportGemData.grantedEffect
							if isReportableImbuedSupportGem(supportGemData) then
								local coinLabel = getImbuedCoinLabel(supportGemData)
								local canSupportGem = false
								for _, activeSkill in ipairs(activeSkills) do
									if calcLib.canGrantedEffectSupportActiveSkill(supportGrantedEffect, activeSkill) then
										canSupportGem = true
										break
									end
								end
								if coinLabel and canSupportGem then
									gemInstance.imbuedSupport = supportGemData.grantedEffectId
									local errMsg, output = PCall(calcFunc, nil, useFullDPS)
									gemInstance.imbuedSupport = ""
									if not errMsg then
										local score = lowerIsBetter and -(getStatValue(output, currentStat) - baseValue) or (getStatValue(output, currentStat) - baseValue)
										t_insert(imbuedSupportEntries, {
											coinLabel = coinLabel,
											gemData = supportGemData,
											output = output,
											score = score,
										})
									end
								end
							end
						end
						t_sort(imbuedSupportEntries, function(a, b)
							local coinOrderA = imbuedCoinSortOrder[a.coinLabel] or 999
							local coinOrderB = imbuedCoinSortOrder[b.coinLabel] or 999
							if coinOrderA ~= coinOrderB then
								return coinOrderA < coinOrderB
							end
							if a.score ~= b.score then
								return a.score > b.score
							end
							return a.gemData.name < b.gemData.name
						end)
						for _, imbuedSupportEntry in ipairs(imbuedSupportEntries) do
							addUpgradeRow(
								gemType,
								gemCategory,
								"IMBUED",
								imbuedSupportEntry.coinLabel,
								gemName,
								groupLabel,
								"None",
								imbuedSupportEntry.gemData.name,
								0,
								imbuedSupportEntry.gemData.name,
								imbuedSupportEntry.output,
								socketGroup,
								gemIndex,
								currentLevel,
								currentQuality,
								imbuedSupportEntry.gemData.grantedEffectId
							)
						end
					end
				end
			end
		end
		advanceBuildState(buildState)
	end

	return report
end

function gemUpgradeReport.Filter(report, filters)
	local filteredReport = { }
	for _, row in ipairs(report or {}) do
		if isRowAllowedByFilters(row, filters) then
			t_insert(filteredReport, row)
		end
	end
	return filteredReport
end

return gemUpgradeReport
