-- Path of Building
--
-- Class: Stash Loader
-- Fetches stash tab contents from the Path of Exile character-window API
-- and feeds each item into the build's stashDB for browsing/sorting.
--
local dkjson = require "dkjson"
local t_insert = table.insert
local s_format = string.format

local stashApiHost = "https://www.pathofexile.com/character-window/get-stash-items"
local profileApiHost = "https://www.pathofexile.com/"
-- GGG V2 stash API. The per-stash fetch /stash/<league>/<id> accepts POESESSID
-- cookie auth (verified 2026-04-23) and is the only way to retrieve UniqueStash
-- contents. The listing /stash/<league> requires an OAuth Bearer token with
-- scope account:stashes (confirmed by GGG docs and 403 under POESESSID + headers),
-- so tab listing stays on the legacy /character-window path until a proper
-- OAuth flow is added in a future branch.
local altStashApiHost = "https://api.pathofexile.com/stash"

local realmCodeList = { "pc", "xbox", "sony" }
local profileURLList = { "account/view-profile/", "account/xbox/view-profile/", "account/sony/view-profile/" }

-- Stash tab types that can contain items PoB understands. Other types (Currency,
-- Map, Fragment, Divination, Blight, Delve, Essence, etc.) return items without
-- a base PoB recognises, so loading them wastes API calls and shows nothing.
local supportedStashTypes = {
	NormalStash = true,
	PremiumStash = true,
	QuadStash = true,
	FlaskStash = true,
	UniqueStash = true,
	GemStash = true,
}

local function urlEscape(value)
	return (value or ""):gsub("#", "%%23"):gsub(" ", "+")
end

local function parseStatus(header)
	return header and header:match("HTTP/[%d%.]+ (%d+)") or ""
end

