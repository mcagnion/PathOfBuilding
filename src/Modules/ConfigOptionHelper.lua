-- Path of Building
--
-- Module: Config Option Helper
-- Shared helpers for config option visibility and tooltip generation in Config tab.
--

local ipairs = ipairs
local next = next
local pairs = pairs
local t_insert = table.insert
local t_concat = table.concat
local s_format = string.format
local m_abs = math.abs
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
	Maimed = { "MaimChance" },
	Poisoned = { "PoisonChance" },
	Hindered = { "HinderChance" },
	Taunted = { "TauntChance" },
	Ignited = { "IgniteChancePerHit", "IgniteChance" },
	Burning = { "IgniteChancePerHit", "IgniteChance" },
	Frozen = { "FreezeChance" },
	Shocked = { "ShockChance" },
	Scorched = { "ScorchChance" },
	Brittle = { "BrittleChance" },
	Sapped = { "SapChance" },
	Blinded = { "BlindChance" },
	Intimidated = { "IntimidateChance" },
}

local configVarElementMap = {
	conditionEnemyFireExposure = "Fire",
	conditionEnemyColdExposure = "Cold",
	conditionEnemyLightningExposure = "Lightning",
}

local configVarChargeMap = {
	usePowerCharges = {
		actor = "player",
		label = "Power Charges",
		maxStat = "PowerChargesMax",
		convertedFlag = "PowerChargesConvertToAbsorptionCharges",
		skillNames = {
			["Assassin's Mark"] = true,
			["Power Siphon"] = true,
			["Power Siphon of the Archmage"] = true,
			["Vaal Power Siphon"] = true,
		},
		supportNames = {
			["Power Charge On Critical"] = true,
			["Charged Traps"] = true,
		},
	},
	useFrenzyCharges = {
		actor = "player",
		label = "Frenzy Charges",
		maxStat = "FrenzyChargesMax",
		convertedFlag = "FrenzyChargesConvertToAfflictionCharges",
		skillNames = {
			["Blood Rage"] = true,
			["Frenzy"] = true,
			["Frenzy of Onslaught"] = true,
			["Poacher's Mark"] = true,
			["Vaal Cold Snap"] = true,
			["Cold Snap"] = true,
		},
		supportNames = {
			["Ice Bite"] = true,
			["Charged Traps"] = true,
		},
	},
	useEnduranceCharges = {
		actor = "player",
		label = "Endurance Charges",
		maxStat = "EnduranceChargesMax",
		convertedFlag = "EnduranceChargesConvertToBrutalCharges",
		skillNames = {
			["Enduring Cry"] = true,
			["Warlord's Mark"] = true,
		},
		supportNames = {
			["Endurance Charge on Melee Stun"] = true,
		},
	},
	minionsUsePowerCharges = {
		actor = "minion",
		label = "Power Charges",
		maxStat = "PowerChargesMax",
		convertedFlag = "PowerChargesConvertToAbsorptionCharges",
		skillNames = {
			["Assassin's Mark"] = true,
			["Power Siphon"] = true,
			["Power Siphon of the Archmage"] = true,
			["Vaal Power Siphon"] = true,
		},
		supportNames = {
			["Power Charge On Critical"] = true,
			["Charged Traps"] = true,
		},
	},
	minionsUseFrenzyCharges = {
		actor = "minion",
		label = "Frenzy Charges",
		maxStat = "FrenzyChargesMax",
		convertedFlag = "FrenzyChargesConvertToAfflictionCharges",
		skillNames = {
			["Blood Rage"] = true,
			["Frenzy"] = true,
			["Frenzy of Onslaught"] = true,
			["Poacher's Mark"] = true,
			["Vaal Cold Snap"] = true,
			["Cold Snap"] = true,
		},
		supportNames = {
			["Ice Bite"] = true,
			["Charged Traps"] = true,
		},
	},
	minionsUseEnduranceCharges = {
		actor = "minion",
		label = "Endurance Charges",
		maxStat = "EnduranceChargesMax",
		convertedFlag = "EnduranceChargesConvertToBrutalCharges",
		skillNames = {
			["Enduring Cry"] = true,
			["Warlord's Mark"] = true,
		},
		supportNames = {
			["Endurance Charge on Melee Stun"] = true,
		},
	},
}

