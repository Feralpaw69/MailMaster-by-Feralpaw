-- MailMaster by feralpaw - core: settings, events, timers, themes, helpers
local ADDON, MM = ...
_G.MailMaster = MM
MM.version = GetAddOnMetadata(ADDON, "Version") or "?"

local floor, format, tinsert, tremove = floor, format, tinsert, tremove

------------------------------------------------------------------------
-- Defaults
------------------------------------------------------------------------
MM.defaults = {
	speed = 0.03,        -- seconds between two take/return requests
	keepFree = 1,        -- bag slots to keep free when taking items
	verbose = false,     -- print every mail while opening
	chatFrame = 1,
	filters = {
		AHSold = true, AHExpired = true, AHCancelled = true, AHOutbid = true, AHWon = true,
		PlayerItems = true, PlayerGold = true, System = true,
	},
	expiryDays = 3,
	checkboxes = true,
	deleteButton = true,
	confirmDelete = true,
	summary = true,
	rake = true,
	slide = true,
	slideAutoSend = false,
	wire = true,
	codHelper = true,
	contacts = true,
	autocomplete = true,
	blockTrade = true,
	blockGuild = true,
	blockParty = false,
	rulesAuto = false,
	rulesTest = true,
	queueAuto = true,
	sentKeep = 10,
	minimap = true,
	versionCheck = true,
	minimapAngle = 200,
	theme = "Gold",
	folded = {},
}

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end
MM.CopyDefaults = CopyDefaults

------------------------------------------------------------------------
-- Events (one frame, handler lists)
------------------------------------------------------------------------
local evFrame = CreateFrame("Frame")
local handlers = {}
function MM:On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		evFrame:RegisterEvent(event)
	end
	list[#list + 1] = fn
end
evFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	for i = 1, #list do list[i](...) end
end)

