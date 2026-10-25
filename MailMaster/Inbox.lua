-- MailMaster - inbox: fast Open All, select, delete/return, shortcuts, summary, rules, snapshot
local ADDON, MM = ...
local Inbox = {}
MM.Inbox = Inbox

local floor, format, min, max = floor, format, math.min, math.max
local GetInboxHeaderInfo, GetInboxNumItems, GetInboxItemLink = GetInboxHeaderInfo, GetInboxNumItems, GetInboxItemLink
local ROWS = INBOXITEMS_TO_DISPLAY or 7
local MAX_ATTACH = ATTACHMENTS_MAX_RECEIVE or 12
local VERIFY_DELAY, BAG_RECHECK, MAX_PASSES = 1.0, 0.5, 6
-- "cruise control": at most this many requests waiting for the server at once
local MAX_INFLIGHT, INFLIGHT_TIMEOUT = 4, 0.6
local inflight, waitSince = 0, nil

-- sender, subject, money, cod, daysLeft, items, wasRead, wasReturned, textCreated, canReply, isGM
local function H(i)
	return select(3, GetInboxHeaderInfo(i))
end

local function Identity(i)
	local sender, subject, _, _, days = H(i)
	return (sender or "") .. "\1" .. (subject or "") .. "\1" .. floor((days or 0) * 100000)
end
Inbox.Identity = Identity

------------------------------------------------------------------------
-- Mail types
------------------------------------------------------------------------
local AH = {}
local function Pattern(fmt, fallback)
	fmt = fmt or fallback
	local p = fmt:gsub("%%s", "\001")
	p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
	p = p:gsub("\001", ".+")
	return "^" .. p
end

Inbox.typeLabels = {
	AHSold = "Auction successful", AHExpired = "Auction expired", AHCancelled = "Auction cancelled",
	AHOutbid = "Outbid", AHWon = "Auction won", PlayerItems = "Player mail with items",
	PlayerGold = "Player mail with gold only", System = "System / Postmaster mail",
}
Inbox.shortLabels = {
	AHSold = "AH sold", AHExpired = "AH expired", AHCancelled = "AH cancelled",
	AHOutbid = "AH outbid", AHWon = "AH won", PlayerItems = "Player mail (items)",
	PlayerGold = "Player mail (gold)", System = "System / Postmaster",
}
Inbox.typeOrder = { "AHSold", "AHExpired", "AHCancelled", "AHOutbid", "AHWon", "PlayerItems", "PlayerGold", "System" }

function Inbox:Type(i)
	local sender, subject, money, cod, _, items, _, wasReturned, _, canReply, isGM = H(i)
	if not sender and not subject then return end
	if isGM then return "GM" end
	if cod and cod > 0 then return "COD" end
	subject = subject or ""
	for k, p in pairs(AH) do
		if subject:find(p) then return k end
	end
	if canReply or wasReturned then
		return items and "PlayerItems" or "PlayerGold"
	end
	return "System"
end

------------------------------------------------------------------------
-- Open engine (sends requests back to back, then check passes)
------------------------------------------------------------------------
local targets, ti, attachIndex, pass, lastRemaining, freeSlots, bagRechecked, invFull
local stepTimer

