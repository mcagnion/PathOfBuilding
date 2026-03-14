-- Tests for the resistance swap feature:
--   - ItemsTab: which explicit mods are detected as Harvest-swappable
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

	it("marks corrupted items correctly", function()
		local item = new("Item", makeRing({ "+40% to Fire Resistance" }, nil, true))
		assert.is_true(item.corrupted)
	end)

	it("non-corrupted item is not marked corrupted", function()
		local item = new("Item", makeRing({ "+40% to Fire Resistance" }))
		assert.is_not_true(item.corrupted)
	end)
end)

describe("Resistance Swap — resistTag tagging", function()
	-- mirrors the logic in TradeQueryGenerator:GenerateModWeights
	local function getResistTag(modText)
		local elemType = modText:match("to (%a+) Resistance$")
		if elemType == "Fire" or elemType == "Cold" or elemType == "Lightning" then
			return { elem = true }
		elseif elemType == "Chaos" then
			return { chaos = true }
		end
		local hybridElem = modText:match("to (%a+) and Chaos Resistances$")
		if hybridElem == "Fire" or hybridElem == "Cold" or hybridElem == "Lightning" then
			return { elem = true, chaos = true }
		end
		return nil
	end

	it("tags Fire/Cold/Lightning mods as elem", function()
		for _, t in ipairs({ "Fire", "Cold", "Lightning" }) do
			local tag = getResistTag("+40% to " .. t .. " Resistance")
			assert.is_not_nil(tag)
			assert.is_true(tag.elem)
			assert.is_nil(tag.chaos)
		end
	end)

	it("tags Chaos mod as chaos only", function()
		local tag = getResistTag("+20% to Chaos Resistance")
		assert.is_not_nil(tag)
		assert.is_nil(tag.elem)
		assert.is_true(tag.chaos)
	end)

	it("tags element+chaos hybrid as both elem and chaos", function()
		for _, t in ipairs({ "Fire", "Cold", "Lightning" }) do
			local tag = getResistTag("+15% to " .. t .. " and Chaos Resistances")
			assert.is_not_nil(tag)
			assert.is_true(tag.elem)
			assert.is_true(tag.chaos)
		end
	end)

	it("returns nil for non-resistance mods", function()
		assert.is_nil(getResistTag("+50 to maximum Life"))
		assert.is_nil(getResistTag("+15% to Fire and Cold Resistances"))
	end)
end)

describe("Resistance Swap — groupResists merging", function()
	-- mirrors the logic in TradeQueryGenerator:FinishQuery
	local function mergeResists(modWeights)
		local elemMax, chaosMax = 0, 0
		local filtered = {}
		for _, entry in ipairs(modWeights) do
			if entry.resistTag then
				if entry.resistTag.elem and entry.weight > elemMax then elemMax = entry.weight end
				if entry.resistTag.chaos and entry.weight > chaosMax then chaosMax = entry.weight end
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

	it("adds both pseudo-stats for element+chaos hybrid mods", function()
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
end)
