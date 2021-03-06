local addonName = ...
local addon = _G[addonName]
local colors = addon.Colors

if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
    return
end

local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local THIS_ACCOUNT = "Default"
local THIS_REALM = GetRealmName()

local storedLink = nil

-- Bugfix: make the game cache store this item on load, so we don't get a nil error if the recipe is moused over later on
GetItemInfo(4401)

local GatheringNodes = {			-- Add herb/ore possession info to Plants/Mines, thanks to Tempus on wowace for gathering this.

	-- Mining nodes
	-- Classic
	[L["Copper Vein"]]                     =  2770, -- Copper Ore
	[L["Dark Iron Deposit"]]               = 11370, -- Dark Iron Ore
	[L["Gold Vein"]]                       =  2776, -- Gold Ore
	[L["Hakkari Thorium Vein"]]            = 10620, -- Thorium Ore
	[L["Iron Deposit"]]                    =  2772, -- Iron Ore
	[L["Mithril Deposit"]]                 =  3858, -- Mithril Ore
	[L["Ooze Covered Gold Vein"]]          =  2776, -- Gold Ore
	[L["Ooze Covered Mithril Deposit"]]    =  3858, -- Mithril Ore
	[L["Ooze Covered Rich Thorium Vein"]]  = 10620, -- Thorium Ore
	[L["Ooze Covered Silver Vein"]]        =  2775, -- Silver Ore
	[L["Ooze Covered Thorium Vein"]]       = 10620, -- Thorium Ore
	[L["Ooze Covered Truesilver Deposit"]] =  7911, -- Truesilver Ore
	[L["Rich Thorium Vein"]]               = 10620, -- Thorium Ore
	[L["Silver Vein"]]                     =  2775, -- Silver Ore
	[L["Small Thorium Vein"]]              = 10620, -- Thorium Ore
	[L["Tin Vein"]]                        =  2771, -- Tin Ore
	[L["Truesilver Deposit"]]              =  7911, -- Truesilver Ore

	[L["Lesser Bloodstone Deposit"]]       =  4278, -- Lesser Bloodstone Ore
	[L["Incendicite Mineral Vein"]]        =  3340, -- Incendicite Ore
	[L["Indurium Mineral Vein"]]           =  5833, -- Indurium Ore
	[L["Large Obsidian Chunk"]]            = 22203, -- Large Obsidian Shard. Both drop on both nodes.
	[L["Small Obsidian Chunk"]]            = 22202, -- Small Obsidian Shard. Both drop on both nodes.
	
	-- Herbs
	-- Classic
	[L["Arthas' Tears"]]        =  8836,
	[L["Black Lotus"]]          = 13468,
	[L["Blindweed"]]            =  8839,
	[L["Bloodthistle"]]         = 22710,
	[L["Briarthorn"]]           =  2450,
	[L["Bruiseweed"]]           =  2453,
	[L["Dreamfoil"]]            = 13463,
	[L["Earthroot"]]            =  2449,
	[L["Fadeleaf"]]             =  3818,
	[L["Firebloom"]]            =  4625,
	[L["Ghost Mushroom"]]       =  8845,
	[L["Golden Sansam"]]        = 13464,
	[L["Goldthorn"]]            =  3821,
	[L["Grave Moss"]]           =  3369,
	[L["Gromsblood"]]           =  8846,
	[L["Icecap"]]               = 13467,
	[L["Khadgar's Whisker"]]    =  3358,
	[L["Kingsblood"]]           =  3356,
	[L["Liferoot"]]             =  3357,
	[L["Mageroyal"]]            =   785,
	[L["Mountain Silversage"]]  = 13465,
	[L["Peacebloom"]]           =  2447,
	[L["Plaguebloom"]]          = 13466,
	[L["Purple Lotus"]]         =  8831,
	[L["Silverleaf"]]           =   765,
	[L["Stranglekelp"]]         =  3820,
	[L["Sungrass"]]             =  8838,
	[L["Wild Steelbloom"]]      =  3355,
	[L["Wintersbite"]]          =  3819,	
}

-- *** Utility functions ***
local function IsGatheringNode(name)
	if name then
		for k, v in pairs(GatheringNodes) do
			if string.find(name, k) then				-- returns the itemID if "name" is a known type of gathering node (mines & herbs)
				return v
			end
		end
	end
end

