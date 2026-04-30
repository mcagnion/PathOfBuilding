-- Shared JSON-RPC handlers for PoB API (transport-agnostic)

-- Debug logging control
local DEBUG = os.getenv('POB_API_DEBUG') == '1'
local function debug_log(msg)
  if DEBUG then io.stderr:write('[Handlers] ' .. msg .. '\n') end
end

-- Resolve BuildOps reliably regardless of CWD
local BuildOps
do
  debug_log('Attempting to require API.BuildOps')
  local ok_ops, mod = pcall(require, 'API.BuildOps')
  debug_log('pcall require result: ok=' .. tostring(ok_ops) .. ', mod=' .. tostring(mod))
  if ok_ops and mod then
    debug_log('Successfully loaded BuildOps via require')
    BuildOps = mod
  else
    debug_log('require failed, trying dofile fallbacks')
    -- Try path relative to this file's directory
    local dir = ''
    local info = debug and debug.getinfo and debug.getinfo(1, 'S')
    local src = info and info.source or ''
    if type(src) == 'string' and src:sub(1,1) == '@' then
      local p = src:sub(2)
      dir = (p:gsub('[^/\\]+$', ''))
    end
    local tried = {}
    local function try(p)
      if p then table.insert(tried, p) end
      if not p then return false end
      debug_log('Trying to load: ' .. tostring(p))
      local ok2, m = pcall(dofile, p)
      if ok2 and m then
        debug_log('Successfully loaded BuildOps from: ' .. tostring(p))
        BuildOps = m
        return true
      end
      debug_log('Failed to load from: ' .. tostring(p) .. ' - error: ' .. tostring(m))
      return false
    end
    if not BuildOps then
      local _ = try(dir .. 'BuildOps.lua')
              or try((rawget(_G,'POB_SCRIPT_DIR') or '.') .. '/API/BuildOps.lua')
              or try('API/BuildOps.lua')
              or try('src/API/BuildOps.lua')
    end
    if not BuildOps then
      io.stderr:write('[Handlers] BuildOps.lua not found. Tried paths: ' .. table.concat(tried, ', ') .. '\n')
      error('API/BuildOps.lua not found. Tried: ' .. table.concat(tried, ', '))
    end
  end
end

local API_VERSION = "1.0.0"

local function version_meta()
  return {
    number      = _G.launch and launch.versionNumber or '?',
    branch      = _G.launch and launch.versionBranch or '?',
    platform    = _G.launch and launch.versionPlatform or '?',
    apiVersion  = API_VERSION,
  }
end

local handlers = {}

handlers.ping = function(params)
  return { ok = true, pong = true }
end

handlers.version = function(params)
  return { ok = true, version = version_meta() }
end

-- Class name → classId mapping (PoE1)
local CLASS_IDS = {
  Scion=0, Marauder=1, Ranger=2, Witch=3, Duelist=4, Templar=5, Shadow=6,
  scion=0, marauder=1, ranger=2, witch=3, duelist=4, templar=5, shadow=6,
}
-- Ascendancy index matches the order in TreeData/3_27/tree.lua ["ascendancies"] array (1-based)
local ASCENDANCY_IDS = {
  [0] = { Ascendant=1 },                               -- Scion
  [1] = { Juggernaut=1, Berserker=2, Chieftain=3 },    -- Marauder
  [2] = { Raider=1, Deadeye=2, Pathfinder=3 },         -- Ranger
  [3] = { Occultist=1, Elementalist=2, Necromancer=3 }, -- Witch
  [4] = { Slayer=1, Gladiator=2, Champion=3 },          -- Duelist
  [5] = { Inquisitor=1, Hierophant=2, Guardian=3 },     -- Templar
  [6] = { Assassin=1, Trickster=2, Saboteur=3 },        -- Shadow
}