------------------------------------------------------------------------
-- Timers (OnUpdate only runs while something is scheduled)
------------------------------------------------------------------------
local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
local timers = {}
timerFrame:SetScript("OnUpdate", function(self)
	local now = GetTime()
	local i = 1
	while i <= #timers do
		local t = timers[i]
		if t.cancelled then
			tremove(timers, i)
		elseif now >= t.at then
			tremove(timers, i)
			t.fn()
		else
			i = i + 1
		end
	end
	if #timers == 0 then self:Hide() end
end)
function MM:After(delay, fn)
	local t = { at = GetTime() + (delay or 0), fn = fn }
	timers[#timers + 1] = t
	timerFrame:Show()
	return t
end
function MM:Cancel(t)
	if t then t.cancelled = true end
end

------------------------------------------------------------------------
-- Output
------------------------------------------------------------------------
function MM:Print(msg)
	local f = _G["ChatFrame" .. ((MM.db and MM.db.chatFrame) or 1)] or DEFAULT_CHAT_FRAME
	f:AddMessage("|cff" .. MM:AccentHex() .. "MailMaster|r: " .. tostring(msg))
end

local function Commas(n)
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return out
end
MM.Commas = Commas

-- 12,345g 67s 89c (coloured)
function MM:Money(c, noCopper)
	c = floor(c or 0)
	local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
	local out = ""
	if g > 0 then out = Commas(g) .. "|cffffd700g|r" end
	if s > 0 then out = out .. (out ~= "" and " " or "") .. s .. "|cffc7c7cfs|r" end
	if cp > 0 and not (noCopper and g > 0) then out = out .. (out ~= "" and " " or "") .. cp .. "|cffeda55fc|r" end
	if out == "" then out = "0|cffeda55fc|r" end
	return out
end

-- plain text money for subjects: 12g 50s
function MM:MoneyPlain(c)
	local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
	local t = {}
	if g > 0 then t[#t + 1] = g .. "g" end
	if s > 0 then t[#t + 1] = s .. "s" end
	if cp > 0 then t[#t + 1] = cp .. "c" end
	return table.concat(t, " ")
end

------------------------------------------------------------------------
-- Themes
------------------------------------------------------------------------
MM.themes = {
	{ "Gold",          { 1.00, 0.82, 0.00 }, { 0.80, 0.80, 0.80 } },
	{ "Silver",        { 0.88, 0.88, 0.92 }, { 0.70, 0.70, 0.75 } },
	{ "Frost",         { 0.45, 0.80, 1.00 }, { 0.45, 0.70, 0.95 } },
	{ "Fel",           { 0.50, 1.00, 0.30 }, { 0.40, 0.80, 0.30 } },
	{ "Blood",         { 1.00, 0.35, 0.35 }, { 0.80, 0.25, 0.25 } },
	{ "Arcane",        { 0.80, 0.55, 1.00 }, { 0.60, 0.40, 0.85 } },
	{ "Shadow",        { 0.75, 0.75, 0.75 }, { 0.30, 0.30, 0.35 } },
	{ "Horde",         { 0.90, 0.20, 0.15 }, { 0.60, 0.15, 0.10 } },
	{ "Alliance",      { 0.30, 0.55, 1.00 }, { 0.20, 0.35, 0.75 } },
	{ "Emerald",       { 0.20, 0.90, 0.60 }, { 0.15, 0.65, 0.45 } },
	{ "Sunset",        { 1.00, 0.55, 0.20 }, { 0.85, 0.45, 0.15 } },
	{ "Rose",          { 1.00, 0.55, 0.75 }, { 0.80, 0.40, 0.60 } },
	{ "Ice",           { 0.75, 0.95, 1.00 }, { 0.60, 0.85, 0.95 } },
	{ "Class colour",  nil, nil },
}

local themed = {}
local accent, border = { 1, 0.82, 0 }, { 0.8, 0.8, 0.8 }

function MM:ThemeColors()
	return accent, border
end

function MM:AccentHex()
	return format("%02x%02x%02x", accent[1] * 255, accent[2] * 255, accent[3] * 255)
end

function MM:ApplyTheme()
	local name = MM.db and MM.db.theme or "Gold"
	for _, t in ipairs(MM.themes) do
		if t[1] == name then
			if t[2] then
				accent, border = t[2], t[3]
			else
				local _, token = UnitClass("player")
				local c = RAID_CLASS_COLORS[token] or { r = 1, g = 0.82, b = 0 }
				accent = { c.r, c.g, c.b }
				border = { c.r * 0.8, c.g * 0.8, c.b * 0.8 }
			end
		end
	end
	for i = 1, #themed do
		local obj, kind = themed[i][1], themed[i][2]
		if kind == "border" then
			obj:SetBackdropBorderColor(border[1], border[2], border[3])
		else
			obj:SetTextColor(accent[1], accent[2], accent[3])
		end
	end
end

function MM:Theme(obj, kind)
	themed[#themed + 1] = { obj, kind }
	if kind == "border" then
		obj:SetBackdropBorderColor(border[1], border[2], border[3])
	else
		obj:SetTextColor(accent[1], accent[2], accent[3])
	end
	return obj
end

------------------------------------------------------------------------
-- Small UI factory (Blizzard style: dark background, silver rounded border)
------------------------------------------------------------------------
local BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

function MM:Panel(name, parent, w, h)
	local f = CreateFrame("Frame", name, parent or UIParent)
	f:SetBackdrop(BACKDROP)
	f:SetBackdropColor(0, 0, 0, 0.92)
	if w then f:SetWidth(w) end
	if h then f:SetHeight(h) end
	MM:Theme(f, "border")
	return f
end

function MM:Title(parent, text, size)
	local fs = parent:CreateFontString(nil, "OVERLAY", size == "small" and "GameFontNormalSmall" or "GameFontNormal")
	fs:SetText(text)
	MM:Theme(fs, "text")
	return fs
end

-- MailMaster's own button look: dark face, theme-coloured border and text, optional icon
local BTN_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = false, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
function MM:Button(parent, text, w, h, icon)
	w, h = w or 80, h or 22
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(w)
	b:SetHeight(h)
	b:SetBackdrop(BTN_BACKDROP)
	b:SetBackdropColor(0.07, 0.07, 0.09, 0.95)
	MM:Theme(b, "border")
	local textX = 0
	if icon then
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetWidth(h - 8)
		t:SetHeight(h - 8)
		t:SetTexture(icon)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if text and text ~= "" then
			t:SetPoint("LEFT", 5, 0)
			textX = (h - 6) / 2
		else
			t:SetPoint("CENTER", 0, 0)
		end
		b.icon = t
	end
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER", textX, 0)
	b:SetFontString(fs)
	MM:Theme(fs, "text")
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 3, -3)
	hl:SetPoint("BOTTOMRIGHT", -3, 3)
	hl:SetTexture(1, 1, 1, 0.12)
	b:SetScript("OnMouseDown", function()
		fs:SetPoint("CENTER", textX + 1, -1)
		if b.icon then b.icon:SetVertexColor(0.7, 0.7, 0.7) end
	end)
	b:SetScript("OnMouseUp", function()
		fs:SetPoint("CENTER", textX, 0)
		if b.icon then b.icon:SetVertexColor(1, 1, 1) end
	end)
	b:SetText(text or "")
	return b
end

function MM:CloseButton(parent)
	local b = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
	b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 2, 2)
	return b
end

function MM:Tooltip(widget, title, text)
	widget:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title, 1, 1, 1)
		if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function MM:MakeMovable(f)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
end

------------------------------------------------------------------------
-- Item helpers
------------------------------------------------------------------------
function MM:ItemID(link)
	return link and tonumber(link:match("item:(%d+)"))
end

local scanTip
local BLOCKED = {}
function MM:IsMailable(bag, slot)
	if bag < 0 or bag > NUM_BAG_SLOTS then return false end
	local _, _, locked = GetContainerItemInfo(bag, slot)
	if locked or not GetContainerItemLink(bag, slot) then return false end
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "MailMasterScanTip", nil, "GameTooltipTemplate")
		BLOCKED[ITEM_SOULBOUND or "Soulbound"] = true
		BLOCKED[ITEM_BIND_QUEST or "Quest Item"] = true
		BLOCKED[ITEM_CONJURED or "Conjured Item"] = true
	end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanTip:SetBagItem(bag, slot)
	for i = 2, math.min(scanTip:NumLines(), 6) do
		local fs = _G["MailMasterScanTipTextLeft" .. i]
		local t = fs and fs:GetText()
		if t and BLOCKED[t] then
			scanTip:Hide()
			return false
		end
	end
	scanTip:Hide()
	return true
end

-- Item categories (for QuickAttach and send rules)
MM.categories = {
	{ key = "Cloth",      label = "Cloth",           type = "Trade Goods", sub = { Cloth = true },                         icon = "INV_Fabric_Linen_01" },
	{ key = "Herb",       label = "Herbs",           type = "Trade Goods", sub = { Herb = true },                          icon = "INV_Misc_Herb_10" },
	{ key = "Metal",      label = "Ore & Bars",      type = "Trade Goods", sub = { ["Metal & Stone"] = true },             icon = "INV_Ore_Copper_01" },
	{ key = "Leather",    label = "Leather",         type = "Trade Goods", sub = { Leather = true },                       icon = "INV_Misc_LeatherScrap_03" },
	{ key = "Enchanting", label = "Enchanting",      type = "Trade Goods", sub = { Enchanting = true },                    icon = "INV_Enchant_DustArcane" },
	{ key = "Gem",        label = "Gems",            type = "Gem",                                                          icon = "INV_Misc_Gem_01" },
	{ key = "Elemental",  label = "Elemental",       type = "Trade Goods", sub = { Elemental = true },                     icon = "INV_Elemental_Primal_Fire" },
	{ key = "Glyph",      label = "Glyphs",          type = "Glyph",                                                        icon = "INV_Inscription_Tradeskill01" },
	{ key = "Meat",       label = "Meat & Fish",     type = "Trade Goods", sub = { Meat = true },                          icon = "INV_Misc_Fish_02" },
	{ key = "Parts",      label = "Engineering",     type = "Trade Goods", sub = { Parts = true, Devices = true, Explosives = true }, icon = "INV_Misc_Gear_01" },
	{ key = "Consumable", label = "Consumables",     type = "Consumable",                                                   icon = "INV_Potion_51" },
	{ key = "Recipe",     label = "Recipes",         type = "Recipe",                                                       icon = "INV_Scroll_03" },
	{ key = "TradeOther", label = "Other trade goods", type = "Trade Goods", sub = { Other = true, Materials = true, Jewelcrafting = true, ["Armor Enchantment"] = true, ["Weapon Enchantment"] = true }, icon = "INV_Misc_Bag_10" },
}
MM.catByKey = {}
for _, c in ipairs(MM.categories) do MM.catByKey[c.key] = c end

function MM:InCategory(link, key)
	local c = MM.catByKey[key]
	if not c or not link then return false end
	local _, _, _, _, _, itemType, subType = GetItemInfo(link)
	if itemType ~= c.type then return false end
	return not c.sub or (subType and c.sub[subType]) and true or false
end

-- Bag iteration over normal bags only
function MM:FreeBagSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS do
		local n, fam = GetContainerNumFreeSlots(bag)
		if fam == 0 then free = free + n end
	end
	return free
end

function MM:FindEmptySlot()
	for bag = 0, NUM_BAG_SLOTS do
		local _, fam = GetContainerNumFreeSlots(bag)
		if fam == 0 then
			for slot = 1, GetContainerNumSlots(bag) do
				if not GetContainerItemLink(bag, slot) then return bag, slot end
			end
		end
	end
end

-- Price for one item (AuctionaryPro / Auctionary -> Auctionator -> TSM -> vendor)
function MM:Price(link)
	if not link then return end
	local ok, v
	if Auctionary and Auctionary.API and Auctionary.API.v1 and Auctionary.API.v1.GetAuctionPriceByItemLink then
		ok, v = pcall(Auctionary.API.v1.GetAuctionPriceByItemLink, "MailMaster", link)
		if ok and v and v > 0 then return v, "Auctionary" end
	end
	if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink then
		ok, v = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, "MailMaster", link)
		if ok and v and v > 0 then return v, "Auctionator" end
	end
	if Atr_GetAuctionBuyout then
		ok, v = pcall(Atr_GetAuctionBuyout, link)
		if ok and v and v > 0 then return v, "Auctionator" end
	end
	if TSMAPI and TSMAPI.GetItemValue then
		ok, v = pcall(TSMAPI.GetItemValue, TSMAPI, link, "DBMarket")
		if ok and v and v > 0 then return v, "TSM" end
	end
	local sell = select(11, GetItemInfo(link))
	if sell and sell > 0 then return sell, "vendor" end
