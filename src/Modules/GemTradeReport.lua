-- Path of Building
--
-- Module: Gem Trade Report
-- Builds replacement-gem report rows for the Skills tab.
--

local ipairs = ipairs
local t_insert = table.insert
local m_abs = math.abs
local m_floor = math.floor
local m_max = math.max
local m_min = math.min
local s_format = string.format
local co_running = coroutine.running
local co_yield = coroutine.yield

local alternateGemQualityPrefixMap = {
	Default = "",
	Alternate1 = "Anomalous ",
	Alternate2 = "Divergent ",
	Alternate3 = "Phantasmal ",
}

local gemTradeReport = { }

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

local function isLevelUsable(skillsTab, gemInstance, grantedEffect, targetLevel, output)
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

local function getStatValue(output, currentStat, build)
	if currentStat.getValue then
		return currentStat.getValue(output, build) or 0
	end
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

local function addDistinctValue(list, seen, value)
	if value == nil or seen[value] then
		return
	end
	seen[value] = true
	t_insert(list, value)
end

local function getTradeGemNameSpec(gemData, nameSpec)
	if gemData and gemData.grantedEffect and gemData.grantedEffect.support then
		return (nameSpec or gemData.name) .. " Support"
	end
	return nameSpec or (gemData and gemData.name) or ""
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
	for _, activeSkill in ipairs(socketGroup.displaySkillList or { }) do
		if activeSkill.activeEffect and activeSkill.activeEffect.srcInstance == gemInstance then
			t_insert(activeSkills, activeSkill)
		end
	end
	return activeSkills
end