handlers.new_build = function(params)
  if not _G.newBuild then
    return { ok = false, error = 'headless wrapper not initialized' }
  end
  _G.newBuild()
  if params and (params.className or params.ascendancy) then
    local classId = 0
    local ascendId = 0
    if params.className then
      classId = CLASS_IDS[params.className] or CLASS_IDS[params.className:lower()] or 0
    end
    if params.ascendancy and ASCENDANCY_IDS[classId] then
      ascendId = ASCENDANCY_IDS[classId][params.ascendancy] or 0
    end
    if build and build.spec then
      build.spec:ImportFromNodeList(classId, ascendId, 0, {}, {}, {})
    end
  end
  return { ok = true }
end

handlers.load_build_xml = function(params)
  if not params or type(params.xml) ~= 'string' then
    return { ok = false, error = 'missing xml' }
  end
  local name = (params.name and tostring(params.name)) or 'API Build'
  if not _G.loadBuildFromXML then
    return { ok = false, error = 'headless wrapper not initialized' }
  end
  _G.loadBuildFromXML(params.xml, name)
  return { ok = true, build_id = 1 }
end

handlers.get_stats = function(params)
  local fields = params and params.fields or nil
  local stats, err = BuildOps.export_stats(fields)
  if not stats then
    return { ok = false, error = err }
  end
  return { ok = true, stats = stats }
end

handlers.get_items = function(params)
  local list, err = BuildOps.get_items()
  if not list then return { ok = false, error = err } end
  return { ok = true, items = list }
end

handlers.get_skills = function(params)
  local info, err = BuildOps.get_skills()
  if not info then return { ok = false, error = err } end
  return { ok = true, skills = info }
end

handlers.get_tree = function(params)
  local tree, err = BuildOps.get_tree()
  if not tree then
    return { ok = false, error = err }
  end
  return { ok = true, tree = tree }
end

handlers.set_main_selection = function(params)
  local ok2, err = BuildOps.set_main_selection(params or {})
  if not ok2 then return { ok = false, error = err } end
  local skills = BuildOps.get_skills()
  return { ok = true, skills = skills }
end

handlers.set_tree = function(params)
  local ok2, err = BuildOps.set_tree(params or {})
  if not ok2 then
    return { ok = false, error = err }
  end
  local tree = BuildOps.get_tree()
  return { ok = true, tree = tree }
end

handlers.add_item_text = function(params)
  local res, err = BuildOps.add_item_text(params or {})
  if not res then return { ok = false, error = err } end
  return { ok = true, item = res }
end

handlers.export_build_xml = function(params)
  local xml, err = BuildOps.export_build_xml()
  if not xml then return { ok = false, error = err } end
  return { ok = true, xml = xml }
end

handlers.set_level = function(params)
  if not params or params.level == nil then
    return { ok = false, error = 'missing level' }
  end
  local ok2, err = BuildOps.set_level(params.level)
  if not ok2 then return { ok = false, error = err } end
  return { ok = true }
end

handlers.set_flask_active = function(params)
  local ok2, err = BuildOps.set_flask_active(params or {})
  if not ok2 then return { ok = false, error = err } end
  return { ok = true }
end

handlers.get_build_info = function(params)
  local info, err = BuildOps.get_build_info()
  if not info then return { ok = false, error = err } end
  return { ok = true, info = info }
end

handlers.update_tree_delta = function(params)
  local result, err = BuildOps.update_tree_delta(params or {})
  if not result then return { ok = false, error = err } end
  return {
    ok = true,
    tree = result.tree,
    restored = result.restored == true,
    restoredTree = result.restoredTree,
  }
end

handlers.calc_with = function(params)
  local out, base = BuildOps.calc_with(params or {})
  if not out then return { ok = false, error = base } end
  return { ok = true, output = out }
end

handlers.get_mastery_options = function(params)
  local result, err = BuildOps.get_mastery_options()
  if not result then return { ok = false, error = err } end
  return { ok = true, result = result }
end

handlers.get_config = function(params)
  local cfg, err = BuildOps.get_config()
  if not cfg then return { ok = false, error = err } end
  return { ok = true, config = cfg }
end

handlers.set_config = function(params)
  local result, err = BuildOps.set_config(params or {})
  if not result then return { ok = false, error = err } end
  local cfg = BuildOps.get_config()
  return {
    ok = true,
    config = cfg,
    appliedKeys = result.appliedKeys,
    aliasedKeys = result.aliasedKeys,
    ignoredKeys = result.ignoredKeys,
  }
