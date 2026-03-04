-- Path of Building
--
-- Module: Config Enemy Condition Helper
-- Shared helpers for condition source/chance/recommendation tooltips in Config tab.
--

local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert
local t_concat = table.concat
local m_min = math.min
local m_max = math.max
local m_floor = math.floor
local m_pow = math.pow

local enemyConditionUtils = LoadModule("Modules/EnemyConditionUtils")

local helper = { }

local ailmentSourceLabels = {
	Chill = "Ailment calculation: Chill",
	Freeze = "Ailment calculation: Freeze",
	Shock = "Ailment calculation: Shock",
	Ignite = "Ailment calculation: Ignite",
	Scorch = "Ailment calculation: Scorch",
	Brittle = "Ailment calculation: Brittle",
	Sap = "Ailment calculation: Sap",
	Bleed = "Ailment calculation: Bleed",
	Poison = "Ailment calculation: Poison",
	Blind = "Debuff calculation: Blind",
}

local manualEnemyConditionHintsByVar = {
	conditionEnemyChilled = { "Chilled", "ChilledByYourHits", "ChilledByYou" },
	conditionEnemyBlinded = { "Blinded" },
}

local enemyConditionChanceStatMap = {
	Bleeding = { "BleedChance" },
	Poisoned = { "PoisonChance" },
	Ignited = { "IgniteChancePerHit", "IgniteChance" },
	Burning = { "IgniteChancePerHit", "IgniteChance" },
	Frozen = { "FreezeChance" },
	Shocked = { "ShockChance" },
	Scorched = { "ScorchChance" },
	Brittle = { "BrittleChance" },
	Sapped = { "SapChance" },
	Blinded = { "BlindChance" },
}

local function forEachIfOption(ifOption, ifFunc)
	if type(ifOption) == "table" then
		for _, ifOpt in ipairs(ifOption) do
			ifFunc(ifOpt)
		end
		return
	end
	ifFunc(ifOption)
end

local function roundTo(value, digits)
	local factor = m_pow(10, digits)
	return m_floor(value * factor + 0.5) / factor
end

local function getConditionChancePerHit(output, enemyCondition, skillFlags)
	if (enemyCondition == "ChilledByYourHits" or enemyCondition == "ChilledByYou")
		and skillFlags and skillFlags.inflictChill then
		-- Chill from hits is effectively guaranteed per successful hit.
		return 1
	end
	local chanceStats = enemyConditionChanceStatMap[enemyCondition]
	if not output or not chanceStats then
		return
	end
	local chance = 0
	for _, statName in ipairs(chanceStats) do
		chance = m_max(chance, output[statName] or 0)
	end
	if chance <= 0 then
		return
	end
	return m_min(chance, 100) / 100
end

local function getEffectiveAttemptsPerSecond(output, skillData)
	if not output then
		return
	end
	local baseRate = output.HitSpeed or output.Speed
	if not baseRate or baseRate <= 0 then
		return
	end
	local hitChance = m_min(m_max(output.HitChance or 100, 0), 100) / 100
	local dpsMultiplier = skillData and (skillData.dpsMultiplier or 1) or 1
	local attempts = baseRate * hitChance * dpsMultiplier
	if attempts <= 0 then
		return
	end
	return attempts
end

local function getConditionApplyChanceInOneSecond(build, enemyCondition)
	local output = build.calcsTab.mainOutput
	local mainEnv = build.calcsTab.mainEnv
	if not output or not mainEnv then
		return
	end
	local function chanceForActor(actorOutput, actorSkillData, actorSkillFlags)
		if enemyCondition == "ChilledByYou"
			and actorSkillFlags and actorSkillFlags.chill and not actorSkillFlags.hit then
			-- Non-hit chill sources (e.g. chilling area) don't use hit-rate math.
			return 1, nil, nil, true
		end
		local chancePerHit = getConditionChancePerHit(actorOutput, enemyCondition, actorSkillFlags)
		local attemptsPerSecond = getEffectiveAttemptsPerSecond(actorOutput, actorSkillData)
		if not chancePerHit or not attemptsPerSecond then
			return
		end
		local oneSecondChance = 1 - m_pow(1 - chancePerHit, attemptsPerSecond)
		return oneSecondChance, chancePerHit, attemptsPerSecond, false
	end

	local playerSkillData = mainEnv.player and mainEnv.player.mainSkill
		and mainEnv.player.mainSkill.skillData
	local playerSkillFlags = mainEnv.player and mainEnv.player.mainSkill
		and mainEnv.player.mainSkill.skillFlags
	local minionSkillData = mainEnv.minion and mainEnv.minion.mainSkill
		and mainEnv.minion.mainSkill.skillData
	local minionSkillFlags = mainEnv.minion and mainEnv.minion.mainSkill
		and mainEnv.minion.mainSkill.skillFlags
	local playerChance, playerChancePerHit, playerAttempts, playerNonHitSource =
		chanceForActor(output, playerSkillData, playerSkillFlags)
	local minionChance, minionChancePerHit, minionAttempts, minionNonHitSource =
		chanceForActor(output.Minion, minionSkillData, minionSkillFlags)
	if not playerChance and not minionChance then
		return
	end
	playerChance = playerChance or 0
	minionChance = minionChance or 0
	local combined = 1 - (1 - playerChance) * (1 - minionChance)
	return {
		combined = combined,
		playerChancePerHit = playerChancePerHit,
		playerAttempts = playerAttempts,
		playerNonHitSource = playerNonHitSource,
		minionChancePerHit = minionChancePerHit,
		minionAttempts = minionAttempts,
		minionNonHitSource = minionNonHitSource,
	}
