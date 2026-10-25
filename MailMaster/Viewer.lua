-- MailMaster - alt mail overview and remote inbox (/mm alts, /mm inbox)
local ADDON, MM = ...
local Viewer = {}
MM.Viewer = Viewer

local format, floor = format, floor
local frame, charScroll, mailScroll
local charRows, mailRows = {}, {}
local chars, mails = {}, {}
local selected
local CROWS, MROWS, RH = 15, 15, 20

local function Remaining(c, e)
	return (e.d or 0) - (time() - (c.t or time())) / 86400
end

local function Stats(c)
	local n, gold, items, soon = 0, 0, 0, nil
	for _, e in ipairs(c.inbox or {}) do
		local rem = Remaining(c, e)
		if rem > 0 then
			n = n + 1
			gold = gold + (e.m or 0)
			if e.it then items = items + #e.it / 2 end
			if (e.m or e.it) and (not soon or rem < soon) then soon = rem end
		end
	end
	return n, gold, items, soon
end

local function DaysText(d)
	if not d then return "" end
	local col = d < 1 and "ff4040" or d < (MM.db.expiryDays or 3) and "ff8000" or "40ff40"
	if d < 1 then return format("|cff%s%dh|r", col, floor(d * 24)) end
	return format("|cff%s%dd|r", col, floor(d))
end

local function Ago(t)
	if not t then return "never" end
	local s = time() - t
	if s < 3600 then return floor(s / 60) .. " min ago" end
	if s < 86400 then return floor(s / 3600) .. " h ago" end
	return floor(s / 86400) .. " days ago"
end

