local _G = _G
local assert = assert
local C_PetJournal = C_PetJournal
local C_PetJournal_GetPetInfoByPetID = C_PetJournal.GetPetInfoByPetID
local C_PetJournal_GetPetLoadOutInfo = C_PetJournal.GetPetLoadOutInfo
local C_PetJournal_GetPetStats = C_PetJournal.GetPetStats
local C_PetJournal_PickupPet = C_PetJournal.PickupPet
local C_PetJournal_SetAbility = C_PetJournal.SetAbility
local C_PetJournal_SetPetLoadOutInfo = C_PetJournal.SetPetLoadOutInfo
local C_Timer_After = C_Timer.After
local ClearCursor = ClearCursor
local CreateFrame = CreateFrame
local format = format
local GetAddOnInfo = GetAddOnInfo
local ipairs = ipairs
local IsAddOnLoaded = IsAddOnLoaded
local math = math
local next = next
local pairs = pairs
local table = table
local tonumber = tonumber
local type = type

local addonName = ...
local addon = CreateFrame("Frame")
addon:SetScript("OnEvent", function(self, event, ...) self[event](self, event, ...) end)
addon:RegisterEvent("ADDON_LOADED")

-- variables
local MAX_BATTLE_TABS = 10 -- 8 to 10 for most natural results
local MAX_ACTIVE_PETS = MAX_ACTIVE_PETS or 3
local BATTLEPETTABSFLYOUT_BORDERWIDTH = 0
local BATTLEPETTABSFLYOUT_ITEM_HEIGHT = 35
local BATTLEPETTABSFLYOUT_ITEM_WIDTH = 35
local BATTLEPETTABSFLYOUT_ITEM_XOFFSET = 4
local BATTLEPETTABSFLYOUT_ITEM_YOFFSET = -6
local BATTLEPETTABSFLYOUT_ITEMS_PER_ROW = 5
local BATTLEPETTABSFLYOUT_MAX_ITEMS = 65
local FLYOUT_COMMAND_NEW = 1
local FLYOUT_COMMAND_MOVETO = 2
local FLYOUT_COMMAND_RENAME = 3
local FLYOUT_COMMAND_DELETE = 4
local FLYOUT_COMMAND_TEAM = 5

-- load defaults or fallback to stored settings
BattlePetTabsDB3 = type(BattlePetTabsDB3) == "table" and BattlePetTabsDB3 or {
	Teams = {},
	Groups = {},
	Inactive = {},
}

-- temporary variables until the dependency addon loads
addon.PetJournalName = "Blizzard_Collections"
addon.NumLoaded = 0

-- loads the UI once our addon and the pet journal have loaded
function addon:ADDON_LOADED(event, name)
	if name == addonName then
		addon.NumLoaded = addon.NumLoaded + 1
		-- the journal was loaded before our addon
		if IsAddOnLoaded(addon.PetJournalName) then
			addon.NumLoaded = addon.NumLoaded + 1
		end
		-- check if Aurora is enabled
		local _, _, _, enabled = GetAddOnInfo("Aurora")
		addon.HasAurora = enabled
	elseif name == addon.PetJournalName then
		addon.NumLoaded = addon.NumLoaded + 1
	end
	if addon.NumLoaded >= 2 then
		addon.PetJournalName, addon.NumLoaded = nil
		addon:UnregisterEvent(event)
		addon:CreateUI()
		addon:RegisterEvent("BATTLE_PET_CURSOR_CLEAR")
		addon:RegisterEvent("COMPANION_UPDATE")
		addon:RegisterEvent("CURSOR_UPDATE")
		addon:RegisterEvent("MOUNT_CURSOR_CLEAR")
		addon:RegisterUnitEvent("UNIT_PET", "player")
		addon:SetLoginLoadOut()
	end
end

