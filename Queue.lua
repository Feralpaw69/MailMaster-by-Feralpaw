-- MailMaster - prepared mail: build mails anywhere, they go out automatically at the next mailbox (/mm queue)
local ADDON, MM = ...
local Q = {}
MM.Queue = Q

local format, floor, tinsert, tremove, min = format, floor, tinsert, tremove, math.min
local MAX_ITEMS = 12
local frame, draft, editIndex, listRows, itemSlots, listScroll
local lastPick
local slideAdded = {}

local function Queue()
	MailMasterCharDB.queue = MailMasterCharDB.queue or {}
	return MailMasterCharDB.queue
end

local function NewDraft()
	return { to = "", subject = "", money = 0, items = {} }
end

local function ItemIcon(id)
	return (GetItemIcon and GetItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Describe(m)
	local parts = {}
	if #m.items > 0 then parts[#parts + 1] = #m.items .. (#m.items == 1 and " item" or " items") end
	if m.money and m.money > 0 then parts[#parts + 1] = MM:Money(m.money, true) end
	return table.concat(parts, ", ")
end

------------------------------------------------------------------------
-- Draft editing
------------------------------------------------------------------------
function Q:AddItem(id, count)
	if not id then return end
	for _, e in ipairs(draft.items) do
		if e.id == id then
			if not e.all then e.count = e.count + (count or 1) end
			Q:UpdateEditor()
			return
		end
	end
	if #draft.items >= MAX_ITEMS then
		MM:Print("A prepared mail holds up to 12 different items (any amount of each).")
		return
	end
	tinsert(draft.items, { id = id, count = count or 1 })
	Q:UpdateEditor()
end

local function ReadEditor()
	draft.to = MM:NormName(frame.to:GetText()) or ""
	draft.subject = frame.subject:GetText() or ""
	draft.money = (tonumber(frame.gold:GetText()) or 0) * 10000
end

function Q:UpdateEditor()
	if not frame then return end
	frame.to:SetText(draft.to or "")
	frame.subject:SetText(draft.subject or "")
	frame.gold:SetText((draft.money and draft.money > 0) and tostring(floor(draft.money / 10000)) or "")
	for i = 1, MAX_ITEMS do
		local slot, e = itemSlots[i], draft.items[i]
		slot.entry = e
		if e then
			slot.icon:SetTexture(ItemIcon(e.id))
			slot.count:SetText(e.all and "all" or (e.count > 1 and e.count or ""))
		else
			slot.icon:SetTexture(nil)
			slot.count:SetText("")
		end
	end
	frame.editTitle:SetText(editIndex and "Edit prepared mail" or "New prepared mail")
	frame.save:SetText(editIndex and "Save changes" or "Add to queue")
end

function Q:UpdateList()
	if not frame then return end
	local q = Queue()
	FauxScrollFrame_Update(listScroll, #q, #listRows, 20)
	local off = FauxScrollFrame_GetOffset(listScroll)
	for i = 1, #listRows do
		local row, m = listRows[i], q[i + off]
		row.index = i + off
		if m then
			row.text:SetText(format("|cffffffff%s|r  |cffaaaaaa%s|r  %s", m.to, Describe(m), m.subject ~= "" and ("- " .. m.subject) or ""))
			if editIndex == i + off then row:LockHighlight() else row:UnlockHighlight() end
			row:Show()
		else
			row:Hide()
		end
	end
	frame.count:SetText(#q == 0 and "No prepared mail." or (#q .. " prepared mail(s)"))
	frame.sendNow:SetAlpha(MM.Inbox.open and 1 or 0.4)
end

local function Save()
	ReadEditor()
	if draft.to == "" then MM:Print("Enter a recipient.") return end
	if draft.to == MM.player then MM:Print("You can't mail yourself.") return end
	if #draft.items == 0 and draft.money <= 0 then MM:Print("Add items or gold first.") return end
	local q = Queue()
	if editIndex and q[editIndex] then q[editIndex] = draft else tinsert(q, draft) end
	MM:Print(format("Prepared mail to %s saved (%s). It goes out the next time you open a mailbox.", draft.to, Describe(draft)))
	draft, editIndex = NewDraft(), nil
	wipe(slideAdded)
	Q:UpdateEditor()
	Q:UpdateList()
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
function Q:Build()
	frame = MM:Panel("MailMasterQueue", UIParent, 340, 446)
	frame:SetPoint("CENTER", 200, 0)
	frame:SetFrameStrata("HIGH")
	MM:MakeMovable(frame)
	tinsert(UISpecialFrames, "MailMasterQueue")
	local t = MM:Title(frame, "Prepared mail")
	t:SetPoint("TOP", 0, -12)
	MM:CloseButton(frame)

	local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 16, -32)
	note:SetWidth(308)
	note:SetJustifyH("LEFT")
	note:SetText("Prepare mails anywhere. They are sent automatically the next time you open a mailbox.")

	-- queue list
	frame.count = MM:Title(frame, "", "small")
	frame.count:SetPoint("TOPLEFT", 16, -60)
	listScroll = CreateFrame("ScrollFrame", "MailMasterQueueScroll", frame, "FauxScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", 12, -74)
	listScroll:SetWidth(290)
	listScroll:SetHeight(6 * 20)
	listScroll:SetScript("OnVerticalScroll", function(self, o) FauxScrollFrame_OnVerticalScroll(self, o, 20, Q.UpdateList) end)
	listRows = {}
	for i = 1, 6 do
		local row = CreateFrame("Button", nil, frame)
		row:SetWidth(296)
		row:SetHeight(20)
		row:SetPoint("TOPLEFT", 14, -74 - (i - 1) * 20)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetWidth(262)
		row.text:SetJustifyH("LEFT")
		local del = CreateFrame("Button", nil, row)
		del:SetWidth(14)
		del:SetHeight(14)
		del:SetPoint("RIGHT", -4, 0)
		del:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
		del:SetScript("OnClick", function()
			tremove(Queue(), row.index)
			if editIndex == row.index then draft, editIndex = NewDraft(), nil; Q:UpdateEditor() end
			Q:UpdateList()
		end)
		row:SetScript("OnClick", function(self)
			local m = Queue()[self.index]
			if not m then return end
			-- load a copy into the editor
			draft = { to = m.to, subject = m.subject, money = m.money, items = {} }
			for _, e in ipairs(m.items) do tinsert(draft.items, { id = e.id, count = e.count, all = e.all }) end
			editIndex = self.index
			Q:UpdateEditor()
			Q:UpdateList()
		end)
		listRows[i] = row
	end

	-- editor
	frame.editTitle = MM:Title(frame, "", "small")
	frame.editTitle:SetPoint("TOPLEFT", 16, -206)
	local function box(label, x, y, w, numeric)
		local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("TOPLEFT", x - 4, y)
		fs:SetText(label)
		local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
		eb:SetWidth(w)
		eb:SetHeight(20)
		eb:SetPoint("TOPLEFT", x, y - 12)
		eb:SetAutoFocus(false)
		if numeric then eb:SetNumeric(true) end
		eb:SetScript("OnEscapePressed", eb.ClearFocus)
		eb:SetScript("OnEnterPressed", eb.ClearFocus)
		return eb
	end
	frame.to = box("To", 20, -224, 110)
	frame.gold = box("Gold", 146, -224, 60, true)
	frame.subject = box("Subject (optional)", 20, -262, 296)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 16, -300)
	hint:SetWidth(308)
	hint:SetJustifyH("LEFT")
	hint:SetText("Drop items on the slots, or hold Alt and move the mouse over bag items. Right-click: remove. Ctrl-click: send all of it.")

	itemSlots = {}
	for i = 1, MAX_ITEMS do
		local s = CreateFrame("Button", nil, frame)
		s:SetWidth(36)
		s:SetHeight(36)
		local col, line = (i - 1) % 6, floor((i - 1) / 6)
		s:SetPoint("TOPLEFT", 18 + col * 51, -326 - line * 40)
		s:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
		s:GetNormalTexture():SetTexCoord(0.14, 0.86, 0.14, 0.86)
		s.icon = s:CreateTexture(nil, "OVERLAY")
		s.icon:SetPoint("TOPLEFT", 2, -2)
		s.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		s.count = s:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		s.count:SetPoint("BOTTOMRIGHT", -2, 2)
		s:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local function drop()
			local kind, id = GetCursorInfo()
			if kind ~= "item" then return false end
			local count = 1
			if lastPick then
				local _, c = GetContainerItemInfo(lastPick[1], lastPick[2])
				count = c or 1
			end
			ClearCursor()
			ReadEditor()
			Q:AddItem(id, count)
			return true
		end
		s:SetScript("OnReceiveDrag", drop)
		s:SetScript("OnClick", function(self, button)
			if drop() then return end
			local e = self.entry
			if not e then return end
			ReadEditor()
			if button == "RightButton" then
				for k, v in ipairs(draft.items) do if v == e then tremove(draft.items, k) break end end
			elseif IsControlKeyDown() then
				e.all = not e.all or nil
			end
			Q:UpdateEditor()
		end)
		s:SetScript("OnEnter", function(self)
			local e = self.entry
			if not e then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:" .. e.id)
			GameTooltip:AddLine(e.all and "Sends all you have" or ("Sends " .. e.count), 0.4, 1, 0.4)
			GameTooltip:AddLine("In bags: " .. GetItemCount(e.id), 0.8, 0.8, 0.8)
			GameTooltip:Show()
		end)
		s:SetScript("OnLeave", function() GameTooltip:Hide() end)
		itemSlots[i] = s
	end

	frame.save = MM:Button(frame, "Add to queue", 110, 22)
	frame.save:SetPoint("BOTTOMLEFT", 14, 12)
	frame.save:SetScript("OnClick", Save)
	local new = MM:Button(frame, "Clear", 70, 22)
	new:SetPoint("LEFT", frame.save, "RIGHT", 6, 0)
	new:SetScript("OnClick", function()
		draft, editIndex = NewDraft(), nil
		wipe(slideAdded)
		Q:UpdateEditor()
		Q:UpdateList()
	end)
	frame.sendNow = MM:Button(frame, "Send now", 100, 22)
	frame.sendNow:SetPoint("BOTTOMRIGHT", -14, 12)
	frame.sendNow:SetScript("OnClick", function()
		if not MM.Inbox.open then MM:Print("Open a mailbox to send prepared mail.") return end
		Q:Run()
	end)
	MM:Tooltip(frame.sendNow, "Send now", "Sends all prepared mail (only at a mailbox).")

	frame:SetScript("OnShow", function() Q:UpdateList() end)
end

function Q:Show()
	if not frame then Q:Build() end
	draft = draft or NewDraft()
	frame:Show()
	Q:UpdateEditor()
	Q:UpdateList()
end

------------------------------------------------------------------------
-- Sending at the mailbox
------------------------------------------------------------------------
local function FindStack(id)
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			if MM:ItemID(GetContainerItemLink(bag, slot)) == id and MM:IsMailable(bag, slot) then
				local _, count = GetContainerItemInfo(bag, slot)
				return bag, slot, count or 1
			end
		end
	end
end

function Q:Run()
	local q = Queue()
	local Send = MM.Send
	if #q == 0 or Q.running or Send.busy or Send.sending then return end
	if not SendMailFrame:IsVisible() then MailFrameTab2:Click() end
	Q.running = true
	Send.busy = true
	MM:Print(format("Sending %d prepared mail(s)...", #q))
	local qi, sent = 1, 0
	local pending, moneyLeft

	local function finish(msg)
		Q.running = false
		Send.busy = false
		MM:Print(msg or format("Prepared mail: %d mail(s) sent.%s", sent, #q > 0 and format(" %d left in the queue (/mm queue).", #q) or ""))
		Q:UpdateList()
		if MM.Inbox.open and MailFrameTab1 then MM:After(0.5, function() if MM.Inbox.open then MailFrameTab1:Click() end end) end
	end

	local nextMail
	local function fill(done)
		if not Send.FreeAttach() then return done() end
		local p
		for _, e in ipairs(pending) do
			if e.left > 0 then p = e break end
		end
		if not p then return done() end
		local b, s, c = FindStack(p.id)
		if not b then
			p.left = 0
			return fill(done)
		end
		if c <= p.left then
			Send.Attach(b, s)
			p.left = p.left - c
			return fill(done)
		end
		Send:MakeStack(p.id, p.left, function(bb, ss)
			if bb then Send.Attach(bb, ss) end
			p.left = 0
			MM:After(0.2, function() fill(done) end)
		end)
	end

	nextMail = function()
		if not SendMailFrame:IsVisible() then return finish("Mailbox closed - prepared mail stopped.") end
		local m = q[qi]
		if not m then return finish() end
		if not pending then
			pending = {}
			for _, e in ipairs(m.items) do
				local have = GetItemCount(e.id)
				local n = e.all and have or min(e.count, have)
				if n < (e.all and 1 or e.count) then
					MM:Print(format("%s: only %d of %s in your bags.", m.to, have, (GetItemInfo(e.id)) or ("item " .. e.id)))
				end
				if n > 0 then tinsert(pending, { id = e.id, left = n }) end
			end
			moneyLeft = m.money or 0
			if moneyLeft > 0 and GetMoney() < moneyLeft + 30 * 12 then
				MM:Print(format("Not enough gold for the mail to %s - sending it without gold.", m.to))
				moneyLeft = 0
			end
		end
		fill(function()
			local attached = 0
			for i = 1, ATTACHMENTS_MAX_SEND or 12 do
				if GetSendMailItem(i) then attached = attached + 1 end
			end
			if attached == 0 and moneyLeft <= 0 then
				-- nothing (left) to send for this mail
				tremove(q, qi)
				pending = nil
				return nextMail()
			end
			SendMailNameEditBox:SetText(m.to)
			local subject = m.subject ~= "" and m.subject or (GetSendMailItem(1)) or "MailMaster"
			SendMailSubjectEditBox:SetText(subject)
			if moneyLeft > 0 then
				SendMailSendMoneyButton:Click()
				MoneyInputFrame_SetCopper(SendMailMoney, moneyLeft)
				moneyLeft = 0
			end
			Send.onSent = function(ok)
				if not ok then
					pending = nil
					qi = qi + 1
					MM:Print("Sending to " .. m.to .. " failed - it stays in the queue.")
					return MM:After(0.5, nextMail)
				end
				sent = sent + 1
				local more = false
				for _, e in ipairs(pending) do if e.left > 0 then more = true end end
				if not more then
					tremove(q, qi)
					pending = nil
				end
				MM:After(0.5, nextMail)
			end
			Send:SendNow(false)
		end)
	end
	nextMail()
end

------------------------------------------------------------------------
function Q:Init()
	hooksecurefunc("PickupContainerItem", function(bag, slot) lastPick = { bag, slot } end)

	-- Alt-slide into the draft while the queue window is open (away from the mailbox)
	hooksecurefunc(GameTooltip, "SetBagItem", function(_, bag, slot)
		if not frame or not frame:IsVisible() or not IsAltKeyDown() or SendMailFrame:IsVisible() then return end
		if not bag or bag < 0 or bag > NUM_BAG_SLOTS then return end
		local key = bag .. ":" .. slot
		if slideAdded[key] then return end
		local link = GetContainerItemLink(bag, slot)
		if not link or not MM:IsMailable(bag, slot) then return end
		slideAdded[key] = true
		local _, count = GetContainerItemInfo(bag, slot)
		ReadEditor()
		Q:AddItem(MM:ItemID(link), count or 1)
	end)

	MM:On("MAIL_SHOW", function()
		if #Queue() == 0 then return end
		if MM.db.queueAuto then
			MM:After(1.2, function() if MM.Inbox.open then Q:Run() end end)
		else
			MM:Print(format("You have %d prepared mail(s). /mm queue to send them.", #Queue()))
		end
	end)
	MM:On("MAIL_SHOW", function() if frame and frame:IsVisible() then Q:UpdateList() end end)
	MM:On("MAIL_CLOSED", function() if frame and frame:IsVisible() then Q:UpdateList() end end)
end
