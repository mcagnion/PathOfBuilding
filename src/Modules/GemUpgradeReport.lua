-- Path of Building
--
-- Module: Gem Upgrade Report
-- Builds gem upgrade report rows for the Skills tab.
--

local ipairs = ipairs
local t_insert = table.insert
local t_sort = table.sort
local m_abs = math.abs
local m_max = math.max
local s_format = string.format
local co_running = coroutine.running
local co_yield = coroutine.yield

local common = LoadModule("Modules/GemReportCommon")
local advanceBuildState = common.advanceBuildState
local isLevelUsable = common.isLevelUsable
local getDisplayStat = common.getDisplayStat
local getStatValue = common.getStatValue
local formatDelta = common.formatDelta
local slotHasOtherImbuedGem = common.slotHasOtherImbuedGem
local getGemActiveSkills = common.getGemActiveSkills
local alternateGemQualityPrefixMap = common.alternateGemQualityPrefixMap

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
	local build = skillsTab.build
	local baseValue = getStatValue(calcBase, currentStat, build)
	local maxQuality = 23

	-- Pre-filter imbued support gems once instead of scanning data.gems per active gem.
	local reportableImbuedSupports = common.filterReportableImbuedSupports(build.data.gems)

	local function addUpgradeRow(gemType, gemCategory, sourceType, upgradeLabel, name, groupLabel, currentValue, nextValue, curSort, nextSort, output, socketGroup, gemIndex, targetLevel, targetQuality, targetImbuedSupport)
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
						if not errMsg and isLevelUsable(skillsTab, gemInstance, grantedEffect, nextLevel, output) then
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
								local delta = getStatValue(output, currentStat, build) - baseValue
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
					if not errMsg and isLevelUsable(skillsTab, gemInstance, grantedEffect, 21, output) then
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
						local imbuedCalcCount = 0
						for _, supportGemData in ipairs(reportableImbuedSupports) do
							local supportGrantedEffect = supportGemData.grantedEffect
							local coinLabel = getImbuedCoinLabel(supportGemData)
							local canSupportGem = false
							for _, activeSkill in ipairs(activeSkills) do
								if calcLib.canGrantedEffectSupportActiveSkill(supportGrantedEffect, activeSkill) then
									canSupportGem = true
									break
								end
							end
							if coinLabel and canSupportGem then
								imbuedCalcCount = imbuedCalcCount + 1
								if imbuedCalcCount % 10 == 0 and co_running() then
									co_yield()
								end
								gemInstance.imbuedSupport = supportGemData.grantedEffectId
								local errMsg, output = PCall(calcFunc, nil, useFullDPS)
								gemInstance.imbuedSupport = ""
								if not errMsg then
									local score = lowerIsBetter and -(getStatValue(output, currentStat, build) - baseValue) or (getStatValue(output, currentStat, build) - baseValue)
									t_insert(imbuedSupportEntries, {
										coinLabel = coinLabel,
										gemData = supportGemData,
										output = output,
										score = score,
									})
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
