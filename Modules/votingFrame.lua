---	votingFrame.lua	Displays everything related to handling loot for all members.
--	Will only show certain aspects depending on addon.isMasterLooter, addon.isCouncil and addon.mldb.observe.
-- DefaultModule
-- @author	Potdisc
-- Create Date : 12/15/2014 8:54:35 PM

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
RCVotingFrame = addon:NewModule("RCVotingFrame", "AceComm-3.0", "AceTimer-3.0")
local LibDialog = LibStub("LibDialog-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("RCLootCouncil")
local EPGP	= LibStub("AceAddon-3.0"):GetAddon("EPGP")

local ROW_HEIGHT = 20;
local NUM_ROWS = 15;
local db
local session = 1 -- The session we're viewing
local lootTable = {} -- Table containing all data, lib-st cells pulls data from this
local sessionButtons = {}
local moreInfo = false -- Show more info frame?
local active = false -- Are we currently in session?
local candidates = {} -- Candidates for the loot, initial data from the ML
local councilInGroup = {}
local menuFrame -- Right click menu frame
local filterMenu -- Filter drop down menu
local enchanters -- Enchanters drop down menu frame
local guildRanks = {} -- returned from addon:GetGuildRanks()
local GuildRankSort, ResponseSort -- Initialize now to avoid errors
local defaultScrollTableData = {} -- See below
local moreInfoData = {}

function RCVotingFrame:OnInitialize()
	if(EPGP==nil)then
		print("EPGP NOT FOUND SON")
	end

	-- Contains all the default data needed for the scroll table
	-- The default values are in sorted order
	defaultScrollTableData = {
		{ name = "",				DoCellUpdate = RCVotingFrame.SetCellClass,		colName = "class",	sortnext = 2,		width = 20, },										-- 1 Class
		{ name = L["Name"],		DoCellUpdate = RCVotingFrame.SetCellName,			colName = "name",								width = 120,},										-- 2 Candidate Name
		{ name = L["Rank"],		DoCellUpdate = RCVotingFrame.SetCellRank,			colName = "rank",		sortnext = 5,		width = 95, comparesort = GuildRankSort,},-- 3 Guild rank
		{ name = L["Role"],		DoCellUpdate = RCVotingFrame.SetCellRole,			colName = "role",		sortnext = 5,		width = 55, },										-- 4 Role
		{ name = L["Response"],	DoCellUpdate = RCVotingFrame.SetCellResponse,	colName = "response",sortnext = 13,		width = 240, comparesort = ResponseSort,},-- 5 Response
		{ name = L["ilvl"],		DoCellUpdate = RCVotingFrame.SetCellIlvl,			colName = "ilvl",		sortnext = 7,		width = 45, },										-- 6 Total ilvl
		{ name = "pr",		DoCellUpdate = RCVotingFrame.SetCellPR,			colName = "pr",		sortnext = 7,		width = 45, },										-- 7 pr
		{ name = L["Diff"],		DoCellUpdate = RCVotingFrame.SetCellDiff,			colName = "diff",								width = 40, },										-- 7 ilvl difference
		{ name = L["g1"],			DoCellUpdate = RCVotingFrame.SetCellGear,			colName = "gear1",	sortnext = 5,		width = 20, align = "CENTER", },				-- 8 Current gear 1
		{ name = L["g2"],			DoCellUpdate = RCVotingFrame.SetCellGear,			colName = "gear2",	sortnext = 5,		width = 20, align = "CENTER", },				-- 9 Current gear 2
		{ name = L["Votes"], 	DoCellUpdate = RCVotingFrame.SetCellVotes,		colName = "votes",	sortnext = 7,		width = 40, align = "CENTER", },				-- 10 Number of votes
		{ name = L["Vote"],		DoCellUpdate = RCVotingFrame.SetCellVote,			colName = "vote",		sortnext = 10,		width = 60, align = "CENTER", },				-- 11 Vote button
		{ name = L["Notes"],		DoCellUpdate = RCVotingFrame.SetCellNote,			colName = "note",								width = 40, align = "CENTER", },				-- 12 Note icon
		{ name = L["Roll"],		DoCellUpdate = RCVotingFrame.SetCellRoll, 		colName = "roll",		sortnext = 10,		width = 30, align = "CENTER", },				-- 13 Roll
	}
	-- The actual table being worked on, new entries should be added to this table "tinsert(RCVotingFrame.scrollCols, data)"
	-- If you want to add or remove columns, you should do so on your OnInitialize. See RCVotingFrame:RemoveColumn() for removal.
	self.scrollCols = {unpack(defaultScrollTableData)}

	menuFrame = CreateFrame("Frame", "RCLootCouncil_VotingFrame_RightclickMenu", UIParent, "Lib_UIDropDownMenuTemplate")
	filterMenu = CreateFrame("Frame", "RCLootCouncil_VotingFrame_FilterMenu", UIParent, "Lib_UIDropDownMenuTemplate")
	enchanters = CreateFrame("Frame", "RCLootCouncil_VotingFrame_EnchantersMenu", UIParent, "Lib_UIDropDownMenuTemplate")
	Lib_UIDropDownMenu_Initialize(menuFrame, self.RightClickMenu, "MENU")
	Lib_UIDropDownMenu_Initialize(filterMenu, self.FilterMenu)
	Lib_UIDropDownMenu_Initialize(enchanters, self.EnchantersMenu)
end

function RCVotingFrame:OnEnable()
	self:RegisterComm("RCLootCouncil")
	db = addon:Getdb()
	active = true
	moreInfo = db.modules["RCVotingFrame"].moreInfo
	moreInfoData = addon:GetLootDBStatistics()
	self.frame = self:GetFrame()
	self.pr = {};
	self:ScheduleTimer("CandidateCheck", 20)
	guildRanks = addon:GetGuildRanks()
	addon:Debug("RCVotingFrame", "enabled")
end

function RCVotingFrame:OnDisable() -- We never really call this
	self:Hide()
	self.frame:SetParent(nil)
	self.frame = nil
	wipe(lootTable)
	active = false
	session = 1
	self:UnregisterAllComm()
end

function RCVotingFrame:Hide()
	addon:Debug("Hide VotingFrame")
	self.frame.moreInfo:Hide()
	self.frame:Hide()
end

function RCVotingFrame:Show()
	if self.frame then
		councilInGroup = addon:GetCouncilInGroup()
		self.frame:Show()
		self:SwitchSession(session)
	else
		addon:Print(L["No session running"])
	end
end

function RCVotingFrame:EndSession(hide)
	active = false -- The session has ended, so deactivate
	self:Update()
	if hide then self:Hide() end -- Hide if need be
end

function RCVotingFrame:CandidateCheck()
	if not candidates[addon.playerName] and addon.masterLooter then -- If our own name isn't there, we assume it's not received
		addon:DebugLog("CandidateCheck", "failed")
		addon:SendCommand(addon.masterLooter, "candidates_request")
		self:ScheduleTimer("CandidateCheck", 20) -- check again in 20
	end
end

--- Removes a specific entry from the voting frame's columns
-- Takes either index or colName as the identifier, and returns the removed rows
-- if succesful, or nil if not. Should be called before any session begins.
function RCVotingFrame:RemoveColumn(id)
	addon:Debug("Removing Column", id)
	if type(id) == "number" then
		return tremove(self.scrollCols, id)
	else
		for i, col in ipairs(self.scrollCols) do
			if col.colName == id then
				return tremove(self.scrollCols, i)
			end
		end
	end
end

function RCVotingFrame:OnCommReceived(prefix, serializedMsg, distri, sender)
	if prefix == "RCLootCouncil" then
		-- data is always a table to be unpacked
		local test, command, data = addon:Deserialize(serializedMsg)
		if addon:HandleXRealmComms(self, command, data, sender) then return end

		if test then
			if command == "vote" then
				if addon:IsCouncil(sender) then
					local s, name, vote = unpack(data)
					self:HandleVote(s, name, vote, sender)
				else
					addon:Debug("Non-council member (".. tostring(sender) .. ") sent a vote!")
				end

			elseif command == "change_response" and addon:UnitIsUnit(sender, addon.masterLooter) then
				local ses, name, response, isTier = unpack(data)
				self:SetCandidateData(ses, name, "isTier", isTier)
				self:SetCandidateData(ses, name, "response", response)
				self:GetPRValues(ses)
				self:Update()

			elseif command == "lootAck" then
				local name = unpack(data)
				for i = 1, #lootTable do
					self:SetCandidateData(i, name, "response", "WAIT")
				end
				self:Update()

			elseif command == "awarded" and addon:UnitIsUnit(sender, addon.masterLooter) then
				self:ScheduleTimer(function()
					moreInfoData = addon:GetLootDBStatistics() -- Just update it on every award
				end, 1) -- Make sure we've received the history data before updating
				lootTable[unpack(data)].awarded = true
				if addon.isMasterLooter and session ~= #lootTable then -- ML should move to the next item on award
					self:SwitchSession(session + 1)
				else
					self:SwitchSession(session) -- Use switch session to update awardstring
				end

			elseif command == "candidates" and addon:UnitIsUnit(sender, addon.masterLooter) then
				candidates = unpack(data)

			elseif command == "offline_timer" and addon:UnitIsUnit(sender, addon.masterLooter) then
				for i = 1, #lootTable do
					for name in pairs(lootTable[i].candidates) do
						if self:GetCandidateData(i, name, "response") == "ANNOUNCED" then
							addon:DebugLog("No response from:", name)
							self:SetCandidateData(i, name, "response", "NOTHING")
						end
					end
				end
				self:Update()

			elseif command == "lootTable" and addon:UnitIsUnit(sender, addon.masterLooter) then
				active = true
				self:Setup(unpack(data))
				if not addon.enabled then return end -- We just want things ready
				if db.autoOpen then
					self:Show()
				else
					addon:Print(L["A new session has begun, type '/rc open' to open the voting frame."])
				end

			elseif command == "response" then
				local session, name, t = unpack(data)
				for k,v in pairs(t) do
					self:SetCandidateData(session, name, k, v);
				end
				self:GetPRValues(ses)
				self:Update()

			elseif command == "rolls" then
				if addon:UnitIsUnit(sender, addon.masterLooter) then
					local session, table = unpack(data)
					for name, roll in pairs(table) do
						self:SetCandidateData(session, name, "roll", roll)
					end
					self:Update()
				else
					addon:Debug("Non-ML", sender, "sent rolls!")
				end

			elseif command == "reconnectData" and addon:UnitIsUnit(sender, addon.masterLooter) then
				-- We assume we always receive a regular lootTable command first
				-- All we need to do is updating the loot table and figure out if we've voted previously
				lootTable = unpack(data)
				for _, data in ipairs(lootTable) do
					for _, cand in pairs(data.candidates) do
						for _, voter in ipairs(cand.voters) do
							if addon:UnitIsUnit(voter, "player") then -- WE've voted
								data.haveVoted = true
								cand.haveVoted = true
							end
						end
					end
				end
				self:Update()
				self:UpdatePeopleToVote()
			end
		end
	end
end

-- Getter/Setter for candidate data
-- Handles errors
function RCVotingFrame:SetCandidateData(session, candidate, data, val)
	--print("SetCandidateData: " .. (session or "") .. ", " .. (candidate or "") .. ", " .. (data  or "") .. ", " .. (val  or ""));
	local function Set(session, candidate, data, val)
		lootTable[session].candidates[candidate][data] = val
	end
	local ok, arg = pcall(Set, session, candidate, data, val)
	if not ok then addon:Debug("Error in 'SetCandidateData':", arg, session, candidate, data, val) end
end

function RCVotingFrame:GetCandidateData(session, candidate, data)
	local function Get(session, candidate, data)
		return lootTable[session].candidates[candidate][data]
	end
	local ok, arg = pcall(Get, session, candidate, data)
	if not ok then addon:Debug("Error in 'GetCandidateData':", arg, session, candidate, data)
	else return arg end
end

function RCVotingFrame:GetLootTable()
	return lootTable
end

function RCVotingFrame:GetPRValues(s)
	local numRaidMembers = GetNumGroupMembers();
	local realmName = GetRealmName();
	for i = 1, numRaidMembers do
		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i);
		local ep, gp, main = EPGP:GetEPGP(name .. "-" .. realmName);
		if(ep ~= nil)then
				self:SetCandidateData(s, name .. "-" .. realmName, "pr", ep/gp);
		end
	end