local getEffectiveAttemptsPerSecond

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

local function formatValue(value, digits)
	if not value then
		return
	end
	digits = digits or 0
	local rounded = roundTo(value, digits)
	if digits > 0 then
		return formatNumSep(s_format("%." .. digits .. "f", rounded))
	end
	return formatNumSep(tostring(rounded))
end

local function formatSeconds(value, digits)
	if not value or value <= 0 then
		return
	end
	return formatValue(value, digits or 2) .. "s"
end

local function getOutput(build)
	return build.calcsTab and build.calcsTab.mainOutput
end

local function getMainEnv(build)
	return build.calcsTab and build.calcsTab.mainEnv
end

local function getActorOutput(build, actor)
	local output = getOutput(build)
	if not output then
		return
	end
	if actor == "minion" then
		return output.Minion
	end
	return output
end

local function getActor(build, actor)
	local mainEnv = getMainEnv(build)
	if not mainEnv then
		return
	end
	return mainEnv[actor or "player"]
end

local function getMaxActorStat(build, statName)
	local output = getOutput(build)
	if not output then
		return 0
	end
	return m_max(
		output[statName] or 0,
		output.Minion and output.Minion[statName] or 0
	)
end

local function getPlayerAndMinionSkillData(build)
	local mainEnv = getMainEnv(build)
	if not mainEnv then
		return
	end
	return mainEnv.player and mainEnv.player.mainSkill,
		mainEnv.minion and mainEnv.minion.mainSkill
end

local function collectActorSkillAndSupportNames(actor)
	local names = { }
	if not actor then
		return names
	end
	for _, activeSkill in ipairs(actor.activeSkillList or { }) do
		local activeName = activeSkill.activeEffect
			and activeSkill.activeEffect.grantedEffect
			and activeSkill.activeEffect.grantedEffect.name
		if activeName then
			names[activeName] = true
		end
		for _, supportEffect in ipairs(activeSkill.supportList or { }) do
			local supportName = supportEffect.grantedEffect and supportEffect.grantedEffect.name
			if supportName then
				names[supportName] = true
			end
		end
	end
	return names
end

local function forEachRelevantMod(build, modFunc)
	local mainEnv = getMainEnv(build)
	if not mainEnv then
		return
	end
	local function iterateModDB(modDB)
		if not modDB or not modDB.mods then
			return
		end
		for _, modList in pairs(modDB.mods) do
			for _, mod in ipairs(modList) do
				modFunc(mod)
			end
		end
	end
	local function iterateActiveSkillList(activeSkillList)
		for _, activeSkill in ipairs(activeSkillList or { }) do
			for _, mod in ipairs(activeSkill.baseSkillModList or { }) do
				modFunc(mod)
			end
			for _, mod in ipairs(activeSkill.skillModList or { }) do
				modFunc(mod)
			end
			if activeSkill.minion then
				iterateActiveSkillList(activeSkill.minion.activeSkillList)
			end
		end
	end
	iterateModDB(mainEnv.player and mainEnv.player.modDB)
	iterateModDB(mainEnv.minion and mainEnv.minion.modDB)
	iterateActiveSkillList(mainEnv.player and mainEnv.player.activeSkillList)
end

local function collectDirectEnemyModifierSourceMods(build, targetName)
	local out = { }
	forEachRelevantMod(build, function(mod)
		local listMod = mod and mod.name == "EnemyModifier" and mod.type == "LIST"
			and mod.value and mod.value.mod
		if not listMod or mod.source == "Base" then
			return
		end
		if mod.value.mod.name == targetName then
			t_insert(out, mod)
		end
	end)
	return out
