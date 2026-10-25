-- MailMaster - sent mail log (/mm sent) and minimap button
local ADDON, MM = ...
local Log = {}
MM.Log = Log

local format, floor, tinsert, tremove = format, floor, tinsert, tremove
local frame, scroll, rows, search
local view = {}
local RH, NROWS = 20, 15

Log.keepOptions = {
	{ text = "10 days", value = 10 },
	{ text = "1 month", value = 30 },
	{ text = "3 months", value = 90 },
	{ text = "6 months", value = 180 },
	{ text = "12 months", value = 365 },
	{ text = "Forever", value = 0 },
}

local tab = "sent"   -- "sent" or "received"

local function List(kind)
	kind = kind or tab
	MailMasterDB[kind] = MailMasterDB[kind] or {}
	return MailMasterDB[kind]
end

function Log:Prune()
	local keep = MM.db.sentKeep or 10
	if keep <= 0 then return end
	local cutoff = time() - keep * 86400
	for _, kind in ipairs({ "sent", "received" }) do
		local l = List(kind)
		while l[1] and (l[1].t or 0) < cutoff do tremove(l, 1) end
	end
end

------------------------------------------------------------------------
-- Received log: every take (gold / item) is recorded, one entry per mail
------------------------------------------------------------------------
local session, logged = {}, {}
local lastItem