end

handlers.create_socket_group = function(params)
  local res, err = BuildOps.create_socket_group(params or {})
  if not res then return { ok = false, error = err or 'failed to create socket group' } end
  return { ok = true, socketGroup = res }
end

handlers.add_gem = function(params)
  local res, err = BuildOps.add_gem(params or {})
  if not res then return { ok = false, error = err or 'failed to add gem' } end
  return { ok = true, gem = res }
end

handlers.set_gem_level = function(params)
  local ok2, err = BuildOps.set_gem_level(params or {})
  if not ok2 then return { ok = false, error = err or 'failed to set gem level' } end
  return { ok = true }
end

handlers.set_gem_quality = function(params)
  local ok2, err = BuildOps.set_gem_quality(params or {})
  if not ok2 then return { ok = false, error = err or 'failed to set gem quality' } end
  return { ok = true }
end

handlers.preview_gem_quality = function(params)
  local result, err = BuildOps.preview_gem_quality(params or {})
  if not result then return { ok = false, error = err or 'failed to preview gem quality' } end
  return { ok = true, result = result }
end

handlers.remove_skill = function(params)
  local ok2, err = BuildOps.remove_skill(params or {})
  if not ok2 then return { ok = false, error = err or 'failed to remove skill' } end
  return { ok = true }
end

handlers.remove_gem = function(params)
  local ok2, err = BuildOps.remove_gem(params or {})
  if not ok2 then return { ok = false, error = err or 'failed to remove gem' } end
  return { ok = true }
end

handlers.search_nodes = function(params)
  local res, err = BuildOps.search_nodes(params or {})
  if not res then return { ok = false, error = err or 'failed to search nodes' } end
  return { ok = true, results = res }
end

handlers.save_build = function(params)
  local res, err = BuildOps.save_build(params or {})
  if not res then return { ok = false, error = err or 'failed to save build' } end
  return { ok = true, result = res }
end

local function import_status_success(status, successText)
  return type(status) == 'string' and status:find(successText, 1, true) ~= nil
end

local function import_status_error(status, fallback)
  if type(status) ~= 'string' or #status == 0 then
    return fallback
  end
  -- Strip PoB colour escapes before returning the status over JSON-RPC.
  return (status:gsub('%^x%x%x%x%x%x%x', ''):gsub('%^%d', ''))
end

-- Import character passive tree + jewels from PoE official API JSON.
-- Caller fetches /character-window/get-passive-skills and forwards the raw
-- response body as params.json. params.char_data carries character metadata
-- required by ImportTab.lua (name, level, class, league).
handlers.import_passive_tree = function(params)
  if not _G.build or not _G.build.importTab then
    return { ok = false, error = 'no build loaded - call load_build_xml or new_build first' }
  end
  if not params or type(params.json) ~= 'string' or #params.json == 0 then
    return { ok = false, error = 'missing or empty json' }
  end
  if type(params.char_data) ~= 'table' then
    return { ok = false, error = 'missing char_data (need at least name, level, class, league)' }
  end

  local importTab = _G.build.importTab
  if params.clear_jewels ~= nil and importTab.controls and importTab.controls.charImportTreeClearJewels then
    importTab.controls.charImportTreeClearJewels.state = params.clear_jewels and true or false
  end

  local ok, err = pcall(function()
    importTab:ImportPassiveTreeAndJewels(params.json, params.char_data)
  end)
  if not ok then
    return { ok = false, error = 'ImportPassiveTreeAndJewels failed: ' .. tostring(err) }
  end
  if not import_status_success(importTab.charImportStatus, 'Passive tree and jewels successfully imported') then
    return {
      ok = false,
      error = 'ImportPassiveTreeAndJewels failed: ' .. import_status_error(importTab.charImportStatus, 'import did not report success'),
    }
  end

  return {
    ok = true,
    status = importTab.charImportStatus,
    level = _G.build.characterLevel,
    className = _G.build.spec and _G.build.spec.curClassName or nil,
    ascendClassName = _G.build.spec and _G.build.spec.curAscendClassName or nil,
  }
