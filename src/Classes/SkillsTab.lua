-- Path of Building
--
-- Module: Skills Tab
-- Skills tab for the current build.
--
local dkjson = require "dkjson"

local get_time = os.time
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_ceil = math.ceil
local m_min = math.min
local m_max = math.max
local gemUpgradeReport = LoadModule("Modules/GemUpgradeReport")
local gemTradeReport = LoadModule("Modules/GemTradeReport")
local supportReplacementReport = LoadModule("Modules/SupportReplacementReport")
local imbuedTradeStatMap = LoadModule("Data/ImbuedTradeStatMap")

local groupSlotDropList = {
	{ label = "None" },
	{ label = "Weapon 1", slotName = "Weapon 1" },
	{ label = "Weapon 2", slotName = "Weapon 2" },
	{ label = "Weapon 1 (Swap)", slotName = "Weapon 1 Swap" },
	{ label = "Weapon 2 (Swap)", slotName = "Weapon 2 Swap" },
	{ label = "Helmet", slotName = "Helmet" },
	{ label = "Body Armour", slotName = "Body Armour" },
	{ label = "Gloves", slotName = "Gloves" },
	{ label = "Boots", slotName = "Boots" }, 
	{ label = "Amulet", slotName = "Amulet" },
	{ label = "Ring 1", slotName = "Ring 1" },
	{ label = "Ring 2", slotName = "Ring 2" },
	{ label = "Ring 3", slotName = "Ring 3" },
	{ label = "Belt", slotName = "Belt" },
}

local defaultGemLevelList = {
	{
		label = "Normal Maximum",
		description = "All gems default to their highest valid non-corrupted gem level.",
		gemLevel = "normalMaximum",
	},
	{
		label = "Corrupted Maximum",
		description = [[Normal gems default to their highest valid corrupted gem level.
Awakened gems default to their highest valid non-corrupted gem level.]],
		gemLevel = "corruptedMaximum",
	},
	{
		label = "Awakened Maximum",
		description = "All gems default to their highest valid corrupted gem level.",
		gemLevel = "awakenedMaximum",
	},
	{
		label = "Match Character Level",
		description = [[All gems default to their highest valid non-corrupted gem level that your character meets the level requirement for.
This hides gems with a minimum level requirement above your character level, preventing them from showing up in the dropdown list.]],
		gemLevel = "characterLevel",
	},
	{
		label = "Level 1",
		description = "All gems default to level 1.",
		gemLevel = "levelOne",
	},
}

local showSupportGemTypeList = {
	{ label = "All", show = "ALL" },
	{ label = "Non-Exceptional", show = "NORMAL" },
	{ label = "Exceptional", show = "EXCEPTIONAL" },
}

local sortGemTypeList = {
	{ label = "Full DPS", type = "FullDPS" },
	{ label = "Combined DPS", type = "CombinedDPS" },
	{ label = "Hit DPS", type = "TotalDPS" },
	{ label = "Average Hit", type = "AverageDamage" },
	{ label = "DoT DPS", type = "TotalDot" },
	{ label = "Bleed DPS", type = "BleedDPS" },
	{ label = "Ignite DPS", type = "IgniteDPS" },
	{ label = "Poison DPS", type = "TotalPoisonDPS" },
	{ label = "Effective Hit Pool", type = "TotalEHP" },
}

local gemUpgradeImpactFilterList = {
	{ label = "All", value = "ALL" },
	{ label = "Upgrade > 0", value = "POSITIVE" },
}

local gemUpgradeSourceFilterList = {
	{ label = "All", value = "ALL" },
	{ label = "Normal (no corruption)", value = "NATURAL" },
	{ label = "Corruption", value = "CORRUPTION" },
	{ label = "Imbued Coin", value = "IMBUED" },
	{ label = "GCP Recipe", value = "RECIPE" },
}

local SkillsTabClass = newClass("SkillsTab", "UndoHandler", "ControlHost", "Control", function(self, build)
	self.UndoHandler()
	self.ControlHost()
	self.Control()

	self.build = build

	self.socketGroupList = { }

	self.sortGemsByDPS = true
	self.sortGemsByDPSField = "CombinedDPS"
	self.showSupportGemTypes = "ALL"
	self.showLegacyGems = false
	self.defaultGemLevel = "normalMaximum"
	self.defaultGemQuality = main.defaultGemQuality
	self.gemUpgradeImpactFilter = "POSITIVE"
	self.gemUpgradeSourceFilter = "ALL"

	-- Set selector
	self.controls.setSelect = new("DropDownControl", { "TOPLEFT", self, "TOPLEFT" }, { 76, 8, 210, 20 }, nil, function(index, value)
		self:SetActiveSkillSet(self.skillSetOrderList[index])
		self:AddUndoState()
	end)
	self.controls.setSelect.enableDroppedWidth = true
	self.controls.setSelect.enabled = function()
		return #self.skillSetOrderList > 1
	end
	self.controls.setLabel = new("LabelControl", { "RIGHT", self.controls.setSelect, "LEFT" }, { -2, 0, 0, 16 }, "^7Skill set:")
	self.controls.setManage = new("ButtonControl", { "LEFT", self.controls.setSelect, "RIGHT" }, { 4, 0, 90, 20 }, "Manage...", function()
		self:OpenSkillSetManagePopup()
	end)
	self.gemUpgradeSortStatList = { }
	for _, stat in ipairs(data.powerStatList) do
		if stat.stat then
			t_insert(self.gemUpgradeSortStatList, stat)
		end
	end
	self.gemUpgradeSortStat = self.gemUpgradeSortStatList[1]
	for _, stat in ipairs(self.gemUpgradeSortStatList) do
		if stat.stat == self.sortGemsByDPSField then
			self.gemUpgradeSortStat = stat
			break
		end
	end
	self.controls.gemUpgradeReport = new("ButtonControl", { "LEFT", self.controls.setManage, "RIGHT" }, { 8, 0, 150, 20 }, "Gem Upgrade Report", function()
		self:OpenGemUpgradePopup()
	end)
	self.controls.gemTradeReport = new("ButtonControl", { "LEFT", self.controls.gemUpgradeReport, "RIGHT" }, { 8, 0, 150, 20 }, "Gem Trade Report", function()
		self:OpenGemTradePopup()
	end)
	self.controls.supportReplacementReport = new("ButtonControl", { "LEFT", self.controls.gemTradeReport, "RIGHT" }, { 8, 0, 175, 20 }, "Support Replacement", function()
		self:OpenSupportReplacementPopup()
	end)

	-- Socket group list
	self.controls.groupList = new("SkillListControl", { "TOPLEFT", self, "TOPLEFT" }, { 20, 54, 360, 300 }, self)
	self.controls.groupTip = new("LabelControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { 0, 8, 0, 14 }, 
[[
^7Usage Tips:
- You can copy/paste socket groups using Ctrl+C and Ctrl+V.
- Ctrl + Click to enable/disable socket groups.
- Ctrl + Right click to include/exclude in FullDPS calculations.
- Right click to set as the Main skill group.
]]
	)

	-- Gem options
	local optionInputsX = 170
	local optionInputsY = 45
	self.controls.optionSection = new("SectionControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { 0, optionInputsY + 50, 360, 156 }, "Gem Options")
	self.controls.sortGemsByDPS = new("CheckBoxControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 70, 20 }, "Sort gems by DPS:", function(state)
		self.sortGemsByDPS = state
	end, nil, true)
	self.controls.sortGemsByDPSFieldControl = new("DropDownControl", { "LEFT", self.controls.sortGemsByDPS, "RIGHT" }, { 10, 0, 140, 20 }, sortGemTypeList, function(index, value)
		self.sortGemsByDPSField = value.type
	end)
	self.controls.defaultLevel = new("DropDownControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 94, 170, 20 }, defaultGemLevelList, function(index, value)
		self.defaultGemLevel = value.gemLevel
	end)
	self.controls.defaultLevel.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode ~= "OUT" and value.description then
			tooltip:AddLine(16, "^7" .. value.description)
		end
	end
	self.controls.defaultLevelLabel = new("LabelControl", { "RIGHT", self.controls.defaultLevel, "LEFT" }, { -4, 0, 0, 16 }, "^7Default gem level:")
	self.controls.defaultQuality = new("EditControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 118, 60, 20 }, nil, nil, "%D", 2, function(buf)
		self.defaultGemQuality = m_min(tonumber(buf) or 0, 23)
	end)
	self.controls.defaultQualityLabel = new("LabelControl", { "RIGHT", self.controls.defaultQuality, "LEFT" }, { -4, 0, 0, 16 }, "^7Default gem quality:")
	self.controls.showSupportGemTypes = new("DropDownControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 142, 170, 20 }, showSupportGemTypeList, function(index, value)
		self.showSupportGemTypes = value.show
	end)
	self.controls.showSupportGemTypesLabel = new("LabelControl", { "RIGHT", self.controls.showSupportGemTypes, "LEFT" }, { -4, 0, 0, 16 }, "^7Show support gems:")
	self.controls.showLegacyGems = new("CheckBoxControl", { "TOPLEFT", self.controls.groupList, "BOTTOMLEFT" }, { optionInputsX, optionInputsY + 166, 20 }, "^7Show legacy gems:", function(state)
		self.showLegacyGems = state
	end)

	-- Socket group details
	if main.portraitMode then
		self.anchorGroupDetail = new("Control", { "TOPLEFT", self.controls.optionSection, "BOTTOMLEFT" }, { 0, 20, 0, 0 })
	else
		self.anchorGroupDetail = new("Control", { "TOPLEFT", self.controls.groupList, "TOPRIGHT" }, { 20, 0, 0, 0 })
	end
	self.anchorGroupDetail.shown = function()
		return self.displayGroup ~= nil
	end
	self.controls.groupLabel = new("EditControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, { 0, 0, 380, 20 }, nil, "Label", "%c", 50, function(buf)
		self.displayGroup.label = buf
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlotLabel = new("LabelControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, { 0, 30, 0, 16 }, "^7Socketed in:")
	self.controls.groupSlot = new("DropDownControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, { 85, 28, 130, 20 }, groupSlotDropList, function(index, value)
		-- maintain imbued support to new slot
		if self.imbuedSupportBySlot[self.displayGroup.slot] and self.displayGroup.imbuedSupport then
			if value.slotName and not self.imbuedSupportBySlot[value.slotName] then
				self.imbuedSupportBySlot[value.slotName] = copyTable(self.imbuedSupportBySlot[self.displayGroup.slot], true)
			else
				self.controls.imbuedSupport.gemId = nil
				self.controls.imbuedSupport:SetText("")
				self.displayGroup.imbuedSupport = nil  -- reset saved support to None
			end
			self.imbuedSupportBySlot[self.displayGroup.slot] = nil
		end

		self.displayGroup.slot = value.slotName
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlot.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode == "OUT" or index == 1 then
			tooltip:AddLine(16, "Select the item in which this skill is socketed.")
			tooltip:AddLine(16, "This will allow the skill to benefit from modifiers on the item that affect socketed gems.")
		else
			local slot = self.build.itemsTab.slots[value.slotName]
			local ttItem = self.build.itemsTab.items[slot.selItemId]
			if ttItem then
				self.build.itemsTab:AddItemTooltip(tooltip, ttItem, slot)
			else
				tooltip:AddLine(16, "No item is equipped in this slot.")
			end
		end
	end
	self.controls.groupSlot.enabled = function()
		return self.displayGroup.source == nil
	end
	self.controls.groupEnabled = new("CheckBoxControl", { "LEFT", self.controls.groupSlot, "RIGHT" }, { 70, 0, 20 }, "Enabled:", function(state)
		self.displayGroup.enabled = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.includeInFullDPS = new("CheckBoxControl", { "LEFT", self.controls.groupEnabled, "RIGHT" }, { 145, 0, 20 }, "Include in Full DPS:", function(state)
		self.displayGroup.includeInFullDPS = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)

	-- self.imbuedSupportBySlot is used by CalcSetup to add an ExtraSupport mod of the selected gem
	-- Each displayGroup has its own "imbuedSupport" and is saved to the xml to load when changing sockets or loading a build
	-- "slotName" is used on import, which uses builtInSupport to get the gemData and pass in here
	-- buildFlag to true triggers the reload/run the CalcSetup to add on the support
	-- the last var in the GemSelectControl init, the true, sets imbuedSelect to true which sets the level to 1 and support filtering
	self.imbuedSupportBySlot = { }
	self.controls.imbuedSupportLabel = new("LabelControl", { "LEFT", self.controls.groupSlotLabel, "LEFT" }, { 86, 28, 0, 16 }, colorCodes.CRAFTED.."Imbued Support:")
	self.controls.imbuedSupport = new("GemSelectControl", { "LEFT", self.controls.imbuedSupportLabel, "RIGHT" }, { 8, 0, 250, 20 }, self, 1, function(gemData, _, _, slotName) -- slotName used on Import
		local targetSlot = slotName or (self.displayGroup and self.displayGroup.slot)
		if not targetSlot then
			return
		end
		local updateDisplayGroup = self.displayGroup and targetSlot == self.displayGroup.slot
		if gemData and (type(gemData) == "string" or gemData.id) then
			local gem = data.gems[gemData.id or gemData]
			self.imbuedSupportBySlot[targetSlot] = gem.grantedEffect
			if updateDisplayGroup then
				self.displayGroup.imbuedSupport = gem.name
			end
			self.controls.imbuedSupport.inactiveCol = data.skillColorMap[gem.grantedEffect.color]
			self.build.buildFlag = true
		else
			self.imbuedSupportBySlot[targetSlot] = nil
			if updateDisplayGroup then
				self.displayGroup.imbuedSupport = nil
			end
		end
	end, true, true)
	local function isImbuedEnabled() -- socketedIn must be set and the displayGroup must have an imbued, otherwise disable the imbued dropdown
		return (self.displayGroup and self.displayGroup.slot and ((self.imbuedSupportBySlot[self.displayGroup.slot] and self.displayGroup.imbuedSupport) or not self.imbuedSupportBySlot[self.displayGroup.slot]))
	end
	self.controls.imbuedSupport.enabled = function()
		return isImbuedEnabled()
	end
	self.controls.imbuedSupportLabel.shown = function() -- don't show imbued for skills from items
		return not self.displayGroup.source
	end
	self.controls.imbuedSupportClear = new("ButtonControl", { "LEFT", self.controls.imbuedSupportLabel, "RIGHT" }, { 260, 0, 20, 20}, "x", function()
		self.controls.imbuedSupport.gemId = nil
		self.controls.imbuedSupport:SetText("")
		self.displayGroup.imbuedSupport = nil
		self.imbuedSupportBySlot[self.displayGroup.slot] = nil
		self.build.buildFlag = true
	end)
	self.controls.imbuedSupportClear.enabled = function()
		return isImbuedEnabled()
	end
	self.controls.imbuedSupportClear.tooltipText = "Remove this imbued support."

	self.controls.groupCountLabel = new("LabelControl", { "LEFT", self.controls.includeInFullDPS, "RIGHT" }, { 16, 0, 0, 16 }, "Count:")
	self.controls.groupCountLabel.shown = function()
		return self.displayGroup.source ~= nil
	end
	self.controls.groupCount = new("EditControl", { "LEFT", self.controls.groupCountLabel, "RIGHT" }, { 4, 0, 60, 20 }, nil, nil, "%D", 2, function(buf)
		self.displayGroup.groupCount = tonumber(buf) or 1
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupCount.shown = function()
		return self.displayGroup.source ~= nil
	end
	self.controls.sourceNote = new("LabelControl", { "TOPLEFT", self.controls.groupSlotLabel, "TOPLEFT" }, { 0, 30, 0, 16 })
	self.controls.sourceNote.shown = function()
		return self.displayGroup.source ~= nil
	end
	self.controls.sourceNote.label = function()
		local label
		if self.displayGroup.explodeSources then
			label = [[^7This is a special group created for the enemy explosion effect,
which comes from the following sources:]]
			for _, source in ipairs(self.displayGroup.explodeSources) do
				label = label .. "\n\t" .. colorCodes[source.rarity or "NORMAL"] .. (source.name or source.dn or "???")
			end
			label = label .. "^7\nYou cannot delete this group, but it will disappear if you lose the above sources."
		else
			local activeGem = self.displayGroup.gemList[1]
			local sourceName
			if self.displayGroup.sourceItem then
				sourceName = "'" .. colorCodes[self.displayGroup.sourceItem.rarity] .. self.displayGroup.sourceItem.name
			elseif self.displayGroup.sourceNode then
				sourceName = "'" .. colorCodes["NORMAL"] .. self.displayGroup.sourceNode.name
			else
				sourceName = "'" .. colorCodes["NORMAL"] .. "?"
			end
			sourceName = sourceName .. "^7'"
			label = [[^7This is a special group created for the ']] .. activeGem.color .. (activeGem.grantedEffect and activeGem.grantedEffect.name or activeGem.nameSpec) .. [[^7' skill,
which is being provided by ]] .. sourceName .. [[.
You cannot delete this group, but it will disappear if you ]] .. (self.displayGroup.sourceNode and [[un-allocate the node.]] or [[un-equip the item.]])
			if not self.displayGroup.noSupports then
				label = label .. "\n\n" .. [[You cannot add support gems to this group, but support gems in
any other group socketed into ]] .. sourceName .. [[
will automatically apply to the skill.]]
			end
		end
		return label
	end

	-- Scroll bar
	self.controls.scrollBarH = new("ScrollBarControl", nil, {0, 0, 0, 18}, 100, "HORIZONTAL", true)

	-- Initialise skill sets
	self.skillSets = { }
	self.skillSetOrderList = { 1 }
	self:NewSkillSet(1)
	self:SetActiveSkillSet(1)

	-- Skill gem slots
	self.anchorGemSlots = new("Control", {"TOPLEFT",self.anchorGroupDetail,"TOPLEFT"}, {0, 28 + 28 + 16 + 28, 0, 0})
	self.gemSlots = { }
	self:CreateGemSlot(1)
	self.controls.gemNameHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].nameSpec, "TOPLEFT"}, {0, -2, 0, 16}, "^7Gem name:")
	self.controls.gemLevelHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].level, "TOPLEFT"}, {0, -2, 0, 16}, "^7Level:")
	self.controls.gemQualityHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].quality, "TOPLEFT"}, {0, -2, 0, 16}, "^7Quality:")
	self.controls.gemEnableHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].enabled, "TOPLEFT"}, {-16, -2, 0, 16}, "^7Enabled:")
	self.controls.gemCountHeader = new("LabelControl", {"BOTTOMLEFT", self.gemSlots[1].count, "TOPLEFT"}, {8, -2, 0, 16}, "^7Count:")
end)


function SkillsTabClass:LoadSkill(node, skillSetId)
	if node.elem ~= "Skill" then
		return
	end

	local socketGroup = { }
	socketGroup.enabled = node.attrib.active == "true" or node.attrib.enabled == "true"
	socketGroup.includeInFullDPS = node.attrib.includeInFullDPS and node.attrib.includeInFullDPS == "true"
	socketGroup.groupCount = tonumber(node.attrib.groupCount)
	socketGroup.label = node.attrib.label
	socketGroup.slot = node.attrib.slot
	socketGroup.source = node.attrib.source
	socketGroup.mainActiveSkill = tonumber(node.attrib.mainActiveSkill) or 1
	socketGroup.mainActiveSkillCalcs = tonumber(node.attrib.mainActiveSkillCalcs) or 1
	socketGroup.gemList = { }
	if node.attrib.imbuedSupport and node.attrib.slot then
		socketGroup.imbuedSupport = node.attrib.imbuedSupport
		self.controls.imbuedSupport.gemChangeFunc(data.gems[data.gemForBaseName[socketGroup.imbuedSupport:lower().." support"]], nil, nil, socketGroup.slot)
	end

	for _, child in ipairs(node) do
		local gemInstance = { }
		gemInstance.nameSpec = sanitiseText(child.attrib.nameSpec or "")
		if child.attrib.gemId then
			local gemData
			local possibleVariants = self.build.data.gemsByGameId[child.attrib.gemId]
			if possibleVariants then
				-- If it is a known gem, try to determine which variant is used
				if child.attrib.variantId then
					-- New save format from 3.23 that stores the specific variation (transfiguration)
					gemData = possibleVariants[child.attrib.variantId]
				elseif child.attrib.skillId then
					-- Old format relying on the uniqueness of the granted effects id
					for _, variant in pairs(possibleVariants) do
						if variant.grantedEffectId == child.attrib.skillId then
							gemData = variant
							break
						end
					end
				end
			end
			if gemData then
				gemInstance.gemId = gemData.id
				gemInstance.skillId = gemData.grantedEffectId
				gemInstance.nameSpec = gemData.nameSpec
			end
		elseif child.attrib.skillId then
			local grantedEffect = self.build.data.skills[child.attrib.skillId]
			if grantedEffect then
				gemInstance.gemId = self.build.data.gemForSkill[grantedEffect]
				gemInstance.skillId = grantedEffect.id
				gemInstance.nameSpec = grantedEffect.name
			end
		end
		gemInstance.level = tonumber(child.attrib.level)
		gemInstance.quality = tonumber(child.attrib.quality)
		gemInstance.nameSpec = sanitiseText(gemInstance.nameSpec)
		gemInstance.enabled = not child.attrib.enabled and true or child.attrib.enabled == "true"
		gemInstance.enableGlobal1 = not child.attrib.enableGlobal1 or child.attrib.enableGlobal1 == "true"
		gemInstance.enableGlobal2 = child.attrib.enableGlobal2 == "true"
		gemInstance.count = tonumber(child.attrib.count) or 1
		gemInstance.skillPart = tonumber(child.attrib.skillPart)
		gemInstance.skillPartCalcs = tonumber(child.attrib.skillPartCalcs)
		gemInstance.skillStageCount = tonumber(child.attrib.skillStageCount)
		gemInstance.skillStageCountCalcs = tonumber(child.attrib.skillStageCountCalcs)
		gemInstance.skillMineCount = tonumber(child.attrib.skillMineCount)
		gemInstance.skillMineCountCalcs = tonumber(child.attrib.skillMineCountCalcs)
		gemInstance.skillMinion = child.attrib.skillMinion
		gemInstance.skillMinionCalcs = child.attrib.skillMinionCalcs
		gemInstance.skillMinionItemSet = tonumber(child.attrib.skillMinionItemSet)
		gemInstance.skillMinionItemSetCalcs = tonumber(child.attrib.skillMinionItemSetCalcs)
		gemInstance.skillMinionSkill = tonumber(child.attrib.skillMinionSkill)
		gemInstance.skillMinionSkillCalcs = tonumber(child.attrib.skillMinionSkillCalcs)
		t_insert(socketGroup.gemList, gemInstance)
	end
	if node.attrib.skillPart and socketGroup.gemList[1] then
		socketGroup.gemList[1].skillPart = tonumber(node.attrib.skillPart)
	end
	self:ProcessSocketGroup(socketGroup)
	t_insert(self.skillSets[skillSetId].socketGroupList, socketGroup)
