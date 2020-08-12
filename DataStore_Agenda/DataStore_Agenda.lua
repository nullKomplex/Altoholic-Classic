if not DataStore then return end

local addonName = "DataStore_Agenda"

_G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0")

local addon = _G[addonName]

local THIS_ACCOUNT = "Default"

local AddonDB_Defaults = {
	global = {
		Options = {
			WeeklyResetDay = nil,		-- weekday (0 = Sunday, 6 = Saturday)
			WeeklyResetHour = nil,		-- 0 to 23
			NextWeeklyReset = nil,
		},
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"]
				lastUpdate = nil,
				Contacts = {},
				DungeonIDs = {},		-- raid timers
                DungeonBosses = {},     -- raid timers for individual bosses
								
				Notes = {},
				Tasks = {},
				Mail = {},			-- This is for intenal mail only, unrelated to wow's
			}
		}
	}
}

-- *** Utility functions ***
local function GetOption(option)
	return addon.db.global.Options[option]
end

local function SetOption(option, value)
	addon.db.global.Options[option] = value
end

-- *** Scanning functions ***
local function ScanContacts()
	local contacts = addon.ThisCharacter.Contacts

	local oldValues = {}

	-- if a known contact disconnected, preserve the info we know about him
	for name, info in pairs(contacts) do
		if type(info) == "table" then		-- contacts were only saved as strings in earlier versions,  make sure they're not taken into account
			if info.level then
				oldValues[name] = {}
				oldValues[name].level = info.level
				oldValues[name].class = info.class
			end
		end
	end

	wipe(contacts)

	for i = 1, C_FriendList.GetNumFriends() do	-- only friends, not real id, as they're always visible
	    local info = C_FriendList.GetFriendInfo(i)
        if info then
            local name, level, class, zone, isOnline, note = info.name, info.level, info.className, info.area, info.connected, info.notes 
    
    		if name then
    			contacts[name] = contacts[name] or {}
    			contacts[name].note = note
    
    			if isOnline then	-- level, class, zone will be ok
    				contacts[name].level = level
    				contacts[name].class = class
    			elseif oldValues[name] then	-- did we save information earlier about this contact ?
    				contacts[name].level = oldValues[name].level
    				contacts[name].class = oldValues[name].class
    			end
    		end
        end
	end

	addon.ThisCharacter.lastUpdate = time()
end

local function ScanDungeonIDs()
	local dungeons = addon.ThisCharacter.DungeonIDs
    local dungeonBosses = addon.ThisCharacter.DungeonBosses
	wipe(dungeons)
    wipe(dungeonBosses)

	for i = 1, GetNumSavedInstances() do
		local instanceName, instanceID, instanceReset, difficulty, _, extended, _, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress, extendDisabled = GetSavedInstanceInfo(i)

		if difficulty > 1 then
			instanceName = format("%s %s", instanceName, difficultyName)
		end

		local key = instanceName.. "|" .. instanceID
		dungeons[key] = format("%s|%s|%s|%s", instanceReset, time(), numEncounters, encounterProgress )
          
        -- track all the bosses killed / left alive
        dungeonBosses[key] = {}
        for j = 1, numEncounters do
            local bossName, _, isKilled = GetSavedInstanceEncounterInfo(i, j)
            dungeonBosses[key][bossName] = isKilled
        end
	end
end

-- *** Event Handlers ***
local function OnPlayerAlive()
	ScanContacts()
	ScanDungeonIDs()
end

local function OnFriendListUpdate()
	ScanContacts()
end

local function OnUpdateInstanceInfo()
	ScanDungeonIDs()
end

local pendingBossKillScan = false
local function OnBossKill()
    if not pendingBossKillScan then
        pendingBossKillScan = true
        C_Timer.After(5, function()
            pendingBossKillScan = false
            RequestRaidInfo()
        end)
    end
end

local function OnRaidInstanceWelcome()
	RequestRaidInfo()
end

local function OnChatMsgSystem(event, arg)
	if arg then
		if tostring(arg) == INSTANCE_SAVED then
			RequestRaidInfo()
		end
	end
end

-- * Contacts *
local function _GetContactInfo(character, key)
	local contact = character.Contacts[key]
	if type(contact) == "table" then
		return contact.level, contact.class, contact.note
	end
end

-- * Dungeon IDs *
local function _GetSavedInstances(character)
	return character.DungeonIDs

	--[[	Typical usage:

		for dungeonKey, _ in pairs(DataStore:GetSavedInstances(character) do
			myvar1, myvar2, .. = DataStore:GetSavedInstanceInfo(character, dungeonKey)
		end
	--]]
end

local function _GetSavedInstanceInfo(character, key)
	local instanceInfo = character.DungeonIDs[key]
	if not instanceInfo then return end

	local hasExpired
	local reset, lastCheck, isExtended, isRaid, numEncounters, encounterProgress = strsplit("|", instanceInfo)

	return tonumber(reset), tonumber(lastCheck), numEncounters or 0, encounterProgress or 0, character.DungeonBosses[key]
end

local function _HasSavedInstanceExpired(character, key)
	local reset, lastCheck = _GetSavedInstanceInfo(character, key)
	if not reset or not lastCheck then return end

	local hasExpired
	local expiresIn = reset - (time() - lastCheck)

	if expiresIn <= 0 then	-- has expired
		hasExpired = true
	end

	return hasExpired, expiresIn
end

local function _DeleteSavedInstance(character, key)
	character.DungeonIDs[key] = nil
end

local PublicMethods = {
	GetContactInfo = _GetContactInfo,

	GetSavedInstances = _GetSavedInstances,
	GetSavedInstanceInfo = _GetSavedInstanceInfo,
	HasSavedInstanceExpired = _HasSavedInstanceExpired,
	DeleteSavedInstance = _DeleteSavedInstance,
}

function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New(addonName .. "DB", AddonDB_Defaults)

	DataStore:RegisterModule(addonName, addon, PublicMethods)
    
	DataStore:SetCharacterBasedMethod("GetContactInfo")

	DataStore:SetCharacterBasedMethod("GetSavedInstances")
	DataStore:SetCharacterBasedMethod("GetSavedInstanceInfo")
	DataStore:SetCharacterBasedMethod("HasSavedInstanceExpired")
	DataStore:SetCharacterBasedMethod("DeleteSavedInstance")
end

function addon:OnEnable()
	-- Contacts
	addon:RegisterEvent("PLAYER_ALIVE", OnPlayerAlive)
	addon:RegisterEvent("FRIENDLIST_UPDATE", OnFriendListUpdate)

	-- Dungeon IDs
	addon:RegisterEvent("UPDATE_INSTANCE_INFO", OnUpdateInstanceInfo)
    addon:RegisterEvent("BOSS_KILL", OnBossKill)
	addon:RegisterEvent("RAID_INSTANCE_WELCOME", OnRaidInstanceWelcome)
		
	addon:RegisterEvent("CHAT_MSG_SYSTEM", OnChatMsgSystem)
end

function addon:OnDisable()
	addon:UnregisterEvent("PLAYER_ALIVE")
	addon:UnregisterEvent("FRIENDLIST_UPDATE")
	addon:UnregisterEvent("UPDATE_INSTANCE_INFO")
    addon:UnregisterEvent("BOSS_KILL")
	addon:UnregisterEvent("RAID_INSTANCE_WELCOME")
	addon:UnregisterEvent("CHAT_MSG_SYSTEM")
end
