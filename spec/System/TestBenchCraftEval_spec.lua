-- Tests for the bench craft evaluation feature:
--   - Free slot detection: affixMax from rarity, explicit mod counting
--   - Craft filtering: craft.types[item.type] gate
--   - Skip conditions: corrupted/mirrored items
--   - Weight selection: best bench craft wins, nil when no improvement

local function makeHelm(explicits, corrupted, mirrored)
	local lines = { "Rarity: Rare", "Test Helm", "Vine Circlet" }
	for _, mod in ipairs(explicits or {}) do
		table.insert(lines, mod)
	end
	if corrupted then table.insert(lines, "Corrupted") end
	if mirrored  then table.insert(lines, "Mirrored")  end
	return table.concat(lines, "\n")
end

local function makeRing(explicits, corrupted, mirrored)
	local lines = { "Rarity: Rare", "Test Ring", "Coral Ring" }
	for _, mod in ipairs(explicits or {}) do
		table.insert(lines, mod)
	end
	if corrupted then table.insert(lines, "Corrupted") end
	if mirrored  then table.insert(lines, "Mirrored")  end
	return table.concat(lines, "\n")
end

-- Mirrors affixMax logic in GetResultEvaluation
-- prefixes.limit and suffixes.limit are deltas on top of the rarity default
local function getAffixMax(item)
	if item.rarity == "RARE" then
		local defaultHalf = (item.type == "Jewel") and 2 or 3
		return (item.prefixes.limit or 0) + defaultHalf + (item.suffixes.limit or 0) + defaultHalf
	elseif item.rarity == "MAGIC" then
		return (item.prefixes.limit or 0) + 1 + (item.suffixes.limit or 0) + 1
	end
	return 0
end

-- Mirrors explicit count logic in GetResultEvaluation (all mods, including crafted)
local function countExplicit(item)
	return #(item.explicitModLines or {})
end

describe("Bench Craft Eval — free slot detection", function()
	-- Pass: 3 mods on a rare leaves 3 free slots detected
	-- Fail: affixMax computed wrong or explicit count wrong → bench craft skipped when slots are free
	it("detects free slots on a rare with 3 mods", function()
		local item = new("Item", makeHelm({
			"+50 to maximum Life",
			"+30% to Fire Resistance",
			"+25% to Cold Resistance",
		}))
		local affixMax = getAffixMax(item)
		local explicit = countExplicit(item)
		assert.are.equal(6, affixMax)
		assert.are.equal(3, explicit)
		assert.is_true(explicit < affixMax)
	end)

	-- Pass: 6 mods on a rare → no free slots
	-- Fail: wrong count → bench craft attempted on a full item
	it("detects no free slots on a full rare (6 mods)", function()
		local item = new("Item", makeHelm({
			"+50 to maximum Life",
			"+30% to Fire Resistance",
			"+25% to Cold Resistance",
			"+40 to Strength",
			"+35% to Lightning Resistance",
			"10% increased Attack Speed",
		}))
		local affixMax = getAffixMax(item)
		local explicit = countExplicit(item)
		assert.are.equal(6, affixMax)
		assert.are.equal(6, explicit)
		assert.is_false(explicit < affixMax)
	end)

	-- Pass: 1 mod on a magic item leaves 1 free slot
	-- Fail: magic item gets wrong affixMax (6) → bench craft attempted too eagerly
	it("affixMax is 2 for magic items", function()
		local lines = "Rarity: Magic\nTest\nVine Circlet\n+50 to maximum Life"
		local item = new("Item", lines)
		local affixMax = getAffixMax(item)
		assert.are.equal(2, affixMax)
		assert.is_true(countExplicit(item) < affixMax)
	end)

	-- Pass: unique item gets affixMax 0 → bench craft never triggered
	-- Fail: unique items get bench-crafted → nonsensical evaluation
	it("affixMax is 0 for unique items", function()
		local lines = "Rarity: Unique\nShav\nShavronnes Wrappings\n+50 to maximum Life"
		local item = new("Item", lines)
		local affixMax = getAffixMax(item)
		assert.are.equal(0, affixMax)
	end)

	-- Pass: Eldritch implicit "+1 prefix allowed" raises affixMax to 7 on a rare helmet
	-- Fail: fixed affixMax=6 used → item with Eldritch +1 prefix has 7 mods but bench craft still triggered
	it("affixMax accounts for +1 prefix modifiers allowed (Eldritch implicit)", function()
		local item = new("Item", makeHelm({
			"+50 to maximum Life",
			"+30% to Fire Resistance",
			"+25% to Cold Resistance",
			"+40 to Strength",
			"+35% to Lightning Resistance",
			"10% increased Attack Speed",
			"+1 Prefix Modifier allowed",
		}))
		local affixMax = getAffixMax(item)
		-- prefixes.limit = 1 (delta), suffixes.limit = nil (0 delta), so affixMax = (0+1+3) + (0+3) = 7
		assert.are.equal(7, affixMax)
		-- 7 mods on the item → no free slot
		assert.is_false(countExplicit(item) < affixMax)
	end)

	-- Pass: crafted mod counts as an occupied slot → prevents simulating a second crafted mod
	-- Fail: crafted mod excluded → item with 5 regular + 1 crafted = 5 counted, bench craft attempted, simulation adds 7th mod
	it("counts crafted mods as occupying an explicit slot", function()
		local item = new("Item", makeHelm({
			"+50 to maximum Life",
			"+30% to Fire Resistance",
			"{crafted}10% increased Attack Speed",
		}))
		local explicit = countExplicit(item)
		-- All 3 mods (including the crafted one) occupy slots
		assert.are.equal(3, explicit)
	end)
end)