end

function SkillsTabClass:Load(xml, fileName)
	self.activeSkillSetId = 0
	self.skillSets = { }
	self.skillSetOrderList = { }
	-- Handle legacy configuration settings when loading `defaultGemLevel`
	if xml.attrib.matchGemLevelToCharacterLevel == "true" then
		self.controls.defaultLevel:SelByValue("characterLevel", "gemLevel")
	elseif type(xml.attrib.defaultGemLevel) == "string" and tonumber(xml.attrib.defaultGemLevel) == nil then
		self.controls.defaultLevel:SelByValue(xml.attrib.defaultGemLevel, "gemLevel")
	else
		self.controls.defaultLevel:SelByValue("normalMaximum", "gemLevel")
	end
	self.defaultGemLevel = self.controls.defaultLevel:GetSelValueByKey("gemLevel")
	self.defaultGemQuality = m_max(m_min(tonumber(xml.attrib.defaultGemQuality) or 0, 23), 0)
	self.controls.defaultQuality:SetText(self.defaultGemQuality or "")
	if xml.attrib.sortGemsByDPS then
		self.sortGemsByDPS = xml.attrib.sortGemsByDPS == "true"
	end
	self.controls.sortGemsByDPS.state = self.sortGemsByDPS
	if xml.attrib.showLegacyGems then
		self.showLegacyGems = xml.attrib.showLegacyGems == "true"
	end
	self.controls.showLegacyGems.state = self.showLegacyGems
	self.controls.showSupportGemTypes:SelByValue(xml.attrib.showSupportGemTypes or "ALL", "show")
	self.controls.sortGemsByDPSFieldControl:SelByValue(xml.attrib.sortGemsByDPSField or "CombinedDPS", "type") 
	self.showSupportGemTypes = self.controls.showSupportGemTypes:GetSelValueByKey("show")
	self.sortGemsByDPSField = self.controls.sortGemsByDPSFieldControl:GetSelValueByKey("type")
	for _, node in ipairs(xml) do
		if node.elem == "Skill" then
			-- Old format, initialize skill sets if needed
			if not self.skillSetOrderList[1] then
				self.skillSetOrderList[1] = 1
				self:NewSkillSet(1)
			end
			self:LoadSkill(node, 1)
		end

		if node.elem == "SkillSet" then
			local skillSet = self:NewSkillSet(tonumber(node.attrib.id))
			skillSet.title = node.attrib.title
			t_insert(self.skillSetOrderList, skillSet.id)
			for _, subNode in ipairs(node) do
				self:LoadSkill(subNode, skillSet.id)
			end
		end
	end
	self:SetActiveSkillSet(tonumber(xml.attrib.activeSkillSet) or 1)
	self:ResetUndo()
end

function SkillsTabClass:Save(xml)
	xml.attrib = {
		activeSkillSet = tostring(self.activeSkillSetId),
		defaultGemLevel = self.defaultGemLevel,
		defaultGemQuality = tostring(self.defaultGemQuality),
		sortGemsByDPS = tostring(self.sortGemsByDPS),
		showSupportGemTypes = self.showSupportGemTypes,
		sortGemsByDPSField = self.sortGemsByDPSField,
		showLegacyGems = tostring(self.showLegacyGems),
	}
	for _, skillSetId in ipairs(self.skillSetOrderList) do
		local skillSet = self.skillSets[skillSetId]
		local child = { elem = "SkillSet", attrib = { id = tostring(skillSetId), title = skillSet.title } }
		t_insert(xml, child)

		for _, socketGroup in ipairs(skillSet.socketGroupList) do
			local node = { elem = "Skill", attrib = {
				enabled = tostring(socketGroup.enabled),
				includeInFullDPS = tostring(socketGroup.includeInFullDPS),
				groupCount = socketGroup.groupCount ~= nil and tostring(socketGroup.groupCount),
				label = socketGroup.label,
				slot = socketGroup.slot,
				source = socketGroup.source,
				mainActiveSkill = tostring(socketGroup.mainActiveSkill),
				mainActiveSkillCalcs = tostring(socketGroup.mainActiveSkillCalcs),
				imbuedSupport = socketGroup.imbuedSupport and tostring(socketGroup.imbuedSupport),
			} }
			for _, gemInstance in ipairs(socketGroup.gemList) do
				t_insert(node, { elem = "Gem", attrib = {
					nameSpec = gemInstance.nameSpec,
					skillId = gemInstance.skillId,
					gemId = gemInstance.gemData and gemInstance.gemData.gameId,
					variantId = gemInstance.gemData and gemInstance.gemData.variantId,
					level = tostring(gemInstance.level),
					quality = tostring(gemInstance.quality),
					enabled = tostring(gemInstance.enabled),
					enableGlobal1 = tostring(gemInstance.enableGlobal1),
					enableGlobal2 = tostring(gemInstance.enableGlobal2),
					count = tostring(gemInstance.count),
					skillPart = gemInstance.skillPart and tostring(gemInstance.skillPart),
					skillPartCalcs = gemInstance.skillPartCalcs and tostring(gemInstance.skillPartCalcs),
					skillStageCount = gemInstance.skillStageCount and tostring(gemInstance.skillStageCount),
					skillStageCountCalcs = gemInstance.skillStageCountCalcs and tostring(gemInstance.skillStageCountCalcs),
					skillMineCount = gemInstance.skillMineCount and tostring(gemInstance.skillMineCount),
					skillMineCountCalcs = gemInstance.skillMineCountCalcs and tostring(gemInstance.skillMineCountCalcs),
					skillMinion = gemInstance.skillMinion,
					skillMinionCalcs = gemInstance.skillMinionCalcs,
					skillMinionItemSet = gemInstance.skillMinionItemSet and tostring(gemInstance.skillMinionItemSet),
					skillMinionItemSetCalcs = gemInstance.skillMinionItemSetCalcs and tostring(gemInstance.skillMinionItemSetCalcs),
					skillMinionSkill = gemInstance.skillMinionSkill and tostring(gemInstance.skillMinionSkill),
					skillMinionSkillCalcs = gemInstance.skillMinionSkillCalcs and tostring(gemInstance.skillMinionSkillCalcs),
				} })
			end
			t_insert(child, node)
		end
	end
end

function SkillsTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height
	self.controls.scrollBarH.width = viewPort.width
	self.controls.scrollBarH.x = viewPort.x
	self.controls.scrollBarH.y = viewPort.y + viewPort.height - 18

	do
		local maxX = self.controls.gemCountHeader:GetPos() + self.controls.gemCountHeader:GetSize() + 350
		local contentWidth = maxX - self.x
		self.controls.scrollBarH:SetContentDimension(contentWidth, viewPort.width)
	end
	self.x = self.x - self.controls.scrollBarH.offset

	for _, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "z" and IsKeyDown("CTRL") then
				self:Undo()
				self.build.buildFlag = true
			elseif event.key == "y" and IsKeyDown("CTRL") then
				self:Redo()
				self.build.buildFlag = true
			elseif event.key == "v" and IsKeyDown("CTRL") then
				self:PasteSocketGroup()
			end
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)
	for _, event in ipairs(inputEvents) do
		if event.type == "KeyUp" then
			if self.controls.scrollBarH:IsScrollDownKey(event.key) then
				self.controls.scrollBarH:Scroll(1)
			elseif self.controls.scrollBarH:IsScrollUpKey(event.key) then
				self.controls.scrollBarH:Scroll(-1)
			end
		end
	end

	main:DrawBackground(viewPort)

	local newSetList = { }
	for index, skillSetId in ipairs(self.skillSetOrderList) do
		local skillSet = self.skillSets[skillSetId]
		t_insert(newSetList, skillSet.title or "Default")
		if skillSetId == self.activeSkillSetId then
			self.controls.setSelect.selIndex = index
		end
	end
	self.controls.setSelect:SetList(newSetList)

	if main.portraitMode then
		self.anchorGroupDetail:SetAnchor("TOPLEFT",self.controls.optionSection,"BOTTOMLEFT", 0, 20)
	else
		self.anchorGroupDetail:SetAnchor("TOPLEFT",self.controls.groupList,"TOPRIGHT", 20, 0)
	end

	self:UpdateGemSlots()

	self:DrawControls(viewPort)
end

function SkillsTabClass:BuildGemUpgradeReport(currentStat)
	return gemUpgradeReport.Build(self, currentStat, {
		impact = self.gemUpgradeImpactFilter,
		source = self.gemUpgradeSourceFilter,
	})
end

local function getGemTradePriceKey(reportRow, league)
	return table.concat({
		league or reportRow.tradeLeague or "",
		reportRow.tradeGemNameSpec or reportRow.name or "",
		reportRow.tradeQualityId or "Default",
		tostring(reportRow.targetLevel or ""),
		tostring(reportRow.targetQuality or ""),
		tostring(reportRow.targetImbuedSupport or ""),
		tostring(reportRow.tradeNaturalMaxLevel or ""),
	}, "|")
end

local function getGemTradeQueryFingerprint(queryContext, query)
	return table.concat({
		queryContext and queryContext.realm or "",
		queryContext and queryContext.league or "",
		query or "",
	}, "|")
end

local function resolveGemTradeCacheEntry(priceCache, priceKey)
	local cacheEntry = priceCache and priceCache[priceKey]
	local seen = { }
	while cacheEntry and cacheEntry.state == "alias" and cacheEntry.aliasKey and not seen[cacheEntry.aliasKey] do
		if cacheEntry.aliasKey == priceKey then
			return nil
		end
		seen[cacheEntry.aliasKey] = true
		cacheEntry = priceCache[cacheEntry.aliasKey]
	end
	if cacheEntry and cacheEntry.state == "alias" then
		return nil
	end
	return cacheEntry
end

local function canPriceGemTradeRow(reportRow)
	return reportRow
		and reportRow.tradeGemNameSpec
		and reportRow.tradeGemNameSpec ~= ""
		and (reportRow.score or 0) > 0
end

local function getGemTradeQueueWaitSeconds(tradeQueryRequests)
	if not tradeQueryRequests then
		return nil
	end
	local now = os.time()
	local waitSeconds = nil
	for _, key in ipairs({ "search", "fetch" }) do
		local queue = tradeQueryRequests.requestQueue and tradeQueryRequests.requestQueue[key]
		if queue and queue[1] and queue[1].retryTime and queue[1].retryTime > now then
			local queueWait = queue[1].retryTime - now
			if not waitSeconds or queueWait > waitSeconds then
				waitSeconds = queueWait
			end
		end
		local rateLimiter = tradeQueryRequests.rateLimiter
		local policy = rateLimiter and rateLimiter.GetPolicyName and rateLimiter:GetPolicyName(key)
		if policy and rateLimiter and rateLimiter.NextRequestTime then
			local nextTime = rateLimiter:NextRequestTime(policy, now)
			if nextTime and nextTime > now and nextTime < 1956528000 then
				local rateWait = nextTime - now
				if not waitSeconds or rateWait > waitSeconds then
					waitSeconds = rateWait
				end
			end
		end
	end
	return waitSeconds
end

local function getGemTradeQueueCounts(tradeQueryRequests)
	if not tradeQueryRequests or not tradeQueryRequests.requestQueue then
		return 0, 0
	end
	local searchQueue = tradeQueryRequests.requestQueue.search and #tradeQueryRequests.requestQueue.search or 0
	local fetchQueue = tradeQueryRequests.requestQueue.fetch and #tradeQueryRequests.requestQueue.fetch or 0
	return searchQueue, fetchQueue
end

local function formatTradePrice(amount, currency)
	return tostring(amount) .. " " .. tostring(currency)
end

local gemTradeQueuePumpKey = "SkillsTabGemTradeQueuePump"
local gemReportBuildPumpKey = "SkillsTabReportBuild"
local gemReportInitPumpKey = "SkillsTabReportInit"

local function loadTradeCurrencyConversionFromFile(tradeQuery, league)
	if not (tradeQuery and league and league ~= "") then
		return nil
	end
	tradeQuery.pbCurrencyConversion = tradeQuery.pbCurrencyConversion or { }
	if tradeQuery.pbCurrencyConversion[league] then
		return tradeQuery.pbCurrencyConversion[league]
	end
	local valuesFile = io.open("../" .. league .. "_currency_values.json", "r")
	if not valuesFile then
		return nil
	end
	local lines = valuesFile:read("*a")
	valuesFile:close()
	local conversionTable = dkjson.decode(lines)
	if type(conversionTable) == "table" then
		tradeQuery.pbCurrencyConversion[league] = conversionTable
		return conversionTable
	end
	return nil
end

local function storeTradeCurrencyConversionRate(tradeQuery, league, currencyName, chaosEquivalent)
	if not (tradeQuery and league and currencyName and chaosEquivalent) then
		return
	end
	tradeQuery.pbCurrencyConversion = tradeQuery.pbCurrencyConversion or { }
	tradeQuery.pbCurrencyConversion[league] = tradeQuery.pbCurrencyConversion[league] or { }
	local normalizedName = tostring(currencyName):lower()
	tradeQuery.pbCurrencyConversion[league][normalizedName] = chaosEquivalent
	local mappedTradeId = tradeQuery.currencyConversionTradeMap and tradeQuery.currencyConversionTradeMap[normalizedName]
	if mappedTradeId and mappedTradeId ~= "" then
		tradeQuery.pbCurrencyConversion[league][mappedTradeId:lower()] = chaosEquivalent
	end
end

local function tryConvertTradePriceToChaos(tradeQuery, league, currency, amount)
	if not (currency and amount) then
		return nil
	end
	loadTradeCurrencyConversionFromFile(tradeQuery, league)
	currency = tostring(currency):lower()
	if currency == "chaos" then
		return m_ceil(tonumber(amount) or 0)
	end
	local conversionTable = tradeQuery and tradeQuery.pbCurrencyConversion and tradeQuery.pbCurrencyConversion[league]
	if conversionTable and conversionTable[currency] then
		return m_ceil((tonumber(amount) or 0) * conversionTable[currency])
	end
	if conversionTable and tradeQuery and tradeQuery.currencyConversionTradeMap then
		for currencyName, tradeId in pairs(tradeQuery.currencyConversionTradeMap) do
			if currencyName == currency or tostring(tradeId):lower() == currency then
				local mappedRate = conversionTable[currencyName] or conversionTable[tostring(tradeId):lower()]
				if mappedRate then
					return m_ceil((tonumber(amount) or 0) * mappedRate)
				end
			end
		end
	end
	return nil
end

local function getGemTradeStatusOption(tradeQuery)
	if not tradeQuery then
		return "securable"
	end
	if type(tradeQuery.GetTradeStatusOption) == "function" then
		local ok, status = pcall(tradeQuery.GetTradeStatusOption, tradeQuery)
		if ok and type(status) == "string" and status ~= "" then
			return status
		end
	end
	local status = tradeQuery.tradeStatusOption
	if type(status) == "table" then
		status = status.option or status.id or status.value or status.label
	end
	if type(status) == "string" and status ~= "" then
		return status
	end
	local statusOptions = tradeQuery.tradeStatusOptions
	local statusIndex = tradeQuery.tradeStatusIndex
	if type(statusOptions) == "table" and statusIndex and statusOptions[statusIndex] then
		local indexedStatus = statusOptions[statusIndex]
		if type(indexedStatus) == "table" then
			indexedStatus = indexedStatus.option or indexedStatus.id or indexedStatus.value or indexedStatus.label
		end
		if type(indexedStatus) == "string" and indexedStatus ~= "" then
			return indexedStatus
		end
	end
	return "securable"
end

local function resolveTradeRealm(tradeQuery)
	if not tradeQuery then
		return "pc"
	end
	if tradeQuery.controls and tradeQuery.controls.realm and tradeQuery.controls.realm.list then
		local selIndex = tradeQuery.controls.realm.selIndex
		local realmLabel = selIndex and tradeQuery.controls.realm.list[selIndex]
		if realmLabel and tradeQuery.realmIds and tradeQuery.realmIds[realmLabel] then
			tradeQuery.pbRealmIndex = selIndex
			tradeQuery.pbRealm = tradeQuery.realmIds[realmLabel]
			tradeQuery.realmDropList = copyTable(tradeQuery.controls.realm.list)
			return tradeQuery.pbRealm
		end
	end
	if tradeQuery.pbRealm and tradeQuery.pbRealm ~= "" then
		return tradeQuery.pbRealm
	end
	if tradeQuery.realmIds and tradeQuery.pbRealmIndex and tradeQuery.realmDropList and tradeQuery.realmDropList[tradeQuery.pbRealmIndex] then
		local realmLabel = tradeQuery.realmDropList[tradeQuery.pbRealmIndex]
		if realmLabel and tradeQuery.realmIds[realmLabel] then
			return tradeQuery.realmIds[realmLabel]
		end
	end
	return "pc"
end

local function resolveTradeLeague(tradeQuery)
	if not tradeQuery then
		return "Standard"
	end
	if tradeQuery.controls and tradeQuery.controls.league and tradeQuery.controls.league.list then
		local selIndex = tradeQuery.controls.league.selIndex or tradeQuery.pbLeagueIndex
		local selectedLeague = selIndex and tradeQuery.controls.league.list[selIndex]
		if selectedLeague then
			tradeQuery.pbLeagueIndex = selIndex
			tradeQuery.pbLeague = selectedLeague
			if tradeQuery.itemsTab then
				tradeQuery.itemsTab.leagueDropList = copyTable(tradeQuery.controls.league.list)
			else
				tradeQuery.leagueDropList = copyTable(tradeQuery.controls.league.list)
			end
			return selectedLeague
		end
	end
	if tradeQuery.pbLeague and tradeQuery.pbLeague ~= "" then
		return tradeQuery.pbLeague
	end
	local leagueList = tradeQuery.itemsTab and tradeQuery.itemsTab.leagueDropList or tradeQuery.leagueDropList
	if leagueList and tradeQuery.pbLeagueIndex and leagueList[tradeQuery.pbLeagueIndex] then
		return leagueList[tradeQuery.pbLeagueIndex]
	end
	return "Standard"
end

local function getTraderLeagueSelection(tradeQuery)
	if not (tradeQuery and tradeQuery.controls and tradeQuery.controls.league and tradeQuery.controls.league.list) then
		return
	end
	local leagueList = tradeQuery.controls.league.list
	local selIndex = tradeQuery.controls.league.selIndex
	if selIndex and leagueList[selIndex] then
		return leagueList, selIndex, leagueList[selIndex]
	end
end

