-- MailMaster - options (Esc > Interface > AddOns > MailMaster). Pages are built the first time they are shown.
local ADDON, MM = ...
local Options = {}
MM.Options = Options

local format = format
local pages = {}
local uid = 0
local function Name()
	uid = uid + 1
	return "MailMasterOpt" .. uid
end

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
local function Header(p, text, x, y)
	local fs = MM:Title(p, text)
	fs:SetPoint("TOPLEFT", x, y)
	return fs
end

local function Note(p, text, x, y, w)
	local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetWidth(w or 390)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

-- get/set can be a settings key or functions
local function Check(p, label, key, x, y, tip, onChange)
	local cb = CreateFrame("CheckButton", Name(), p, "OptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	_G[cb:GetName() .. "Text"]:SetText(label)
	local get = type(key) == "function" and key or function() return MM.db[key] end
	cb:SetScript("OnShow", function(self) self:SetChecked(get() and 1 or nil) end)
	cb:SetScript("OnClick", function(self)
		local v = self:GetChecked() and true or false
		if type(key) == "string" then MM.db[key] = v end
		if onChange then onChange(v) end
	end)
	if tip then
		cb.tooltipText = label
		cb.tooltipRequirement = tip
	end
	cb:SetChecked(get() and 1 or nil)
	return cb
end

local function Slider(p, label, key, lo, hi, step, x, y, fmt, w)
	local name = Name()
	local s = CreateFrame("Slider", name, p, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", x, y)
	s:SetWidth(w or 200)
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	_G[name .. "Low"]:SetText(format(fmt, lo))
	_G[name .. "High"]:SetText(format(fmt, hi))
	s:SetScript("OnValueChanged", function(self, v)
		v = floor(v / step + 0.5) * step
		MM.db[key] = v
		_G[name .. "Text"]:SetText(label .. ": " .. format(fmt, v))
	end)
	s:SetScript("OnShow", function(self) self:SetValue(MM.db[key]) end)
	s:SetValue(MM.db[key])
	return s
end

local function Dropdown(p, label, x, y, width, items, get, set)
	local dd = CreateFrame("Frame", Name(), p, "UIDropDownMenuTemplate")
	dd:SetPoint("TOPLEFT", x - 16, y - 14)
	local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 18, 2)
	fs:SetText(label)
	UIDropDownMenu_SetWidth(dd, width)
	local function textFor(v)
		for _, it in ipairs(items()) do if it.value == v then return it.text end end
		return tostring(v or "")
	end
	UIDropDownMenu_Initialize(dd, function(self, level)
		for _, it in ipairs(items()) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = it.text
			info.value = it.value
			info.checked = get() == it.value
			info.func = function()
				set(it.value)
				UIDropDownMenu_SetText(dd, it.text)
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	dd:SetScript("OnShow", function() UIDropDownMenu_SetText(dd, textFor(get())) end)
	UIDropDownMenu_SetText(dd, textFor(get()))
	dd.Refresh = function() UIDropDownMenu_SetText(dd, textFor(get())) end
	return dd
end

local function EditBox(p, w, x, y)
	local eb = CreateFrame("EditBox", Name(), p, "InputBoxTemplate")
	eb:SetWidth(w)
	eb:SetHeight(20)
	eb:SetPoint("TOPLEFT", x, y)
	eb:SetAutoFocus(false)
	eb:SetScript("OnEscapePressed", eb.ClearFocus)
	eb:SetScript("OnEnterPressed", eb.ClearFocus)
	return eb
end

-- simple scrolling list: getItems() -> list, render(row, item)
local function List(p, x, y, w, nrows, getItems, render, onDelete, onToggle)
	local RH = 20
	local list = {}
	local scroll = CreateFrame("ScrollFrame", Name(), p, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", x, y)
	scroll:SetWidth(w)
	scroll:SetHeight(nrows * RH)
	local bg = MM:Panel(nil, p)
	bg:SetPoint("TOPLEFT", x - 6, y + 6)
	bg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 26, -6)
	bg:SetFrameLevel(p:GetFrameLevel())
	local rows = {}
	local function update()
		local items = getItems()
		FauxScrollFrame_Update(scroll, #items, nrows, RH)
		local off = FauxScrollFrame_GetOffset(scroll)
		for i = 1, nrows do
			local row, it = rows[i], items[i + off]
			row.index = i + off
			if it then
				render(row, it)
				if onToggle then row.on:SetChecked(it.on and 1 or nil) end
				row:Show()
			else
				row:Hide()
			end
		end
	end
	scroll:SetScript("OnVerticalScroll", function(self, o) FauxScrollFrame_OnVerticalScroll(self, o, RH, update) end)
	for i = 1, nrows do
		local row = CreateFrame("Frame", nil, p)
		row:SetWidth(w)
		row:SetHeight(RH)
		row:SetPoint("TOPLEFT", x, y - (i - 1) * RH)
		row:SetFrameLevel(bg:GetFrameLevel() + 2)
		local tx = 4
		if onToggle then
			row.on = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
			row.on:SetWidth(20)
			row.on:SetHeight(20)
			row.on:SetPoint("LEFT", 0, 0)
			row.on:SetScript("OnClick", function(self) onToggle(row.index, self:GetChecked() and true or false) end)
			tx = 24
		end
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", tx, 0)
		row.text:SetWidth(w - tx - 24)
		row.text:SetJustifyH("LEFT")
		local del = CreateFrame("Button", nil, row)
		del:SetWidth(14)
		del:SetHeight(14)
		del:SetPoint("RIGHT", -4, 0)
		del:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
		del:SetScript("OnClick", function() onDelete(row.index); update() end)
		rows[i] = row
	end
	p:HookScript("OnShow", update)
	update()
	return update
end

------------------------------------------------------------------------
-- Pages (the options area is only ~400 wide)
------------------------------------------------------------------------
local function Inbox(p)
	Header(p, "MailMaster " .. MM.version, 16, -16)
	Note(p, "/mm alts  ·  /mm inbox <name>  ·  /mm queue  ·  /mm sent  ·  /mm help", 16, -34)

	Header(p, "Open All", 16, -58)
	Slider(p, "Delay", "speed", 0, 1, 0.01, 20, -90, "%.2fs", 170)
	Slider(p, "Keep bag slots free", "keepFree", 0, 10, 1, 214, -90, "%d", 170)
	Note(p, "Open All takes:", 16, -122)
	for i, k in ipairs(MM.Inbox.typeOrder) do
		local col = (i - 1) % 2
		local row = floor((i - 1) / 2)
		Check(p, MM.Inbox.shortLabels[k], function() return MM.db.filters[k] end, 12 + col * 196, -134 - row * 22, nil,
			function(v) MM.db.filters[k] = v end)
	end
	Note(p, "CoD and GM mail is never opened. Shift-click Open All to take everything.", 16, -226, 390)

	Header(p, "Inbox", 16, -252)
	Check(p, "Select checkboxes", "checkboxes", 12, -268, nil, function() MM.Inbox:ApplyLayout() end)
	Check(p, "Delete / return X", "deleteButton", 208, -268, nil, function() if InboxFrame:IsVisible() then InboxFrame_Update() end end)
	Check(p, "Confirm deleting items", "confirmDelete", 12, -290)
	Check(p, "Summary line", "summary", 208, -290, nil, function() if InboxFrame:IsVisible() then InboxFrame_Update() end end)
	Check(p, "Show gold collected", "rake", 12, -312)
	Check(p, "Print each mail in chat", "verbose", 208, -312)
	Slider(p, "Expiry warning", "expiryDays", 1, 7, 1, 20, -358, "%d days", 170)
	local frames = function()
		local t = {}
		for i = 1, NUM_CHAT_WINDOWS or 7 do
			local n = GetChatWindowInfo(i)
			if n and n ~= "" then t[#t + 1] = { text = i .. ": " .. n, value = i } end
		end
		return t
	end
	Dropdown(p, "Chat window", 214, -344, 130, frames,
		function() return MM.db.chatFrame end, function(v) MM.db.chatFrame = v end)
end

local function Sending(p)
	Header(p, "Sending", 16, -16)
	Note(p, "|cffffffffAlt|r + mouse over bag items: attach them.\n|cffffffffAlt+Shift|r: attach every stack of that item.\n|cffffffffCtrl+Alt|r over an attachment: take it back out.\nWorks with default bags, Bagnon, AdiBags and ElvUI bags.", 16, -36, 390)
	Check(p, "Alt + mouse slide attaches items", "slide", 12, -100)
	Check(p, "Mail full (12/12): send it, keep the name", "slideAutoSend", 12, -124,
		"During an Alt-slide the mail is sent as soon as all 12 slots are used, then the next mail to the same name starts.")
	Check(p, "Wire: gold amount as subject", "wire", 12, -148)
	Check(p, "CoD helper: suggest a CoD price", "codHelper", 12, -172,
		"Uses AuctionaryPro, Auctionator or the vendor price.", function() MM.Send:UpdateCOD() end)
	Check(p, "Side panel (contacts, quick attach, rules)", "contacts", 12, -196, nil, function() MM.Send:ApplyPanel() end)
	Check(p, "Complete names (favourites, alts, recent)", "autocomplete", 12, -220)
	Check(p, "Send prepared mail when the mailbox opens", "queueAuto", 12, -244, "Prepare mails anywhere with /mm queue.")
	local qb = MM:Button(p, "Prepared mail...", 120, 20)
	qb:SetPoint("TOPLEFT", 290, -246)
	qb:SetScript("OnClick", function() MM.Queue:Show() end)

	Header(p, "While the mailbox is open", 16, -280)
	Check(p, "Block trade requests", "blockTrade", 12, -298)
	Check(p, "Decline guild invites", "blockGuild", 12, -322)
	Check(p, "Decline group invites", "blockParty", 12, -346)
end

local function Rules(p)
	Header(p, "Auto return / delete", 16, -16)
	Note(p, "Return sends player mail back. Delete only removes mail without gold, items or CoD.", 16, -36, 390)
	Check(p, "Run when the mailbox opens", "rulesAuto", 12, -58)
	Check(p, "Test mode (only print)", "rulesTest", 208, -58)

	local act, field = "return", "sender"
	local acts = function() return { { text = "Return", value = "return" }, { text = "Delete", value = "delete" } } end
	local fields = function() return { { text = "Sender contains", value = "sender" }, { text = "Subject contains", value = "subject" } } end
	Dropdown(p, "Action", 16, -96, 80, acts, function() return act end, function(v) act = v end)
	Dropdown(p, "When", 140, -96, 120, fields, function() return field end, function(v) field = v end)
	local text = EditBox(p, 260, 22, -160)
	local tl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tl:SetPoint("BOTTOMLEFT", text, "TOPLEFT", -4, 2)
	tl:SetText("Text")
	local update
	local add = MM:Button(p, "Add", 70, 22)
	add:SetPoint("LEFT", text, "RIGHT", 12, 0)
	add:SetScript("OnClick", function()
		local t = text:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		if t == "" then return end
		tinsert(MailMasterDB.rules, { on = true, act = act, field = field, text = t })
		text:SetText("")
		update()
	end)

	update = List(p, 22, -196, 350, 9,
		function() return MailMasterDB.rules end,
		function(row, r)
			row.text:SetText(format("%s if %s has \"|cffffffff%s|r\"",
				r.act == "return" and "|cffffd200Return|r" or "|cffff6060Delete|r", r.field, r.text))
		end,
		function(i) tremove(MailMasterDB.rules, i) end,
		function(i, v) if MailMasterDB.rules[i] then MailMasterDB.rules[i].on = v end end)

	local test = MM:Button(p, "Test now", 100, 22)
	test:SetPoint("TOPLEFT", 16, -388)
	test:SetScript("OnClick", function() MM.Inbox:RunRules(true) end)
	local run = MM:Button(p, "Run now", 100, 22)
	run:SetPoint("LEFT", test, "RIGHT", 8, 0)
	run:SetScript("OnClick", function() MM.Inbox:RunRules(false) end)
	Note(p, "(at a mailbox)", 232, -394, 150)
end

local function SendRules(p)
	Header(p, "Send rules", 16, -16)
	Note(p, "\"Send by rules\" in the side panel packs matching items into mails to your alts (preview first). \"Never send\" is checked first, then the first matching rule wins.", 16, -36, 390)

	local cat, item, itemName = "Herb", nil, nil
	local cats = function()
		local t = {}
		for _, c in ipairs(MM.categories) do t[#t + 1] = { text = c.label, value = c.key } end
		t[#t + 1] = { text = "One item (use the slot)", value = "ITEM" }
		return t
	end
	local dd = Dropdown(p, "What", 16, -84, 140, cats, function() return cat end, function(v) cat = v end)

	local slot = CreateFrame("Button", nil, p)
	slot:SetWidth(30)
	slot:SetHeight(30)
	slot:SetPoint("TOPLEFT", 196, -98)
	slot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
	slot.icon = slot:CreateTexture(nil, "OVERLAY")
	slot.icon:SetAllPoints()
	local function grab()
		local kind, id, link = GetCursorInfo()
		if kind == "item" then
			item, itemName, cat = id, link, "ITEM"
			slot.icon:SetTexture((GetItemIcon and GetItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
			dd.Refresh()
			ClearCursor()
		end
	end
	slot:SetScript("OnClick", grab)
	slot:SetScript("OnReceiveDrag", grab)
	MM:Tooltip(slot, "Item", "Drop an item here for a rule about that one item.")

	local to = EditBox(p, 130, 22, -150)
	local tl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tl:SetPoint("BOTTOMLEFT", to, "TOPLEFT", -4, 2)
	tl:SetText("Send to")
	local never = Check(p, "Never send", function() return false end, 162, -146)

	local update
	local add = MM:Button(p, "Add", 70, 22)
	add:SetPoint("TOPLEFT", 300, -148)
	add:SetScript("OnClick", function()
		local r = {}
		if cat == "ITEM" then
			if not item then MM:Print("Drop an item on the slot first.") return end
			r.item, r.name = item, itemName
		else
			r.cat = cat
		end
		if not never:GetChecked() then
			r.to = MM:NormName(to:GetText())
			if not r.to then MM:Print("Enter the name of the alt to send to.") return end
		end
		tinsert(MailMasterDB.sendRules, r)
		to:SetText("")
		never:SetChecked(nil)
		update()
	end)

	update = List(p, 22, -190, 350, 10,
		function() return MailMasterDB.sendRules end,
		function(row, r)
			local what = MM.Send:RuleLabel(r)
			if r.item and r.name then what = r.name end
			if r.to then
				row.text:SetText(format("%s  ->  |cffffffff%s|r", what, r.to))
			else
				row.text:SetText(format("|cffff6060Never send|r  %s", what))
			end
		end,
		function(i) tremove(MailMasterDB.sendRules, i) end)
end

local function Appearance(p)
	Header(p, "Appearance", 16, -16)
	local themes = function()
		local t = {}
		for _, th in ipairs(MM.themes) do t[#t + 1] = { text = th[1], value = th[1] } end
		return t
	end
	Dropdown(p, "Colour theme", 16, -50, 150, themes, function() return MM.db.theme end,
		function(v) MM.db.theme = v; MM:ApplyTheme(); MM.Send.UpdateList() end)
	Check(p, "Minimap button", "minimap", 208, -58,
		"Left-click: prepared mail. Shift-click: sent mail log. Right-click: options. Drag to move.",
		function() MM.Log:ApplyMinimap() end)
	Check(p, "Tell me about new versions", "versionCheck", 208, -80,
		"Players with MailMaster in your guild or group quietly share their version. If someone has a newer one, you get a message once.")

	Header(p, "Settings profile", 16, -110)
	Note(p, "By default all characters share one set of settings.", 16, -130, 390)
	Check(p, "Separate settings for this character", function() return MailMasterCharDB.own end, 12, -146, nil,
		function(v)
			if v and not MailMasterCharDB.settings then
				MailMasterCharDB.settings = MM.CopyDefaults({}, MailMasterDB.settings)
			end
			MailMasterCharDB.own = v
			MM:UseSettings()
			MM.Inbox:ApplyLayout()
		end)
	local copy = MM:Button(p, "Copy shared settings to this character", 260, 22)
	copy:SetPoint("TOPLEFT", 20, -178)
	copy:SetScript("OnClick", function()
		MailMasterCharDB.settings = MM.CopyDefaults({}, MailMasterDB.settings)
		MailMasterCharDB.own = true
		MM:UseSettings()
		MM:Print("This character now uses its own copy of the shared settings.")
	end)
	local reset = MM:Button(p, "Reset to defaults", 160, 22)
	reset:SetPoint("TOPLEFT", 20, -206)
	reset:SetScript("OnClick", function() StaticPopup_Show("MAILMASTER_RESET") end)

	Header(p, "Saved data", 16, -246)
	Note(p, "Remove a character you deleted from the overview:", 16, -266, 390)
	local who = EditBox(p, 140, 22, -284)
	local del = MM:Button(p, "Forget character", 130, 22)
	del:SetPoint("LEFT", who, "RIGHT", 10, 0)
	del:SetScript("OnClick", function()
		local n = MM:NormName(who:GetText())
		if n and n ~= MM.player and MM.realm.chars[n] then
			MM.realm.chars[n] = nil
			MM.favs[n] = nil
			MM:Print(n .. " removed.")
			who:SetText("")
		end
	end)

	Dropdown(p, "Keep mail log (sent + received) for", 16, -322, 120, function() return MM.Log.keepOptions end,
		function() return MM.db.sentKeep end, function(v) MM.db.sentKeep = v; MM.Log:Prune() end)
	local open = MM:Button(p, "Mail log...", 120, 22)
	open:SetPoint("TOPLEFT", 196, -338)
	open:SetScript("OnClick", function() MM.Log:Show() end)
end

StaticPopupDialogs["MAILMASTER_RESET"] = {
	text = "Reset MailMaster settings to the defaults?",
	button1 = YES, button2 = NO,
	OnAccept = function() MM:ResetSettings(); MM.Inbox:ApplyLayout(); ReloadUI() end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

------------------------------------------------------------------------
local defs = {
	{ "MailMaster", Inbox },
	{ "Sending", Sending },
	{ "Rules", Rules },
	{ "Send Rules", SendRules },
	{ "Appearance", Appearance },
}

function Options:Init()
	for i, d in ipairs(defs) do
		local p = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)
		p.name = d[1]
		if i > 1 then p.parent = "MailMaster" end
		p:Hide()
		p:SetScript("OnShow", function(self)
			if not self.built then
				self.built = true
				d[2](self)
			end
		end)
		InterfaceOptions_AddCategory(p)
		pages[d[1]] = p
	end
end

function Options:Open(page)
	local p = pages[page or "MailMaster"] or pages.MailMaster
	InterfaceOptionsFrame_OpenToCategory(p)
	InterfaceOptionsFrame_OpenToCategory(p)
end