end

function MM:NormName(name)
	if not name or name == "" then return end
	name = name:gsub("%s", "")
	name = name:match("^([^%-]+)") or name
	return name:sub(1, 1):upper() .. name:sub(2):lower()
end

-- localized class name -> class token
local classToken
function MM:ClassToken(localized)
	if not localized then return end
	if not classToken then
		classToken = {}
		for k, v in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classToken[v] = k end
		for k, v in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classToken[v] = k end
	end
	return classToken[localized] or (RAID_CLASS_COLORS[localized] and localized)
end

function MM:ClassHex(token)
	local c = token and RAID_CLASS_COLORS[token]
	if not c then return "ffffff" end
	return format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

------------------------------------------------------------------------
-- Saved variables & login
------------------------------------------------------------------------
function MM:UseSettings()
	if MailMasterCharDB.own then
		MailMasterCharDB.settings = CopyDefaults(MailMasterCharDB.settings or {}, MM.defaults)
		MM.db = MailMasterCharDB.settings
	else
		MM.db = MailMasterDB.settings
	end
	-- 1.2.1: new faster default (only if the old default was never changed)
	if not MM.db.speedV2 then
		if MM.db.speed and math.abs(MM.db.speed - 0.10) < 0.001 then MM.db.speed = 0.03 end
		MM.db.speedV2 = true
	end
	MM:ApplyTheme()