local function getGemTradeCurrencyButtonState(tradeQuery, league, realm)
	if realm ~= "pc" then
		return "Currency Rates are not available", false, "Currency Conversion rates are pulled from PoE Ninja\nThe data is only available for the PC realm."
	end
	local conversionTable = loadTradeCurrencyConversionFromFile(tradeQuery, league)
	local updateTime = conversionTable and conversionTable.updateTime or nil
	if not updateTime then
		return "Get Currency Conversion Rates", true, "Currency Conversion rates are pulled from PoE Ninja\nUpdates are limited to once per hour and not necessary more than once per day"
	end
	local age = get_time() - updateTime
	if age < 3600 then
		return "Currency Rates are very recent", false, "Conversion Rates are less than an hour old (" .. tostring(age) .. " seconds old)"
	elseif age < 24 * 3600 then
		return "Currency Rates are recent", true, "Currency Conversion rates are pulled from PoE Ninja\nUpdates are limited to once per hour and not necessary more than once per day"
	end
	return "Update Currency Conversion Rates", true, "Currency Conversion rates are pulled from PoE Ninja\nUpdates are limited to once per hour and not necessary more than once per day"
end

local function buildGemTradeLeagueList(tradeQuery)
	local leagueList = { }
	local knownLeagues = { }
	local function addLeagueList(sourceList)
		for _, league in ipairs(sourceList or { }) do
			if type(league) == "string" and league ~= "" and not knownLeagues[league] then
				knownLeagues[league] = true
				t_insert(leagueList, league)
			end
		end
	end
	local realm = resolveTradeRealm(tradeQuery)
	local allLeagues = tradeQuery and tradeQuery.allLeagues and tradeQuery.allLeagues[realm]
	addLeagueList(allLeagues)
	addLeagueList(tradeQuery and tradeQuery.controls and tradeQuery.controls.league and tradeQuery.controls.league.list)
	local sourceList = tradeQuery and ((tradeQuery.itemsTab and tradeQuery.itemsTab.leagueDropList) or tradeQuery.leagueDropList) or { }
	addLeagueList(sourceList)
	local resolvedLeague = resolveTradeLeague(tradeQuery)
	if resolvedLeague ~= "" and not knownLeagues[resolvedLeague] then
		t_insert(leagueList, 1, resolvedLeague)
	end
	if #leagueList == 0 then
		t_insert(leagueList, "Standard")
	end
	return leagueList
end

local function resolvePreferredGemTradeLeague(tradeQuery, currentReportLeague)
	local traderLeague = resolveTradeLeague(tradeQuery)
	local leagueList = buildGemTradeLeagueList(tradeQuery)
	local knownLeagues = { }
	for _, league in ipairs(leagueList) do
		knownLeagues[league] = true
	end
	if traderLeague and traderLeague ~= "" and traderLeague ~= "Standard" and knownLeagues[traderLeague] then
		return traderLeague
	end
	if currentReportLeague and currentReportLeague ~= "" and knownLeagues[currentReportLeague] then
		return currentReportLeague
	end
	if traderLeague and traderLeague ~= "" and knownLeagues[traderLeague] then
		return traderLeague
	end
	return currentReportLeague or traderLeague or "Standard"
end

local function syncGemTradeLeagueSelection(self, controls, tradeQuery, fallbackLeague)
	if not (controls and controls.leagueSelect) then
		return fallbackLeague or resolvePreferredGemTradeLeague(tradeQuery, self.gemTradeLeague)
	end
	local traderLeagueList, traderSelIndex, traderLeague = getTraderLeagueSelection(tradeQuery)
	if traderLeagueList and traderSelIndex then
		controls.leagueSelect:SetList(copyTable(traderLeagueList))
		controls.leagueSelect:SetSel(traderSelIndex)
		self.gemTradeLeague = controls.leagueSelect.list[controls.leagueSelect.selIndex] or traderLeague or fallbackLeague or self.gemTradeLeague
		return self.gemTradeLeague
	end
	local selectedLeague = resolvePreferredGemTradeLeague(tradeQuery, fallbackLeague or self.gemTradeLeague)
	local leagueList = buildGemTradeLeagueList(tradeQuery)
	controls.leagueSelect:SetList(leagueList)
	controls.leagueSelect:SelByValue(selectedLeague, nil)
	if not controls.leagueSelect.list[controls.leagueSelect.selIndex] then
		controls.leagueSelect:SetSel(1)
	end
	self.gemTradeLeague = controls.leagueSelect.list[controls.leagueSelect.selIndex] or selectedLeague
	return self.gemTradeLeague
end

local function sortTradeLeaguesForPopup(leagues)
	local sortedLeagues = { }
	for _, league in ipairs(leagues or { }) do
		if league ~= "Standard" and league ~= "Ruthless" and league ~= "Hardcore" and league ~= "Hardcore Ruthless" then
			t_insert(sortedLeagues, league)
		end
	end
	t_insert(sortedLeagues, "Standard")
	t_insert(sortedLeagues, "Hardcore")
	t_insert(sortedLeagues, "Ruthless")
	t_insert(sortedLeagues, "Hardcore Ruthless")
	return sortedLeagues
end

local function ensureGemTradeLeagueSelectionFromState(tradeQuery, preferredLeague)
	if not tradeQuery then
		return "Standard"
	end
	local realm = resolveTradeRealm(tradeQuery)
	local realmLeagues = tradeQuery.allLeagues and tradeQuery.allLeagues[realm]
	if realmLeagues and #realmLeagues > 0 then
		tradeQuery.itemsTab.leagueDropList = copyTable(realmLeagues)
		local selectedIndex = tradeQuery.pbLeagueIndex
		local canPreferLeague = preferredLeague and preferredLeague ~= ""
		if canPreferLeague and preferredLeague == "Standard" then
			local hasExplicitTradeLeague = tradeQuery.pbLeague and tradeQuery.pbLeague ~= ""
			local hasExplicitSelection = tradeQuery.controls
				and tradeQuery.controls.league
				and tradeQuery.controls.league.selIndex
				and tradeQuery.controls.league.list
				and tradeQuery.controls.league.list[tradeQuery.controls.league.selIndex] == preferredLeague
			if not hasExplicitTradeLeague and not hasExplicitSelection then
				canPreferLeague = false
			end
		end
		if canPreferLeague then
			for index, league in ipairs(realmLeagues) do
				if league == preferredLeague then
					selectedIndex = index
					break
				end
			end
		elseif tradeQuery.pbLeague and tradeQuery.pbLeague ~= "" then
			for index, league in ipairs(realmLeagues) do
				if league == tradeQuery.pbLeague then
					selectedIndex = index
					break
				end
			end
		end
		selectedIndex = selectedIndex or 1
		if not realmLeagues[selectedIndex] then
			selectedIndex = 1
		end
		tradeQuery.pbLeagueIndex = selectedIndex
		tradeQuery.pbLeague = realmLeagues[selectedIndex]
		return tradeQuery.pbLeague
	end
	return tradeQuery.pbLeague or preferredLeague or "Standard"
end

local isPOESESSIDError

local function getGemTradeCacheDisplay(cacheEntry)
	if not cacheEntry then
		return "No status", "No status"
	end
	if cacheEntry.state == "done" then
		return cacheEntry.priceText or "--", nil
	elseif cacheEntry.state == "pending" then
		return "Fetching...", "Fetching..."
	elseif cacheEntry.state == "queued" then
		if cacheEntry.fetchAttempted then
			return "Queued", "Queued"
		end
		return "Fetch needed", "Fetch needed"
	elseif cacheEntry.state == "rate_limited" then
		return "Rate limited", "--"
	elseif cacheEntry.state == "skipped" then
		return "Unsupported", "Unsupported"
	elseif cacheEntry.state == "not_found" then
		return "No listings", "--"
	elseif cacheEntry.state == "error" then
		local errorText = tostring(cacheEntry.errorText or "")
		if errorText:find("Invalid query", 1, true) then
			return "Invalid query", "--"
		elseif isPOESESSIDError(errorText) then
			return "Session needed", "--"
		end
		return "Request failed", "--"
	end
	return "No status", "No status"
end

local function isResolvedGemTradePriceText(priceText)
	return priceText
		and priceText ~= "--"
		and priceText ~= "No status"
		and priceText ~= "Fetching..."
		and priceText ~= "Queued"
		and priceText ~= "Fetch needed"
		and priceText ~= "Rate limited"
		and priceText ~= "Unsupported"
		and priceText ~= "No listings"
		and priceText ~= "Invalid query"
		and priceText ~= "Session needed"
		and priceText ~= "Request failed"
end

isPOESESSIDError = function(errMsg)
	errMsg = tostring(errMsg or "")
	return errMsg:find("POESESSID", 1, true) ~= nil
		or errMsg:find("Session is invalid", 1, true) ~= nil
		or errMsg:find("Please provide your POESESSID", 1, true) ~= nil
end

local function getTradeRateLimitRetrySeconds(errMsg)
	errMsg = tostring(errMsg or "")
	local retrySeconds = errMsg:match("Rate limit exceeded; Please wait (%d+) seconds")
	return retrySeconds and tonumber(retrySeconds) or nil
end

function SkillsTabClass:GetGemTradeImbuedSupportStats()
	local state = self.gemTradeImbuedSupportStats
	if state and state.byGrantedEffectId then
		return state.byGrantedEffectId
	end
	local byGrantedEffectId = { }
	for grantedEffectId, skillData in pairs(data.skills) do
		local statId = skillData and skillData.name and imbuedTradeStatMap[skillData.name]
		if statId then
			byGrantedEffectId[grantedEffectId] = statId
		end
	end
	self.gemTradeImbuedSupportStats = { byGrantedEffectId = byGrantedEffectId }
	return byGrantedEffectId
end

local function isGemTradeRequestQueueStale(tradeQueryRequests)
	if not (tradeQueryRequests and tradeQueryRequests.rateLimiter) then
		return false
	end
	local rateLimiter = tradeQueryRequests.rateLimiter
	for _, key in ipairs({ "search", "fetch" }) do
		local policy = rateLimiter.GetPolicyName and rateLimiter:GetPolicyName(key)
		local history = policy and rateLimiter.requestHistory and rateLimiter.requestHistory[policy]
		local pendingRequests = policy and rateLimiter.pendingRequests and rateLimiter.pendingRequests[policy]
		if history and #history.timestamps > 0 and (not pendingRequests or #pendingRequests == 0) then
			local nextTime = rateLimiter.NextRequestTime and rateLimiter:NextRequestTime(policy, os.time()) or nil
			if (not rateLimiter.policies or not rateLimiter.policies[policy]) or (nextTime and nextTime >= 1956528000) then
				return true
			end
		end
	end
	return false
end

function SkillsTabClass:GetGemTradeQueryContext(selectedLeague)
	local tradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
	if not (tradeQuery and tradeQuery.tradeQueryRequests) then
		return nil, "Trader is unavailable."
	end
	if isGemTradeRequestQueueStale(tradeQuery.tradeQueryRequests) then
		tradeQuery.tradeQueryRequests = new("TradeQueryRequests")
	end
	local realm = resolveTradeRealm(tradeQuery)
	local league = selectedLeague or resolveTradeLeague(tradeQuery)
	return {
		tradeQuery = tradeQuery,
		realm = realm,
		league = league,
		status = getGemTradeStatusOption(tradeQuery),
	}
end

function SkillsTabClass:BuildGemTradePriceQuery(reportRow, queryContext)
	if not reportRow.tradeGemNameSpec or reportRow.tradeGemNameSpec == "" then
		return nil, "Missing gem name."
	end
	if reportRow.tradeQualityId and reportRow.tradeQualityId ~= "Default" then
		return nil, "Alt quality pricing is not supported yet."
	end

	local queryTable = {
		query = {
			status = { option = queryContext.status },
			type = reportRow.tradeGemNameSpec,
		},
		sort = { price = "asc" },
		engine = "new",
	}
	local miscFilters = { }
	if reportRow.targetLevel then
		miscFilters.gem_level = { min = reportRow.targetLevel, max = reportRow.targetLevel }
	end
	if reportRow.targetQuality ~= nil then
		miscFilters.quality = { min = reportRow.targetQuality, max = reportRow.targetQuality }
	end
	if reportRow.targetImbuedSupport
		or (reportRow.targetLevel or 0) > (reportRow.tradeNaturalMaxLevel or math.huge)
		or (reportRow.targetQuality or 0) > 20 then
		miscFilters.corrupted = { option = "true" }
	end
	queryTable.query.filters = {
		misc_filters = {
			filters = miscFilters,
		},
	}
	if reportRow.targetImbuedSupport then
		local statId = queryContext.imbuedSupportStatIds and queryContext.imbuedSupportStatIds[reportRow.targetImbuedSupport]
		if not statId then
			return nil, "Missing imbued support trade stat."
		end
		queryTable.query.stats = {
			{
				type = "and",
				filters = {
					{ id = statId, disabled = false, value = { } },
				},
			},
		}
	end
	return dkjson.encode(queryTable)
end

function SkillsTabClass:PrepareGemTradePriceQueue(report, league)
	self.gemTradePriceCache = self.gemTradePriceCache or { }
	for _, reportRow in ipairs(report or { }) do
		if canPriceGemTradeRow(reportRow) then
			local priceKey = getGemTradePriceKey(reportRow, league)
			if not self.gemTradePriceCache[priceKey] then
				self.gemTradePriceCache[priceKey] = {
					state = "queued",
					errorText = "Price not fetched yet. Click Fetch Prices to continue.",
				}
			end
		end
	end
end

function SkillsTabClass:ApplyGemTradePriceCache(report, league)
	local priceCache = self.gemTradePriceCache or { }
	for _, reportRow in ipairs(report or { }) do
		if canPriceGemTradeRow(reportRow) then
			local priceKey = getGemTradePriceKey(reportRow, league)
			local cacheEntry = resolveGemTradeCacheEntry(priceCache, priceKey)
			if cacheEntry then
				if cacheEntry.state == "done" and (not cacheEntry.priceChaos or cacheEntry.priceChaos <= 0)
					and cacheEntry.priceCurrency and cacheEntry.priceAmount then
					cacheEntry.priceChaos = tryConvertTradePriceToChaos(tradeQuery, league, cacheEntry.priceCurrency, cacheEntry.priceAmount)
				end
				local priceText, valueText = getGemTradeCacheDisplay(cacheEntry)
				reportRow.priceText = priceText
				reportRow.priceSort = cacheEntry.priceChaos
				reportRow.tradeUrl = cacheEntry.tradeUrl
				reportRow.tradePriceError = cacheEntry.errorText
				if cacheEntry.priceChaos and cacheEntry.priceChaos > 0 then
					reportRow.valueSort = reportRow.score / cacheEntry.priceChaos
					reportRow.valueText = string.format("%.2f", reportRow.valueSort)
				elseif cacheEntry.state == "done" then
					reportRow.valueSort = nil
					reportRow.valueText = "No rates"
				else
					reportRow.valueSort = nil
					reportRow.valueText = valueText or "--"
				end
			else
				reportRow.priceText = "Fetch needed"
				reportRow.priceSort = nil
				reportRow.tradeUrl = nil
				reportRow.tradePriceError = nil
				reportRow.valueSort = nil
				reportRow.valueText = "Fetch needed"
			end
		else
			reportRow.priceText = "Unsupported"
			reportRow.priceSort = nil
			reportRow.tradeUrl = nil
			reportRow.tradePriceError = "This row is not supported by the current trade pricing flow."
			reportRow.valueSort = nil
			reportRow.valueText = "Unsupported"
		end
	end
end

function SkillsTabClass:UpdateGemTradePriceStatus(controls, report)
	if not controls or not controls.priceStatus then
		return
	end
	local dispatched, queuedLocal, priced, issues = 0, 0, 0, 0
	local hasQueued = false
	local needsSession = false
	local rateLimitRetrySeconds = nil
	local priceCache = self.gemTradePriceCache or { }
	local league = controls.leagueSelect and controls.leagueSelect.list[controls.leagueSelect.selIndex] or self.gemTradeLeague or "Standard"
	for _, row in ipairs(report or { }) do
		if canPriceGemTradeRow(row) then
			local cacheEntry = resolveGemTradeCacheEntry(priceCache, getGemTradePriceKey(row, row.tradeLeague or league))
			local state = cacheEntry and cacheEntry.state or nil
			if state == "pending" then
				dispatched = dispatched + 1
			elseif state == "queued" then
				queuedLocal = queuedLocal + 1
				hasQueued = hasQueued or not cacheEntry.fetchAttempted
			elseif not cacheEntry then
				queuedLocal = queuedLocal + 1
				hasQueued = true
			elseif isResolvedGemTradePriceText(row.priceText) then
				priced = priced + 1
			elseif row.priceText ~= "--" then
				issues = issues + 1
			end
			if isPOESESSIDError(row.tradePriceError) then
				needsSession = true
			end
			local retrySeconds = getTradeRateLimitRetrySeconds(row.tradePriceError)
			if retrySeconds and (not rateLimitRetrySeconds or retrySeconds > rateLimitRetrySeconds) then
				rateLimitRetrySeconds = retrySeconds
			end
		end
	end
	if controls.fetchMore then
		controls.fetchMore.hasQueued = hasQueued and not rateLimitRetrySeconds
	end
	local tradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
	local searchQueue, fetchQueue = getGemTradeQueueCounts(tradeQuery and tradeQuery.tradeQueryRequests)
	local queueWaitSeconds = getGemTradeQueueWaitSeconds(tradeQuery and tradeQuery.tradeQueryRequests)
	controls.priceStatus.label = string.format("^7Prices (%s): %d priced, %d dispatched, %d queued, %d unavailable", league, priced, dispatched, queuedLocal, issues)
	if searchQueue > 0 or fetchQueue > 0 then
		controls.priceStatus.label = controls.priceStatus.label .. string.format("  ^7Queue s:%d f:%d", searchQueue, fetchQueue)
	end
	if needsSession then
		controls.priceStatus.label = controls.priceStatus.label .. "  ^xFF9922POESESSID required."
	elseif rateLimitRetrySeconds then
		controls.priceStatus.label = controls.priceStatus.label .. string.format("  ^xFF9922Trade API rate limited (%ds).", rateLimitRetrySeconds)
	elseif dispatched > 0 and queueWaitSeconds and queueWaitSeconds > 0 then
		controls.priceStatus.label = controls.priceStatus.label .. string.format("  ^xFF9922Trade queue waiting (%ds).", queueWaitSeconds)
	end
end

function SkillsTabClass:EnsureGemTradeLeagueList(controls, refreshReport)
	local tradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
	if not (tradeQuery and tradeQuery.tradeQueryRequests) then
		return
	end
	local function updateControlsFromTradeState()
		local preferredLeague = controls and controls.leagueSelect and controls.leagueSelect.list[controls.leagueSelect.selIndex] or self.gemTradeLeague
		local selectedLeague = ensureGemTradeLeagueSelectionFromState(tradeQuery, preferredLeague)
		syncGemTradeLeagueSelection(self, controls, tradeQuery, selectedLeague)
	end
	local function ensureRealmState(callback)
		if tradeQuery.pbRealm and tradeQuery.pbRealm ~= "" then
			return callback()
		end
		if main.POESESSID and main.POESESSID ~= "" then
			if self.gemTradeRealmListLoading then
				return
			end
			self.gemTradeRealmListLoading = true
			return tradeQuery.tradeQueryRequests:FetchRealmsAndLeaguesHTML(function(data, errMsg)
				self.gemTradeRealmListLoading = false
				if errMsg or not data then
					tradeQuery.realmIds = {
						["PC"] = "pc",
						["PS4"] = "sony",
						["Xbox"] = "xbox",
					}
					tradeQuery.realmDropList = { "PC", "PS4", "Xbox" }
					tradeQuery.pbRealmIndex = tradeQuery.pbRealmIndex or 1
					tradeQuery.pbRealm = tradeQuery.realmIds[tradeQuery.realmDropList[tradeQuery.pbRealmIndex] or "PC"] or "pc"
					return callback()
				end
				tradeQuery.allLeagues = {}
				for _, value in ipairs(data.leagues or { }) do
					if not tradeQuery.allLeagues[value.realm] then
						tradeQuery.allLeagues[value.realm] = {}
					end
					t_insert(tradeQuery.allLeagues[value.realm], value.id)
				end
				tradeQuery.realmIds = {}
				for _, value in pairs(data.realms or { }) do
					if value.text and value.text:match("PoE 1 ") then
						tradeQuery.realmIds[value.text:gsub("PoE 1 ", "")] = value.id
					end
				end
				tradeQuery.realmDropList = {}
				for realmLabel, _ in pairs(tradeQuery.realmIds) do
					if realmLabel == "PC" then
						t_insert(tradeQuery.realmDropList, 1, realmLabel)
					else
						t_insert(tradeQuery.realmDropList, realmLabel)
					end
				end
				tradeQuery.pbRealmIndex = tradeQuery.pbRealmIndex or 1
				local realmLabel = tradeQuery.realmDropList[tradeQuery.pbRealmIndex] or tradeQuery.realmDropList[1]
				tradeQuery.pbRealm = realmLabel and tradeQuery.realmIds[realmLabel] or "pc"
				if tradeQuery.allLeagues[tradeQuery.pbRealm] then
					tradeQuery.allLeagues[tradeQuery.pbRealm] = sortTradeLeaguesForPopup(tradeQuery.allLeagues[tradeQuery.pbRealm])
				end
				callback()
			end)
		end
		tradeQuery.realmIds = tradeQuery.realmIds or {
			["PC"] = "pc",
			["PS4"] = "sony",
			["Xbox"] = "xbox",
		}
		tradeQuery.realmDropList = tradeQuery.realmDropList or { "PC", "PS4", "Xbox" }
		tradeQuery.pbRealmIndex = tradeQuery.pbRealmIndex or 1
		tradeQuery.pbRealm = tradeQuery.pbRealm or tradeQuery.realmIds[tradeQuery.realmDropList[tradeQuery.pbRealmIndex] or "PC"] or "pc"
		callback()
	end
	local realm = resolveTradeRealm(tradeQuery)
	if tradeQuery.allLeagues and tradeQuery.allLeagues[realm] then
		updateControlsFromTradeState()
		return
	end
	if self.gemTradeLeagueListLoading then
		return
	end
	self.gemTradeLeagueListLoading = true
	if controls and controls.priceStatus then
		controls.priceStatus.label = "^7Prices: loading trade leagues..."
	end
	ensureRealmState(function()
		local resolvedRealm = resolveTradeRealm(tradeQuery)
		if tradeQuery.allLeagues and tradeQuery.allLeagues[resolvedRealm] then
			self.gemTradeLeagueListLoading = false
			updateControlsFromTradeState()
			if refreshReport then
				refreshReport(false, false)
			end
			return
		end
		tradeQuery.tradeQueryRequests:FetchLeagues(resolvedRealm, function(leagues, errMsg)
			self.gemTradeLeagueListLoading = false
			if errMsg then
				if controls and controls.priceStatus then
					controls.priceStatus.label = "^1Unable to load trade leagues: " .. errMsg
				end
				return
			end
			tradeQuery.allLeagues = tradeQuery.allLeagues or { }
			tradeQuery.allLeagues[resolvedRealm] = sortTradeLeaguesForPopup(leagues)
			updateControlsFromTradeState()
			if refreshReport then
				refreshReport(false, false)
			end
		end)
	end)
