-- Path of Building
--
-- Module: Gem Report Common
-- Shared utilities for gem report modules.
--

local ipairs = ipairs
local t_insert = table.insert
local m_floor = math.floor
local m_max = math.max
local s_format = string.format
local co_running = coroutine.running
local co_yield = coroutine.yield

local common = { }

common.alternateGemQualityPrefixMap = {
	Default = "",
	Alternate1 = "Anomalous ",
	Alternate2 = "Divergent ",
	Alternate3 = "Phantasmal ",
}

function common.advanceBuildState(buildState)
	if not buildState then
		return
	end
	buildState.completedGroups = (buildState.completedGroups or 0) + 1
	local batchSize = buildState.batchSize or 1
	if buildState.completedGroups % batchSize == 0 and co_running() then
		co_yield()
	end
end

function common.getOutputAttr(skillsTab, output, stat)
	if output and output[stat] ~= nil then
		return output[stat]
	end
	local mainOutput = skillsTab.build and skillsTab.build.calcsTab and skillsTab.build.calcsTab.mainOutput
	if mainOutput and mainOutput[stat] ~= nil then
		return mainOutput[stat]
	end
	return 0
end

function common.isLevelUsable(skillsTab, gemInstance, grantedEffect, targetLevel, output)
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
		return omniReq <= common.getOutputAttr(skillsTab, output, "Omni")
	end

	return (reqStr or 0) <= common.getOutputAttr(skillsTab, output, "Str")
		and (reqDex or 0) <= common.getOutputAttr(skillsTab, output, "Dex")
		and (reqInt or 0) <= common.getOutputAttr(skillsTab, output, "Int")
end

function common.getDisplayStat(build, currentStat)
	for _, displayStat in ipairs(build.displayStats) do
		if displayStat.stat == currentStat.stat then
			return displayStat
		end
	end
	return { fmt = ".1f" }
end

function common.getStatValue(output, currentStat, build)
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

function common.formatDelta(delta, displayStat, lowerIsBetter)
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

function common.isReportableImbuedSupportGem(gemData)
	if not (gemData and gemData.grantedEffect and gemData.grantedEffect.support) then
		return false
	end
	-- 3.28 imbues should not suggest legacy awakened-only supports.
	if gemData.tags and gemData.tags.awakened then
		return false
	end
	return gemData.grantedEffect.levels and gemData.grantedEffect.levels[1] ~= nil
end

function common.slotHasOtherImbuedGem(skillsTab, slotName, sourceGroup, sourceGemIndex)
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

function common.getGemActiveSkills(socketGroup, gemInstance)
	local activeSkills = { }
	for _, activeSkill in ipairs(socketGroup.displaySkillList or { }) do
		if activeSkill.activeEffect and activeSkill.activeEffect.srcInstance == gemInstance then
			t_insert(activeSkills, activeSkill)
		end
	end
	return activeSkills
end

function common.filterReportableImbuedSupports(dataGems)
	local list = { }
	for _, gemData in pairs(dataGems) do
		if common.isReportableImbuedSupportGem(gemData) then
			t_insert(list, gemData)
		end
	end
	return list
end

return common