end

function RCVotingFrame:Setup(table)
	--lootTable[session] = {bagged, lootSlot, awarded, name, link, quality, ilvl, type, subType, equipLoc, texture, boe}
	lootTable = table -- Extract all the data we get
	for session, t in ipairs(lootTable) do -- and build the rest (candidates)
		lootTable[session].haveVoted = false -- Have we voted for ANY candidate in this session?
		t.candidates = {}
		for name, v in pairs(candidates) do
			t.candidates[name] = {
				class = v.class,
				rank = v.rank,
				role = v.role,
				response = "ANNOUNCED",
				pr = 0,
				ilvl = "",
				diff = "",
				gear1 = nil,
				gear2 = nil,
				votes = 0,
				note = nil,
				roll = "",
				voters = {},
				haveVoted = false, -- Have we voted for this particular candidate in this session?
			}
		end
		-- Init session toggle
		sessionButtons[session] = self:UpdateSessionButton(session, t.texture, t.link, t.awarded)
		sessionButtons[session]:Show()
	end
	-- Hide unused session buttons
	for i = #lootTable+1, #sessionButtons do
		sessionButtons[i]:Hide()
	end
	session = 1
	self:BuildST()
	self:SwitchSession(session)
end

function RCVotingFrame:HandleVote(session, name, vote, voter)
	-- Do the vote
	lootTable[session].candidates[name].votes = lootTable[session].candidates[name].votes + vote
	-- And update voters names
	if vote == 1 then
		tinsert(lootTable[session].candidates[name].voters, addon.Ambiguate(voter))
	else
		for i, n in ipairs(lootTable[session].candidates[name].voters) do
			if addon:UnitIsUnit(voter, n) then
				tremove(lootTable[session].candidates[name].voters, i)
				break
			end
		end
	end
	self.frame.st:Refresh()
	self:UpdatePeopleToVote()
