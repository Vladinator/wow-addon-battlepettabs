local _G = _G
local C_PetBattles = C_PetBattles
local C_PetBattles_GetAbilityInfoByID = C_PetBattles.GetAbilityInfoByID
local C_PetBattles_GetAttackModifier = C_PetBattles.GetAttackModifier
local C_PetBattles_GetPVPMatchmakingInfo = C_PetBattles.GetPVPMatchmakingInfo
local C_PetBattles_IsInBattle = C_PetBattles.IsInBattle
local C_PetJournal = C_PetJournal
local C_PetJournal_GetNumPetTypes = C_PetJournal.GetNumPetTypes
local C_PetJournal_GetPetInfoByPetID = C_PetJournal.GetPetInfoByPetID
local C_PetJournal_GetPetInfoBySpeciesID = C_PetJournal.GetPetInfoBySpeciesID
local C_PetJournal_GetPetLoadOutInfo = C_PetJournal.GetPetLoadOutInfo
local C_PetJournal_IsJournalUnlocked = C_PetJournal.IsJournalUnlocked
local C_PetJournal_SetAbility = C_PetJournal.SetAbility
local C_PetJournal_SetPetLoadOutInfo = C_PetJournal.SetPetLoadOutInfo
local ChatEdit_FocusActiveWindow = ChatEdit_FocusActiveWindow
local ClearCursor = ClearCursor
local CreateFrame = CreateFrame
local CreateMacro = CreateMacro
local DeleteMacro = DeleteMacro
local EditMacro = EditMacro
local GameTooltip = GameTooltip
local GetMacroIndexByName = GetMacroIndexByName
local GetMouseFocus = GetMouseFocus
local GetNumMacros = GetNumMacros
local HideUIPanel = HideUIPanel
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local Is64BitClient = Is64BitClient
local IsModifiedClick = IsModifiedClick
local math = math
local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 36 -- LOD
local OKAY = OKAY
local pairs = pairs
local PickupMacro = PickupMacro
local PlaySound = PlaySound
local print = print
local select = select
local SetItemButtonCount = SetItemButtonCount
local SetItemButtonNormalTextureVertexColor = SetItemButtonNormalTextureVertexColor
local SetItemButtonTexture = SetItemButtonTexture
local SetItemButtonTextureVertexColor = SetItemButtonTextureVertexColor
local StaticPopup_Hide = StaticPopup_Hide
local StaticPopup_Show = StaticPopup_Show
local StaticPopupDialogs = StaticPopupDialogs
local strlen = strlen
local strlower = strlower
local table = table
local time = time
local tonumber = tonumber
local type = type
local unpack = unpack

