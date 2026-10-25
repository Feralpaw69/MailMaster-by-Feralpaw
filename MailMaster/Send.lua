-- MailMaster - sending: Alt-slide attach, contacts panel, quick attach, send rules,
-- stack splitting, CoD helper, Wire, Forward, trade/invite block
local ADDON, MM = ...
local Send = {}
MM.Send = Send

local format, floor, tinsert, tremove, wipe = format, floor, tinsert, tremove, wipe
local MAX_SEND = ATTACHMENTS_MAX_SEND or 12

------------------------------------------------------------------------
-- Attachment helpers
------------------------------------------------------------------------
local reserved = {}   -- attachment slots filled this frame (before the client updates)

local function FreeAttach()
	for i = 1, MAX_SEND do
		if not reserved[i] and not GetSendMailItem(i) then return i end
	end
end
Send.FreeAttach = FreeAttach

local function AttachedCount()
	local c = 0
	for i = 1, MAX_SEND do
		if GetSendMailItem(i) then c = c + 1 end
	end
	return c
end

local function Attach(bag, slot)
	local free = FreeAttach()
	if not free or CursorHasItem() then return false end
	PickupContainerItem(bag, slot)
	if not CursorHasItem() then return false end
	ClickSendMailItemButton(free)
	if CursorHasItem() then
		ClearCursor()
		return false
	end
	reserved[free] = true
	return true
end
Send.Attach = Attach

local function ForEachBagSlot(fn)
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			if fn(bag, slot) then return end
		end
	end
end