function gemTradeReport.Build(skillsTab, currentStat, filters, buildState)
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
	local build = skillsTab.build
	local baseValue = getStatValue(calcBase, currentStat, build)

	-- Pre-filter imbued support gems once instead of scanning data.gems per active gem.
	local reportableImbuedSupports = { }
	for _, gemData in pairs(build.data.gems) do
		if isReportableImbuedSupportGem(gemData) then
			t_insert(reportableImbuedSupports, gemData)
		end
	end

	local function addTradeRow(gemType, gemCategory, upgradeLabel, name, groupLabel, currentValue, nextValue, curSort, nextSort, output, socketGroup, gemIndex, targetLevel, targetQuality, tradeGemNameSpec, tradeQualityId, tradeNaturalMaxLevel, targetImbuedSupport)
		local upgradedValue = getStatValue(output, currentStat, build)
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
			sourceType = "TRADE",
			upgradeLabel = upgradeLabel,
			name = name,
			groupLabel = groupLabel,
			currentState = currentState,
			level = currentValue,
			nextLevel = nextValue,
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
			tradeGemNameSpec = tradeGemNameSpec,
			tradeQualityId = tradeQualityId,
			tradeNaturalMaxLevel = tradeNaturalMaxLevel,
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
			if gemInstance.gemData and grantedEffect and gemInstance.enabled and groupEnabled then
				local gemType = grantedEffect.support and "Support" or (grantedEffect.hasGlobalEffect and "Global" or "Active")
				local gemCategory = grantedEffect.support and "SUPPORT" or "ACTIVE"
				local gemName = (alternateGemQualityPrefixMap[gemInstance.qualityId or "Default"] or "") .. gemInstance.nameSpec
				local groupLabel = socketGroup.displayLabel or socketGroup.label or ("Socket Group " .. groupIndex)
				local currentLevel = gemInstance.level or 0
				local currentQuality = m_max(0, gemInstance.quality or 0)
				local currentImbuedSupport = gemInstance.imbuedSupport
				local naturalMaxLevel = gemInstance.gemData.naturalMaxLevel or 0
				local maxLevel = naturalMaxLevel
				-- Exceptional line gems do not get the generic +1 corrupted level step.
				if not grantedEffect.plusVersionOf then
					maxLevel = maxLevel + 1
				end

				local candidateLevels = { }
				local seenLevels = { }
				addDistinctValue(candidateLevels, seenLevels, naturalMaxLevel)
				addDistinctValue(candidateLevels, seenLevels, maxLevel)

				local candidateQualities = { }
				local seenQualities = { }
				addDistinctValue(candidateQualities, seenQualities, currentQuality)
				if currentQuality < 20 then
					addDistinctValue(candidateQualities, seenQualities, 20)
				end
				if currentQuality < 23 then
					addDistinctValue(candidateQualities, seenQualities, 23)
				end

				for _, targetLevel in ipairs(candidateLevels) do
					for _, targetQuality in ipairs(candidateQualities) do
						if targetLevel >= currentLevel
							and targetQuality >= currentQuality
							and (targetLevel > currentLevel or targetQuality > currentQuality)
							and grantedEffect.levels[targetLevel] then
							gemInstance.level = targetLevel
							gemInstance.quality = targetQuality
							local errMsg, output = PCall(calcFunc, nil, useFullDPS)
							gemInstance.level = currentLevel
							gemInstance.quality = currentQuality
							if not errMsg and isLevelUsable(skillsTab, gemInstance, grantedEffect, targetLevel, output) then
								addTradeRow(
									gemType,
									gemCategory,
									"Trade",
									gemName,
									groupLabel,
									s_format("%d/%d", currentLevel, currentQuality),
									s_format("%d/%d", targetLevel, targetQuality),
									currentLevel * 100 + currentQuality,
									targetLevel * 100 + targetQuality,
									output,
									socketGroup,
									gemIndex,
									targetLevel,
									targetQuality,
									getTradeGemNameSpec(gemInstance.gemData, gemInstance.nameSpec),
									gemInstance.qualityId or "Default",
									naturalMaxLevel,
									nil
								)
							end
						end
					end
				end

				if gemCategory == "ACTIVE"
					and socketGroup.slot
					and currentLevel <= 20
					and not slotHasOtherImbuedGem(skillsTab, socketGroup.slot, socketGroup, gemIndex) then
					local activeSkills = getGemActiveSkills(socketGroup, gemInstance)
					if #activeSkills > 0 then
						local imbuedQualities = { }
						local seenImbuedQualities = { }
						addDistinctValue(imbuedQualities, seenImbuedQualities, 0)
						addDistinctValue(imbuedQualities, seenImbuedQualities, m_max(0, m_min(currentQuality, 20)))
						addDistinctValue(imbuedQualities, seenImbuedQualities, 20)
						local imbuedCalcCount = 0
						for _, targetQuality in ipairs(imbuedQualities) do
							gemInstance.level = 20
							gemInstance.quality = targetQuality
							for _, supportGemData in ipairs(reportableImbuedSupports) do
								local supportGrantedEffect = supportGemData.grantedEffect
								local canSupportGem = false
								for _, activeSkill in ipairs(activeSkills) do
									if calcLib.canGrantedEffectSupportActiveSkill(supportGrantedEffect, activeSkill) then
										canSupportGem = true
										break
									end
								end
								if canSupportGem then
									imbuedCalcCount = imbuedCalcCount + 1
									if imbuedCalcCount % 10 == 0 and co_running() then
										co_yield()
									end
									gemInstance.imbuedSupport = supportGemData.grantedEffectId
									local errMsg, output = PCall(calcFunc, nil, useFullDPS)
									if not errMsg and isLevelUsable(skillsTab, gemInstance, grantedEffect, 20, output) then
										addTradeRow(
											gemType,
											gemCategory,
											"Trade",
											gemName,
											groupLabel,
											s_format("%d/%d", currentLevel, currentQuality),
											s_format("20/%d + %s", targetQuality, supportGemData.name),
											currentLevel * 100 + currentQuality,
											s_format("20/%02d|%s", targetQuality, supportGemData.name),
											output,
											socketGroup,
											gemIndex,
											20,
											targetQuality,
											getTradeGemNameSpec(gemInstance.gemData, gemInstance.nameSpec),
											gemInstance.qualityId or "Default",
											naturalMaxLevel,
											supportGemData.grantedEffectId
										)
									end
								end
							end
						end
					end
				end

				gemInstance.level = currentLevel
				gemInstance.quality = currentQuality
				gemInstance.imbuedSupport = currentImbuedSupport
			end
		end
		advanceBuildState(buildState)
	end

	return report
end

function gemTradeReport.Filter(report, filters)
	local filteredReport = { }
	for _, row in ipairs(report or { }) do
		if isRowAllowedByFilters(row, filters) then
			t_insert(filteredReport, row)
		end
	end
	return filteredReport
end

return gemTradeReport