-- Minimum seconds between successive V2 (api.pathofexile.com/stash/*) fetches
-- to stay under GGG's per-IP rate limit. Empirically 12 back-to-back sub-stash
-- fetches on a UniqueStash tab triggered immediate 429s, so we gate them.
local V2_MIN_GAP_SECONDS = 2

local StashLoaderClass = newClass("StashLoader", function(self, itemsTab)
	self.itemsTab = itemsTab
	self.build = itemsTab.build
	self.accountName = main.lastAccountName or ""
	self.realmIndex = 1
	self.league = ""
	self.tabs = { }
	self.v2Queue = { }
	self.v2LastFire = 0
	main.onFrameFuncs["StashLoader_" .. tostring(self)] = function()
		self:ProcessV2Queue()
	end
end)

function StashLoaderClass:ProcessV2Queue()
	self:UpdateProgressLine()
	if #self.v2Queue == 0 then return end
	local now = os.time()
	if now - self.v2LastFire < V2_MIN_GAP_SECONDS then return end
	local entry = table.remove(self.v2Queue, 1)
	self.v2LastFire = now
	entry.run()
end

function StashLoaderClass:EnqueueV2Fetch(parentId, subId, tabName, onDone)
	t_insert(self.v2Queue, {
		run = function()
			self:FetchTabViaV2(parentId, subId, tabName, onDone)
		end,
	})
end

function StashLoaderClass:OpenTabSelector(onLoaded)
	self.onLoaded = onLoaded
	self:OpenInputPopup()
end

function StashLoaderClass:OpenInputPopup()
	local controls = { }
	controls.sessionStatus = new("LabelControl", nil, {0, 16, 0, 16},
		(main.POESESSID and main.POESESSID ~= "")
			and "^8POESESSID is set."
			or "^1POESESSID is not set. Set it from the TradeQuery panel first.")
	controls.accountLabel = new("LabelControl", nil, {-150, 44, 0, 16}, "^7Account name:")
	controls.accountInput = new("EditControl", nil, {40, 42, 240, 20}, self.accountName, nil, "%c", nil, nil, nil, nil, true)
	controls.accountInput.pasteFilter = function(text)
		return text:gsub(".", function(c)
			local byte = c:byte()
			return byte >= 128 and s_format("%%%02X", byte) or c
		end)
	end
	controls.realmLabel = new("LabelControl", nil, {-150, 70, 0, 16}, "^7Realm:")
	controls.realmInput = new("DropDownControl", nil, {40, 68, 120, 20}, { "PC", "Xbox", "Sony" })
	controls.realmInput.selIndex = self.realmIndex
	controls.leagueLabel = new("LabelControl", nil, {-150, 96, 0, 16}, "^7League:")
	controls.leagueInput = new("EditControl", nil, {40, 94, 175, 20}, self.league, nil, "%c")
	controls.leagueDetect = new("ButtonControl", {"LEFT", controls.leagueInput, "RIGHT"}, {4, 0, 60, 20}, "Detect", function()
		local accountName = controls.accountInput.buf
		local realmIdx = controls.realmInput.selIndex
		if not main.POESESSID or main.POESESSID == "" then
			main:OpenMessagePopup("POESESSID required", "POESESSID is not set.\nOpen the TradeQuery panel to set it.")
			return
		end
		if accountName == "" then
			main:OpenMessagePopup("Missing input", "Enter an account name first.")
			return
		end
		self:OpenStatusPopup("Detecting leagues...")
		self:FetchLeaguesForAccount(accountName, realmCodeList[realmIdx], function(leagues, errMsg)
			main:ClosePopup()
			if errMsg then
				self:OpenAuthErrorPopup("Detect failed", tostring(errMsg))
				return
			end
			self:OpenLeaguePicker(leagues, function(league)
				controls.leagueInput:SetText(league)
			end)
		end)
	end)
	controls.hint = new("LabelControl", nil, {0, 124, 0, 14},
		"^x7F7F7FAccount name must include discriminator (e.g. PlayerName#1234).")
	controls.fetch = new("ButtonControl", nil, {-60, 154, 120, 20}, "Fetch tabs", function()
		self.accountName = controls.accountInput.buf
		self.realmIndex = controls.realmInput.selIndex
		self.league = controls.leagueInput.buf
		if not main.POESESSID or main.POESESSID == "" then
			main:OpenMessagePopup("POESESSID required", "POESESSID is not set.\nOpen the TradeQuery panel to set it.")
			return
		end
		if self.accountName == "" or self.league == "" then
			main:OpenMessagePopup("Missing input", "Account name and league are required.")
			return
		end
		main:ClosePopup()
		self:FetchTabList()
	end)
	controls.cancel = new("ButtonControl", nil, {70, 154, 100, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(420, 190, "Load stash tabs", controls, "fetch", nil, "cancel")
end

function StashLoaderClass:FetchLeaguesForAccount(accountName, realm, onDone)
	local url = s_format("https://www.pathofexile.com/character-window/get-characters?accountName=%s&realm=%s",
		urlEscape(accountName), realm)
	launch:DownloadPage(url, function(response, errMsg)
		if errMsg then
			onDone(nil, errMsg)
			return
		end
		local status = parseStatus(response.header)
		if status == "401" or status == "403" then
			onDone(nil, "Access denied: POESESSID invalid or profile private.")
			return
		end
		if status == "404" then
			onDone(nil, "Account name not found.")
			return
		end
		local chars = dkjson.decode(response.body)
		if type(chars) ~= "table" then
			onDone(nil, "Invalid characters response.")
			return
		end
		local leagueSet = { }
		local leagues = { }
		for _, char in ipairs(chars) do
			if char.league and not leagueSet[char.league] then
				leagueSet[char.league] = true
				t_insert(leagues, char.league)
			end
		end
		table.sort(leagues)
		onDone(leagues)
	end, { header = "Cookie: POESESSID=" .. main.POESESSID })
end

function StashLoaderClass:OpenLeaguePicker(leagues, onPicked)
	if not leagues or #leagues == 0 then
		main:OpenMessagePopup("No leagues", "No characters found on this account/realm.")
		return
	end
	if #leagues == 1 then
		onPicked(leagues[1])
		return
	end
	local controls = { }
	controls.header = new("LabelControl", nil, {0, 16, 0, 16}, "^7Pick a league:")
	for idx, league in ipairs(leagues) do
		local y = 40 + (idx - 1) * 24
		controls["pick"..idx] = new("ButtonControl", nil, {0, y, 260, 20}, league, function()
			main:ClosePopup()
			onPicked(league)
		end)
	end
	local cancelY = 40 + #leagues * 24 + 8
	controls.cancel = new("ButtonControl", nil, {0, cancelY, 80, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(300, cancelY + 36, "Select league", controls, nil, nil, "cancel")
end

-- Resolves the canonical (correctly-cased) account name by scraping the public
-- profile page. Required because GGG's /get-characters is case-insensitive but
-- /get-stash-items is case-sensitive, so a mis-cased account silently returns
-- empty stash data.
function StashLoaderClass:ResolveCanonicalAccountName(accountName, realmIdx, onDone)
	if self._canonicalAccount and self._canonicalRealm == realmIdx and self._canonicalSource == accountName then
		return onDone(self._canonicalAccount)
	end
	local url = profileApiHost .. profileURLList[realmIdx] .. urlEscape(accountName)
	launch:DownloadPage(url, function(response, errMsg)
		if errMsg then return onDone(nil, errMsg) end
		local status = parseStatus(response.header)
		if status == "404" then return onDone(nil, "Account name not found.") end
		if status == "403" or status == "401" then
			return onDone(nil, "Profile is private. Enable characters in the account privacy settings.")
		end
		local canonical = response.body and response.body:match("/view%-profile/([^/]+)/characters")
		if not canonical then
			return onDone(nil, "Could not extract a canonical account name from the profile page.")
		end
		canonical = canonical:gsub(".", function(c)
			return c:byte(1) > 127 and s_format("%%%02X", c:byte(1)) or c
		end)
		canonical = canonical:gsub("(.*)[#%-]", "%1#")
		self._canonicalAccount = canonical
		self._canonicalRealm = realmIdx
		self._canonicalSource = accountName
		onDone(canonical)
	end, { header = "Cookie: POESESSID=" .. main.POESESSID })
end

function StashLoaderClass:FetchTabList()
	self:OpenStatusPopup("Resolving account name...")
	self:ResolveCanonicalAccountName(self.accountName, self.realmIndex, function(canonical, err)
		if err then
			main:ClosePopup()
			self:OpenAuthErrorPopup("Account lookup failed",
				"Could not resolve the canonical account name:\n"..tostring(err))
			return
		end
		self.accountName = canonical
		self:SetStatus("Fetching stash tab list...")
		self:DoFetchTabList()
	end)
end

function StashLoaderClass:DoFetchTabList()
	local url = s_format("%s?accountName=%s&league=%s&tabs=1&tabIndex=0",
		stashApiHost, urlEscape(self.accountName), urlEscape(self.league))
	launch:DownloadPage(url, function(response, errMsg)
		main:ClosePopup()
		if errMsg then
			main:OpenMessagePopup("Stash fetch failed",
				s_format("Could not fetch stash tabs:\n%s\n\nURL: %s", tostring(errMsg), url))
			return
		end
		local status = parseStatus(response.header)
		if status == "403" or status == "401" then
			self:OpenAuthErrorPopup("Access denied",
				"Your POESESSID or account name is invalid, or the stash is private.")
			return
		end
		if status == "429" then
			main:OpenMessagePopup("Rate limited", "The stash API is rate-limiting requests. Wait a minute and try again.")
			return
		end
		local data = dkjson.decode(response.body)
		if not data or not data.tabs then
			main:OpenMessagePopup("Invalid response", "The stash response did not contain a tab list.")
			return
		end
		self.tabs = { }
		local hiddenCount, unsupportedCount = 0, 0
		for _, tab in ipairs(data.tabs) do
			if tab.hidden then
				hiddenCount = hiddenCount + 1
			elseif not supportedStashTypes[tab.type] then
				unsupportedCount = unsupportedCount + 1
			else
				t_insert(self.tabs, {
					index = tab.i,
					name = tab.n,
					type = tab.type,
					id = tab.id,
					colour = tab.colour,
				})
			end
		end
		self.skippedTabsSummary = (hiddenCount > 0 or unsupportedCount > 0)
			and s_format("^x7F7F7F(%d hidden, %d unsupported type skipped)", hiddenCount, unsupportedCount)
			or nil
		if #self.tabs == 0 then
			main:OpenMessagePopup("No tabs",
				s_format("No loadable stash tabs on this account/realm/league.\n%d hidden, %d unsupported types.",
					hiddenCount, unsupportedCount))
			return
		end
		self:OpenTabListPopup()
	end, { header = "Cookie: POESESSID=" .. main.POESESSID })
end

function StashLoaderClass:OpenTabListPopup()
	local controls = { }
	controls.header = new("LabelControl", nil, {0, 12, 0, 16},
		s_format("^7Select which stash tabs to load (%d available): %s",
			#self.tabs, self.skippedTabsSummary or ""))
	local rowHeight = 22
	local colWidth = 300
	-- Adapt columns to tab count: up to 20 rows per column, cap at 4 columns.
	-- Anything bigger (> 80 tabs) gets packed into 4 taller columns; for really
	-- enormous stashes the Cancel/Load buttons stay in view via popup padding.
	local maxRowsPerCol = 20
	local maxCols = 4
	local cols = math.min(maxCols, math.max(1, math.ceil(#self.tabs / maxRowsPerCol)))
	local rowsPerCol = math.ceil(#self.tabs / cols)
	local popupWidth = math.max(460, 40 + cols * colWidth)
	-- Anchor each checkbox near the RIGHT edge of its column so its label
	-- (which PoB's CheckBoxControl draws to the LEFT of the square) fits
	-- within the column width. See retro item 65 on the checkbox anchor gotcha.
	local xBase = -popupWidth / 2 + colWidth - 20
	self.tabChecks = { }
	for idx, tab in ipairs(self.tabs) do
		local col = math.floor((idx - 1) / rowsPerCol)
		local row = (idx - 1) % rowsPerCol
		local c = tab.colour
		local colourCode = "^7"
		if type(c) == "string" then
			colourCode = "^x" .. c:upper()
		elseif type(c) == "table" then
			colourCode = s_format("^x%02X%02X%02X", c.r or 255, c.g or 255, c.b or 255)
		end
		local label = s_format(" [%d] %s%s  ^x7F7F7F(%s)", tab.index, colourCode, tab.name, tab.type or "")
		local x = xBase + col * colWidth
		local y = 36 + row * rowHeight
		local key = "cb"..idx
		controls[key] = new("CheckBoxControl", nil, {x, y, 18}, label, nil, nil, false)
		t_insert(self.tabChecks, controls[key])
	end
	local listHeight = rowsPerCol * rowHeight
	local buttonY = 36 + listHeight + 16
	controls.selectAll = new("ButtonControl", nil, {-170, buttonY, 100, 20}, "Select all", function()
		for _, cb in ipairs(self.tabChecks) do cb.state = true end
	end)
	controls.clearAll = new("ButtonControl", nil, {-60, buttonY, 100, 20}, "Clear all", function()
		for _, cb in ipairs(self.tabChecks) do cb.state = false end
	end)
	controls.loadBtn = new("ButtonControl", nil, {60, buttonY, 120, 20}, "Load selected", function()
		local selected = { }
		for idx, cb in ipairs(self.tabChecks) do
			if cb.state then
				t_insert(selected, self.tabs[idx])
			end
		end
		if #selected == 0 then
			main:OpenMessagePopup("No selection", "Check at least one stash tab.")
			return
		end
		main:ClosePopup()
		self:FetchSelectedTabs(selected)
	end)
	controls.cancel = new("ButtonControl", nil, {180, buttonY, 80, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(popupWidth, buttonY + 40, "Select stash tabs", controls, "loadBtn", nil, "cancel")
end

function StashLoaderClass:OpenAuthErrorPopup(title, message)
	local controls = { }
	local numLines = 0
	for line in string.gmatch(message .. "\n", "([^\n]*)\n") do
		t_insert(controls, new("LabelControl", nil, {0, 20 + numLines * 16, 0, 16}, line))
		numLines = numLines + 1
	end
	local buttonY = 40 + numLines * 16
	controls.privacy = new("ButtonControl", nil, {-80, buttonY, 140, 20}, "Privacy Settings", function()
		OpenURL("https://www.pathofexile.com/my-account/privacy")
	end)
	controls.close = new("ButtonControl", nil, {80, buttonY, 80, 20}, "OK", function()
		main:ClosePopup()
	end)
	main:OpenPopup(360, buttonY + 40, title, controls, "close")
end

function StashLoaderClass:OpenStatusPopup(message)
	local controls = { }
	controls.status = new("LabelControl", nil, {0, 18, 0, 16}, "^7"..message)
	controls.progress = new("LabelControl", nil, {0, 42, 0, 14}, "")
	self.statusControl = controls.status
	self.progressControl = controls.progress
	main:OpenPopup(520, 80, "Stash loader", controls)
	self:UpdateProgressLine()
end

function StashLoaderClass:SetStatus(message)
	if self.statusControl then
		self.statusControl.label = "^7"..message
	end
	self:UpdateProgressLine()
end

function StashLoaderClass:UpdateProgressLine()
	if not self.progressControl then return end
	if not self.loadResult then
		self.progressControl.label = ""
		return
	end
	local parts = { s_format("^7Added: %d", self.loadResult.added) }
	if self.loadResult.replaced > 0 then
		t_insert(parts, s_format("^7Replaced: %d", self.loadResult.replaced))
	end
	if self.loadResult.errors > 0 then
		t_insert(parts, s_format("^1Errors: %d", self.loadResult.errors))
	end
	if self.v2Queue and #self.v2Queue > 0 then
		local waitSeconds = math.max(0, V2_MIN_GAP_SECONDS - (os.time() - (self.v2LastFire or 0)))
		t_insert(parts, s_format("^x7F7F7FQueue: %d (next in ~%ds)", #self.v2Queue, waitSeconds))
	end
	self.progressControl.label = table.concat(parts, "   ")
end

function StashLoaderClass:FetchSelectedTabs(selected)
	self.loadResult = { added = 0, errors = 0, replaced = 0 }
	self:OpenStatusPopup(s_format("Loading tab 1 of %d...", #selected))
	self:FetchNextTab(selected, 1)
end

function StashLoaderClass:FetchNextTab(selected, index)
	if index > #selected then
		main:ClosePopup()
		main:OpenMessagePopup("Stash loaded",
			s_format("Added %d items, replaced %d, %d errors.",
				self.loadResult.added, self.loadResult.replaced, self.loadResult.errors))
		if self.onLoaded then self.onLoaded() end
		return
	end
	local tab = selected[index]
	self:SetStatus(s_format("Loading tab %d of %d: %s", index, #selected, tab.name))
	self:EnqueueV2Fetch(tab.id, nil, tab.name, function()
		self:FetchNextTab(selected, index + 1)
	end)
end

-- V2 stash API: api.pathofexile.com/stash/<league>/<stashId>[/<subStashId>]
-- Returns { stash: { id, type, items?, children? } }. Folder stashes (notably
-- UniqueStash) have a `children` array of sub-stash descriptors; fetch each
-- one recursively to aggregate items.
function StashLoaderClass:FetchTabViaV2(parentId, subId, tabName, onDone)
	local suffix = subId and ("/" .. subId) or ""
	local url = s_format("%s/%s/%s%s", altStashApiHost,
		urlEscape(self.league), parentId, suffix)
	launch:DownloadPage(url, function(response, errMsg)
		local status = response and response.header and parseStatus(response.header) or ""
		-- launch:DownloadPage surfaces non-2xx as errMsg ("Response code: N"),
		-- so we detect 429 there before the generic error branch runs.
		if status == "429" or (errMsg and errMsg:find("429")) then
			main:ClosePopup()
			main:OpenMessagePopup("Rate limited",
				s_format("GGG's stash API rate-limited us while loading '%s'.\nAdded %d items so far. Wait a minute and try again.",
					tabName, self.loadResult.added))
			if self.onLoaded then self.onLoaded() end
			return
		end
		if errMsg then
			ConPrintf("StashLoader: V2 fetch error for tab '%s' (sub=%s): %s | status=%s",
				tabName, tostring(subId), tostring(errMsg), status ~= "" and status or "n/a")
			self.loadResult.errors = self.loadResult.errors + 1
			onDone()
			return
		end
		local data = dkjson.decode(response.body)
		local stash = data and data.stash
		if not stash then
			ConPrintf("StashLoader: V2 no-stash payload for tab '%s' (sub=%s): body sample: %s",
				tabName, tostring(subId), (response.body or ""):sub(1, 300))
			self.loadResult.errors = self.loadResult.errors + 1
			onDone()
			return
		end
		if stash.items then
			for _, itemData in ipairs(stash.items) do
				self:AddItemFromApiData(itemData, tabName)
			end
		end
		if stash.children and not subId then
			self:FetchV2Children(parentId, stash.children, 1, tabName, onDone)
		else
			onDone()
		end
	end, { header = "Cookie: POESESSID=" .. main.POESESSID })
end

function StashLoaderClass:FetchV2Children(parentId, children, index, tabName, onDone)
	if index > #children then
		onDone()
		return
	end
	local child = children[index]
	self:SetStatus(s_format("Loading '%s' sub-stash %d of %d...", tabName, index, #children))
	self:EnqueueV2Fetch(parentId, child.id, tabName, function()
		self:FetchV2Children(parentId, children, index + 1, tabName, onDone)
	end)
end

function StashLoaderClass:AddItemFromApiData(itemData, tabName)
	local item = self.build.importTab:BuildItemFromApiData(itemData)
	if not item then
		return
	end
	item.stashTab = tabName
	local list = self.itemsTab.stashDB.list
	if item.uniqueID then
		for id, existing in pairs(list) do
			if existing.uniqueID == item.uniqueID then
				item.id = id
				list[id] = item
				self.loadResult.replaced = self.loadResult.replaced + 1
				return
			end
		end
	end
	local nextId = (self.nextStashId or 0) + 1
	while list[nextId] do
		nextId = nextId + 1
	end
	self.nextStashId = nextId
	item.id = nextId
	list[nextId] = item
	self.loadResult.added = self.loadResult.added + 1
end