local function ItemIcon(id)
	return (GetItemIcon and GetItemIcon(id)) or select(10, GetItemInfo(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

------------------------------------------------------------------------
function Viewer:UpdateChars()
	FauxScrollFrame_Update(charScroll, #chars, CROWS, RH)
	local off = FauxScrollFrame_GetOffset(charScroll)
	for i = 1, CROWS do
		local row, name = charRows[i], chars[i + off]
		if name then
			local c = MM.realm.chars[name]
			local n, gold, items, soon = Stats(c)
			local extra = (c.total and c.inbox and c.total > #c.inbox) and format("+%d", c.total - #c.inbox) or ""
			row.name:SetText("|cff" .. MM:ClassHex(c.class) .. name .. "|r" .. (c.faction ~= MM.faction and " |cff808080(" .. (c.faction or "?") .. ")|r" or ""))
			row.mails:SetText(c.inbox and (n .. (extra ~= "" and (" " .. extra) or "")) or "|cff808080-|r")
			row.gold:SetText(gold > 0 and MM:Money(gold, true) or "")
			row.exp:SetText(DaysText(soon))
			row.name2 = name
			if name == selected then row:LockHighlight() else row:UnlockHighlight() end
			row:Show()
		else
			row:Hide()
		end
	end
end

function Viewer:UpdateMails()
	local c = selected and MM.realm.chars[selected]
	wipe(mails)
	if c and c.inbox then
		for _, e in ipairs(c.inbox) do
			if Remaining(c, e) > 0 then mails[#mails + 1] = e end
		end
	end
	if c then
		frame.mailTitle:SetText(format("%s's inbox |cffaaaaaa- last seen %s%s|r", selected, Ago(c.t),
			(c.total and c.inbox and c.total > #c.inbox) and format(", %d more on the server", c.total - #c.inbox) or ""))
	end
	FauxScrollFrame_Update(mailScroll, #mails, MROWS, RH)
	local off = FauxScrollFrame_GetOffset(mailScroll)
	for i = 1, MROWS do
		local row, e = mailRows[i], mails[i + off]
		row.e = e
		if e then
			local icon = "Interface\\Icons\\INV_Scroll_03"
			if e.it and e.it[1] then icon = ItemIcon(e.it[1])
			elseif e.m then icon = "Interface\\Icons\\INV_Misc_Coin_01" end
			row.icon:SetTexture(icon)
			row.from:SetText(e.s or "?")
			row.subj:SetText((e.c and "|cffff4040CoD|r " or "") .. (e.j or ""))
			local it = e.it and (#e.it / 2) or 0
			row.money:SetText((e.m and MM:Money(e.m, true) or "") .. (it > 1 and ("  |cffaaaaaax" .. it .. "|r") or ""))
			row.exp:SetText(DaysText(Remaining(c, e)))
			row:Show()
		else
			row:Hide()
		end
	end
	if #mails == 0 then
		frame.empty:SetText(c and (c.inbox and "No mail." or "Open a mailbox on this character once to see its inbox here.") or "")
		frame.empty:Show()
	else
		frame.empty:Hide()
	end
end

function Viewer:Refresh()
	wipe(chars)
	for name in pairs(MM.realm.chars) do chars[#chars + 1] = name end
	table.sort(chars, function(a, b)
		if a == MM.player then return true end
		if b == MM.player then return false end
		return a < b
	end)
	Viewer:UpdateChars()
	Viewer:UpdateMails()
end

local function MailTooltip(row)
	local e = row.e
	if not e then return end
	local c = MM.realm.chars[selected]
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(e.j or "?", 1, 1, 1, true)
	GameTooltip:AddLine("From: " .. (e.s or "?"), 0.8, 0.8, 0.8)
	if e.m then GameTooltip:AddLine("Gold: " .. MM:Money(e.m), 1, 1, 1) end
	if e.c then GameTooltip:AddLine("CoD: " .. MM:Money(e.c), 1, 0.3, 0.3) end
	if e.it then
		for k = 1, #e.it, 2 do
			local id, count = e.it[k], e.it[k + 1]
			local name, link = GetItemInfo(id)
			GameTooltip:AddLine("|T" .. ItemIcon(id) .. ":14|t " .. (link or name or ("item:" .. id)) .. ((count or 1) > 1 and (" x" .. count) or ""))
		end
	end
	local rem = Remaining(c, e)
	GameTooltip:AddLine(format("Expires in %s, then it is %s.", SecondsToTime(rem * 86400), e.r and "returned to the sender" or "deleted"), 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

function Viewer:Build()
	frame = MM:Panel("MailMasterViewer", UIParent, 640, 420)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	MM:MakeMovable(frame)
	tinsert(UISpecialFrames, "MailMasterViewer")
	local title = MM:Title(frame, "MailMaster - mail overview")
	title:SetPoint("TOP", 0, -12)
	MM:CloseButton(frame)

	-- characters
	local h = MM:Title(frame, "Character            Mails        Gold          Exp.", "small")
	h:SetPoint("TOPLEFT", 16, -36)
	charScroll = CreateFrame("ScrollFrame", "MailMasterViewerChars", frame, "FauxScrollFrameTemplate")
	charScroll:SetPoint("TOPLEFT", 12, -52)
	charScroll:SetWidth(232)
	charScroll:SetHeight(CROWS * RH)
	charScroll:SetScript("OnVerticalScroll", function(self, o)
		FauxScrollFrame_OnVerticalScroll(self, o, RH, Viewer.UpdateChars)
	end)
	for i = 1, CROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetWidth(240)
		row:SetHeight(RH)
		row:SetPoint("TOPLEFT", 14, -52 - (i - 1) * RH)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		local function fs(x, w, j)
			local f = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			f:SetPoint("LEFT", x, 0)
			f:SetWidth(w)
			f:SetJustifyH(j or "LEFT")
			return f
		end
		row.name = fs(2, 100)
		row.mails = fs(104, 40, "RIGHT")
		row.gold = fs(146, 64, "RIGHT")
		row.exp = fs(212, 26, "RIGHT")
		row:SetScript("OnClick", function(self)
			selected = self.name2
			FauxScrollFrame_SetOffset(mailScroll, 0)
			mailScroll:SetVerticalScroll(0)
			Viewer:Refresh()
		end)
		charRows[i] = row
	end

	-- mails of the selected character
	frame.mailTitle = MM:Title(frame, "", "small")
	frame.mailTitle:SetPoint("TOPLEFT", 270, -36)
	frame.mailTitle:SetWidth(350)
	frame.mailTitle:SetJustifyH("LEFT")
	mailScroll = CreateFrame("ScrollFrame", "MailMasterViewerMails", frame, "FauxScrollFrameTemplate")
	mailScroll:SetPoint("TOPLEFT", 266, -52)
	mailScroll:SetWidth(340)
	mailScroll:SetHeight(MROWS * RH)
	mailScroll:SetScript("OnVerticalScroll", function(self, o)
		FauxScrollFrame_OnVerticalScroll(self, o, RH, Viewer.UpdateMails)
	end)
	for i = 1, MROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetWidth(346)
		row:SetHeight(RH)
		row:SetPoint("TOPLEFT", 268, -52 - (i - 1) * RH)
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
		row.from = fs(22, 78)
		row.subj = fs(102, 140)
		row.money = fs(244, 72, "RIGHT")
		row.exp = fs(318, 26, "RIGHT")
		row:SetScript("OnEnter", MailTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		mailRows[i] = row
	end
	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("TOP", frame, "TOPLEFT", 440, -120)
	frame.empty:SetWidth(320)

	local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("BOTTOMLEFT", 16, 14)
	note:SetText("Updated each time you open a mailbox. Mail you send to your alts is added right away.")
end

function Viewer:Show(name)
	if not frame then Viewer:Build() end
	selected = (name and MM.realm.chars[name]) and name or selected or MM.player
	frame:Show()
	Viewer:Refresh()
end

-- Login warning: mail with gold/items about to expire on any character
function Viewer:Init()
	local warned
	MM:On("PLAYER_ENTERING_WORLD", function()
		if warned then return end
		warned = true
		MM:After(8, function()
			for name, c in pairs(MM.realm.chars) do
				local count, soonest = 0, nil
				for _, e in ipairs(c.inbox or {}) do
					local rem = Remaining(c, e)
					if rem > 0 and rem < MM.db.expiryDays and (e.m or e.it) then
						count = count + 1
						if not soonest or rem < soonest then soonest = rem end
					end
				end
				if count > 0 then
					MM:Print(format("|cffff8000%s: %d mail(s) with gold or items expire within %d days|r (first in %s). /mm alts",
						name, count, MM.db.expiryDays, SecondsToTime(soonest * 86400)))
				end
			end
		end)
	end)
end