end

local function getConditionEffectLines(build, enemyCondition)
	if enemyCondition == "Bleeding" then
		local bleedDPS = getMaxActorStat(build, "BleedDPS")
		local bleedDuration = getMaxActorStat(build, "BleedDuration")
		if bleedDPS <= 0 then
			return
		end
		return {
			"^7Current bleed DPS: " .. formatValue(bleedDPS, 1),
			bleedDuration > 0 and "^8Duration: " .. formatSeconds(bleedDuration, 2) or nil,
		}
	end
	if enemyCondition == "Maimed" then
		return {
			"^7Maimed enemies have 30% reduced Movement Speed.",
		}
	end
	if enemyCondition == "Hindered" then
		return {
			"^7Hinder is a movement speed debuff.",
			"^8Its exact slow amount depends on the source.",
		}
	end
	if enemyCondition == "Taunted" then
		return {
			"^7Taunt-dependent modifiers will apply while this enemy is taunted.",
			"^8Enemy targeting behaviour is not modelled here.",
		}
	end
	if enemyCondition == "Poisoned" then
		local poisonDPS = getMaxActorStat(build, "PoisonDPS")
		local totalPoisonDPS = getMaxActorStat(build, "TotalPoisonDPS")
		local poisonDuration = getMaxActorStat(build, "PoisonDuration")
		if poisonDPS <= 0 and totalPoisonDPS <= 0 then
			return
		end
		local poisonLine = "^7Current poison DPS: " .. formatValue(poisonDPS > 0 and poisonDPS or totalPoisonDPS, 1)
		if totalPoisonDPS > poisonDPS and poisonDPS > 0 then
			poisonLine = poisonLine .. " ^8(single " .. formatValue(poisonDPS, 1)
				.. ", stacked " .. formatValue(totalPoisonDPS, 1) .. ")"
		end
		return {
			poisonLine,
			poisonDuration > 0 and "^8Duration: " .. formatSeconds(poisonDuration, 2) or nil,
		}
	end
	if enemyCondition == "Ignited" or enemyCondition == "Burning" then
		local igniteDPS = m_max(getMaxActorStat(build, "IgniteDPS"), getMaxActorStat(build, "TotalIgniteDPS"))
		local burningGroundDPS = getMaxActorStat(build, "BurningGroundDPS")
		local igniteDuration = getMaxActorStat(build, "IgniteDuration")
		local out = { }
		if igniteDPS > 0 then
			t_insert(out, "^7Current ignite DPS: " .. formatValue(igniteDPS, 1))
			if igniteDuration > 0 then
				t_insert(out, "^8Duration: " .. formatSeconds(igniteDuration, 2))
			end
		end
		if enemyCondition == "Burning" and burningGroundDPS > 0 then
			t_insert(out, "^7Burning ground DPS: " .. formatValue(burningGroundDPS, 1))
		end
		return #out > 0 and out or nil
	end
	if enemyCondition == "Intimidated" then
		local mainEnv = getMainEnv(build)
		local isAttack = mainEnv and mainEnv.player and mainEnv.player.mainSkill
			and mainEnv.player.mainSkill.skillFlags
			and mainEnv.player.mainSkill.skillFlags.attack
		return {
			"^7Intimidated enemies take 10% increased Attack Damage.",
			not isAttack and "^8Current main skill is not an Attack." or nil,
		}
	end
end