end

function RCVotingFrame:DoRandomRolls(ses)
	local table = {}
	for name, v in pairs (lootTable[ses].candidates) do
		table[name] = math.random(100)
	end
	addon:SendCommand("group", "rolls", ses, table)
end

----------------------------------------------------------------- -
--	Visuals
-- @section Visuals
------------------------------------------------------------------
function RCVotingFrame:Update()
	if not self.frame then return end -- No updates when it doesn't exist
	self.frame.st:SortData()
	-- update awardString
	if lootTable[session] and lootTable[session].awarded then
		self.frame.awardString:Show()
	else
		self.frame.awardString:Hide()
	end
	-- This only applies to the ML
	if addon.isMasterLooter then
		-- Update close button text
		if active then
			self.frame.abortBtn:SetText(L["Abort"])
		else
			self.frame.abortBtn:SetText(L["Close"])
		end
		self.frame.disenchant:Show()
	else -- Non-MLs:
		self.frame.abortBtn:SetText(L["Close"])
		self.frame.disenchant:Hide()
	end
end

function RCVotingFrame:SwitchSession(s)
	addon:Debug("SwitchSession", s)
	self:GetPRValues(s);
	-- Start with setting up some statics
	local old = session
	session = s
	local t = lootTable[s] -- Shortcut
	self.frame.itemIcon:SetNormalTexture(t.texture)
	self.frame.itemText:SetText(t.link)
	self.frame.iState:SetText(self:GetItemStatus(t.link))
	self.frame.itemLvl:SetText(format(L["ilvl: x"], t.ilvl))
	-- Set a proper item type text
	if t.subType and t.subType ~= "Miscellaneous" and t.subType ~= "Junk" and t.equipLoc ~= "" then
		self.frame.itemType:SetText(getglobal(t.equipLoc)..", "..t.subType); -- getGlobal to translate from global constant to localized name
	elseif t.subType ~= "Miscellaneous" and t.subType ~= "Junk" then
		if t.subType == addon.db.global.localizedSubTypes["Artifact Relic"] then
			local id = addon:GetItemIDFromLink(t.link)
         self.frame.itemType:SetText((t.relic or select(3, C_ArtifactUI.GetRelicInfoByItemID(id))) or "".." "..t.subType or "")
		else
			self.frame.itemType:SetText(tostring(t.subType))
		end
	else
		if RCTokenTable[addon:GetItemIDFromLink(t.link)] then -- It's a token
			self.frame.itemType:SetText(L["Armor Token"])
		else
			self.frame.itemType:SetText(getglobal(t.equipLoc));
		end
	end

	-- Update the session buttons
	sessionButtons[s] = self:UpdateSessionButton(s, t.texture, t.link, t.awarded)
	sessionButtons[old] = self:UpdateSessionButton(old, lootTable[old].texture, lootTable[old].link, lootTable[old].awarded)

	-- Since we switched sessions, we want to sort by response
	local j = 1
	for i in ipairs(self.frame.st.cols) do
		self.frame.st.cols[i].sort = nil
		if self.frame.st.cols[i].colName == "response" then j = i end
	end
	self.frame.st.cols[j].sort = "asc"
	FauxScrollFrame_OnVerticalScroll(self.frame.st.scrollframe, 0, self.frame.st.rowHeight, function() self.frame.st:Refresh() end) -- Reset scrolling to 0
	self:Update()
	self:UpdatePeopleToVote()
end

function RCVotingFrame:BuildST()
	local rows = {}
	local i = 1
	-- We need to build the columns from the data in self.scrollCols
	-- We only really need the colName and value to get added
	for name in pairs(candidates) do
		local data = {}
		for num, col in ipairs(self.scrollCols) do
			data[num] = {value = "", colName = col.colName}
		end
		rows[i] = {
			name = name,
			cols = data,
		}
		i = i + 1
	end
	self.frame.st:SetData(rows)
end

function RCVotingFrame:UpdateMoreInfo(row, data)
	local name
	if data and row then
		name  = data[row].name
	else -- Try to extract the name from the selected row
		name = self.frame.st:GetSelection() and self.frame.st:GetRow(self.frame.st:GetSelection()).name or nil
	end

	if not moreInfo or not name then -- Hide the frame
		return self.frame.moreInfo:Hide()
	end

	local color = addon:GetClassColor(self:GetCandidateData(session, name, "class"))
	local tip = self.frame.moreInfo -- shortening
	tip:SetOwner(self.frame, "ANCHOR_RIGHT")

	tip:AddLine(addon.Ambiguate(name), color.r, color.g, color.b)
	if moreInfoData and moreInfoData[name] then
		local r,g,b
		tip:AddLine(L["Latest item(s) won"])
		for i, v in ipairs(moreInfoData[name]) do -- extract latest awarded items
			if v[3] then r,g,b = unpack(v[3],1,3) end
			tip:AddDoubleLine(v[1], v[2], nil,nil,nil, r or 1, g or 1, b or 1)
		end
		tip:AddLine(" ") -- spacer
		tip:AddLine(L["Totals"])
		for _, v in pairs(moreInfoData[name].totals.responses) do
			if v[3] then r,g,b = unpack(v[3],1,3) end
			tip:AddDoubleLine(v[1], v[2], r or 1,g or 1,b or 1, r or 1,g or 1,b or 1)
		end
		tip:AddLine(" ")
		if moreInfoData[name].totals.tokens[addon.currentInstanceName] then
			tip:AddDoubleLine(L["Tier tokens received from here:"], moreInfoData[name].totals.tokens[addon.currentInstanceName].num, 1,1,1, 1,1,1)
		end
		tip:AddDoubleLine(L["Total items received:"], moreInfoData[name].totals.total, 0,1,1, 0,1,1)
	else
		tip:AddLine(L["No entries in the Loot History"])
	end
	tip:SetScale(db.UI.votingframe.scale-0.15) -- Make it a bit smaller, as it's too wide otherwise
	tip:Show()
	tip:SetAnchorType("ANCHOR_RIGHT", 0, -tip:GetHeight())