end

local function getBestConditionChanceData(build, ifEnemyCond)
	local bestChanceData
	local bestCondition
	forEachIfOption(ifEnemyCond, function(enemyCondition)
		local chanceData = getConditionApplyChanceInOneSecond(build, enemyCondition)
		if chanceData and (not bestChanceData or chanceData.combined > bestChanceData.combined) then
			bestChanceData = chanceData
			bestCondition = enemyCondition
		end
	end)
	return bestChanceData, bestCondition
end

function helper.joinTooltipLines(...)
	local out
	for i = 1, select("#", ...) do
		local line = select(i, ...)
		if line and line ~= "" then
			out = (out and out .. "\n" or "") .. line
		end
	end
	return out
end

function helper.formatConditionSource(build, source)
	return enemyConditionUtils.formatConditionSource(build, source, ailmentSourceLabels)
end

function helper.formatConditionSourcesTooltip(build, mods)
	if not mods then
		return
	end
	local sourceList = enemyConditionUtils.collectConditionSources(build, mods, ailmentSourceLabels)
	if #sourceList == 0 then
		return
	end
	local maxSources = 4
	local shownSources = { }
	for i = 1, m_min(maxSources, #sourceList) do
		t_insert(shownSources, sourceList[i])
	end
	local out = "^7Condition referenced by "
		.. #sourceList
		.. " source"
		.. (#sourceList > 1 and "s" or "")
		.. ": "
		.. t_concat(shownSources, ", ")
	if #sourceList > maxSources then
		out = out .. " +" .. (#sourceList - maxSources) .. " more"
	end
	return out .. "\n^8Check this when the condition is reliably applied in combat."
end

function helper.collectEnemyConditionMods(build, ifEnemyCond)
	local allMods = { }
	forEachIfOption(ifEnemyCond, function(enemyCondition)
		for _, mod in ipairs(build.calcsTab.mainEnv.enemyConditionsUsed[enemyCondition] or { }) do
			t_insert(allMods, mod)
		end
	end)
	return #allMods > 0 and allMods or nil
end

function helper.getEnemyConditionHints(varData)
	return varData.ifEnemyCond or manualEnemyConditionHintsByVar[varData.var]
end

function helper.formatConditionChanceTooltip(build, ifEnemyCond)
	local chanceData, bestCondition = getBestConditionChanceData(build, ifEnemyCond)
	if not chanceData then
		return
	end
	local out = "^7Estimated apply chance within 1s: "
		.. roundTo(chanceData.combined * 100, 1) .. "%"
	if type(ifEnemyCond) == "table" and bestCondition then
		out = out .. " ^8(" .. bestCondition .. ")"
	end
	local details = { }
	if chanceData.playerChancePerHit and chanceData.playerAttempts then
		t_insert(
			details,
			"Player "
				.. roundTo(chanceData.playerChancePerHit * 100, 1)
				.. "%/hit, "
				.. roundTo(chanceData.playerAttempts, 2)
				.. " effective hits/s"
		)
	end
	if chanceData.playerNonHitSource then
		t_insert(details, "Player non-hit chill source (enemy assumed in area/range)")
	end
	if chanceData.minionChancePerHit and chanceData.minionAttempts then
		t_insert(
			details,
			"Minion "
				.. roundTo(chanceData.minionChancePerHit * 100, 1)
				.. "%/hit, "
				.. roundTo(chanceData.minionAttempts, 2)
				.. " effective hits/s"
		)
	end
	if chanceData.minionNonHitSource then
		t_insert(details, "Minion non-hit chill source (enemy assumed in area/range)")
	end
	if #details > 0 then
		out = out .. "\n^8" .. t_concat(details, " | ")
	end
	return out
end

function helper.getEnemyConditionRecommendationData(build, configInput, ifEnemyCond, varName)
	if not ifEnemyCond or not varName then
		return
	end
	if not configInput or configInput[varName] then
		return
	end
	local mainEnv = build.calcsTab.mainEnv
	if not mainEnv then
		return
	end
	local hasSource
	local bestChance
	forEachIfOption(ifEnemyCond, function(enemyCondition)
		local mods = mainEnv.enemyConditionsUsed[enemyCondition]
		if mods and #mods > 0 then
			hasSource = true
		end
		local chanceData = getConditionApplyChanceInOneSecond(build, enemyCondition)
		if chanceData then
			bestChance = m_max(bestChance or 0, chanceData.combined)
		end
	end)
	if not hasSource then
		return
	end
	local level = "soft"
	if bestChance and bestChance >= 0.75 then
		level = "strong"
	elseif bestChance and bestChance >= 0.35 then
		level = "medium"
	end
	return {
		level = level,
		chance = bestChance,
	}
end

function helper.formatConditionRecommendationTooltip(build, configInput, ifEnemyCond, varName)
	local recommendation = helper.getEnemyConditionRecommendationData(
		build,
		configInput,
		ifEnemyCond,
		varName
	)
	if not recommendation then
		return
	end
	if recommendation.level == "strong" and recommendation.chance then
		return "^2Suggestion: enable this option (" ..
			roundTo(recommendation.chance * 100, 1) .. "% within 1s)."
	end
	if recommendation.level == "medium" and recommendation.chance then
		return "^7Suggestion: consider enabling this option (" ..
			roundTo(recommendation.chance * 100, 1) .. "% within 1s)."
	end
	return "^7Suggestion: source detected; enable when uptime is reliable."
end

return helper