end

-- Import character items + skill gems from PoE official API JSON.
-- params.json is the raw body of /character-window/get-items.
handlers.import_items_skills = function(params)
  if not _G.build or not _G.build.importTab then
    return { ok = false, error = 'no build loaded - call load_build_xml or new_build first' }
  end
  if not params or type(params.json) ~= 'string' or #params.json == 0 then
    return { ok = false, error = 'missing or empty json' }
  end

  local importTab = _G.build.importTab
  local controls = importTab.controls or {}
  if params.clear_items ~= nil and controls.charImportItemsClearItems then
    controls.charImportItemsClearItems.state = params.clear_items and true or false
  end
  if params.clear_skills ~= nil and controls.charImportItemsClearSkills then
    controls.charImportItemsClearSkills.state = params.clear_skills and true or false
  end
  if params.ignore_weapon_swap ~= nil and controls.charImportItemsIgnoreWeaponSwap then
    controls.charImportItemsIgnoreWeaponSwap.state = params.ignore_weapon_swap and true or false
  end

  local ok, ret = pcall(function()
    return importTab:ImportItemsAndSkills(params.json)
  end)
  if not ok then
    return { ok = false, error = 'ImportItemsAndSkills failed: ' .. tostring(ret) }
  end
  if not import_status_success(importTab.charImportStatus, 'Items and skills successfully imported') then
    return {
      ok = false,
      error = 'ImportItemsAndSkills failed: ' .. import_status_error(importTab.charImportStatus, 'import did not report success'),
    }
  end

  -- The PoE API returns the character's currently active inventory under
  -- "Weapon"/"Offhand" and the swap set under "Weapon2"/"Offhand2".
  -- ImportTab maps those to primary and swap slots but does not update
  -- useSecondWeaponSet. Unless swap import is intentionally ignored, force the
  -- active item set back to primary slots so immediate calculations match the
  -- live character's active weapons.
  if not (params.ignore_weapon_swap and true or false) and _G.build.itemsTab and _G.build.itemsTab.activeItemSet then
    _G.build.itemsTab.activeItemSet.useSecondWeaponSet = false
    if _G.build.itemsTab.AddUndoState then
      pcall(function() _G.build.itemsTab:AddUndoState() end)
    end
    _G.build.buildFlag = true
  end

  local character = nil
  if type(ret) == 'table' then
    character = {
      name = ret.name,
      level = ret.level,
      class = ret.class,
      league = ret.league,
    }
  end

  return {
    ok = true,
    status = importTab.charImportStatus,
    level = _G.build.characterLevel,
    character = character,
  }
end