local function GetCraftNameFromRecipeLink(link)
	-- get the craft name from the itemlink (strsplit on | to get the 4th value, then split again on ":" )
	local recipeName = select(4, strsplit("|", link))
	local craftName

	-- try to determine if it's a transmute (has 2 colons in the string --> Alchemy: Transmute: blablabla)
	local pos = string.find(recipeName, L["Transmute"])
	if pos then	-- it's a transmute
		return string.sub(recipeName, pos, -2)
	else
		craftName = select(2, strsplit(":", recipeName))
	end
	
	if craftName == nil then		-- will be nil for enchants
		return string.sub(recipeName, 3, -2)		-- ex: "Enchant Weapon - Striking"
	end
	
	return string.sub(craftName, 2, -2)	-- at this point, get rid of the leading space and trailing square bracket
end

local isTooltipDone, isNodeDone			-- for informant
local cachedItemID, cachedCount, cachedTotal, cachedSource
local cachedRecipeOwners

local itemCounts = {}
local itemCountsLabels = {	L["Bags"], L["Bank"], L["AH"], L["Equipped"], L["Mail"] }
local counterLines = {}		-- list of lines containing a counter to display in the tooltip

local function AddCounterLine(owner, counters)
	table.insert(counterLines, { ["owner"] = owner, ["info"] = counters } )
end

local function WriteCounterLines(tooltip)
	if #counterLines == 0 then return end

	if addon:GetOption("UI.Tooltip.ShowItemCount") then			-- add count per character/guild
		tooltip:AddLine(" ",1,1,1);
		for _, line in ipairs (counterLines) do
			tooltip:AddDoubleLine(line.owner,  colors.teal .. line.info);
		end
	end
end

local function WriteTotal(tooltip)
	if addon:GetOption("UI.Tooltip.ShowTotalItemCount") and cachedTotal then
		tooltip:AddLine(cachedTotal,1,1,1);
	end
end

local function GetRealmsList()
	-- returns the list of realms to check, either only this realm, or merged realms too.
	local realms = {}
	table.insert(realms, THIS_REALM)
	
	if addon:GetOption("UI.Tooltip.ShowMergedRealmsCount") then
		for _, connectedRealm in pairs(DataStore:GetRealmsConnectedWith(THIS_REALM)) do
			table.insert(realms, connectedRealm)
		end
	end
	
	return realms
end

local function GetCharacterItemCount(character, searchedID)
	itemCounts[1], itemCounts[2] = DataStore:GetContainerItemCount(character, searchedID)
	itemCounts[3] = DataStore:GetAuctionHouseItemCount(character, searchedID)
	itemCounts[4] = DataStore:GetInventoryItemCount(character, searchedID)
	itemCounts[5] = DataStore:GetMailItemCount(character, searchedID)
	
	local charCount = 0
	for _, v in pairs(itemCounts) do
		charCount = charCount + v
	end
	
	if charCount > 0 then
		local account, realm, char = strsplit(".", character)
		local name = DataStore:GetColoredCharacterName(character) or char		-- if for any reason this char isn't in DS_Characters.. use the name part of the key
		
		local isOtherAccount = (account ~= THIS_ACCOUNT)
		local isOtherRealm = (realm ~= THIS_REALM)
		
		if isOtherAccount and isOtherRealm then		-- other account AND other realm
			name = format("%s%s (%s / %s)", name, colors.yellow, account, realm)
		elseif isOtherAccount then							-- only other account
			name = format("%s%s (%s)", name, colors.yellow, account)
		elseif isOtherRealm then							-- only other realm
			name = format("%s%s (%s)", name, colors.yellow, realm)
		end
		
		local t = {}

		for k, v in pairs(itemCounts) do
			if v > 0 then	-- if there are more than 0 items in this container
				table.insert(t, colors.white .. itemCountsLabels[k] .. ": "  .. colors.teal .. v)
			end
		end

		if addon:GetOption("UI.Tooltip.ShowSimpleCount") then
			AddCounterLine(name, format("%s%s", colors.orange, charCount))
		else
			-- charInfo should look like 	(Bags: 4, Bank: 8, Equipped: 1, Mail: 7), table concat takes care of this
			AddCounterLine(name, format("%s%s%s (%s%s)", colors.orange, charCount, colors.white, table.concat(t, colors.white..", "), colors.white))
		end
	end
	
	return charCount