end

function MM:ResetSettings()
	local t = {}
	CopyDefaults(t, MM.defaults)
	if MailMasterCharDB.own then MailMasterCharDB.settings = t else MailMasterDB.settings = t end
	MM:UseSettings()
end

MM:On("PLAYER_LOGIN", function()
	MailMasterDB = MailMasterDB or {}
	MailMasterCharDB = MailMasterCharDB or {}
	local g = MailMasterDB
	g.settings = CopyDefaults(g.settings or {}, MM.defaults)
	g.realms = g.realms or {}
	g.rules = g.rules or {}
	g.sendRules = g.sendRules or {}

	MM.realmName = GetRealmName()
	MM.faction = UnitFactionGroup("player") or "Neutral"
	MM.player = UnitName("player")
	local realm = g.realms[MM.realmName] or { chars = {}, recent = {}, favs = {} }
	g.realms[MM.realmName] = realm
	realm.recent[MM.faction] = realm.recent[MM.faction] or {}
	realm.favs[MM.faction] = realm.favs[MM.faction] or {}
	MM.realm = realm
	MM.recent = realm.recent[MM.faction]
	MM.favs = realm.favs[MM.faction]

	local me = realm.chars[MM.player] or {}
	realm.chars[MM.player] = me
	local _, token = UnitClass("player")
	me.class, me.level, me.faction = token, UnitLevel("player"), MM.faction
	MM.char = me

	MM:UseSettings()
	if MM.Inbox then MM.Inbox:Init() end
	if MM.Send then MM.Send:Init() end
	if MM.Queue then MM.Queue:Init() end
	if MM.Log then MM.Log:Init() end
	if MM.Viewer then MM.Viewer:Init() end
	if MM.Options then MM.Options:Init() end

end)