-- Generate a weighted trade query JSON via PoB's TradeQueryGenerator.
-- Drives the normally async coroutine to completion in headless mode.
-- Params:
--   slot          (string, required) — e.g. "Belt", "Ring 1", "Body Armour", "Helmet Abyssal Socket #1"
--   options       (table, optional)  — pass-through to StartQuery (statWeights, influence1, influence2,
--                                       jewelType, includeMirrored, includeCorrupted, includeScourge,
--                                       includeEldritch, includeSynthesis, maxPrice, maxPriceType,
--                                       maxLevel, sockets, links, special{itemName})
-- Returns: { ok=true, query=<json string>, warning?=<string> } or { ok=false, error=<string> }
handlers.generate_weighted_trade_query = function(params)
  if not _G.build or not _G.build.itemsTab then
    return { ok = false, error = 'no build loaded' }
  end
  if not params or type(params.slot) ~= 'string' then
    return { ok = false, error = 'missing slot' }
  end

  local itemsTab = _G.build.itemsTab
  local slot = itemsTab.slots and itemsTab.slots[params.slot]
  if not slot then
    return { ok = false, error = 'unknown slot: ' .. tostring(params.slot) }
  end
  if not itemsTab.tradeQuery then
    return { ok = false, error = 'trade query subsystem missing on itemsTab' }
  end
  -- TradeQueryGenerator is lazy-initialized inside TradeQueryClass:PriceItem()
  -- (the GUI "Price This Item" button handler). Instantiate it directly here
  -- so headless callers don't depend on GUI side effects.
  local generator = itemsTab.tradeQuery.tradeQueryGenerator
  if not generator then
    local ok_new, gen_or_err = pcall(_G.new, 'TradeQueryGenerator', itemsTab.tradeQuery)
    if not ok_new then
      return { ok = false, error = 'failed to instantiate TradeQueryGenerator: ' .. tostring(gen_or_err) }
    end
    generator = gen_or_err
    itemsTab.tradeQuery.tradeQueryGenerator = generator
  end

  -- Build options with defaults; caller can override any field.
  local options = {}
  if type(params.options) == 'table' then
    for k, v in pairs(params.options) do options[k] = v end
  end
  if options.statWeights == nil then
    options.statWeights = itemsTab.tradeQuery.statSortSelectionList
  end
  if not options.statWeights or #options.statWeights == 0 then
    -- Match the GUI's canonical default (TradeQuery.lua initStatSortSelectionList).
    options.statWeights = {
      { label = 'Full DPS',            stat = 'FullDPS',  weightMult = 1.0 },
      { label = 'Effective Hit Pool',  stat = 'TotalEHP', weightMult = 0.5 },
    }
  end
  if options.influence1 == nil then options.influence1 = 1 end
  if options.influence2 == nil then options.influence2 = 1 end
  if options.jewelType  == nil then options.jewelType  = 'Any' end
  if options.includeMirrored == nil then options.includeMirrored = false end

  -- Capture FinishQuery's callback output without touching the GUI.
  local resultJson, resultErr
  generator.requesterContext = {}
  generator.requesterCallback = function(_ctx, queryJson, errMsg)
    resultJson = queryJson
    resultErr = errMsg
  end

  -- Mock the popup API so headless mode doesn't blow up at OpenPopup/ClosePopup.
  local origOpen = _G.main and _G.main.OpenPopup
  local origClose = _G.main and _G.main.ClosePopup
  if _G.main then
    _G.main.OpenPopup = function() return { Close = function() end } end
    _G.main.ClosePopup = function() end
  end

  local ok, err = pcall(function() generator:StartQuery(slot, options) end)
  if not ok then
    if _G.main then _G.main.OpenPopup, _G.main.ClosePopup = origOpen, origClose end
    return { ok = false, error = 'StartQuery failed: ' .. tostring(err) }
  end

  -- Pump the coroutine to completion. Mod-weight loops can iterate thousands of times,
  -- but each :OnFrame() resumes the coroutine for one step, so we need a generous cap.
  local maxIters = 100000
  while generator.calcContext and generator.calcContext.co and maxIters > 0 do
    local ok2, err2 = pcall(function() generator:OnFrame() end)
    if not ok2 then
      if _G.main then _G.main.OpenPopup, _G.main.ClosePopup = origOpen, origClose end
      return { ok = false, error = 'coroutine resume failed: ' .. tostring(err2) }
    end
    maxIters = maxIters - 1
  end

  if _G.main then _G.main.OpenPopup, _G.main.ClosePopup = origOpen, origClose end

  if maxIters == 0 then
    return { ok = false, error = 'coroutine pump exceeded iteration cap' }
  end
  if not resultJson then
    return { ok = false, error = resultErr or 'query generation produced no result' }
  end

  return { ok = true, query = resultJson, warning = resultErr }
end

local anointHeadlineStats = {
  CombinedDPS = true,
  TotalDPS = true,
  FullDPS = true,
  FullDotDPS = true,
  SkillDPS = true,
  TotalEHP = true,
  EHP = true,
}

local anointDpsMetricOrder = { 'FullDPS', 'CombinedDPS', 'TotalDPS', 'MinionCombinedDPS', 'MinionTotalDPS' }

local function anoint_metric_value(output, metric)
  if type(output) ~= 'table' or type(metric) ~= 'string' then
    return 0
  end
  if metric == 'MinionCombinedDPS' then
    return (type(output.Minion) == 'table' and tonumber(output.Minion.CombinedDPS)) or tonumber(output.MinionCombinedDPS) or 0
  end
  if metric == 'MinionTotalDPS' then
    return (type(output.Minion) == 'table' and tonumber(output.Minion.TotalDPS)) or tonumber(output.MinionTotalDPS) or 0
  end
  return tonumber(output[metric]) or 0