end

local function GetAccountItemCount(account, searchedID)
	local count = 0

	for _, realm in pairs(GetRealmsList()) do
        -- sort the characters in alphabetical order
        local characters = DataStore:GetCharacters(realm, account)
        local characterKeys = {}
        for characterKey in pairs(characters) do
            table.insert(characterKeys, characterKey)
        end
        table.sort(characterKeys)
		for _, characterKey in ipairs(characterKeys) do
            local character = characters[characterKey]
			if addon:GetOption("UI.Tooltip.ShowCrossFactionCount") then
				count = count + GetCharacterItemCount(character, searchedID)
			else
				if	DataStore:GetCharacterFaction(character) == UnitFactionGroup("player") then
					count = count + GetCharacterItemCount(character, searchedID)
				end
			end
		end
	end
	return count
end

local function GetItemCount(searchedID)
	-- Return the total amount of times an item is present on this realm, and prepares the counterLines table for later display by the tooltip
	wipe(counterLines)

	local count = 0
	if addon:GetOption("UI.Tooltip.ShowAllAccountsCount") and not addon.Comm.Sharing.SharingInProgress then
		for account in pairs(DataStore:GetAccounts()) do
			count = count + GetAccountItemCount(account, searchedID)
		end
	else
		count = GetAccountItemCount(THIS_ACCOUNT, searchedID)
	end

	return count
end

function addon:GetRecipeOwners(professionName, link, recipeLevel)
	local craftName = GetCraftNameFromRecipeLink(link)
	if not craftName then return end		-- still nothing usable ? then exit
	   
	local know = {}				-- list of alts who know this recipe
	local couldLearn = {}		-- list of alts who could learn it
	local willLearn = {}			-- list of alts who will be able to learn it later

	if not recipeLevel then
		-- it seems that some tooltip libraries interfere and cause a recipeLevel to be nil
		return know, couldLearn, willLearn
	end
	
	local profession, isKnownByChar
	for characterName, character in pairs(DataStore:GetCharacters()) do
		profession = DataStore:GetProfession(character, professionName)
		isKnownByChar = nil
		if profession then
            local coloredName = DataStore:GetColoredCharacterName(character)
            local currentLevel, maxLevel = DataStore:GetProfessionInfo(DataStore:GetProfession(character, professionName))
            
            -- Is the recipe Expert First Aid - Under Wraps or Expert Cookbook or the fishing book?
            local itemID = GetItemInfoInstant(link)
            if (itemID == 16084) or (itemID == 16072) or (itemID == 16083) then
                if (currentLevel > 124) and (maxLevel == 150) then
                    table.insert(couldLearn, format("%s |r(%d)", coloredName, currentLevel))
                elseif (currentLevel < 125) then
                    table.insert(willLearn, format("%s |r(%d)", coloredName, currentLevel))
                else
                    table.insert(know, coloredName)
                end
    		else
                -- Special case for Mechanical Squirrel: get the name of the item it creates instead
                if (itemID == 4408) then
                    craftName = GetItemInfo(4401)
                    if not craftName then craftName = "" end
                end
                
                -- Transmutes need to search for the item created
                local transmuteRecipeIDs = {[9305] = 6037, [12958] = 12360, [13486] = 7080, [13485] = 7082, [20761] = 7068, [13484] = 7080, [13489] = 12803, [13483] = 7076, [13488] = 7076, [13482] = 7078, [13487] = 12808, [9304] = 3577}
                for recipeID, craftedItemID in pairs(transmuteRecipeIDs) do
                    if (itemID == recipeID) then
                        craftName = GetItemInfo(craftedItemID)
                        if not craftName then craftName = "" end
                    end
                end 

                -- is the game in French and the recipe an Enchanting recipe?
                -- if so, change "Enchantement" to "Ench."
                if (GetLocale() == "frFR") and (string.find(craftName, "Enchantement")) and (not string.find(craftName, "Grand sac d'enchantement")) then
                    craftName = craftName:gsub("Enchantement", "Ench.")
                    -- Also, for some reason the recipe demonslaying says "démon" while the spellbook says "démons"
                    if itemID == 11208 then
                        craftName = "Ench. d'arme (Tueur de démons)"
                    end
                end
            
            	DataStore:IterateRecipes(profession, 0, 0, function(recipeData)
    				local _, recipeID, isLearned = DataStore:GetRecipeInfo(recipeData)
    				local skillName = DataStore:GetResultItemName(recipeID)
                    
                    -- is the recipe Enchant Weapon - Healing Power or Enchant Weapon - Spell Power?
                    -- These two recipes have a bug: they have an extra space between "Enchant" and "Weapon"
                    -- I don't know if this is a Classic bug or if it existed in Vanilla
                    
                    if (itemID == 18260) then
                        -- Healing power
                        skillName = skillName:gsub(" +"," ")
                    end
                    
                    if (itemID == 18259) then
                        -- Spell power
                        skillName:gsub(" +"," ")
                    end
                    
    				if (skillName) and (string.lower(skillName) == string.lower(craftName)) and isLearned then
    					isKnownByChar = true
    					return true	-- stop iteration
    				end
    			end)
    			
    			if isKnownByChar then
    				table.insert(know, coloredName)
    			else
    				if currentLevel > 0 then
    					if currentLevel < recipeLevel then
    						table.insert(willLearn, format("%s |r(%d)", coloredName, currentLevel))
    					else
    						table.insert(couldLearn, format("%s |r(%d)", coloredName, currentLevel))
    					end
    				end
    			end
            end
		end
	end
    
    local function sortStripFormatting(a, b)
        local escapes = {
            ["|c%x%x%x%x%x%x%x%x"] = "", -- color start
            ["|r"] = "", -- color end
            ["|H.-|h(.-)|h"] = "%1", -- links
            ["|T.-|t"] = "", -- textures
            ["{.-}"] = "", -- raid target icons
        }
        local function unescape(str)
            for k, v in pairs(escapes) do
                str = gsub(str, k, v)
            end
            return str
        end
        return (unescape(a) < unescape(b))
    end
    
    table.sort(know, sortStripFormatting)
    table.sort(couldLearn, sortStripFormatting)
    table.sort(willLearn, sortStripFormatting)
	return know, couldLearn, willLearn
