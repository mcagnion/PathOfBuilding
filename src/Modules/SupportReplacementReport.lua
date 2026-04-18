-- Path of Building
--
-- Module: Support Replacement Report
-- Builds support replacement report rows for the Skills tab.
--

local ipairs = ipairs
local t_insert = table.insert
local m_abs = math.abs
local m_max = math.max
local m_min = math.min
local s_format = string.format
local co_running = coroutine.running
local co_yield = coroutine.yield

local common = LoadModule("Modules/GemReportCommon")
local advanceBuildState = common.advanceBuildState
local isLevelUsable = common.isLevelUsable
local getDisplayStat = common.getDisplayStat
local getStatValue = common.getStatValue
local formatDelta = common.formatDelta

local supportReplacementReport = { }

local function isRowAllowedByFilters(reportRow, filters)
	if not filters then
		return true
	end
	if filters.impact == "POSITIVE" and reportRow.score <= 0 then
		return false
	end
	return true
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

local function addDistinctState(list, seen, level, quality)
	if not level or not quality then
		return
	end
	local key = tostring(level) .. "/" .. tostring(quality)
	if seen[key] then
		return
	end
	seen[key] = true
	t_insert(list, {
		level = level,
		quality = quality,
	})
end

local function getTradeGemNameSpec(gemData)
	if gemData and gemData.grantedEffect and gemData.grantedEffect.support then
		return gemData.name .. " Support"
	end
	return gemData and gemData.name or ""
end

function supportReplacementReport.Build(skillsTab, currentStat, filters, buildState)
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

	-- Pre-filter candidate support gems once instead of scanning data.gems per support slot.
	local candidateSupportGems = { }
	for _, gemData in pairs(build.data.gems) do
		local ge = gemData.grantedEffect
		if ge and ge.support and not ge.unsupported and not isRemovedLegacySupportGem(gemData) then
			t_insert(candidateSupportGems, gemData)
		end
	end

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
					local currentGemId = gemInstance.gemId
					local currentNameSpec = gemInstance.nameSpec
					local currentSkillId = gemInstance.skillId
					local currentCorrupted = gemInstance.corrupted

					local replacementCalcCount = 0
					for _, candidateGemData in ipairs(candidateSupportGems) do
						local candidateGrantedEffect = candidateGemData.grantedEffect
						if candidateGemData.id ~= currentGemId
							and not existingSupportIds[candidateGemData.grantedEffectId]
							and calcLib.canGrantedEffectSupportActiveSkill(candidateGrantedEffect, activeSkill) then
							local candidateMaxLevel = candidateGemData.naturalMaxLevel or 0
							-- Exceptional line gems do not get the generic +1 corrupted level step.
							if not candidateGrantedEffect.plusVersionOf then
								candidateMaxLevel = candidateMaxLevel + 1
							end
							local candidateStates = { }
							local seenStates = { }
							addDistinctState(candidateStates, seenStates, m_min(currentLevel, candidateMaxLevel), m_min(currentQuality, 23))
							if candidateMaxLevel >= 21 and candidateGrantedEffect.levels[21] then
								addDistinctState(candidateStates, seenStates, 21, 20)
							end
							if (candidateGemData.naturalMaxLevel or 0) >= 20 then
								addDistinctState(candidateStates, seenStates, 20, 23)
							end

							for _, candidateState in ipairs(candidateStates) do
								local candidateLevel = candidateState.level
								local candidateQuality = candidateState.quality
								if candidateGrantedEffect.levels[candidateLevel] then
									replacementCalcCount = replacementCalcCount + 1
									if replacementCalcCount % 10 == 0 and co_running() then
										co_yield()
									end
									gemInstance.gemId = candidateGemData.id
									gemInstance.nameSpec = candidateGemData.name
									gemInstance.skillId = candidateGemData.grantedEffectId
									gemInstance.gemData = candidateGemData
									gemInstance.grantedEffect = candidateGrantedEffect
									gemInstance.level = candidateLevel
									gemInstance.quality = candidateQuality
									gemInstance.corrupted = (candidateLevel > (candidateGemData.naturalMaxLevel or 0)) or candidateQuality > 20
									skillsTab:ProcessSocketGroup(socketGroup)
									local errMsg, output = PCall(calcFunc, nil, useFullDPS)
									local processedGem = socketGroup.gemList[gemIndex]
									if not errMsg and isLevelUsable(skillsTab, processedGem, candidateGrantedEffect, candidateLevel, output) then
										local upgradedValue = getStatValue(output, currentStat, build)
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
											candidateGemId = candidateGemData.id,
											candidateLevel = candidateLevel,
											candidateQuality = candidateQuality,
											tradeGemNameSpec = getTradeGemNameSpec(candidateGemData),
											tradeNaturalMaxLevel = candidateGemData.naturalMaxLevel,
											targetLevel = candidateLevel,
											targetQuality = candidateQuality,
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
									gemInstance.corrupted = currentCorrupted
									skillsTab:ProcessSocketGroup(socketGroup)
								end
							end
						end
					end
				end
			end
		end
		advanceBuildState(buildState)
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