end

function RCVotingFrame:GetFrame()
	if self.frame then return self.frame end

	-- Container and title
	local f = addon:CreateFrame("DefaultRCLootCouncilFrame", "votingframe", L["RCLootCouncil Voting Frame"], 250, 420)
	-- Scrolling table
	function f.UpdateSt()
		if f.st then -- It might already be created, so just update the cols
			f.st:Hide()
			f.st = nil
		end
		local st = LibStub("ScrollingTable"):CreateST(self.scrollCols, NUM_ROWS, ROW_HEIGHT, { ["r"] = 1.0, ["g"] = 0.9, ["b"] = 0.0, ["a"] = 0.5 }, f.content)
		st.frame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
		st:RegisterEvents({
			["OnClick"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
				if button == "RightButton" and row then
					if active then
						menuFrame.name = data[realrow].name
						Lib_ToggleDropDownMenu(1, nil, menuFrame, cellFrame, 0, 0);
					else
						addon:Print(L["You cannot use the menu when the session has ended."])
					end
				elseif button == "LeftButton" and row then -- Update more info
					self:UpdateMoreInfo(realrow, data)
				end
				-- Return false to have the default OnClick handler take care of left clicks
				return false
			end,
		})
		-- We also want to show moreInfo on mouseover
		st:RegisterEvents({
			["OnEnter"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
				if row then self:UpdateMoreInfo(realrow, data) end
				-- Return false to have the default OnEnter handler take care mouseover
				return false
			end
		})
		-- We also like to return to the actual selected player when we remove the mouse
		st:RegisterEvents({
			["OnLeave"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
				self:UpdateMoreInfo()
				return false
			end
		})
		st:SetFilter(RCVotingFrame.filterFunc)
		st:EnableSelection(true)
		f.st = st
		f:SetWidth(f.st.frame:GetWidth() + 20)
	end
	f.UpdateSt()

	--[[------------------------------
		Session item icon and strings
	    ------------------------------]]
	local item = CreateFrame("Button", nil, f.content)
	item:EnableMouse()
    item:SetNormalTexture("Interface/ICONS/INV_Misc_QuestionMark")
    item:SetScript("OnEnter", function()
		if not lootTable then return; end
		addon:CreateHypertip(lootTable[session].link)
	end)
	item:SetScript("OnLeave", function() addon:HideTooltip() end)
	item:SetScript("OnClick", function()
		if not lootTable then return; end
	    if ( IsModifiedClick() ) then
		    HandleModifiedItemClick(lootTable[session].link);
        end
    end);
	item:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -20)
	item:SetSize(50,50)
	f.itemIcon = item

	local iTxt = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	iTxt:SetPoint("TOPLEFT", item, "TOPRIGHT", 10, 0)
	iTxt:SetText(L["Something went wrong :'("]) -- Set text for reasons
	f.itemText = iTxt

	local ilvl = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ilvl:SetPoint("TOPLEFT", iTxt, "BOTTOMLEFT", 0, -4)
	ilvl:SetTextColor(1, 1, 1) -- White
	ilvl:SetText("")
	f.itemLvl = ilvl

	local iState = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	iState:SetPoint("LEFT", ilvl, "RIGHT", 5, 0)
	iState:SetTextColor(0,1,0,1) -- Green
	iState:SetText("")
	f.iState = iState

	local iType = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	iType:SetPoint("TOPLEFT", ilvl, "BOTTOMLEFT", 0, -4)
	iType:SetTextColor(0.5, 1, 1) -- Turqouise
	iType:SetText("")
	f.itemType = iType
	--#end----------------------------

	-- Abort button
	local b1 = addon:CreateButton(L["Close"], f.content)
	b1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -50)
	b1:SetScript("OnClick", function()
		-- This needs to be dynamic if the ML has changed since this was first created
		if addon.isMasterLooter and active then LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_ABORT")
		else self:Hide() end
	end)
	f.abortBtn = b1

	-- More info button
	local b2 = CreateFrame("Button", nil, f.content, "UIPanelButtonTemplate")
	b2:SetSize(25,25)
	b2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -20)
	if moreInfo then
		b2:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up");
		b2:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down");
	else
		b2:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
		b2:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
	end
	b2:SetScript("OnClick", function(button)
		moreInfo = not moreInfo
		db.modules["RCVotingFrame"].moreInfo = moreInfo
		if moreInfo then -- show the more info frame
			button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up");
			button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down");
		else -- hide it
			button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
			button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
		end
		self:UpdateMoreInfo()
	end)
	b2:SetScript("OnEnter", function() addon:CreateTooltip(L["Click to expand/collapse more info"]) end)
	b2:SetScript("OnLeave", function() addon:HideTooltip() end)
	f.moreInfoBtn = b2

	f.moreInfo = CreateFrame( "GameTooltip", "RCVotingFrameMoreInfo", nil, "GameTooltipTemplate" )

	-- Filter
	local b3 = addon:CreateButton(L["Filter"], f.content)
	b3:SetPoint("RIGHT", b1, "LEFT", -10, 0)
	b3:SetScript("OnClick", function(self) Lib_ToggleDropDownMenu(1, nil, filterMenu, self, 0, 0) end )
	b3:SetScript("OnEnter", function() addon:CreateTooltip(L["Deselect responses to filter them"]) end)
	b3:SetScript("OnLeave", function() addon:HideTooltip() end)
	f.filter = b3

	-- Disenchant button
	local b4 = addon:CreateButton(L["Disenchant"], f.content)
	b4:SetPoint("RIGHT", b3, "LEFT", -10, 0)
	b4:SetScript("OnClick", function(self) Lib_ToggleDropDownMenu(1, nil, enchanters, self, 0, 0) end )
	--b4:SetNormalTexture("Interface\\Icons\\INV_Enchant_Disenchant")