end

local function GetRecipeOwnersText(professionName, link, recipeLevel)

	local know, couldLearn, willLearn = addon:GetRecipeOwners(professionName, link, recipeLevel)
	
	local lines = {}
	if #know > 0 then
		table.insert(lines, colors.teal .. L["Already known by "] ..": ".. colors.white.. table.concat(know, ", ") .."\n")
	end
	
	if #couldLearn > 0 then
		table.insert(lines, colors.yellow .. L["Could be learned by "] ..": ".. colors.white.. table.concat(couldLearn, ", ") .."\n")
	end
	
	if #willLearn > 0 then
		table.insert(lines, colors.red .. L["Will be learnable by "] ..": ".. colors.white.. table.concat(willLearn, ", "))
	end
	
	return table.concat(lines, "\n")
end

local gatheringNodeWasShown

local function ShowGatheringNodeCounters()
    gatheringNodeWasShown = true
	-- exit if player does not want counters for known gathering nodes
	if addon:GetOption("UI.Tooltip.ShowGatheringNodesCount") == false then return end

	local itemID = IsGatheringNode( _G["GameTooltipTextLeft1"]:GetText() )
	if not itemID or (itemID == cachedItemID) then return end					-- is the item in the tooltip a known type of gathering node ?
	
	if Informant then
		isNodeDone = true
	end

	-- check player bags to see how many times he owns this item, and where
	if addon:GetOption("UI.Tooltip.ShowItemCount") or addon:GetOption("UI.Tooltip.ShowTotalItemCount") then
		cachedCount = GetItemCount(itemID) -- if one of the 2 options is active, do the count
		cachedTotal = (cachedCount > 0) and format("%s: %s", colors.gold..L["Total owned"], colors.teal..cachedCount) or nil
	end
	
	WriteCounterLines(GameTooltip)
	WriteTotal(GameTooltip)
    return true
end