local function getExposureChanceData(build, element)
	local output = getOutput(build)
	local mainEnv = getMainEnv(build)
	if not output or not mainEnv then
		return
	end
	local playerMainSkill, minionMainSkill = getPlayerAndMinionSkillData(build)
	local function chanceForActor(actorOutput, actorMainSkill, actorModDB)
		if not actorMainSkill or not actorOutput then
			return
		end
		local chance = actorMainSkill.skillModList:Sum("BASE", actorMainSkill.skillCfg, element .. "ExposureChance")
		if actorModDB then
			chance = chance + actorModDB:Sum("BASE", nil, element .. "ExposureChance")
		end
		if chance <= 0 then
			return
		end
		local attemptsPerSecond = getEffectiveAttemptsPerSecond(actorOutput, actorMainSkill.skillData)
		if not attemptsPerSecond then
			return
		end
		local chancePerHit = m_min(chance, 100) / 100
		return {
			chancePerHit = chancePerHit,
			attempts = attemptsPerSecond,
			combined = 1 - m_pow(1 - chancePerHit, attemptsPerSecond),
		}
	end
	local playerChanceData = chanceForActor(output, playerMainSkill, mainEnv.modDB)
	local minionChanceData = chanceForActor(output.Minion, minionMainSkill, mainEnv.minion and mainEnv.minion.modDB)
	if not playerChanceData and not minionChanceData then
		return
	end
	local combined = 1 - (1 - (playerChanceData and playerChanceData.combined or 0))
		* (1 - (minionChanceData and minionChanceData.combined or 0))
	return {
		player = playerChanceData,
		minion = minionChanceData,
		combined = combined,
	}
end

local function getExposureMagnitude(build, element)
	local mainEnv = getMainEnv(build)
	if not mainEnv then
		return
	end
	local exposure = -10 + mainEnv.modDB:Sum("BASE", nil, "ExtraExposure", "Extra" .. element .. "Exposure")
	local minimum = mainEnv.modDB:Override(nil, "ExposureMin")
	if minimum then
		exposure = m_min(exposure, minimum)
	end
	return m_abs(exposure)
end

local function getChargeConfig(build, varName)
	return configVarChargeMap[varName]
end

local function getChargeSourceMatches(build, varName)
	local chargeConfig = getChargeConfig(build, varName)
	local actor = getActor(build, chargeConfig and chargeConfig.actor)
	if not chargeConfig or not actor then
		return
	end
	if chargeConfig.convertedFlag and actor.modDB and actor.modDB:Flag(nil, chargeConfig.convertedFlag) then
		return
	end
	local names = collectActorSkillAndSupportNames(actor)
	local matches = { }
	for name in pairs(chargeConfig.skillNames or { }) do
		if names[name] then
			t_insert(matches, name)
		end
	end
	for name in pairs(chargeConfig.supportNames or { }) do
		if names[name] then
			t_insert(matches, name)
		end
	end
	table.sort(matches)
	return #matches > 0 and matches or nil
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

getEffectiveAttemptsPerSecond = function(output, skillData)
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

function helper.collectConditionSourceMods(build, ifCond)
	local allMods = { }
	local seen = { }
	local mainEnv = getMainEnv(build)
	if not mainEnv then
		return
	end
	forEachIfOption(ifCond, function(condition)
		if type(condition) ~= "string" then
			return
		end
		for _, mod in ipairs(mainEnv.modsUsed["Condition:" .. condition] or { }) do
			if mod.source ~= "Base" and mod.source ~= "Config" and not seen[mod] then
				seen[mod] = true
				t_insert(allMods, mod)
			end
		end
		for _, mod in ipairs(mainEnv.modsUsed[condition] or { }) do
			if mod.source ~= "Base" and mod.source ~= "Config" and not seen[mod] then
				seen[mod] = true
				t_insert(allMods, mod)
			end
		end
	end)
	return #allMods > 0 and allMods or nil
end

function helper.hasConditionSource(build, ifCond)
	local mods = helper.collectConditionSourceMods(build, ifCond)
	return mods and #mods > 0 or false
end

function helper.getConditionRecommendationData(build, configInput, ifCond, varName)
	if not ifCond or not varName then
		return
	end
	if not configInput or configInput[varName] then
		return
	end
	if not helper.hasConditionSource(build, ifCond) then
		return
	end
	return {
		level = "soft",
	}
end