end

function SkillsTabClass:UpdateGemTradeCurrencyConversionButton(controls)
	local tradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
	if not (controls and controls.currencyRates and tradeQuery) then
		return
	end
	local selectedLeague = controls.leagueSelect and controls.leagueSelect.list[controls.leagueSelect.selIndex] or self.gemTradeLeague or resolveTradeLeague(tradeQuery)
	local realm = resolveTradeRealm(tradeQuery)
	local label, enabled, tooltipText = getGemTradeCurrencyButtonState(tradeQuery, selectedLeague, realm)
	controls.currencyRates.label = label
	controls.currencyRates.enabled = enabled
	controls.currencyRates.tooltipText = tooltipText
end

function SkillsTabClass:FetchGemTradeCurrencyConversion(controls, refreshReport)
	local tradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
	if not (tradeQuery and tradeQuery.tradeQueryRequests) then
		if controls and controls.priceStatus then
			controls.priceStatus.label = "^1Trader is unavailable."
		end
		return
	end
	local selectedLeague = controls and controls.leagueSelect and controls.leagueSelect.list[controls.leagueSelect.selIndex] or self.gemTradeLeague or resolveTradeLeague(tradeQuery)
	local realm = resolveTradeRealm(tradeQuery)
	if realm ~= "pc" then
		if controls and controls.priceStatus then
			controls.priceStatus.label = "^1Currency conversion is only available on the PC realm."
		end
		return
	end
	local now = get_time()
	local conversionTable = loadTradeCurrencyConversionFromFile(tradeQuery, selectedLeague)
	local updateTime = conversionTable and conversionTable.updateTime or nil
	if updateTime and (now - updateTime) < 3600 then
		self:UpdateGemTradeCurrencyConversionButton(controls)
		if refreshReport then
			refreshReport(false, false)
		end
		return
	end
	if (now - (tradeQuery.lastCurrencyConversionRequest or 0)) < 3600 then
		self:UpdateGemTradeCurrencyConversionButton(controls)
		return
	end
	if controls and controls.priceStatus then
		controls.priceStatus.label = "^7Prices: loading currency conversion rates..."
	end
	tradeQuery:FetchCurrencyConversionTable(function(data, errMsg)
		if errMsg then
			if controls and controls.priceStatus then
				controls.priceStatus.label = "^1Error: " .. tostring(errMsg)
			end
			return
		end
		tradeQuery.pbCurrencyConversion = tradeQuery.pbCurrencyConversion or { }
		tradeQuery.pbCurrencyConversion[selectedLeague] = { }
		tradeQuery.lastCurrencyConversionRequest = now
		launch:DownloadPage("https://poe.ninja/api/data/CurrencyRates?league=" .. urlEncode(selectedLeague), function(response, downloadErrMsg)
			if downloadErrMsg then
				if controls and controls.priceStatus then
					controls.priceStatus.label = "^1Error: " .. tostring(downloadErrMsg)
				end
				return
			end
			local jsonData = dkjson.decode(response.body)
			if not jsonData then
				if controls and controls.priceStatus then
					controls.priceStatus.label = "^1Failed to get PoE Ninja response."
				end
				return
			end
			for currencyName, chaosEquivalent in pairs(jsonData) do
				storeTradeCurrencyConversionRate(tradeQuery, selectedLeague, currencyName, chaosEquivalent)
			end
			tradeQuery.pbCurrencyConversion[selectedLeague].updateTime = get_time()
			local valuesFile = io.open("../" .. selectedLeague .. "_currency_values.json", "w")
			if valuesFile then
				valuesFile:write(dkjson.encode(tradeQuery.pbCurrencyConversion[selectedLeague]))
				valuesFile:close()
			end
			self:UpdateGemTradeCurrencyConversionButton(controls)
			if refreshReport then
				refreshReport(false, false)
			end
		end)
	end)
end

