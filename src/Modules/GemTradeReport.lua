-- Path of Building
--
-- Module: Gem Trade Report
-- Builds replacement-gem report rows for the Skills tab.
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
local isReportableImbuedSupportGem = common.isReportableImbuedSupportGem
local slotHasOtherImbuedGem = common.slotHasOtherImbuedGem
local getGemActiveSkills = common.getGemActiveSkills
local alternateGemQualityPrefixMap = common.alternateGemQualityPrefixMap

local gemTradeReport = { }

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
	local reportableImbuedSupports = common.filterReportableImbuedSupports(build.data.gems)

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