function addon:UPDATE()
	-- enable or disable the new/moveTo button depending if we reached the limit or not
	addon.Manager.flyout.new:SetEnabled(#BattlePetTabsDB3.Inactive < BATTLEPETTABSFLYOUT_MAX_ITEMS)
	addon.Manager.flyout.moveTo:SetEnabled(#BattlePetTabsDB3.Inactive < BATTLEPETTABSFLYOUT_MAX_ITEMS)

	-- teams
	for i, team in ipairs(addon.Teams) do
		local dbTeam = BattlePetTabsDB3.Teams[i]
		team.dbTeam = dbTeam
		if dbTeam then
			team.button:SetChecked(addon:IsTeamEquipped(dbTeam))
			team.icon:SetTexture(addon:GetTeamTexture(dbTeam))
			team:Show()
		elseif not addon.IsDraggingInactiveTeam then
			team.button:SetChecked(false)
			team.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			team:Hide()
		end
	end

	-- inactive teams
	for i, team in ipairs(addon.InactiveTeams) do
		local dbTeam = BattlePetTabsDB3.Inactive[i]
		team.dbTeam = dbTeam
		if dbTeam then
			team.icon:SetTexture(addon:GetTeamTexture(dbTeam))
			team:Show()
		else
			team.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			team:Hide()
		end
	end

	-- dragging a team
	if addon.IsDraggingTeam then
		if not addon.Manager.flyout:IsShown() then
			addon.Manager.button:Click()
		end
		addon.Manager.flyout.new:Hide()
		addon.Manager.flyout.moveTo:Show()
	else
		addon.Manager.flyout.new:Show()
		addon.Manager.flyout.moveTo:Hide()
	end

	-- dragging an inactive team
	if addon.IsDraggingInactiveTeam then
		for i, team in ipairs(addon.Teams) do
			if not team.dbTeam then
				team.icon:SetTexture("Interface\\Icons\\Misc_ArrowLeft")
				team:Show()
				break
			end
		end
	end
end

-- additional events that trigger updates
addon.BATTLE_PET_CURSOR_CLEAR = addon.UPDATE
addon.COMPANION_UPDATE = addon.UPDATE
addon.CURSOR_UPDATE = addon.UPDATE
addon.MOUNT_CURSOR_CLEAR = addon.UPDATE
addon.UNIT_PET = addon.UPDATE

-- create the addon UI
function addon:CreateUI()
	-- setup the container
	addon.Container = CreateFrame("Frame", addonName .. "Frame", PetJournal)
	addon.Container:SetParent(PetJournal)
	addon.Container:SetSize(42, 50)
	addon.Container:SetPoint("TOPLEFT", "$parent", "TOPRIGHT", addon.HasAurora and 3 or -1, MAX_BATTLE_TABS > 8 and 24 or -17)
	addon.Container:SetScript("OnShow", addon.Widget.Container.OnShow)

	-- setup the manager button
	addon.Manager = addon:CreatePetButton(0)
	addon.Manager:SetParent(addon.Container)
	addon.Manager:SetPoint("TOPLEFT", "$parent", "BOTTOMLEFT")
	addon.Manager.icon:SetTexture("Interface\\Icons\\INV_Pet_Achievement_CaptureAWildPet")
	addon.Manager.button:SetScript("OnClick", addon.Widget.Manager.OnClick)
	addon.Manager.button:SetScript("OnEnter", addon.Widget.Manager.OnEnter)
	addon.Manager.button:SetScript("OnLeave", addon.Widget.Manager.OnLeave)
	addon.Manager.button:SetScript("OnDragStart", nil)
	addon.Manager.button:SetScript("OnDragStop", nil)
	addon.Manager.button:SetScript("OnReceiveDrag", nil)

	-- setup the manager flyout
	addon.Manager.flyout = addon:CreateFlyout(addon.Manager)

	-- add new team button
	addon.Manager.flyout.new = addon.Manager.flyout:CreateButton(FLYOUT_COMMAND_NEW)

	-- add move to team button
	addon.Manager.flyout.moveTo = addon.Manager.flyout:CreateButton(FLYOUT_COMMAND_MOVETO)
	addon.Manager.flyout.moveTo:ClearAllPoints()
	addon.Manager.flyout.moveTo:SetAllPoints(addon.Manager.flyout.new)

	-- add padding
	for i = 1, BATTLEPETTABSFLYOUT_ITEMS_PER_ROW - 2 do
		addon.Manager.flyout:CreateButton():Hide()
	end

	-- add inactive teams
	addon.InactiveTeams = {}
	for i = 1, BATTLEPETTABSFLYOUT_MAX_ITEMS do
		local team = addon.Manager.flyout:CreateButton(FLYOUT_COMMAND_TEAM)
		team:SetID(i)
		table.insert(addon.InactiveTeams, team)
	end

	-- create team buttons
	addon.Teams = {}
	for i = 1, MAX_BATTLE_TABS do
		local team = addon:CreatePetButton(i)
		team:SetID(i)
		team:SetParent(addon.Container)
		team:SetPoint("TOPLEFT", addon.Teams[#addon.Teams] or addon.Manager, "BOTTOMLEFT")
		team.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

		-- setup the team flyout
		team.flyout = addon:CreateFlyout(team)

		-- create team flyout buttons
		team.flyout.rename = team.flyout:CreateButton(FLYOUT_COMMAND_RENAME)
		team.flyout.delete = team.flyout:CreateButton(FLYOUT_COMMAND_DELETE)

		table.insert(addon.Teams, team)
	end

	-- create rename static popup
	StaticPopupDialogs[addonName .. "_TEAM_RENAME"] = {
		text = "",
		button1 = ACCEPT,
		button2 = CANCEL,
		hasEditBox = 1,
		maxLetters = 32,
		OnAccept = function(self, team)
			local text = self.editBox:GetText()
			if type(text) == "string" and text:len() > 0 then
				team.name = text
			end
		end,
		EditBoxOnEnterPressed = function(self, team)
			local text = self:GetParent().editBox:GetText()
			if type(text) == "string" and text:len() > 0 then
				team.name = text
			end
			self:GetParent():Hide()
		end,
		EditBoxOnEscapePressed = function(self)
			self:GetParent():Hide()
		end,
		OnShow = function(self, team)
			self.text:SetFormattedText("What do you want to rename \"%s\" to?", team.name or "Team")
			self.editBox:SetFocus()
		end,
		OnHide = function(self)
			self.editBox:SetText("")
		end,
		timeout = 0,
		exclusive = 1,
		whileDead = 1,
		hideOnEscape = 1
	}
end

-- create pet button
function addon:CreatePetButton(id)
	local frame = CreateFrame("Frame", addonName .. "Team" .. id)
	frame:SetSize(42, 50)
	frame:SetPoint("TOPLEFT")

	frame.background = frame:CreateTexture(nil, "BACKGROUND")
	frame.background:SetTexture("Interface\\GuildBankFrame\\UI-GuildBankFrame-Tab")
	frame.background:SetSize(64, 64)
	frame.background:SetPoint("TOPLEFT")
	frame.background:SetShown(not addon.HasAurora)

	frame.button = CreateFrame("CheckButton", nil, frame)
	frame.button:SetSize(36, 34)
	frame.button:SetPoint("TOPLEFT", 2, -8)
	frame.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame.button:RegisterForDrag("LeftButton")
	frame.button:SetMotionScriptsWhileDisabled(true)

	frame.button:SetScript("OnClick", addon.Widget.PetButton.OnClick)
	frame.button:SetScript("OnDragStart", addon.Widget.PetButton.OnDragStart)
	frame.button:SetScript("OnDragStop", addon.Widget.PetButton.OnDragStop)
	frame.button:SetScript("OnReceiveDrag", addon.Widget.PetButton.OnReceiveDrag)
	frame.button:SetScript("OnEnter", addon.Widget.PetButton.OnEnter)
	frame.button:SetScript("OnLeave", addon.Widget.PetButton.OnLeave)

	-- frame.button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
	frame.button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	frame.button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	frame.button:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD") -- TODO: "ADD" ?

	frame.icon = frame.button:CreateTexture(nil, "BORDER")
	frame.icon:SetPoint("TOPLEFT", 1, -1)
	frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.icon:SetTexCoord(.1, .9, .1, .9)
	frame.icon:SetTexture("Interface\\Icons\\Temp")

	frame.count = frame.button:CreateFontString(nil, "BORDER", "NumberFontNormal")
	frame.count:SetJustifyH("RIGHT")
	frame.count:SetPoint("BOTTOMRIGHT", -5, 2)

	frame.overlay = frame.button:CreateTexture(nil, "ARTWORK", nil, -4)
	frame.overlay:SetAllPoints()
	frame.overlay:SetTexture(0, 0, 0, .8)
	frame.overlay:Hide()

	return frame
end

-- create flyout frame
function addon:CreateFlyout(parent)
	local frame = CreateFrame("Frame", "$parentFlyout", parent or UIParent)
	frame:Hide()
	frame:SetPoint("TOPLEFT", "$parent", "TOPRIGHT", 0, -8)
	frame:SetSize(1, 1) -- otherwise it's invisible

	frame:SetScript("OnShow", addon.Widget.Flyout.OnShow)
	frame:SetScript("OnHide", addon.Widget.Flyout.OnHide)
	frame:SetScript("OnUpdate", addon.Widget.Flyout.OnUpdate)

	frame.CreateButton = addon.Widget.Flyout.CreateButton
	frame.GetButton = addon.Widget.Flyout.GetButton

	return frame
end

-- pickup team when dragging
function addon:DraggingPickupTeam(team)
	ClearCursor()
	if type(team) == "table" then
		local _, firstPet = next(team)
		if firstPet and firstPet[1] then
			C_PetJournal_PickupPet(firstPet[1])
		end
	end
end

-- move pet from one location to another
function addon:MoveTo(src, dst)
	if not src or not dst then
		return -- both must exist
	elseif src == dst then
		return -- pointless to move to the same location
	elseif dst.command == FLYOUT_COMMAND_NEW then
		return -- can't move to the new button
	end

	-- team variables
	local srcIsInactive, srcTeam, srcIndex = not not src.command, src.dbTeam
	local dstIsInactive, dstTeam, dstIndex = not not dst.command, dst.dbTeam

	-- active teams
	for i, team in ipairs(BattlePetTabsDB3.Teams) do
		if not srcIndex and not srcIsInactive and team == srcTeam then
			srcIndex = i
		end
		if not dstIndex and not dstIsInactive and team == dstTeam then
			dstIndex = i
		end
		if srcIndex and dstIndex then
			break
		end
	end

	-- inactive teams
	if not srcIndex or not dstIndex then
		for i, team in ipairs(BattlePetTabsDB3.Inactive) do
			if not srcIndex and srcIsInactive and team == srcTeam then
				srcIndex = i
			end
			if not dstIndex and dstIsInactive and team == dstTeam then
				dstIndex = i
			end
			if srcIndex and dstIndex then
				break
			end
		end
	end

	-- DEBUG
	--print("S", srcTeam and "Y" or "N", srcIndex, "D", dstTeam and "Y" or "N", dstIndex, "C", dst.command, "")

	-- logic
	if srcIsInactive and dstIsInactive then
		-- swap two inactive teams
		if srcIndex and dstIndex then
			local teamA = BattlePetTabsDB3.Inactive[srcIndex]
			local teamB = BattlePetTabsDB3.Inactive[dstIndex]
			BattlePetTabsDB3.Inactive[srcIndex] = teamB
			BattlePetTabsDB3.Inactive[dstIndex] = teamA
		end
	elseif not srcIsInactive and not dstIsInactive then
		-- swap two active teams
		if srcIndex and dstIndex then
			local teamA = BattlePetTabsDB3.Teams[srcIndex]
			local teamB = BattlePetTabsDB3.Teams[dstIndex]
			BattlePetTabsDB3.Teams[srcIndex] = teamB
			BattlePetTabsDB3.Teams[dstIndex] = teamA
		end
	elseif srcIsInactive and not dstIsInactive then
		-- swap an inactive team with an active one
		if srcIndex and dstIndex then
			local teamA = BattlePetTabsDB3.Inactive[srcIndex]
			local teamB = BattlePetTabsDB3.Teams[dstIndex]
			BattlePetTabsDB3.Inactive[srcIndex] = teamB
			BattlePetTabsDB3.Teams[dstIndex] = teamA
		-- activate an inactive team
		elseif srcIndex and not dstIndex then
			-- only if we have space for an additional active team
			if #BattlePetTabsDB3.Teams < MAX_BATTLE_TABS then
				local team = table.remove(BattlePetTabsDB3.Inactive, srcIndex)
				table.insert(BattlePetTabsDB3.Teams, team)
			end
		end
	elseif not srcIsInactive and dstIsInactive then
		-- swap an active team with an inactive one
		if srcIndex and dstIndex then
			local teamA = BattlePetTabsDB3.Teams[srcIndex]
			local teamB = BattlePetTabsDB3.Inactive[dstIndex]
			BattlePetTabsDB3.Teams[srcIndex] = teamB
			BattlePetTabsDB3.Inactive[dstIndex] = teamA
		-- deactivate an active team
		elseif srcIndex and not dstIndex then
			-- only if we have space for an additional active team
			if #BattlePetTabsDB3.Inactive < BATTLEPETTABSFLYOUT_MAX_ITEMS then
				local team = table.remove(BattlePetTabsDB3.Teams, srcIndex)
				table.insert(BattlePetTabsDB3.Inactive, team)
			end
		end
	end

	-- force update the UI
	addon:UPDATE()
end

-- copy loadout
function addon:CopyLoadout()
	local team = {}
	team.name = "Team"

	for i = 1, MAX_ACTIVE_PETS do
		local petID, ability1ID, ability2ID, ability3ID, locked = C_PetJournal_GetPetLoadOutInfo(i)

		table.insert(team, {petID, ability1ID, ability2ID, ability3ID})
	end

	return team
end

-- rename team
function addon:RenameTeam(team)
	assert(type(team) == "table", "BattlePetTabs:RenameTeam(team) expected first argument to be a table")
	StaticPopup_Show(addonName .. "_TEAM_RENAME", nil, nil, team)
end

-- set loadout at login
function addon:SetLoginLoadOut()
	local index = tonumber(BattlePetTabsDB3.LoadOutTeamIndex, 10) or 0
	if not index then
		index = #BattlePetTabsDB3.Teams
	end
	if index > 0 then
		local team = BattlePetTabsDB3.Teams[index]
		addon:EquipTeamLoadout(team)
	end
end

-- find a team index from the active teams
function addon:GetTeamIndex(team, fallback)
	for i, t in ipairs(BattlePetTabsDB3.Teams) do
		if t == team then
			return i
		end
	end
	if fallback then
		local i = BattlePetTabsDB3.Teams
		if i then
			return i
		end
	end
end

-- equip a team
function addon:EquipTeamLoadout(team)
	BattlePetTabsDB3.LoadOutTeamIndex = addon:GetTeamIndex(team, true)
	addon.EquippedLoadOut = team
	addon.LoadingLoadOut = true

	if type(team) == "table" then
		local recheck, firstPet

		for i = 1, MAX_ACTIVE_PETS do
			local equippedPetID, equippedAbility1ID, equippedAbility2ID, equippedAbility3ID, locked = C_PetJournal_GetPetLoadOutInfo(i)
			local pet = team[i]

			if type(pet) == "table" then
				if not locked then
					local petID, ability1ID, ability2ID, ability3ID = pet[1], pet[2], pet[3], pet[4]
					firstPet = petID

					if equippedPetID ~= petID then
						C_PetJournal_SetPetLoadOutInfo(i, petID)
						recheck = true
					else
						if equippedAbility1ID ~= ability1ID then
							C_PetJournal_SetAbility(i, 1, ability1ID)
							recheck = true
						end
						if equippedAbility2ID ~= ability2ID then
							C_PetJournal_SetAbility(i, 2, ability2ID)
							recheck = true
						end
						if equippedAbility3ID ~= ability3ID then
							C_PetJournal_SetAbility(i, 3, ability3ID)
							recheck = true
						end
					end
				end
			end
		end

		-- if not all pets or abilities were loaded we will check again really soon
		if recheck then
			C_Timer_After(.1, function()
				addon:EquipTeamLoadout(team)
			end)
		end

		-- update the pet journal UI
		PetJournal_UpdatePetLoadOut()
	end

	addon.LoadingLoadOut = nil
end

-- is team equipped
function addon:IsTeamEquipped(team)
	if type(team) == "table" then
		for i = 1, MAX_ACTIVE_PETS do
			local pet = team[i]
			if type(pet) ~= "table" then
				return false
			end
			local equippedPetID, equippedAbility1ID, equippedAbility2ID, equippedAbility3ID, locked = C_PetJournal_GetPetLoadOutInfo(i)
			local petID, ability1ID, ability2ID, ability3ID = pet[1], pet[2], pet[3], pet[4]
			if equippedPetID ~= petID then
				return false
			end
			if equippedAbility1ID ~= ability1ID then
				return false
			end
			if equippedAbility2ID ~= ability2ID then
				return false
			end
			if equippedAbility3ID ~= ability3ID then
				return false
			end
		end
	end
	return true
end

-- get team texture
function addon:GetTeamTexture(team)
	local texture = "Interface\\Icons\\INV_Misc_QuestionMark"
	if type(team) == "table" then
		local _, firstPet = next(team)
		if firstPet and firstPet[1] then
			_, _, _, _, _, _, _, _, texture = C_PetJournal_GetPetInfoByPetID(firstPet[1])
		end
	end
	return texture
end

-- get team tooltip string
function addon:GetTeamTooltipString(team)
	if type(team) == "table" then
		local lines = ""

		for i = 1, #team do
			local pet = team[i]

			if type(pet) == "table" then
				local petID, ability1ID, ability2ID, ability3ID = pet[1], pet[2], pet[3], pet[4]
				local speciesID, customName, level, xp, maxXp, displayID, isFavorite, name, icon, petType, creatureID, sourceText, description, isWild, canBattle, tradable, unique = C_PetJournal_GetPetInfoByPetID(petID)

				if speciesID then
					local health, maxHealth, power, speed, rarity = C_PetJournal_GetPetStats(petID)
					local color = ITEM_QUALITY_COLORS[rarity - 1]

					lines = lines .. "L" .. level .. " "
					lines = lines .. "|T" .. icon .. ":-1:-1|t "
					lines = lines .. color.hex .. (customName or name) .. "|r "
					lines = lines .. format("|cff00FF00%d|r/|cff00FFFF%d|r/|cffFFFF00%d|r", health/maxHealth*100, power, speed) .. " "
					lines = lines .. "\n"
				end
			end
		end

		lines = lines:sub(1, lines:len() - 1)

		if lines ~= "" then
			return "\n" .. lines
		end
	end
end

-- widget handlers
do
	addon.Widget = {}

	-- hide all flyouts and uncheck all buttons
	addon.Widget.HideFlyouts = function(button)
		if addon.Manager.button ~= button then
			addon.Manager.button:SetChecked(false)
			addon.Manager.flyout:Hide()
		end

		for _, team in pairs(addon.Teams) do
			if team.button ~= button then
				team.button:SetChecked(false)
				team.flyout:Hide()
			end
			if addon:IsTeamEquipped(team) then
				team.button:SetChecked(true)
			end
		end
	end

	-- tooltip handlers
	do
		addon.Tooltip = {}

		local tooltip = GameTooltip -- CreateFrame("GameTooltip", addonName .. "Tooltip", WorldFrame, "GameTooltipTemplate")

		function addon.Tooltip:Show(frame, lines)
			tooltip:SetOwner(frame, "ANCHOR_RIGHT")
			if type(lines) == "string" then
				tooltip:AddLine(lines, 1, 1, 1)
			elseif type(lines) == "table" then
				for _, line in ipairs(lines) do
					tooltip:AddLine(line, 1, 1, 1)
				end
			end
			tooltip:Show()
		end

		function addon.Tooltip:Hide()
			tooltip:Hide()
		end
	end

	-- container handlers
	do
		addon.Widget.Container = {}

		function addon.Widget.Container.OnShow(self)
			addon.Widget.HideFlyouts()
			addon:DraggingPickupTeam()

			addon.IsDraggingTeam = nil
			addon.IsDraggingInactiveTeam = nil

			addon:UPDATE()
		end
	end

	-- manager handlers
	do
		addon.Widget.Manager = {}

		function addon.Widget.Manager.OnClick(self)
			addon.Widget.HideFlyouts(self)

			if self:GetChecked() then
				self:GetParent().flyout:Show()
			else
				self:GetParent().flyout:Hide()
			end
		end

		function addon.Widget.Manager.OnEnter(self)
			if not addon.IsDraggingInactiveTeam then
				addon.Tooltip:Show(self, addonName)
			end
		end

		function addon.Widget.Manager.OnLeave(self)
			addon.Tooltip:Hide()
		end
	end

	-- pet button handlers
	do
		addon.Widget.PetButton = {}

		function addon.Widget.PetButton.OnClick(self, button)
			addon.Widget.HideFlyouts(self)

			if button == "RightButton" then
				if self:GetChecked() then
					self:GetParent().flyout:Show()
				else
					self:GetParent().flyout:Hide()
				end
			else
				self:GetParent().flyout:Hide()
				self:SetChecked(false)

				addon:EquipTeamLoadout(self:GetParent().dbTeam)

				addon:UPDATE()
			end
		end

		function addon.Widget.PetButton.OnDragStart(self)
			self:LockHighlight()
			self:GetParent().flyout:Hide()

			addon.IsDraggingTeam = self:GetParent()
			addon:DraggingPickupTeam(self:GetParent().dbTeam)
			addon:UPDATE()
		end

		function addon.Widget.PetButton.OnDragStop(self)
			self:UnlockHighlight()

			addon:DraggingPickupTeam()
			addon:UPDATE()

			C_Timer_After(.001, function()
				addon.IsDraggingTeam = nil
				addon:UPDATE()
			end)
		end

		function addon.Widget.PetButton.OnReceiveDrag(self)
			if addon.IsDraggingInactiveTeam then
				addon:MoveTo(addon.IsDraggingInactiveTeam, self:GetParent(), true, false)
			elseif addon.IsDraggingTeam then
				addon:MoveTo(addon.IsDraggingTeam, self:GetParent(), false, false)
			end

			addon.IsDraggingInactiveTeam = nil
			addon.IsDraggingTeam = nil
			addon:UPDATE()
		end

		function addon.Widget.PetButton.OnEnter(self)
			if addon.IsDraggingInactiveTeam then
				addon.DraggedTeamTo = self
				if self.dbTeam then
					addon.Tooltip:Show(self, {self.dbTeam and self.dbTeam.name or "Team", "Release to swap with this team."})
				else
					addon.Tooltip:Show(self, {"Team", "Release to place team on this slot."})
				end
			else
				local dbTeam = self:GetParent().dbTeam
				local lines = {dbTeam and dbTeam.name or "Team", "Left-click to equip as current loadout.", "Right-click for additional options.", "Drag to move team."}
				local tooltip = addon:GetTeamTooltipString(dbTeam)
				if tooltip then
					table.insert(lines, tooltip)
				end
				addon.Tooltip:Show(self, lines)
			end
		end

		function addon.Widget.PetButton.OnLeave(self)
			addon.Tooltip:Hide()
		end
	end

	-- flyout handlers
	do
		addon.Widget.Flyout = {}

		function addon.Widget.Flyout.OnShow(self)
		end

		function addon.Widget.Flyout.OnHide(self)
		end

		function addon.Widget.Flyout.OnUpdate(self)
		end

		function addon.Widget.Flyout.CreateButton(self, command)
			local numButtons = #self
			local buttonIndex = numButtons + 1

			local button = CreateFrame("CheckButton", "$parent" .. buttonIndex, self)
			button.command = command
			button:SetSize(BATTLEPETTABSFLYOUT_ITEM_WIDTH, BATTLEPETTABSFLYOUT_ITEM_HEIGHT)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			button:RegisterForDrag("LeftButton")
			button:SetMotionScriptsWhileDisabled(true)

			local position = numButtons / BATTLEPETTABSFLYOUT_ITEMS_PER_ROW
			if position == math.floor(position) then
				button:SetPoint("TOPLEFT", self, "TOPLEFT", BATTLEPETTABSFLYOUT_BORDERWIDTH, -BATTLEPETTABSFLYOUT_BORDERWIDTH - (BATTLEPETTABSFLYOUT_ITEM_HEIGHT - BATTLEPETTABSFLYOUT_ITEM_YOFFSET) * position)
			else
				button:SetPoint("TOPLEFT", self[numButtons], "TOPRIGHT", BATTLEPETTABSFLYOUT_ITEM_XOFFSET, 0)
			end

			button:SetScript("OnShow", addon.Widget.Flyout.Button.OnShow)
			button:SetScript("OnClick", addon.Widget.Flyout.Button.OnClick)
			button:SetScript("OnDragStart", addon.Widget.Flyout.Button.OnDragStart)
			button:SetScript("OnDragStop", addon.Widget.Flyout.Button.OnDragStop)
			button:SetScript("OnReceiveDrag", addon.Widget.Flyout.Button.OnReceiveDrag)
			button:SetScript("OnEnter", addon.Widget.Flyout.Button.OnEnter)
			button:SetScript("OnLeave", addon.Widget.Flyout.Button.OnLeave)

			-- button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
			button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
			button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			button:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD") -- TODO: "ADD" ?

			button.icon = button:CreateTexture(nil, "BORDER")
			button.icon:SetPoint("TOPLEFT", 1, -1)
			button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
			button.icon:SetTexCoord(.1, .9, .1, .9)
			button.icon:SetTexture("Interface\\Icons\\Temp")

			button.count = button:CreateFontString(nil, "BORDER", "NumberFontNormal")
			button.count:SetJustifyH("RIGHT")
			button.count:SetPoint("BOTTOMRIGHT", -5, 2)

			button.overlay = button:CreateTexture(nil, "ARTWORK", nil, -4)
			button.overlay:SetAllPoints()
			button.overlay:SetTexture(0, 0, 0, .8)
			button.overlay:Hide()

			table.insert(self, button)
			return button
		end

		function addon.Widget.Flyout.GetButton(self)
			local button

			for i = 1, #self do
				local b = self[i]

				if not b:IsShown() then
					button = b
					break
				end
			end

			if not button then
				button = self:CreateButton()
				button:SetID(#self + 1)
			end

			return button
		end

		-- flyout button handlers
		do
			addon.Widget.Flyout.Button = {}

			function addon.Widget.Flyout.Button.OnShow(self)
				if self.command == FLYOUT_COMMAND_NEW then
					self.icon:SetTexture("Interface\\GuildBankFrame\\UI-GuildBankFrame-NewTab")
				elseif self.command == FLYOUT_COMMAND_MOVETO then
					self.icon:SetTexture("Interface\\Icons\\Misc_ArrowDown")
				elseif self.command == FLYOUT_COMMAND_RENAME then
					self.icon:SetTexture("Interface\\Icons\\INV_Scroll_02")
				elseif self.command == FLYOUT_COMMAND_DELETE then
					self.icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
				end
			end

			function addon.Widget.Flyout.Button.OnClick(self, button)
				self:SetChecked(false)

				if self.command == FLYOUT_COMMAND_NEW then
					if #BattlePetTabsDB3.Inactive < BATTLEPETTABSFLYOUT_MAX_ITEMS then
						local team = addon:CopyLoadout()
						table.insert(BattlePetTabsDB3.Inactive, team)
					end

				elseif self.command == FLYOUT_COMMAND_RENAME then
					local dbTeam = self:GetParent():GetParent().dbTeam
					if dbTeam then
						addon:RenameTeam(dbTeam)
					end

				elseif self.command == FLYOUT_COMMAND_DELETE then
					local dbTeam = self:GetParent():GetParent().dbTeam
					for i, team in ipairs(BattlePetTabsDB3.Teams) do
						if team == dbTeam then
							table.remove(BattlePetTabsDB3.Teams, i)
							break
						end
					end

				elseif self.command == FLYOUT_COMMAND_TEAM then
					if button == "RightButton" then
						for i, team in ipairs(BattlePetTabsDB3.Inactive) do
							if self.dbTeam == team then
								table.remove(BattlePetTabsDB3.Inactive, i)
								break
							end
						end
					end
				end

				addon:UPDATE()
			end

			function addon.Widget.Flyout.Button.OnDragStart(self)
				if self.command == FLYOUT_COMMAND_TEAM then
					self:LockHighlight()

					addon.IsDraggingInactiveTeam = self
					addon:DraggingPickupTeam(self.dbTeam)
					addon:UPDATE()
				end
			end

			function addon.Widget.Flyout.Button.OnDragStop(self)
				if self.command == FLYOUT_COMMAND_TEAM then
					self:UnlockHighlight()

					addon:DraggingPickupTeam()
					addon:UPDATE()

					C_Timer_After(.001, function()
						addon.IsDraggingInactiveTeam = nil
						addon:UPDATE()
					end)
				end
			end

			function addon.Widget.Flyout.Button.OnReceiveDrag(self)
				if addon.IsDraggingInactiveTeam then
					addon:MoveTo(addon.IsDraggingInactiveTeam, self, true, false)
				elseif addon.IsDraggingTeam then
					addon:MoveTo(addon.IsDraggingTeam, self, false, false)
				end

				addon.IsDraggingInactiveTeam = nil
				addon.IsDraggingTeam = nil
				addon:UPDATE()
			end

			function addon.Widget.Flyout.Button.OnEnter(self)
				if self.command == FLYOUT_COMMAND_NEW then
					if not addon.IsDraggingInactiveTeam then
						if self:IsEnabled() then
							addon.Tooltip:Show(self, {"New", "Creates a copy of the current loadout."})
						else
							addon.Tooltip:Show(self, {"New", "Can't create additional teams.", "Delete unused teams to free up space."})
						end
					end
				elseif self.command == FLYOUT_COMMAND_MOVETO then
					if addon.IsDraggingTeam then
						if self:IsEnabled() then
							addon.Tooltip:Show(self, {"Deactivate", "Places the team with the other inactive teams."})
						else
							addon.Tooltip:Show(self, {"Deactivate", "Can't deactive team.", "Delete unused inactive teams to free up space."})
						end
					end
				elseif self.command == FLYOUT_COMMAND_RENAME then
					if not addon.IsDraggingInactiveTeam then
						addon.Tooltip:Show(self, "Rename")
					end
				elseif self.command == FLYOUT_COMMAND_DELETE then
					if not addon.IsDraggingInactiveTeam then
						addon.Tooltip:Show(self, {"Delete", "This can't be undone."})
					end
				elseif self.command == FLYOUT_COMMAND_TEAM then
					if addon.IsDraggingInactiveTeam then
						addon.DraggedTeamTo = self
						addon.Tooltip:Show(self, {self.dbTeam and self.dbTeam.name or "Team", "Release to move team to this position."})
					else
						local lines = {self.dbTeam and self.dbTeam.name or "Team", "Drag to move team.", "Right-click to delete."}
						local tooltip = addon:GetTeamTooltipString(self.dbTeam)
						if tooltip then
							table.insert(lines, tooltip)
						end
						addon.Tooltip:Show(self, lines)
					end
				end
			end

			function addon.Widget.Flyout.Button.OnLeave(self)
				addon.Tooltip:Hide()
			end
		end
	end
end

-- update the current team when loadout is manually changed
do
	hooksecurefunc(C_PetJournal, "SetPetLoadOutInfo", function(slotIndex, petID)
		if not addon.LoadingLoadOut and addon.EquippedLoadOut then
			local loadout = addon:CopyLoadout()
			for i = 1, MAX_ACTIVE_PETS do
				addon.EquippedLoadOut[i] = loadout[i]
			end
		end
	end)

	hooksecurefunc(C_PetJournal, "SetAbility", function(slotIndex, abilityIndex, abilityID)
		if not addon.LoadingLoadOut and addon.EquippedLoadOut then
			addon.EquippedLoadOut[slotIndex][abilityIndex + 1] = abilityID
		end
	end)
end