function SkillsTabClass:OpenGemTradeSessionPopup(refreshReport)
	local tradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
	local poesessidControls = { }
	poesessidControls.sessionInput = new("EditControl", nil, { 0, 18, 350, 18 }, main.POESESSID, nil, "%X", 32)
	poesessidControls.sessionInput:SetProtected(true)
	poesessidControls.sessionInput.placeholder = "Enter your session ID here"
	poesessidControls.sessionInput.tooltipText = "You can get this from your web browser's cookies while logged into the Path of Exile website."
	poesessidControls.save = new("ButtonControl", { "TOPRIGHT", poesessidControls.sessionInput, "TOP" }, { -8, 24, 90, 20 }, "Save", function()
		main.POESESSID = poesessidControls.sessionInput.buf
		main:ClosePopup()
		main:SaveSettings()
		if tradeQuery and tradeQuery.UpdateRealms then
			tradeQuery:UpdateRealms()
		end
		if refreshReport then
			refreshReport(false, false)
		end
	end)
	poesessidControls.save.enabled = function()
		return #poesessidControls.sessionInput.buf == 32 or poesessidControls.sessionInput.buf == 0
	end
	poesessidControls.cancel = new("ButtonControl", { "TOPLEFT", poesessidControls.sessionInput, "TOP" }, { 8, 24, 90, 20 }, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(364, 72, "Change session ID", poesessidControls)
end

function SkillsTabClass:StartGemReportBuild(popupSession, buildFunction, progressFunction, completeFunction, errorFunction)
	self.currentReportBuildSession = popupSession
	self:StopGemReportBuild()
	local buildState = {
		report = { },
		batchSize = 1,
		completedGroups = 0,
		totalGroups = 0,
	}
	local buildCoroutine = coroutine.create(function()
		return buildFunction(buildState)
	end)
	main.onFrameFuncs[gemReportBuildPumpKey] = function()
		if self.currentReportBuildSession ~= popupSession then
			main.onFrameFuncs[gemReportBuildPumpKey] = nil
			return
		end
		local resumed = false
		for _ = 1, 2 do
			if coroutine.status(buildCoroutine) == "dead" then
				break
			end
			local ok, result = coroutine.resume(buildCoroutine)
			if not ok then
				main.onFrameFuncs[gemReportBuildPumpKey] = nil
				if errorFunction then
					errorFunction(result, buildState)
				end
				return
			end
			resumed = true
			if coroutine.status(buildCoroutine) == "dead" then
				main.onFrameFuncs[gemReportBuildPumpKey] = nil
				if completeFunction then
					completeFunction(result or buildState.report, buildState)
				end
				return
			end
		end
		if resumed and progressFunction then
			progressFunction(buildState.report, buildState)
		end
	end
end

function SkillsTabClass:StopGemReportBuild()
	main.onFrameFuncs[gemReportBuildPumpKey] = nil
	main.onFrameFuncs[gemReportInitPumpKey] = nil
end

local function getReportBuildStatusText(prefix, buildState)
	local completedGroups = buildState and buildState.completedGroups or 0
	local totalGroups = buildState and buildState.totalGroups or 0
	if totalGroups and totalGroups > 0 then
		return string.format("^7%s... %d/%d groups", prefix, completedGroups, totalGroups)
	end
	return "^7" .. prefix .. "..."
end

function SkillsTabClass:DeferGemReportInit(popupSession, callback)
	main.onFrameFuncs[gemReportInitPumpKey] = function()
		main.onFrameFuncs[gemReportInitPumpKey] = nil
		if self.currentReportBuildSession == popupSession and callback then
			callback()
		end
	end
end

function SkillsTabClass:StartGemTradeQueuePump(popupSession)
	main.onFrameFuncs[gemTradeQueuePumpKey] = function()
		if self.gemTradePopupSession ~= popupSession then
			main.onFrameFuncs[gemTradeQueuePumpKey] = nil
			return
		end
		local tradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
		if tradeQuery and tradeQuery.tradeQueryRequests then
			tradeQuery.tradeQueryRequests:ProcessQueue()
		end
	end
end

function SkillsTabClass:StopGemTradeQueuePump()
	main.onFrameFuncs[gemTradeQueuePumpKey] = nil
end

function SkillsTabClass:PrimeGemTradePrices(report, controls, refreshReport, selectedLeague)
	local queryContext, errMsg = self:GetGemTradeQueryContext(selectedLeague)
	if not queryContext then
		if controls and controls.priceStatus then
			controls.priceStatus.label = "^1" .. errMsg
		end
		return
	end
	queryContext.imbuedSupportStatIds = self:GetGemTradeImbuedSupportStats()

	self.gemTradePriceCache = self.gemTradePriceCache or { }
	self.gemTradePricePendingPrime = false
	local popupSession = self.gemTradePopupSession or 0
	local fetchLimit = self.gemTradePriceFetchBudget or 0
	local requestedCount = 0
	local issuedRequests = 0
	local rateLimitRetrySeconds = nil
	self.gemTradeQueryToPriceKey = self.gemTradeQueryToPriceKey or { }
	for _, reportRow in ipairs(report or { }) do
		if canPriceGemTradeRow(reportRow) then
			local existingEntry = resolveGemTradeCacheEntry(self.gemTradePriceCache, getGemTradePriceKey(reportRow, queryContext.league))
			if existingEntry and existingEntry.fetchAttempted then
				requestedCount = requestedCount + 1
			end
			local retrySeconds = existingEntry and getTradeRateLimitRetrySeconds(existingEntry.errorText)
			if retrySeconds and (not rateLimitRetrySeconds or retrySeconds > rateLimitRetrySeconds) then
				rateLimitRetrySeconds = retrySeconds
			end
		end
	end
	if rateLimitRetrySeconds then
		self:UpdateGemTradePriceStatus(controls, report)
		return
	end
	local queued = 0
	for _, reportRow in ipairs(report or { }) do
		if canPriceGemTradeRow(reportRow) then
			local priceKey = getGemTradePriceKey(reportRow, queryContext.league)
			local existingEntry = self.gemTradePriceCache[priceKey]
			if existingEntry and existingEntry.state == "alias" then
				existingEntry = resolveGemTradeCacheEntry(self.gemTradePriceCache, priceKey)
			end
			if not existingEntry or existingEntry.state == "queued" then
				local query, queryErr = self:BuildGemTradePriceQuery(reportRow, queryContext)
				if not query then
					self.gemTradePriceCache[priceKey] = {
						state = queryErr == "Alt quality pricing is not supported yet." and "skipped" or "error",
						errorText = queryErr,
					}
				else
					local queryFingerprint = getGemTradeQueryFingerprint(queryContext, query)
					local canonicalPriceKey = self.gemTradeQueryToPriceKey[queryFingerprint]
					local canonicalEntry = canonicalPriceKey and resolveGemTradeCacheEntry(self.gemTradePriceCache, canonicalPriceKey) or nil
					if canonicalPriceKey == priceKey then
						self.gemTradeQueryToPriceKey[queryFingerprint] = nil
						canonicalPriceKey = nil
						canonicalEntry = nil
					end
					if canonicalPriceKey and canonicalEntry then
						self.gemTradePriceCache[priceKey] = {
							state = "alias",
							aliasKey = canonicalPriceKey,
						}
					elseif canonicalPriceKey and not canonicalEntry then
						self.gemTradeQueryToPriceKey[queryFingerprint] = nil
					end
					local cacheEntry = self.gemTradePriceCache[priceKey]
					if cacheEntry and cacheEntry.state == "queued" and not cacheEntry.fetchAttempted then
						self.gemTradeQueryToPriceKey[queryFingerprint] = priceKey
						cacheEntry.queryFingerprint = queryFingerprint
						if (requestedCount + queued) < fetchLimit then
							queued = queued + 1
							issuedRequests = issuedRequests + 1
							cacheEntry.fetchAttempted = true
							queryContext.tradeQuery.tradeQueryRequests:SearchWithQuery(
								queryContext.realm,
								queryContext.league,
								query,
								function(items, callbackErrMsg)
									local retrySeconds = getTradeRateLimitRetrySeconds(callbackErrMsg)
									if retrySeconds then
										cacheEntry.state = "rate_limited"
										cacheEntry.errorText = callbackErrMsg
									elseif callbackErrMsg then
										cacheEntry.state = "error"
										cacheEntry.errorText = callbackErrMsg
								elseif not items or not items[1] then
									cacheEntry.state = "not_found"
									cacheEntry.errorText = "No trade result found."
								else
									local bestItem = items[1]
									cacheEntry.state = "done"
									cacheEntry.priceAmount = bestItem.amount
									cacheEntry.priceCurrency = bestItem.currency
									cacheEntry.priceText = formatTradePrice(bestItem.amount, bestItem.currency)
									cacheEntry.priceChaos = tryConvertTradePriceToChaos(queryContext.tradeQuery, queryContext.league, bestItem.currency, bestItem.amount)
								end
									if self.gemTradePopupSession == popupSession and refreshReport then
										refreshReport(false, false)
									end
								end,
								{
									onDispatch = function()
										if cacheEntry.state == "queued" then
											cacheEntry.state = "pending"
											if self.gemTradePopupSession == popupSession and refreshReport then
												refreshReport(false, false)
											end
										end
									end,
									callbackQueryId = function(queryId)
										cacheEntry.tradeUrl = queryContext.tradeQuery.tradeQueryRequests:buildUrl(queryContext.tradeQuery.hostName .. "trade/search", queryContext.realm, queryContext.league, queryId)
									end,
								}
							)
						else
							cacheEntry.errorText = "Price not fetched yet. Click Fetch Prices to continue."
						end
					end
				end
			end
		end
	end
	self:ApplyGemTradePriceCache(report, queryContext.league)
	self:UpdateGemTradePriceStatus(controls, report)
	if issuedRequests > 0 then
		queryContext.tradeQuery.tradeQueryRequests:ProcessQueue()
	end
end

function SkillsTabClass:OpenSelectedGemTrade(controls, refreshReport)
	local reportRow = controls and controls.reportList and controls.reportList.selValue
	if not reportRow then
		return
	end
	if reportRow.tradeUrl and reportRow.tradeUrl ~= "" then
		OpenURL(reportRow.tradeUrl)
		return
	end
	local selectedLeague = controls and controls.leagueSelect and controls.leagueSelect.list[controls.leagueSelect.selIndex] or self.gemTradeLeague
	local queryContext, errMsg = self:GetGemTradeQueryContext(selectedLeague)
	if not queryContext then
		if controls and controls.priceStatus then
			controls.priceStatus.label = "^1" .. errMsg
		end
		return
	end
	if reportRow.targetImbuedSupport then
		queryContext.imbuedSupportStatIds = self:GetGemTradeImbuedSupportStats()
	end
	local query, queryErr = self:BuildGemTradePriceQuery(reportRow, queryContext)
	if not query then
		if controls and controls.priceStatus then
			controls.priceStatus.label = "^1" .. queryErr
		end
		return
	end
	local directUrl = queryContext.tradeQuery.tradeQueryRequests:buildUrl(queryContext.tradeQuery.hostName .. "trade/search", queryContext.realm, queryContext.league)
	directUrl = directUrl .. "?q=" .. urlEncode(query)
	reportRow.tradeUrl = directUrl
	OpenURL(directUrl)
end

function SkillsTabClass:SelectGemFromUpgradeReport(reportRow, popupsToClose)
	if not reportRow then
		return
	end

	local groupIndex = isValueInArray(self.socketGroupList, reportRow.socketGroup)
	if not groupIndex then
		return
	end

	self.controls.groupList:SelectIndex(groupIndex)
	self:SetDisplayGroup(self.socketGroupList[groupIndex])
	if self.gemSlots[reportRow.gemIndex] and self.gemSlots[reportRow.gemIndex].nameSpec then
		self:SelectControl(self.gemSlots[reportRow.gemIndex].nameSpec)
	end

	for _ = 1, popupsToClose or 1 do
		if main.popups[1] then
			main:ClosePopup()
		end
	end
end

function SkillsTabClass:AddGemQualitySummaryToTooltip(tooltip, gemInstance, qualityAmount)
	if not (gemInstance and gemInstance.gemData) then
		return 0
	end
	local gemData = gemInstance.gemData
	local qualityType = gemInstance.qualityId or "Default"
	local qualityValue = m_max(0, qualityAmount or gemInstance.quality or 0)
	if qualityValue <= 0 then
		return 0
	end

	local lineCount = 0
	local function addQualityLines(qualityList, grantedEffect)
		tooltip:AddLine(18, colorCodes.GEM .. grantedEffect.name)
		tooltip:AddLine(16, colorCodes.NORMAL .. "At +" .. tostring(qualityValue) .. "% Quality:")
		for _, qual in pairs(qualityList) do
			local stats = { }
			stats[qual[1]] = qual[2] * qualityValue
			local descriptions = self.build.data.describeStats(stats, grantedEffect.statDescriptionScope)
			for _, line in ipairs(descriptions) do
				if line then
					if grantedEffect.statMap[qual[1]] or self.build.data.skillStatMap[qual[1]] then
						tooltip:AddLine(16, colorCodes.MAGIC .. line)
					else
						local unsupportedLine = colorCodes.UNSUPPORTED .. line
						unsupportedLine = main.notSupportedModTooltips and (unsupportedLine .. main.notSupportedTooltipText) or unsupportedLine
						tooltip:AddLine(16, unsupportedLine)
					end
					lineCount = lineCount + 1
				end
			end
		end
	end

	local addedSection = false
	if gemData.grantedEffect and gemData.grantedEffect.qualityStats and gemData.grantedEffect.qualityStats[qualityType] then
		addQualityLines(gemData.grantedEffect.qualityStats[qualityType], gemData.grantedEffect)
		addedSection = true
	end
	if gemData.secondaryGrantedEffect and gemData.secondaryGrantedEffect.qualityStats and gemData.secondaryGrantedEffect.qualityStats[qualityType] then
		if addedSection then
			tooltip:AddSeparator(10)
		end
		addQualityLines(gemData.secondaryGrantedEffect.qualityStats[qualityType], gemData.secondaryGrantedEffect)
	end
	return lineCount
end

function SkillsTabClass:GetGemUpgradeReportStatValue(output, statData)
	if not (output and statData and statData.stat) then
		return nil
	end
	local statValue = output[statData.stat]
	if statValue == nil and output.Minion then
		statValue = output.Minion[statData.stat]
	end
	if statValue == nil then
		statValue = 0
	end
	if statData.transform then
		statValue = statData.transform(statValue)
	end
	return statValue
end

function SkillsTabClass:FindGemUpgradeQualityBreakpoint(gemInstance, reportRow, calcFunc)
	local statData = self.gemUpgradeSortStat
	if not (gemInstance and reportRow and calcFunc and statData and statData.stat) then
		return nil
	end
	local currentQuality = gemInstance.quality or 0
	local targetQuality = reportRow.targetQuality or currentQuality
	if targetQuality <= currentQuality then
		return nil
	end

	local currentLevel = gemInstance.level or 0
	local contextLevel = reportRow.targetLevel or currentLevel
	local useFullDPS = reportRow.useFullDPS

	gemInstance.level = contextLevel
	gemInstance.quality = currentQuality
	local baseErr, baseOutput = PCall(calcFunc, nil, useFullDPS)
	if baseErr then
		gemInstance.level = currentLevel
		gemInstance.quality = currentQuality
		return nil
	end
	local baseStatValue = self:GetGemUpgradeReportStatValue(baseOutput, statData)

	for quality = currentQuality + 1, targetQuality do
		gemInstance.quality = quality
		local errMsg, output = PCall(calcFunc, nil, useFullDPS)
		if not errMsg then
			local statValue = self:GetGemUpgradeReportStatValue(output, statData)
			if statValue ~= baseStatValue then
				gemInstance.level = currentLevel
				gemInstance.quality = currentQuality
				return quality
			end
		end
	end

	gemInstance.level = currentLevel
	gemInstance.quality = currentQuality
	return nil
end

function SkillsTabClass:GetGemUpgradeReportTooltipHelper()
	if not self.gemUpgradeReportTooltipHelper then
		self.gemUpgradeReportTooltipHelper = new("GemSelectControl", nil, { 0, 0, 1, 1 }, self, 1, function() end, true)
	end
	return self.gemUpgradeReportTooltipHelper
end

function SkillsTabClass:AddGemUpgradeReportPreviewGemTooltip(tooltip, gemInstance)
	if not (gemInstance and gemInstance.gemData) then
		return false
	end
	local tooltipHelper = self:GetGemUpgradeReportTooltipHelper()
	local prevTooltip = tooltipHelper.tooltip
	local prevCenter = tooltip.center
	local prevColor = tooltip.color
	local prevHeader = tooltip.tooltipHeader
	tooltipHelper.tooltip = tooltip
	tooltipHelper:AddGemTooltip(gemInstance)
	tooltipHelper.tooltip = prevTooltip
	tooltip.center = prevCenter
	tooltip.color = prevColor
	tooltip.tooltipHeader = prevHeader
	return true
end

function SkillsTabClass:AddGemUpgradeReportPreviewGemDataTooltip(tooltip, gemData, level, quality, qualityId, imbuedSupport)
	if not gemData then
		return false
	end
	local previewGem = {
		gemData = gemData,
		gemId = gemData.id,
		skillId = gemData.grantedEffectId,
		nameSpec = gemData.name,
		level = level or gemData.naturalMaxLevel or 1,
		quality = quality or 0,
		qualityId = qualityId or "Default",
		imbuedSupport = imbuedSupport,
		enabled = true,
		count = 1,
	}
	return self:AddGemUpgradeReportPreviewGemTooltip(tooltip, previewGem)
end

local function getGemUpgradeReportDeltaText(delta)
	if delta > 0 then
		return " (" .. colorCodes.MAGIC .. "+" .. delta .. "^7)"
	elseif delta < 0 then
		return " (" .. colorCodes.WARNING .. delta .. "^7)"
	end
	return ""
end

function SkillsTabClass:RewriteGemUpgradeReportCandidateTooltip(tooltip, startLineIndex, currentGem, candidateGem)
	if not (tooltip and currentGem and candidateGem) then
		return
	end

	local currentLevel = currentGem.level or 0
	local candidateLevel = candidateGem.level or currentLevel
	local currentQuality = currentGem.quality or 0
	local candidateQuality = candidateGem.quality or currentQuality
	local levelDeltaText = getGemUpgradeReportDeltaText(candidateLevel - currentLevel)
	local qualityDeltaText = getGemUpgradeReportDeltaText(candidateQuality - currentQuality)
	local maxText = (candidateGem.gemData and candidateGem.gemData.naturalMaxLevel and candidateLevel >= candidateGem.gemData.naturalMaxLevel) and " (Max)" or ""

	for lineIndex = startLineIndex, #tooltip.lines do
		local line = tooltip.lines[lineIndex]
		if line and line.text then
			if line.text:match("^%^x7F7F7FLevel: ") then
				line.text = string.format("^x7F7F7FLevel: ^7%d%s%s", candidateLevel, levelDeltaText, maxText)
			elseif line.text:match("^%^x7F7F7FQuality: ") then
				line.text = string.format("^x7F7F7FQuality: " .. colorCodes.MAGIC .. "+%d%%^7%s", candidateQuality, qualityDeltaText)
			end
		end
	end
end

function SkillsTabClass:AddGemUpgradeReportCurrentGemTooltip(tooltip, reportRow)
	local socketGroup = reportRow and reportRow.socketGroup
	local gemInstance = socketGroup and socketGroup.gemList and socketGroup.gemList[reportRow.gemIndex]
	return self:AddGemUpgradeReportPreviewGemTooltip(tooltip, gemInstance)
end

function SkillsTabClass:AddGemUpgradeReportCandidateGemTooltip(tooltip, reportRow)
	local socketGroup = reportRow and reportRow.socketGroup
	local gemInstance = socketGroup and socketGroup.gemList and socketGroup.gemList[reportRow.gemIndex]
	if not (gemInstance and gemInstance.gemData) then
		return false
	end

	local previewGem = copyTable(gemInstance, true)
	previewGem.level = reportRow.targetLevel or previewGem.level
	previewGem.quality = reportRow.targetQuality or previewGem.quality
	previewGem.qualityId = reportRow.tradeQualityId or previewGem.qualityId or "Default"
	previewGem.imbuedSupport = reportRow.targetImbuedSupport or previewGem.imbuedSupport
	previewGem.displayEffect = nil
	local startLineIndex = #tooltip.lines + 1
	if not self:AddGemUpgradeReportPreviewGemTooltip(tooltip, previewGem) then
		return false
	end
	self:RewriteGemUpgradeReportCandidateTooltip(tooltip, startLineIndex, gemInstance, previewGem)
	if reportRow.targetImbuedSupport then
		tooltip:AddSeparator(8)
		self:AddGemUpgradeReportSupportTooltip(tooltip, reportRow.targetImbuedSupport)
	end
	return true
end

function SkillsTabClass:AddGemUpgradeReportSupportTooltip(tooltip, supportGrantedEffectId)
	local grantedEffect = supportGrantedEffectId and data.skills[supportGrantedEffectId]
	local gemId = grantedEffect and data.gemForSkill[grantedEffect]
	local gemData = gemId and self.build.data.gems[gemId]
	if not gemData then
		return false
	end
	return self:AddGemUpgradeReportPreviewGemDataTooltip(tooltip, gemData, 1, 0, "Default")
end

function SkillsTabClass:AddGemUpgradeReportMethodTooltip(tooltip, reportRow)
	tooltip:Clear()
	tooltip:AddLine(16, "^7Method: ^x33FF77" .. tostring(reportRow.upgradeLabel))
	if reportRow.sourceType == "TRADE" then
		tooltip:AddLine(14, "^7Buys a stronger version of the current gem.")
	elseif reportRow.sourceType == "NATURAL" then
		tooltip:AddLine(14, "^7Improves the current gem without corruption.")
	elseif reportRow.sourceType == "CORRUPTION" then
		tooltip:AddLine(14, "^7Targets a corruption outcome on the current gem.")
	elseif reportRow.sourceType == "VENDOR" then
		tooltip:AddLine(14, "^7Transforms the current gem with the vendor recipe.")
	elseif reportRow.sourceType == "IMBUED" then
		if reportRow.upgradeLabel == "Coin of Knowledge" then
			tooltip:AddLine(14, "^7Adds a valid Intelligence support to the current gem.")
		elseif reportRow.upgradeLabel == "Coin of Power" then
			tooltip:AddLine(14, "^7Adds a valid Strength support to the current gem.")
		elseif reportRow.upgradeLabel == "Coin of Skill" then
			tooltip:AddLine(14, "^7Adds a valid Dexterity support to the current gem.")
		else
			tooltip:AddLine(14, "^7Adds an inherent level 1 support to the current gem.")
		end
	end
end

function SkillsTabClass:AddGemUpgradeReportImprovementTooltip(tooltip, reportRow)
	tooltip:Clear()
	local sortStatLabel = (self.gemUpgradeSortStat and self.gemUpgradeSortStat.label) or "selected stat"
	tooltip:AddLine(16, "^7Relative gain for ^x33FF77" .. sortStatLabel)
	if reportRow.hasImprovementPct then
		tooltip:AddLine(14, string.format("^7Improvement: ^x33FF77%+.2f%%", reportRow.improvementPct))
		tooltip:AddLine(14, "^7Absolute delta: " .. tostring(reportRow.deltaStr))
	else
		tooltip:AddLine(14, "^7No relative percentage is available for this stat.")
	end
end

function SkillsTabClass:AddGemUpgradeReportDeltaTooltip(tooltip, reportRow)
	tooltip:Clear()
	if not reportRow or not reportRow.socketGroup then
		return
	end

	local socketGroup = reportRow.socketGroup
	local gemInstance = socketGroup.gemList and socketGroup.gemList[reportRow.gemIndex]
	if not gemInstance then
		tooltip:AddLine(14, "^1Unable to find gem for this report row.")
		return
	end

	local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator()
	if not calcFunc then
		tooltip:AddLine(14, "^1Unable to calculate upgrade delta.")
		return
	end

	local currentLevel = gemInstance.level
	local currentQuality = gemInstance.quality
	local currentImbuedSupport = gemInstance.imbuedSupport
	gemInstance.level = reportRow.targetLevel or gemInstance.level
	gemInstance.quality = reportRow.targetQuality or gemInstance.quality
	gemInstance.imbuedSupport = reportRow.targetImbuedSupport or gemInstance.imbuedSupport

	local errMsg, upgradedOutput = PCall(calcFunc, nil, reportRow.useFullDPS)

	gemInstance.level = currentLevel
	gemInstance.quality = currentQuality
	gemInstance.imbuedSupport = currentImbuedSupport
	self:ProcessSocketGroup(socketGroup)

	if errMsg then
		tooltip:AddLine(14, "^1Unable to calculate delta for this upgrade.")
		return
	end

	local changeCount = self.build:AddStatComparesToTooltip(tooltip, calcBase, upgradedOutput, "^7Stat delta:")
	if changeCount == 0 then
		tooltip:AddLine(14, "^7No measurable stat change for current config.")
	end
end

function SkillsTabClass:AddGemTradePriceTooltip(tooltip, reportRow)
	tooltip:Clear()
	tooltip:AddLine(16, "^7Trade price")
	tooltip:AddLine(14, "^7League: ^x33FF77" .. tostring(reportRow.tradeLeague or self.gemTradeLeague or "Standard"))
	if isResolvedGemTradePriceText(reportRow.priceText) then
		tooltip:AddLine(14, "^7Lowest listed price: ^x33FF77" .. tostring(reportRow.priceText))
	elseif reportRow.priceText == "Unsupported" then
		tooltip:AddLine(14, "^1This row is not supported by the current trade pricing flow.")
		if reportRow.tradePriceError and reportRow.tradePriceError ~= "" then
			tooltip:AddLine(14, "^7Reason: ^8" .. tostring(reportRow.tradePriceError))
		end
	elseif reportRow.priceText == "No status" then
		tooltip:AddLine(14, "^1This row has no resolved pricing state yet.")
		if reportRow.tradePriceError and reportRow.tradePriceError ~= "" then
			tooltip:AddLine(14, "^7Detail: ^8" .. tostring(reportRow.tradePriceError))
		else
			tooltip:AddLine(14, "^7Detail: ^8The report did not assign a final pricing status for this row.")
		end
	elseif reportRow.priceText == "Invalid query" then
		tooltip:AddLine(14, "^1The trade API rejected this search query.")
		if reportRow.tradePriceError and reportRow.tradePriceError ~= "" then
			tooltip:AddLine(14, "^7Error: ^8" .. tostring(reportRow.tradePriceError))
		end
	elseif reportRow.priceText == "No listings" then
		tooltip:AddLine(14, "^7No matching instant-buyout listings were found.")
	elseif reportRow.priceText == "Rate limited" then
		tooltip:AddLine(14, "^1The trade API is temporarily rate limited.")
		if reportRow.tradePriceError and reportRow.tradePriceError ~= "" then
			tooltip:AddLine(14, "^7Status: ^8" .. tostring(reportRow.tradePriceError))
		end
	elseif reportRow.priceText == "Session needed" then
		tooltip:AddLine(14, "^1A valid POESESSID is required for this search.")
	else
		tooltip:AddLine(14, "^7Status: ^8" .. tostring(reportRow.priceText or "--"))
		if reportRow.tradePriceError and reportRow.tradePriceError ~= "" then
			tooltip:AddLine(14, "^7Detail: ^8" .. tostring(reportRow.tradePriceError))
		end
	end
end

function SkillsTabClass:AddGemTradeValueTooltip(tooltip, reportRow)
	tooltip:Clear()
	tooltip:AddLine(16, "^7Stat Value / Price")
	if reportRow.valueSort then
		tooltip:AddLine(14, "^7Value: ^x33FF77" .. tostring(reportRow.valueText))
	elseif reportRow.priceText == "Unsupported" or reportRow.priceText == "No status" then
		tooltip:AddLine(14, "^7Value is unavailable because price resolution did not complete for this row.")
		if reportRow.tradePriceError and reportRow.tradePriceError ~= "" then
			tooltip:AddLine(14, "^7Reason: ^8" .. tostring(reportRow.tradePriceError))
		end
	elseif reportRow.priceSort then
		tooltip:AddLine(14, "^7Currency conversion rates are required to calculate value.")
	else
		tooltip:AddLine(14, "^7Fetch a trade price first to calculate value.")
	end
end

function SkillsTabClass:AddSupportReplacementSkillTooltip(tooltip, reportRow)
	tooltip:Clear()
	tooltip:AddLine(16, "^7Skill: ^x33FF77" .. tostring(reportRow.skillName))
	if reportRow.groupLabel and reportRow.groupLabel ~= "" then
		tooltip:AddLine(14, "^7Socket Group: ^x33FF77" .. tostring(reportRow.groupLabel))
	end
	tooltip:AddLine(14, "^7The report compares the current support against other valid supports for this skill.")
end

function SkillsTabClass:AddSupportReplacementCurrentTooltip(tooltip, reportRow)
	local socketGroup = reportRow and reportRow.socketGroup
	local gemInstance = socketGroup and socketGroup.gemList and socketGroup.gemList[reportRow.gemIndex]
	tooltip:Clear()
	return self:AddGemUpgradeReportPreviewGemTooltip(tooltip, gemInstance)
end

function SkillsTabClass:AddSupportReplacementCandidateTooltip(tooltip, reportRow)
	tooltip:Clear()
	local gemData = reportRow and reportRow.candidateGemId and self.build.data.gems[reportRow.candidateGemId]
	return self:AddGemUpgradeReportPreviewGemDataTooltip(tooltip, gemData, reportRow.candidateLevel, reportRow.candidateQuality, reportRow.candidateQualityId)
end

function SkillsTabClass:AddSupportReplacementDeltaTooltip(tooltip, reportRow)
	tooltip:Clear()
	if not reportRow or not reportRow.socketGroup then
		return
	end
	local socketGroup = reportRow.socketGroup
	local gemInstance = socketGroup.gemList and socketGroup.gemList[reportRow.gemIndex]
	local candidateGemData = reportRow.candidateGemId and self.build.data.gems[reportRow.candidateGemId]
	if not (gemInstance and candidateGemData) then
		tooltip:AddLine(14, "^1Unable to find support data for this report row.")
		return
	end

	local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator()
	if not calcFunc then
		tooltip:AddLine(14, "^1Unable to calculate support replacement delta.")
		return
	end

	local currentGemId = gemInstance.gemId
	local currentNameSpec = gemInstance.nameSpec
	local currentSkillId = gemInstance.skillId
	local currentGemData = gemInstance.gemData
	local currentGrantedEffect = gemInstance.grantedEffect
	local currentLevel = gemInstance.level
	local currentQuality = gemInstance.quality
	local currentQualityId = gemInstance.qualityId
	local currentImbuedSupport = gemInstance.imbuedSupport
	local currentCorrupted = gemInstance.corrupted

	gemInstance.gemId = candidateGemData.id
	gemInstance.nameSpec = candidateGemData.name
	gemInstance.skillId = candidateGemData.grantedEffectId
	gemInstance.gemData = candidateGemData
	gemInstance.grantedEffect = candidateGemData.grantedEffect
	gemInstance.level = reportRow.candidateLevel
	gemInstance.quality = reportRow.candidateQuality
	gemInstance.qualityId = reportRow.candidateQualityId or "Default"
	gemInstance.imbuedSupport = nil
	gemInstance.corrupted = (reportRow.candidateLevel or 0) > (candidateGemData.naturalMaxLevel or 0) or (reportRow.candidateQuality or 0) > 20
	self:ProcessSocketGroup(socketGroup)

	local errMsg, upgradedOutput = PCall(calcFunc, nil, reportRow.useFullDPS)

	gemInstance.gemId = currentGemId
	gemInstance.nameSpec = currentNameSpec
	gemInstance.skillId = currentSkillId
	gemInstance.gemData = currentGemData
	gemInstance.grantedEffect = currentGrantedEffect
	gemInstance.level = currentLevel
	gemInstance.quality = currentQuality
	gemInstance.qualityId = currentQualityId
	gemInstance.imbuedSupport = currentImbuedSupport
	gemInstance.corrupted = currentCorrupted
	self:ProcessSocketGroup(socketGroup)

	if errMsg then
		tooltip:AddLine(14, "^1Unable to calculate support replacement delta.")
		return
	end

	local changeCount = self.build:AddStatComparesToTooltip(tooltip, calcBase, upgradedOutput, "^7Stat delta:")
	if changeCount == 0 then
		tooltip:AddLine(14, "^7No measurable stat change for current config.")
	end
end

function SkillsTabClass:AddGemUpgradeReportTooltip(tooltip, reportRow)
	if not reportRow or not reportRow.socketGroup then
		tooltip:Clear()
		return
	end

	if not tooltip:CheckForUpdate(self.build.outputRevision, reportRow) then
		return
	end

	local socketGroup = reportRow.socketGroup
	local gemInstance = socketGroup.gemList and socketGroup.gemList[reportRow.gemIndex]
	if not gemInstance then
		tooltip:AddLine(14, "^1Unable to find gem for this report row.")
		return
	end

	local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator()
	if not calcFunc then
		tooltip:AddLine(14, "^1Unable to calculate upgrade delta.")
		return
	end

	local currentLevel = gemInstance.level
	local currentQuality = gemInstance.quality
	local currentImbuedSupport = gemInstance.imbuedSupport
	gemInstance.level = reportRow.targetLevel or gemInstance.level
	gemInstance.quality = reportRow.targetQuality or gemInstance.quality
	gemInstance.imbuedSupport = reportRow.targetImbuedSupport or gemInstance.imbuedSupport

	local errMsg, upgradedOutput = PCall(calcFunc, nil, reportRow.useFullDPS)

	gemInstance.level = currentLevel
	gemInstance.quality = currentQuality
	gemInstance.imbuedSupport = currentImbuedSupport
	self:ProcessSocketGroup(socketGroup)

	if errMsg then
		tooltip:AddLine(14, "^1Unable to calculate delta for this upgrade.")
		return
	end

	tooltip:AddLine(14, string.format("^7%s  |  ^7%s: %s -> %s", reportRow.name, reportRow.upgradeLabel, tostring(reportRow.level), tostring(reportRow.nextLevel)))
	if reportRow.sourceType == "TRADE" then
		tooltip:AddLine(14, "^7Buys a stronger version of the current gem.")
		if isResolvedGemTradePriceText(reportRow.priceText) then
			tooltip:AddLine(14, string.format("^7Lowest listed price: ^x33FF77%s", reportRow.priceText))
		elseif reportRow.tradePriceError then
			tooltip:AddLine(14, string.format("^7Price status: ^8%s", reportRow.tradePriceError))
		end
		if reportRow.valueSort then
			tooltip:AddLine(14, string.format("^7Stat Value / Price: ^x33FF77%s", reportRow.valueText))
		end
	end
	if reportRow.targetImbuedSupport and data.skills[reportRow.targetImbuedSupport] then
		if reportRow.sourceType == "TRADE" then
			tooltip:AddLine(14, string.format("^7Inherent support: ^x33FF77Level 1 %s", data.skills[reportRow.targetImbuedSupport].name))
		else
			tooltip:AddLine(14, string.format("^7Consumes: ^x33FF77%s", reportRow.upgradeLabel))
			tooltip:AddLine(14, string.format("^7Adds inherent support: ^x33FF77Level 1 %s", data.skills[reportRow.targetImbuedSupport].name))
		end
		tooltip:AddLine(14, "^7Limit: one imbued gem per equipped item.")
	end
	tooltip:AddSeparator(8)
	local changeCount = self.build:AddStatComparesToTooltip(tooltip, calcBase, upgradedOutput, "^7Applying this upgrade will give you:")
	if changeCount == 0 then
		tooltip:AddLine(14, "^7No measurable stat change for current config.")
	end
	if (reportRow.targetQuality or currentQuality) ~= currentQuality then
		tooltip:AddSeparator(8)
		tooltip:AddLine(14, "^7Quality effect reminder:")
		local qualityLineCount = self:AddGemQualitySummaryToTooltip(tooltip, gemInstance, reportRow.targetQuality)
		if qualityLineCount == 0 then
			tooltip:AddLine(14, "^7No quality effect description for this gem.")
		end
		local firstBreakpointQuality = self:FindGemUpgradeQualityBreakpoint(gemInstance, reportRow, calcFunc)
		local sortStatLabel = (self.gemUpgradeSortStat and self.gemUpgradeSortStat.label) or "selected stat"
		if firstBreakpointQuality then
			tooltip:AddSeparator(8)
			tooltip:AddLine(14, string.format("^7First quality breakpoint for %s: ^x33FF77+%d%%", sortStatLabel, firstBreakpointQuality))
		else
			tooltip:AddSeparator(8)
			tooltip:AddLine(14, string.format("^7No quality breakpoint for %s up to ^7+%d%%", sortStatLabel, reportRow.targetQuality or currentQuality))
		end
		self:ProcessSocketGroup(socketGroup)
	end
end

function SkillsTabClass:OpenGemUpgradePopup()
	local controls = { }
	local refreshReport
	local rawReportCacheByStat = { }
	local rawReportCacheRevision = -1
	local deferInitialLoad = true
	self.currentReportBuildSession = (self.currentReportBuildSession or 0) + 1
	local popupSession = self.currentReportBuildSession
	controls.sortLabel = new("LabelControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 24, 0, 16 }, "^7Sort by:")
	controls.sortSelect = new("DropDownControl", { "LEFT", controls.sortLabel, "RIGHT" }, { 8, 0, 220, 20 }, self.gemUpgradeSortStatList, function(index, selected)
		self.gemUpgradeSortStat = selected or self.gemUpgradeSortStat
		if refreshReport and not deferInitialLoad then
			refreshReport(true)
		end
	end)
	controls.impactLabel = new("LabelControl", { "LEFT", controls.sortSelect, "RIGHT" }, { 20, 0, 0, 16 }, "^7Impact:")
	controls.impactSelect = new("DropDownControl", { "LEFT", controls.impactLabel, "RIGHT" }, { 8, 0, 160, 20 }, gemUpgradeImpactFilterList, function(index, selected)
		self.gemUpgradeImpactFilter = selected and selected.value or self.gemUpgradeImpactFilter
		if refreshReport and not deferInitialLoad then
			refreshReport(false)
		end
	end)
	controls.sourceLabel = new("LabelControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 52, 0, 16 }, "^7Method:")
	controls.sourceSelect = new("DropDownControl", { "LEFT", controls.sourceLabel, "RIGHT" }, { 8, 0, 160, 20 }, gemUpgradeSourceFilterList, function(index, selected)
		self.gemUpgradeSourceFilter = selected and selected.value or self.gemUpgradeSourceFilter
		if refreshReport and not deferInitialLoad then
			refreshReport(false)
		end
	end)
	controls.reportStatus = new("LabelControl", { "LEFT", controls.sourceSelect, "RIGHT" }, { 16, 0, 0, 16 }, "^7Loading report...")
	controls.reportList = new("GemUpgradeReportListControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 100, 860, 376 }, function(reportRow, doubleClick)
		if doubleClick then
			self:SelectGemFromUpgradeReport(reportRow, 1)
		end
	end, function(tooltip, reportRow, colIndex)
		if colIndex == 1 then
			self:AddGemUpgradeReportMethodTooltip(tooltip, reportRow)
			return
		elseif colIndex == 2 then
			tooltip:Clear()
			if self:AddGemUpgradeReportCurrentGemTooltip(tooltip, reportRow) then
				return
			end
		elseif colIndex == 3 then
			tooltip:Clear()
			if self:AddGemUpgradeReportCandidateGemTooltip(tooltip, reportRow) then
				return
			end
		elseif colIndex == 4 then
			self:AddGemUpgradeReportDeltaTooltip(tooltip, reportRow)
			return
		elseif colIndex == 5 then
			self:AddGemUpgradeReportImprovementTooltip(tooltip, reportRow)
			return
		end
		self:AddGemUpgradeReportTooltip(tooltip, reportRow)
	end)
	controls.close = new("ButtonControl", { "TOP", controls.reportList, "BOTTOM" }, { 0, 12, 90, 20 }, "Close", function()
		self:StopGemReportBuild()
		main:ClosePopup()
	end)
	refreshReport = function(forceRebuild)
		local selectedStat = controls.sortSelect.list[controls.sortSelect.selIndex] or self.gemUpgradeSortStat or self.gemUpgradeSortStatList[1]
		self.gemUpgradeSortStat = selectedStat
		if rawReportCacheRevision ~= self.build.outputRevision then
			rawReportCacheRevision = self.build.outputRevision
			rawReportCacheByStat = { }
			forceRebuild = true
		end
		local statKey = selectedStat and selectedStat.stat or ""
		local buildEntry = rawReportCacheByStat[statKey]
		if forceRebuild or not buildEntry then
			buildEntry = {
				report = { },
				loading = true,
			}
			rawReportCacheByStat[statKey] = buildEntry
			controls.reportStatus.label = getReportBuildStatusText("Loading report", buildEntry)
			self:StartGemReportBuild(
				popupSession,
				function(buildState)
					buildEntry.report = buildState.report
					return gemUpgradeReport.Build(self, selectedStat, nil, buildState)
				end,
				function(partialReport, buildState)
					if rawReportCacheByStat[statKey] ~= buildEntry or self.currentReportBuildSession ~= popupSession then
						return
					end
					buildEntry.report = partialReport
					buildEntry.loading = true
					buildEntry.completedGroups = buildState.completedGroups
					buildEntry.totalGroups = buildState.totalGroups
					refreshReport(false)
				end,
				function(finalReport, buildState)
					if rawReportCacheByStat[statKey] ~= buildEntry or self.currentReportBuildSession ~= popupSession then
						return
					end
					buildEntry.report = finalReport
					buildEntry.loading = false
					buildEntry.completedGroups = buildState.completedGroups
					buildEntry.totalGroups = buildState.totalGroups
					refreshReport(false)
				end,
				function(errMsg)
					if self.currentReportBuildSession ~= popupSession then
						return
					end
					buildEntry.loading = false
					controls.reportStatus.label = "^1Error: " .. tostring(errMsg)
				end
			)
		end
		local filteredReport = gemUpgradeReport.Filter(buildEntry.report, {
			impact = self.gemUpgradeImpactFilter,
			source = self.gemUpgradeSourceFilter,
		})
		controls.reportList:SetReport(selectedStat, filteredReport)
		if buildEntry.loading then
			controls.reportStatus.label = getReportBuildStatusText("Loading report", buildEntry)
		else
			controls.reportStatus.label = "^7Hover for details, double-click to jump to gem"
		end
	end

	main:OpenPopup(900, 520, "Gem Upgrade Report", controls, nil, nil, "close")
	controls.sortSelect:SelByValue((self.gemUpgradeSortStat and self.gemUpgradeSortStat.stat) or self.sortGemsByDPSField or "CombinedDPS", "stat")
	self.gemUpgradeSortStat = controls.sortSelect.list[controls.sortSelect.selIndex] or self.gemUpgradeSortStatList[1]
	controls.impactSelect:SelByValue(self.gemUpgradeImpactFilter, "value")
	self.gemUpgradeImpactFilter = (controls.impactSelect.list[controls.impactSelect.selIndex] or controls.impactSelect.list[1]).value
	controls.sourceSelect:SelByValue(self.gemUpgradeSourceFilter, "value")
	self.gemUpgradeSourceFilter = (controls.sourceSelect.list[controls.sourceSelect.selIndex] or controls.sourceSelect.list[1]).value
	self:DeferGemReportInit(popupSession, function()
		deferInitialLoad = false
		refreshReport(true)
	end)
end

function SkillsTabClass:OpenGemTradePopup()
	local controls = { }
	local refreshReport
	local rawReportCacheByStat = { }
	local rawReportCacheRevision = -1
	local tradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
	local leagueList = buildGemTradeLeagueList(tradeQuery)
	local deferInitialLoad = true
	self.gemTradePopupSession = (self.gemTradePopupSession or 0) + 1
	local popupSession = self.gemTradePopupSession
	self.gemTradePriceFetchBudget = 0
	self.gemTradePricePendingPrime = false
	controls.sortLabel = new("LabelControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 24, 0, 16 }, "^7Sort by:")
	controls.sortSelect = new("DropDownControl", { "LEFT", controls.sortLabel, "RIGHT" }, { 8, 0, 220, 20 }, self.gemUpgradeSortStatList, function(index, selected)
		self.gemUpgradeSortStat = selected or self.gemUpgradeSortStat
		if refreshReport and not deferInitialLoad then
			self.gemTradePricePendingPrime = false
			refreshReport(true, false)
		end
	end)
	controls.impactLabel = new("LabelControl", { "LEFT", controls.sortSelect, "RIGHT" }, { 20, 0, 0, 16 }, "^7Impact:")
	controls.impactSelect = new("DropDownControl", { "LEFT", controls.impactLabel, "RIGHT" }, { 8, 0, 160, 20 }, gemUpgradeImpactFilterList, function(index, selected)
		self.gemUpgradeImpactFilter = selected and selected.value or self.gemUpgradeImpactFilter
		if refreshReport and not deferInitialLoad then
			self.gemTradePricePendingPrime = false
			refreshReport(false, false)
		end
	end)
	controls.leagueLabel = new("LabelControl", { "LEFT", controls.impactSelect, "RIGHT" }, { 20, 0, 0, 16 }, "^7League:")
	controls.leagueSelect = new("DropDownControl", { "LEFT", controls.leagueLabel, "RIGHT" }, { 8, 0, 200, 20 }, leagueList, function(index, selected)
		self.gemTradeLeague = selected or self.gemTradeLeague
		self.gemTradePricePendingPrime = false
		if refreshReport and not deferInitialLoad then
			refreshReport(false, false)
		end
	end)
	controls.priceStatus = new("LabelControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 52, 0, 16 }, "^7Prices: click Fetch Prices to begin.")
	controls.reportStatus = new("LabelControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 68, 0, 16 }, "^7Loading report...")
	controls.reportList = new("GemTradeReportListControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 100, 860, 376 }, function(reportRow, doubleClick)
		if doubleClick then
			self:SelectGemFromUpgradeReport(reportRow, 1)
		end
	end, function(tooltip, reportRow, colIndex)
		if colIndex == 1 then
			tooltip:Clear()
			if self:AddGemUpgradeReportCurrentGemTooltip(tooltip, reportRow) then
				return
			end
		elseif colIndex == 2 then
			tooltip:Clear()
			if self:AddGemUpgradeReportCandidateGemTooltip(tooltip, reportRow) then
				return
			end
		elseif colIndex == 3 then
			self:AddGemUpgradeReportDeltaTooltip(tooltip, reportRow)
			return
		elseif colIndex == 4 then
			self:AddGemUpgradeReportImprovementTooltip(tooltip, reportRow)
			return
		elseif colIndex == 5 then
			self:AddGemTradePriceTooltip(tooltip, reportRow)
			return
		elseif colIndex == 6 then
			self:AddGemTradeValueTooltip(tooltip, reportRow)
			return
		end
		self:AddGemUpgradeReportTooltip(tooltip, reportRow)
	end)
	controls.close = new("ButtonControl", { "TOP", controls.reportList, "BOTTOM" }, { 0, 12, 90, 20 }, "Close", function()
		self:StopGemReportBuild()
		self:StopGemTradeQueuePump()
		main:ClosePopup()
	end)
	controls.currencyRates = new("ButtonControl", { "RIGHT", controls.close, "LEFT" }, { -8, 0, 220, 20 }, "Get Currency Conversion Rates", function()
		self:FetchGemTradeCurrencyConversion(controls, refreshReport)
	end)
	controls.fetchMore = new("ButtonControl", { "RIGHT", controls.currencyRates, "LEFT" }, { -8, 0, 110, 20 }, "Fetch Prices", function()
		if not controls.fetchMore.hasQueued then
			controls.priceStatus.label = "^7Prices: nothing new to fetch right now."
			return
		end
		self.gemTradePriceFetchBudget = (self.gemTradePriceFetchBudget or 0) + 12
		self.gemTradePricePendingPrime = true
		refreshReport(false, true)
		local currentTradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
		if currentTradeQuery and currentTradeQuery.tradeQueryRequests then
			currentTradeQuery.tradeQueryRequests:ProcessQueue()
		end
	end)
	controls.fetchMore.enabled = function()
		return controls.fetchMore.hasQueued and not controls.fetchMore.reportLoading
	end
	controls.fetchMore.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip.center = true
		tooltip:AddLine(16, "Fetches prices for the next batch of upgrades in the selected league")
	end
	controls.session = new("ButtonControl", { "TOPRIGHT", nil, "TOPRIGHT" }, { -20, 52, 110, 20 }, function()
		return main.POESESSID ~= "" and "^2Session Mode" or colorCodes.WARNING .. "No Session Mode"
	end, function()
		self:OpenGemTradeSessionPopup(refreshReport)
	end)
	controls.session.tooltipText = [[
Enter your POESESSID to enable authenticated trade searches.

Without it, price fetching may fail or return limited results.]]
	controls.trade = new("ButtonControl", { "LEFT", controls.close, "RIGHT" }, { 8, 0, 90, 20 }, "Open Trade", function()
		self:OpenSelectedGemTrade(controls, refreshReport)
	end)
	controls.trade.enabled = function()
		local row = controls.reportList and controls.reportList.selValue
		return row ~= nil
	end
	controls.trade.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip.center = true
		tooltip:AddLine(16, "Opens the official trade site for the selected upgrade")
	end
	refreshReport = function(forceRebuild, primePrices)
		local selectedStat = controls.sortSelect.list[controls.sortSelect.selIndex] or self.gemUpgradeSortStat or self.gemUpgradeSortStatList[1]
		local selectedLeague = controls.leagueSelect and controls.leagueSelect.list[controls.leagueSelect.selIndex] or self.gemTradeLeague or resolveTradeLeague(tradeQuery)
		self.gemUpgradeSortStat = selectedStat
		self.gemTradeLeague = selectedLeague
		if rawReportCacheRevision ~= self.build.outputRevision then
			rawReportCacheRevision = self.build.outputRevision
			rawReportCacheByStat = { }
			forceRebuild = true
		end
		local statKey = selectedStat and selectedStat.stat or ""
		if forceRebuild or not rawReportCacheByStat[statKey] then
			local buildEntry = {
				report = { },
				loading = true,
			}
			rawReportCacheByStat[statKey] = buildEntry
			controls.reportStatus.label = getReportBuildStatusText("Loading report", buildEntry)
			self:StartGemReportBuild(
				popupSession,
				function(buildState)
					buildEntry.report = buildState.report
					return gemTradeReport.Build(self, selectedStat, nil, buildState)
				end,
				function(partialReport, buildState)
					if rawReportCacheByStat[statKey] ~= buildEntry or self.currentReportBuildSession ~= popupSession then
						return
					end
					buildEntry.report = partialReport
					buildEntry.loading = true
					buildEntry.completedGroups = buildState.completedGroups
					buildEntry.totalGroups = buildState.totalGroups
					refreshReport(false, false)
				end,
				function(finalReport, buildState)
					if rawReportCacheByStat[statKey] ~= buildEntry or self.currentReportBuildSession ~= popupSession then
						return
					end
					buildEntry.report = finalReport
					buildEntry.loading = false
					buildEntry.completedGroups = buildState.completedGroups
					buildEntry.totalGroups = buildState.totalGroups
					refreshReport(false, false)
				end,
				function(errMsg)
					if self.currentReportBuildSession ~= popupSession then
						return
					end
					buildEntry.loading = false
					controls.reportStatus.label = "^1Error: " .. tostring(errMsg)
				end
			)
		end
		local buildEntry = rawReportCacheByStat[statKey]
		local filteredReport = gemTradeReport.Filter(buildEntry.report, {
			impact = self.gemUpgradeImpactFilter,
		})
		local imbuedSupportStatIds = self:GetGemTradeImbuedSupportStats()
		if imbuedSupportStatIds then
			local supportedReport = { }
			for _, reportRow in ipairs(filteredReport) do
				if not reportRow.targetImbuedSupport or imbuedSupportStatIds[reportRow.targetImbuedSupport] then
					t_insert(supportedReport, reportRow)
				end
			end
			filteredReport = supportedReport
		end
		for _, reportRow in ipairs(filteredReport) do
			reportRow.tradeLeague = selectedLeague
		end
		self:PrepareGemTradePriceQueue(filteredReport, selectedLeague)
		self:ApplyGemTradePriceCache(filteredReport, selectedLeague)
		controls.reportList:SetReport(selectedStat, filteredReport)
		local displayReport = controls.reportList.list or filteredReport
		controls.fetchMore.reportLoading = buildEntry.loading
		if buildEntry.loading then
			controls.reportStatus.label = getReportBuildStatusText("Loading report", buildEntry)
			controls.priceStatus.label = "^7Prices: report is still loading..."
			controls.fetchMore.hasQueued = false
		else
			controls.reportStatus.label = "^7Hover for details, double-click to jump to gem"
			self:UpdateGemTradePriceStatus(controls, displayReport)
		end
		self:UpdateGemTradeCurrencyConversionButton(controls)
		if primePrices and not buildEntry.loading then
			self:PrimeGemTradePrices(displayReport, controls, refreshReport, selectedLeague)
		end
	end

	main:OpenPopup(900, 520, "Gem Trade Report", controls, nil, nil, "close")
	self.currentReportBuildSession = popupSession
	self:StartGemTradeQueuePump(popupSession)
	controls.sortSelect:SelByValue((self.gemUpgradeSortStat and self.gemUpgradeSortStat.stat) or self.sortGemsByDPSField or "CombinedDPS", "stat")
	self.gemUpgradeSortStat = controls.sortSelect.list[controls.sortSelect.selIndex] or self.gemUpgradeSortStatList[1]
	controls.impactSelect:SelByValue(self.gemUpgradeImpactFilter, "value")
	self.gemUpgradeImpactFilter = (controls.impactSelect.list[controls.impactSelect.selIndex] or controls.impactSelect.list[1]).value
	syncGemTradeLeagueSelection(self, controls, tradeQuery, self.gemTradeLeague)
	self:EnsureGemTradeLeagueList(controls, refreshReport)
	self:UpdateGemTradeCurrencyConversionButton(controls)
	self:DeferGemReportInit(popupSession, function()
		deferInitialLoad = false
		refreshReport(true, false)
	end)
end

function SkillsTabClass:OpenSupportReplacementPopup()
	local controls = { }
	local refreshReport
	local rawReportCacheByStat = { }
	local rawReportCacheRevision = -1
	local deferInitialLoad = true
	self.gemTradePopupSession = (self.gemTradePopupSession or 0) + 1
	local popupSession = self.gemTradePopupSession
	local tradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
	local leagueList = buildGemTradeLeagueList(tradeQuery)
	self.gemTradePriceFetchBudget = 0
	self.gemTradePricePendingPrime = false

	controls.sortLabel = new("LabelControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 24, 0, 16 }, "^7Sort by:")
	controls.sortSelect = new("DropDownControl", { "LEFT", controls.sortLabel, "RIGHT" }, { 8, 0, 220, 20 }, self.gemUpgradeSortStatList, function(index, selected)
		self.gemUpgradeSortStat = selected or self.gemUpgradeSortStat
		if refreshReport and not deferInitialLoad then
			self.gemTradePricePendingPrime = false
			refreshReport(true, false)
		end
	end)
	controls.impactLabel = new("LabelControl", { "LEFT", controls.sortSelect, "RIGHT" }, { 20, 0, 0, 16 }, "^7Impact:")
	controls.impactSelect = new("DropDownControl", { "LEFT", controls.impactLabel, "RIGHT" }, { 8, 0, 160, 20 }, gemUpgradeImpactFilterList, function(index, selected)
		self.gemUpgradeImpactFilter = selected and selected.value or self.gemUpgradeImpactFilter
		if refreshReport and not deferInitialLoad then
			self.gemTradePricePendingPrime = false
			refreshReport(false, false)
		end
	end)
	controls.leagueLabel = new("LabelControl", { "LEFT", controls.impactSelect, "RIGHT" }, { 20, 0, 0, 16 }, "^7League:")
	controls.leagueSelect = new("DropDownControl", { "LEFT", controls.leagueLabel, "RIGHT" }, { 8, 0, 200, 20 }, leagueList, function(index, selected)
		self.gemTradeLeague = selected or self.gemTradeLeague
		self.gemTradePricePendingPrime = false
		if refreshReport and not deferInitialLoad then
			refreshReport(false, false)
		end
	end)
	controls.priceStatus = new("LabelControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 52, 0, 16 }, "^7Prices: click Fetch Prices to begin.")
	controls.reportStatus = new("LabelControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 68, 0, 16 }, "^7Loading report...")
	controls.reportList = new("SupportReplacementReportListControl", { "TOPLEFT", nil, "TOPLEFT" }, { 20, 100, 860, 376 }, function(reportRow, doubleClick)
		if doubleClick then
			self:SelectGemFromUpgradeReport(reportRow, 1)
		end
	end, function(tooltip, reportRow, colIndex)
		if colIndex == 1 then
			self:AddSupportReplacementSkillTooltip(tooltip, reportRow)
			return
		elseif colIndex == 2 then
			if self:AddSupportReplacementCurrentTooltip(tooltip, reportRow) then
				return
			end
		elseif colIndex == 3 then
			if self:AddSupportReplacementCandidateTooltip(tooltip, reportRow) then
				return
			end
		elseif colIndex == 4 then
			self:AddSupportReplacementDeltaTooltip(tooltip, reportRow)
			return
		elseif colIndex == 5 then
			self:AddGemUpgradeReportImprovementTooltip(tooltip, reportRow)
			return
		elseif colIndex == 6 then
			self:AddGemTradePriceTooltip(tooltip, reportRow)
			return
		elseif colIndex == 7 then
			self:AddGemTradeValueTooltip(tooltip, reportRow)
			return
		end
	end)
	controls.close = new("ButtonControl", { "TOP", controls.reportList, "BOTTOM" }, { 0, 12, 90, 20 }, "Close", function()
		self:StopGemReportBuild()
		self:StopGemTradeQueuePump()
		main:ClosePopup()
	end)
	controls.currencyRates = new("ButtonControl", { "RIGHT", controls.close, "LEFT" }, { -8, 0, 220, 20 }, "Get Currency Conversion Rates", function()
		self:FetchGemTradeCurrencyConversion(controls, refreshReport)
	end)
	controls.fetchMore = new("ButtonControl", { "RIGHT", controls.currencyRates, "LEFT" }, { -8, 0, 110, 20 }, "Fetch Prices", function()
		if not controls.fetchMore.hasQueued then
			controls.priceStatus.label = "^7Prices: nothing new to fetch right now."
			return
		end
		self.gemTradePriceFetchBudget = (self.gemTradePriceFetchBudget or 0) + 12
		self.gemTradePricePendingPrime = true
		refreshReport(false, true)
		local currentTradeQuery = self.build and self.build.itemsTab and self.build.itemsTab.tradeQuery
		if currentTradeQuery and currentTradeQuery.tradeQueryRequests then
			currentTradeQuery.tradeQueryRequests:ProcessQueue()
		end
	end)
	controls.fetchMore.enabled = function()
		return controls.fetchMore.hasQueued and not controls.fetchMore.reportLoading
	end
	controls.fetchMore.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip.center = true
		tooltip:AddLine(16, "Fetches prices for the next batch of support replacements in the selected league")
	end
	controls.session = new("ButtonControl", { "TOPRIGHT", nil, "TOPRIGHT" }, { -20, 52, 110, 20 }, function()
		return main.POESESSID ~= "" and "^2Session Mode" or colorCodes.WARNING .. "No Session Mode"
	end, function()
		self:OpenGemTradeSessionPopup(refreshReport)
	end)
	controls.session.tooltipText = [[
Enter your POESESSID to enable authenticated trade searches.

Without it, price fetching may fail or return limited results.]]
	controls.trade = new("ButtonControl", { "LEFT", controls.close, "RIGHT" }, { 8, 0, 90, 20 }, "Open Trade", function()
		self:OpenSelectedGemTrade(controls, refreshReport)
	end)
	controls.trade.enabled = function()
		local row = controls.reportList and controls.reportList.selValue
		return row ~= nil and canPriceGemTradeRow(row)
	end
	controls.trade.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip.center = true
		tooltip:AddLine(16, "Opens the official trade site for the selected support candidate")
	end

	refreshReport = function(forceRebuild, primePrices)
		local selectedStat = controls.sortSelect.list[controls.sortSelect.selIndex] or self.gemUpgradeSortStat or self.gemUpgradeSortStatList[1]
		local selectedLeague = controls.leagueSelect and controls.leagueSelect.list[controls.leagueSelect.selIndex] or self.gemTradeLeague or resolveTradeLeague(tradeQuery)
		self.gemUpgradeSortStat = selectedStat
		self.gemTradeLeague = selectedLeague
		if rawReportCacheRevision ~= self.build.outputRevision then
			rawReportCacheRevision = self.build.outputRevision
			rawReportCacheByStat = { }
			forceRebuild = true
		end
		local statKey = selectedStat and selectedStat.stat or ""
		if forceRebuild or not rawReportCacheByStat[statKey] then
			local buildEntry = {
				report = { },
				loading = true,
			}
			rawReportCacheByStat[statKey] = buildEntry
			controls.reportStatus.label = getReportBuildStatusText("Loading report", buildEntry)
			self:StartGemReportBuild(
				popupSession,
				function(buildState)
					buildEntry.report = buildState.report
					return supportReplacementReport.Build(self, selectedStat, nil, buildState)
				end,
				function(partialReport, buildState)
					if rawReportCacheByStat[statKey] ~= buildEntry or self.currentReportBuildSession ~= popupSession then
						return
					end
					buildEntry.report = partialReport
					buildEntry.loading = true
					buildEntry.completedGroups = buildState.completedGroups
					buildEntry.totalGroups = buildState.totalGroups
					refreshReport(false, false)
				end,
				function(finalReport, buildState)
					if rawReportCacheByStat[statKey] ~= buildEntry or self.currentReportBuildSession ~= popupSession then
						return
					end
					buildEntry.report = finalReport
					buildEntry.loading = false
					buildEntry.completedGroups = buildState.completedGroups
					buildEntry.totalGroups = buildState.totalGroups
					refreshReport(false, false)
				end,
				function(errMsg)
					if self.currentReportBuildSession ~= popupSession then
						return
					end
					buildEntry.loading = false
					controls.reportStatus.label = "^1Error: " .. tostring(errMsg)
				end
			)
		end
		local buildEntry = rawReportCacheByStat[statKey]
		local filteredReport = supportReplacementReport.Filter(buildEntry.report, {
			impact = self.gemUpgradeImpactFilter,
		})
		for _, reportRow in ipairs(filteredReport) do
			reportRow.tradeLeague = selectedLeague
		end
		self:PrepareGemTradePriceQueue(filteredReport, selectedLeague)
		self:ApplyGemTradePriceCache(filteredReport, selectedLeague)
		controls.reportList:SetReport(selectedStat, filteredReport)
		local displayReport = controls.reportList.list or filteredReport
		controls.fetchMore.reportLoading = buildEntry.loading
		if buildEntry.loading then
			controls.reportStatus.label = getReportBuildStatusText("Loading report", buildEntry)
			controls.priceStatus.label = "^7Prices: report is still loading..."
			controls.fetchMore.hasQueued = false
		else
			controls.reportStatus.label = "^7Hover for details, double-click to jump to gem"
			self:UpdateGemTradePriceStatus(controls, displayReport)
		end
		self:UpdateGemTradeCurrencyConversionButton(controls)
		if primePrices and not buildEntry.loading then
			self:PrimeGemTradePrices(displayReport, controls, refreshReport, selectedLeague)
		end
	end

	main:OpenPopup(900, 520, "Support Replacement Report", controls, nil, nil, "close")
	self.currentReportBuildSession = popupSession
	self:StartGemTradeQueuePump(popupSession)
	controls.sortSelect:SelByValue((self.gemUpgradeSortStat and self.gemUpgradeSortStat.stat) or self.sortGemsByDPSField or "CombinedDPS", "stat")
	self.gemUpgradeSortStat = controls.sortSelect.list[controls.sortSelect.selIndex] or self.gemUpgradeSortStatList[1]
	controls.impactSelect:SelByValue(self.gemUpgradeImpactFilter, "value")
	self.gemUpgradeImpactFilter = (controls.impactSelect.list[controls.impactSelect.selIndex] or controls.impactSelect.list[1]).value
	syncGemTradeLeagueSelection(self, controls, tradeQuery, self.gemTradeLeague)
	self:EnsureGemTradeLeagueList(controls, refreshReport)
	self:UpdateGemTradeCurrencyConversionButton(controls)
	self:DeferGemReportInit(popupSession, function()
		deferInitialLoad = false
		refreshReport(true, false)
	end)
end

function SkillsTabClass:CopySocketGroup(socketGroup)
	local skillText = ""
	if socketGroup.label and socketGroup.label:match("%S") then
		skillText = skillText .. "Label: " .. socketGroup.label .. "\r\n"
	end
	if socketGroup.slot then
		skillText = skillText .. "Slot: " .. socketGroup.slot .. "\r\n"
	end
	for _, gemInstance in ipairs(socketGroup.gemList) do
		skillText = skillText .. string.format("%s %d/%d %s %d\r\n", gemInstance.nameSpec, gemInstance.level, gemInstance.quality, gemInstance.enabled and "" or "DISABLED", gemInstance.count or 1)
	end
	Copy(skillText)
end

function SkillsTabClass:PasteSocketGroup(testInput)
	local skillText = sanitiseText(Paste() or testInput)
	if skillText then
		local newGroup = { label = "", enabled = true, gemList = { } }
		local label = skillText:match("Label: (%C+)")
		if label then
			newGroup.label = label
		end
		local slot = skillText:match("Slot: (%C+)")
		if slot then
			newGroup.slot = slot
		end
		for nameSpec, level, quality, state, count in skillText:gmatch("([ %a']+) (%d+)/(%d+) ?(%a*) (%d+)") do
			t_insert(newGroup.gemList, {
				nameSpec = nameSpec,
				level = tonumber(level) or 20,
				quality = tonumber(quality) or 0,
				enabled = state ~= "DISABLED",
				count = tonumber(count) or 1,
				enableGlobal1 = true,
				enableGlobal2 = true
			})
		end
		if #newGroup.gemList > 0 then
			t_insert(self.socketGroupList, newGroup)
			self.controls.groupList.selIndex = #self.socketGroupList
			self.controls.groupList.selValue = newGroup
			self:SetDisplayGroup(newGroup)
			self:AddUndoState()
			self.build.buildFlag = true
		end
	end
end

-- Create the controls for editing the gem at a given index
function SkillsTabClass:CreateGemSlot(index)
	local slot = { }
	self.gemSlots[index] = slot

	-- Delete gem
	slot.delete = new("ButtonControl", nil, {0, 0, 20, 20}, "x", function()
		t_remove(self.displayGroup.gemList, index)
		for index2 = index, #self.displayGroup.gemList do
			-- Update the other gem slot controls
			local gemInstance = self.displayGroup.gemList[index2]
			self.gemSlots[index2].nameSpec:SetText(gemInstance.nameSpec)
			self.gemSlots[index2].level:SetText(gemInstance.level)
			self.gemSlots[index2].quality:SetText(gemInstance.quality)
			self.gemSlots[index2].enabled.state = gemInstance.enabled
			self.gemSlots[index2].enableGlobal1.state = gemInstance.enableGlobal1
			self.gemSlots[index2].enableGlobal2.state = gemInstance.enableGlobal2
			self.gemSlots[index2].count:SetText(gemInstance.count or 1)
		end
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	if index == 1 then
		slot.delete:SetAnchor("TOPLEFT", self.anchorGemSlots, "TOPLEFT", 0, 0)
	else
		local prevSlot = self.gemSlots[index-1]
		slot.delete:SetAnchor("TOPLEFT", prevSlot.delete, "BOTTOMLEFT", 0, function()
			return (prevSlot.enableGlobal1:IsShown() or prevSlot.enableGlobal2:IsShown()) and 24 or 2
		end)
	end
	slot.delete.shown = function()
		return index <= #self.displayGroup.gemList + 1 and self.displayGroup.source == nil
	end
	slot.delete.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	slot.delete.tooltipText = "Remove this gem."
	self.controls["gemSlot"..index.."Delete"] = slot.delete

	-- Gem name specification
	slot.nameSpec = new("GemSelectControl", { "LEFT", slot.delete, "RIGHT" }, { 2, 0, 300, 20 }, self, index, function(gemId, addUndo)
		if not self.displayGroup then
			return
		end
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			if not gemId then
				return
			end
			gemInstance = {
				nameSpec = "",
				level = 1,
				quality = self.defaultGemQuality or 0,
				enabled = true,
				enableGlobal1 = true,
				enableGlobal2 = true,
				count = 1,
				new = true
			}
			self.displayGroup.gemList[index] = gemInstance
			slot.level:SetText(gemInstance.level)
			slot.quality:SetText(gemInstance.quality)
			slot.enabled.state = true
			slot.enableGlobal1.state = true
			slot.enableGlobal2.state = true
			slot.count:SetText(gemInstance.count)
		elseif gemId == gemInstance.gemId then
			if addUndo then
				self:AddUndoState()
			end
			return
		end
		gemInstance.gemId = gemId
		gemInstance.skillId = nil
		self:ProcessSocketGroup(self.displayGroup)
		-- New gems need to be constrained by ProcessGemLevel
		gemInstance.level = self:ProcessGemLevel(gemInstance.gemData)
		gemInstance.naturalMaxLevel = gemInstance.level
		slot.level:SetText(gemInstance.level)
		slot.count:SetText(gemInstance.count or 1)
		if addUndo then
			self:AddUndoState()
		end
		self.build.buildFlag = true
	end, true)
	slot.nameSpec:AddToTabGroup(self.controls.groupLabel)
	self.controls["gemSlot"..index.."Name"] = slot.nameSpec

	-- Gem level
	slot.level = new("EditControl", { "LEFT", slot.nameSpec, "RIGHT" }, { 2, 0, 60, 20 }, nil, nil, "%D", 2, function(buf)
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			gemInstance = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true, enableGlobal1 = true, enableGlobal2 = true, count = 1, new = true }
			self.displayGroup.gemList[index] = gemInstance
			slot.quality:SetText(gemInstance.quality)
			slot.enabled.state = true
			slot.enableGlobal1.state = true
			slot.count:SetText(gemInstance.count)
		end
		gemInstance.level = tonumber(buf) or self.displayGroup.gemList[index].naturalMaxLevel or self:ProcessGemLevel(gemInstance.gemData) or 20
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.level:AddToTabGroup(self.controls.groupLabel)
	slot.level.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	self.controls["gemSlot"..index.."Level"] = slot.level

	-- Gem quality
	slot.quality = new("EditControl", {"LEFT",slot.level,"RIGHT"}, {2, 0, 60, 20}, nil, nil, "%D", 2, function(buf)
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			gemInstance = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true, enableGlobal1 = true, enableGlobal2 = true, count = 1, new = true }
			self.displayGroup.gemList[index] = gemInstance
			slot.level:SetText(gemInstance.level)
			slot.enabled.state = true
			slot.enableGlobal1.state = true
			slot.count:SetText(gemInstance.count)
		end
		gemInstance.quality = tonumber(buf) or self.defaultGemQuality or 0
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.quality.tooltipFunc = function(tooltip)
		if tooltip:CheckForUpdate(self.build.outputRevision, self.displayGroup) then
			-- Get the gem instance from the skills
			local gemInstance = self.displayGroup.gemList[index]
			if not gemInstance then
				return
			end
			local gemData = gemInstance.gemData

			-- Function for both granted effect and secondary such as vaal
			local addQualityLines = function(qualityList, grantedEffect)
				tooltip:AddLine(18, colorCodes.GEM..grantedEffect.name)
				-- Hardcoded to use 20% quality instead of grabbing from gem, this is for consistency and so we always show something
				tooltip:AddLine(16, colorCodes.NORMAL.."At +20% Quality:")
				for k, qual in pairs(qualityList) do
					-- Do the stats one at a time because we're not guaranteed to get the descriptions in the same order we look at them here
					local stats = { }
					stats[qual[1]] = qual[2] * 20
					local descriptions = self.build.data.describeStats(stats, grantedEffect.statDescriptionScope)
					-- line may be nil if the value results in no line due to not being enough quality
					for _, line in ipairs(descriptions) do
						if line then
							-- Check if we have a handler for the mod in the gem's statMap or in the shared stat map for skills
							if grantedEffect.statMap[qual[1]] or self.build.data.skillStatMap[qual[1]] then
								tooltip:AddLine(16, colorCodes.MAGIC..line)
							else
								local line = colorCodes.UNSUPPORTED..line
								line = main.notSupportedModTooltips and (line .. main.notSupportedTooltipText) or line
								tooltip:AddLine(16, line)
							end
						end
					end
				end
			end
			-- Check if there is quality for the effect
			if gemData and gemData.grantedEffect and gemData.grantedEffect.qualityStats then
				local qualityTable = gemData.grantedEffect.qualityStats
				if qualityTable[1] then
					addQualityLines(qualityTable, gemData.grantedEffect)
					tooltip:AddSeparator(10)
				end
			end
			if gemData and gemData.secondaryGrantedEffect and gemData.secondaryGrantedEffect.qualityStats then
				local qualityTable = gemData.secondaryGrantedEffect.qualityStats
				if qualityTable[1] then
					addQualityLines(qualityTable, gemData.secondaryGrantedEffect)
					tooltip:AddSeparator(10)
				end
			end

			local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator(self.build)
			if calcFunc then
				local storedQuality = self.displayGroup.gemList[index].quality
				self.displayGroup.gemList[index].quality = 20
				local output = calcFunc()
				self.displayGroup.gemList[index].quality = storedQuality
				self.build:AddStatComparesToTooltip(tooltip, calcBase, output, "^7Setting to 20 quality will give you:")
			end
		end
	end
	slot.quality:AddToTabGroup(self.controls.groupLabel)
	slot.quality.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	self.controls["gemSlot"..index.."Quality"] = slot.quality

	-- Enable gem
	slot.enabled = new("CheckBoxControl", {"LEFT",slot.quality,"RIGHT"}, {18, 0, 20}, nil, function(state)
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			gemInstance = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true, enableGlobal1 = true, enableGlobal2 = true, count = 1, new = true }
			self.displayGroup.gemList[index] = gemInstance
			slot.level:SetText(gemInstance.level)
			slot.quality:SetText(gemInstance.quality)
			slot.count:SetText(gemInstance.count)
		end
		if not gemInstance.gemData.vaalGem then
			slot.enableGlobal1.state = true
			gemInstance.enableGlobal1 = true
			slot.enableGlobal2.state = true
			gemInstance.enableGlobal2 = true
		end
		gemInstance.enabled = state
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.enabled.tooltipFunc = function(tooltip)
		if tooltip:CheckForUpdate(self.build.outputRevision, self.displayGroup) then
			if self.displayGroup.gemList[index] then
				local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator(self.build)
				if calcFunc then
					self.displayGroup.gemList[index].enabled = not self.displayGroup.gemList[index].enabled
					local output = calcFunc()
					self.displayGroup.gemList[index].enabled = not self.displayGroup.gemList[index].enabled
					self.build:AddStatComparesToTooltip(tooltip, calcBase, output, self.displayGroup.gemList[index].enabled and "^7Disabling this gem will give you:" or "^7Enabling this gem will give you:")
				end
			end
		end
	end
	slot.enabled.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	self.controls["gemSlot"..index.."Enable"] = slot.enabled

	-- Count gem
	slot.count = new("EditControl", {"LEFT",slot.enabled,"RIGHT"}, {18, 0, 60, 20}, nil, nil, "%D", 2, function(buf)
		local gemInstance = self.displayGroup.gemList[index]
		if not gemInstance then
			gemInstance = { nameSpec = "", level = self.defaultGemLevel or 20, quality = self.defaultGemQuality or 0, enabled = true, enableGlobal1 = true, count = 1, new = true }
			self.displayGroup.gemList[index] = gemInstance
			slot.level:SetText(gemInstance.level)
			slot.quality:SetText(gemInstance.quality)
			slot.enabled.state = true
			slot.enableGlobal1.state = true
		end
		gemInstance.count = tonumber(buf) or 1
		slot.count.buf = tostring(gemInstance.count)
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.count.shown = function()
		local gemInstance = self.displayGroup and self.displayGroup.gemList[index]
		if gemInstance then
			local grantedEffectList = gemInstance.gemData and gemInstance.gemData.grantedEffectList or { gemInstance.grantedEffect }
			for index, grantedEffect in ipairs(grantedEffectList) do
				if not grantedEffect.support and not grantedEffect.unsupported and (not grantedEffect.hasGlobalEffect or gemInstance["enableGlobal"..index]) then
					return true
				end
			end
		end
		return false
	end
	slot.count.tooltipFunc = function(tooltip)
		if tooltip:CheckForUpdate(self.build.outputRevision, self.displayGroup) then
			tooltip:AddLine(16, "^8Note: `count` integer value scales the DPS of associated skill by a scalar.")
			tooltip:AddLine(16, "^8To be used with totems, minions, shot-gunning of projectiles (e.g., VD, magma-orbs),")
			tooltip:AddLine(16, "^8multi-hit projectiles (e.g. ball-lightning), traps, mines.")
		end
	end
	slot.count.enabled = function()
		return index <= #self.displayGroup.gemList
	end
	self.controls["gemSlot"..index.."Count"] = slot.count

	-- Parser/calculator error message
	slot.errMsg = new("LabelControl", {"LEFT",slot.count,"RIGHT"}, {2, 2, 0, 16}, function()
		local gemInstance = self.displayGroup and self.displayGroup.gemList[index]
		return "^1"..(gemInstance and gemInstance.errMsg or "")
	end)
	self.controls["gemSlot"..index.."ErrMsg"] = slot.errMsg

	-- Enable global-effect skill 1
	slot.enableGlobal1 = new("CheckBoxControl", {"TOPLEFT",slot.delete,"BOTTOMLEFT"}, {0, 2, 20}, "", function(state)
		local gemInstance = self.displayGroup.gemList[index]
		gemInstance.enableGlobal1 = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.enableGlobal1.shown = function()
		local gemInstance = self.displayGroup and self.displayGroup.gemList[index]
		return gemInstance and gemInstance.gemData and gemInstance.gemData.vaalGem and gemInstance.gemData.grantedEffectList[1] and not gemInstance.gemData.grantedEffectList[1].support
	end
	slot.enableGlobal1.x = function()
		return self:IsShown() and (DrawStringWidth(16, "VAR", slot.enableGlobal1:GetProperty("label")) + 5) or 0
	end
	slot.enableGlobal1.label = function()
		return "Enable "..self.displayGroup.gemList[index].gemData.grantedEffectList[1].name..":"
	end
	self.controls["gemSlot"..index.."EnableGlobal1"] = slot.enableGlobal1

	-- Enable global-effect skill 2
	slot.enableGlobal2 = new("CheckBoxControl", {"LEFT",slot.enableGlobal1,"RIGHT",true}, {0, 0, 20}, "", function(state)
		local gemInstance = self.displayGroup.gemList[index]
		gemInstance.enableGlobal2 = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	slot.enableGlobal2.shown = function()
		local gemInstance = self.displayGroup and self.displayGroup.gemList[index]
		return gemInstance and gemInstance.gemData and gemInstance.gemData.vaalGem and gemInstance.gemData.grantedEffectList[2] and not gemInstance.gemData.grantedEffectList[2].support
	end
	slot.enableGlobal2.x = function()
		return self:IsShown() and (DrawStringWidth(16, "VAR", slot.enableGlobal2:GetProperty("label")) + 12) or 0
	end
	slot.enableGlobal2.label = function()
		return "Enable "..self.displayGroup.gemList[index].gemData.grantedEffectList[2].name..":"
	end
	self.controls["gemSlot"..index.."EnableGlobal2"] = slot.enableGlobal2
end

-- Update the gem slot controls to reflect the currently displayed socket group
function SkillsTabClass:UpdateGemSlots()
	if not self.displayGroup then
		return
	end
	for slotIndex = 1, #self.displayGroup.gemList + 1 do
		if not self.gemSlots[slotIndex] then
			self:CreateGemSlot(slotIndex)
		end
		local slot = self.gemSlots[slotIndex]
		if slotIndex == #self.displayGroup.gemList + 1 then
			slot.nameSpec:SetText("")
			slot.level:SetText("")
			slot.quality:SetText("")
			slot.enabled.state = false
			slot.count:SetText(1)
		else
			slot.nameSpec.inactiveCol = self.displayGroup.gemList[slotIndex].color
		end
	end
end

-- Find the skill gem matching the given specification
function SkillsTabClass:FindSkillGem(nameSpec)
	-- Search for gem name using increasingly broad search patterns
	local patternList = {
		"^ "..nameSpec:gsub("%a", function(a) return "["..a:upper()..a:lower().."]" end).."$", -- Exact match (case-insensitive)
		"^"..nameSpec:gsub("%a", " %0%%l+").."$", -- Simple abbreviation ("CtF" -> "Cold to Fire")
		"^ "..nameSpec:gsub(" ",""):gsub("%l", "%%l*%0").."%l+$", -- Abbreviated words ("CldFr" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", ".*%0"), -- Global abbreviation ("CtoF" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", function(a) return ".*".."["..a:upper()..a:lower().."]" end), -- Case insensitive global abbreviation ("ctof" -> "Cold to Fire")
	}
	for i, pattern in ipairs(patternList) do
		local foundGemData
		for gemId, gemData in pairs(self.build.data.gems) do
			if (" "..gemData.name):match(pattern) then
				if foundGemData then
					return "Ambiguous gem name '" .. nameSpec .. "': matches '" .. foundGemData.name .. "', '" .. gemData.name .. "'"
				end
				foundGemData = gemData
			end
		end
		if foundGemData then
			return nil, foundGemData
		end
	end
	return "Unrecognised gem name '" .. nameSpec .. "'"
end

function SkillsTabClass:ProcessGemLevel(gemData, imbued)
	local grantedEffect = gemData.grantedEffect
	local naturalMaxLevel = gemData.naturalMaxLevel
	if imbued or self.defaultGemLevel == "levelOne" then
		return 1
	elseif self.defaultGemLevel == "awakenedMaximum" then
		return naturalMaxLevel + 1
	elseif self.defaultGemLevel == "corruptedMaximum" then
		if grantedEffect.plusVersionOf then
			return naturalMaxLevel
		else
			return naturalMaxLevel + 1
		end
	elseif self.defaultGemLevel == "normalMaximum" then
		return naturalMaxLevel
	else -- self.defaultGemLevel == "characterLevel"
		local maxGemLevel = naturalMaxLevel
		if not grantedEffect.levels[maxGemLevel] then
			maxGemLevel = #grantedEffect.levels
		end
		local characterLevel = self.build and self.build.characterLevel or 1
		for gemLevel = maxGemLevel, 1, -1 do
			if grantedEffect.levels[gemLevel].levelRequirement <= characterLevel then
				return gemLevel
			end
		end
		return 1
	end
end

-- Processes the given socket group, filling in information that will be used for display or calculations
function SkillsTabClass:ProcessSocketGroup(socketGroup)
	-- Loop through the skill gem list
	local data = self.build.data
	for _, gemInstance in ipairs(socketGroup.gemList) do
		gemInstance.color = "^8"
		gemInstance.nameSpec = gemInstance.nameSpec or ""
		local prevDefaultLevel = gemInstance.gemData and gemInstance.gemData.naturalMaxLevel or (gemInstance.new and 20)
		gemInstance.gemData, gemInstance.grantedEffect = nil
		if gemInstance.gemId then
			-- Specified by gem ID
			-- Used for skills granted by skill gems
			gemInstance.errMsg = nil
			gemInstance.gemData = data.gems[gemInstance.gemId]
			if gemInstance.gemData then
				gemInstance.nameSpec = gemInstance.gemData.name
				gemInstance.skillId = gemInstance.gemData.grantedEffectId
			end
		elseif gemInstance.skillId then
			-- Specified by skill ID
			-- Used for skills granted by items
			gemInstance.errMsg = nil
			local gemId = data.gemForSkill[gemInstance.skillId]
			if gemId then
				gemInstance.gemData = data.gems[gemId]
			else
				gemInstance.grantedEffect = data.skills[gemInstance.skillId]
			end
			if gemInstance.triggered then
				if gemInstance.grantedEffect.levels[gemInstance.level] then
					gemInstance.grantedEffect.levels[gemInstance.level].cost = {}
				end
			end
		elseif gemInstance.nameSpec:match("%S") then
			-- Specified by gem/skill name, try to match it
			-- Used to migrate pre-1.4.20 builds
			gemInstance.errMsg, gemInstance.gemData = self:FindSkillGem(gemInstance.nameSpec)
			gemInstance.gemId = gemInstance.gemData and gemInstance.gemData.id
			gemInstance.skillId = gemInstance.gemData and gemInstance.gemData.grantedEffectId
			if gemInstance.gemData then
				gemInstance.nameSpec = gemInstance.gemData.name
			end
		else
			gemInstance.errMsg, gemInstance.gemData, gemInstance.skillId = nil
		end
		if gemInstance.gemData and gemInstance.gemData.grantedEffect.unsupported then
			gemInstance.errMsg = gemInstance.nameSpec .. " is not supported yet"
			gemInstance.gemData = nil
		end
		if gemInstance.gemData or gemInstance.grantedEffect then
			gemInstance.new = nil
			local grantedEffect = gemInstance.grantedEffect or gemInstance.gemData.grantedEffect
			if grantedEffect.color == 1 then
				gemInstance.color = colorCodes.STRENGTH
			elseif grantedEffect.color == 2 then
				gemInstance.color = colorCodes.DEXTERITY
			elseif grantedEffect.color == 3 then
				gemInstance.color = colorCodes.INTELLIGENCE
			else
				gemInstance.color = colorCodes.NORMAL
			end
			if prevDefaultLevel and gemInstance.gemData and gemInstance.gemData.naturalMaxLevel ~= prevDefaultLevel then
				gemInstance.level = gemInstance.gemData.naturalMaxLevel
				gemInstance.naturalMaxLevel = gemInstance.level
			end
			calcLib.validateGemLevel(gemInstance)
			if gemInstance.gemData then
				gemInstance.reqLevel = grantedEffect.levels[gemInstance.level].levelRequirement
				gemInstance.reqStr = calcLib.getGemStatRequirement(gemInstance.reqLevel, grantedEffect.support, gemInstance.gemData.reqStr)
				gemInstance.reqDex = calcLib.getGemStatRequirement(gemInstance.reqLevel, grantedEffect.support, gemInstance.gemData.reqDex)
				gemInstance.reqInt = calcLib.getGemStatRequirement(gemInstance.reqLevel, grantedEffect.support, gemInstance.gemData.reqInt)
			end
		end
	end
end

-- Set the skill to be displayed/edited
function SkillsTabClass:SetDisplayGroup(socketGroup)
	self.displayGroup = socketGroup
	if socketGroup then
		self:ProcessSocketGroup(socketGroup)

		-- Update the main controls
		self.controls.groupLabel:SetText(socketGroup.label)
		self.controls.groupSlot:SelByValue(socketGroup.slot, "slotName")
		self.controls.groupEnabled.state = socketGroup.enabled
		self.controls.includeInFullDPS.state = socketGroup.includeInFullDPS and socketGroup.enabled
		self.controls.groupCount:SetText(socketGroup.groupCount or 1)
		if socketGroup.imbuedSupport then
			local gemId = data.gems[data.gemForBaseName[socketGroup.imbuedSupport:lower().." support"]]
			self.controls.imbuedSupport.gemId = gemId
			self.controls.imbuedSupport:SetText(socketGroup.imbuedSupport)
			self.controls.imbuedSupport.inactiveCol = data.skillColorMap[gemId.grantedEffect.color]
		else
			self.controls.imbuedSupport.gemId = nil
			self.controls.imbuedSupport:SetText("")
		end

		-- Update the gem slot controls
		self:UpdateGemSlots()
		for index, gemInstance in pairs(socketGroup.gemList) do
			self.gemSlots[index].nameSpec:SetText(gemInstance.nameSpec)
			self.gemSlots[index].level:SetText(gemInstance.level)
			self.gemSlots[index].quality:SetText(gemInstance.quality)
			self.gemSlots[index].enabled.state = gemInstance.enabled
			self.gemSlots[index].enableGlobal1.state = gemInstance.enableGlobal1
			self.gemSlots[index].enableGlobal2.state = gemInstance.enableGlobal2
			self.gemSlots[index].count:SetText(gemInstance.count or 1)
		end
	end
end

function SkillsTabClass:AddSocketGroupTooltip(tooltip, socketGroup)
	if socketGroup.explodeSources then
		for _, source in ipairs(socketGroup.explodeSources) do
			tooltip:AddLine(18, "^7Source: " .. colorCodes[source.rarity or "NORMAL"] .. (source.name or source.dn or "???"))
		end
		return
	end
	if socketGroup.enabled and not socketGroup.slotEnabled then
		tooltip:AddLine(16, "^7Note: this group is disabled because it is socketed in the inactive weapon set.")
	end
	local sourceSingle = socketGroup.sourceItem or socketGroup.sourceNode
	if sourceSingle then
		tooltip:AddLine(18, "^7Source: " .. colorCodes[sourceSingle.rarity or "NORMAL"] .. sourceSingle.name)
		tooltip:AddSeparator(10)
	end
	local gemShown = { }
	for index, activeSkill in ipairs(socketGroup.displaySkillList) do
		if index > 1 then
			tooltip:AddSeparator(10)
		end
		tooltip:AddLine(16, "^7Active Skill #"..index..":")
		for _, skillEffect in ipairs(activeSkill.effectList) do
			tooltip:AddLine(20, string.format("%s%s ^7%d%s/%d%s",
				data.skillColorMap[skillEffect.grantedEffect.color],
				skillEffect.grantedEffect.name,
				skillEffect.srcInstance and skillEffect.srcInstance.level or skillEffect.level,
				(skillEffect.srcInstance and skillEffect.level > skillEffect.srcInstance.level) and colorCodes.MAGIC.."+"..(skillEffect.level - skillEffect.srcInstance.level).."^7" or "",
				skillEffect.srcInstance and skillEffect.srcInstance.quality or skillEffect.quality,
				(skillEffect.srcInstance and skillEffect.quality > skillEffect.srcInstance.quality) and colorCodes.MAGIC.."+"..(skillEffect.quality - skillEffect.srcInstance.quality).."^7" or ""
			))
			if skillEffect.srcInstance then
				gemShown[skillEffect.srcInstance] = true
			end
		end
		if activeSkill.minion then
			tooltip:AddSeparator(10)
			tooltip:AddLine(16, "^7Active Skill #" .. index .. "'s Main Minion Skill:")
			local activeEffect = activeSkill.minion.mainSkill.effectList[1]
			tooltip:AddLine(20, string.format("%s%s ^7%d%s/%d%s",
				data.skillColorMap[activeEffect.grantedEffect.color],
				activeEffect.grantedEffect.name,
				activeEffect.srcInstance and activeEffect.srcInstance.level or activeEffect.level,
				(activeEffect.srcInstance and activeEffect.level > activeEffect.srcInstance.level) and colorCodes.MAGIC .. "+" .. (activeEffect.level - activeEffect.srcInstance.level) .. "^7" or "",
				activeEffect.srcInstance and activeEffect.srcInstance.quality or activeEffect.quality,
				(activeEffect.srcInstance and activeEffect.quality > activeEffect.srcInstance.quality) and colorCodes.MAGIC .. "+" .. (activeEffect.quality - activeEffect.srcInstance.quality) .. "^7" or ""
			))
			if activeEffect.srcInstance then
				gemShown[activeEffect.srcInstance] = true
			end
		end
	end
	local showOtherHeader = true
	for _, gemInstance in ipairs(socketGroup.displayGemList or socketGroup.gemList) do
		if not gemShown[gemInstance] then
			if showOtherHeader then
				showOtherHeader = false
				tooltip:AddSeparator(10)
				tooltip:AddLine(16, "^7Inactive Gems:")
			end
			local reason = ""
			local displayEffect = gemInstance.displayEffect or gemInstance
			local grantedEffect = gemInstance.gemData and gemInstance.gemData.grantedEffect or gemInstance.grantedEffect
			if not grantedEffect then
				reason = "(Unsupported)"
			elseif not gemInstance.enabled then
				reason = "(Disabled)"
			elseif not socketGroup.enabled or not socketGroup.slotEnabled then
			elseif grantedEffect.support then
				if displayEffect.superseded then
					reason = "(Superseded)"
				elseif (not displayEffect.isSupporting or not next(displayEffect.isSupporting)) and #socketGroup.displaySkillList > 0 then
					reason = "(Cannot apply to any of the active skills)"
				end
			end
			tooltip:AddLine(20, string.format("%s%s ^7%d%s/%d%s %s",
				gemInstance.color,
				(gemInstance.grantedEffect and gemInstance.grantedEffect.name) or (gemInstance.gemData and gemInstance.gemData.name) or gemInstance.nameSpec,
				displayEffect.srcInstance and displayEffect.srcInstance.level or displayEffect.level,
				displayEffect.level > gemInstance.level and colorCodes.MAGIC .. "+" .. (displayEffect.level - gemInstance.level) .. "^7" or "",
				displayEffect.srcInstance and displayEffect.srcInstance.quality or displayEffect.quality,
				displayEffect.quality > gemInstance.quality and colorCodes.MAGIC .. "+" .. (displayEffect.quality - gemInstance.quality) .. "^7" or "",
				reason
			))
		end
	end
end

function SkillsTabClass:CreateUndoState()
	local state = { }
	state.activeSkillSetId = self.activeSkillSetId
	state.skillSets = { }
	for skillSetIndex, skillSet in pairs(self.skillSets) do
		local newSkillSet = copyTable(skillSet, true)
		newSkillSet.socketGroupList = { }
		for socketGroupIndex, socketGroup in pairs(skillSet.socketGroupList) do
			local newGroup = copyTable(socketGroup, true)
			newGroup.gemList = { }
			for gemIndex, gem in pairs(socketGroup.gemList) do
				newGroup.gemList[gemIndex] = copyTable(gem, true)
			end
			newSkillSet.socketGroupList[socketGroupIndex] = newGroup
		end
		state.skillSets[skillSetIndex] = newSkillSet
	end
	state.skillSetOrderList = copyTable(self.skillSetOrderList)
	-- Save active socket group for both skillsTab and calcsTab to UndoState
	state.activeSocketGroup = self.build.mainSocketGroup
	state.activeSocketGroup2 = self.build.calcsTab.input.skill_number
	return state
end

function SkillsTabClass:RestoreUndoState(state)
	local displayId = isValueInArray(self.socketGroupList, self.displayGroup)
	wipeTable(self.skillSets)
	for k, v in pairs(state.skillSets) do
		self.skillSets[k] = v
	end
	wipeTable(self.skillSetOrderList)
	for k, v in ipairs(state.skillSetOrderList) do
		self.skillSetOrderList[k] = v
	end
	self:SetActiveSkillSet(state.activeSkillSetId)
	self:SetDisplayGroup(displayId and self.socketGroupList[displayId])
	if self.controls.groupList.selValue then
		self.controls.groupList.selValue = self.socketGroupList[self.controls.groupList.selIndex]
	end
	-- Load active socket group for both skillsTab and calcsTab from UndoState
	self.build.mainSocketGroup = state.activeSocketGroup
	self.build.calcsTab.input.skill_number = state.activeSocketGroup2
end

-- Opens the skill set manager
function SkillsTabClass:OpenSkillSetManagePopup()
	main:OpenPopup(370, 290, "Manage Skill Sets", {
		new("SkillSetListControl", nil, {0, 50, 350, 200}, self),
		new("ButtonControl", nil, {0, 260, 90, 20}, "Done", function()
			main:ClosePopup()
		end),
	})
end

-- Creates a new skill set
function SkillsTabClass:NewSkillSet(skillSetId)
	local skillSet = { id = skillSetId, socketGroupList = {} }
	if not skillSetId then
		skillSet.id = 1
		while self.skillSets[skillSet.id] do
			skillSet.id = skillSet.id + 1
		end
	end
	self.skillSets[skillSet.id] = skillSet
	return skillSet
end

function SkillsTabClass:RebuildImbuedSupportBySlot()
	wipeTable(self.imbuedSupportBySlot)
	for _, socketGroup in ipairs(self.socketGroupList) do
		if socketGroup.slot and socketGroup.imbuedSupport then
			local gemId = data.gemForBaseName[socketGroup.imbuedSupport:lower().." support"]
			local gem = gemId and data.gems[gemId]
			if gem and gem.grantedEffect then
				self.imbuedSupportBySlot[socketGroup.slot] = gem.grantedEffect
			end
		end
	end
end

-- Changes the active skill set
function SkillsTabClass:SetActiveSkillSet(skillSetId)
	-- Initialize skill sets if needed
	if not self.skillSetOrderList[1] then
		self.skillSetOrderList[1] = 1
		self:NewSkillSet(1)
	end

	if not skillSetId then
		skillSetId = self.activeSkillSetId
	end

	if not self.skillSets[skillSetId] then
		skillSetId = self.skillSetOrderList[1]
	end

	self.socketGroupList = self.skillSets[skillSetId].socketGroupList
	self:RebuildImbuedSupportBySlot()
	self.controls.groupList.list = self.socketGroupList
	self.activeSkillSetId = skillSetId
	self.build.buildFlag = true

	-- set the loadout option to the dummy option since it is now dirty
	self:SetDisplayGroup(self.socketGroupList[1])
	self.build:SyncLoadouts()
end