end

local function choose_anoint_dps_metric(output)
  for _, metric in ipairs(anointDpsMetricOrder) do
    local value = anoint_metric_value(output, metric)
    if value > 0 then
      return metric, value
    end
  end
  return 'CombinedDPS', anoint_metric_value(output, 'CombinedDPS')
end

local function summarize_anoint_metrics(output, dpsMetric)
  return {
    DPS = anoint_metric_value(output, dpsMetric),
    CombinedDPS = anoint_metric_value(output, 'CombinedDPS'),
    TotalDPS = anoint_metric_value(output, 'TotalDPS'),
    FullDPS = anoint_metric_value(output, 'FullDPS'),
    MinionCombinedDPS = anoint_metric_value(output, 'MinionCombinedDPS'),
    MinionTotalDPS = anoint_metric_value(output, 'MinionTotalDPS'),
    TotalEHP = tonumber(output.TotalEHP) or tonumber(output.Life) or 0,
  }
end

local function copy_string_list(list)
  local result = {}
  if type(list) == 'table' then
    for _, value in ipairs(list) do
      if type(value) == 'string' then
        table.insert(result, value)
      end
    end
  end
  return result
end

local function get_item_anoint_names(item)
  local result = {}
  if item then
    for _, modList in ipairs({ item.enchantModLines, item.scourgeModLines, item.implicitModLines, item.explicitModLines, item.crucibleModLines }) do
      if type(modList) == 'table' then
        for _, mod in ipairs(modList) do
          local line = type(mod) == 'table' and mod.line
          local nodeName = type(line) == 'string' and line:match('^Allocates%s+(.+)$')
          if nodeName then
            table.insert(result, nodeName)
          end
        end
      end
    end
  end
  return result
end

local function find_tree_node_by_name(tree, name)
  if type(name) ~= 'string' or name == '' or type(tree) ~= 'table' then
    return nil, nil
  end
  local notableMap = tree.notableMap
  if type(notableMap) == 'table' then
    local mapped = notableMap[name:lower()]
    if mapped then
      return mapped.id, mapped
    end
  end
  for nodeId, node in pairs(tree.nodes or {}) do
    if node.dn == name then
      return nodeId, node
    end
  end
  return nil, nil
end

local function summarize_anoint_node(nodeId, node)
  if not node then
    return nil
  end
  return {
    nodeId = nodeId or node.id,
    name = node.dn,
    statLines = copy_string_list(node.sd),
    recipe = copy_string_list(node.recipe),
  }
end

local function anoint_match_flags(reqFlags, notFlags, flags)
  flags = flags or {}
  if type(reqFlags) == 'string' then
    reqFlags = { reqFlags }
  end
  if reqFlags then
    for _, flag in ipairs(reqFlags) do
      if not flags[flag] then
        return false
      end
    end
  end

  if type(notFlags) == 'string' then
    notFlags = { notFlags }
  end
  if notFlags then
    for _, flag in ipairs(notFlags) do
      if flags[flag] then
        return false
      end
    end
  end

  return true
end

local function add_anoint_stat_deltas(deltas, statList, currentOutput, candidateOutput, skillFlags, actorName)
  if type(statList) ~= 'table' or type(currentOutput) ~= 'table' or type(candidateOutput) ~= 'table' then
    return
  end
  local seen = {}
  for _, statData in ipairs(statList) do
    local stat = statData.stat
    local seenKey = tostring(stat) .. ':' .. tostring(statData.label)
    if stat and anoint_match_flags(statData.flag, statData.notFlag, skillFlags) and not anointHeadlineStats[stat] and not statData.childStat and stat ~= 'SkillDPS' and not seen[seenKey] then
      local current = tonumber(currentOutput[stat]) or 0
      local candidate = tonumber(candidateOutput[stat]) or 0
      local diff = candidate - current
      if (diff > 0.001 or diff < -0.001) and (not statData.condFunc or statData.condFunc(candidate, candidateOutput) or statData.condFunc(current, currentOutput)) then
        local scale = (statData.pc or statData.mod) and 100 or 1
        local percentDelta
        if statData.compPercent and current ~= 0 and candidate ~= 0 then
          percentDelta = candidate / current * 100 - 100
        end
        table.insert(deltas, {
          stat = stat,
          label = statData.label or stat,
          delta = diff * scale,
          current = current * scale,
          candidate = candidate * scale,
          percentDelta = percentDelta,
          actor = actorName,
          lowerIsBetter = statData.lowerIsBetter == true,
        })
        seen[seenKey] = true
      end
    end
  end