-- returns list of indices (high -> low) and how many requests are still needed
local function BuildTargets(j)
	local list, remaining = {}, 0
	local left
	if j.ids then
		left = {}
		for k, v in pairs(j.ids) do left[k] = v end
	end
	j.skippedCOD = 0
	for i = GetInboxNumItems(), 1, -1 do
		local _, _, money, _, _, items = H(i)
		local t = Inbox:Type(i)
		if t and ((money and money > 0) or items) then
			local ok
			if left then
				local id = Identity(i)
				if left[id] and left[id] > 0 then
					left[id] = left[id] - 1
					ok = true
				end
			else
				ok = j.override or MM.db.filters[t]
			end
			if ok and (t == "GM" or t == "COD") then
				ok = false
				j.skippedCOD = j.skippedCOD + 1
			end
			if ok then
				list[#list + 1] = i
				if money and money > 0 then remaining = remaining + 1 end
				if items and not invFull then remaining = remaining + items end
			end
		end
	end
	return list, remaining
end

function Inbox.Step()
	stepTimer = nil
	local j = Inbox.busy
	if not j or j.kind ~= "open" then return end
	-- wait until the server has answered some of the requests already sent
	if inflight >= MAX_INFLIGHT then
		waitSince = waitSince or GetTime()
		if GetTime() - waitSince < INFLIGHT_TIMEOUT then
			stepTimer = MM:After(0.02, Inbox.Step)
			return
		end
		inflight = 0 -- server went quiet: don't stall, carry on
	end
	waitSince = nil
	while ti <= #targets do
		local i = targets[ti]
		local _, subject, money, _, _, items = H(i)
		if not attachIndex then
			attachIndex = MAX_ATTACH
			if pass == 1 and MM.db.verbose then
				MM:Print(format("Mail %d: %s%s", i, subject or "", (money and money > 0) and ("  " .. MM:Money(money)) or ""))
			end
		end
		if items and not invFull then
			while attachIndex > 0 and not GetInboxItemLink(i, attachIndex) do
				attachIndex = attachIndex - 1
			end
			if attachIndex > 0 then
				local keep = MM.db.keepFree
				if keep > 0 and freeSlots <= keep then
					if not bagRechecked then
						bagRechecked = true
						stepTimer = MM:After(BAG_RECHECK, function()
							freeSlots = MM:FreeBagSlots()
							Inbox.Step()
						end)
						return
					end
					invFull = true
					MM:Print(format("Only %d free bag slots left - taking gold only.", freeSlots))
				else
					TakeInboxItem(i, attachIndex)
					inflight = inflight + 1
					freeSlots = freeSlots - 1
					bagRechecked = false
					attachIndex = attachIndex - 1
					stepTimer = MM:After(MM.db.speed, Inbox.Step)
					return
				end
			end
		end
		ti = ti + 1
		attachIndex = nil
		if money and money > 0 then
			TakeInboxMoney(i)
			inflight = inflight + 1
			stepTimer = MM:After(MM.db.speed, Inbox.Step)
			return
		end
	end
	stepTimer = MM:After(inflight > 0 and VERIFY_DELAY or 0.5, Inbox.Verify)
end

local function BeginPass(list)
	inflight, waitSince = 0, nil
	targets, ti, attachIndex = list, 1, nil
	freeSlots = MM:FreeBagSlots()
	bagRechecked = false
	Inbox.Step()
end

function Inbox.Verify()
	stepTimer = nil
	local j = Inbox.busy
	if not j or j.kind ~= "open" then return end
	local list, remaining = BuildTargets(j)
	if remaining > 0 and pass < MAX_PASSES and (not lastRemaining or remaining < lastRemaining) then
		lastRemaining = remaining
		pass = pass + 1
		return BeginPass(list)
	end
	Inbox:AfterPasses()
end

function Inbox:StartOpen(j)
	if Inbox.busy or not Inbox.open then return end
	j.kind = "open"
	Inbox.busy = j
	invFull, pass, lastRemaining = nil, 1, nil
	Inbox:SetBusyUI(true)
	local list, remaining = BuildTargets(j)
	if #list == 0 then return Inbox:AfterPasses() end
	BeginPass(list)
end

function Inbox:OpenAll(override)
	Inbox:StartOpen({ openAll = true, override = override })
end

function Inbox:AfterPasses()
	local j = Inbox.busy
	if j.openAll then
		local n, total = GetInboxNumItems()
		if total > n then
			Inbox:WaitForServer(n)
			return
		end
	end
	if j.skippedCOD and j.skippedCOD > 0 then
		MM:Print(format("Skipped %d CoD/GM mail(s).", j.skippedCOD))
	end
	Inbox:Stop()
end

-- More mail is waiting on the server: refresh until the next batch arrives
local waitTimer
function Inbox:WaitForServer(shown)
	local j = Inbox.busy
	j.waiting, j.waitFrom, j.waitStart = true, shown, GetTime()
	if not j.waitMsg then
		MM:Print("More mail is waiting on the server - refreshing (the server allows this about once a minute)...")
		j.waitMsg = true
	end
	local function tick()
		if not Inbox.busy or not Inbox.busy.waiting then return end
		local waited = floor(GetTime() - j.waitStart)
		if waited > 0 and waited % 10 == 0 then CheckInbox() end
		Inbox:UpdateSummary()
		if waited > 180 then
			MM:Print("The server didn't send more mail. Stopped.")
			return Inbox:Stop()
		end
		waitTimer = MM:After(1, tick)
	end
	CheckInbox()
	waitTimer = MM:After(1, tick)
	Inbox:UpdateSummary()
end

function Inbox:CheckWaiting()
	local j = Inbox.busy
	if not j or not j.waiting then return end
	local n, total = GetInboxNumItems()
	if n < j.waitFrom then j.waitFrom = n end
	if n > j.waitFrom then
		j.waiting = nil
		MM:Cancel(waitTimer)
		invFull, pass, lastRemaining = nil, 1, nil
		local list = BuildTargets(j)
		if #list == 0 then return Inbox:AfterPasses() end
		BeginPass(list)
	elseif total <= n then
		Inbox:Stop()
	end
end

-- Return / delete a list of mails ({ i =, act = "return"|"delete", id = })
function Inbox:RunActions(list)
	if Inbox.busy or #list == 0 then return end
	Inbox.busy = { kind = "actions" }
	Inbox:SetBusyUI(true)
	local k, done = 0, 0
	local function nextAct()
		stepTimer = nil
		k = k + 1
		local a = list[k]
		if not a or not Inbox.busy then
			MM:Print(format("%d mail(s) returned/deleted.", done))
			return Inbox:Stop()
		end
		if Identity(a.i) == a.id then
			if a.act == "return" then ReturnInboxItem(a.i) else DeleteInboxItem(a.i) end
			done = done + 1
		end
		stepTimer = MM:After(max(MM.db.speed, 0.15), nextAct)
	end
	nextAct()
end

function Inbox:Stop(user)
	if not Inbox.busy then return end
	MM:Cancel(stepTimer)
	MM:Cancel(waitTimer)
	stepTimer, waitTimer = nil, nil
	Inbox.busy = nil
	Inbox:SetBusyUI(false)
	Inbox:UpdateSummary(true)
	if Inbox.open then Inbox:Snapshot() end
	if user then MM:Print("Stopped.") end
	if InboxFrame:IsVisible() then InboxFrame_Update() end
end

------------------------------------------------------------------------
-- Select (checkboxes), delete/return buttons, summary
------------------------------------------------------------------------
local selected, lastClick = {}, nil
local cbs, xs = {}, {}
local openAllBtn, menuBtn, summary, openSelBtn, returnSelBtn
local lastCount = 0

local function SelectedCount()
	local c = 0
	for _ in pairs(selected) do c = c + 1 end
	return c
end

function Inbox:ClearSelection()
	wipe(selected)
	lastClick = nil
end

local summaryTimer
function Inbox:UpdateSummary(force)
	if not summary then return end
	if not MM.db.summary then summary:SetText("") return end
	local j = Inbox.busy
	-- while opening, redraw at most 3x per second (less work per request = less lag)
	if j and not force and not j.waiting then
		if not summaryTimer then
			summaryTimer = MM:After(0.35, function()
				summaryTimer = nil
				Inbox:UpdateSummary(true)
			end)
		end
		return
	end
	if j and j.waiting then
		summary:SetText(format("|cffffd200Waiting for the next batch from the server... %ds|r", floor(GetTime() - j.waitStart)))
		return
	end
	local n, total = GetInboxNumItems()
	local money, items, cod, soon = 0, 0, 0, 0
	for i = 1, n do
		local _, _, m, c, days, it = H(i)
		money = money + (m or 0)
		items = items + (it or 0)
		if c and c > 0 then cod = cod + 1 end
		if days and days < MM.db.expiryDays and ((m and m > 0) or it) then soon = soon + 1 end
	end
	local t = format("%d mails", n)
	if total > n then t = t .. format(" |cffaaaaaa(+%d)|r", total - n) end
	if money > 0 then t = t .. " · " .. MM:Money(money, true) end
	t = t .. " · " .. items .. " items"
	if cod > 0 then t = t .. " · " .. cod .. " CoD" end
	if soon > 0 then t = t .. format(" · |cffff8000%d expiring|r", soon) end
	if MM.db.rake and (Inbox.collected or 0) > 0 then t = t .. " · |cff40ff40+" .. MM:Money(Inbox.collected, true) .. "|r" end
	summary:SetText(t)
end

function Inbox.UpdateRows()
	if not cbs[1] then return end
	local n = GetInboxNumItems()
	local page = InboxFrame.pageNum or 1
	for r = 1, ROWS do
		local idx = (page - 1) * ROWS + r
		local cb, x = cbs[r], xs[r]
		if idx <= n then
			cb.index, x.index = idx, idx
			cb:SetChecked(selected[idx] and 1 or nil)
			if MM.db.checkboxes then cb:Show() else cb:Hide() end
			local _, _, money, cod, days, items, _, _, _, _, isGM = H(idx)
			if MM.db.deleteButton and not isGM then x:Show() else x:Hide() end
			local exp = _G["MailItem" .. r .. "ExpireTime"]
			if exp and days and days >= 1 and days < MM.db.expiryDays then
				exp:SetText("|cffff8000" .. format(DAYS_ABBR or "%d Days", floor(days)) .. "|r ")
			end
		else
			cb:Hide()
			x:Hide()
		end
	end
	local c = SelectedCount()
	if c > 0 and not Inbox.busy then
		openSelBtn:SetText("Open (" .. c .. ")")
		returnSelBtn:SetText("Return (" .. c .. ")")
		openSelBtn:Show()
		returnSelBtn:Show()
		summary:Hide()
	else
		openSelBtn:Hide()
		returnSelBtn:Hide()
		summary:Show()
	end
	if MM.db.summary and InboxTooMuchMail then InboxTooMuchMail:Hide() end
	Inbox:UpdateSummary()
end

function Inbox:SetBusyUI(busy)
	if not openAllBtn then return end
	openAllBtn:SetText(busy and "Stop" or "Open All")
	if InboxFrame:IsVisible() then Inbox.UpdateRows() end
end

function Inbox:ApplyLayout()
	if not cbs[1] then return end
	if MM.db.checkboxes then
		MailItem1:ClearAllPoints()
		MailItem1:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 48, -80)
		for i = 1, ROWS do _G["MailItem" .. i]:SetWidth(280) end
	else
		MailItem1:ClearAllPoints()
		MailItem1:SetPoint(unpack(Inbox.origPoint))
		for i = 1, ROWS do _G["MailItem" .. i]:SetWidth(Inbox.origWidth) end
	end
	if InboxFrame:IsVisible() then InboxFrame_Update() end
