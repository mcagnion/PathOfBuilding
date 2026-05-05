-- Thin wrappers around PoB headless objects for programmatic operations

local M = {}

local MIN_PLAYER_LEVEL = 1
local MAX_PLAYER_LEVEL = 100
local NUM_FLASK_SLOTS = 5
local MAX_ITEM_TEXT_LENGTH = 10240  -- 10KB

function M.get_main_output()
  if not build or not build.calcsTab then
    return nil, "build not initialized"
  end
  if build.calcsTab.BuildOutput then
    build.calcsTab:BuildOutput()
  end
  local output = build.calcsTab and build.calcsTab.mainOutput or nil
  if not output then
    return nil, "no output available"
  end
  return output
end

local function copy_scalar_fields(tbl)
  local out = {}
  if type(tbl) ~= 'table' then return out end
  for key, value in pairs(tbl) do
    local valueType = type(value)
    if (type(key) == 'string' or type(key) == 'number') and
       (valueType == 'number' or valueType == 'string' or valueType == 'boolean') then
      out[key] = value
    end
  end
  return out
end

local function compact_calc_output(output)
  local out = copy_scalar_fields(output)
  if output and type(output.Minion) == 'table' then
    out.Minion = copy_scalar_fields(output.Minion)
  end
  return out
end

function M.export_stats(fields)
  local output, err = M.get_main_output()
  if not output then
    return nil, err
  end
  local wanted = fields or {
    "Life", "EnergyShield", "Armour", "Evasion",
    "FireResist", "ColdResist", "LightningResist", "ChaosResist",
    "BlockChance", "SpellBlockChance",
    "LifeRegen", "Mana", "ManaRegen", "ManaUnreserved",
    "Ward", "DodgeChance", "SpellDodgeChance",
    "TotalEHP", "PhysicalDamageReduction",
    "AttackDodgeChance", "EffectiveMovementSpeedMod",
    "SpellSuppressionChance", "LifeLeechGainRate", "ManaLeechGainRate",
    "EnduranceChargesMax", "FrenzyChargesMax", "PowerChargesMax",
    "FullDPS", "FullDotDPS", "ActiveTotemLimit",
  }
  local result = {}
  for _, k in ipairs(wanted) do
    if type(output[k]) ~= 'nil' then
      result[k] = output[k]
    end
  end
  local minionOutput = output.Minion
  if minionOutput and type(minionOutput) == 'table' then
    local minionWanted = {
      "Life", "EnergyShield", "Armour", "Evasion",
      "TotalDPS", "CombinedDPS", "AverageDamage", "Speed",
      "FireResist", "ColdResist", "LightningResist", "ChaosResist",
      "BlockChance", "PhysicalDamageReduction",
    }
    for _, k in ipairs(minionWanted) do
      if type(minionOutput[k]) ~= 'nil' then
        result["Minion" .. k] = minionOutput[k]
      end
    end
  end
  result._meta = result._meta or {}
  if build and build.targetVersion then
    result._meta.treeVersion = tostring(build.targetVersion)
  end
  if build and build.characterLevel then
    result._meta.level = tonumber(build.characterLevel)
  end
  if build and build.buildName then
    result._meta.buildName = tostring(build.buildName)
  end
  return result
end

function M.get_tree()
  if not build or not build.spec then
    return nil, "build/spec not initialized"
  end
  local spec = build.spec
  local out = {
    treeVersion = spec.treeVersion,
    classId = tonumber(spec.curClassId) or 0,
    ascendClassId = tonumber(spec.curAscendClassId) or 0,
    secondaryAscendClassId = tonumber(spec.curSecondaryAscendClassId or 0) or 0,
    nodes = {},
    masteryEffects = {},
  }
  for id, _ in pairs(spec.allocNodes or {}) do
    table.insert(out.nodes, id)
  end
  for mastery, effect in pairs(spec.masterySelections or {}) do
    out.masteryEffects[mastery] = effect
  end
  table.sort(out.nodes)
  return out
end

local function normalize_mastery_effects(masteryEffects)
  local out = {}
  if type(masteryEffects) ~= 'table' then return out end
  for mastery, effect in pairs(masteryEffects) do
    local masteryId = tonumber(mastery)
    local effectId = tonumber(effect)
    if masteryId and effectId then
      out[masteryId] = effectId
    end
  end
  return out
end

local function find_assigned_mastery_node(spec, effectId)
  for masteryId, selectedEffectId in pairs(spec.masterySelections or {}) do
    if tonumber(selectedEffectId) == tonumber(effectId) then
      return tonumber(masteryId)
    end
  end
  return nil
end

local function mastery_effect_stats(effect)
  local stats = {}
  if effect and type(effect.sd) == 'table' then
    for _, stat in ipairs(effect.sd) do
      if type(stat) == 'string' then table.insert(stats, stat) end
    end
  end
  return stats
end

local function apply_mastery_effects(spec, masteryEffects)
  if not spec or not spec.tree or not spec.tree.masteryEffects then
    return nil, 'passive tree mastery data unavailable'
  end
  for masteryId, effectId in pairs(masteryEffects or {}) do
    local node = spec.nodes and spec.nodes[masteryId] or spec.allocNodes and spec.allocNodes[masteryId]
    local effect = spec.tree.masteryEffects[effectId]
    if not node or not effect then
      return nil, string.format('invalid mastery effect %s for node %s', tostring(effectId), tostring(masteryId))
    end
    node.sd = effect.sd
    node.allMasteryOptions = false
    node.reminderText = { "Tip: Right click to select a different effect" }
    spec.masterySelections[masteryId] = effectId
    if spec.tree.ProcessStats then
      spec.tree:ProcessStats(node)
    end
  end
  return true
end