end

local function collect_anoint_stat_deltas(build, currentOutput, candidateOutput)
  local deltas = {}
  if not build or not build.calcsTab or not build.calcsTab.mainEnv then
    return deltas
  end
  local env = build.calcsTab.mainEnv
  if env.player then
    add_anoint_stat_deltas(deltas, build.displayStats, currentOutput, candidateOutput, env.player.mainSkill and env.player.mainSkill.skillFlags)
  end
  if env.player and env.player.mainSkill and env.player.mainSkill.minion and currentOutput.Minion and candidateOutput.Minion then
    add_anoint_stat_deltas(deltas, build.minionDisplayStats, currentOutput.Minion, candidateOutput.Minion, env.minion and env.minion.mainSkill and env.minion.mainSkill.skillFlags, 'Minion')
  end
  return deltas
end

-- Rank anointable notables by their DPS/EHP impact on the build, using PoB's
-- non-destructive MiscCalculator (same mechanism as the GUI's NotableDBControl
-- when sorting anoints in the item picker). Iterates every anointable notable
-- in the tree, simulates each via calcFunc({repSlotName, repItem=anointItem(node)}),
-- returns rankings sorted by combined score.
handlers.evaluate_anoint_candidates = function(params)
  if not _G.build or not _G.build.itemsTab or not _G.build.calcsTab or not _G.build.spec then
    return { ok = false, error = 'no build loaded' }
  end
  local itemsTab = _G.build.itemsTab
  local slotName = params and params.slot
  if type(slotName) ~= 'string' or slotName == '' then
    return { ok = false, error = 'missing slot (e.g. "Amulet" or "Belt")' }
  end

  local slot = itemsTab.slots and itemsTab.slots[slotName]
  if not slot then
    return { ok = false, error = 'unknown slot: ' .. tostring(slotName) }
  end
  local currentItem = itemsTab.items and itemsTab.items[slot.selItemId]
  if not currentItem then
    return { ok = false, error = 'no item equipped in slot: ' .. slotName }
  end

  local baseType = currentItem.base and currentItem.base.type
  if not baseType then
    return { ok = false, error = 'item has no base type' }
  end
  -- Anointable items: any Amulet, or specifically Cord Belt
  if baseType ~= 'Amulet' and not (baseType == 'Belt' and currentItem.baseName == 'Cord Belt') then
    return { ok = false, error = 'slot item is not anointable (must be Amulet or Cord Belt)' }
  end

  local focus = (params and params.focus) or 'both'
  if focus ~= 'dps' and focus ~= 'defence' and focus ~= 'both' then
    return { ok = false, error = 'invalid focus (use "dps", "defence", or "both")' }
  end
  local dpsWeight = (focus == 'defence') and 0 or 1
  local ehpWeight = (focus == 'dps') and 0 or 0.5

  -- SetDisplayItem so anointItem() reads the right base; restore at the end.
  local origDisplay = itemsTab.displayItem
  local origAnointSlot = itemsTab.anointEnchantSlot
  itemsTab:SetDisplayItem(currentItem)

  local calcFunc = _G.build.calcsTab:GetMiscCalculator()
  local ok_base, calcBase = pcall(calcFunc, { repSlotName = baseType, repItem = itemsTab:anointItem(nil) })
  if not ok_base or type(calcBase) ~= 'table' then
    itemsTab.displayItem = origDisplay
    itemsTab.anointEnchantSlot = origAnointSlot
    return { ok = false, error = 'baseline calc failed: ' .. tostring(calcBase) }
  end

  local dpsMetric, baseDPS = choose_anoint_dps_metric(calcBase)
  local baseEHP = tonumber(calcBase.TotalEHP) or tonumber(calcBase.Life) or 0

  local ok_current, calcCurrent = pcall(calcFunc, { repSlotName = baseType, repItem = currentItem })
  if not ok_current or type(calcCurrent) ~= 'table' then
    itemsTab.displayItem = origDisplay
    itemsTab.anointEnchantSlot = origAnointSlot
    return { ok = false, error = 'current anoint calc failed: ' .. tostring(calcCurrent) }
  end
  local currentDPS = anoint_metric_value(calcCurrent, dpsMetric)
  local currentEHP = tonumber(calcCurrent.TotalEHP) or tonumber(calcCurrent.Life) or 0

  local currentAnoints = get_item_anoint_names(currentItem)
  local currentAnoint = nil
  if currentAnoints[1] then
    local currentNodeId, currentNode = find_tree_node_by_name(_G.build.spec.tree, currentAnoints[1])
    currentAnoint = summarize_anoint_node(currentNodeId, currentNode) or { name = currentAnoints[1], statLines = {} }
    currentAnoint.dpsDelta = currentDPS - baseDPS
    currentAnoint.ehpDelta = currentEHP - baseEHP
    currentAnoint.dpsMetric = dpsMetric
  end

  local rankings = {}
  local evaluated = 0
  local skipped = 0
  for nodeId, node in pairs(_G.build.spec.tree.nodes) do
    -- Anointable: has a recipe (oil combo). Skip nodes already allocated.
    if node.recipe and #node.recipe >= 1 and not (_G.build.spec.allocNodes and _G.build.spec.allocNodes[nodeId]) then
      local ok_eval, output = pcall(calcFunc, { repSlotName = baseType, repItem = itemsTab:anointItem(node) })
      if ok_eval and type(output) == 'table' then
        local newDPS = anoint_metric_value(output, dpsMetric)
        local newEHP = tonumber(output.TotalEHP) or tonumber(output.Life) or 0
        local dpsDelta = newDPS - baseDPS
        local ehpDelta = newEHP - baseEHP
        local swapDpsDelta = newDPS - currentDPS
        local swapEhpDelta = newEHP - currentEHP
        local score = 0
        if baseDPS > 0 then score = score + (dpsDelta / baseDPS) * dpsWeight end
        if baseEHP > 0 then score = score + (ehpDelta / baseEHP) * ehpWeight end
        table.insert(rankings, {
          nodeId = nodeId,
          name = node.dn,
          statLines = copy_string_list(node.sd),
          dpsDelta = dpsDelta,
          ehpDelta = ehpDelta,
          swapDpsDelta = swapDpsDelta,
          swapEhpDelta = swapEhpDelta,
          dpsMetric = dpsMetric,
          score = score,
          recipe = node.recipe,
          statDeltas = collect_anoint_stat_deltas(_G.build, calcCurrent, output),
        })
        evaluated = evaluated + 1
      else
        skipped = skipped + 1
      end
    end
  end

  -- Restore original display item state
  itemsTab.displayItem = origDisplay
  itemsTab.anointEnchantSlot = origAnointSlot

  table.sort(rankings, function(a, b) return a.score > b.score end)

  local limit = tonumber(params and params.limit) or 20
  if limit > 0 and limit < #rankings then
    local truncated = {}
    for i = 1, limit do truncated[i] = rankings[i] end
    rankings = truncated
  end

  return {
    ok = true,
    candidates = rankings,
    dpsMetric = dpsMetric,
    base = summarize_anoint_metrics(calcBase, dpsMetric),
    current = summarize_anoint_metrics(calcCurrent, dpsMetric),
    currentAnoint = currentAnoint,
    currentAnointDetected = currentAnoint ~= nil,
    evaluated = evaluated,
    skipped = skipped,
    slot = slotName,
    baseType = baseType,
    focus = focus,
  }
end

return {
  handlers = handlers,
  version_meta = version_meta,
}
