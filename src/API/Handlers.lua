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

return {
  handlers = handlers,
  version_meta = version_meta,
}