local addonName = ...
local addon = CreateFrame("Frame")
local frameName = "BattlePetTabs"
local petJournalAddonName = "Blizzard_PetJournal"
local numTabs = 8 -- hardcoded tab limit (so they don't grow outside the journal frame)
BattlePetTabsDB2 = type(BattlePetTabsDB2) == "table" and BattlePetTabsDB2 or {}
BattlePetTabsSnapshotDB = type(BattlePetTabsSnapshotDB) == "table" and BattlePetTabsSnapshotDB or {}

local watcher = CreateFrame("Frame")
local elapsed = 0

local LoadTeam
local Watcher_OnUpdate
local Update
local Initialize

local EMPTY_PET_X64 = "0x0000000000000000"
local EMPTY_PET_X86 = "0x00000000"
local EMPTY_PET = "0x0000"
local EMPTY_PET_DYNAMIC = EMPTY_PET_X64 -- Is64BitClient() and EMPTY_PET_X64 or EMPTY_PET_X86

local MAX_ACTIVE_PETS = 3
local MAX_ACTIVE_ABILITIES = 3
local MAX_PET_LEVEL = 25

local PET_EFFECTIVENESS_CHART = {
	[1] = {4, 5},  -- Humanoid    +Undead      -Critter
	[2] = {1, 3},  -- Dragon      +Humanoid    -Flying
	[3] = {6, 8},  -- Flying      +Magical     -Beast
	[4] = {5, 2},  -- Undead      +Critter     -Dragon
	[5] = {8, 1},  -- Critter     +Beast       -Humanoid
	[6] = {2, 9},  -- Magical     +Dragon      -Water
	[7] = {9, 10}, -- Elemental   +Water       -Mechanical
	[8] = {10, 1}, -- Beast       +Mechanical  -Humanoid
	[9] = {3, 4},  -- Water       +Flying      -Undead
	[10] = {7, 6}, -- Mechanical  +Elemental   -Magical
}

local InCombatLockdown
local InProcessingLockdown
do
	local _G_InCombatLockdown = _G.InCombatLockdown
	local combat

	addon:HookScript("OnEvent", function(addon, event, ...)
		if event == "PLAYER_REGEN_DISABLED" then
			combat = 1
		elseif event == "PLAYER_REGEN_ENABLED" then
			combat = nil
		end
	end)

	function InCombatLockdown()
		return _G_InCombatLockdown() or combat
	end
end

do
	local isCoreLoaded, isJournalLoaded, isEventFound

	addon:HookScript("OnEvent", function(addon, event, ...)
		if event == "ADDON_LOADED" then
			if ... == addonName then
				isCoreLoaded = 1
			elseif ... == petJournalAddonName then
				isJournalLoaded = 1
			end
			if type(PetJournalParent) == "table" and type(PetJournalParent.GetObjectType) == "function" then
				isJournalLoaded = 1 -- some addons load the PetJournal before PetBattleTabs can load - leaving it waiting for the PetJournal until the end of days - but no longer!
			end
		elseif event == "UPDATE_SUMMONPETS_ACTION" then
			isEventFound = 1
		end
		if isCoreLoaded and isJournalLoaded and isEventFound then
			isCoreLoaded, isJournalLoaded, isEventFound = nil
			addon:UnregisterEvent("ADDON_LOADED")
			addon:UnregisterEvent("UPDATE_SUMMONPETS_ACTION")
			Initialize()
		end
	end)

	addon:RegisterEvent("ADDON_LOADED")
	addon:RegisterEvent("UPDATE_SUMMONPETS_ACTION")
end

local function GetStatIconString(i)
	return "|TInterface\\PetBattles\\BattleBar-AbilityBadge-" .. (i and "Strong" or "Weak") .. ":18:18:0:-2|t" -- 18:18 looks good
end

local function GetPetIconString(i, s) -- needs more work, the dimensions get weird when the image is too big and it creates too much padding
	return "|TInterface\\PetBattles\\PetIcon-" .. (type(i) == "string" and i or (type(i) == "number" and PET_TYPE_SUFFIX[i] or "NO_TYPE")) .. ":22:22:3:" .. (s and "2" or "4.25") .. ":128:256:62:128:102:168|t" -- 18:18 too small, 22:22 is better
end

local function BuildPetTooltipString(petId)
	local speciesId, customName, level, xp, maxXp, displayID, isFavorite, petName, petIcon, petType, creatureID, sourceText, description, isWild, canBattle, tradable, unique = C_PetJournal_GetPetInfoByPetID(petId)
	if not speciesId then
		speciesId, petName, petIcon = 0, "Unknown", "Interface\\Icons\\INV_Misc_QuestionMark.blp"
	elseif customName then
		petName = customName
	end
	if level then
		return GetPetIconString(select(3, C_PetJournal_GetPetInfoBySpeciesID(speciesId)), nil) .. "|T" .. petIcon .. ":18:18|t |cffCCCCCCL"..level.."|r " .. petName .. (maxXp > 0 and level < MAX_PET_LEVEL and " |cffCCCCCC("..math.floor(xp/maxXp*100).."% exp)|r" or "") -- 0:0 too small, 18:18 is better
	end
	return ""
end

local function BuildStrongWeakTooltip(petIds, isAttack, isWeak)
	local speciesId, abilityId, petType
	local modifier, matchStrong, matchWeak
	local temp = {strong = {}, weak = {}, sKeys = {}, wKeys = {}}
	for _, petData in pairs(petIds) do
		local petId = petData[1]
		speciesId = C_PetJournal_GetPetInfoByPetID(petId)
		if speciesId then
			abilityId = PET_BATTLE_PET_TYPE_PASSIVES[select(3, C_PetJournal_GetPetInfoBySpeciesID(speciesId))]
			petType = select(7, C_PetBattles_GetAbilityInfoByID(abilityId))
			if isAttack then
				if petType then
					for i = 1, C_PetJournal_GetNumPetTypes() do
						modifier = C_PetBattles_GetAttackModifier(petType, i)
						if modifier > 1 then
							temp.strong[PET_TYPE_SUFFIX[i]] = GetPetIconString(i, 1)
							table.insert(temp.sKeys, PET_TYPE_SUFFIX[i])
						elseif modifier < 1 then
							temp.weak[PET_TYPE_SUFFIX[i]] = GetPetIconString(i, 1)
							table.insert(temp.wKeys, PET_TYPE_SUFFIX[i])
						end
					end
				end
			else
				if petType then
					matchStrong, matchWeak = unpack(PET_EFFECTIVENESS_CHART[petType] or {})
					if matchStrong then
						temp.strong[matchStrong] = GetPetIconString(matchStrong, 1)
						table.insert(temp.sKeys, matchStrong)
					end
					if matchWeak then
						temp.weak[matchWeak] = GetPetIconString(matchWeak, 1)
						table.insert(temp.wKeys, matchWeak)
					end
				end
			end
		end
	end
	local lookup = isWeak and temp.wKeys or temp.sKeys
	local lookup2 = isWeak and temp.weak or temp.strong
	table.sort(lookup)
	local text = ""
	for _, key in ipairs(lookup) do
		text = text..lookup2[key]
	end
	return text:trim()
end

local function PetJournal_UpdateDisplay()
	if type(PetJournal_UpdatePetLoadOut) == "function" then
		PetJournal_UpdatePetLoadOut()
	elseif type(PetJournal_UpdateAll) == "function" then
		PetJournal_UpdateAll()
	end
end

local function GetNumTeams()
	local i = 0
	if type(BattlePetTabsDB2) == "table" then
		for _, object in pairs(BattlePetTabsDB2) do
			if type(object) == "table" then
				i = i + 1
			end
		end
	end
	return i
end

local function GetTeamId(teamId)
	teamId = tonumber(teamId) or 0
	if teamId < 1 then
		teamId = tonumber(BattlePetTabsDB2.currentId) or 0
	end
	if teamId >= 1 then
		return teamId
	end
	return 1 -- fallback
end

--[[ desperate times call for desperate measures
local ValidatePetSmartly
do
	local MAX_FAILS = 3
	local CHECK_INTERVAL = 1
	ValidatePetSmartly = {}

	function ValidatePetSmartly:Check(petId)
		if not self[petId] then
			self[petId] = {time(), 1}
		end
		if C_PetJournal_GetPetInfoByPetID(petId) then
			self[petId] = nil
			return 1
		end
		if self[petId][2] > MAX_FAILS then
			self[petId] = nil
			--print("DEBUG", "VPS:C(", petId, ") = FAIL") -- DEBUG
			return nil
		end
		if time() - self[petId][1] > CHECK_INTERVAL then
			self[petId][1] = time()
			self[petId][2] = self[petId][2] + 1
			--print("DEBUG", "VPS:C(", petId, ") =", self[petId][2]) -- DEBUG
		end
		return self[petId][2]
	end
end --]] --_G.ValidatePetSmartly = ValidatePetSmartly -- /run ValidatePetSmartly:Check("0x0000000000000000") -- DEBUG

local function ValidatePetId(petId, petCheck, isValidating)
	if type(petId) == "string" and strlen(petId) >= 10 and (not Is64BitClient() or strlen(petId) >= 18) then -- x86 is 8+2 while x64 is 16+2
		if petCheck then
			return C_PetJournal_GetPetInfoByPetID(petId)
		end
		return 1
	end
end

local function ValidateTeam(teamId, attemptFix)
	teamId = GetTeamId(teamId)
	if type(BattlePetTabsDB2[teamId]) == "table" then
		local team = BattlePetTabsDB2[teamId]
		if type(team.name) ~= "string" then
			return
		end
		if type(team.setup) ~= "table" then
			if attemptFix then
				team.setup = {}
			else
				return
			end
		end
		for index = 1, MAX_ACTIVE_PETS do
			local petData = team.setup[index]
			if type(petData) ~= "table" then
				if attemptFix then
					team.setup[index] = {EMPTY_PET_DYNAMIC, 0, 0, 0}
					petData = team.setup[index]
				else
					return
				end
			end
			local petId, ab1, ab2, ab3 = petData[1], petData[2], petData[3], petData[4]
			if not ValidatePetId(petId, 1, 1) then
				if attemptFix then
					team.setup[index] = {EMPTY_PET_DYNAMIC, 0, 0, 0}
				else
					return
				end
			end
		end
		if type(team.icon) ~= "string" then
			team.icon = "Interface\\Icons\\INV_Misc_QuestionMark.blp"
		end
		BattlePetTabsDB2[teamId] = team
		return team
	end
end

local function ApplyRename(teamId, newName)
	teamId = GetTeamId(teamId)
	if teamId <= numTabs and type(newName) == "string" and strlen(newName) > 0 then
		BattlePetTabsDB2[teamId].name = newName
		GameTooltip:Hide()
		Update()
	end
end

local function ApplyDelete(teamId)
	teamId = GetTeamId(teamId)
	if teamId <= numTabs then
		table.wipe(BattlePetTabsDB2[teamId])
		if teamId - 1 >= 1 then
			BattlePetTabsDB2.currentId = teamId - 1
		elseif BattlePetTabsDB2.currentId > 1 then
			BattlePetTabsDB2.currentId = BattlePetTabsDB2.currentId - 1
		else
			BattlePetTabsDB2.currentId = 1
		end
		GameTooltip:Hide()
		LoadTeam()
		Update()
	end
end

local function GetTeamMacroName(teamId)
	teamId = GetTeamId(teamId)
	if teamId then
		return "BattlePetTeam" .. teamId
	end
end

local function CreateTeamMacro(macroName, teamId, teamData)
	teamId = GetTeamId(teamId)
	if type(macroName) ~= "string" then
		return
	end
	if type(teamId) ~= "number" then
		return
	end
	if type(teamData) ~= "table" then
		return
	end
	if InCombatLockdown() then
		return -- can't work with macros in combat
	end
	if GetNumMacros() >= MAX_ACCOUNT_MACROS then
		return print("Can't create macro for team #" .. teamId .. " because you don't have any more available macro slots in your General category.")
	end
	if MacroFrame then
		HideUIPanel(MacroFrame)
	end
	local iconFile = teamData.icon:lower():gsub(".-\\.-\\(.-)%.blp", "%1") -- need only the filename, the API is strict and doesn't anyway let you define paths outside the Interface\Icons folder
	local macroBody = "#showtooltip\n/run PetJournal_LoadUI()if\"RightButton\"==GetMouseButtonClicked()then TogglePetJournal(2)else local i,b=tonumber(" .. (teamId or 0) .. ")b=_G[\"" .. frameName .. "Tab\"..i..\"Button\"]if b then if not b.newTeam then b:Click()end else print\"" .. frameName .. " not loaded!\"end end"
	if GetMacroIndexByName(macroName) == 0 then
		CreateMacro(macroName, 0, macroBody, nil)
	end
	return EditMacro(GetMacroIndexByName(macroName), macroName, iconFile, macroBody)
end

local function IntegrityCheck()
	local temp = {}
	for index, team in ipairs(BattlePetTabsDB2) do
		team = ValidateTeam(index, 1)
		if team then
			table.insert(temp, team)
		end
	end
	temp.currentId = BattlePetTabsDB2.currentId
	BattlePetTabsDB2 = temp
	if not InCombatLockdown() then
		local lastId = #temp
		if lastId == 0 then
			for i = 1, numTabs do
				if ValidateTeam(i, 1) then
					lastId = lastId + 1
				else
					lastId = lastId - 1
				end
			end
		end
		local canDelete = 1
		if type(BattlePetTabsSnapshotDB.db) == "table" then
			for _, snapshot in pairs(BattlePetTabsSnapshotDB.db) do
				if type(snapshot) == "table" and type(snapshot.db) == "table" then
					local numTeams = 0
					for _, team in pairs(snapshot.db) do
						if type(team) == "table" then
							numTeams = numTeams + 1
						end
					end
					if numTeams > lastId then
						canDelete = nil
						break
					end
				end
			end
		end
		for i = 1, numTabs do
			local macroName = GetTeamMacroName(i)
			if macroName then
				if lastId > 0 and i <= lastId then
					local macroIndex = GetMacroIndexByName(macroName)
					if macroIndex > 0 then
						CreateTeamMacro(macroName, i, BattlePetTabsDB2[i])
					end
				elseif canDelete then
					DeleteMacro(macroName)
				end
			end
		end
	end
end

local function UpdateCurrentTeam(teamId)
	teamId = GetTeamId(teamId)
	if type(BattlePetTabsDB2[teamId]) ~= "table" then
		BattlePetTabsDB2[teamId] = {}
	end
	local team = BattlePetTabsDB2[teamId]
	if type(team.name) ~= "string" then
		team.name = "Team " .. teamId
	end
	if type(team.setup) ~= "table" then
		team.setup = {}
	end
	table.wipe(team.setup)
	for i = 1, MAX_ACTIVE_PETS do
		local petId, ab1, ab2, ab3, locked = C_PetJournal_GetPetLoadOutInfo(i)
		if petId then
			table.insert(team.setup, {petId, ab1, ab2, ab3})
		end
	end
	for i = MAX_ACTIVE_PETS - #team.setup, 1, -1 do
		table.insert(team.setup, {EMPTY_PET_DYNAMIC, 0, 0, 0})
	end
	team.icon = nil
	for _, petData in ipairs(team.setup) do
		if not team.icon then
			team.icon = select(9, C_PetJournal_GetPetInfoByPetID(petData[1]))
		else
			break
		end
	end
	if not team.icon then
		team.icon = "Interface\\Icons\\INV_Misc_QuestionMark.blp"
	end
	Update()
end

local function UpdateTeamLoadOut(slotId, petId, skipUpdating, ...)
	if skipUpdating ~= addonName then
		UpdateCurrentTeam()
	end
end

local function UpdateTeamLoadOutAbilities(slotId, abilitySlot, abilityId, skipUpdating, ...)
	if skipUpdating ~= addonName then
		UpdateCurrentTeam()
	end
end

function LoadTeam(teamId) -- local
	teamId = GetTeamId(teamId)
	if type(BattlePetTabsDB2[teamId]) ~= "table" or type(BattlePetTabsDB2[teamId].setup) ~= "table" or not ValidateTeam(teamId, 1) then
		return
	end
	local team = BattlePetTabsDB2[teamId]
	local pets, count, emptyCount, unhook, loadoutId = {}, 0, 0
	for i = 1, MAX_ACTIVE_PETS do
		local petData = team.setup[i]
		if type(petData) == "table" then
			local petId, ab1, ab2, ab3 = petData[1], petData[2], petData[3], petData[4]
			petId = strlower(petId)
			loadoutId = C_PetJournal_GetPetLoadOutInfo(i)
			if loadoutId then
				loadoutId = strlower(loadoutId)
			end
			if petId == loadoutId or ((petId == "" or petId == EMPTY_PET_X64 or petId == EMPTY_PET_X86 or petId == EMPTY_PET) and not loadoutId) then
				count = count + 1
				if not loadoutId then
					emptyCount = emptyCount + 1
				end
			elseif ValidatePetId(petId, 1) then
				C_PetJournal_SetPetLoadOutInfo(i, petId, addonName)
			else
				C_PetJournal_SetPetLoadOutInfo(i, EMPTY_PET_DYNAMIC, addonName)
			end
			table.insert(pets, {petId, ab1, ab2, ab3})
		end
	end
	if count == MAX_ACTIVE_PETS then
		unhook = 1
		count = 0
		for i, petData in ipairs(pets) do
			local petId = petData[1]
			if petId == "" or petId == EMPTY_PET_X64 or petId == EMPTY_PET_X86 or petId == EMPTY_PET then
				count = count + MAX_ACTIVE_ABILITIES
			else
				for j = 1, MAX_ACTIVE_ABILITIES do
					if petData[1 + j] == 0 or petData[1 + j] == select(1 + j, C_PetJournal_GetPetLoadOutInfo(i)) then
						count = count + 1
					else
						C_PetJournal_SetAbility(i, j, petData[1 + j], addonName)
					end
				end
			end
		end
		if count ~= MAX_ACTIVE_PETS * MAX_ACTIVE_ABILITIES then
			unhook = nil
		end
		if unhook then
			InProcessingLockdown = nil
			watcher:SetScript("OnUpdate", nil)
			elapsed = 0
			PetJournal_UpdateDisplay()
		else
			InProcessingLockdown = 1
			watcher:SetScript("OnUpdate", Watcher_OnUpdate)
		end
	else
		InProcessingLockdown = 1
		watcher:SetScript("OnUpdate", Watcher_OnUpdate)
	end
	Update()
end

function Watcher_OnUpdate(watcher, elapse) -- local
	elapsed = elapsed + elapse
	if elapsed > .1 then
		elapsed = 0
		LoadTeam()
	end
end

local function onGameTooltipShow(self)
	local text, tabButton = _G[self:GetName() .. "TextLeft1"]:GetText()
	for i = 1, numTabs do
		if text and text == GetTeamMacroName(i) then
			tabButton = _G[frameName .. "Tab" .. i .. "Button"]
			if tabButton and tabButton.tooltip and not tabButton.newTeam and tabButton:IsVisible() then
				self:ClearLines()
				if type(tabButton.tooltip) == "table" then
					for _, line in ipairs(tabButton.tooltip) do
						self:AddLine(line)
					end
				else
					self:AddLine(tabButton.tooltip)
				end
				self:AddLine("|cff999999Right-click to open the Pet Journal|r")
				self:Show()
			end
			break
		end
	end
end

local function UpdateLock()
	local lockdown = InProcessingLockdown or not C_PetJournal_IsJournalUnlocked() or C_PetBattles_GetPVPMatchmakingInfo() or C_PetBattles_IsInBattle() or InCombatLockdown() -- reason for InCombatLockdown is to prevent managing pets and calling combat protected functions and throwing errors everywhere
	local tabButton, tabTexture
	tabButton = _G[frameName .. "TabManagerButton"]
	tabTexture = _G[frameName .. "TabManagerButtonIconTexture"]
	if lockdown then
		tabButton:Disable()
		tabTexture:SetDesaturated(true)
		if InProcessingLockdown then
			tabButton.tooltip2 = "Please wait..."
		else
			tabButton.tooltip2 = {"|cffFFFFFFLocked|r", "You are either queued for a match\nor caught up in a pet battle."}
		end
		BattlePetTabFlyoutFrame:Hide()
	else
		tabButton:Enable()
		tabTexture:SetDesaturated(false)
		tabButton.tooltip2 = nil
	end
	for i = 1, numTabs do
		tabButton = _G[frameName .. "Tab" .. i .. "Button"]
		if tabButton:IsVisible() then
			tabTexture = _G[frameName .. "Tab" .. i .. "ButtonIconTexture"]
			if lockdown then
				tabButton:Disable()
				tabTexture:SetDesaturated(true)
				if InProcessingLockdown then
					tabButton.tooltip2 = "Please wait..."
				else
					tabButton.tooltip2 = {"|cffFFFFFFLocked|r", "You are either queued for a match\nor caught up in a pet battle."}
				end
			else
				tabButton:Enable()
				tabTexture:SetDesaturated(false)
				tabButton.tooltip2 = nil
			end
		end
	end
end

function Update() -- local
	IntegrityCheck()
	local shownNewTeam
	for i = 1, numTabs do
		local team = BattlePetTabsDB2[i] or {}
		local tab = _G[frameName .. "Tab" .. i]
		local tabButton = _G[frameName .. "Tab" .. i .. "Button"]
		if shownNewTeam then
			tab:Hide()
			tabButton:SetEnabled(false)
		else
			local tabTexture = _G[frameName .. "Tab" .. i .. "ButtonIconTexture"]
			if type(team.setup) ~= "table" then
				tabTexture:SetTexture("Interface\\GuildBankFrame\\UI-GuildBankFrame-NewTab")
				tabButton.tooltip = "New Team"
				tabButton.newTeam = 1
				shownNewTeam = 1
			else
				tabTexture:SetTexture(team.icon)
				tabButton.tooltip = {}
				table.insert(tabButton.tooltip, team.name)
				tabButton.newTeam = nil
				for _, petData in ipairs(team.setup) do
					table.insert(tabButton.tooltip, BuildPetTooltipString(petData[1]))
				end
				table.insert(tabButton.tooltip, "Atk." .. GetStatIconString(1) .. "vs " .. BuildStrongWeakTooltip(team.setup, 1))
				table.insert(tabButton.tooltip, "Atk." .. GetStatIconString() .. "vs " .. BuildStrongWeakTooltip(team.setup, 1, 1))
				table.insert(tabButton.tooltip, "Def." .. GetStatIconString(1) .. "vs " .. BuildStrongWeakTooltip(team.setup, nil, 1))
				table.insert(tabButton.tooltip, "Def." .. GetStatIconString() .. "vs " .. BuildStrongWeakTooltip(team.setup))
			end
			if not tabButton.newTeam and i == GetTeamId() then
				tabButton:SetChecked(1)
			else
				tabButton:SetChecked(nil)
			end
			tab:Show()
			tabButton:SetEnabled(true)
		end
	end
	UpdateLock()
	local focus = GetMouseFocus() -- the tooltip stays the same when we add or remove teams, so this helps update that tooltip automatically by checking what we are currently hovering over and triggering the mechanism is appropriate
	if type(focus) == "table" and type(focus.GetObjectType) == "function" and (focus:GetObjectType() == "Button" or focus:GetObjectType() == "CheckButton") and type(focus.GetScript) == "function" then
		(focus:GetScript("OnEnter") or function() end)(focus)
	end
	PetJournal_UpdateDisplay()
	if BattlePetTabFlyoutFrame:IsVisible() then
		BattlePetTabFlyoutPopupFrame.skipHide = 1
		BattlePetTabFlyoutFrame:Hide()
		BattlePetTabFlyoutFrame:Show()
	end
end

function BattlePetTab_OnClick(self, button, currentId)
	if button == "LeftButton" then
		StaticPopup_Hide("BATTLETABS_TEAM_RENAME")
		StaticPopup_Hide("BATTLETABS_TEAM_DELETE")
	end
	if not self.newTeam or button == "LeftButton" then
		BattlePetTabsDB2.currentId = currentId
		if button == "LeftButton" then
			if self.newTeam then
				UpdateCurrentTeam()
			end
			LoadTeam()
		elseif button == "RightButton" and not self.newTeam then
			LoadTeam()
			if IsModifiedClick() then
				StaticPopup_Show("BATTLETABS_TEAM_RENAME", BattlePetTabsDB2[currentId].name, nil, currentId)
			else
				StaticPopup_Show("BATTLETABS_TEAM_DELETE", BattlePetTabsDB2[currentId].name, nil, currentId)
			end
		end
	end
	Update()
end

function BattlePetTab_OnDrag(self, button, currentId)
	if not InCombatLockdown() and not self.newTeam then
		local macroName = GetTeamMacroName(currentId)
		if macroName then
			local macroId = CreateTeamMacro(macroName, currentId, BattlePetTabsDB2[currentId])
			if macroId then
				ClearCursor()
				PickupMacro(macroId)
			end
		end
	end
end

local BATTLEPETTABSFLYOUT_ITEM_HEIGHT = 37
local BATTLEPETTABSFLYOUT_ITEM_WIDTH = 37
local BATTLEPETTABSFLYOUT_ITEM_XOFFSET = 4
local BATTLEPETTABSFLYOUT_ITEM_YOFFSET = -5

local BATTLEPETTABSFLYOUT_BORDERWIDTH = 3
local BATTLEPETTABSFLYOUT_HEIGHT = 43
local BATTLEPETTABSFLYOUT_WIDTH = 43

local BATTLEPETTABSFLYOUT_ITEMS_PER_ROW = 5
local BATTLEPETTABSFLYOUT_MAXITEMS = 50

local BATTLEPETTABSFLYOUT_ONESLOT_LEFT_COORDS = {0, 0.09765625, 0.5546875, 0.77734375}
local BATTLEPETTABSFLYOUT_ONESLOT_RIGHT_COORDS = {0.41796875, 0.51171875, 0.5546875, 0.77734375}
local BATTLEPETTABSFLYOUT_ONESLOT_LEFTWIDTH = 25
local BATTLEPETTABSFLYOUT_ONESLOT_RIGHTWIDTH = 24

local BATTLEPETTABSFLYOUT_ONEROW_LEFT_COORDS = {0, 0.16796875, 0.5546875, 0.77734375}
local BATTLEPETTABSFLYOUT_ONEROW_CENTER_COORDS = {0.16796875, 0.328125, 0.5546875, 0.77734375}
local BATTLEPETTABSFLYOUT_ONEROW_RIGHT_COORDS = {0.328125, 0.51171875, 0.5546875, 0.77734375}
local BATTLEPETTABSFLYOUT_ONEROW_LEFT_WIDTH = 43
local BATTLEPETTABSFLYOUT_ONEROW_CENTER_WIDTH = 41
local BATTLEPETTABSFLYOUT_ONEROW_RIGHT_WIDTH = 47
local BATTLEPETTABSFLYOUT_ONEROW_HEIGHT = 54

local BATTLEPETTABSFLYOUT_MULTIROW_TOP_COORDS = {0, 0.8359375, 0, 0.19140625}
local BATTLEPETTABSFLYOUT_MULTIROW_MIDDLE_COORDS = {0, 0.8359375, 0.19140625, 0.35546875}
local BATTLEPETTABSFLYOUT_MULTIROW_BOTTOM_COORDS = {0, 0.8359375, 0.35546875, 0.546875}
local BATTLEPETTABSFLYOUT_MULTIROW_TOP_HEIGHT = 49
local BATTLEPETTABSFLYOUT_MULTIROW_MIDDLE_HEIGHT = 42
local BATTLEPETTABSFLYOUT_MULTIROW_BOTTOM_HEIGHT = 49
local BATTLEPETTABSFLYOUT_MULTIROW_WIDTH = 214

local table_clone
function table_clone(t) -- local
	if type(t) == "table" then
		local c = {}
		for k, v in pairs(t) do
			c[k] = table_clone(v)
		end
		return c
	end
	return t
end

local function CreateSnapshot()
	local clone = table_clone(BattlePetTabsDB2)
	local cloneIcon = type(clone) == "table" and type(clone[1]) == "table" and clone[1].icon
	local newIndex = #BattlePetTabsSnapshotDB.db + 1
	table.insert(BattlePetTabsSnapshotDB.db, {
		index = newIndex,
		created = time(),
		name = "Snapshot " .. newIndex,
		icon = cloneIcon or "Interface\\Icons\\INV_Misc_QuestionMark.blp",
		db = clone,
	})
	BattlePetTabsSnapshotDB.currentId = newIndex
end

local function GetSnapshotIndex(index)
	index = tonumber(index) or 0
	index = index > 0 and index <= #BattlePetTabsSnapshotDB.db and index or 0
	return index
end

local function LoadSnapshot(index)
	index = GetSnapshotIndex(index)
	if index > 0 then
		local snapshot = BattlePetTabsSnapshotDB.db[index]
		local clone = table_clone(snapshot.db)
		table.wipe(BattlePetTabsDB2)
		BattlePetTabsDB2 = clone
		BattlePetTabsSnapshotDB.currentId = index
	end
end

local function ApplySnapshotRename(index, newName) -- deprecated/obscolete
	index = GetSnapshotIndex(index)
	if index > 0 and type(newName) == "string" and strlen(newName) > 0 then
		BattlePetTabsSnapshotDB.db[index].name = newName
		if BattlePetTabFlyoutFrame:IsVisible() then
			--BattlePetTabFlyoutPopupFrame.skipHide = 1
			BattlePetTabFlyoutFrame:Hide()
			BattlePetTabFlyoutFrame:Show()
		end
	end
end

local function ApplySnapshotDelete(index)
	index = GetSnapshotIndex(index)
	if index > 0 then
		local temp = {}
		for k, v in pairs(BattlePetTabsSnapshotDB.db) do
			if k ~= index then
				table.insert(temp, v)
			end
		end
		table.wipe(BattlePetTabsSnapshotDB.db)
		BattlePetTabsSnapshotDB.db = temp
		if not BattlePetTabsSnapshotDB.db[index] then
			BattlePetTabsSnapshotDB.currentId = BattlePetTabsSnapshotDB.currentId - 1
			if BattlePetTabsSnapshotDB.currentId < 1 then
				BattlePetTabsSnapshotDB.currentId = 1
			end
		end
		if BattlePetTabFlyoutFrame:IsVisible() then
			--BattlePetTabFlyoutPopupFrame.skipHide = 1
			BattlePetTabFlyoutFrame:Hide()
			BattlePetTabFlyoutFrame:Show()
		end
	end
end

local function SnapshotIntegrityCheck()
	if type(BattlePetTabsSnapshotDB) ~= "table" then
		BattlePetTabsSnapshotDB = {}
	end
	if type(BattlePetTabsSnapshotDB.db) ~= "table" then
		BattlePetTabsSnapshotDB.db = {}
	end
	if type(BattlePetTabsSnapshotDB.currentId) ~= "number" then
		BattlePetTabsSnapshotDB.currentId = 1
	end
end

local function BattlePetTabFlyout_DisplayButton(button, managerButton, snapshot)
	button.snapshot = snapshot
	snapshot = snapshot or {}
	button.newSnapshot = snapshot.newSnapshot
	button.tooltip = snapshot.name
	SetItemButtonTexture(button, snapshot.icon)
	SetItemButtonCount(button, 0)
	local locked = button.newSnapshot and GetNumTeams() < 1
	if locked then
		--SetItemButtonTextureVertexColor(button, .9, 0, 0)
		--SetItemButtonNormalTextureVertexColor(button, .9, 0, 0)
		button:SetEnabled(false)
		button.icon:SetDesaturated(true)
	else
		--SetItemButtonTextureVertexColor(button, 1, 1, 1)
		--SetItemButtonNormalTextureVertexColor(button, 1, 1, 1)
		button:SetEnabled(true)
		button.icon:SetDesaturated(false)
	end
	--if not button.newSnapshot and BattlePetTabsSnapshotDB.currentId == button:GetID() then
	--	button:LockHighlight()
	--else
	--	button:UnlockHighlight()
	--end
	button.UpdateTooltip = function(self)
		--GameTooltip:SetOwner(BattlePetTabFlyoutFrame.buttonFrame, "ANCHOR_RIGHT", 6, -BattlePetTabFlyoutFrame.buttonFrame:GetHeight() - 6)
		if self.tooltip or self.tooltip2 then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:ClearLines()
			if type(self.tooltip2 or self.tooltip) == "table" then
				for _, line in ipairs(self.tooltip2 or self.tooltip) do
					GameTooltip:AddLine(line)
				end
			else
				GameTooltip:AddLine(self.tooltip2 or self.tooltip)
			end
			if not self.tooltip2 and not self.newSnapshot then
				GameTooltip:AddLine("|cff999999Right-click to delete.|r")
				GameTooltip:AddLine("|cff999999Right-click with modifier to edit.|r")
			end
			GameTooltip:Show()
		end
	end
	if button:IsMouseOver() then
		button:UpdateTooltip()
	end
end

function BattlePetTabFlyout_CreateButton()
	local buttons = BattlePetTabFlyoutFrame.buttons
	local buttonAnchor = BattlePetTabFlyoutFrame.buttonFrame
	local numButtons = #buttons
	local button = CreateFrame("Button", "BattlePetTabFlyoutFrameButton" .. numButtons + 1, buttonAnchor, "BattlePetTabFlyoutButtonTemplate")
	local pos = numButtons/BATTLEPETTABSFLYOUT_ITEMS_PER_ROW
	if pos == math.floor(pos) then
		button:SetPoint("TOPLEFT", buttonAnchor, "TOPLEFT", BATTLEPETTABSFLYOUT_BORDERWIDTH, -BATTLEPETTABSFLYOUT_BORDERWIDTH - (BATTLEPETTABSFLYOUT_ITEM_HEIGHT - BATTLEPETTABSFLYOUT_ITEM_YOFFSET)*pos)
	else
		button:SetPoint("TOPLEFT", buttons[numButtons], "TOPRIGHT", BATTLEPETTABSFLYOUT_ITEM_XOFFSET, 0);
	end
	table.insert(buttons, button)
	return button
end

function BattlePetTabFlyout_CreateBackground(buttonAnchor)
	local numBGs = buttonAnchor.numBGs
	numBGs = numBGs + 1
	local texture = buttonAnchor:CreateTexture(nil, nil, "BattlePetTabFlyoutTexture")
	buttonAnchor["bg" .. numBGs] = texture
	buttonAnchor.numBGs = numBGs
	return texture
end

function BattlePetTabFlyout_OnClick(button, mouseButton)
	local snapshot = button.snapshot
	if not snapshot then
		return
	end
	if mouseButton == "LeftButton" then
		if snapshot.newSnapshot then
			CreateSnapshot()
			BattlePetTabFlyoutFrame:Show() -- make sure it stays open after the click
		else
			LoadSnapshot(button:GetID())
			LoadTeam() -- refresh the loadout team
		end
		if BattlePetTabFlyoutFrame:IsVisible() then
			BattlePetTabFlyoutPopupFrame.skipHide = 1
			BattlePetTabFlyoutFrame:Hide()
			BattlePetTabFlyoutFrame:Show()
		end
	elseif mouseButton == "RightButton" and not snapshot.newSnapshot then
		if IsModifiedClick() then
			BattlePetTabFlyoutPopupFrame:Hide()
			BattlePetTabFlyoutPopupFrame.button = button
			BattlePetTabFlyoutPopupFrame:Show()
		else
			StaticPopup_Show("BATTLETABS_SNAPSHOT_DELETE", snapshot.name, nil, button:GetID())
		end
	end
	Update()
end

function BattlePetTabFlyout_OnShow(self)
	SnapshotIntegrityCheck()
	self:SetScale(.935) -- weaked scale for uniform button size

	local managerButton = self.managerButton
	local buttons = self.buttons
	local buttonAnchor = self.buttonFrame

	table.wipe(self.snapshots)
	for i, snapshot in ipairs(BattlePetTabsSnapshotDB.db) do
		table.insert(self.snapshots, snapshot)
	end
	table.sort(self.snapshots, function(a, b) return a.created < b.created end)

	local numSnapshots = #self.snapshots
	for i = BATTLEPETTABSFLYOUT_MAXITEMS + 1, numSnapshots do
		self.snapshots[i] = nil
	end
	table.insert(self.snapshots, {
		created = time() + 1,
		name = "New Snapshot",
		icon = "Interface\\GuildBankFrame\\UI-GuildBankFrame-NewTab.blp",
		newSnapshot = 1,
	})
	numSnapshots = math.min(#self.snapshots, BATTLEPETTABSFLYOUT_MAXITEMS)

	while #buttons < numSnapshots do
		BattlePetTabFlyout_CreateButton()
	end

	if numSnapshots == 0 then
		self:Hide()
		return
	end

	for i, button in ipairs(buttons) do
		if i <= numSnapshots then
			button:SetID(i)
			BattlePetTabFlyout_DisplayButton(button, managerButton, self.snapshots[i])
			button:Show()
		else
			button:Hide()
		end
	end

	self:SetParent(BattlePetTabsTabManager)
	self:SetFrameStrata("HIGH")
	self:ClearAllPoints()
	self:SetFrameLevel(managerButton:GetFrameLevel() - 1)
	self:SetPoint("TOPLEFT", managerButton, "TOPLEFT", -BATTLEPETTABSFLYOUT_BORDERWIDTH, BATTLEPETTABSFLYOUT_BORDERWIDTH)

	local horizontalItems = math.min(numSnapshots, BATTLEPETTABSFLYOUT_ITEMS_PER_ROW)
	local relativeAnchor = managerButton and managerButton.popoutButton or managerButton
	buttonAnchor:SetPoint("TOPLEFT", relativeAnchor, "TOPRIGHT", 12, 2)
	buttonAnchor:SetWidth((horizontalItems * BATTLEPETTABSFLYOUT_ITEM_WIDTH) + ((horizontalItems - 1) * BATTLEPETTABSFLYOUT_ITEM_XOFFSET) + BATTLEPETTABSFLYOUT_BORDERWIDTH)
	buttonAnchor:SetHeight(BATTLEPETTABSFLYOUT_HEIGHT + (math.floor((numSnapshots - 1)/BATTLEPETTABSFLYOUT_ITEMS_PER_ROW) * (BATTLEPETTABSFLYOUT_ITEM_HEIGHT - BATTLEPETTABSFLYOUT_ITEM_YOFFSET)))

	if self.numSnapshots ~= numSnapshots then
		local texturesUsed = 0
		if numSnapshots == 1 then
			local bgTex, lastBGTex
			bgTex = buttonAnchor.bg1
			bgTex:ClearAllPoints()
			bgTex:SetTexCoord(unpack(BATTLEPETTABSFLYOUT_ONESLOT_LEFT_COORDS))
			bgTex:SetWidth(BATTLEPETTABSFLYOUT_ONESLOT_LEFTWIDTH)
			bgTex:SetHeight(BATTLEPETTABSFLYOUT_ONEROW_HEIGHT)
			bgTex:SetPoint("TOPLEFT", -5, 4)
			bgTex:Show()
			texturesUsed = texturesUsed + 1
			lastBGTex = bgTex

			bgTex = buttonAnchor.bg2 or BattlePetTabFlyout_CreateBackground(buttonAnchor)
			bgTex:ClearAllPoints()
			bgTex:SetTexCoord(unpack(BATTLEPETTABSFLYOUT_ONESLOT_RIGHT_COORDS))
			bgTex:SetWidth(BATTLEPETTABSFLYOUT_ONESLOT_RIGHTWIDTH)
			bgTex:SetHeight(BATTLEPETTABSFLYOUT_ONEROW_HEIGHT)
			bgTex:SetPoint("TOPLEFT", lastBGTex, "TOPRIGHT")
			bgTex:Show()
			texturesUsed = texturesUsed + 1
			lastBGTex = bgTex

		elseif numSnapshots <= BATTLEPETTABSFLYOUT_ITEMS_PER_ROW then
			local bgTex, lastBGTex
			bgTex = buttonAnchor.bg1
			bgTex:ClearAllPoints()
			bgTex:SetTexCoord(unpack(BATTLEPETTABSFLYOUT_ONEROW_LEFT_COORDS))
			bgTex:SetWidth(BATTLEPETTABSFLYOUT_ONEROW_LEFT_WIDTH)
			bgTex:SetHeight(BATTLEPETTABSFLYOUT_ONEROW_HEIGHT)
			bgTex:SetPoint("TOPLEFT", -5, 4)
			bgTex:Show()
			texturesUsed = texturesUsed + 1
			lastBGTex = bgTex
			for i = texturesUsed + 1, numSnapshots - 1 do
				bgTex = buttonAnchor["bg"..i] or BattlePetTabFlyout_CreateBackground(buttonAnchor)
				bgTex:ClearAllPoints()
				bgTex:SetTexCoord(unpack(BATTLEPETTABSFLYOUT_ONEROW_CENTER_COORDS))
				bgTex:SetWidth(BATTLEPETTABSFLYOUT_ONEROW_CENTER_WIDTH)
				bgTex:SetHeight(BATTLEPETTABSFLYOUT_ONEROW_HEIGHT)
				bgTex:SetPoint("TOPLEFT", lastBGTex, "TOPRIGHT")
				bgTex:Show()
				texturesUsed = texturesUsed + 1
				lastBGTex = bgTex
			end

			bgTex = buttonAnchor["bg"..numSnapshots] or BattlePetTabFlyout_CreateBackground(buttonAnchor)
			bgTex:ClearAllPoints()
			bgTex:SetTexCoord(unpack(BATTLEPETTABSFLYOUT_ONEROW_RIGHT_COORDS))
			bgTex:SetWidth(BATTLEPETTABSFLYOUT_ONEROW_RIGHT_WIDTH)
			bgTex:SetHeight(BATTLEPETTABSFLYOUT_ONEROW_HEIGHT)
			bgTex:SetPoint("TOPLEFT", lastBGTex, "TOPRIGHT")
			bgTex:Show()
			texturesUsed = texturesUsed + 1

		elseif numSnapshots > BATTLEPETTABSFLYOUT_ITEMS_PER_ROW then
			local numRows = math.ceil(numSnapshots/BATTLEPETTABSFLYOUT_ITEMS_PER_ROW)
			local bgTex, lastBGTex
			bgTex = buttonAnchor.bg1
			bgTex:ClearAllPoints()
			bgTex:SetTexCoord(unpack(BATTLEPETTABSFLYOUT_MULTIROW_TOP_COORDS))
			bgTex:SetWidth(BATTLEPETTABSFLYOUT_MULTIROW_WIDTH)
			bgTex:SetHeight(BATTLEPETTABSFLYOUT_MULTIROW_TOP_HEIGHT)
			bgTex:SetPoint("TOPLEFT", -5, 4)
			bgTex:Show()
			texturesUsed = texturesUsed + 1
			lastBGTex = bgTex
			for i = 2, numRows - 1 do -- Middle rows
				bgTex = buttonAnchor["bg"..i] or BattlePetTabFlyout_CreateBackground(buttonAnchor)
				bgTex:ClearAllPoints()
				bgTex:SetTexCoord(unpack(BATTLEPETTABSFLYOUT_MULTIROW_MIDDLE_COORDS))
				bgTex:SetWidth(BATTLEPETTABSFLYOUT_MULTIROW_WIDTH)
				bgTex:SetHeight(BATTLEPETTABSFLYOUT_MULTIROW_MIDDLE_HEIGHT)
				bgTex:SetPoint("TOPLEFT", lastBGTex, "BOTTOMLEFT")
				bgTex:Show()
				texturesUsed = texturesUsed + 1
				lastBGTex = bgTex
			end

			bgTex = buttonAnchor["bg"..numRows] or BattlePetTabFlyout_CreateBackground(buttonAnchor)
			bgTex:ClearAllPoints()
			bgTex:SetTexCoord(unpack(BATTLEPETTABSFLYOUT_MULTIROW_BOTTOM_COORDS))
			bgTex:SetWidth(BATTLEPETTABSFLYOUT_MULTIROW_WIDTH)
			bgTex:SetHeight(BATTLEPETTABSFLYOUT_MULTIROW_BOTTOM_HEIGHT)
			bgTex:SetPoint("TOPLEFT", lastBGTex, "BOTTOMLEFT")
			bgTex:Show()
			texturesUsed = texturesUsed + 1
			lastBGTex = bgTex
		end

		for i = texturesUsed + 1, buttonAnchor.numBGs do
			buttonAnchor["bg" .. i]:Hide()
		end

		self.numSnapshots = numSnapshots
	end
end

function Initialize() -- local
	Initialize = function() end

	-- conversion between old and new structure
	-- [[
	do
		if type(BattlePetTabsDB) == "table" then
			for index = 1, numTabs do
				local team = BattlePetTabsDB[index]
				if type(team) == "table" then
					local newTeam = {}
					local emptyPets = 0
					if type(team.name) == "string" then
						newTeam.name = team.name
					else
						newTeam.name = "Team " .. index
					end
					newTeam.setup = {}
					if type(team.team) == "table" then
						for i = 1, MAX_ACTIVE_PETS do
							local petId = team.team[i]
							if ValidatePetId(petId, 1) then
								newTeam.setup[i] = {petId, 0, 0, 0}
							else
								newTeam.setup[i] = {EMPTY_PET_DYNAMIC, 0, 0, 0}
								emptyPets = emptyPets + 1
							end
						end
						if type(team.team2) == "table" then
							for i = 1, MAX_ACTIVE_PETS do
								if type(team.team2[i]) == "table" then
									for j = 1, MAX_ACTIVE_ABILITIES do
										newTeam.setup[i][1 + j] = tonumber(team.team2[i][j]) or 0
									end
								end
							end
						end
					else
						for i = 1, MAX_ACTIVE_PETS do
							newTeam.setup[i] = {EMPTY_PET_DYNAMIC, 0, 0, 0}
							emptyPets = emptyPets + 1
						end
					end
					if type(team.icon) == "string" then
						newTeam.icon = team.icon
					else
						for _, petData in ipairs(newTeam.setup) do
							local petId = petData[1]
							if ValidatePetId(petId, 1) then
								newTeam.icon = select(9, C_PetJournal_GetPetInfoByPetID(petId))
								if newTeam.icon then
									break
								end
							end
						end
						if not newTeam.icon then
							newTeam.icon = "Interface\\Icons\\INV_Misc_QuestionMark.blp"
						end
					end
					if emptyPets < 3 then
						BattlePetTabsDB2[index] = newTeam
					end
				end
			end
			BattlePetTabsDB2.currentId = tonumber(BattlePetTabsDB.currentId) or 1
			BattlePetTabsDB = nil
		end
	end
	-- ]]

	StaticPopupDialogs["BATTLETABS_TEAM_RENAME"] = {
		text = "What do you wish to rename |cffffd200%s|r to?",
		button1 = ACCEPT,
		button2 = CANCEL,
		hasEditBox = 1,
		maxLetters = 30,
		OnAccept = function(self)
			ApplyRename(self.data, self.editBox:GetText())
		end,
		EditBoxOnEnterPressed = function(self)
			local parent = self:GetParent()
			ApplyRename(parent.data, parent.editBox:GetText())
			parent:Hide()
		end,
		OnShow = function(self)
			self.editBox:SetFocus()
		end,
		OnHide = function(self)
			ChatEdit_FocusActiveWindow()
			self.editBox:SetText("")
		end,
		timeout = 0,
		exclusive = 1,
		hideOnEscape = 1,
	}

	StaticPopupDialogs["BATTLETABS_TEAM_DELETE"] = {
		text = "Are you sure you want to delete team |cffffd200%s|r?",
		button1 = OKAY,
		button2 = CANCEL,
		OnAccept = function(self)
			ApplyDelete(self.data)
		end,
		timeout = 0,
		exclusive = 1,
		hideOnEscape = 1,
	}

	StaticPopupDialogs["BATTLETABS_SNAPSHOT_DELETE"] = {
		text = "Are you sure you want to delete snapshot |cffffd200%s|r?",
		button1 = OKAY,
		button2 = CANCEL,
		OnAccept = function(self)
			ApplySnapshotDelete(self.data)
		end,
		timeout = 0,
		exclusive = 1,
		hideOnEscape = 1,
	}

	local tabs = CreateFrame("Frame", frameName, PetJournal)
	tabs:SetSize(42, 50)
	tabs:SetPoint("TOPLEFT", "$parent", "TOPRIGHT", -1, -17)
	tabs:HookScript("OnShow", Update)

	local tab = CreateFrame("Frame", "$parentTabManager", tabs, "BattlePetTabTemplate")
	tab:SetID(0)
	tab:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, 0)
	tab.button.checked:SetTexture(nil)
	tab.button.icon:SetTexture("Interface\\Icons\\INV_Pet_Achievement_CaptureAWildPet")
	tab.button.tooltip = "Snapshot Manager"
	tab.button.snapshotManager = 1
	tab.button:SetScript("OnDragStart", nil)
	tab.button:SetScript("OnClick", function(self)
		PlaySound("igMainMenuOptionCheckBoxOn")
		if BattlePetTabFlyoutFrame:IsVisible() then
			BattlePetTabFlyoutFrame:Hide()
		else
			BattlePetTabFlyoutFrame:Show()
		end
	end)
	tab.button:HookScript("OnHide", function(self)
		BattlePetTabFlyoutFrame:Hide()
	end)
	BattlePetTabFlyoutFrame.managerButton = tab.button

	for i = 1, numTabs do
		tabs[i] = CreateFrame("Frame", "$parentTab" .. i, tabs, "BattlePetTabTemplate")
		tabs[i]:SetID(i)
		tabs[i]:SetPoint("TOPLEFT", tab or "$parent", "BOTTOMLEFT", 0, 0)
		tab = "$parentTab" .. i
	end

	do
		local function onClick(...)
			if InCombatLockdown() then
				return
			end
			PetJournalPetLoadoutDragButton_OnClick(...)
		end

		local function onDragStart(...)
			if InCombatLockdown() then
				return
			end
			PetJournalDragButton_OnDragStart(...)
		end

		for i = 1, MAX_ACTIVE_PETS do
			local button = _G["PetJournalLoadoutPet" .. i]
			button.dragButton:SetScript("OnClick", onClick)
			button.dragButton:SetScript("OnDragStart", onDragStart)
		end
	end

	hooksecurefunc(C_PetJournal, "SetPetLoadOutInfo", UpdateTeamLoadOut)
	hooksecurefunc(C_PetJournal, "SetAbility", UpdateTeamLoadOutAbilities)
	GameTooltip:HookScript("OnShow", onGameTooltipShow)

	addon:RegisterEvent("COMPANION_UPDATE")
	addon:RegisterEvent("LFG_LOCK_INFO_RECEIVED")
	addon:RegisterEvent("LFG_UPDATE_RANDOM_INFO")
	addon:RegisterEvent("PET_BATTLE_CLOSE")
	addon:RegisterEvent("PET_BATTLE_OPENING_START")
	addon:RegisterEvent("PET_BATTLE_QUEUE_STATUS")
	addon:RegisterEvent("PLAYER_REGEN_DISABLED")
	addon:RegisterEvent("PLAYER_REGEN_ENABLED")

	addon:HookScript("OnEvent", Update)

	-- (bonus feature) allows you to modify right-click the avatar of the pets in the loadout and confirm their removal from the team (allows you to have a true 2v or 1v teams)
	-- [[
	do
		StaticPopupDialogs["BATTLETABS_REMOVE_MEMBER"] = {
			text = "Are you sure you wish to remove |cffffd200%s|r from the team?",
			button1 = ACCEPT,
			button2 = CANCEL,
			OnAccept = function(self)
				C_PetJournal_SetPetLoadOutInfo(self.data, EMPTY_PET_DYNAMIC)
				UpdateCurrentTeam()
			end,
			timeout = 0,
			exclusive = 1,
			hideOnEscape = 1,
		}

		hooksecurefunc("PetJournalPetLoadoutDragButton_OnClick", function(self, button)
			local loadout = self:GetParent()
			if button == "RightButton" and loadout.petID and IsModifiedClick() then
				local slot = loadout:GetID()
				local _, customName, _, _, _, _, _, name = C_PetJournal_GetPetInfoByPetID(C_PetJournal_GetPetLoadOutInfo(slot))
				local alone = 1
				for i = 1, MAX_ACTIVE_PETS do
					if i ~= slot and C_PetJournal_GetPetLoadOutInfo(i) then
						alone = nil
						break
					end
				end
				if not alone then
					PetJournal_HidePetDropdown()
					StaticPopup_Show("BATTLETABS_REMOVE_MEMBER", customName or name, nil, slot)
				end
			end
		end)
	end
	-- ]]

	Update()
end