------------------------------------------------------------------------
-- Sending (through Blizzard's own Send button, so money/CoD/subject checks stay intact)
------------------------------------------------------------------------
local sendTimeout
function Send:SendNow(keepName)
	if Send.sending then return end
	local name = SendMailNameEditBox:GetText()
	if name == "" then
		MM:Print("Enter a recipient first.")
		return
	end
	if SendMailSubjectEditBox:GetText() == "" then
		local first = GetSendMailItem(1)
		for i = 1, MAX_SEND do
			first = first or GetSendMailItem(i)
		end
		local c = MoneyInputFrame_GetCopper(SendMailMoney)
		SendMailSubjectEditBox:SetText(first or (c > 0 and MM:MoneyPlain(c)) or "Mail")
	end
	Send.sending = true
	Send.keepName = keepName and name or nil
	sendTimeout = MM:After(10, function()
		Send.sending = false
		if Send.onSent then local f = Send.onSent; Send.onSent = nil; f(false) end
	end)
	SendMailMailButton:Click()
end

-- Mail is full during an Alt-slide
function Send:Full()
	if MM.db.slideAutoSend and SendMailNameEditBox:GetText() ~= "" then
		Send:SendNow(true)
	elseif not Send.fullWarned then
		Send.fullWarned = true
		UIErrorsFrame:AddMessage("Mail is full (12/12)", 1, 0.82, 0)
	end
end

function Send:SlideAttach(bag, slot)
	if Send.sending or Send.busy then return end
	if not MM:IsMailable(bag, slot) then return end
	if not FreeAttach() then return Send:Full() end
	local link = GetContainerItemLink(bag, slot)
	if Attach(bag, slot) and IsShiftKeyDown() then
		local id = MM:ItemID(link)
		ForEachBagSlot(function(b, s)
			if not FreeAttach() then return true end
			if MM:ItemID(GetContainerItemLink(b, s)) == id and MM:IsMailable(b, s) then Attach(b, s) end
		end)
	end
	if not FreeAttach() then Send:Full() end
end

-- attach every mailable bag item for which match(link) is true
function Send:AttachWhere(match, label)
	local n = 0
	ForEachBagSlot(function(b, s)
		if not FreeAttach() then return true end
		local link = GetContainerItemLink(b, s)
		if link and match(link) and MM:IsMailable(b, s) then
			if Attach(b, s) then n = n + 1 end
		end
	end)
	if n == 0 then
		MM:Print("No mailable " .. label .. " in your bags" .. (FreeAttach() and "." or " (mail is full)."))
	end
end

function Send:AttachCategory(key)
	Send:AttachWhere(function(link) return MM:InCategory(link, key) end, MM.catByKey[key].label:lower())
end

-- Right-click menu: pick a sub type (e.g. Potion, Flask) or one specific item
local quickMenu
function Send:QuickMenu(key)
	local c = MM.catByKey[key]
	local subs, subOrder = {}, {}
	ForEachBagSlot(function(b, s)
		local link = GetContainerItemLink(b, s)
		if link and MM:InCategory(link, key) then
			local name, _, quality, _, _, _, subType, _, _, tex = GetItemInfo(link)
			subType = subType or "Other"
			local g = subs[subType]
			if not g then
				g = { count = 0, items = {}, order = {} }
				subs[subType] = g
				subOrder[#subOrder + 1] = subType
			end
			local _, count = GetContainerItemInfo(b, s)
			count = count or 1
			g.count = g.count + count
			local id = MM:ItemID(link)
			local it = g.items[id]
			if not it then
				it = { id = id, name = name or link, link = link, tex = tex, count = 0, quality = quality }
				g.items[id] = it
				g.order[#g.order + 1] = it
			end
			it.count = it.count + count
		end
	end)
	if #subOrder == 0 then
		MM:Print("No " .. c.label:lower() .. " in your bags.")
		return
	end
	table.sort(subOrder)
	local menu = { { text = c.label, isTitle = true, notCheckable = true } }
	local total = 0
	for _, st in ipairs(subOrder) do total = total + subs[st].count end
	menu[#menu + 1] = { text = format("All %s (%d)", c.label:lower(), total), notCheckable = true,
		func = function() Send:AttachCategory(key) end }
	for _, st in ipairs(subOrder) do
		local g = subs[st]
		if #subOrder > 1 then
			menu[#menu + 1] = { text = format("|cffffd200All %s (%d)|r", st, g.count), notCheckable = true,
				func = function()
					Send:AttachWhere(function(link)
						return MM:InCategory(link, key) and select(7, GetItemInfo(link)) == st
					end, st:lower())
				end }
		end
		table.sort(g.order, function(a, b) return a.name < b.name end)
		for _, it in ipairs(g.order) do
			local r, gg, bb = GetItemQualityColor(it.quality or 1)
			menu[#menu + 1] = {
				text = format("    |T%s:14|t |cff%02x%02x%02x%s|r |cffaaaaaax%d|r", it.tex or "", r * 255, gg * 255, bb * 255, it.name, it.count),
				notCheckable = true,
				func = function()
					Send:AttachWhere(function(link) return MM:ItemID(link) == it.id end, it.name)
				end,
			}
		end
	end
	menu[#menu + 1] = { text = CANCEL, notCheckable = true }
	if not quickMenu then quickMenu = CreateFrame("Frame", "MailMasterQuickMenu", UIParent, "UIDropDownMenuTemplate") end
	EasyMenu(menu, quickMenu, "cursor", 0, 0, "MENU")
end

local function CountCategory(key)
	local n = 0
	ForEachBagSlot(function(b, s)
		local link = GetContainerItemLink(b, s)
		if link and MM:InCategory(link, key) then
			local _, count = GetContainerItemInfo(b, s)
			n = n + (count or 1)
		end
	end)
	return n
end

------------------------------------------------------------------------
-- Stack building (used by stack splitting and Forward)
------------------------------------------------------------------------
function Send:MakeStack(id, size, cb)
	local exact, larger
	ForEachBagSlot(function(b, s)
		if MM:ItemID(GetContainerItemLink(b, s)) == id and MM:IsMailable(b, s) then
			local _, count = GetContainerItemInfo(b, s)
			if count == size then
				exact = { b, s }
				return true
			elseif count and count > size and not larger then
				larger = { b, s }
			end
		end
	end)
	if exact then return cb(exact[1], exact[2]) end
	if not larger then return cb(nil) end
	local eb, es = MM:FindEmptySlot()
	if not eb then return cb(nil) end
	SplitContainerItem(larger[1], larger[2], size)
	PickupContainerItem(eb, es)
	local tries = 0
	local function check()
		tries = tries + 1
		local _, count, locked = GetContainerItemInfo(eb, es)
		if count == size and not locked then return cb(eb, es) end
		if tries > 30 then
			ClearCursor()
			return cb(nil)
		end
		MM:After(0.1, check)
	end
	MM:After(0.1, check)
end

function Send:DoSplit(id, size, count)
	if not id or not size or size < 1 or not count or count < 1 then return end
	Send.busy = true
	local made = 0
	local function step()
		if made >= count or not FreeAttach() or not SendMailFrame:IsVisible() then
			Send.busy = false
			MM:Print(format("Attached %d stack(s) of %d.", made, size))
			return
		end
		Send:MakeStack(id, size, function(b, s)
			if not b then
				Send.busy = false
				MM:Print(format("Attached %d stack(s) of %d - not enough items or no free bag slot left.", made, size))
				return
			end
			if Attach(b, s) then made = made + 1 end
			MM:After(0.25, step)
		end)
	end
	step()
end

------------------------------------------------------------------------
-- Forward
------------------------------------------------------------------------
function Send:Forward(id)
	if not id or Send.busy then return end
	local sender, subject, money, cod, _, items = select(3, GetInboxHeaderInfo(id))
	if not subject then return end
	if cod and cod > 0 then MM:Print("CoD mail can't be forwarded.") return end
	local body = GetInboxText(id) or ""
	local want, need, before = {}, {}, {}
	for a = 1, MAX_SEND do
		local link = GetInboxItemLink(id, a)
		if link then
			local _, _, count = GetInboxItem(id, a)
			local iid = MM:ItemID(link)
			want[#want + 1] = { iid, count or 1 }
			need[iid] = (need[iid] or 0) + (count or 1)
			before[iid] = before[iid] or GetItemCount(iid)
		end
	end
	if #want > MM:FreeBagSlots() then
		MM:Print("Not enough free bag slots to forward this mail.")
		return
	end
	Send.busy = true

	local function fill()
		MailFrameTab2:Click()
		MM:After(0.2, function()
			SendMailSubjectEditBox:SetText("FW: " .. subject)
			if body ~= "" then
				SendMailBodyEditBox:SetText("\n\n--- Forwarded mail from " .. (sender or "?") .. " ---\n" .. body)
			end
			if money and money > 0 then
				SendMailSendMoneyButton:Click()
				MoneyInputFrame_SetCopper(SendMailMoney, money)
			end
			local k = 0
			local function nextItem()
				k = k + 1
				local w = want[k]
				if not w then
					Send.busy = false
					SendMailNameEditBox:SetFocus()
					MM:Print("Forward ready - enter a name and click Send.")
					return
				end
				Send:MakeStack(w[1], w[2], function(b, s)
					if b then Attach(b, s) end
					MM:After(0.25, nextItem)
				end)
			end
			nextItem()
		end)
	end

	local tries = 0
	local function waitItems()
		tries = tries + 1
		local ok = true
		for iid, n in pairs(need) do
			if GetItemCount(iid) < before[iid] + n then ok = false end
		end
		if ok or tries > 50 then
			if not ok then MM:Print("Some items didn't arrive in time - attach the rest by hand.") end
			return fill()
		end
		MM:After(0.1, waitItems)
	end

	local a = MAX_SEND
	local function take()
		while a >= 1 and not GetInboxItemLink(id, a) do a = a - 1 end
		if a >= 1 then
			TakeInboxItem(id, a)
			a = a - 1
			return MM:After(MM.db.speed + 0.1, take)
		end
		if money and money > 0 then TakeInboxMoney(id) end
		MM:After(0.3, waitItems)
	end
	take()
end

------------------------------------------------------------------------
-- Send rules ("herbs -> HerbAlt")
------------------------------------------------------------------------
local function RuleMatches(r, link, id)
	if r.item then return r.item == id end
	return r.cat and MM:InCategory(link, r.cat)
end

function Send:RuleLabel(r)
	if r.item then
		return (GetItemInfo(r.item)) or r.name or ("item " .. r.item)
	end
	return r.cat and MM.catByKey[r.cat] and MM.catByKey[r.cat].label or "?"
end

function Send:PlanRules()
	local rules = MailMasterDB.sendRules
	local plan, order = {}, {}
	ForEachBagSlot(function(b, s)
		local link = GetContainerItemLink(b, s)
		if not link then return end
		local id = MM:ItemID(link)
		for _, r in ipairs(rules) do
			if not r.to and RuleMatches(r, link, id) then return end -- never send
		end
		for _, r in ipairs(rules) do
			local to = MM:NormName(r.to)
			if to and to ~= MM.player and RuleMatches(r, link, id) then
				if MM:IsMailable(b, s) then
					if not plan[to] then
						plan[to] = { slots = {}, label = Send:RuleLabel(r) }
						order[#order + 1] = to
					end
					tinsert(plan[to].slots, { b, s, id })
				end
				return
			end
		end
	end)
	return plan, order
end

local previewFrame
function Send:PreviewRules()
	if Send.busy or Send.sending then return end
	if #MailMasterDB.sendRules == 0 then
		MM:Print("No send rules yet - set them up in /mm > Send Rules.")
		MM.Options:Open("Send Rules")
		return
	end
	if AttachedCount() > 0 or MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
		MM:Print("Clear the current mail first (attachments and gold).")
		return
	end
	local plan, order = Send:PlanRules()
	if #order == 0 then
		MM:Print("Send rules: nothing in your bags matches.")
		return
	end
	if not previewFrame then
		previewFrame = MM:Panel("MailMasterRulesPreview", UIParent, 260, 100)
		previewFrame:SetFrameStrata("DIALOG")
		previewFrame:SetPoint("CENTER")
		MM:MakeMovable(previewFrame)
		local t = MM:Title(previewFrame, "Send by rules")
		t:SetPoint("TOP", 0, -10)
		previewFrame.text = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		previewFrame.text:SetPoint("TOPLEFT", 14, -32)
		previewFrame.text:SetJustifyH("LEFT")
		previewFrame.go = MM:Button(previewFrame, "Send", 90, 22)
		previewFrame.go:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOM", -4, 10)
		local cancel = MM:Button(previewFrame, CANCEL, 90, 22)
		cancel:SetPoint("BOTTOMLEFT", previewFrame, "BOTTOM", 4, 10)
		cancel:SetScript("OnClick", function() previewFrame:Hide() end)
	end
	local lines = {}
	for _, to in ipairs(order) do
		local n = #plan[to].slots
		lines[#lines + 1] = format("|cffffffff%s|r: %d stack(s), %d mail(s)", to, n, math.ceil(n / MAX_SEND))
	end
	previewFrame.text:SetText(table.concat(lines, "\n"))
	previewFrame:SetHeight(80 + #lines * 14)
	previewFrame.go:SetScript("OnClick", function()
		previewFrame:Hide()
		Send:ExecutePlan(plan, order)
	end)
	previewFrame:Show()
end

function Send:ExecutePlan(plan, order)
	Send.busy = true
	local qi, pos, sent = 1, 1, 0
	local function finish(msg)
		Send.busy = false
		MM:Print(msg or format("Send rules: %d mail(s) sent.", sent))
	end
	local function nextMail()
		if not SendMailFrame:IsVisible() then return finish("Mailbox closed - send rules stopped.") end
		local to = order[qi]
		if not to then return finish() end
		local p = plan[to]
		local attached = 0
		while pos <= #p.slots and FreeAttach() do
			local slot = p.slots[pos]
			pos = pos + 1
			if MM:ItemID(GetContainerItemLink(slot[1], slot[2])) == slot[3] and MM:IsMailable(slot[1], slot[2]) then
				if Attach(slot[1], slot[2]) then attached = attached + 1 end
			end
		end
		if attached == 0 then
			qi, pos = qi + 1, 1
			return nextMail()
		end
		SendMailNameEditBox:SetText(to)
		SendMailSubjectEditBox:SetText(p.label)
		Send.onSent = function(ok)
			if not ok then return finish("Sending failed - send rules stopped.") end
			sent = sent + 1
			if pos > #p.slots then qi, pos = qi + 1, 1 end
			MM:After(0.5, nextMail)
		end
		Send:SendNow(false)
	end
	nextMail()
end

------------------------------------------------------------------------
-- Wire (subject = gold amount) and CoD helper
------------------------------------------------------------------------
local lastWire
local function Wire()
	if not MM.db or not MM.db.wire or not SendMailSendMoneyButton:GetChecked() then return end
	local c = MoneyInputFrame_GetCopper(SendMailMoney)
	local subj = SendMailSubjectEditBox:GetText()
	if subj == "" or subj == lastWire then
		lastWire = c > 0 and MM:MoneyPlain(c) or ""
		SendMailSubjectEditBox:SetText(lastWire)
	end
end

local panel, codLine, codBtn
function Send:UpdateCOD()
	if not codLine then return end
	if not MM.db.codHelper or not SendMailCODButton:GetChecked() then
		codLine:Hide()
		codBtn:Hide()
		return
	end
	local total, src, n, missing = 0, nil, 0, 0
	for i = 1, MAX_SEND do
		local link = GetSendMailItemLink(i)
		if link then
			n = n + 1
			local _, _, count = GetSendMailItem(i)
			local p, s = MM:Price(link)
			if p then
				total = total + p * (count or 1)
				src = src or s
			else
				missing = missing + 1
			end
		end
	end
	codLine:Show()
	if n == 0 then
		codLine:SetText("CoD: attach items to see a price")
		codBtn:Hide()
	else
		codLine:SetText("Value: " .. MM:Money(total, true) .. " |cffaaaaaa(" .. (src or "no price") .. (missing > 0 and (", " .. missing .. " unknown") or "") .. ")|r")
		codBtn.value = total
		if total > 0 then codBtn:Show() else codBtn:Hide() end
	end
end

------------------------------------------------------------------------
-- Contacts panel (own design: always-visible side panel with search)
------------------------------------------------------------------------
local rows, entries, scroll, search = {}, {}, nil, nil
local ROWH, NROWS = 16, 17
local SECTIONS = {
	{ key = "fav", label = "Favourites" },
	{ key = "alt", label = "Alts" },
	{ key = "recent", label = "Recent" },
	{ key = "friend", label = "Friends" },
	{ key = "guild", label = "Guild" },
}

local function ByName(a, b) return a.name < b.name end
local function OnlineFirst(a, b)
	if (a.online and true) ~= (b.online and true) then return a.online and true or false end
	return a.name < b.name
end

function Send:Refresh()
	if not panel or not panel:IsVisible() then return end
	wipe(entries)
	local filter = search:GetText():lower()
	local function ok(name) return name and (filter == "" or name:lower():find(filter, 1, true)) end
	local chars = MM.realm.chars
	local lists = { fav = {}, alt = {}, recent = {}, friend = {}, guild = {} }

	for name in pairs(MM.favs) do
		if ok(name) then
			local c = chars[name]
			tinsert(lists.fav, { name = name, kind = "fav", class = c and c.class, alt = c and c.faction == MM.faction, online = true })
		end
	end
	table.sort(lists.fav, ByName)
	for name, c in pairs(chars) do
		if name ~= MM.player and c.faction == MM.faction and ok(name) then
			tinsert(lists.alt, { name = name, kind = "alt", class = c.class, info = c.level, alt = true, online = true })
		end
	end
	table.sort(lists.alt, ByName)
	for _, name in ipairs(MM.recent) do
		if ok(name) then
			local c = chars[name]
			tinsert(lists.recent, { name = name, kind = "recent", class = c and c.class, alt = c and c.faction == MM.faction, online = true })
		end
	end
	for i = 1, GetNumFriends() do
		local name, level, class, _, connected = GetFriendInfo(i)
		if ok(name) then
			tinsert(lists.friend, { name = name, kind = "friend", class = MM:ClassToken(class), info = level, online = connected })
		end
	end
	table.sort(lists.friend, OnlineFirst)
	if IsInGuild() then
		for i = 1, GetNumGuildMembers(true) do
			local name, rank, _, level, class, _, _, _, online = GetGuildRosterInfo(i)
			if name and name ~= MM.player and ok(name) then
				tinsert(lists.guild, { name = name, kind = "guild", class = MM:ClassToken(class), info = level, online = online })
			end
		end
		table.sort(lists.guild, OnlineFirst)
	end

	for _, sec in ipairs(SECTIONS) do
		local list = lists[sec.key]
		if #list > 0 then
			entries[#entries + 1] = { header = sec.key, label = sec.label, n = #list }
			if not MM.db.folded[sec.key] or filter ~= "" then
				for _, e in ipairs(list) do entries[#entries + 1] = e end
			end
		end
	end
	Send.UpdateList()
end

function Send.UpdateList()
	if not scroll then return end
	FauxScrollFrame_Update(scroll, #entries, NROWS, ROWH)
	local offset = FauxScrollFrame_GetOffset(scroll)
	local acc = MM:ThemeColors()
	for i = 1, NROWS do
		local row, e = rows[i], entries[i + offset]
		row.entry = e
		if e then
			if e.header then
				row.name:SetText((MM.db.folded[e.header] and "+ " or "- ") .. e.label .. " (" .. e.n .. ")")
				row.name:SetTextColor(acc[1], acc[2], acc[3])
				row.info:SetText("")
				row.mail:Hide()
			else
				local hex = e.online and MM:ClassHex(e.class) or "808080"
				row.name:SetText("  |cff" .. hex .. e.name .. "|r")
				row.name:SetTextColor(1, 1, 1)
				row.info:SetText(e.info and ("|cffaaaaaa" .. e.info .. "|r") or "")
				if e.alt then row.mail:Show() else row.mail:Hide() end
			end
			row:Show()
		else
			row:Hide()
		end
	end
end

local rowMenu
local function RowMenu(row, e)
	if not rowMenu then rowMenu = CreateFrame("Frame", "MailMasterContactMenu", UIParent, "UIDropDownMenuTemplate") end
	local menu = { { text = e.name, isTitle = true, notCheckable = true } }
	if MM.favs[e.name] then
		menu[#menu + 1] = { text = "Remove from favourites", notCheckable = true, func = function() MM.favs[e.name] = nil; Send:Refresh() end }
	else
		menu[#menu + 1] = { text = "Add to favourites", notCheckable = true, func = function() MM.favs[e.name] = true; Send:Refresh() end }
	end
	if e.kind == "recent" then
		menu[#menu + 1] = { text = "Remove from recent", notCheckable = true, func = function()
			for i = #MM.recent, 1, -1 do if MM.recent[i] == e.name then tremove(MM.recent, i) end end
			Send:Refresh()
		end }
	end
	menu[#menu + 1] = { text = CANCEL, notCheckable = true }
	EasyMenu(menu, rowMenu, "cursor", 0, 0, "MENU")
end

local splitFrame
function Send:ShowSplit()
	if not splitFrame then
		splitFrame = MM:Panel("MailMasterSplit", panel, 196, 128)
		splitFrame:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, 4)
		splitFrame:SetFrameStrata("DIALOG")
		local t = MM:Title(splitFrame, "Split stacks into the mail")
		t:SetPoint("TOP", 0, -10)
		MM:CloseButton(splitFrame)
		local slot = CreateFrame("Button", nil, splitFrame)
		slot:SetWidth(34)
		slot:SetHeight(34)
		slot:SetPoint("TOPLEFT", 14, -30)
		slot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
		slot.icon = slot:CreateTexture(nil, "OVERLAY")
		slot.icon:SetAllPoints()
		local function grab()
			local kind, id = GetCursorInfo()
			if kind == "item" then
				splitFrame.item = id
				slot.icon:SetTexture((GetItemIcon and GetItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
				ClearCursor()
			end
		end
		slot:SetScript("OnClick", grab)
		slot:SetScript("OnReceiveDrag", grab)
		MM:Tooltip(slot, "Item", "Drop an item from your bags here.")
		local function num(label, x, default)
			local fs = splitFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("TOPLEFT", x, -30)
			fs:SetText(label)
			local eb = CreateFrame("EditBox", nil, splitFrame, "InputBoxTemplate")
			eb:SetWidth(40)
			eb:SetHeight(18)
			eb:SetPoint("TOPLEFT", x + 4, -44)
			eb:SetAutoFocus(false)
			eb:SetNumeric(true)
			eb:SetText(default)
			eb:SetScript("OnEnterPressed", eb.ClearFocus)
			return eb
		end
		splitFrame.size = num("Stack size", 62, "20")
		splitFrame.count = num("Stacks", 130, "1")
		local go = MM:Button(splitFrame, "Split & attach", 160, 22)
		go:SetPoint("BOTTOM", 0, 12)
		go:SetScript("OnClick", function()
			if not splitFrame.item then MM:Print("Drop an item into the slot first.") return end
			Send:DoSplit(splitFrame.item, tonumber(splitFrame.size:GetText()), tonumber(splitFrame.count:GetText()))
		end)
	end
	if splitFrame:IsShown() then splitFrame:Hide() else splitFrame:Show() end
end

function Send:BuildPanel()
	panel = MM:Panel("MailMasterContacts", SendMailFrame, 196, 446)
	panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", -34, -12)
	panel:EnableMouse(true)

	local title = MM:Title(panel, "Contacts")
	title:SetPoint("TOPLEFT", 12, -10)

	search = CreateFrame("EditBox", "MailMasterContactSearch", panel, "InputBoxTemplate")
	search:SetWidth(144)
	search:SetHeight(18)
	search:SetPoint("TOPLEFT", 16, -28)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function() Send:Refresh() end)
	search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local e = entries[1] and entries[1].header and entries[2] or entries[1]
		if e and not e.header then SendMailNameEditBox:SetText(e.name) end
	end)
	MM:Tooltip(search, "Search", "Type to filter all lists. Enter picks the first match.")

	local add = CreateFrame("Button", nil, panel)
	add:SetWidth(18)
	add:SetHeight(18)
	add:SetPoint("LEFT", search, "RIGHT", 6, 0)
	add:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
	add:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
	add:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	add:SetScript("OnClick", function()
		local name = MM:NormName(SendMailNameEditBox:GetText())
		if not name then MM:Print("Type a name in the To: field first.") return end
		MM.favs[name] = true
		Send:Refresh()
	end)
	MM:Tooltip(add, "Add favourite", "Adds the name in the To: field to your favourites.")

	scroll = CreateFrame("ScrollFrame", "MailMasterContactScroll", panel, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -52)
	scroll:SetWidth(158)
	scroll:SetHeight(NROWS * ROWH)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROWH, Send.UpdateList)
	end)

	for i = 1, NROWS do
		local row = CreateFrame("Button", nil, panel)
		row:SetWidth(166)
		row:SetHeight(ROWH)
		row:SetPoint("TOPLEFT", 10, -52 - (i - 1) * ROWH)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", 2, 0)
		row.name:SetJustifyH("LEFT")
		row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.info:SetPoint("RIGHT", -20, 0)
		row.mail = CreateFrame("Button", nil, row)
		row.mail:SetWidth(14)
		row.mail:SetHeight(14)
		row.mail:SetPoint("RIGHT", -2, 0)
		row.mail:SetNormalTexture("Interface\\Minimap\\Tracking\\Mailbox")
		row.mail:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		row.mail:SetScript("OnClick", function(self)
			local e = self:GetParent().entry
			if not e then return end
			SendMailNameEditBox:SetText(e.name)
			if AttachedCount() > 0 or MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
				Send:SendNow(false)
			else
				MM:Print("Attach items or gold first, then click the letter to send it to " .. e.name .. ".")
			end
		end)
		MM:Tooltip(row.mail, "Send now", "Sends the current mail straight to this alt.")
		row:SetScript("OnClick", function(self, button)
			local e = self.entry
			if not e then return end
			if e.header then
				MM.db.folded[e.header] = not MM.db.folded[e.header] or nil
				Send:Refresh()
			elseif button == "RightButton" then
				RowMenu(self, e)
			else
				SendMailNameEditBox:SetText(e.name)
				search:ClearFocus()
			end
		end)
		rows[i] = row
	end

	-- CoD helper
	codLine = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	codLine:SetPoint("TOPLEFT", 12, -330)
	codLine:SetWidth(132)
	codLine:SetJustifyH("LEFT")
	codBtn = MM:Button(panel, "Use", 40, 18)
	codBtn:SetPoint("TOPRIGHT", -10, -328)
	codBtn:SetScript("OnClick", function(self)
		if self.value and self.value > 0 then MoneyInputFrame_SetCopper(SendMailMoney, self.value) end
	end)
	MM:Tooltip(codBtn, "Use as CoD", "Puts the suggested value into the CoD amount.")
	codLine:Hide()
	codBtn:Hide()

	-- Quick attach icons (2 rows)
	local qt = MM:Title(panel, "Quick attach", "small")
	qt:SetPoint("TOPLEFT", 12, -350)
	for k, c in ipairs(MM.categories) do
		local b = CreateFrame("Button", nil, panel)
		b:SetWidth(19)
		b:SetHeight(19)
		local col, line = (k - 1) % 7, floor((k - 1) / 7)
		b:SetPoint("TOPLEFT", 12 + col * 25, -364 - line * 23)
		b:SetNormalTexture("Interface\\Icons\\" .. c.icon)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnClick", function() Send:QuickMenu(c.key) end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(c.label, 1, 1, 1)
			GameTooltip:AddLine("In bags: " .. CountCategory(c.key), 0.8, 0.8, 0.8)
			GameTooltip:AddLine("Click: choose all, a type or one item.", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	local split = MM:Button(panel, "Split stacks", 84, 22)
	split:SetPoint("BOTTOMLEFT", 10, 10)
	split:SetScript("OnClick", function() Send:ShowSplit() end)
	local rules = MM:Button(panel, "Send by rules", 88, 22)
	rules:SetPoint("BOTTOMRIGHT", -10, 10)
	rules:SetScript("OnClick", function() Send:PreviewRules() end)
	MM:Tooltip(rules, "Send by rules", "Packs everything that matches your send rules (/mm > Send Rules) into mails to the right alts. Shows a preview first.")

	panel:SetScript("OnShow", function()
		ShowFriends()
		if IsInGuild() then GuildRoster() end
		Send:Refresh()
		Send:UpdateCOD()
	end)
	Send:Refresh()
	if not MM.db.contacts then panel:Hide() end
end

function Send:ApplyPanel()
	if MM.db.contacts then
		if not panel then
			if SendMailFrame:IsVisible() then Send:BuildPanel() end
		else
			panel:Show()
		end
	elseif panel then
		panel:Hide()
	end
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
local refreshTimer
local function QueueRefresh()
	if not panel or not panel:IsVisible() or refreshTimer then return end
	refreshTimer = MM:After(0.5, function()
		refreshTimer = nil
		Send:Refresh()
	end)
end

local oldBlock
function Send:Init()
	-- Alt-slide: works with every bag addon that shows the normal item tooltip
	hooksecurefunc(GameTooltip, "SetBagItem", function(_, bag, slot)
		if MM.db.slide and IsAltKeyDown() and SendMailFrame:IsVisible() and bag and slot then
			Send:SlideAttach(bag, slot)
		end
	end)

	-- Ctrl+Alt over an attachment: take it back out
	for i = 1, MAX_SEND do
		local b = _G["SendMailAttachment" .. i]
		if b then
			b:HookScript("OnEnter", function(self)
				if MM.db.slide and IsAltKeyDown() and IsControlKeyDown() and not CursorHasItem() then
					local id = self:GetID()
					if GetSendMailItem(id) then
						ClickSendMailItemButton(id)
						ClearCursor()
					end
				end
			end)
		end
	end

	-- Clear button: removes all attachments and the gold amount
	local anchor = _G["SendMailAttachment7"] or _G["SendMailAttachment" .. MAX_SEND]
	local clear = MM:Button(SendMailFrame, "Clear", 52, 18)
	-- next to "Amount to send:"
	if SendMailMoneyText then
		clear:SetPoint("LEFT", SendMailMoneyText, "RIGHT", 14, 0)
	elseif SendMailMoney then
		clear:SetPoint("BOTTOMLEFT", SendMailMoney, "TOPLEFT", 110, 3)
	elseif anchor then
		clear:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -26, 4)
	end
	clear:SetFrameLevel(clear:GetFrameLevel() + 3)
	clear:SetScript("OnClick", function()
		if Send.busy or Send.sending then return end
		ClearCursor()
		for i = 1, MAX_SEND do
			if GetSendMailItem(i) then
				ClickSendMailItemButton(i)
				ClearCursor()
			end
		end
		wipe(reserved)
		MoneyInputFrame_SetCopper(SendMailMoney, 0)
		Send.fullWarned = nil
	end)
	MM:Tooltip(clear, "Clear", "Takes all attachments out of the mail and resets the gold amount.")

	-- Wire + CoD helper
	for _, n in ipairs({ "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }) do
		if _G[n] then _G[n]:HookScript("OnTextChanged", Wire) end
	end
	SendMailCODButton:HookScript("OnClick", function() Send:UpdateCOD() end)
	SendMailSendMoneyButton:HookScript("OnClick", function() Send:UpdateCOD() end)

	-- Side panel (built the first time the Send Mail tab opens)
	SendMailFrame:HookScript("OnShow", function()
		if MM.db.contacts and not panel then Send:BuildPanel() end
	end)

	-- Name completion from favourites, alts and recent
	SendMailNameEditBox:HookScript("OnChar", function(self)
		if not MM.db.autocomplete then return end
		local text = self:GetText()
		if text == "" then return end
		local lt, n = text:lower(), #text
		local function try(name)
			if name and #name > n and name:lower():sub(1, n) == lt then
				self:SetText(name)
				self:HighlightText(n, -1)
				return true
			end
		end
		for name in pairs(MM.favs) do if try(name) then return end end
		for name, c in pairs(MM.realm.chars) do
			if c.faction == MM.faction and name ~= MM.player and try(name) then return end
		end
		for _, name in ipairs(MM.recent) do if try(name) then return end end
	end)

	-- Remember what goes out (recent list + alt inbox overview)
	hooksecurefunc("SendMail", function(name, subject)
		local it = {}
		for i = 1, MAX_SEND do
			local link = GetSendMailItemLink(i)
			if link then
				local _, _, count = GetSendMailItem(i)
				it[#it + 1] = MM:ItemID(link)
				it[#it + 1] = count or 1
			end
		end
		Send.pending = { to = MM:NormName(name), j = subject, m = GetSendMailMoney(), c = GetSendMailCOD(), it = #it > 0 and it or nil }
	end)

	MM:On("MAIL_SEND_SUCCESS", function()
		wipe(reserved)
		Send.fullWarned = nil
		MM:Cancel(sendTimeout)
		Send.sending = false
		local p = Send.pending
		Send.pending = nil
		if p and p.to then
			MM.Log:Add(p)
			for i = #MM.recent, 1, -1 do
				if MM.recent[i] == p.to then tremove(MM.recent, i) end
			end
			tinsert(MM.recent, 1, p.to)
			while #MM.recent > 15 do tremove(MM.recent) end
			local alt = MM.realm.chars[p.to]
			if alt and alt.faction == MM.faction and alt.inbox then
				local e = { s = MM.player, j = p.j, d = (p.c and p.c > 0) and 3 or 30, it = p.it, r = 1 }
				if p.m and p.m > 0 then e.m = p.m end
				if p.c and p.c > 0 then e.c = p.c end
				-- store relative to the alt's snapshot time
				e.d = e.d + (time() - (alt.t or time())) / 86400
				tinsert(alt.inbox, 1, e)
				alt.total = (alt.total or 0) + 1
			end
		end
		if Send.keepName then
			local n = Send.keepName
			Send.keepName = nil
			MM:After(0.1, function()
				if SendMailFrame:IsVisible() then SendMailNameEditBox:SetText(n) end
			end)
		end
		if Send.onSent then local f = Send.onSent; Send.onSent = nil; f(true) end
		QueueRefresh()
	end)
	MM:On("MAIL_FAILED", function()
		wipe(reserved)
		MM:Cancel(sendTimeout)
		Send.sending = false
		Send.keepName = nil
		Send.pending = nil
		if Send.onSent then local f = Send.onSent; Send.onSent = nil; f(false) end
	end)
	MM:On("MAIL_SEND_INFO_UPDATE", function()
		wipe(reserved)
		if FreeAttach() then Send.fullWarned = nil end
		Send:UpdateCOD()
	end)
	MM:On("FRIENDLIST_UPDATE", QueueRefresh)
	MM:On("GUILD_ROSTER_UPDATE", QueueRefresh)

	-- Trade / invite block while the mailbox is open
	MM:On("MAIL_SHOW", function()
		if MM.db.blockTrade and not oldBlock then
			oldBlock = GetCVar("BlockTrades")
			SetCVar("BlockTrades", "1")
		end
	end)
	local function restore()
		if oldBlock then
			SetCVar("BlockTrades", oldBlock)
			oldBlock = nil
		end
	end
	MM:On("MAIL_CLOSED", restore)
	MM:On("PLAYER_LOGOUT", restore)
	MM:On("PARTY_INVITE_REQUEST", function(name)
		if MM.Inbox.open and MM.db.blockParty then
			DeclineGroup()
			MM:After(0, function() StaticPopup_Hide("PARTY_INVITE") end)
			MM:Print("Declined a group invite from " .. (name or "?") .. " while at the mailbox.")
		end
	end)
	MM:On("GUILD_INVITE_REQUEST", function(name)
		if MM.Inbox.open and MM.db.blockGuild then
			DeclineGuild()
			MM:After(0, function() StaticPopup_Hide("GUILD_INVITE") end)
			MM:Print("Declined a guild invite from " .. (name or "?") .. " while at the mailbox.")
		end
	end)
end