MM:On("PLAYER_LEVEL_UP", function(level)
	if MM.char then MM.char.level = level end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_MAILMASTER1 = "/mm"
SLASH_MAILMASTER2 = "/mailmaster"
SlashCmdList.MAILMASTER = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	if cmd == "alts" or cmd == "overview" then
		MM.Viewer:Show()
	elseif cmd == "inbox" then
		MM.Viewer:Show(rest ~= "" and MM:NormName(rest) or MM.player)
	elseif cmd == "rules" then
		MM.Inbox:RunRules(rest == "test")
	elseif cmd == "sent" then
		MM.Log:Show("sent")
	elseif cmd == "received" or cmd == "got" then
		MM.Log:Show("received")
	elseif cmd == "log" then
		MM.Log:Show()
	elseif cmd == "queue" or cmd == "prep" then
		MM.Queue:Show()
	elseif cmd == "stop" then
		MM.Inbox:Stop(true)
	elseif cmd == "help" or cmd == "?" then
		MM:Print("v" .. MM.version .. " commands:")
		MM:Print("/mm - options")
		MM:Print("/mm alts - mail overview of all your characters")
		MM:Print("/mm inbox [name] - last seen inbox of a character (works anywhere)")
		MM:Print("/mm queue - prepare mails anywhere, they go out at the next mailbox")
		MM:Print("/mm sent - everything you have sent")
		MM:Print("/mm received - everything you have collected from the mailbox")
		MM:Print("/mm rules - run auto return/delete rules now (at a mailbox)")
		MM:Print("/mm rules test - show what the rules would do")
		MM:Print("/mm stop - stop opening mail")
	else
		MM.Options:Open()
	end
end

------------------------------------------------------------------------
-- Version check: players with MailMaster tell each other their version
-- (hidden addon messages in guild / group / raid / battleground)
------------------------------------------------------------------------
local VPREFIX = "MailMaster"
local notified, lastGroupSend, lastReply = false, 0, {}

local function VersionNumber(v)
	local a, b, c = tostring(v or ""):match("(%d+)%.?(%d*)%.?(%d*)")
	return (tonumber(a) or 0) * 10000 + (tonumber(b) or 0) * 100 + (tonumber(c) or 0)
end

local function SendVersion(channel, target)
	if channel == "WHISPER" and not target then return end
	SendAddonMessage(VPREFIX, "V:" .. MM.version, channel, target)
end

local function GroupChannel()
	local _, instanceType = IsInInstance()
	if instanceType == "pvp" then return "BATTLEGROUND" end
	if GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers() > 0 then return "PARTY" end
end

local function SendToGroup()
	if GetTime() - lastGroupSend < 60 then return end
	local ch = GroupChannel()
	if ch then
		lastGroupSend = GetTime()
		SendVersion(ch)
	end
end

MM:On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix ~= VPREFIX or not msg or sender == MM.player then return end
	local v = msg:match("^V:(.+)$")
	if not v then return end
	local theirs, mine = VersionNumber(v), VersionNumber(MM.version)
	if theirs > mine then
		if not notified and MM.db and MM.db.versionCheck then
			notified = true
			MM:Print(format("|cff40ff40A newer version (%s) is available|r - you have %s. Download: github.com/Feralpaw69/MailMaster", v, MM.version))
		end
	elseif theirs < mine then
		-- let them know a newer one exists (at most once per 10 minutes per player)
		if not lastReply[sender] or GetTime() - lastReply[sender] > 600 then
			lastReply[sender] = GetTime()
			SendVersion("WHISPER", sender)
		end
	end
end)

local sentGuild = false
MM:On("PLAYER_ENTERING_WORLD", function()
	MM:After(15, function()
		if not sentGuild and IsInGuild() then
			sentGuild = true
			SendVersion("GUILD")
		end
		SendToGroup()
	end)
end)
MM:On("PARTY_MEMBERS_CHANGED", function() MM:After(3, SendToGroup) end)
MM:On("RAID_ROSTER_UPDATE", function() MM:After(3, SendToGroup) end)
