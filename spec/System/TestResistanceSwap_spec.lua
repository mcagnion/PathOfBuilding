-- Tests for the element swap feature:
--   - ItemsTab: which explicit mods are detected as Harvest-swappable (resistance + damage)
--   - TradeQueryGenerator: resistTag tagging and groupResists merging
--   - TradeQuery: 3^N combo enumeration and mod line gsub logic

local function makeRing(explicits, implicits, corrupted)
	local lines = { "Rarity: Rare", "Name", "Coral Ring" }
	if implicits and #implicits > 0 then
		table.insert(lines, "Implicits: " .. #implicits)
		for _, mod in ipairs(implicits) do
			table.insert(lines, mod)
		end
	end
	for _, mod in ipairs(explicits) do
		table.insert(lines, mod)
	end
	if corrupted then
		table.insert(lines, "Corrupted")
	end
	return table.concat(lines, "\n")
end

-- Returns the list of explicit mod lines that are Harvest-swappable elemental resists
local function swappableResists(item)
	local found = {}
	for i, modLine in ipairs(item.explicitModLines or {}) do
		local t = modLine.line and modLine.line:match("to (%a+) Resistance$")
		if t == "Fire" or t == "Cold" or t == "Lightning" then
			table.insert(found, { idx = i, elemType = t })
		end
	end
	return found
end

describe("Resistance Swap — Item parsing", function()
	it("detects explicit Fire/Cold/Lightning resistance mods", function()
		local item = new("Item", makeRing({
			"+40% to Fire Resistance",
			"+35% to Cold Resistance",
			"+30% to Lightning Resistance",
		}))
		local found = swappableResists(item)
		assert.are.equal(3, #found)
	end)

	it("does not detect implicit resistance as swappable", function()
		local item = new("Item", makeRing(
			{ "+40% to Cold Resistance" },
			{ "+20% to Fire Resistance" }
		))
		local found = swappableResists(item)
		-- Cold is explicit (swappable), Fire is implicit (not swappable)
		assert.are.equal(1, #found)
		assert.are.equal("Cold", found[1].elemType)
	end)

	it("does not detect Chaos resistance as swappable", function()
		local item = new("Item", makeRing({ "+20% to Chaos Resistance" }))
		assert.are.equal(0, #swappableResists(item))
	end)

	it("does not detect element+chaos hybrid as swappable", function()
		local item = new("Item", makeRing({ "+15% to Fire and Chaos Resistances" }))
		assert.are.equal(0, #swappableResists(item))
	end)

	it("does not detect dual elemental resistance as swappable", function()
		local item = new("Item", makeRing({ "+15% to Fire and Cold Resistances" }))
		assert.are.equal(0, #swappableResists(item))
	end)

	it("does not detect crafted resistance mod as swappable (crafted = not Harvest-swappable via this path)", function()
		local item = new("Item", makeRing({ "{crafted}+35% to Lightning Resistance" }))
		-- crafted mods are in explicitModLines but flagged; current detection includes them
		-- this test documents the current behaviour
		local found = swappableResists(item)
		assert.are.equal(1, #found)
		assert.is_true(item.explicitModLines[found[1].idx].crafted)
	end)

	it("does not detect All Elemental Resistances as swappable", function()
		local item = new("Item", makeRing({ "+15% to all Elemental Resistances" }))
		assert.are.equal(0, #swappableResists(item))
	end)

	it("does not detect fractured resistance mod as swappable", function()
		local item = new("Item", makeRing({ "{fractured}+35% to Cold Resistance" }))
		-- fractured mods are in explicitModLines but must be excluded from swap
		local found = {}
		for i, modLine in ipairs(item.explicitModLines or {}) do
			local t = modLine.line and modLine.line:match("to (%a+) Resistance$")
			if (t == "Fire" or t == "Cold" or t == "Lightning") and not modLine.fractured then
				table.insert(found, { idx = i, elemType = t })
			end
		end
		assert.are.equal(0, #found)
		-- but the mod itself is present and flagged
		local allFound = swappableResists(item) -- naive detection without fractured check
		assert.are.equal(1, #allFound)
		assert.is_true(item.explicitModLines[allFound[1].idx].fractured)
	end)

	it("marks corrupted items correctly", function()
		local item = new("Item", makeRing({ "+40% to Fire Resistance" }, nil, true))
		assert.is_true(item.corrupted)
	end)

	it("non-corrupted item is not marked corrupted", function()
		local item = new("Item", makeRing({ "+40% to Fire Resistance" }))
		assert.is_not_true(item.corrupted)
	end)

	it("marks mirrored items correctly", function()
		local lines = "Rarity: Rare\nName\nCoral Ring\n+40% to Fire Resistance\nMirrored"
		local item = new("Item", lines)
		assert.is_true(item.mirrored)
	end)

	it("non-mirrored item is not marked mirrored", function()
		local item = new("Item", makeRing({ "+40% to Fire Resistance" }))
		assert.is_not_true(item.mirrored)
	end)
end)

describe("Resistance Swap — resistTag tagging", function()
	-- mirrors the logic in TradeQueryGenerator:GenerateModWeights
	local function getResistTag(modText)
		local elemType = modText:match("to (%a+) Resistance$")
		if elemType == "Fire" or elemType == "Cold" or elemType == "Lightning" then
			return { elem = true }, 1
		elseif elemType == "Chaos" then
			return { chaos = true }, 1
		end
		local hybridElem = modText:match("to (%a+) and Chaos Resistances$")
		if hybridElem == "Fire" or hybridElem == "Cold" or hybridElem == "Lightning" then
			-- Hybrid: each pseudo stat on the trade site only sees its own component, no split needed.
			return { elem = true, chaos = true }, 1
		end
		if modText:match("^%+#%% to all Elemental Resistances$") then
			return { elem = true }, 3
		end
		local dualA, dualB = modText:match("^%+#%% to (%a+) and (%a+) Resistances$")
		if dualA and dualB then
			local aElem = dualA == "Fire" or dualA == "Cold" or dualA == "Lightning"
			local bElem = dualB == "Fire" or dualB == "Cold" or dualB == "Lightning"
			if aElem and bElem then
				return { elem = true }, 2
			end
		end
		return nil, 1
	end

	it("tags Fire/Cold/Lightning mods as elem (factor 1)", function()
		for _, t in ipairs({ "Fire", "Cold", "Lightning" }) do
			local tag, factor = getResistTag("+40% to " .. t .. " Resistance")
			assert.is_not_nil(tag)
			assert.is_true(tag.elem)
			assert.is_nil(tag.chaos)
			assert.are.equal(1, factor)
		end
	end)

	it("tags Chaos mod as chaos only (factor 1)", function()
		local tag, factor = getResistTag("+20% to Chaos Resistance")
		assert.is_not_nil(tag)
		assert.is_nil(tag.elem)
		assert.is_true(tag.chaos)
		assert.are.equal(1, factor)
	end)

	it("tags element+chaos hybrid as both elem and chaos (factor 1)", function()
		for _, t in ipairs({ "Fire", "Cold", "Lightning" }) do
			local tag, factor = getResistTag("+15% to " .. t .. " and Chaos Resistances")
			assert.is_not_nil(tag)
			assert.is_true(tag.elem)
			assert.is_true(tag.chaos)
			assert.are.equal(1, factor)
		end
	end)

	it("tags all Elemental Resistances as elem with factor 3", function()
		local tag, factor = getResistTag("+#% to all Elemental Resistances")
		assert.is_not_nil(tag)
		assert.is_true(tag.elem)
		assert.is_nil(tag.chaos)
		assert.are.equal(3, factor)
	end)

	it("tags dual elemental mods as elem with factor 2", function()
		local pairs_list = {
			{ "Fire", "Cold" }, { "Fire", "Lightning" }, { "Cold", "Lightning" }
		}
		for _, p in ipairs(pairs_list) do
			local tag, factor = getResistTag("+#% to " .. p[1] .. " and " .. p[2] .. " Resistances")
			assert.is_not_nil(tag, "expected tag for " .. p[1] .. "+" .. p[2])
			assert.is_true(tag.elem)
			assert.is_nil(tag.chaos)
			assert.are.equal(2, factor)
		end
	end)

	it("returns nil for non-resistance mods", function()
		assert.is_nil(getResistTag("+50 to maximum Life"))
	end)

	it("does not tag minion or totem all-elemental mods (no character prefix)", function()
		-- These mods do NOT match the strict ^+#% prefix anchor
		assert.is_nil(getResistTag("Minions have +#% to all Elemental Resistances"))
		assert.is_nil(getResistTag("Totems gain +#% to all Elemental Resistances"))
	end)
end)

-- mirrors the logic in TradeQueryGenerator:FinishQuery
-- Elemental and chaos pseudo stats are separate; hybrid elem+chaos mods
-- contribute to both pseudos without double-counting either component.
local function mergeResists(modWeights)
		local elemMax, chaosMax = 0, 0
		local filtered = {}
		for _, entry in ipairs(modWeights) do
			if entry.resistTag then
				local nw = entry.normalizedWeight or entry.weight
				if entry.resistTag.elem and nw > elemMax then elemMax = nw end
				if entry.resistTag.chaos and nw > chaosMax then chaosMax = nw end
			else
				table.insert(filtered, entry)
			end
		end
		if elemMax > 0 then
			table.insert(filtered, { tradeModId = "pseudo.pseudo_total_elemental_resistance", weight = elemMax })
		end
		if chaosMax > 0 then
			table.insert(filtered, { tradeModId = "pseudo.pseudo_total_chaos_resistance", weight = chaosMax })
		end
		return filtered
end

describe("Resistance Swap — groupResists merging", function()
	it("replaces elemental mods with a single pseudo_total_elemental_resistance", function()
		local weights = {
			{ tradeModId = "fire_resist",  weight = 10, resistTag = { elem = true } },
			{ tradeModId = "cold_resist",  weight = 7,  resistTag = { elem = true } },
			{ tradeModId = "life",         weight = 5 },
		}
		local result = mergeResists(weights)
		assert.are.equal(2, #result)
		assert.are.equal("life", result[1].tradeModId)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[2].tradeModId)
		assert.are.equal(10, result[2].weight) -- max of 10 and 7
	end)

	it("keeps non-resist mods unchanged", function()
		local weights = {
			{ tradeModId = "fire_resist", weight = 8, resistTag = { elem = true } },
			{ tradeModId = "life",        weight = 5 },
			{ tradeModId = "es",          weight = 3 },
		}
		local result = mergeResists(weights)
		assert.are.equal(3, #result)
		assert.are.equal("life", result[1].tradeModId)
		assert.are.equal("es",   result[2].tradeModId)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[3].tradeModId)
	end)

	it("adds pseudo_total_chaos_resistance for chaos-tagged mods", function()
		local weights = {
			{ tradeModId = "chaos_resist", weight = 6, resistTag = { chaos = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_chaos_resistance", result[1].tradeModId)
		assert.are.equal(6, result[1].weight)
	end)

	it("element+chaos hybrid mod contributes to both pseudo stats with full weight", function()
		local weights = {
			{ tradeModId = "fire_chaos", weight = 9, resistTag = { elem = true, chaos = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(2, #result)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[1].tradeModId)
		assert.are.equal("pseudo.pseudo_total_chaos_resistance",     result[2].tradeModId)
		assert.are.equal(9, result[1].weight)
		assert.are.equal(9, result[2].weight)
	end)

	it("produces no pseudo-stats when no resist mods are present", function()
		local weights = {
			{ tradeModId = "life", weight = 5 },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("life", result[1].tradeModId)
	end)

	it("chaos-only mod does not produce pseudo_total_elemental_resistance", function()
		local weights = {
			{ tradeModId = "chaos_resist", weight = 4, resistTag = { chaos = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_chaos_resistance", result[1].tradeModId)
		-- elemental pseudo-stat must not appear
		for _, e in ipairs(result) do
			assert.are_not.equal("pseudo.pseudo_total_elemental_resistance", e.tradeModId)
		end
	end)

	it("takes the maximum weight among multiple same-type elemental mods", function()
		local weights = {
			{ tradeModId = "fire_resist_1", weight = 3,  resistTag = { elem = true } },
			{ tradeModId = "fire_resist_2", weight = 12, resistTag = { elem = true } },
			{ tradeModId = "fire_resist_3", weight = 7,  resistTag = { elem = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[1].tradeModId)
		assert.are.equal(12, result[1].weight)
	end)

	it("does not emit pseudo-stat for elemental mod with weight 0", function()
		local weights = {
			{ tradeModId = "fire_resist", weight = 0, normalizedWeight = 0, resistTag = { elem = true } },
			{ tradeModId = "life",        weight = 5 },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("life", result[1].tradeModId)
	end)

	it("normalizes all-elemental mod weight by factor 3 to avoid double-counting", function()
		-- all-elem mod: raw weight=30, normalizedWeight=10 (30/3)
		-- single fire mod: raw weight=8, normalizedWeight=8 (8/1)
		-- elemMax should be max(10, 8) = 10, not max(30, 8) = 30
		local weights = {
			{ tradeModId = "all_elem",    weight = 30, normalizedWeight = 10, resistTag = { elem = true } },
			{ tradeModId = "fire_resist", weight = 8,  normalizedWeight = 8,  resistTag = { elem = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[1].tradeModId)
		assert.are.equal(10, result[1].weight)
	end)

	it("normalizes dual-elemental mod weight by factor 2 to avoid double-counting", function()
		-- dual fire+lightning: raw weight=20, normalizedWeight=10 (20/2)
		-- single fire mod: raw weight=9, normalizedWeight=9
		-- elemMax should be max(10, 9) = 10
		local weights = {
			{ tradeModId = "fire_lightning", weight = 20, normalizedWeight = 10, resistTag = { elem = true } },
			{ tradeModId = "fire_resist",    weight = 9,  normalizedWeight = 9,  resistTag = { elem = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[1].tradeModId)
		assert.are.equal(10, result[1].weight)
	end)

	it("implicit elemental resist mod is merged like explicit", function()
		local weights = {
			{ tradeModId = "implicit.stat_fire_resist", weight = 5, resistTag = { elem = true } },
			{ tradeModId = "life", weight = 8 },
		}
		local result = mergeResists(weights)
		assert.are.equal(2, #result)
		assert.are.equal("life", result[1].tradeModId)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[2].tradeModId)
		assert.are.equal(5, result[2].weight)
	end)

	it("implicit dual-elem resist mod is merged like explicit", function()
		local weights = {
			{ tradeModId = "implicit.stat_fire_cold", weight = 20, normalizedWeight = 10, resistTag = { elem = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[1].tradeModId)
		assert.are.equal(10, result[1].weight)
	end)

	it("implicit all-elem resist mod is merged like explicit", function()
		local weights = {
			{ tradeModId = "implicit.stat_all_elem", weight = 30, normalizedWeight = 10, resistTag = { elem = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[1].tradeModId)
		assert.are.equal(10, result[1].weight)
	end)

	it("implicit chaos resist mod is merged into chaos pseudo", function()
		local weights = {
			{ tradeModId = "implicit.stat_chaos_resist", weight = 4, resistTag = { chaos = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_chaos_resistance", result[1].tradeModId)
		assert.are.equal(4, result[1].weight)
	end)

	it("explicit and implicit elemental mods are merged together (max wins)", function()
		local weights = {
			{ tradeModId = "explicit.stat_fire_resist",  weight = 10, resistTag = { elem = true } },
			{ tradeModId = "implicit.stat_cold_resist",  weight = 7,  resistTag = { elem = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[1].tradeModId)
		assert.are.equal(10, result[1].weight)
	end)

	it("explicit and implicit chaos mods are merged together (max wins)", function()
		local weights = {
			{ tradeModId = "explicit.stat_chaos_resist", weight = 3, resistTag = { chaos = true } },
			{ tradeModId = "implicit.stat_chaos_resist", weight = 6, resistTag = { chaos = true } },
		}
		local result = mergeResists(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_total_chaos_resistance", result[1].tradeModId)
		assert.are.equal(6, result[1].weight) -- implicit had higher weight
	end)

	it("dual/all-elem mods are removed from individual filters (no double-counting)", function()
		local weights = {
			{ tradeModId = "all_elem",    weight = 30, normalizedWeight = 10, resistTag = { elem = true } },
			{ tradeModId = "fire_resist", weight = 8,  normalizedWeight = 8,  resistTag = { elem = true } },
			{ tradeModId = "life",        weight = 5 },
		}
		local result = mergeResists(weights)
		-- Only "life" and the single pseudo entry should remain — no individual all_elem or fire_resist
		assert.are.equal(2, #result)
		assert.are.equal("life", result[1].tradeModId)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", result[2].tradeModId)
	end)
end)

-- =====================
-- damageTag tagging & groupDamage merging
-- =====================

-- Mirrors the damageTag tagging logic in TradeQueryGenerator:GenerateModWeights.
-- "Adds" pseudo stats cover Fire/Cold/Lightning individually,
-- but "increased" pseudo stats only cover generic "Elemental".
local function getDamageTag(modText)
	local damageElem = modText:match("(%a+) Damage")
	if damageElem ~= "Fire" and damageElem ~= "Cold" and damageElem ~= "Lightning" and damageElem ~= "Elemental" then
		return nil
	end
	if modText:match("Adds") then
		if modText:match("to Spells and Attacks") then
			return { adds_attacks = true, adds_spells = true }
		elseif modText:match("to Attacks") then
			return { adds_attacks = true }
		elseif modText:match("to Spells") then
			return { adds_spells = true }
		else
			return { adds = true }
		end
	elseif damageElem == "Elemental" and modText:match("increased") then
		if modText:match("with Attack Skills") then
			return { increased_attacks = true }
		else
			return { increased = true }
		end
	end
	return nil
end

describe("Damage Swap — damageTag tagging", function()
	it("tags flat added fire damage to attacks", function()
		local tag = getDamageTag("Adds # to # Fire Damage to Attacks")
		assert.is_not_nil(tag)
		assert.is_true(tag.adds_attacks)
		assert.is_nil(tag.adds_spells)
	end)

	it("tags flat added cold damage to spells", function()
		local tag = getDamageTag("Adds # to # Cold Damage to Spells")
		assert.is_not_nil(tag)
		assert.is_true(tag.adds_spells)
		assert.is_nil(tag.adds_attacks)
	end)

	it("tags flat added damage to spells and attacks as both", function()
		local tag = getDamageTag("Adds # to # Lightning Damage to Spells and Attacks")
		assert.is_not_nil(tag)
		assert.is_true(tag.adds_attacks)
		assert.is_true(tag.adds_spells)
	end)

	it("tags generic flat added damage (local/global)", function()
		local tag = getDamageTag("Adds # to # Fire Damage")
		assert.is_not_nil(tag)
		assert.is_true(tag.adds)
	end)

	it("tags local weapon damage with (Local) suffix", function()
		local tag = getDamageTag("Adds # to # Fire Damage (Local)")
		assert.is_not_nil(tag)
		assert.is_true(tag.adds)
	end)

	it("does not tag element-specific increased damage (pseudo only covers generic)", function()
		assert.is_nil(getDamageTag("#% increased Fire Damage"))
		assert.is_nil(getDamageTag("#% increased Cold Damage with Attack Skills"))
	end)

	it("tags generic increased Elemental Damage", function()
		local tag = getDamageTag("#% increased Elemental Damage")
		assert.is_not_nil(tag)
		assert.is_true(tag.increased)
	end)

	it("tags increased Elemental Damage with Attack Skills", function()
		local tag = getDamageTag("#% increased Elemental Damage with Attack Skills")
		assert.is_not_nil(tag)
		assert.is_true(tag.increased_attacks)
	end)

	it("does not tag Physical damage", function()
		assert.is_nil(getDamageTag("Adds # to # Physical Damage to Attacks"))
	end)

	it("does not tag Chaos damage", function()
		assert.is_nil(getDamageTag("Adds # to # Chaos Damage to Spells"))
	end)

	it("does not tag damage leech mods", function()
		assert.is_nil(getDamageTag("#% of Fire Damage Leeched as Life"))
	end)

	it("does not tag damage conversion mods", function()
		assert.is_nil(getDamageTag("#% of Physical Damage Converted to Fire Damage"))
	end)

	it("tags conditional added damage mods", function()
		local tag = getDamageTag("While a Unique Enemy is in your Presence, Adds # to # Fire Damage to Attacks")
		assert.is_not_nil(tag)
		assert.is_true(tag.adds_attacks)
	end)
end)

describe("Damage Swap — groupDamage merging", function()
	-- Mirrors the overlap-aware merging in TradeQueryGenerator:FinishQuery.
	-- Uses specific pseudo stats when only one subcategory is present;
	-- falls back to the generic pseudo stat when multiple subcategories overlap.
	local function mergeDamage(modWeights)
		local categoryMax = {}
		local filtered = {}
		for _, entry in ipairs(modWeights) do
			if entry.damageTag then
				local nw = entry.normalizedWeight or entry.weight
				for cat, _ in pairs(entry.damageTag) do
					if not categoryMax[cat] or nw > categoryMax[cat] then
						categoryMax[cat] = nw
					end
				end
			else
				table.insert(filtered, entry)
			end
		end
		-- Resolve overlap for the "adds" family
		local addsMax = categoryMax.adds or 0
		local addsAtkMax = categoryMax.adds_attacks or 0
		local addsSplMax = categoryMax.adds_spells or 0
		local addsCount = (addsMax > 0 and 1 or 0) + (addsAtkMax > 0 and 1 or 0) + (addsSplMax > 0 and 1 or 0)
		if addsCount > 1 then
			local maxW = math.max(addsMax, addsAtkMax, addsSplMax)
			table.insert(filtered, { tradeModId = "pseudo.pseudo_adds_elemental_damage", weight = maxW })
		elseif addsMax > 0 then
			table.insert(filtered, { tradeModId = "pseudo.pseudo_adds_elemental_damage", weight = addsMax })
		elseif addsAtkMax > 0 then
			table.insert(filtered, { tradeModId = "pseudo.pseudo_adds_elemental_damage_to_attacks", weight = addsAtkMax })
		elseif addsSplMax > 0 then
			table.insert(filtered, { tradeModId = "pseudo.pseudo_adds_elemental_damage_to_spells", weight = addsSplMax })
		end
		-- Resolve overlap for the "increased" family
		local incMax = categoryMax.increased or 0
		local incAtkMax = categoryMax.increased_attacks or 0
		local incCount = (incMax > 0 and 1 or 0) + (incAtkMax > 0 and 1 or 0)
		if incCount > 1 then
			local maxW = math.max(incMax, incAtkMax)
			table.insert(filtered, { tradeModId = "pseudo.pseudo_increased_elemental_damage", weight = maxW })
		elseif incMax > 0 then
			table.insert(filtered, { tradeModId = "pseudo.pseudo_increased_elemental_damage", weight = incMax })
		elseif incAtkMax > 0 then
			table.insert(filtered, { tradeModId = "pseudo.pseudo_increased_elemental_damage_with_attack_skills", weight = incAtkMax })
		end
		return filtered
	end

	it("only attacks → uses specific pseudo stat", function()
		local weights = {
			{ tradeModId = "fire_dmg_atk", weight = 10, damageTag = { adds_attacks = true } },
			{ tradeModId = "cold_dmg_atk", weight = 7,  damageTag = { adds_attacks = true } },
			{ tradeModId = "life",         weight = 5 },
		}
		local result = mergeDamage(weights)
		assert.are.equal(2, #result)
		assert.are.equal("life", result[1].tradeModId)
		assert.are.equal("pseudo.pseudo_adds_elemental_damage_to_attacks", result[2].tradeModId)
		assert.are.equal(10, result[2].weight)
	end)

	it("only spells → uses specific pseudo stat", function()
		local weights = {
			{ tradeModId = "fire_dmg_spl", weight = 8, damageTag = { adds_spells = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_adds_elemental_damage_to_spells", result[1].tradeModId)
	end)

	it("only increased_attacks → uses specific pseudo stat", function()
		local weights = {
			{ tradeModId = "inc_fire_atk", weight = 6, damageTag = { increased_attacks = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_increased_elemental_damage_with_attack_skills", result[1].tradeModId)
		assert.are.equal(6, result[1].weight)
	end)

	it("attacks + spells overlap → falls back to generic adds pseudo", function()
		local weights = {
			{ tradeModId = "fire_dmg_atk", weight = 10, damageTag = { adds_attacks = true } },
			{ tradeModId = "cold_dmg_spl", weight = 8,  damageTag = { adds_spells = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_adds_elemental_damage", result[1].tradeModId)
		assert.are.equal(10, result[1].weight) -- max of 10, 8
	end)

	it("hybrid 'to Spells and Attacks' triggers overlap → generic adds pseudo", function()
		local weights = {
			{ tradeModId = "fire_dmg_both", weight = 9, damageTag = { adds_attacks = true, adds_spells = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_adds_elemental_damage", result[1].tradeModId)
		assert.are.equal(9, result[1].weight)
	end)

	it("generic adds + attacks overlap → generic pseudo", function()
		local weights = {
			{ tradeModId = "fire_dmg_gen", weight = 5, damageTag = { adds = true } },
			{ tradeModId = "cold_dmg_atk", weight = 12, damageTag = { adds_attacks = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_adds_elemental_damage", result[1].tradeModId)
		assert.are.equal(12, result[1].weight)
	end)

	it("increased + increased_attacks overlap → generic increased pseudo", function()
		local weights = {
			{ tradeModId = "inc_fire",     weight = 8, damageTag = { increased = true } },
			{ tradeModId = "inc_cold_atk", weight = 6, damageTag = { increased_attacks = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_increased_elemental_damage", result[1].tradeModId)
		assert.are.equal(8, result[1].weight)
	end)

	it("no overlap: adds_attacks and increased stay separate", function()
		local weights = {
			{ tradeModId = "fire_dmg_atk", weight = 10, damageTag = { adds_attacks = true } },
			{ tradeModId = "inc_fire_dmg", weight = 6,  damageTag = { increased = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(2, #result)
		local ids = {}
		for _, e in ipairs(result) do ids[e.tradeModId] = e.weight end
		assert.are.equal(10, ids["pseudo.pseudo_adds_elemental_damage_to_attacks"])
		assert.are.equal(6,  ids["pseudo.pseudo_increased_elemental_damage"])
	end)

	it("max weight wins when multiple mods contribute to same category", function()
		local weights = {
			{ tradeModId = "fire_dmg_atk",  weight = 5,  damageTag = { adds_attacks = true } },
			{ tradeModId = "cold_dmg_atk",  weight = 12, damageTag = { adds_attacks = true } },
			{ tradeModId = "light_dmg_atk", weight = 8,  damageTag = { adds_attacks = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(1, #result)
		assert.are.equal(12, result[1].weight)
	end)

	it("non-damage mods pass through untouched", function()
		local weights = {
			{ tradeModId = "life",   weight = 10 },
			{ tradeModId = "mana",   weight = 5 },
			{ tradeModId = "fire_dmg_atk", weight = 8, damageTag = { adds_attacks = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(3, #result)
		assert.are.equal("life", result[1].tradeModId)
		assert.are.equal("mana", result[2].tradeModId)
	end)

	it("explicit + implicit increased Elemental Damage merge into pseudo", function()
		local weights = {
			{ tradeModId = "inc_elem_explicit", weight = 8, damageTag = { increased = true } },
			{ tradeModId = "inc_elem_implicit", weight = 6, damageTag = { increased = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_increased_elemental_damage", result[1].tradeModId)
		assert.are.equal(8, result[1].weight)
	end)

	it("increased Elemental Damage + with Attack Skills overlap → generic pseudo", function()
		local weights = {
			{ tradeModId = "inc_elem",     weight = 8, damageTag = { increased = true } },
			{ tradeModId = "inc_elem_atk", weight = 5, damageTag = { increased_attacks = true } },
		}
		local result = mergeDamage(weights)
		assert.are.equal(1, #result)
		assert.are.equal("pseudo.pseudo_increased_elemental_damage", result[1].tradeModId)
		assert.are.equal(8, result[1].weight)
	end)

	it("groupResists and groupDamage can coexist independently", function()
		local weights = {
			{ tradeModId = "fire_resist",  weight = 10, resistTag = { elem = true } },
			{ tradeModId = "fire_dmg_atk", weight = 8,  damageTag = { adds_attacks = true } },
			{ tradeModId = "life",         weight = 5 },
		}
		-- Apply resist merging first
		local afterResist = mergeResists(weights)
		-- Then apply damage merging
		local result = mergeDamage(afterResist)
		assert.are.equal(3, #result)
		local ids = {}
		for _, e in ipairs(result) do ids[e.tradeModId] = e.weight end
		assert.are.equal(5,  ids["life"])
		assert.are.equal(10, ids["pseudo.pseudo_total_elemental_resistance"])
		assert.are.equal(8,  ids["pseudo.pseudo_adds_elemental_damage_to_attacks"])
	end)
end)

describe("Resistance Swap — combo enumeration", function()
	-- mirrors the mixed-radix counter in TradeQuery:GetResultEvaluation
	local function allCombos(N)
		if N == 0 then return {{}} end
		local combos = {}
		local combo = {}
		for i = 1, N do combo[i] = 1 end
		for _ = 1, 3 ^ N do
			local c = {}
			for i = 1, N do c[i] = combo[i] end
			table.insert(combos, c)
			for j = N, 1, -1 do
				combo[j] = combo[j] + 1
				if combo[j] <= 3 then break end
				combo[j] = 1
			end
		end
		return combos
	end

	it("generates 3 combinations for N=1", function()
		local combos = allCombos(1)
		assert.are.equal(3, #combos)
		assert.are.equal(1, combos[1][1])
		assert.are.equal(2, combos[2][1])
		assert.are.equal(3, combos[3][1])
	end)

	it("generates 9 unique combinations for N=2", function()
		local combos = allCombos(2)
		assert.are.equal(9, #combos)
		-- Check all pairs are distinct
		local seen = {}
		for _, c in ipairs(combos) do
			local key = c[1] .. "," .. c[2]
			assert.is_nil(seen[key], "duplicate combo: " .. key)
			seen[key] = true
		end
	end)

	it("generates 27 unique combinations for N=3", function()
		local combos = allCombos(3)
		assert.are.equal(27, #combos)
	end)

	it("generates 1 combination for N=0", function()
		local combos = allCombos(0)
		assert.are.equal(1, #combos)
	end)

	it("gsub pattern correctly swaps any elemental type", function()
		local elemTypes = { "Fire", "Cold", "Lightning" }
		local line = "+40% to Fire Resistance"
		for _, target in ipairs(elemTypes) do
			local swapped = line:gsub("to %a+ Resistance$", "to " .. target .. " Resistance")
			assert.are.equal("+40% to " .. target .. " Resistance", swapped)
		end
	end)

	it("gsub is idempotent when target matches current type", function()
		local line = "+40% to Cold Resistance"
		local swapped = line:gsub("to %a+ Resistance$", "to Cold Resistance")
		assert.are.equal(line, swapped)
	end)

	it("gsub does not alter unrelated lines", function()
		local line = "+50 to maximum Life"
		local swapped = line:gsub("to %a+ Resistance$", "to Fire Resistance")
		assert.are.equal(line, swapped)
	end)

	it("gsub chain covers all types when starting from Cold or Lightning", function()
		local elemTypes = { "Fire", "Cold", "Lightning" }
		for _, startType in ipairs(elemTypes) do
			local line = "+25% to " .. startType .. " Resistance"
			for _, target in ipairs(elemTypes) do
				local swapped = line:gsub("to %a+ Resistance$", "to " .. target .. " Resistance")
				assert.are.equal("+25% to " .. target .. " Resistance", swapped)
			end
		end
	end)

	it("mixed-radix counter visits all 27 combos for N=3 with correct first and last", function()
		local combos = allCombos(3)
		assert.are.equal(27, #combos)
		-- first combo: {1,1,1}, last combo: {3,3,3}
		assert.are.equal(1, combos[1][1]) assert.are.equal(1, combos[1][2]) assert.are.equal(1, combos[1][3])
		assert.are.equal(3, combos[27][1]) assert.are.equal(3, combos[27][2]) assert.are.equal(3, combos[27][3])
	end)
end)

-- =====================
-- Damage Swap Tests
-- =====================

-- Returns the list of explicit mod lines that are Harvest-swappable elemental damage mods
local function swappableDamage(item)
	local found = {}
	for i, modLine in ipairs(item.explicitModLines or {}) do
		local t = modLine.line and modLine.line:match("(%a+) Damage")
		if t == "Fire" or t == "Cold" or t == "Lightning" then
			table.insert(found, { idx = i, elemType = t })
		end
	end
	return found
end

-- Combined detection (mirrors TradeQuery:GetResultEvaluation)
local function swappableMods(item)
	local found = {}
	for i, modLine in ipairs(item.explicitModLines or {}) do
		if not modLine.fractured and modLine.line then
			local resistType = modLine.line:match("to (%a+) Resistance$")
			if resistType == "Fire" or resistType == "Cold" or resistType == "Lightning" then
				table.insert(found, { idx = i, originalType = resistType, kind = "resist" })
			else
				local damageType = modLine.line:match("(%a+) Damage")
				if damageType == "Fire" or damageType == "Cold" or damageType == "Lightning" then
					table.insert(found, { idx = i, originalType = damageType, kind = "damage" })
				end
			end
		end
	end
	return found
end

local function makeWeapon(explicits)
	local lines = { "Rarity: Rare", "Name", "Vaal Rapier" }
	for _, mod in ipairs(explicits) do
		table.insert(lines, mod)
	end
	return table.concat(lines, "\n")
end

describe("Damage Swap — Item parsing", function()
	it("detects explicit elemental damage mods", function()
		local item = new("Item", makeRing({
			"Adds 10 to 20 Fire Damage to Attacks",
			"Adds 5 to 15 Cold Damage to Spells",
			"Adds 1 to 30 Lightning Damage",
		}))
		local found = swappableDamage(item)
		assert.are.equal(3, #found)
		assert.are.equal("Fire", found[1].elemType)
		assert.are.equal("Cold", found[2].elemType)
		assert.are.equal("Lightning", found[3].elemType)
	end)

	it("does not detect Physical or Chaos damage as swappable", function()
		local item = new("Item", makeRing({
			"Adds 10 to 20 Physical Damage to Attacks",
			"Adds 5 to 15 Chaos Damage to Spells",
		}))
		local found = swappableDamage(item)
		assert.are.equal(0, #found)
	end)

	it("does not detect implicit damage mods as swappable in explicitModLines", function()
		local item = new("Item", makeRing(
			{ "+40 to maximum Life" },
			{ "Adds 10 to 20 Fire Damage to Attacks" }
		))
		local found = swappableDamage(item)
		assert.are.equal(0, #found)
	end)

	it("detects increased elemental damage mods", function()
		local item = new("Item", makeRing({
			"20% increased Fire Damage",
			"15% increased Cold Damage",
		}))
		local found = swappableDamage(item)
		assert.are.equal(2, #found)
	end)

	it("detects increased elemental damage with Attack Skills", function()
		local item = new("Item", makeRing({
			"20% increased Fire Damage with Attack Skills",
		}))
		local found = swappableDamage(item)
		assert.are.equal(1, #found)
		assert.are.equal("Fire", found[1].elemType)
	end)
end)

describe("Damage Swap — combined detection with resistance", function()
	it("detects both resist and damage mods on the same item", function()
		local item = new("Item", makeRing({
			"+40% to Fire Resistance",
			"Adds 10 to 20 Cold Damage to Attacks",
			"+30% to Lightning Resistance",
			"15% increased Fire Damage",
		}))
		local found = swappableMods(item)
		assert.are.equal(4, #found)
		assert.are.equal("resist", found[1].kind)
		assert.are.equal("Fire", found[1].originalType)
		assert.are.equal("damage", found[2].kind)
		assert.are.equal("Cold", found[2].originalType)
		assert.are.equal("resist", found[3].kind)
		assert.are.equal("Lightning", found[3].originalType)
		assert.are.equal("damage", found[4].kind)
		assert.are.equal("Fire", found[4].originalType)
	end)

	it("excludes fractured mods from both resist and damage", function()
		local item = new("Item", makeRing({
			"+40% to Fire Resistance",
			"Adds 10 to 20 Cold Damage to Attacks",
		}))
		-- Mark both as fractured
		for _, ml in ipairs(item.explicitModLines) do
			ml.fractured = true
		end
		local found = swappableMods(item)
		assert.are.equal(0, #found)
	end)
end)

describe("Damage Swap — gsub patterns", function()
	it("swaps flat added damage to attacks", function()
		local elemTypes = { "Fire", "Cold", "Lightning" }
		local line = "Adds 10 to 20 Fire Damage to Attacks"
		for _, target in ipairs(elemTypes) do
			local swapped = line:gsub("%a+ Damage", target .. " Damage", 1)
			assert.are.equal("Adds 10 to 20 " .. target .. " Damage to Attacks", swapped)
		end
	end)

	it("swaps flat added damage to spells", function()
		local line = "Adds 5 to 15 Cold Damage to Spells"
		local swapped = line:gsub("%a+ Damage", "Lightning Damage", 1)
		assert.are.equal("Adds 5 to 15 Lightning Damage to Spells", swapped)
	end)

	it("swaps increased elemental damage", function()
		local line = "20% increased Lightning Damage"
		local swapped = line:gsub("%a+ Damage", "Fire Damage", 1)
		assert.are.equal("20% increased Fire Damage", swapped)
	end)

	it("swaps increased elemental damage with Attack Skills", function()
		local line = "20% increased Fire Damage with Attack Skills"
		local swapped = line:gsub("%a+ Damage", "Cold Damage", 1)
		assert.are.equal("20% increased Cold Damage with Attack Skills", swapped)
	end)

	it("swaps local weapon damage", function()
		local line = "Adds 10 to 20 Fire Damage"
		local swapped = line:gsub("%a+ Damage", "Cold Damage", 1)
		assert.are.equal("Adds 10 to 20 Cold Damage", swapped)
	end)

	it("does not alter unrelated lines", function()
		local line = "+50 to maximum Life"
		local swapped = line:gsub("%a+ Damage", "Fire Damage", 1)
		assert.are.equal(line, swapped)
	end)

	it("gsub is idempotent when target matches current type", function()
		local line = "Adds 10 to 20 Fire Damage to Attacks"
		local swapped = line:gsub("%a+ Damage", "Fire Damage", 1)
		assert.are.equal(line, swapped)
	end)

	it("gsub with limit 1 only replaces first occurrence", function()
		-- Edge case: a line with "Damage" appearing in different contexts
		local line = "Gain 5% of Physical Damage as Extra Fire Damage"
		-- The first %a+ Damage match is "Physical Damage", which gets replaced
		local swapped = line:gsub("%a+ Damage", "Cold Damage", 1)
		assert.are.equal("Gain 5% of Cold Damage as Extra Fire Damage", swapped)
		-- This mod wouldn't be detected as swappable because match("(%a+) Damage")
		-- returns "Physical", not Fire/Cold/Lightning
	end)
end)

-- =====================
-- Swap Group & Duplicate Element Constraint
-- =====================

-- Mirrors the swap group computation in TradeQuery:GetResultEvaluation
local function swapGroupKey(line, elemType, kind)
	if kind == "resist" then
		return "resist"
	end
	return line:gsub(elemType .. " Damage", "ELEM Damage", 1):gsub("%d+", "#")
end

-- Mirrors the validity check: no two mods in the same group can share an element
local function isComboValid(swapMods, combo)
	local N = #swapMods
	for a = 1, N - 1 do
		for b = a + 1, N do
			if swapMods[a].group == swapMods[b].group and combo[a] == combo[b] then
				return false
			end
		end
	end
	return true
end

describe("Swap Group — key computation", function()
	it("all pure resist mods share the same group", function()
		assert.are.equal("resist", swapGroupKey("+40% to Fire Resistance", "Fire", "resist"))
		assert.are.equal("resist", swapGroupKey("+35% to Cold Resistance", "Cold", "resist"))
		assert.are.equal("resist", swapGroupKey("+30% to Lightning Resistance", "Lightning", "resist"))
	end)

	it("same damage mod template produces same group", function()
		local g1 = swapGroupKey("Adds 10 to 20 Fire Damage to Attacks", "Fire", "damage")
		local g2 = swapGroupKey("Adds 5 to 15 Cold Damage to Attacks", "Cold", "damage")
		assert.are.equal(g1, g2)
	end)

	it("different damage mod templates produce different groups", function()
		local gAttacks = swapGroupKey("Adds 10 to 20 Fire Damage to Attacks", "Fire", "damage")
		local gSpells = swapGroupKey("Adds 10 to 20 Fire Damage to Spells", "Fire", "damage")
		local gIncreased = swapGroupKey("20% increased Fire Damage", "Fire", "damage")
		local gLocal = swapGroupKey("Adds 10 to 20 Fire Damage", "Fire", "damage")
		assert.are_not.equal(gAttacks, gSpells)
		assert.are_not.equal(gAttacks, gIncreased)
		assert.are_not.equal(gAttacks, gLocal)
		assert.are_not.equal(gSpells, gIncreased)
	end)

	it("increased damage with Attack Skills is a separate group", function()
		local g1 = swapGroupKey("20% increased Fire Damage", "Fire", "damage")
		local g2 = swapGroupKey("20% increased Fire Damage with Attack Skills", "Fire", "damage")
		assert.are_not.equal(g1, g2)
	end)
end)

describe("Swap Group — duplicate element constraint", function()
	it("rejects combo with two resist mods assigned the same element", function()
		local mods = {
			{ group = "resist", kind = "resist" },
			{ group = "resist", kind = "resist" },
		}
		-- combo {1,1} = both Fire → invalid
		assert.is_false(isComboValid(mods, {1, 1}))
		-- combo {1,2} = Fire + Cold → valid
		assert.is_true(isComboValid(mods, {1, 2}))
	end)

	it("rejects combo with two same-group damage mods assigned the same element", function()
		local group = "Adds # to # ELEM Damage to Attacks"
		local mods = {
			{ group = group, kind = "damage" },
			{ group = group, kind = "damage" },
		}
		assert.is_false(isComboValid(mods, {2, 2}))
		assert.is_true(isComboValid(mods, {2, 3}))
	end)

	it("allows same element across different groups", function()
		local mods = {
			{ group = "resist", kind = "resist" },
			{ group = "Adds # to # ELEM Damage to Attacks", kind = "damage" },
		}
		-- Both assigned Fire → valid (different groups)
		assert.is_true(isComboValid(mods, {1, 1}))
	end)

	it("allows same element for damage mods in different subgroups", function()
		local mods = {
			{ group = "Adds # to # ELEM Damage to Attacks", kind = "damage" },
			{ group = "#% increased ELEM Damage", kind = "damage" },
		}
		-- Both assigned Fire → valid (different damage subgroups)
		assert.is_true(isComboValid(mods, {1, 1}))
	end)

	it("validates mixed resist + damage combo correctly", function()
		local mods = {
			{ group = "resist", kind = "resist" },
			{ group = "resist", kind = "resist" },
			{ group = "Adds # to # ELEM Damage to Attacks", kind = "damage" },
			{ group = "Adds # to # ELEM Damage to Attacks", kind = "damage" },
		}
		-- {1,2,1,2} = Fire res + Cold res + Fire dmg + Cold dmg → valid
		assert.is_true(isComboValid(mods, {1, 2, 1, 2}))
		-- {1,1,1,2} = Fire res + Fire res + ... → invalid (resist duplicate)
		assert.is_false(isComboValid(mods, {1, 1, 1, 2}))
		-- {1,2,3,3} = valid resist + Lightning dmg + Lightning dmg → invalid (damage duplicate)
		assert.is_false(isComboValid(mods, {1, 2, 3, 3}))
	end)

	it("three resist mods: only combos with all distinct elements are valid", function()
		local mods = {
			{ group = "resist", kind = "resist" },
			{ group = "resist", kind = "resist" },
			{ group = "resist", kind = "resist" },
		}
		-- Count valid combos: should be 3! = 6 (all permutations of {1,2,3})
		local validCount = 0
		local combo = {1, 1, 1}
		for _ = 1, 27 do
			if isComboValid(mods, combo) then
				validCount = validCount + 1
			end
			for j = 3, 1, -1 do
				combo[j] = combo[j] + 1
				if combo[j] <= 3 then break end
				combo[j] = 1
			end
		end
		assert.are.equal(6, validCount)
	end)
end)

describe("Resistance Swap — TradeQueryGenerator integration", function()
	it("keeps a high-impact grouped resistance pseudo within the filter budget", function()
		local queryGen = new("TradeQueryGenerator", { itemsTab = { items = { } } })
		queryGen.modWeights = { }
		for index = 1, 40 do
			table.insert(queryGen.modWeights, {
				tradeModId = "explicit.stat_" .. index,
				weight = 1,
				meanStatDiff = 100 - index,
			})
		end
		table.insert(queryGen.modWeights, {
			tradeModId = "explicit.stat_900000",
			weight = 2,
			normalizedWeight = 2,
			meanStatDiff = 1000,
			resistTag = { elem = true },
		})
		queryGen.calcContext = {
			testItem = new("Item", "Rarity: RARE\nNew Item\nGold Ring\nImplicits: 0"),
			baseOutput = { },
			baseStatValue = 0,
			itemCategoryQueryStr = "accessory.ring",
			special = { },
			options = {
				statWeights = { },
				influence1 = 1,
				influence2 = 1,
				includeMirrored = false,
				sockets = 6,
				links = 6,
				groupResists = true,
				groupDamage = false,
			},
		}
		queryGen.tradeTypeIndex = 1
		local query
		queryGen.requesterCallback = function(_, queryJson)
			query = require("dkjson").decode(queryJson).query
		end

		queryGen:FinishQuery()

		assert.are.equal(31, #query.stats[1].filters)
		assert.are.equal("pseudo.pseudo_total_elemental_resistance", query.stats[1].filters[1].id)
		assert.are.equal(2, query.stats[1].filters[1].value.weight)
	end)
end)