end

local function OpenSelected()
	local ids = {}
	for idx in pairs(selected) do
		local id = Identity(idx)
		ids[id] = (ids[id] or 0) + 1
	end
	Inbox:ClearSelection()
	Inbox:StartOpen({ ids = ids, override = true })
end

local function ReturnSelected()
	local list, skipped = {}, 0
	local idxs = {}
	for idx in pairs(selected) do idxs[#idxs + 1] = idx end
	table.sort(idxs, function(a, b) return a > b end)
	for _, idx in ipairs(idxs) do
		local _, _, _, _, _, _, _, wasReturned, _, _, isGM = H(idx)
		if InboxItemCanDelete(idx) or wasReturned or isGM then
			skipped = skipped + 1
		else
			list[#list + 1] = { i = idx, act = "return", id = Identity(idx) }
		end
	end
	if skipped > 0 then MM:Print(format("%d selected mail(s) can't be returned (auction house, system or already returned).", skipped)) end
	Inbox:ClearSelection()
	Inbox:RunActions(list)
end

local function DeleteOrReturn(idx)
	if Inbox.busy or not idx then return end
	local _, subject, money, cod, _, items, _, wasReturned, _, _, isGM = H(idx)
	if isGM then return end
	if InboxItemCanDelete(idx) then
		if MM.db.confirmDelete and ((money and money > 0) or items) then
			StaticPopup_Show("MAILMASTER_DELETE", subject or "?", nil, { idx = idx, id = Identity(idx) })
		else
			DeleteInboxItem(idx)
		end
	elseif not wasReturned then
		ReturnInboxItem(idx)
	end
end

StaticPopupDialogs["MAILMASTER_DELETE"] = {
	text = "Delete \"%s\"?\nThe gold and items in it will be lost.",
	button1 = YES, button2 = NO,
	OnAccept = function(self, data)
		if data and Identity(data.idx) == data.id then DeleteInboxItem(data.idx) end
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

------------------------------------------------------------------------
-- Filter quick menu (arrow next to Open All)
------------------------------------------------------------------------
local menuFrame
local function ShowFilterMenu(anchor)
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "MailMasterFilterMenu", UIParent, "UIDropDownMenuTemplate")
	end
	local f = MM.db.filters
	local acc = "|cff" .. MM:AccentHex()
	local menu = { { text = acc .. "MailMaster|r", isTitle = true, notCheckable = true } }
	local function add(k)
		menu[#menu + 1] = {
			text = "  " .. Inbox.shortLabels[k], checked = f[k] and true or false, isNotRadio = true, keepShownOnClick = true,
			func = function() f[k] = not f[k] end,
		}
	end
	menu[#menu + 1] = { text = "Auction house", isTitle = true, notCheckable = true }
	for _, k in ipairs({ "AHSold", "AHExpired", "AHCancelled", "AHOutbid", "AHWon" }) do add(k) end
	menu[#menu + 1] = { text = "Other mail", isTitle = true, notCheckable = true }
	for _, k in ipairs({ "PlayerItems", "PlayerGold", "System" }) do add(k) end
	menu[#menu + 1] = { text = "Options", isTitle = true, notCheckable = true }
	menu[#menu + 1] = { text = "  Print each mail in chat", checked = MM.db.verbose, isNotRadio = true, keepShownOnClick = true,
		func = function() MM.db.verbose = not MM.db.verbose end }
	menu[#menu + 1] = { text = "  All settings...", notCheckable = true, func = function() MM.Options:Open() end }
	EasyMenu(menu, menuFrame, anchor, 0, 0, "MENU")
end

------------------------------------------------------------------------
-- Snapshot (remote inbox / alt overview) and expiry warnings
------------------------------------------------------------------------
function Inbox:Snapshot()
	if not MM.char then return end
	local n, total = GetInboxNumItems()
	local list = {}
	for i = 1, n do
		local sender, subject, money, cod, days, items = H(i)
		local e = { s = sender, j = subject, d = days }
		if money and money > 0 then e.m = money end
		if cod and cod > 0 then e.c = cod end
		if not InboxItemCanDelete(i) then e.r = 1 end
		if items then
			local it = {}
			for a = 1, MAX_ATTACH do
				local link = GetInboxItemLink(i, a)
				if link then
					local _, _, count = GetInboxItem(i, a)
					it[#it + 1] = MM:ItemID(link)
					it[#it + 1] = count or 1
				end
			end
			e.it = it
		end
		list[i] = e
	end
	MM.char.inbox, MM.char.t, MM.char.total = list, time(), total
end

local function WarnExpiring()
	local n = GetInboxNumItems()
	local c, soonest = 0, nil
	for i = 1, n do
		local _, _, money, _, days, items = H(i)
		if days and days < MM.db.expiryDays and ((money and money > 0) or items) then
			c = c + 1
			if not soonest or days < soonest then soonest = days end
		end
	end
	if c > 0 then
		MM:Print(format("|cffff8000%d mail(s) with gold or items expire within %d days|r (first in %s).",
			c, MM.db.expiryDays, SecondsToTime(soonest * 86400)))
	end
end

------------------------------------------------------------------------
-- Auto return / delete rules
------------------------------------------------------------------------
function Inbox:RunRules(test)
	if not Inbox.open then MM:Print("Open a mailbox first.") return end
	if Inbox.busy then return end
	local rules = MailMasterDB.rules
	if #rules == 0 then MM:Print("No return/delete rules set up (see /mm > Rules).") return end
	test = test or MM.db.rulesTest
	local acts = {}
	for i = GetInboxNumItems(), 1, -1 do
		local sender, subject, money, cod, _, items, _, wasReturned, _, _, isGM = H(i)
		if not isGM then
			local ls, lj = (sender or ""):lower(), (subject or ""):lower()
			for _, r in ipairs(rules) do
				if r.on and r.text and r.text ~= "" then
					local hay = r.field == "sender" and ls or lj
					if hay:find(r.text:lower(), 1, true) then
						local canDelete = InboxItemCanDelete(i)
						if r.act == "return" and not canDelete and not wasReturned then
							acts[#acts + 1] = { i = i, act = "return", id = Identity(i), label = subject, from = sender }
						elseif r.act == "delete" and canDelete and not items and (money or 0) == 0 and (cod or 0) == 0 then
							acts[#acts + 1] = { i = i, act = "delete", id = Identity(i), label = subject, from = sender }
						end
						break
					end
				end
			end
		end
	end
	if #acts == 0 then
		MM:Print("Rules: nothing to return or delete.")
		return
	end
	if test then
		MM:Print(format("Rules test - would handle %d mail(s):", #acts))
		for _, a in ipairs(acts) do
			MM:Print(format("  %s: %s |cffaaaaaa(%s)|r", a.act == "return" and "Return" or "Delete", a.label or "?", a.from or "?"))
		end
		return
	end
	Inbox:RunActions(acts)
end

------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------
local firstUpdate, rakeMoney, collected = false, 0, 0

function Inbox:Init()
	AH.AHSold = Pattern(AUCTION_SOLD_MAIL_SUBJECT, "Auction successful: %s")
	AH.AHExpired = Pattern(AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s")
	AH.AHCancelled = Pattern(AUCTION_REMOVED_MAIL_SUBJECT, "Auction cancelled: %s")
	AH.AHOutbid = Pattern(AUCTION_OUTBID_MAIL_SUBJECT, "Outbid on %s")
	AH.AHWon = Pattern(AUCTION_WON_MAIL_SUBJECT, "Auction won: %s")

	-- Open All + filter arrow
	openAllBtn = MM:Button(InboxFrame, "Open All", 118, 24, "Interface\\Icons\\INV_Misc_Coin_02")
	openAllBtn:SetPoint("CENTER", InboxFrame, "TOP", -26, -410)
	openAllBtn:SetFrameLevel(openAllBtn:GetFrameLevel() + 2)
	openAllBtn:SetScript("OnClick", function()
		if Inbox.busy then Inbox:Stop(true) else Inbox:OpenAll(IsShiftKeyDown()) end
	end)
	MM:Tooltip(openAllBtn, "Open All", "Takes gold and items from all mail that passes your filters.\nShift-click: take everything (still skips CoD).\nClick again to stop.")

	menuBtn = MM:Button(InboxFrame, "", 24, 24, "Interface\\Icons\\INV_Misc_Gear_01")
	menuBtn:SetPoint("LEFT", openAllBtn, "RIGHT", 3, 0)
	menuBtn:SetFrameLevel(openAllBtn:GetFrameLevel())
	menuBtn:SetScript("OnClick", function(self) ShowFilterMenu(self) end)
	MM:Tooltip(menuBtn, "Filters", "Choose which mail Open All takes.")

	-- Summary + rake + select buttons (top of inbox)
	summary = InboxFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	summary:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 82, -44)
	summary:SetWidth(258)
	summary:SetHeight(12)
	summary:SetJustifyH("LEFT")

	openSelBtn = MM:Button(InboxFrame, "Open", 84, 20)
	openSelBtn:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 82, -39)
	openSelBtn:SetScript("OnClick", OpenSelected)
	openSelBtn:Hide()
	returnSelBtn = MM:Button(InboxFrame, "Return", 84, 20)
	returnSelBtn:SetPoint("LEFT", openSelBtn, "RIGHT", 4, 0)
	returnSelBtn:SetScript("OnClick", ReturnSelected)
	returnSelBtn:Hide()

	-- per-row checkbox + delete/return button
	local p1, p2, p3, p4, p5 = MailItem1:GetPoint()
	Inbox.origPoint = { p1, p2, p3, p4, p5 }
	Inbox.origWidth = MailItem1:GetWidth()
	for r = 1, ROWS do
		local row = _G["MailItem" .. r]
		local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		cb:SetWidth(22)
		cb:SetHeight(22)
		cb:SetPoint("RIGHT", row, "LEFT", 1, -5)
		cb:SetScript("OnClick", function(self)
			local idx = self.index
			if not idx then return end
			local state = self:GetChecked() and true or nil
			if IsShiftKeyDown() and lastClick then
				for k = min(lastClick, idx), max(lastClick, idx) do selected[k] = state end
			elseif IsControlKeyDown() then
				local who = H(idx)
				for k = 1, GetInboxNumItems() do
					if H(k) == who then selected[k] = state end
				end
			else
				selected[idx] = state
			end
			lastClick = idx
			Inbox.UpdateRows()
		end)
		MM:Tooltip(cb, "Select", "Shift-click: select everything between this and the last one.\nCtrl-click: all mail from this sender.")
		cbs[r] = cb

		local x = CreateFrame("Button", nil, row)
		x:SetWidth(14)
		x:SetHeight(14)
		x:SetPoint("TOPRIGHT", _G["MailItem" .. r .. "ExpireTime"], "BOTTOMRIGHT", -2, -2)
		x:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
		x:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		x:SetScript("OnClick", function(self) DeleteOrReturn(self.index) end)
		x:SetScript("OnEnter", function(self)
			if not self.index then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(InboxItemCanDelete(self.index) and "Delete" or "Return to sender", 1, 1, 1)
			GameTooltip:Show()
		end)
		x:SetScript("OnLeave", function() GameTooltip:Hide() end)
		xs[r] = x
	end
	Inbox:ApplyLayout()
	hooksecurefunc("InboxFrame_Update", Inbox.UpdateRows)

	-- Express: Shift-click takes everything, Ctrl-click returns; block clicks while busy
	local origClick = InboxFrame_OnClick
	InboxFrame_OnClick = function(self, index, ...)
		if Inbox.busy then
			if self.SetChecked then self:SetChecked(nil) end
			return
		end
		if IsShiftKeyDown() and index then
			if self.SetChecked then self:SetChecked(nil) end
			local t = Inbox:Type(index)
			if t == "COD" then MM:Print("That's a CoD mail - open it normally to pay.") return end
			Inbox:StartOpen({ ids = { [Identity(index)] = 1 }, override = true })
			return
		elseif IsControlKeyDown() and index then
			if self.SetChecked then self:SetChecked(nil) end
			if InboxItemCanDelete(index) then
				MM:Print("That mail can't be returned (auction house, system or already returned).")
			else
				ReturnInboxItem(index)
			end
			return
		end
		return origClick(self, index, ...)
	end

	-- Tooltip: all attachments, full subject, what happens on expiry
	if InboxFrameItem_OnEnter then hooksecurefunc("InboxFrameItem_OnEnter", function(self)
		local idx = self.index
		if not idx then return end
		local _, subject, money, _, days, items = H(idx)
		if not subject then return end
		if not GameTooltip:IsOwned(self) then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(subject, 1, 1, 1, true)
		elseif #subject > 28 then
			GameTooltip:AddLine(subject, 1, 1, 1, true)
		end
		if items and items > 1 then
			for a = 1, MAX_ATTACH do
				local name, tex, count = GetInboxItem(idx, a)
				if name then
					local link = GetInboxItemLink(idx, a) or name
					GameTooltip:AddLine("|T" .. (tex or "") .. ":14|t " .. link .. ((count or 1) > 1 and (" x" .. count) or ""))
				end
			end
		end
		if days and ((money and money > 0) or items) then
			GameTooltip:AddLine(format("Expires in %s, then it is %s.", SecondsToTime(days * 86400),
				InboxItemCanDelete(idx) and "deleted" or "returned to the sender"), 0.7, 0.7, 0.7, true)
		end
		GameTooltip:Show()
	end) end

	-- CarbonCopy + Forward buttons on the open mail
	local copyBtn = MM:Button(OpenMailFrame, "Copy", 70, 22)
	copyBtn:SetPoint("TOPLEFT", OpenMailFrame, "TOPRIGHT", -36, -70)
	copyBtn:SetScript("OnClick", function() Inbox:CopyMail() end)
	MM:Tooltip(copyBtn, "Copy", "Shows the sender, subject and text so you can copy it with Ctrl+C.")
	local fwdBtn = MM:Button(OpenMailFrame, "Forward", 70, 22)
	fwdBtn:SetPoint("TOP", copyBtn, "BOTTOM", 0, -4)
	fwdBtn:SetScript("OnClick", function() MM.Send:Forward(InboxFrame.openMailID) end)
	MM:Tooltip(fwdBtn, "Forward", "Takes the items and gold into your bags and puts them into a new mail with the same text.")

	-- Events
	MM:On("MAIL_SHOW", function()
		Inbox.open = true
		firstUpdate = true
		rakeMoney, collected = GetMoney(), 0
		Inbox.collected = 0
		Inbox:ClearSelection()
	end)
	MM:On("MAIL_INBOX_UPDATE", function()
		if inflight > 0 then inflight = inflight - 1 end -- the server answered one request
		if not Inbox.open then return end
		local n = GetInboxNumItems()
		if n ~= lastCount then
			lastCount = n
			Inbox:ClearSelection()
		end
		if Inbox.busy then Inbox:CheckWaiting() end
		if not Inbox.snapTimer and not Inbox.busy then
			Inbox.snapTimer = MM:After(1, function()
				Inbox.snapTimer = nil
				if Inbox.open then Inbox:Snapshot() end
			end)
		end
		if firstUpdate and n > 0 then
			firstUpdate = false
			WarnExpiring()
			if MM.db.rulesAuto and #MailMasterDB.rules > 0 then
				MM:After(0.5, function() Inbox:RunRules(false) end)
			end
		end
		if InboxFrame:IsVisible() then Inbox:UpdateSummary() end
	end)
	MM:On("MAIL_CLOSED", function()
		if not Inbox.open then return end
		Inbox:Snapshot()
		Inbox:Stop()
		Inbox.open = false
		Inbox:ClearSelection()
		if MM.db.rake and collected > 0 then
			MM:Print("Collected " .. MM:Money(collected) .. " from the mailbox.")
		end
		collected = 0
	end)
	MM:On("PLAYER_LEAVING_WORLD", function() Inbox:Stop() end)
	MM:On("PLAYER_MONEY", function()
		if not Inbox.open then return end
		local m = GetMoney()
		if m > rakeMoney then
			collected = collected + (m - rakeMoney)
			Inbox.collected = collected
			if InboxFrame:IsVisible() then Inbox:UpdateSummary() end
		end
		rakeMoney = m
	end)
	MM:On("UI_ERROR_MESSAGE", function(msg)
		if Inbox.busy and msg == ERR_INV_FULL then invFull = true end
	end)
end

------------------------------------------------------------------------
-- CarbonCopy window
------------------------------------------------------------------------
local copyFrame
function Inbox:CopyMail()
	local id = InboxFrame.openMailID
	if not id then return end
	local sender, subject = H(id)
	local body = GetInboxText(id) or ""
	if not copyFrame then
		copyFrame = MM:Panel("MailMasterCopy", UIParent, 420, 300)
		copyFrame:SetPoint("CENTER")
		copyFrame:SetFrameStrata("DIALOG")
		MM:MakeMovable(copyFrame)
		tinsert(UISpecialFrames, "MailMasterCopy")
		local title = MM:Title(copyFrame, "Copy mail text (Ctrl+C)")
		title:SetPoint("TOP", 0, -10)
		MM:CloseButton(copyFrame)
		local sf = CreateFrame("ScrollFrame", "MailMasterCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 12, -32)
		sf:SetPoint("BOTTOMRIGHT", -32, 12)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetFontObject(ChatFontNormal)
		eb:SetWidth(370)
		eb:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
		sf:SetScrollChild(eb)
		copyFrame.eb = eb
	end
	copyFrame.eb:SetText(format("From: %s\nSubject: %s\n\n%s", sender or "?", subject or "", body))
	copyFrame:Show()
	copyFrame.eb:SetFocus()
	copyFrame.eb:HighlightText()
end