describe("Bench Craft Eval — skip conditions", function()
	-- Pass: corrupted flag detected → bench craft simulation skipped
	-- Fail: corrupted items get simulated → invalid crafting on corrupted item shown to user
	it("marks corrupted item correctly", function()
		local item = new("Item", makeHelm({ "+50 to maximum Life" }, true))
		assert.is_true(item.corrupted)
	end)

	-- Pass: mirrored flag detected → bench craft simulation skipped
	-- Fail: mirrored items get simulated → invalid crafting on mirrored item shown to user
	it("marks mirrored item correctly", function()
		local item = new("Item", makeHelm({ "+50 to maximum Life" }, false, true))
		assert.is_true(item.mirrored)
	end)

	-- Pass: normal item is neither corrupted nor mirrored
	-- Fail: normal item wrongly flagged → bench craft silently skipped on craftable items
	it("normal rare item is not corrupted or mirrored", function()
		local item = new("Item", makeHelm({ "+50 to maximum Life" }))
		assert.is_not_true(item.corrupted)
		assert.is_not_true(item.mirrored)
	end)
end)

describe("Bench Craft Eval — craft type filtering", function()
	-- Mirrors the craft.types[item.type] gate in GetResultEvaluation

	local function craftAppliesToType(craft, itemType)
		return craft.types ~= nil and craft.types[itemType] == true
	end

	-- Pass: craft with matching type is accepted
	-- Fail: gate broken → wrong item types get bench-crafted, causing invalid simulations
	it("accepts a craft whose types include the item type", function()
		local craft = { types = { Helmet = true, Gloves = true }, type = "Suffix" }
		assert.is_true(craftAppliesToType(craft, "Helmet"))
		assert.is_true(craftAppliesToType(craft, "Gloves"))
	end)

	-- Pass: craft without matching type is rejected
	-- Fail: all crafts tried on all items → incorrect evaluation with weapon-only mods on armour
	it("rejects a craft whose types do not include the item type", function()
		local craft = { types = { Weapon = true }, type = "Prefix" }
		assert.is_false(craftAppliesToType(craft, "Helmet"))
	end)

	-- Pass: craft with nil types is safely rejected
	-- Fail: nil types crash the gate → runtime error during bench craft loop
	it("safely rejects craft with nil types", function()
		local craft = { type = "Prefix" }
		assert.is_false(craftAppliesToType(craft, "Helmet"))
	end)
end)