local function ProcessTooltip(tooltip, link)
	if Informant and isNodeDone then
		return
	end
	
	local itemID = addon:GetIDFromLink(link)
	if not itemID then return end
	
	if (itemID == 0) and (TradeSkillFrame ~= nil) and TradeSkillFrame:IsVisible() then
		if (GetMouseFocus():GetName()) == "TradeSkillSkillIcon" then
			itemID = tonumber(GetTradeSkillItemLink(TradeSkillFrame.selectedSkill):match("item:(%d+):")) or nil
		else
			for i = 1, 8 do
				if (GetMouseFocus():GetName()) == "TradeSkillReagent"..i then
					itemID = tonumber(GetTradeSkillReagentItemLink(TradeSkillFrame.selectedSkill, i):match("item:(%d+):")) or nil
					break
				end
			end
		end
	end
	 
	if (itemID == 0) then return end
	-- if there's no cached item id OR if it's different from the previous one ..
	if (not cachedItemID) or 
		(cachedItemID and (itemID ~= cachedItemID)) then

		cachedRecipeOwners = nil
		cachedItemID = itemID			-- we have searched this ID ..
        
		-- these are the cpu intensive parts of the update .. so do them only if necessary
		cachedSource = nil
		if addon:GetOption("UI.Tooltip.ShowItemSource") then
			local domain, subDomain = addon.Loots:GetSource(itemID)
			
			if domain then
				subDomain = (subDomain) and format(", %s", subDomain) or ""
				cachedSource = format("%s: %s%s", colors.gold..L["Source"], colors.teal..domain, subDomain)
			end
		end
		
		-- .. then check player bags to see how many times he owns this item, and where
		if addon:GetOption("UI.Tooltip.ShowItemCount") or addon:GetOption("UI.Tooltip.ShowTotalItemCount") then
			cachedCount = GetItemCount(itemID) -- if one of the 2 options is active, do the count
			cachedTotal = (cachedCount > 0) and format("%s: %s", colors.gold..L["Total owned"], colors.teal..cachedCount) or nil
		end
	end

	-- add item cooldown text
	local owner = tooltip:GetOwner()
	if owner and owner.startTime then
		tooltip:AddLine(format(ITEM_COOLDOWN_TIME, SecondsToTime(owner.duration - (GetTime() - owner.startTime))),1,1,1);
	end

	WriteCounterLines(tooltip)
	WriteTotal(tooltip)
	
	if cachedSource then		-- add item source
		tooltip:AddLine(" ",1,1,1);
		tooltip:AddLine(cachedSource,1,1,1);
	end
	
	-- addon:CheckMaterialUtility(itemID)
	
	if addon:GetOption("UI.Tooltip.ShowItemID") then
		local iLevel = select(4, GetItemInfo(itemID))
		
		if iLevel then
			tooltip:AddLine(" ",1,1,1);
			tooltip:AddDoubleLine("Item ID: " .. colors.green .. itemID,  "iLvl: " .. colors.green .. iLevel);
		end
	end
	
	local _, _, _, _, _, itemType, itemSubType, _, _, _, sellPrice = GetItemInfo(itemID)
	
	if sellPrice and sellPrice > 0 and addon:GetOption("UI.Tooltip.ShowSellPrice") then	-- 0 = cannot be sold
		tooltip:AddLine(" ",1,1,1)
		tooltip:AddLine("Sells for " .. addon:GetMoneyStringShort(sellPrice, colors.white) .. " per unit",1,1,1)
	end
	
	if addon:GetOption("UI.Tooltip.ShowKnownRecipes") == false then return end -- exit if recipe information is not wanted
	
	if itemType ~= L["ITEM_TYPE_RECIPE"] then return end		-- exit if not a recipe
	if itemSubType == L["ITEM_SUBTYPE_BOOK"] then return end		-- exit if it's a book

	if not cachedRecipeOwners then
		cachedRecipeOwners = GetRecipeOwnersText(itemSubType, link, addon:GetRecipeLevel(link, tooltip))
	end
	
	if cachedRecipeOwners then
		tooltip:AddLine(" ",1,1,1);	
		tooltip:AddLine(cachedRecipeOwners, 1, 1, 1, 1);
	end	
end

local function Hook_LinkWrangler(frame)
	local _, link = frame:GetItem()
	if link then
		ProcessTooltip(frame, link)
	end
end

-- ** GameTooltip hooks **
local function OnGameTooltipShow(tooltip, ...)
    if GameTooltip:GetItem() then return end
	if ShowGatheringNodeCounters() then
	   GameTooltip:Show()
    end
end

local updateTooltip = TOOLTIP_UPDATE_TIME

