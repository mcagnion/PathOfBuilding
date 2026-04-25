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

return {
  handlers = handlers,
  version_meta = version_meta,
}