describe("Bench Craft Eval — weight selection", function()
	-- Mirrors the best-weight selection loop in GetResultEvaluation

	local function simulateBenchCraftSelection(baseWeight, crafts)
		local weight = baseWeight
		local benchCraft = nil
		for _, craft in ipairs(crafts) do
			if craft.craftWeight > weight then
				weight = craft.craftWeight
				benchCraft = craft.label
			end
		end
		return weight, benchCraft
	end

	-- Pass: best craft is selected when it beats the base weight
	-- Fail: wrong craft selected → user shown a suboptimal bench craft hint
	it("selects the craft with the highest weight above base", function()
		local weight, benchCraft = simulateBenchCraftSelection(1.0, {
			{ label = "adds life (Prefix)",   craftWeight = 1.2 },
			{ label = "adds es (Prefix)",     craftWeight = 1.5 },
			{ label = "adds armour (Suffix)", craftWeight = 1.1 },
		})
		assert.are.equal(1.5, weight)
		assert.are.equal("adds es (Prefix)", benchCraft)
	end)

	-- Pass: benchCraft is nil when no craft beats base weight
	-- Fail: a worse craft is stored → tooltip shows misleading hint that doesn't improve the item
	it("returns nil benchCraft when no craft improves the base weight", function()
		local weight, benchCraft = simulateBenchCraftSelection(1.5, {
			{ label = "adds life (Prefix)", craftWeight = 1.2 },
			{ label = "adds es (Prefix)",   craftWeight = 1.3 },
		})
		assert.are.equal(1.5, weight)
		assert.is_nil(benchCraft)
	end)

	-- Pass: empty craft list leaves weight and benchCraft unchanged
	-- Fail: crash or wrong defaults → bench craft code fails on items with no applicable mods
	it("handles empty craft list gracefully", function()
		local weight, benchCraft = simulateBenchCraftSelection(1.0, {})
		assert.are.equal(1.0, weight)
		assert.is_nil(benchCraft)
	end)

	-- Pass: single improving craft is always selected
	-- Fail: off-by-one in > comparison → craft equal to base is wrongly selected
	it("requires strictly greater weight to select a craft", function()
		local weight, benchCraft = simulateBenchCraftSelection(1.0, {
			{ label = "equal craft (Prefix)", craftWeight = 1.0 },
		})
		assert.are.equal(1.0, weight)
		assert.is_nil(benchCraft) -- equal weight does not trigger selection
	end)

	-- Pass: only the highest craft wins over all others
	-- Fail: first-wins logic → suboptimal craft shown when a later one is better
	it("always picks the globally best craft, not just the first improving one", function()
		local weight, benchCraft = simulateBenchCraftSelection(1.0, {
			{ label = "craft_a (Prefix)", craftWeight = 1.3 },
			{ label = "craft_b (Prefix)", craftWeight = 1.8 },
			{ label = "craft_c (Suffix)", craftWeight = 1.6 },
		})
		assert.are.equal(1.8, weight)
		assert.are.equal("craft_b (Prefix)", benchCraft)
	end)
end)

describe("Bench Craft Eval — item parsing with crafted mod", function()
	-- Pass: crafted mod line added to explicitModLines is flagged correctly
	-- Fail: crafted flag missing → crafted mod counted as an occupied explicit slot
	it("item with a crafted mod has the crafted flag set on that mod line", function()
		local item = new("Item", makeRing({
			"+50 to maximum Life",
			"{crafted}+35% to Cold Resistance",
		}))
		local craftedCount = 0
		for _, modLine in ipairs(item.explicitModLines or {}) do
			if modLine.crafted then
				craftedCount = craftedCount + 1
			end
		end
		assert.are.equal(1, craftedCount)
	end)

	-- Pass: total explicit count (including crafted) is 2
	-- Fail: wrong total → logic relying on total explicit count is broken
	it("total explicitModLines count includes crafted mods", function()
		local item = new("Item", makeRing({
			"+50 to maximum Life",
			"{crafted}+35% to Cold Resistance",
		}))
		assert.are.equal(2, #item.explicitModLines)
	end)
end)