local function OnTake(i, a)
	if not MailMasterDB or not i then return end
	local sender, subject, money, cod = select(3, GetInboxHeaderInfo(i))
	if not sender and not subject then return end
	local id = MM.Inbox.Identity(i)
	local key = id .. ":" .. (a or "m")
	if logged[key] then return end -- repeated request for the same thing
	local e = session[id]
	if a then
		local link = GetInboxItemLink(i, a)
		if not link then return end
		logged[key] = true
		if not e then
			e = { t = time(), r = MM.realmName, f = sender, to = MM.player, j = subject }
			session[id] = e
			tinsert(List("received"), e)
		end
		local _, _, count = GetInboxItem(i, a)
		e.it = e.it or {}
		tinsert(e.it, MM:ItemID(link))
		tinsert(e.it, count or 1)
		if cod and cod > 0 then e.c = cod end
		lastItem = { e = e, n = #e.it, at = GetTime() }
	else
		if not money or money <= 0 then return end
		logged[key] = true
		if not e then
			e = { t = time(), r = MM.realmName, f = sender, to = MM.player, j = subject }
			session[id] = e
			tinsert(List("received"), e)
		end
		e.m = money
	end
	if frame and frame:IsVisible() and tab == "received" then Log:Refresh() end
end

-- called from Send on MAIL_SEND_SUCCESS
function Log:Add(p)
	if not p or not p.to then return end
	tinsert(List(), {
		t = time(), r = MM.realmName, f = MM.player, to = p.to, j = p.j,
		m = (p.m and p.m > 0) and p.m or nil, c = (p.c and p.c > 0) and p.c or nil, it = p.it,
	})
	Log:Prune()
	if frame and frame:IsVisible() then Log:Refresh() end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function ItemIcon(id)
	return (GetItemIcon and GetItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Matches(e, f)
	if f == "" then return true end
	if (e.to or ""):lower():find(f, 1, true) or (e.f or ""):lower():find(f, 1, true) or (e.j or ""):lower():find(f, 1, true) then
		return true
	end
	if e.it then
		for k = 1, #e.it, 2 do
			local name = GetItemInfo(e.it[k])
			if name and name:lower():find(f, 1, true) then return true end
		end
	end
end

function Log:Refresh()
	wipe(view)
	local f = search:GetText():lower()
	local l = List(tab)
	for i = #l, 1, -1 do -- newest first
		local e = l[i]
		if (e.r == nil or e.r == MM.realmName) and Matches(e, f) then view[#view + 1] = e end
	end
	Log.UpdateRows()
end

function Log.UpdateRows()
	FauxScrollFrame_Update(scroll, #view, NROWS, RH)
	local off = FauxScrollFrame_GetOffset(scroll)
	for i = 1, NROWS do
		local row, e = rows[i], view[i + off]
		row.e = e
		if e then
			local icon = "Interface\\Icons\\INV_Scroll_03"
			if e.it and e.it[1] then icon = ItemIcon(e.it[1]) elseif e.m then icon = "Interface\\Icons\\INV_Misc_Coin_01" end
			row.icon:SetTexture(icon)
			row.date:SetText(date("%d.%m. %H:%M", e.t))
			local fc = MM.realm.chars[e.f]
			local tc = MM.realm.chars[e.to]
			row.who:SetText(format("|cff%s%s|r > |cff%s%s|r", MM:ClassHex(fc and fc.class), e.f or "?", tc and MM:ClassHex(tc.class) or "ffffff", e.to))
			row.subj:SetText((e.c and "|cffff4040CoD|r " or "") .. (e.j or ""))
			local n = e.it and (#e.it / 2) or 0
			row.money:SetText((e.m and MM:Money(e.m, true) or "") .. (n > 0 and ("  |cffaaaaaa" .. n .. "x|r") or ""))
			row:Show()
		else
			row:Hide()
		end
	end
	local keep = MM.db.sentKeep or 10
	local label = "forever"
	for _, o in ipairs(Log.keepOptions) do if o.value == keep then label = o.text end end
	frame.footer:SetText(format("%d %s mail(s) shown. Kept for %s (change under /mm > Appearance).", #view, tab, label:lower()))
end

local function RowTooltip(row)
	local e = row.e
	if not e then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(e.j or "?", 1, 1, 1, true)
	GameTooltip:AddLine(format("%s to %s, %s", e.f or "?", e.to, date("%d.%m.%Y %H:%M", e.t)), 0.8, 0.8, 0.8)
	if e.m then GameTooltip:AddLine("Gold: " .. MM:Money(e.m), 1, 1, 1) end
	if e.c then GameTooltip:AddLine("CoD: " .. MM:Money(e.c), 1, 0.3, 0.3) end
	if e.it then
		for k = 1, #e.it, 2 do
			local id, count = e.it[k], e.it[k + 1]
			local name, link = GetItemInfo(id)
			GameTooltip:AddLine("|T" .. ItemIcon(id) .. ":14|t " .. (link or name or ("item:" .. id)) .. ((count or 1) > 1 and (" x" .. count) or ""))
		end
	end
	GameTooltip:Show()
end

function Log:Build()
	frame = MM:Panel("MailMasterSentLog", UIParent, 560, 420)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	MM:MakeMovable(frame)
	tinsert(UISpecialFrames, "MailMasterSentLog")
	local t = MM:Title(frame, "Mail log")
	t:SetPoint("TOP", 0, -12)
	MM:CloseButton(frame)

	frame.tabs = {}
	for k, d in ipairs({ { "sent", "Sent" }, { "received", "Received" } }) do
		local b = MM:Button(frame, d[2], 84, 20)
		b:SetPoint("TOPLEFT", 220 + (k - 1) * 90, -30)
		b:SetScript("OnClick", function() Log:Show(d[1]) end)
		frame.tabs[d[1]] = b
	end

	search = CreateFrame("EditBox", "MailMasterSentSearch", frame, "InputBoxTemplate")
	search:SetWidth(180)
	search:SetHeight(18)
	search:SetPoint("TOPLEFT", 20, -32)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function() Log:Refresh() end)
	search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	MM:Tooltip(search, "Search", "Name, subject or item name.")

	local clear = MM:Button(frame, "Clear log", 80, 20)
	clear:SetPoint("TOPRIGHT", -34, -30)
	clear:SetScript("OnClick", function() StaticPopup_Show("MAILMASTER_CLEARLOG", tab) end)

	scroll = CreateFrame("ScrollFrame", "MailMasterSentScroll", frame, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -58)
	scroll:SetWidth(512)
	scroll:SetHeight(NROWS * RH)
	scroll:SetScript("OnVerticalScroll", function(self, o) FauxScrollFrame_OnVerticalScroll(self, o, RH, Log.UpdateRows) end)
	rows = {}
	for i = 1, NROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetWidth(516)
		row:SetHeight(RH)
		row:SetPoint("TOPLEFT", 14, -58 - (i - 1) * RH)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetWidth(16)
		row.icon:SetHeight(16)
		row.icon:SetPoint("LEFT", 2, 0)
		local function fs(x, w, j)
			local f = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			f:SetPoint("LEFT", x, 0)
			f:SetWidth(w)
			f:SetHeight(RH)
			f:SetJustifyH(j or "LEFT")
			return f
		end
		row.date = fs(22, 72)
		row.who = fs(96, 150)
		row.subj = fs(248, 170)
		row.money = fs(420, 94, "RIGHT")
		row:SetScript("OnEnter", RowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end
	frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.footer:SetPoint("BOTTOMLEFT", 16, 14)
end

StaticPopupDialogs["MAILMASTER_CLEARLOG"] = {
	text = "Delete the whole %s mail log?",
	button1 = YES, button2 = NO,
	OnAccept = function() wipe(List()); if frame and frame:IsVisible() then Log:Refresh() end end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

function Log:Show(which)
	if which then tab = which end
	if not frame then Log:Build() end
	for k, b in pairs(frame.tabs) do
		if k == tab then b:LockHighlight() else b:UnlockHighlight() end
	end
	frame:Show()
	Log:Refresh()
end

------------------------------------------------------------------------
-- Minimap button (left: prepared mail, right: options, shift-left: sent log, drag: move)
------------------------------------------------------------------------
local mini
local function PlaceMini()
	local a = math.rad(MM.db.minimapAngle or 200)
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

function Log:ApplyMinimap()
	if MM.db.minimap then
		if not mini then Log:BuildMinimap() end
		PlaceMini()
		mini:Show()
	elseif mini then
		mini:Hide()
	end
end

function Log:BuildMinimap()
	mini = CreateFrame("Button", "MailMasterMinimapButton", Minimap)
	mini:SetWidth(31)
	mini:SetHeight(31)
	mini:SetFrameStrata("MEDIUM")
	mini:SetFrameLevel(8)
	mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = mini:CreateTexture(nil, "BACKGROUND")
	bg:SetWidth(20)
	bg:SetHeight(20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = mini:CreateTexture(nil, "ARTWORK")
	icon:SetWidth(18)
	icon:SetHeight(18)
	icon:SetTexture("Interface\\Minimap\\Tracking\\Mailbox")
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = mini:CreateTexture(nil, "OVERLAY")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mini:RegisterForDrag("LeftButton")
	mini:SetScript("OnClick", function(_, button)
		GameTooltip:Hide()
		if button == "RightButton" then
			MM.Options:Open()
		elseif IsShiftKeyDown() then
			Log:Show()
		else
			MM.Queue:Show()
		end
	end)
	mini:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			MM.db.minimapAngle = math.deg(math.atan2(py / s - my, px / s - mx))
			PlaceMini()
		end)
	end)
	mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	mini:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("MailMaster", 1, 0.82, 0)
		local q = MailMasterCharDB.queue and #MailMasterCharDB.queue or 0
		if q > 0 then GameTooltip:AddLine(q .. " prepared mail(s) waiting", 0.4, 1, 0.4) end
		GameTooltip:AddLine("Left-click: prepared mail", 1, 1, 1)
		GameTooltip:AddLine("Shift-click: mail log (sent / received)", 1, 1, 1)
		GameTooltip:AddLine("Right-click: options", 1, 1, 1)
		GameTooltip:AddLine("Drag: move", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Log:Init()
	Log:Prune()
	Log:ApplyMinimap()
	hooksecurefunc("TakeInboxMoney", function(i) OnTake(i, nil) end)
	hooksecurefunc("TakeInboxItem", function(i, a) OnTake(i, a) end)
	MM:On("UI_ERROR_MESSAGE", function(msg)
		-- the last item could not be taken (bags full): take it out of the log again
		if msg == ERR_INV_FULL and lastItem and GetTime() - lastItem.at < 3 then
			local e = lastItem.e
			if e.it and #e.it == lastItem.n then
				tremove(e.it)
				tremove(e.it)
				if #e.it == 0 then e.it = nil end
			end
			lastItem = nil
		end
	end)
	MM:On("MAIL_CLOSED", function()
		wipe(session)
		wipe(logged)
		lastItem = nil
	end)
end