function helper.formatConditionRecommendationHintTooltip(build, configInput, ifCond, varName)
	local recommendation = helper.getConditionRecommendationData(build, configInput, ifCond, varName)
	if not recommendation then
		return
	end
	return "^7Suggestion: source detected; enable when this condition is reliably active."
end

function helper.collectEnemyConditionMods(build, ifEnemyCond)
	local allMods = { }
	local seen = { }
	local mainEnv = getMainEnv(build)
	if not mainEnv then
		return
	end
	forEachIfOption(ifEnemyCond, function(enemyCondition)
		for _, mod in ipairs(mainEnv.enemyConditionsUsed[enemyCondition] or { }) do
			if not seen[mod] then
				seen[mod] = true
				t_insert(allMods, mod)
			end
		end
		for _, mod in ipairs(collectDirectEnemyModifierSourceMods(build, "Condition:" .. enemyCondition)) do
			if not seen[mod] then
				seen[mod] = true
				t_insert(allMods, mod)
			end
		end
	end)
	return #allMods > 0 and allMods or nil
end

function helper.hasEnemyConditionSource(build, ifEnemyCond)
	local mods = helper.collectEnemyConditionMods(build, ifEnemyCond)
	if mods and #mods > 0 then
		return true
	end
	local hasChanceBasedSource = false
	forEachIfOption(ifEnemyCond, function(enemyCondition)
		if hasChanceBasedSource then
			return
		end
		hasChanceBasedSource = getConditionApplyChanceInOneSecond(build, enemyCondition) ~= nil
	end)
	return hasChanceBasedSource
end

function helper.getEnemyConditionHints(varData)
	return varData.ifEnemyCond or manualEnemyConditionHintsByVar[varData.var]
end