function M.get_mastery_options()
  if not build or not build.spec then
    return nil, "build/spec not initialized"
  end
  local spec = build.spec
  local tree = spec.tree
  if not tree or not tree.masteryEffects then
    return { masteries = {}, count = 0 }
  end

  local masteries = {}
  for id, node in pairs(spec.allocNodes or {}) do
    if node and node.type == "Mastery" and node.masteryEffects then
      local availableEffects = {}
      local nodeId = tonumber(id) or tonumber(node.id)
      local allocatedEffect = tonumber((spec.masterySelections or {})[nodeId])

      for _, option in ipairs(node.masteryEffects or {}) do
        local effectId = tonumber(option.effect)
        local assignedNodeId = effectId and find_assigned_mastery_node(spec, effectId) or nil
        if effectId and (not assignedNodeId or assignedNodeId == nodeId) then
          local effect = tree.masteryEffects[effectId]
          local stats = mastery_effect_stats(effect)
          if #stats == 0 and type(option.stats) == 'table' then
            for _, stat in ipairs(option.stats) do
              if type(stat) == 'string' then table.insert(stats, stat) end
            end
          end
          if #stats > 0 then
            table.insert(availableEffects, {
              effectId = effectId,
              stat = table.concat(stats, " / "),
              stats = stats,
            })
          end
        end
      end

      table.sort(availableEffects, function(a, b)
        return (a.stat or '') < (b.stat or '')
      end)

      table.insert(masteries, {
        nodeId = nodeId,
        nodeName = node.name or node.dn or "Mastery",
        allocatedEffect = allocatedEffect,
        availableEffects = availableEffects,
      })
    end
  end

  table.sort(masteries, function(a, b)
    if (a.nodeName or '') ~= (b.nodeName or '') then
      return (a.nodeName or '') < (b.nodeName or '')
    end
    return (a.nodeId or 0) < (b.nodeId or 0)
  end)

  return { masteries = masteries, count = #masteries }
end

-- params: { classId, ascendClassId, secondaryAscendClassId?, nodes:[int], masteryEffects?:{[id]=effect}, treeVersion? }
function M.set_tree(params)
  if not build or not build.spec then
    return nil, "build/spec not initialized"
  end
  if type(params) ~= 'table' then
    return nil, "invalid params"
  end
  local classId = tonumber(params.classId or 0) or 0
  local ascendId = tonumber(params.ascendClassId or 0) or 0
  local secondaryId = tonumber(params.secondaryAscendClassId or 0) or 0
  local nodes = {}
  if type(params.nodes) == 'table' then
    for _, v in ipairs(params.nodes) do
      table.insert(nodes, tonumber(v))
    end
  end
  local mastery = params.masteryEffects or {}
  local treeVersion = params.treeVersion
  build.spec:ImportFromNodeList(classId, ascendId, secondaryId, nodes, {}, mastery, treeVersion)
  M.get_main_output()
  return true
end

function M.export_build_xml()
  if not build or not build.SaveDB then
    return nil, 'build not initialized'
  end
  local xml = build:SaveDB('api-export')
  if not xml then return nil, 'failed to compose xml' end
  return xml
end

function M.set_level(level)
  if not build or not build.configTab then
    return nil, 'build/config not initialized'
  end
  local lvl = tonumber(level)
  if not lvl or lvl < MIN_PLAYER_LEVEL or lvl > MAX_PLAYER_LEVEL then
    return nil, string.format('invalid level (must be %d-%d)', MIN_PLAYER_LEVEL, MAX_PLAYER_LEVEL)
  end
  build.characterLevel = lvl
  build.characterLevelAutoMode = false
  if build.configTab and build.configTab.BuildModList then
    build.configTab:BuildModList()
  end
  M.get_main_output()
  return true
end

function M.get_build_info()
  if not build then return nil, 'build not initialized' end
  local info = {
    name = build.buildName,
    level = build.characterLevel,
    className = build.spec and build.spec.curClassName or nil,
    ascendClassName = build.spec and build.spec.curAscendClassName or nil,
    treeVersion = build.targetVersion or (build.spec and build.spec.treeVersion) or nil,
  }
  return info
end

function M.update_tree_delta(params)
  params = params or {}
  if not build or not build.spec then return nil, 'build/spec not initialized' end
  local current, err = M.get_tree()
  if not current then return nil, err end
  local restoreAfter = params.restoreAfter == true or params.restore_after == true or params.preview == true
  if restoreAfter and (not build.spec.CreateUndoState or not build.spec.RestoreUndoState) then
    return nil, 'passive tree restore API not available'
  end
  local undoState = restoreAfter and build.spec:CreateUndoState() or nil
  if undoState then
    undoState.secondaryAscendClassId = current.secondaryAscendClassId or undoState.secondaryAscendClassId or 0
  end
  local set = {}
  for _, id in ipairs(current.nodes) do set[id] = true end
  if type(params.removeNodes) == 'table' then
    for _, id in ipairs(params.removeNodes) do set[tonumber(id)] = nil end
  end
  if type(params.addNodes) == 'table' then
    for _, id in ipairs(params.addNodes) do set[tonumber(id)] = true end
  end
  local nodes = {}
  for id,_ in pairs(set) do table.insert(nodes, id) end
  table.sort(nodes)
  local mastery = current.masteryEffects or {}
  local classId = params.classId or current.classId or 0
  local ascendId = params.ascendClassId or current.ascendClassId or 0
  local secId = params.secondaryAscendClassId or current.secondaryAscendClassId or 0
  local tv = params.treeVersion or current.treeVersion

  local ok, output, outputErr, previewTree, previewTreeErr = pcall(function()
    build.spec:ImportFromNodeList(tonumber(classId) or 0, tonumber(ascendId) or 0, tonumber(secId) or 0, nodes, {}, mastery, tv)
    local calcOutput, calcErr = M.get_main_output()
    local tree, treeErr = M.get_tree()
    return calcOutput, calcErr, tree, treeErr
  end)

  local restoredTree
  local restoreErr
  if undoState then
    local restoreOk, err2 = pcall(function()
      build.spec:RestoreUndoState(undoState)
      local restoredOutput, restoredOutputErr = M.get_main_output()
      if not restoredOutput then
        error(restoredOutputErr or 'failed to recalculate after restoring passive tree')
      end
      restoredTree = M.get_tree()
    end)
    if not restoreOk then
      restoreErr = tostring(err2)
    end
  end

  if not ok then
    if restoreErr then
      return nil, tostring(output) .. '; restore failed: ' .. restoreErr
    end
    return nil, tostring(output)
  end
  if not output then
    if restoreErr then
      return nil, tostring(outputErr or 'failed to recalculate after tree delta') .. '; restore failed: ' .. restoreErr
    end
    return nil, outputErr
  end
  if not previewTree then
    if restoreErr then
      return nil, tostring(previewTreeErr or 'failed to read tree after tree delta') .. '; restore failed: ' .. restoreErr
    end
    return nil, previewTreeErr
  end
  if restoreErr then
    return nil, 'failed to restore passive tree after preview: ' .. restoreErr
  end

  return {
    tree = previewTree,
    output = output,
    restored = restoreAfter,
    restoredTree = restoredTree,
  }
end


-- params: { addNodes?: number[], removeNodes?: number[], masteryEffects?:{[id]=effect}, useFullDPS?: boolean }
function M.calc_with(params)
  if not build or not build.calcsTab then return nil, 'build not initialized' end
  if params and type(params.masteryEffects) == 'table' then
    if not build.spec then return nil, 'build/spec not initialized' end
    if not build.spec.CreateUndoState or not build.spec.RestoreUndoState then
      return nil, 'passive tree restore API not available'
    end
    local current, treeErr = M.get_tree()
    if not current then return nil, treeErr end

    local set = {}
    for _, id in ipairs(current.nodes or {}) do set[id] = true end
    if type(params.removeNodes) == 'table' then
      for _, id in ipairs(params.removeNodes) do set[tonumber(id)] = nil end
    end
    if type(params.addNodes) == 'table' then
      for _, id in ipairs(params.addNodes) do set[tonumber(id)] = true end
    end
    local nodes = {}
    for id, _ in pairs(set) do table.insert(nodes, id) end
    table.sort(nodes)

    local requestedMasteryEffects = normalize_mastery_effects(params.masteryEffects)
    local masteryEffects = normalize_mastery_effects(current.masteryEffects)
    local changedMasteryEffects = {}
    for masteryId, effectId in pairs(requestedMasteryEffects) do
      if tonumber(current.masteryEffects and current.masteryEffects[masteryId]) ~= tonumber(effectId) then
        changedMasteryEffects[masteryId] = effectId
      end
      masteryEffects[masteryId] = effectId
    end

    local undoState = build.spec:CreateUndoState()
    local output, outputErr
    local ok, err = pcall(function()
      if (type(params.addNodes) == 'table' and #params.addNodes > 0) or
         (type(params.removeNodes) == 'table' and #params.removeNodes > 0) then
        build.spec:ImportFromNodeList(
          tonumber(current.classId) or 0,
          tonumber(current.ascendClassId) or 0,
          tonumber(current.secondaryAscendClassId) or 0,
          nodes,
          build.spec.hashOverrides or {},
          masteryEffects,
          current.treeVersion
        )
      else
        local applied, applyErr = apply_mastery_effects(build.spec, changedMasteryEffects)
        if not applied then error(applyErr) end
      end
      output, outputErr = M.get_main_output()
    end)

    local restoreOk, restoreErr = pcall(function()
      build.spec:RestoreUndoState(undoState)
      local restoredOutput, restoredOutputErr = M.get_main_output()
      if not restoredOutput then
        error(restoredOutputErr or 'failed to recalculate after restoring passive tree')
      end
    end)

    if not ok then
      return nil, tostring(err) .. (restoreOk and '' or '; restore failed: ' .. tostring(restoreErr))
    end
    if not restoreOk then
      return nil, 'failed to restore passive tree after mastery calculation: ' .. tostring(restoreErr)
    end
    if not output then
      return nil, outputErr or 'failed to recalculate with mastery effects'
    end
    return compact_calc_output(output), nil
  end

  local calcFunc, baseOut = build.calcsTab:GetMiscCalculator()
  local override = {}
  if params and type(params.addNodes) == 'table' then
    override.addNodes = {}
    for _, id in ipairs(params.addNodes) do
      local n = build.spec and build.spec.nodes and build.spec.nodes[tonumber(id)]
      if n then override.addNodes[n] = true end
    end
  end
  if params and type(params.removeNodes) == 'table' then
    override.removeNodes = {}
    for _, id in ipairs(params.removeNodes) do
      local n = build.spec and build.spec.nodes and build.spec.nodes[tonumber(id)]
      if n then override.removeNodes[n] = true end
    end
  end
  local out = calcFunc(override, params and params.useFullDPS)
  return compact_calc_output(out), baseOut
end


function M.get_config()
  if not build or not build.configTab then return nil, 'build/config not initialized' end
  local input = build.configTab.input or {}
  local cfg = copy_scalar_fields(input)
  if cfg.bandit == nil then cfg.bandit = build.bandit end
  if cfg.pantheonMajorGod == nil then cfg.pantheonMajorGod = build.pantheonMajorGod end
  if cfg.pantheonMinorGod == nil then cfg.pantheonMinorGod = build.pantheonMinorGod end
  cfg.enemyLevel = build.configTab.enemyLevel or cfg.enemyLevel
  return cfg
end

-- Lazily-built lookup of every ConfigOptions var -> declared type, so
-- set_config can pass arbitrary keys through to build.configTab.input
-- instead of relying on a hand-maintained whitelist that silently drops
-- anything outside its scope.
local _configVarTypes = nil
local function _getConfigVarTypes()
  if _configVarTypes then return _configVarTypes end
  local ok, varList = pcall(LoadModule, "Modules/ConfigOptions")
  local map = {}
  if ok and type(varList) == 'table' then
    for _, opt in ipairs(varList) do
      if type(opt) == 'table' and opt.var and opt.type then
        map[opt.var] = opt.type
      end
    end
  end
  _configVarTypes = map
  return map
end

-- Older callers wrote to keys that don't exist in ConfigOptions, so the
-- writes were silent no-ops. Map them to the real var names rather than
-- breaking those callers.
local _configAliases = {
  enemyFireResistance = "enemyFireResist",
  enemyColdResistance = "enemyColdResist",
  enemyLightningResistance = "enemyLightningResist",
  enemyChaosResistance = "enemyChaosResist",
  conditionFortify = "buffFortification",
  conditionShockedGround = "conditionOnShockedGround",
}

local function _coerceConfigValue(varType, value)
  if varType == 'check' then
    if type(value) == 'string' then return value == 'true' end
    return value and true or false
  elseif varType == 'count' or varType == 'countAllowZero' or varType == 'integer' or varType == 'float' then
    return tonumber(value)
  end
  if type(value) == 'boolean' then return value and 'true' or 'false' end
  return tostring(value)
end

function M.set_config(params)
  if not build or not build.configTab then return nil, 'build/config not initialized' end
  if type(params) ~= 'table' then return nil, 'invalid params' end
  local input = build.configTab.input or {}
  build.configTab.input = input
  local varTypes = _getConfigVarTypes()
  local appliedKeys, aliasedKeys, ignoredKeys = {}, {}, {}
  local changed = false
  for key, value in pairs(params) do
    local resolved = _configAliases[key] or key
    local varType = varTypes[resolved]
    if not varType then
      table.insert(ignoredKeys, key)
    else
      local coerced = _coerceConfigValue(varType, value)
      if varType ~= 'check' and coerced == nil then
        table.insert(ignoredKeys, key)
      else
        input[resolved] = coerced
        if resolved ~= key then aliasedKeys[key] = resolved end
        table.insert(appliedKeys, resolved)
        changed = true
      end
    end
  end
  table.sort(appliedKeys)
  table.sort(ignoredKeys)
  if changed and build.configTab.BuildModList then build.configTab:BuildModList() end
  M.get_main_output()
  return { ok = true, appliedKeys = appliedKeys, aliasedKeys = aliasedKeys, ignoredKeys = ignoredKeys }
end


function M.get_skills()
  if not build or not build.skillsTab or not build.calcsTab then return nil, 'skills not initialized' end
  local groups = {}
  for idx, g in ipairs(build.skillsTab.socketGroupList or {}) do
    local names = {}
    if g.displaySkillList then
      for _, eff in ipairs(g.displaySkillList) do
        if eff and eff.activeEffect and eff.activeEffect.grantedEffect then
          table.insert(names, eff.activeEffect.grantedEffect.name)
        end
      end
    end
    local gems = {}
    if g.gemList then
      for gemIdx, gem in ipairs(g.gemList) do
        table.insert(gems, {
          index = gemIdx,
          name = gem.nameSpec or gem.name or '',
          level = gem.level or 1,
          quality = gem.quality or 0,
          qualityId = gem.qualityId or 'Default',
          enabled = gem.enabled ~= false,
          isSupport = gem.skillId and gem.skillId:find('Support') ~= nil or false,
        })
      end
    end
    table.insert(groups, {
      index = idx,
      label = g.label,
      slot = g.slot,
      enabled = g.enabled,
      includeInFullDPS = g.includeInFullDPS,
      mainActiveSkill = g.mainActiveSkill,
      skills = names,
      gems = gems,
    })
  end
  local result = {
    mainSocketGroup = build.mainSocketGroup,
    calcsSkillNumber = build.calcsTab.input and build.calcsTab.input.skill_number or nil,
    groups = groups,
  }
  return result
end

function M.set_main_selection(params)
  if not build or not build.skillsTab or not build.calcsTab then return nil, 'skills not initialized' end
  if type(params) ~= 'table' then return nil, 'invalid params' end
  if params.mainSocketGroup ~= nil then
    build.mainSocketGroup = tonumber(params.mainSocketGroup) or build.mainSocketGroup
  end
  local g = build.skillsTab.socketGroupList[build.mainSocketGroup]
  if not g then return nil, 'invalid mainSocketGroup' end
  if params.mainActiveSkill ~= nil then
    g.mainActiveSkill = tonumber(params.mainActiveSkill) or g.mainActiveSkill
  end
  if params.skillPart ~= nil then
    local idx = g.mainActiveSkill or 1
    local src = g.displaySkillList and g.displaySkillList[idx] and g.displaySkillList[idx].activeEffect and g.displaySkillList[idx].activeEffect.srcInstance
    if src then src.skillPart = tonumber(params.skillPart) end
  end
  -- Keep calcsTab in sync: use active group index
  build.calcsTab.input.skill_number = build.mainSocketGroup
  M.get_main_output()
  return true
end

function M.add_item_text(params)
  if not build or not build.itemsTab then return nil, 'items not initialized' end
  if type(params) ~= 'table' or type(params.text) ~= 'string' then return nil, 'missing text' end

  if #params.text == 0 then return nil, 'item text cannot be empty' end
  if #params.text > MAX_ITEM_TEXT_LENGTH then
    return nil, string.format('item text too long (max %d bytes)', MAX_ITEM_TEXT_LENGTH)
  end

  local ok, item = pcall(new, 'Item', params.text)
  if not ok then return nil, 'invalid item text: ' .. tostring(item) end
  if not item or not item.baseName then return nil, 'failed to parse item' end

  item:NormaliseQuality()
  build.itemsTab:AddItem(item, params.noAutoEquip == true)
  if params.slotName then
    local slot = tostring(params.slotName)
    if build.itemsTab.slots[slot] then
      build.itemsTab.slots[slot]:SetSelItemId(item.id)
      build.itemsTab:PopulateSlots()
    end
  end
  build.itemsTab:AddUndoState()
  build.buildFlag = true
  M.get_main_output()
  return { id = item.id, name = item.name, slot = params.slotName or item:GetPrimarySlot() }
end

function M.set_flask_active(params)
  if not build or not build.itemsTab then return nil, 'items not initialized' end
  if type(params) ~= 'table' then return nil, 'invalid params' end
  local idx = tonumber(params.index)
  local active = params.active == true
  if not idx or idx < 1 or idx > NUM_FLASK_SLOTS then
    return nil, string.format('invalid flask index (must be 1-%d)', NUM_FLASK_SLOTS)
  end
  local slotName = 'Flask ' .. tostring(idx)
  if not build.itemsTab.activeItemSet or not build.itemsTab.activeItemSet[slotName] then return nil, 'slot not found' end
  build.itemsTab.activeItemSet[slotName].active = active
  -- Re-populate slots so flask effects are applied before recalculating
  if build.itemsTab.PopulateSlots then
    build.itemsTab:PopulateSlots()
  end
  if build.configTab and build.configTab.BuildModList then
    build.configTab:BuildModList()
  end
  build.itemsTab:AddUndoState()
  build.buildFlag = true
  M.get_main_output()
  return true
end


function M.get_items()
  if not build or not build.itemsTab then return nil, 'items not initialized' end
  local itemsTab = build.itemsTab
  local result = { }
  -- Prefer orderedSlots for deterministic order
  local ordered = itemsTab.orderedSlots or {}
  local seen = {}
  local function add_slot(slotName)
    if seen[slotName] then return end
    seen[slotName] = true
    local slotCtrl = itemsTab.slots[slotName]
    if not slotCtrl then return end
    local selId = slotCtrl.selItemId or 0
    local entry = { slot = slotName, id = selId }
    if selId > 0 then
      local it = itemsTab.items[selId]
      if it then
        entry.name = it.name
        entry.baseName = it.baseName
        entry.type = it.type
        entry.rarity = it.rarity
        entry.raw = it.raw
      end
    end
    -- Flask/Tincture activation flag stored in activeItemSet
    local set = itemsTab.activeItemSet
    if set and set[slotName] and set[slotName].active ~= nil then
      entry.active = set[slotName].active and true or false
    end
    table.insert(result, entry)
  end
  for _, slot in ipairs(ordered) do
    if slot and slot.slotName then add_slot(slot.slotName) end
  end
  -- Add any remaining slots not in ordered list
  for slotName, _ in pairs(itemsTab.slots or {}) do add_slot(slotName) end
  return result
end


-- params: { label?: string, slot?: string, enabled?: boolean, includeInFullDPS?: boolean }
function M.create_socket_group(params)
  if not build or not build.skillsTab then return nil, 'skills not initialized' end
  if type(params) ~= 'table' then params = {} end

  local socketGroup = {
    label = params.label or '',
    slot = params.slot,
    enabled = params.enabled ~= false,
    includeInFullDPS = params.includeInFullDPS == true,
    gemList = {},
    mainActiveSkill = 1,
    mainActiveSkillCalcs = 1,
  }

  local skillSetId = build.skillsTab.activeSkillSetId or 1
  local skillSet = build.skillsTab.skillSets[skillSetId]
  if not skillSet then return nil, 'active skill set not found' end

  table.insert(skillSet.socketGroupList, socketGroup)
  local index = #skillSet.socketGroupList

  if build.skillsTab.ProcessSocketGroup then
    build.skillsTab:ProcessSocketGroup(socketGroup)
  end

  build.buildFlag = true
  M.get_main_output()

  return { index = index, label = socketGroup.label }
end

-- params: { groupIndex: number, gemName: string, level?: number, quality?: number, qualityId?: string, enabled?: boolean }
function M.add_gem(params)
  if not build or not build.skillsTab then return nil, 'skills not initialized' end
  if type(params) ~= 'table' then return nil, 'invalid params' end
  if not params.groupIndex or not params.gemName then return nil, 'missing groupIndex or gemName' end

  local skillSetId = build.skillsTab.activeSkillSetId or 1
  local skillSet = build.skillsTab.skillSets[skillSetId]
  if not skillSet then return nil, 'active skill set not found' end

  local groupIndex = tonumber(params.groupIndex)
  local socketGroup = skillSet.socketGroupList[groupIndex]
  if not socketGroup then return nil, 'socket group not found at index ' .. tostring(groupIndex) end

  local gemInstance = {
    nameSpec = tostring(params.gemName),
    level = tonumber(params.level) or 20,
    quality = tonumber(params.quality) or 0,
    qualityId = params.qualityId or 'Default',
    enabled = params.enabled ~= false,
    enableGlobal1 = true,
    enableGlobal2 = false,
    count = tonumber(params.count) or 1,
  }

  if build.data and build.data.gems then
    for _, gemData in pairs(build.data.gems) do
      if gemData.name == gemInstance.nameSpec or gemData.nameSpec == gemInstance.nameSpec then
        gemInstance.gemId = gemData.id
        if gemData.grantedEffect then
          gemInstance.skillId = gemData.grantedEffect.id
        elseif gemData.grantedEffectId then
          gemInstance.skillId = gemData.grantedEffectId
        end
        gemInstance.gemData = gemData
        break
      end
    end
  end

  table.insert(socketGroup.gemList, gemInstance)
  local gemIndex = #socketGroup.gemList

  if build.skillsTab.ProcessSocketGroup then
    build.skillsTab:ProcessSocketGroup(socketGroup)
  end

  build.buildFlag = true
  M.get_main_output()

  return { gemIndex = gemIndex, name = gemInstance.nameSpec }
end

-- params: { groupIndex: number, gemIndex: number, level: number }
function M.set_gem_level(params)
  if not build or not build.skillsTab then return nil, 'skills not initialized' end
  if type(params) ~= 'table' then return nil, 'invalid params' end
  if not params.groupIndex or not params.gemIndex or not params.level then
    return nil, 'missing groupIndex, gemIndex, or level'
  end

  local skillSetId = build.skillsTab.activeSkillSetId or 1
  local skillSet = build.skillsTab.skillSets[skillSetId]
  if not skillSet then return nil, 'active skill set not found' end

  local groupIndex = tonumber(params.groupIndex)
  local gemIndex = tonumber(params.gemIndex)
  local level = tonumber(params.level)

  local socketGroup = skillSet.socketGroupList[groupIndex]
  if not socketGroup then return nil, 'socket group not found' end

  local gemInstance = socketGroup.gemList[gemIndex]
  if not gemInstance then return nil, 'gem not found' end

  if level < 1 or level > 40 then return nil, 'invalid level (must be 1-40)' end

  gemInstance.level = level

  if build.skillsTab.ProcessSocketGroup then
    build.skillsTab:ProcessSocketGroup(socketGroup)
  end

  build.buildFlag = true
  M.get_main_output()

  return true
end

local function resolve_gem_instance(params, requireQuality)
  if not build or not build.skillsTab then return nil, 'skills not initialized' end
  if type(params) ~= 'table' then return nil, 'invalid params' end
  if not params.groupIndex or not params.gemIndex then
    return nil, 'missing groupIndex or gemIndex'
  end
  if requireQuality and params.quality == nil then
    return nil, 'missing quality'
  end

  local skillSetId = build.skillsTab.activeSkillSetId or 1
  local skillSet = build.skillsTab.skillSets[skillSetId]
  if not skillSet then return nil, 'active skill set not found' end

  local groupIndex = tonumber(params.groupIndex)
  local gemIndex = tonumber(params.gemIndex)
  if not groupIndex or not gemIndex then
    return nil, 'invalid groupIndex or gemIndex'
  end

  local socketGroup = skillSet.socketGroupList[groupIndex]
  if not socketGroup then return nil, 'socket group not found' end

  local gemInstance = socketGroup.gemList[gemIndex]
  if not gemInstance then return nil, 'gem not found' end

  return gemInstance, socketGroup, groupIndex, gemIndex
end

local function coerce_boolean(value)
  if value == true then return true end
  if value == false then return false end
  if value == 'true' then return true end
  if value == 'false' then return false end
  return nil
end

local function process_socket_group(socketGroup)
  if build.skillsTab.ProcessSocketGroup then
    build.skillsTab:ProcessSocketGroup(socketGroup)
  end
  build.buildFlag = true
  M.get_main_output()
end

local function apply_gem_quality(socketGroup, gemInstance, quality, qualityId)
  if quality < 0 or quality > 23 then return nil, 'invalid quality (must be 0-23)' end

  gemInstance.quality = quality
  if qualityId ~= nil then
    gemInstance.qualityId = tostring(qualityId)
  end

  process_socket_group(socketGroup)
  return true
end

local function apply_gem_enabled(socketGroup, gemInstance, enabled)
  gemInstance.enabled = enabled == true
  process_socket_group(socketGroup)
  return true
end

local function gem_quality_snapshot(gemInstance)
  return {
    name = gemInstance.nameSpec or gemInstance.name or '',
    quality = tonumber(gemInstance.quality) or 0,
    qualityId = gemInstance.qualityId or 'Default',
  }
end

local function gem_enabled_snapshot(gemInstance)
  return {
    name = gemInstance.nameSpec or gemInstance.name or '',
    level = tonumber(gemInstance.level) or 1,
    quality = tonumber(gemInstance.quality) or 0,
    qualityId = gemInstance.qualityId or 'Default',
    enabled = gemInstance.enabled ~= false,
    isSupport = gemInstance.skillId and gemInstance.skillId:find('Support') ~= nil or false,
  }
end

-- params: { groupIndex: number, gemIndex: number, quality: number, qualityId?: string }
function M.set_gem_quality(params)
  local gemInstance, socketGroup = resolve_gem_instance(params, true)
  if not gemInstance then return nil, socketGroup end

  local quality = tonumber(params.quality)
  if not quality then return nil, 'invalid quality' end

  local ok, err = apply_gem_quality(socketGroup, gemInstance, quality, params.qualityId)
  if not ok then return nil, err end

  return true
end

-- params: { groupIndex: number, gemIndex: number, enabled: boolean }
function M.set_gem_enabled(params)
  local gemInstance, socketGroup = resolve_gem_instance(params, false)
  if not gemInstance then return nil, socketGroup end

  local enabled = coerce_boolean(params.enabled)
  if enabled == nil then return nil, 'missing or invalid enabled' end

  local ok, err = apply_gem_enabled(socketGroup, gemInstance, enabled)
  if not ok then return nil, err end

  return true
end

-- params: { groupIndex: number, gemIndex: number, quality: number, qualityId?: string, fields?: string[] }
function M.preview_gem_quality(params)
  local gemInstance, socketGroup = resolve_gem_instance(params, true)
  if not gemInstance then return nil, socketGroup end

  local quality = tonumber(params.quality)
  if not quality then return nil, 'invalid quality' end
  if quality < 0 or quality > 23 then return nil, 'invalid quality (must be 0-23)' end

  local fields = type(params.fields) == 'table' and params.fields or nil
  local original = gem_quality_snapshot(gemInstance)
  local targetQualityId = params.qualityId ~= nil and tostring(params.qualityId) or original.qualityId

  local beforeStats, beforeErr = M.export_stats(fields)
  if not beforeStats then return nil, beforeErr or 'failed to read stats before preview' end

  local previewStats, previewErr
  local ok, previewFailure = pcall(function()
    local applied, applyErr = apply_gem_quality(socketGroup, gemInstance, quality, targetQualityId)
    if not applied then error(applyErr or 'failed to apply preview quality') end
    previewStats, previewErr = M.export_stats(fields)
    if not previewStats then error(previewErr or 'failed to read stats after preview') end
  end)

  local preview = gem_quality_snapshot(gemInstance)
  local restoredOk, restoreErr = apply_gem_quality(socketGroup, gemInstance, original.quality, original.qualityId)
  local restored = gem_quality_snapshot(gemInstance)
  local restoredStats, restoredStatsErr = nil, nil
  if restoredOk then
    restoredStats, restoredStatsErr = M.export_stats(fields)
  end

  local restoredMatches =
    restoredOk and
    restored.quality == original.quality and
    tostring(restored.qualityId or 'Default') == tostring(original.qualityId or 'Default')

  if not ok then
    return nil, 'failed to preview gem quality; restored=' .. tostring(restoredMatches) .. '; error=' .. tostring(previewFailure)
  end
  if not restoredMatches then
    return nil, restoreErr or restoredStatsErr or 'failed to restore gem quality after preview'
  end

  return {
    before = beforeStats,
    after = previewStats,
    restoredStats = restoredStats,
    restored = restoredMatches,
    gemBefore = original,
    gemPreview = preview,
    gemRestored = restored,
  }
end

-- params: { groupIndex: number, gemIndex: number, enabled: boolean, fields?: string[] }
function M.preview_gem_enabled(params)
  local gemInstance, socketGroup = resolve_gem_instance(params, false)
  if not gemInstance then return nil, socketGroup end

  local targetEnabled = coerce_boolean(params.enabled)
  if targetEnabled == nil then return nil, 'missing or invalid enabled' end

  local fields = type(params.fields) == 'table' and params.fields or nil
  local original = gem_enabled_snapshot(gemInstance)

  local beforeStats, beforeErr = M.export_stats(fields)
  if not beforeStats then return nil, beforeErr or 'failed to read stats before preview' end

  local previewStats, previewErr
  local ok, previewFailure = pcall(function()
    local applied, applyErr = apply_gem_enabled(socketGroup, gemInstance, targetEnabled)
    if not applied then error(applyErr or 'failed to apply preview enabled state') end
    previewStats, previewErr = M.export_stats(fields)
    if not previewStats then error(previewErr or 'failed to read stats after preview') end
  end)

  local preview = gem_enabled_snapshot(gemInstance)
  local restoredOk, restoreErr = apply_gem_enabled(socketGroup, gemInstance, original.enabled)
  local restored = gem_enabled_snapshot(gemInstance)
  local restoredStats, restoredStatsErr = nil, nil
  if restoredOk then
    restoredStats, restoredStatsErr = M.export_stats(fields)
  end

  local restoredMatches = restoredOk and restored.enabled == original.enabled

  if not ok then
    return nil, 'failed to preview gem enabled state; restored=' .. tostring(restoredMatches) .. '; error=' .. tostring(previewFailure)
  end
  if not restoredMatches then
    return nil, restoreErr or restoredStatsErr or 'failed to restore gem enabled state after preview'
  end

  return {
    before = beforeStats,
    after = previewStats,
    restoredStats = restoredStats,
    restored = restoredMatches,
    gemBefore = original,
    gemPreview = preview,
    gemRestored = restored,
  }
end

-- params: { groupIndex: number, gemIndices?: number[], enabled?: boolean, fields?: string[] }
function M.preview_gem_enabled_batch(params)
  if not build or not build.skillsTab then return nil, 'skills not initialized' end
  if type(params) ~= 'table' then return nil, 'invalid params' end
  if not params.groupIndex then return nil, 'missing groupIndex' end

  local targetEnabled = params.enabled == nil and false or coerce_boolean(params.enabled)
  if targetEnabled == nil then return nil, 'invalid enabled' end

  local skillSetId = build.skillsTab.activeSkillSetId or 1
  local skillSet = build.skillsTab.skillSets[skillSetId]
  if not skillSet then return nil, 'active skill set not found' end

  local groupIndex = tonumber(params.groupIndex)
  if not groupIndex then return nil, 'invalid groupIndex' end
  local socketGroup = skillSet.socketGroupList[groupIndex]
  if not socketGroup then return nil, 'socket group not found' end

  local gemIndices = {}
  if type(params.gemIndices) == 'table' then
    for _, gemIndex in ipairs(params.gemIndices) do
      local parsedGemIndex = tonumber(gemIndex)
      if not parsedGemIndex then return nil, 'invalid gemIndex in gemIndices' end
      table.insert(gemIndices, parsedGemIndex)
    end
  elseif socketGroup.gemList then
    for gemIndex, _ in ipairs(socketGroup.gemList) do
      table.insert(gemIndices, gemIndex)
    end
  end

  local results = {}
  for _, gemIndex in ipairs(gemIndices) do
    local result, err = M.preview_gem_enabled({
      groupIndex = groupIndex,
      gemIndex = gemIndex,
      enabled = targetEnabled,
      fields = params.fields,
    })
    if result then
      result.ok = true
      result.gemIndex = gemIndex
      table.insert(results, result)
    else
      table.insert(results, { ok = false, gemIndex = gemIndex, error = err or 'failed to preview gem enabled state' })
      if err and string.find(err, 'restored=false', 1, true) then
        break
      end
    end
  end

  return {
    groupIndex = groupIndex,
    enabled = targetEnabled,
    results = results,
  }
end

-- params: { groupIndex: number }
function M.remove_skill(params)
  if not build or not build.skillsTab then return nil, 'skills not initialized' end
  if type(params) ~= 'table' then return nil, 'invalid params' end
  if not params.groupIndex then return nil, 'missing groupIndex' end

  local skillSetId = build.skillsTab.activeSkillSetId or 1
  local skillSet = build.skillsTab.skillSets[skillSetId]
  if not skillSet then return nil, 'active skill set not found' end

  local groupIndex = tonumber(params.groupIndex)
  local socketGroup = skillSet.socketGroupList[groupIndex]
  if not socketGroup then return nil, 'socket group not found' end

  -- Don't allow removing special groups with sources
  if socketGroup.source then
    return nil, 'cannot remove special socket groups (item/node granted skills)'
  end

  table.remove(skillSet.socketGroupList, groupIndex)

  build.buildFlag = true
  M.get_main_output()

  return true
end

-- params: { groupIndex: number, gemIndex: number }
function M.remove_gem(params)
  if not build or not build.skillsTab then return nil, 'skills not initialized' end
  if type(params) ~= 'table' then return nil, 'invalid params' end
  if not params.groupIndex or not params.gemIndex then
    return nil, 'missing groupIndex or gemIndex'
  end

  local skillSetId = build.skillsTab.activeSkillSetId or 1
  local skillSet = build.skillsTab.skillSets[skillSetId]
  if not skillSet then return nil, 'active skill set not found' end

  local groupIndex = tonumber(params.groupIndex)
  local gemIndex = tonumber(params.gemIndex)

  local socketGroup = skillSet.socketGroupList[groupIndex]
  if not socketGroup then return nil, 'socket group not found' end

  local gemInstance = socketGroup.gemList[gemIndex]
  if not gemInstance then return nil, 'gem not found' end

  table.remove(socketGroup.gemList, gemIndex)

  if build.skillsTab.ProcessSocketGroup then
    build.skillsTab:ProcessSocketGroup(socketGroup)
  end

  build.buildFlag = true
  M.get_main_output()

  return true
end

-- params: { text: string }
-- Sets the in-memory notes buffer so a subsequent save_build serialises the
-- new content. Without this, set_build_notes (which writes XML directly to
-- disk) is silently overwritten the next time save_build runs from the stale
-- in-memory NotesTab buffer.
function M.set_notes(params)
  if not build or not build.notesTab then
    return nil, 'build/notes not initialized'
  end
  if type(params) ~= 'table' or type(params.text) ~= 'string' then
    return nil, 'missing or invalid text'
  end
  local edit = build.notesTab.controls and build.notesTab.controls.edit
  if not edit or not edit.SetText then
    return nil, 'notes editor not available'
  end
  edit:SetText(params.text)
  build.notesTab.lastContent = edit.buf
  build.notesTab.modFlag = false
  return { length = #(edit.buf or '') }
end

-- params: { path: string }
function M.save_build(params)
  if not build or not build.SaveDB then
    return nil, 'build not initialized'
  end
  if type(params) ~= 'table' or type(params.path) ~= 'string' or params.path == '' then
    return nil, 'missing or invalid path'
  end

  -- Sync curAscendClassName from the current ascendClassId so the Build XML
  -- element reflects the live state after set_tree/new_build operations.
  if build.spec and build.spec.curClass and build.spec.curClass.classes then
    local ascendId = build.spec.curAscendClassId or 0
    local ascendClass = build.spec.curClass.classes[ascendId] or build.spec.curClass.classes[0]
    if ascendClass and ascendClass.name then
      build.spec.curAscendClassName = ascendClass.name
    end
  end

  -- Resolve socket group gem metadata before SaveDB serialises skills.
  if build.skillsTab and build.skillsTab.socketGroupList then
    for _, socketGroup in ipairs(build.skillsTab.socketGroupList) do
      if build.skillsTab.ProcessSocketGroup then
        build.skillsTab:ProcessSocketGroup(socketGroup)
      end
    end
  end

  local xml = build:SaveDB('api-export')
  if not xml then return nil, 'failed to compose xml' end
  local f, ferr = io.open(params.path, 'w')
  if not f then return nil, 'failed to open file: ' .. tostring(ferr) end
  f:write(xml)
  f:close()
  return { path = params.path, size = #xml }
end

-- params: { keyword: string, nodeType?: string ('normal'|'notable'|'keystone'), maxResults?: number, includeAllocated?: boolean }
function M.search_nodes(params)
  if not build or not build.spec then return nil, 'build/spec not initialized' end
  if type(params) ~= 'table' or type(params.keyword) ~= 'string' then
    return nil, 'missing or invalid keyword'
  end

  local keyword = params.keyword:lower()
  local nodeType = params.nodeType and params.nodeType:lower() or nil
  local maxResults = tonumber(params.maxResults) or 50
  local includeAllocated = params.includeAllocated ~= false

  local results = {}
  local count = 0

  local allocatedSet = {}
  if build.spec.allocNodes then
    for id, _ in pairs(build.spec.allocNodes) do
      allocatedSet[id] = true
    end
  end

  for id, node in pairs(build.spec.nodes) do
    if count >= maxResults then break end

    if not includeAllocated and allocatedSet[id] then
      goto continue
    end

    if nodeType then
      local nType = 'normal'
      if node.isKeystone then nType = 'keystone'
      elseif node.isNotable then nType = 'notable'
      elseif node.isJewelSocket then nType = 'jewel'
      elseif node.isMultipleChoiceOption then nType = 'mastery'
      elseif node.ascendancyName then nType = 'ascendancy'
      end
      if nType ~= nodeType then goto continue end
    end

    local matches = false
    if node.name and node.name:lower():find(keyword, 1, true) then
      matches = true
    end

    if not matches and node.sd then
      for _, stat in ipairs(node.sd) do
        if type(stat) == 'string' and stat:lower():find(keyword, 1, true) then
          matches = true
          break
        end
      end
    end

    if not matches and node.modList then
      for _, mod in ipairs(node.modList) do
        local modStr = tostring(mod)
        if modStr:lower():find(keyword, 1, true) then
          matches = true
          break
        end
      end
    end

    if matches then
      local nodeType = 'normal'
      if node.isKeystone then nodeType = 'keystone'
      elseif node.isNotable then nodeType = 'notable'
      elseif node.isJewelSocket then nodeType = 'jewel'
      elseif node.isMultipleChoiceOption then nodeType = 'mastery'
      elseif node.ascendancyName then nodeType = 'ascendancy'
      end

      local stats = {}
      if node.sd then
        for _, stat in ipairs(node.sd) do
          if type(stat) == 'string' then
            table.insert(stats, stat)
          end
        end
      end

      table.insert(results, {
        id = id,
        name = node.name or 'Unnamed',
        type = nodeType,
        stats = stats,
        allocated = allocatedSet[id] == true,
        x = node.x,
        y = node.y,
        orbit = node.orbit,
        orbitIndex = node.orbitIndex,
        ascendancyName = node.ascendancyName,
      })
      count = count + 1
    end

    ::continue::
  end

  -- Sort results: keystones first, then notables, then normal
  table.sort(results, function(a, b)
    local typeOrder = { keystone = 1, notable = 2, jewel = 3, mastery = 4, ascendancy = 5, normal = 6 }
    local aOrder = typeOrder[a.type] or 99
    local bOrder = typeOrder[b.type] or 99
    if aOrder ~= bOrder then
      return aOrder < bOrder
    end
    return (a.name or '') < (b.name or '')
  end)

  return { nodes = results, count = #results }
end

return M
