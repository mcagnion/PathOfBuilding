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
  local ok2, err = BuildOps.update_tree_delta(params or {})
  if not ok2 then return { ok = false, error = err } end
  local tree = BuildOps.get_tree()
  return { ok = true, tree = tree }
end

handlers.calc_with = function(params)
  local out, base = BuildOps.calc_with(params or {})
  if not out then return { ok = false, error = base } end
  return { ok = true, output = out }
end

handlers.get_config = function(params)
  local cfg, err = BuildOps.get_config()
  if not cfg then return { ok = false, error = err } end
  return { ok = true, config = cfg }
end

handlers.set_config = function(params)
  local ok2, err = BuildOps.set_config(params or {})
  if not ok2 then return { ok = false, error = err } end
  local cfg = BuildOps.get_config()
  return { ok = true, config = cfg }
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

local DEFAULT_RANK_STAT_WEIGHTS = {
  { label = 'Full DPS',           stat = 'FullDPS',  weightMult = 1.0 },
  { label = 'Effective Hit Pool', stat = 'TotalEHP', weightMult = 0.5 },
}

local VALID_RANK_SORT_MODES = {
  StatValue      = true,
  StatValuePrice = true,
  Price          = true,
  Weight         = true,
}

handlers.rank_trade_results = function(params)
  if not _G.build or not _G.build.itemsTab then
    return { ok = false, error = 'no build loaded' }
  end
  if type(params) ~= 'table' then
    return { ok = false, error = 'missing params' }
  end
  if type(params.slot) ~= 'string' or params.slot == '' then
    return { ok = false, error = 'missing slot' }
  end
  if type(params.items) ~= 'table' then
    return { ok = false, error = 'missing items array' }
  end

  local sortMode = params.sortMode or 'StatValue'
  if not VALID_RANK_SORT_MODES[sortMode] then
    return { ok = false, error = 'invalid sortMode: ' .. tostring(sortMode) ..
      ' (allowed: StatValue, StatValuePrice, Price, Weight)' }
  end

  local itemsTab = _G.build.itemsTab
  local slot = itemsTab.slots and itemsTab.slots[params.slot]
  if not slot then
    return { ok = false, error = 'unknown slot: ' .. tostring(params.slot) }
  end

  local statWeights = params.statWeights
  if not statWeights or type(statWeights) ~= 'table' or #statWeights == 0 then
    statWeights = DEFAULT_RANK_STAT_WEIGHTS
  end

  local genCls = _G.common and _G.common.classes and _G.common.classes.TradeQueryGenerator
  if not genCls or type(genCls.WeightedRatioOutputs) ~= 'function' then
    return { ok = false, error = 'TradeQueryGenerator.WeightedRatioOutputs not available' }
  end

  if not _G.build.calcsTab or type(_G.build.calcsTab.GetMiscCalculator) ~= 'function' then
    return { ok = false, error = 'calcsTab.GetMiscCalculator not available' }
  end
  local calcFunc, baseOutput = _G.build.calcsTab:GetMiscCalculator()
  if type(calcFunc) ~= 'function' or type(baseOutput) ~= 'table' then
    return { ok = false, error = 'GetMiscCalculator returned no calculator' }
  end

  local stripEnchants = params.stripEnchants
  if stripEnchants == nil then stripEnchants = true end

  local function getEntryPriceChaos(entry)
    if type(entry.price) ~= 'table' then return nil end
    local chaos = entry.price.chaos
    if type(chaos) == 'number' and chaos > 0 then return chaos end
    return nil
  end

  local scored = {}
  for i, entry in ipairs(params.items) do
    local item_string = type(entry) == 'table' and (entry.item_string or entry.itemString) or nil
    if type(item_string) ~= 'string' or item_string == '' then
      return { ok = false, error = 'items[' .. i .. '] missing item_string' }
    end
    local rec = {
      index = i,
      weight = 0,
      deltas = {},
      price = (type(entry) == 'table' and entry.price) or nil,
    }
    local ok_item, item_or_err = pcall(_G.new, 'Item', item_string)
    if not ok_item or not item_or_err then
      rec.error = 'failed to parse item: ' .. tostring(item_or_err)
    else
      local item = item_or_err
      if stripEnchants then
        item.enchantModLines = {}
        if type(item.BuildAndParseRaw) == 'function' then
          pcall(item.BuildAndParseRaw, item)
        end
      end
      local ok_calc, output = pcall(calcFunc, { repSlotName = params.slot, repItem = item })
      if not ok_calc or type(output) ~= 'table' then
        rec.error = 'calcFunc failed: ' .. tostring(output)
      else
        local ok_w, weight = pcall(genCls.WeightedRatioOutputs, baseOutput, output, statWeights)
        if ok_w and type(weight) == 'number' then
          rec.weight = weight
        else
          rec.error = 'WeightedRatioOutputs failed: ' .. tostring(weight)
        end
        for _, sw in ipairs(statWeights) do
          local key = sw.stat
          if type(key) == 'string' then
            rec.deltas[key] = (output[key] or 0) - (baseOutput[key] or 0)
          end
        end
      end
    end
    table.insert(scored, rec)
  end

  if sortMode == 'StatValue' then
    table.sort(scored, function(a, b) return (a.weight or 0) > (b.weight or 0) end)
  elseif sortMode == 'StatValuePrice' then
    -- Mirrors TradeQueryClass:SortFetchResults StatValuePrice branch
    -- (TradeQuery.lua:836-844): outputAttr = getResultWeight(idx) / priceTable[idx].
    -- Falls back to StatValue if any candidate is missing chaos-equivalent price,
    -- matching the GUI's "MissingConversionRates" notice.
    local missingPrice = false
    for _, s in ipairs(scored) do
      if not getEntryPriceChaos(s) then missingPrice = true; break end
    end
    if missingPrice then
      table.sort(scored, function(a, b) return (a.weight or 0) > (b.weight or 0) end)
      sortMode = 'StatValue'
    else
      for _, s in ipairs(scored) do
        local chaos = getEntryPriceChaos(s)
        s.statValuePerPrice = chaos and ((s.weight or 0) / chaos) or 0
      end
      table.sort(scored, function(a, b) return (a.statValuePerPrice or 0) > (b.statValuePerPrice or 0) end)
    end
  elseif sortMode == 'Price' then
    -- Mirrors TradeQueryClass:SortFetchResults Price branch: ascending chaos price.
    -- Falls back to StatValue if no candidate has chaos-equivalent price (GUI's
    -- "MissingConversionRates" notice equivalent — order by build-impact instead
    -- of dumping every item at math.huge).
    local missingPrice = false
    for _, s in ipairs(scored) do
      if not getEntryPriceChaos(s) then missingPrice = true; break end
    end
    if missingPrice then
      table.sort(scored, function(a, b) return (a.weight or 0) > (b.weight or 0) end)
      sortMode = 'StatValue'
    else
      table.sort(scored, function(a, b)
        local pa = getEntryPriceChaos(a) or math.huge
        local pb = getEntryPriceChaos(b) or math.huge
        return pa < pb
      end)
    end
  end
  -- Weight mode: keep input order

  return { ok = true, ranked = scored, sortMode = sortMode }
end

return {
  handlers = handlers,
  version_meta = version_meta,
}