function helper.formatConditionEffectTooltip(build, ifEnemyCond)
	local out
	forEachIfOption(ifEnemyCond, function(enemyCondition)
		if out then
			return
		end
		local lines = getConditionEffectLines(build, enemyCondition)
		if lines and next(lines) then
			out = helper.joinTooltipLines(unpack(lines))
		end
	end)
	return out
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
	local hasSource = helper.hasEnemyConditionSource(build, ifEnemyCond)
	local bestChance
	forEachIfOption(ifEnemyCond, function(enemyCondition)
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

function helper.hasFlagSource(build, ifFlag)
	if ifFlag == "applyFireExposure" then
		return helper.hasExposureSource(build, "Fire")
	end
	if ifFlag == "applyColdExposure" then
		return helper.hasExposureSource(build, "Cold")
	end
	if ifFlag == "applyLightningExposure" then
		return helper.hasExposureSource(build, "Lightning")
	end
	return false
end

function helper.hasExposureSource(build, element)
	local mainEnv = getMainEnv(build)
	local _, minionMainSkill = getPlayerAndMinionSkillData(build)
	local playerMainSkill = mainEnv and mainEnv.player and mainEnv.player.mainSkill
	if not mainEnv or not playerMainSkill then
		return false
	end
	if playerMainSkill.skillFlags and playerMainSkill.skillFlags["apply" .. element .. "Exposure"] then
		return true
	end
	if playerMainSkill.skillModList:Sum("BASE", playerMainSkill.skillCfg, element .. "ExposureChance") > 0 then
		return true
	end
	if mainEnv.modDB:Sum("BASE", nil, element .. "ExposureChance") > 0 then
		return true
	end
	if minionMainSkill and minionMainSkill.skillModList:Sum("BASE", minionMainSkill.skillCfg, element .. "ExposureChance") > 0 then
		return true
	end
	if #collectDirectEnemyModifierSourceMods(build, element .. "Exposure") > 0 then
		return true
	end
	return mainEnv.enemyDB and mainEnv.enemyDB:Sum("BASE", nil, element .. "Exposure") < 0 or false
end

function helper.formatConfigVarEffectTooltip(build, varName)
	local element = configVarElementMap[varName]
	if element then
		local exposure = getExposureMagnitude(build, element)
		if not exposure then
			return
		end
		return "^7When enabled, applies -" .. formatValue(exposure, 0) .. "% " .. element .. " Resistance."
	end
	local chargeConfig = getChargeConfig(build, varName)
	local output = getActorOutput(build, chargeConfig and chargeConfig.actor)
	if not chargeConfig or not output then
		return
	end
	local maxCharges = output[chargeConfig.maxStat]
	if not maxCharges or maxCharges <= 0 then
		return
	end
	local prefix = chargeConfig.actor == "minion" and "Current minion maximum " or "Current maximum "
	return "^7" .. prefix .. chargeConfig.label .. ": " .. formatValue(maxCharges, 0)
end

function helper.formatConfigVarChanceTooltip(build, varName)
	local element = configVarElementMap[varName]
	if element then
		local chanceData = getExposureChanceData(build, element)
		if not chanceData then
			return
		end
		local out = "^7Estimated apply chance within 1s: "
			.. formatValue(chanceData.combined * 100, 1) .. "%"
		local details = { }
		if chanceData.player then
			t_insert(
				details,
				"Player "
					.. formatValue(chanceData.player.chancePerHit * 100, 1)
					.. "%/hit, "
					.. formatValue(chanceData.player.attempts, 2)
					.. " effective hits/s"
			)
		end
		if chanceData.minion then
			t_insert(
				details,
				"Minion "
					.. formatValue(chanceData.minion.chancePerHit * 100, 1)
					.. "%/hit, "
					.. formatValue(chanceData.minion.attempts, 2)
					.. " effective hits/s"
			)
		end
		if #details > 0 then
			out = out .. "\n^8" .. t_concat(details, " | ")
		end
		return out
	end
	local chargeConfig = getChargeConfig(build, varName)
	if not chargeConfig then
		return
	end
	local matches = getChargeSourceMatches(build, varName)
	if matches then
		return "^7Detected charge generation sources: " .. t_concat(matches, ", ")
	end
end

function helper.getConfigVarRecommendationData(build, configInput, varName)
	local element = configVarElementMap[varName]
	if element then
		if not configInput or configInput[varName] then
			return
		end
		if not helper.hasExposureSource(build, element) then
			return
		end
		local chanceData = getExposureChanceData(build, element)
		if chanceData and chanceData.combined >= 0.75 then
			return {
				level = "strong",
				chance = chanceData.combined,
			}
		end
		if chanceData and chanceData.combined >= 0.35 then
			return {
				level = "medium",
				chance = chanceData.combined,
			}
		end
		return {
			level = "soft",
		}
	end
	local chargeConfig = getChargeConfig(build, varName)
	if not chargeConfig or not configInput or configInput[varName] then
		return
	end
	local matches = getChargeSourceMatches(build, varName)
	if matches then
		return {
			level = "strong",
			matches = matches,
			label = chargeConfig.label,
		}
	end
end

function helper.formatConfigVarRecommendationTooltip(build, configInput, varName)
	local recommendation = helper.getConfigVarRecommendationData(build, configInput, varName)
	if not recommendation then
		return
	end
	if recommendation.matches and recommendation.label then
		return "^2Suggestion: enable this option if " .. t_concat(recommendation.matches, ", ")
			.. " can sustain " .. recommendation.label .. " in combat."
	end
	if recommendation.level == "strong" and recommendation.chance then
		return "^2Suggestion: enable this option (" ..
			formatValue(recommendation.chance * 100, 1) .. "% within 1s)."
	end
	if recommendation.level == "medium" and recommendation.chance then
		return "^7Suggestion: consider enabling this option (" ..
			formatValue(recommendation.chance * 100, 1) .. "% within 1s)."
	end
	if recommendation.level == "soft" then
		return "^7Suggestion: source detected; enable when uptime is reliable."
	end
end

return helper
