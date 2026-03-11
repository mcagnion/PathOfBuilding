-- Path of Building
--
-- Module: Support Replacement Report
-- Builds support replacement report rows for the Skills tab.
--

local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert
local m_abs = math.abs
local m_floor = math.floor
local m_max = math.max
local m_min = math.min
local s_format = string.format

local supportReplacementReport = { }

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

local function getGroupMainActiveSkill(socketGroup)
	local mainIndex = socketGroup.mainActiveSkill or 1
	return socketGroup.displaySkillList and socketGroup.displaySkillList[mainIndex]
end

local function getSupportState(gemInstance)
	return s_format("%d/%d", gemInstance.level or 0, m_max(0, gemInstance.quality or 0))
end

local function isRemovedLegacySupportGem(gemData)
	return gemData and gemData.tags and gemData.tags.awakened and not gemData.tags.exceptional
end

function supportReplacementReport.Build(skillsTab, currentStat, filters)
	local report = { }
	if not (currentStat and currentStat.stat) then
		return report
	end

	local calcFunc, calcBase = skillsTab.build.calcsTab:GetMiscCalculator()
	if not calcFunc or not calcBase then
		return report
	end

	local displayStat = getDisplayStat(skillsTab.build, currentStat)
	local lowerIsBetter = displayStat.lowerIsBetter or currentStat.lowerIsBetter
	local useFullDPS = currentStat.stat == "FullDPS"
	local baseValue = getStatValue(calcBase, currentStat)

	for groupIndex, socketGroup in ipairs(skillsTab.socketGroupList) do
		skillsTab:ProcessSocketGroup(socketGroup)
		local groupEnabled = socketGroup.enabled and socketGroup.slotEnabled ~= false
		local activeSkill = groupEnabled and getGroupMainActiveSkill(socketGroup) or nil
		local activeEffect = activeSkill and activeSkill.activeEffect
		local activeSkillName = activeEffect and activeEffect.grantedEffect and activeEffect.grantedEffect.name or nil
		if activeSkill and activeEffect and activeSkillName then
			local existingSupportIds = { }
			for _, otherGem in ipairs(socketGroup.gemList) do
				local otherGrantedEffect = otherGem.grantedEffect or (otherGem.gemData and otherGem.gemData.grantedEffect)
				if otherGem.enabled and otherGrantedEffect and otherGrantedEffect.support and otherGem.gemData then
					existingSupportIds[otherGem.gemData.grantedEffectId] = true
				end
			end

			for gemIndex, gemInstance in ipairs(socketGroup.gemList) do
				local grantedEffect = gemInstance.grantedEffect or (gemInstance.gemData and gemInstance.gemData.grantedEffect)
				local displayEffect = gemInstance.displayEffect or gemInstance
				local isSupportingMainSkill = displayEffect.isSupporting and displayEffect.isSupporting[activeEffect.srcInstance]
				if gemInstance.enabled
					and gemInstance.gemData
					and grantedEffect
					and grantedEffect.support
					and not displayEffect.superseded
					and isSupportingMainSkill then
					local currentState = getSupportState(gemInstance)
					local currentName = gemInstance.nameSpec or gemInstance.gemData.name
					local currentLevel = gemInstance.level or 0
					local currentQuality = m_max(0, gemInstance.quality or 0)
					local currentQualityId = gemInstance.qualityId or "Default"
					local currentGemId = gemInstance.gemId
					local currentNameSpec = gemInstance.nameSpec
					local currentSkillId = gemInstance.skillId
					local currentImbuedSupport = gemInstance.imbuedSupport
					local currentCorrupted = gemInstance.corrupted

					for _, candidateGemData in pairs(skillsTab.build.data.gems) do
						local candidateGrantedEffect = candidateGemData.grantedEffect
						if candidateGemData.id ~= currentGemId
							and candidateGrantedEffect
							and candidateGrantedEffect.support
							and not candidateGrantedEffect.unsupported
							and not isRemovedLegacySupportGem(candidateGemData)
							and not existingSupportIds[candidateGemData.grantedEffectId]
							and calcLib.canGrantedEffectSupportActiveSkill(candidateGrantedEffect, activeSkill) then
							local candidateMaxLevel = candidateGemData.naturalMaxLevel or 0
							-- Exceptional line gems do not get the generic +1 corrupted level step.
							if not candidateGrantedEffect.plusVersionOf then
								candidateMaxLevel = candidateMaxLevel + 1
							end
							local candidateLevel = m_min(currentLevel, candidateMaxLevel)
							local candidateQuality = m_min(currentQuality, 23)
							if candidateGrantedEffect.levels[candidateLevel] then
								gemInstance.gemId = candidateGemData.id
								gemInstance.nameSpec = candidateGemData.name
								gemInstance.skillId = candidateGemData.grantedEffectId
								gemInstance.gemData = candidateGemData
								gemInstance.grantedEffect = candidateGrantedEffect
								gemInstance.level = candidateLevel
								gemInstance.quality = candidateQuality
								gemInstance.qualityId = "Default"
								gemInstance.imbuedSupport = nil
								gemInstance.corrupted = currentCorrupted and candidateLevel > candidateGemData.naturalMaxLevel or candidateQuality > 20
								skillsTab:ProcessSocketGroup(socketGroup)
								local errMsg, output = PCall(calcFunc, nil, useFullDPS)
								local processedGem = socketGroup.gemList[gemIndex]
								if not errMsg and isLevelUsable(skillsTab, processedGem, candidateGrantedEffect, candidateLevel, output) then
									local upgradedValue = getStatValue(output, currentStat)
									local delta = upgradedValue - baseValue
									local score = lowerIsBetter and -delta or delta
									local improvementPct = 0
									local hasImprovementPct = false
									if baseValue ~= 0 then
										hasImprovementPct = true
										improvementPct = score / m_abs(baseValue) * 100
									end

									local reportRow = {
										type = "Support",
										sourceType = "SUPPORT_REPLACEMENT",
										skillName = activeSkillName,
										groupLabel = socketGroup.displayLabel or socketGroup.label or ("Socket Group " .. groupIndex),
										name = currentName,
										currentState = currentState,
										candidateName = candidateGemData.name,
										candidateState = s_format("%d/%d", candidateLevel, candidateQuality),
										currentLabel = currentName .. " " .. currentState,
										candidateLabel = candidateGemData.name .. " " .. s_format("%d/%d", candidateLevel, candidateQuality),
										level = currentState,
										nextLevel = s_format("%s %d/%d", candidateGemData.name, candidateLevel, candidateQuality),
										curSort = currentName .. "|" .. currentState,
										nextSort = candidateGemData.name .. "|" .. s_format("%02d/%02d", candidateLevel, candidateQuality),
										delta = delta,
										deltaStr = formatDelta(delta, displayStat, lowerIsBetter),
										score = score,
										improvementPct = improvementPct,
										hasImprovementPct = hasImprovementPct,
										socketGroup = socketGroup,
										gemIndex = gemIndex,
										currentGemId = currentGemId,
										currentQualityId = currentQualityId,
										candidateGemId = candidateGemData.id,
										candidateLevel = candidateLevel,
										candidateQuality = candidateQuality,
										candidateQualityId = "Default",
										useFullDPS = useFullDPS,
									}
									if isRowAllowedByFilters(reportRow, filters) then
										t_insert(report, reportRow)
									end
								end

								gemInstance.gemId = currentGemId
								gemInstance.nameSpec = currentNameSpec
								gemInstance.skillId = currentSkillId
								gemInstance.gemData = skillsTab.build.data.gems[currentGemId]
								gemInstance.grantedEffect = gemInstance.gemData and gemInstance.gemData.grantedEffect
								gemInstance.level = currentLevel
								gemInstance.quality = currentQuality
								gemInstance.qualityId = currentQualityId
								gemInstance.imbuedSupport = currentImbuedSupport
								gemInstance.corrupted = currentCorrupted
								skillsTab:ProcessSocketGroup(socketGroup)
							end
						end
					end
				end
			end
		end
	end

	return report
end

function supportReplacementReport.Filter(report, filters)
	if not filters then
		return report
	end
	local filteredReport = { }
	for _, reportRow in ipairs(report or { }) do
		if isRowAllowedByFilters(reportRow, filters) then
			t_insert(filteredReport, reportRow)
		end
	end
	return filteredReport
end

return supportReplacementReport