--	b4:Hide() -- hidden by default
	f.disenchant = b4

	-- Number of votes
	local rf = CreateFrame("Frame", nil, f.content)
	rf:SetWidth(100)
	rf:SetHeight(20)
	if b2 then rf:SetPoint("RIGHT", b2, "LEFT", -10, 0) else rf:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -20) end
	rf:SetScript("OnLeave", function()
		addon:HideTooltip()
	end)
	local rft = rf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rft:SetPoint("CENTER", rf, "CENTER")
	rft:SetText(" ")
	rft:SetTextColor(0,1,0,1) -- Green
	rf.text = rft
	rf:SetWidth(rft:GetStringWidth())
	f.rollResult = rf

	-- Award string
	local awdstr = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	awdstr:SetPoint("CENTER", f.content, "TOP", 0, -60)
	awdstr:SetText(L["Item has been awarded"])
	awdstr:SetTextColor(1, 1, 0, 1) -- Yellow
	awdstr:Hide()
	f.awardString = awdstr

	-- Session toggle
	local stgl = CreateFrame("Frame", nil, f.content)
	stgl:SetWidth(40)
	stgl:SetHeight(f:GetHeight())
	stgl:SetPoint("TOPRIGHT", f, "TOPLEFT", -2, 0)
	f.sessionToggleFrame = stgl
	sessionButtons = {}

	-- Set a proper width
	f:SetWidth(f.st.frame:GetWidth() + 20)
	return f;
end