local function OnGameTooltipUpdate(tooltip, elapsed)
	-- Only update every TOOLTIP_UPDATE_TIME seconds
	updateTooltip = updateTooltip - elapsed;
	if ( updateTooltip > 0 ) then
		return;
	end
	updateTooltip = TOOLTIP_UPDATE_TIME;

    if not gatheringNodeWasShown then
        if ShowGatheringNodeCounters() then
            GameTooltip:Show()
        end
    end
end

local function OnGameTooltipSetItem(tooltip, ...)
	if (not isTooltipDone) and tooltip then
		isTooltipDone = true

		local name, link = tooltip:GetItem()
		-- Blizzard broke tooltip:GetItem() in 6.2. Detect and fix the bug if possible.
		if name == "" then
			local itemID = addon:GetIDFromLink(link)
			if not itemID or itemID == 0 then
				-- hooking SetRecipeResultItem & SetRecipeReagentItem is necessary for trade skill UI, link is captured and saved in storedLink
				link = storedLink
			end
		end
		
		if link then
			ProcessTooltip(tooltip, link)
		end
	end
end

local function OnGameTooltipCleared(tooltip, ...)
	isTooltipDone = nil
	isNodeDone = nil		-- for informant
	storedLink = nil
    gatheringNodeWasShown = nil
end

local function ListEnchantingOwners(enchantLink, tooltip)
    if not cachedRecipeOwners then 
        local know, couldLearn = addon:GetRecipeOwners(DataStore:GetLocaleEnchantingName(), enchantLink, 1)
    	
    	local lines = {}
    	if #know > 0 then
    		table.insert(lines, colors.teal .. L["Already known by "] ..": ".. colors.white.. table.concat(know, ", ") .."\n")
    	end
    	
    	if #couldLearn > 0 then
    		table.insert(lines, colors.yellow .. "Not yet known by " ..": ".. colors.white.. table.concat(couldLearn, ", ") .."\n")
    	end
	
	    cachedRecipeOwners = table.concat(lines, "\n")
    end
    
    if cachedRecipeOwners then
		tooltip:AddLine(" ",1,1,1);	
		tooltip:AddLine(cachedRecipeOwners, 1, 1, 1, 1);
	end
end

-- This should only ever fire when the Enchanting UI is open
local function Hook_GameTooltip_SetCraftSpell(tooltip, craftSelectionIndex)
    if GetCraftName() ~= DataStore:GetLocaleEnchantingName() then return end
    
    ListEnchantingOwners(GetCraftItemLink(craftSelectionIndex), tooltip)
end

-- ** ItemRefTooltip hooks **
local function OnItemRefTooltipShow(tooltip, ...)
	addon:ListCharsOnQuest( _G["ItemRefTooltipTextLeft1"]:GetText(), UnitName("player"), ItemRefTooltip)
	ItemRefTooltip:Show()
end

local function OnItemRefTooltipSetItem(tooltip, ...)
	if (not isTooltipDone) and tooltip then
		local _, link = tooltip:GetItem()
		isTooltipDone = true
		if link then
			ProcessTooltip(tooltip, link)
		end
	end
end

local function OnItemRefTooltipCleared(tooltip, ...)
	isTooltipDone = nil
end

function addon:InitTooltip()
	-- script hooks
	GameTooltip:HookScript("OnShow", OnGameTooltipShow)
    GameTooltip:HookScript("OnUpdate", OnGameTooltipUpdate)
	GameTooltip:HookScript("OnTooltipSetItem", OnGameTooltipSetItem)
	GameTooltip:HookScript("OnTooltipCleared", OnGameTooltipCleared)
    hooksecurefunc(GameTooltip, "SetCraftSpell", Hook_GameTooltip_SetCraftSpell)

	ItemRefTooltip:HookScript("OnShow", OnItemRefTooltipShow)
	ItemRefTooltip:HookScript("OnTooltipSetItem", OnItemRefTooltipSetItem)
	ItemRefTooltip:HookScript("OnTooltipCleared", OnItemRefTooltipCleared)
	
	-- LinkWrangler support
	if LinkWrangler then
		LinkWrangler.RegisterCallback ("Altoholic",  Hook_LinkWrangler, "refresh")
	end
end

function addon:RefreshTooltip()
	cachedItemID = nil	-- putting this at NIL will force a tooltip refresh in self:ProcessToolTip
end

function addon:GetItemCount(searchedID)
	-- "public" for other addons using it
	return GetItemCount(searchedID)
end