function RCVotingFrame:UpdatePeopleToVote()
	local voters = {}
	-- Find out who have voted
	for name in pairs(lootTable[session].candidates) do
		for _, voter in pairs(lootTable[session].candidates[name].voters) do
			if not tContains(voters, voter) then
				tinsert(voters, voter)
			end
		end
	end
	if #councilInGroup == 0 then
		self.frame.rollResult.text:SetText(L["Couldn't find any councilmembers in the group"])
		self.frame.rollResult.text:SetTextColor(1,0,0,1) -- Red
	elseif #voters == #councilInGroup then
		self.frame.rollResult.text:SetText(L["Everyone have voted"])
		self.frame.rollResult.text:SetTextColor(0,1,0,1) -- Green
	elseif #voters < #councilInGroup then
		self.frame.rollResult.text:SetText(format(L["x out of x have voted"], #voters, #councilInGroup))
		self.frame.rollResult.text:SetTextColor(1,1,0,1) -- Yellow
	else
		addon:Debug("#voters > #councilInGroup ?")
	end
	self.frame.rollResult:SetScript("OnEnter", function()
		addon:CreateTooltip(L["The following council members have voted"], unpack(voters))
	end)
	self.frame.rollResult:SetWidth(self.frame.rollResult.text:GetStringWidth())
end

function RCVotingFrame:UpdateSessionButton(i, texture, link, awarded)
	local btn = sessionButtons[i]
	if not btn then -- create the button
		btn = CreateFrame("Button", "RCButton"..i, self.frame.sessionToggleFrame)
		btn:SetSize(40,40)
		--btn:SetText(i)
		if i == 1 then
			btn:SetPoint("TOPRIGHT", self.frame.sessionToggleFrame)
		elseif mod(i,10) == 1 then
			btn:SetPoint("TOPRIGHT", sessionButtons[i-10], "TOPLEFT", -2, 0)
		else
			btn:SetPoint("TOP", sessionButtons[i-1], "BOTTOM", 0, -2)
		end
		btn:SetScript("Onclick", function() RCVotingFrame:SwitchSession(i); end)
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
		btn:GetHighlightTexture():SetBlendMode("ADD")
		btn:SetNormalTexture(texture or "Interface\\InventoryItems\\WoWUnknownItem01")
		btn:GetNormalTexture():SetDrawLayer("BACKGROUND")
	end
	-- then update it
	btn:SetNormalTexture(texture or "Interface\\InventoryItems\\WoWUnknownItem01")
	-- Set the colored border and tooltips
	btn:SetBackdrop({
		bgFile = "",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 18,
		--insets = { left = -4, right = -4, top = -4, bottom = -4 }
	})
	local lines = { format(L["Click to switch to 'item'"], link) }
	if i == session then
		btn:SetBackdropBorderColor(1,1,0,1) -- yellow
		--btn:SetBackdropColor(1,1,1,1)
		btn:GetNormalTexture():SetVertexColor(1,1,1)
	elseif awarded then
		btn:SetBackdropBorderColor(0,1,0,1) -- green
		--btn:SetBackdropColor(1,1,1,0.8)
		btn:GetNormalTexture():SetVertexColor(0.8,0.8,0.8)
		tinsert(lines, L["This item has been awarded"])
	else
		btn:SetBackdropBorderColor(1,1,1,1) -- white
		--btn:SetBackdropColor(0.5,0.5,0.5,0.8)
		btn:GetNormalTexture():SetVertexColor(0.5,0.5,0.5)
	end
	btn:SetScript("OnEnter", function() addon:CreateTooltip(unpack(lines)) end)
	btn:SetScript("OnLeave", function() addon:HideTooltip() end)
	return btn
end


----------------------------------------------------------
--	Lib-st data functions (not particular pretty, I know)
-- @section Lib-st data funcs.
----------------------------------------------------------
function RCVotingFrame:GetDiffColor(num)
	if num == "" then num = 0 end -- Can't compare empty string
	local green, red, grey = {0,1,0,1},{1,0,0,1},{0.75,0.75,0.75,1}
	if num > 0 then return green end
	if num < 0 then return red end
	return grey
end

function RCVotingFrame.SetCellClass(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	addon.SetCellClassIcon(rowFrame, frame, data, cols, row, realrow, column, fShow, table, lootTable[session].candidates[name].class)
end

function RCVotingFrame.SetCellName(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(addon.Ambiguate(name))
	local c = addon:GetClassColor(lootTable[session].candidates[name].class)
	frame.text:SetTextColor(c.r, c.g, c.b, c.a)
	data[realrow].cols[column].value = name
end

function RCVotingFrame.SetCellRank(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(lootTable[session].candidates[name].rank)
	frame.text:SetTextColor(addon:GetResponseColor(lootTable[session].candidates[name].response,lootTable[session].candidates[name].isTier))
	data[realrow].cols[column].value = lootTable[session].candidates[name].rank
end

function RCVotingFrame.SetCellRole(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	local role = addon.TranslateRole(lootTable[session].candidates[name].role)
	frame.text:SetText(role)
	frame.text:SetTextColor(addon:GetResponseColor(lootTable[session].candidates[name].response,lootTable[session].candidates[name].isTier))
	data[realrow].cols[column].value = role
end

function RCVotingFrame.SetCellResponse(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	local isTier = lootTable[session].candidates[name].isTier
	frame.text:SetText(addon:GetResponseText(lootTable[session].candidates[name].response, isTier))
	frame.text:SetTextColor(addon:GetResponseColor(lootTable[session].candidates[name].response, isTier))
end

function RCVotingFrame.SetCellIlvl(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(db.iLvlDecimal and addon.round(lootTable[session].candidates[name].ilvl,2) or addon.round(lootTable[session].candidates[name].ilvl))
	data[realrow].cols[column].value = lootTable[session].candidates[name].ilvl
end

function RCVotingFrame.SetCellPR(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(addon.round(lootTable[session].candidates[name].pr,3))
	data[realrow].cols[column].value = lootTable[session].candidates[name].pr
end

function RCVotingFrame.SetCellDiff(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(lootTable[session].candidates[name].diff)
	frame.text:SetTextColor(unpack(RCVotingFrame:GetDiffColor(lootTable[session].candidates[name].diff)))
	data[realrow].cols[column].value = lootTable[session].candidates[name].diff
end

function RCVotingFrame.SetCellGear(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local gear = data[realrow].cols[column].colName -- gear1 or gear2
	local name = data[realrow].name
	gear = lootTable[session].candidates[name][gear] -- Get the actual gear
	if gear then
		local texture = select(10, GetItemInfo(gear))
		frame:SetNormalTexture(texture)
		frame:SetScript("OnEnter", function() addon:CreateHypertip(gear) end)
		frame:SetScript("OnLeave", function() addon:HideTooltip() end)
		frame:SetScript("OnClick", function()
			if IsModifiedClick() then
			   HandleModifiedItemClick(gear);
	      end
		end)
		frame:Show()
	else
		frame:Hide()
	end
end

function RCVotingFrame.SetCellVotes(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame:SetScript("OnEnter", function()
		if not addon.mldb.anonymousVoting or (db.showForML and addon.isMasterLooter) then
			if not addon.mldb.hideVotes or (addon.mldb.hideVotes and lootTable[session].haveVoted) then
				addon:CreateTooltip(L["Voters"], unpack(lootTable[session].candidates[name].voters))
			end
		end
	end)
	frame:SetScript("OnLeave", function() addon:HideTooltip() end)
	local val = lootTable[session].candidates[name].votes
	data[realrow].cols[column].value = val -- Set the value for sorting reasons
	frame.text:SetText(val)

	if addon.mldb.hideVotes then
		if not lootTable[session].haveVoted then frame.text:SetText(0) end
	end
end

function RCVotingFrame.SetCellVote(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	if not active or lootTable[session].awarded then -- Don't show the vote button if awarded or not active
		if frame.voteBtn then
			frame.voteBtn:Hide()
		end
		return
	end
	if addon.isCouncil or addon.isMasterLooter then -- Only let the right people vote
		if not frame.voteBtn then -- create it
			frame.voteBtn = addon:CreateButton(L["Vote"], frame)
			frame.voteBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
			frame.voteBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		end
		frame.voteBtn:SetScript("OnClick", function(btn)
			addon:Debug("Vote button pressed")
			if lootTable[session].candidates[name].haveVoted then -- unvote
				addon:SendCommand("group", "vote", session, name, -1)
				lootTable[session].candidates[name].haveVoted = false

				-- Check if that was our only vote
				local haveVoted = false
				for _, v in pairs(lootTable[session].candidates) do
					if v.haveVoted then haveVoted = true end
				end
				lootTable[session].haveVoted = haveVoted

			else -- vote
				-- Test if they may vote for themselves
				if not addon.mldb.selfVote and addon:UnitIsUnit("player", name) then
					return addon:Print(L["The Master Looter doesn't allow votes for yourself."])
				end
				-- Test if they're allowed to cast multiple votes
				if not addon.mldb.multiVote then
					if lootTable[session].haveVoted then
						return addon:Print(L["The Master Looter doesn't allow multiple votes."])
					end
				end
				-- Do the vote
				addon:SendCommand("group", "vote", session, name, 1)
				lootTable[session].candidates[name].haveVoted = true
				lootTable[session].haveVoted = true
			end
		end)
		frame.voteBtn:Show()
		if lootTable[session].candidates[name].haveVoted then
			frame.voteBtn:SetText(L["Unvote"])
		else
			frame.voteBtn:SetText(L["Vote"])
		end
	end
end

function RCVotingFrame.SetCellNote(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	local note = lootTable[session].candidates[name].note
	local f = frame.noteBtn or CreateFrame("Button", nil, frame)
	f:SetSize(ROW_HEIGHT, ROW_HEIGHT)
	f:SetPoint("CENTER", frame, "CENTER")
	if note then
		f:SetNormalTexture("Interface/BUTTONS/UI-GuildButton-PublicNote-Up.png")
		f:SetScript("OnEnter", function() addon:CreateTooltip(L["Note"], note)	end)
		f:SetScript("OnLeave", function() addon:HideTooltip() end)
		data[realrow].cols[column].value = 1 -- Set value for sorting compability
	else
		f:SetScript("OnEnter", nil)
		f:SetNormalTexture("Interface/BUTTONS/UI-GuildButton-PublicNote-Disabled.png")
		data[realrow].cols[column].value = 0
	end
	frame.noteBtn = f
end

function RCVotingFrame.SetCellRoll(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(lootTable[session].candidates[name].roll)
	data[realrow].cols[column].value = lootTable[session].candidates[name].roll
end

function RCVotingFrame.filterFunc(table, row)
	if not db.modules["RCVotingFrame"].filters then return true end -- db hasn't been initialized, so just show it
	local response = lootTable[session].candidates[row.name].response
	if response == "AUTOPASS" or response == "PASS" or type(response) == "number" then
		if lootTable[session].token and addon.mldb.tierButtonsEnabled and type(response) == "number" then
			return db.modules["RCVotingFrame"].filters.tier[response]
		else
			return db.modules["RCVotingFrame"].filters[response]
		end
	else -- Filter out the status texts
		return db.modules["RCVotingFrame"].filters["STATUS"]
	end
end

function ResponseSort(table, rowa, rowb, sortbycol)
	local column = table.cols[sortbycol]
	local a, b = table:GetRow(rowa), table:GetRow(rowb);
	a, b = addon:GetResponseSort(lootTable[session].candidates[a.name].response), addon:GetResponseSort(lootTable[session].candidates[b.name].response)
	if a == b then
		if column.sortnext then
			local nextcol = table.cols[column.sortnext];
			if nextcol and not(nextcol.sort) then
				if nextcol.comparesort then
					return nextcol.comparesort(table, rowa, rowb, column.sortnext);
				else
					return table:CompareSort(rowa, rowb, column.sortnext);
				end
			end
		end
		return false
	else
		local direction = column.sort or column.defaultsort or "asc";
		if direction:lower() == "asc" then
			return a < b;
		else
			return a > b;
		end
	end
end

function GuildRankSort(table, rowa, rowb, sortbycol)
	local column = table.cols[sortbycol]
	local a, b = table:GetRow(rowa), table:GetRow(rowb);
	-- Extract the rank index from the name, fallback to 100 if not found
	a = guildRanks[lootTable[session].candidates[a.name].rank] or 100
	b = guildRanks[lootTable[session].candidates[b.name].rank] or 100
	if a == b then
		if column.sortnext then
			local nextcol = table.cols[column.sortnext];
			if nextcol and not(nextcol.sort) then
				if nextcol.comparesort then
					return nextcol.comparesort(table, rowa, rowb, column.sortnext);
				else
					return table:CompareSort(rowa, rowb, column.sortnext);
				end
			end
		end
		return false
	else
		local direction = column.sort or column.defaultsort or "asc";
		if direction:lower() == "asc" then
			return a > b;
		else
			return a < b;
		end
	end
end

----------------------------------------------------
--	Dropdowns.
-- @section Dropdowns.
----------------------------------------------------
do
	local info = Lib_UIDropDownMenu_CreateInfo() -- Efficiency :)
	-- NOTE Take care of info[] values when inserting new buttons
	function RCVotingFrame.RightClickMenu(menu, level)
		if not addon.isMasterLooter then return end

		local candidateName = menu.name
		local data = lootTable[session].candidates[candidateName] -- Shorthand

		if level == 1 then
			info = Lib_UIDropDownMenu_CreateInfo()

			info.text = addon.Ambiguate(candidateName)
			info.isTitle = true
			info.notCheckable = true
			info.disabled = true
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = ""
			info.isTitle = false
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = L["Award"]
			info.func = function()
				LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_AWARD", {
					session,
				  	candidateName,
					data.response,
					nil,
					data.votes,
					data.gear1,
					data.gear2,
					data.isTier,
			}) end
			info.disabled = false
			Lib_UIDropDownMenu_AddButton(info, level)
			info = Lib_UIDropDownMenu_CreateInfo()

			info.text = L["Award for ..."]
			info.value = "AWARD_FOR"
			info.notCheckable = true
			info.hasArrow = true
			Lib_UIDropDownMenu_AddButton(info, level)
			info = Lib_UIDropDownMenu_CreateInfo()

			info.text = ""
			info.notCheckable = true
			info.disabled = true
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = L["Change Response"]
			info.value = "CHANGE_RESPONSE"
			info.hasArrow = true
			info.disabled = false
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = L["Reannounce ..."]
			info.value = "REANNOUNCE"
			Lib_UIDropDownMenu_AddButton(info, level)
			info = Lib_UIDropDownMenu_CreateInfo()

			info.text = L["Remove from consideration"]
			info.notCheckable = true
			info.func = function()
				addon:SendCommand("group", "change_response", session, candidateName, "REMOVED")
			end
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = L["Add rolls"]
			info.notCheckable = true
			info.func = function() RCVotingFrame:DoRandomRolls(session) end
			Lib_UIDropDownMenu_AddButton(info, level)

		elseif level == 2 then
			local value = LIB_UIDROPDOWNMENU_MENU_VALUE
			info = Lib_UIDropDownMenu_CreateInfo()
			if value == "AWARD_FOR" then
				for k,v in ipairs(db.awardReasons) do
					if k > db.numAwardReasons then break end
					info.text = v.text
					info.notCheckable = true
					info.func = function()
						LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_AWARD", {
							session,
						  	candidateName,
							nil,
							v,
							data.votes,
							data.gear1,
							data.gear2,
							data.isTier,
				}) end
					Lib_UIDropDownMenu_AddButton(info, level)
				end

			elseif value == "CHANGE_RESPONSE" then
				local v;
				for i = 1, db.numButtons do
					v = db.responses[i]
					info.text = v.text
					info.colorCode = "|cff"..addon:RGBToHex(unpack(v.color))
					info.notCheckable = true
					info.func = function()
							addon:SendCommand("group", "change_response", session, candidateName, i)
					end
					Lib_UIDropDownMenu_AddButton(info, level)
				end

				info = Lib_UIDropDownMenu_CreateInfo()
				if addon.debug then -- Add all possible responses when debugging
					for k,v in pairs(db.responses) do
						if type(k) ~= "number" and k ~= "tier" then
							info.text = v.text
							info.colorCode = "|cff"..addon:RGBToHex(unpack(v.color))
							info.notCheckable = true
							info.func = function()
									addon:SendCommand("group", "change_response", session, candidateName, k)
							end
							Lib_UIDropDownMenu_AddButton(info, level)
						end
					end
				end

				info = Lib_UIDropDownMenu_CreateInfo()
				-- Add the tier menu
				info.text = L["Tier Tokens ..."]
				info.value = "TIER_TOKENS"
				info.hasArrow = true
				info.notCheckable = true
				Lib_UIDropDownMenu_AddButton(info, level)

			elseif value == "REANNOUNCE" then
				info.text = addon.Ambiguate(candidateName)
				info.isTitle = true
				info.notCheckable = true
				info.disabled = true
				Lib_UIDropDownMenu_AddButton(info, level)
				info = Lib_UIDropDownMenu_CreateInfo()

				info.text = L["This item"]
				info.notCheckable = true
				info.func = function()
					local t = {
						{	name = lootTable[session].name,
							link = lootTable[session].link,
							ilvl = lootTable[session].ilvl,
							texture = lootTable[session].texture,
							session = session,
							equipLoc = lootTable[session].equipLoc,
							token = lootTable[session].token
						}
					}
					addon:SendCommand(candidateName, "reroll", t)
					addon:SendCommand("group", "change_response", session, candidateName, "WAIT")
				end
				Lib_UIDropDownMenu_AddButton(info, level);
				info = Lib_UIDropDownMenu_CreateInfo()

				info.text = L["All items"]
				info.notCheckable = true
				info.func = function()
					local t = {}
					for k,v in ipairs(lootTable) do
						if not v.awarded then
							tinsert(t, {
								name = v.name,
								link = v.link,
								ilvl = v.ilvl,
								texture = v.texture,
								session = k,
								equipLoc = v.equipLoc,
								token = v.token,
							})
							addon:SendCommand("group", "change_response", k, candidateName, "WAIT")
						end
					end
					addon:SendCommand(candidateName, "reroll", t)
				end
				Lib_UIDropDownMenu_AddButton(info, level);
			end

		elseif level == 3 then
			local value = LIB_UIDROPDOWNMENU_MENU_VALUE
			info = Lib_UIDropDownMenu_CreateInfo()
			if value == "TIER_TOKENS" then
				for k,v in ipairs(db.responses.tier) do
					if k > db.tierNumButtons then break end
					info.text = v.text
					info.colorCode = "|cff"..addon:RGBToHex(unpack(v.color))
					info.notCheckable = true
					info.func = function()
							addon:SendCommand("group", "change_response", session, candidateName, k, true)
					end
					Lib_UIDropDownMenu_AddButton(info, level)
				end
			end
		end
	end

	function RCVotingFrame.FilterMenu(menu, level)
		if level == 1 then -- Redundant

			if not db.modules["RCVotingFrame"].filters then -- Create the db entry
				addon:DebugLog("Created VotingFrame filters")
				db.modules["RCVotingFrame"].filters = {}
			end

			-- Build the data table:
			local data = {["STATUS"] = true, ["PASS"] = true, ["AUTOPASS"] = true, tier = {}}

			local isTier = false
			-- If we're viewing a tier token and the ML have it enabled, we want to see it
			if lootTable[session].token and addon.mldb.tierButtonsEnabled then
				isTier = true
				for i = 1, addon.mldb.tierNumButtons or db.tierNumButtons do
					data.tier[i] = i
				end

			else -- otherwise just do the normal buttons
				for i = 1, addon.mldb.numButtons or db.numButtons do
					data[i] = i
				end
			end

			info.text = L["Filter"]
			info.isTitle = true
			info.notCheckable = true
			info.disabled = true
			Lib_UIDropDownMenu_AddButton(info, level)
			info = Lib_UIDropDownMenu_CreateInfo()
			if isTier then -- add tier buttons
				for k in ipairs(data.tier) do
					info.text = addon:GetResponseText(k, isTier)
					info.colorCode = "|cff"..addon:RGBToHex(addon:GetResponseColor(k, isTier))
					info.func = function()
						addon:Debug("Update Filter")
						db.modules["RCVotingFrame"].filters.tier[k] = not db.modules["RCVotingFrame"].filters.tier[k]
						RCVotingFrame:Update()
					end
					info.checked = db.modules["RCVotingFrame"].filters.tier[k]
					Lib_UIDropDownMenu_AddButton(info, level)
				end
			else -- add normal buttons
				for k in ipairs(data) do -- Make sure normal responses are on top
					info.text = addon:GetResponseText(k)
					info.colorCode = "|cff"..addon:RGBToHex(addon:GetResponseColor(k))
					info.func = function()
						addon:Debug("Update Filter")
						db.modules["RCVotingFrame"].filters[k] = not db.modules["RCVotingFrame"].filters[k]
						RCVotingFrame:Update()
					end
					info.checked = db.modules["RCVotingFrame"].filters[k]
					Lib_UIDropDownMenu_AddButton(info, level)
				end
			end
			for k in pairs(data) do -- A bit redundency, but it makes sure these "specials" comes last
				if type(k) == "string" and k ~= "tier" then
					if k == "STATUS" then
						info.text = L["Status texts"]
						info.colorCode = "|cffde34e2" -- purpleish
					else
						info.text = addon:GetResponseText(k)
						info.colorCode = "|cff"..addon:RGBToHex(addon:GetResponseColor(k))
					end
					info.func = function()
						addon:Debug("Update Filter")
						db.modules["RCVotingFrame"].filters[k] = not db.modules["RCVotingFrame"].filters[k]
						RCVotingFrame:Update()
					end
					info.checked = db.modules["RCVotingFrame"].filters[k]
					Lib_UIDropDownMenu_AddButton(info, level)
				end
			end
		end
	end

	function RCVotingFrame.EnchantersMenu(menu, level)
		if level == 1 then
			local added = false
			info = Lib_UIDropDownMenu_CreateInfo()
			if not db.disenchant then
				return addon:Print(L["You haven't selected an award reason to use for disenchanting!"])
			end
			for name, v in pairs(candidates) do
				if v.enchanter then
					local c = addon:GetClassColor(v.class)
					info.text = "|cff"..addon:RGBToHex(c.r, c.g, c.b)..addon.Ambiguate(name).."|r "..tostring(v.enchant_lvl)
					info.notCheckable = true
					info.func = function()
						for k,v in ipairs(db.awardReasons) do
							if v.disenchant then
								LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_AWARD", {
									session,
								  	name,
									nil,
									v,
								})
								return
							end
						end
					end
					added = true
					Lib_UIDropDownMenu_AddButton(info, level)
				end
			end
			if not added then -- No enchanters available
				info.text = L["No (dis)enchanters found"]
				info.notCheckable = true
				info.isTitle = true
				Lib_UIDropDownMenu_AddButton(info, level)
			end
		end
	end
end

function RCVotingFrame:GetItemStatus(item)
	-- addon:Debug("GetitemStatus", item)
	if not item then return "" end
	GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	GameTooltip:SetHyperlink(item)
	local text = ""
	if GameTooltip:NumLines() > 1 then -- check that there is something here
		local line = getglobal('GameTooltipTextLeft2') -- Should always be line 2
		local t =  line:GetText()
		-- The following color string should be there if we have a green status text
		if t then
			if strfind(t, "cFF 0FF 0") then
				text = t
			end
		end
	end
	GameTooltip:Hide()
	return text
end
