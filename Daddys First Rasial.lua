--print("Daddy's first Rasial 1.22")
--print("by Daddy")
local API = require("api")
local UTILS = require("utils")
local AURAS = require("deadAuras")
-----------------------------------------------
-- Edit these. It will automatically combo eat, but no solid food. Make sure these match the names on the ability bar.
local percentHpToEat = 50
local useEquilibriumAura = false
--local hasBankPin = false
--local PIN = 0000
-----------------------------------------------
local globalCD = 3

local globalCooldownActive, foodCooldown, drinkCooldown, moveCooldown, genericCooldown, vulnCooldown = false, false, false, false, false, false
local lastAbilityTime, lastEatTime, lastMoveTime, lastDrinkTime, lastSummonTime, lastGenericTime, lastVulnTime, lastScrollTime = 0, 0, 0, 0, 0, 0, 0, 0
local deflectTimer, storedScrolls = 0, 0
local inP4, inCombat, rasialDead, usingScrolls, usingVulnBombs = false, false, false, false, false

local badTiles = {}
local safeBoundary = {}

local abilityRotation = { -- Ability rotation order, change as needed!
"Vulnerability", "Death Skulls", "Soul Sap", "Bloat", "Touch of Death", "Basic<nbsp>Attack", "Soul Sap", "Command Skeleton Warrior", "Basic<nbsp>Attack", "Resonance",  
 "Living Death", "Touch of Death", "Death Skulls", "Split Soul", "Finger of Death", "Basic<nbsp>Attack", "Basic<nbsp>Attack", "Basic<nbsp>Attack", "Basic<nbsp>Attack", "Death Skulls",
 "Finger of Death", "Touch of Death", "Basic<nbsp>Attack", "Basic<nbsp>Attack", "Finger of Death", "Finger of Death", "Death Skulls", 
 "Soul Sap", "Volley of Souls", "Command Skeleton Warrior","Basic<nbsp>Attack","Soul Sap", "Bloat", "Basic<nbsp>Attack", "Touch of Death", "Vulnerability", "Basic<nbsp>Attack","Soul Sap","Bloat", "Command Putrid Zombie",
 "Basic<nbsp>Attack", "Conjure Undead Army", "Basic<nbsp>Attack", "Soul Sap",  "Freedom","Volley of Souls",
 "Soul Sap", "Touch of Death", "Basic<nbsp>Attack", "Command Vengeful Ghost", "Soul Sap", "Command Skeleton Warrior", "Command Putrid Zombie", "Basic<nbsp>Attack", "Soul Sap", "Volley of Souls","Death Skulls" ,"Reflect", "Touch of Death", "Finger of Death", "Weapon Special Attack",
 "Basic<nbsp>Attack", "Bloat",  -- should be dead here 


"Command Skeleton Warrior","Soul Sap","Bloat", "Basic<nbsp>Attack", "Basic<nbsp>Attack", "Soul Sap", "Bloat", "Volley of Souls", "Basic<nbsp>Attack", "Finger of Death", "Weapon Special Attack", --
"Command Skeleton Warrior", "Touch of Death", "Finger of Death", "Soul Sap", "Basic<nbsp>Attack", "Bloat", "Basic<nbsp>Attack", "Soul Sap", "Volley of Souls", "Bloat", "Command Skeleton Warrior",
"Touch of Death","Soul Sap", "Finger of Death", "Basic<nbsp>Attack", "Bloat", "Soul Sap", "Volley of Souls", "Bloat", "Basic<nbsp>Attack",
}

local deflectCues = {
    "Suffer at my hand",
    "This is true power",
}
local relevantIds = {
    overload = {buffId = {26093, 33210, 49039}, potionID = {}, count = 0, globalCount = 0, globalCountSet = false }, 
    summon = { buffId = {26095}, pouchId = {}, count = 0, globalCount = 0 }, 
    deflectNecro = { buffId = 30745 },
    soulSplit = { buffId = 26033 },
    sorrow = { buffId = 30771 },
    brew = { potionID = {}, count = 0, globalCount = 0, globalCountSet = false },  -- Shared table for both Saradomin Brew and Guthix Rest
    blubber = { potionID = {}, count = 0, globalCount = 0, globalCountSet = false },  
    adrenaline = { potionID = {}, count = 0, globalCount = 0, globalCountSet = false }, -- Shared table for both Adrenaline and Renewals
    excalibur = { hasExcalibur = false, id = 0 },
    scroll = { scrollID = {}, amount = 0 },
    vulnbombs = { id = {}, amount = 0 },
    restore = { potionID = {}, count = 0, globalCount = 0, globalCountSet = false},
    aura = { buffID = 26098 },
}

-- Helper function to check if an ID already exists in the list
local function containsId(id, idList)
    for _, existingId in ipairs(idList) do
        if existingId == id then
            return true
        end
    end
    return false
end
local refreshInterface = {
    InterfaceComp5.new(1477, 25, -1, 0),
    InterfaceComp5.new(1477, 765, -1, 0),
    InterfaceComp5.new(1477, 767, -1, 0),
}
local auraRefreshInterface2 = {
    InterfaceComp5.new(1929, 0, -1, 0),
    InterfaceComp5.new(1929, 3, -1, 0),
    InterfaceComp5.new(1929, 4, -1, 0),
    InterfaceComp5.new(1929, 20, -1, 0),
    InterfaceComp5.new(1929, 21, -1, 0),
    InterfaceComp5.new(1929, 24, -1, 0),
}
function captureAuraActivation()
    local old_print = print
    local message = nil

    -- Override print function
    print = function(...)
        local args = {...}
        local str = ""

        -- Convert all arguments to string
        for i, v in ipairs(args) do
            str = str .. tostring(v)  -- Convert each argument to string
        end

        -- Check if the message is "dont have aura"
        if str == "dont have aura" then
            message = str
        end
        
        old_print(...)  -- Call the original print function
    end

    AURAS.EQUILIBRIUM:activate()

    -- Restore original print function
    print = old_print

    return message ~= "dont have aura"  -- Returns true if activation was successful
end

-- General function to check for items
local function checkItem(itemNames, itemTable)
    local itemFound = false
    local allItems = Inventory:GetItems()
    if itemTable.count ~= nil then
        itemTable.count = 0
    end

    -- Check inventory for matching items
    for _, item in ipairs(allItems) do
        if item then
            for _, itemName in ipairs(itemNames) do
                if item.name:lower():find(itemName:lower()) then
                    itemFound = true
                    if itemTable.potionID then
                        -- Add the item ID only if not already in the list
                        if not containsId(item.id, itemTable.potionID) then
                            table.insert(itemTable.potionID, item.id)
                        end
                        itemTable.count = itemTable.count + 1
                    elseif itemTable == relevantIds.excalibur and not itemTable.hasExcalibur then
                        -- **Excalibur Handling**: Only set if not already set
                        itemTable.hasExcalibur = true
                        itemTable.id = item.id
                        --print("Found Excalibur with ID: " .. item.id)
                    elseif itemTable == relevantIds.scroll then
                        if not containsId(item.id, itemTable.scrollID) then
                            table.insert(itemTable.scrollID, item.id)
                            --print("Found Scrolls: " .. item.name)
                            usingScrolls = true
                        end
                        itemTable.amount = item.amount
                    elseif itemTable == relevantIds.summon and itemTable.pouchId then
                        if not containsId(item.id, itemTable.pouchId) then
                            table.insert(itemTable.pouchId, item.id)
                            --print("Found pouch: " .. item.name)
                        end
                        itemTable.count = itemTable.count + 1
                    elseif itemTable == relevantIds.vulnbombs and itemTable.id then
                        if not containsId(item.id, itemTable.id) then
                            table.insert(itemTable.id, item.id)
                            --print("Found vuln bombs" .. relevantIds.vulnbombs.id[1])
                            usingVulnBombs = true
                        end
                        itemTable.amount = item.amount
                    end
                end
            end
        end
    end

    -- Remove IDs that are no longer in inventory (only for potions)
    if itemTable.potionID then
        for i = #itemTable.potionID, 1, -1 do
            local id = itemTable.potionID[i]
            local idFound = false
            for _, item in ipairs(allItems) do
                if item.id == id then
                    idFound = true
                    break
                end
            end
            if not idFound then
                --print("Removing ID " .. id .. " from potionID list (not found in inventory).")
                table.remove(itemTable.potionID, i)
            end
        end
    end
    -- Logging the result for the category checked
    if itemFound then
        if itemTable.hasExcalibur then
            print("Excalibur found and recorded.")
        elseif itemTable.globalCount and not itemTable.globalCountSet then
            itemTable.globalCount = itemTable.count
            print("Set initial count for " .. table.concat(itemNames, " or ") .. ": " .. itemTable.globalCount)
            itemTable.globalCountSet = true
        elseif itemTable == relevantIds.scroll and itemTable.amount == 0 and usingScrolls then
            itemTable.amount = itemTable.amount
            print("Set initial amount of scrolls for " .. table.concat(itemNames, " or ") .. ": " .. itemTable.amount)
        elseif itemTable == relevantIds.vulnbombs and itemTable.amount == 0 and usingVulnBombs then
            itemTable.amount = itemTable.amount
            print("Set initial amount of scrolls for " .. table.concat(itemNames, " or ") .. ": " .. itemTable.amount)
        else
            print("Updated count for " .. table.concat(itemNames, " or ") .. ": " .. (itemTable.count or itemTable.amount))
        end
    else
        print("No " .. table.concat(itemNames, " or ") .. " found in inventory.")
        itemTable.globalCount = nil
    end
end

-- Main function to check all relevant items in the inventory
local function checkInventoryItems(itemCategories)
    local allItems = Inventory:GetItems()

    -- Loop through item categories and check each
    for _, itemCategory in ipairs(itemCategories) do
        if itemCategory == "overload" then
            checkItem({"overload"}, relevantIds.overload)
        elseif itemCategory == "brew" then
            checkItem({"saradomin brew", "guthix rest"}, relevantIds.brew)
        elseif itemCategory == "blubber" then
            checkItem({"blubber"}, relevantIds.blubber)
        elseif itemCategory == "adrenaline" then
            checkItem({"adrenaline", "replenishment"}, relevantIds.adrenaline)
        elseif itemCategory == "excalibur" then
            checkItem({"excalibur"}, relevantIds.excalibur)
        elseif itemCategory == "bindingContract" then
            checkItem({"binding contract", "pouch"}, relevantIds.summon)
        elseif itemCategory == "scroll" then
            checkItem({"scroll"}, relevantIds.scroll)
        elseif itemCategory == "vulnBombs" then
            checkItem({"vulnerability bomb"}, relevantIds.vulnbombs)
        elseif itemCategory == "restore" then
            checkItem({"super restore", "prayer potion", "prayer flask"}, relevantIds.restore)
        else
            print("Invalid category specified: " .. itemCategory)
        end
    end

    -- Compare current inventory counts to stored global counts
    for category, itemTable in pairs(relevantIds) do
        if itemTable.globalCount and itemTable.potionID and itemTable.count < itemTable.globalCount then
            --print("Insufficient " .. category .. " items. Expected " .. itemTable.globalCount .. ", found " .. (itemTable.count or 0))
            return false
        elseif itemTable == "scroll" and itemTable.amount and itemTable.amount < 10 and usingScrolls then
            local vbValue = API.VB_FindPSettinOrder(4823).state -- Get the VB value for stored scrolls
            storedScrolls = vbValue - 1048576 + itemTable.amount

            if storedScrolls < 10 then
                --print("Insufficient " .. category .. " items. Less than 10 found. Only " .. storedScrolls .. " remaining.")
                return false
            end
        elseif itemTable == "vulnBombs" and itemTable.amount and itemTable.amount < 10 and usingVulnBombs then
            --print("Insufficient " .. category .. " items. Less than 10 found. Only " .. itemTable.amount .. " remaining.")
            return false
        end
    end

    -- **Check for Excalibur: It must be present if it was found initially**
    if relevantIds.excalibur.hasExcalibur and not Inventory:Contains(relevantIds.excalibur.id) then
        --print("Excalibur is missing from inventory!")
        return false
    end
    return true
end

function getRemainingFamiliarTimeInMinutes()
    local vb_state = API.VB_FindPSettinOrder(1786, 0).state
    return math.floor((vb_state * 0.46875) / 60)
end

local function getRasial()
    local rasial = API.GetAllObjArray1({30165}, 20, {1})
    return #rasial > 0 and rasial[1] or nil
end

local function checkCues()
    local chatTexts = API.GatherEvents_chat_check()
    local rasial = getRasial()
    for k, v in pairs(chatTexts) do
        if k > 10 then break end  -- Limit processing to recent messages

        for _, cue in ipairs(deflectCues) do
            if string.find(v.text, cue) then
                return true
            end 
        end
    end
    return false
end

local function buffCheck()
    -- Overload Check
    local overloadActive = false
    for _, buffId in ipairs(relevantIds.overload.buffId) do
        if API.Buffbar_GetIDstatus(buffId, false).id > 0 then
            overloadActive = true
            break
        end
    end
    if not overloadActive and (API.Get_tick() - lastAbilityTime >= 2) and (API.Get_tick() - lastDrinkTime >= globalCD) then
        if relevantIds.overload and #relevantIds.overload.potionID > 0 then
            API.DoAction_Inventory1(relevantIds.overload.potionID[1], 0, 1, API.OFF_ACT_GeneralInterface_route)
            lastDrinkTime = API.Get_tick()
            drinkCooldown = true
            return
        end
    end
    -- Summon Check
    if API.Buffbar_GetIDstatus(relevantIds.summon.buffId, false).id <= 0 then
        if getRemainingFamiliarTimeInMinutes() <= 1 then 
            if relevantIds.summon and #relevantIds.summon.pouchId > 0 then
                if not genericCooldown then
                    API.DoAction_Inventory2({ relevantIds.summon.pouchId[1] }, 0, 1, API.OFF_ACT_GeneralInterface_route)
                    genericCooldown = true
                    lastGenericTime = API.Get_tick()
                end
            end
        end
    end

    -- Chat Cue Based Prayer Handling
    if inCombat then
        if checkCues() then
            if API.Buffbar_GetIDstatus(relevantIds.deflectNecro.buffId, false).id <= 0 then
                API.DoAction_Ability("Deflect Necromancy", 1, API.OFF_ACT_GeneralInterface_route)
                deflectTimer = API.Get_tick() + 6
            end
        elseif API.Get_tick() >= deflectTimer and not genericCooldown then
            if API.Buffbar_GetIDstatus(relevantIds.soulSplit.buffId, false).id <= 0 then
                API.DoAction_Ability("Soul Split", 1, API.OFF_ACT_GeneralInterface_route)
                --print("Soul split activated")
                genericCooldown = true
                lastGenericTime = API.Get_tick()
            end
        end
        -- Sorrow Check
        if API.Buffbar_GetIDstatus(relevantIds.sorrow.buffId, false).id <= 0 and not genericCooldown then
            API.DoAction_Ability("Sorrow", 1, API.OFF_ACT_GeneralInterface_route)
            genericCooldown = true
            lastGenericTime = API.Get_tick()
        end
    end
end

local function checkAndStoreScrolls()
    local vbValue = API.VB_FindPSettinOrder(4823).state -- Get the VB value for stored scrolls
    storedScrolls = vbValue - 1048576 -- Extract stored scroll count

    if relevantIds.scroll and #relevantIds.scroll.scrollID > 0 and storedScrolls < 10 and not genericCooldown then
        API.DoAction_Interface(0xffffffff, 0xffffffff, 1, 662, 78, -1, API.OFF_ACT_GeneralInterface_route)
        print("Stored more familiar scrolls.")
        genericCooldown = true
        lastGenericTime = API.Get_tick()
    end
end

local function executeAbility(abilityName)
    if abilityName == "Living Death" then
        if drinkCooldown then
            API.DoAction_Ability("Basic<nbsp>Attack", 1, API.OFF_ACT_GeneralInterface_route, true)
        else
            API.DoAction_Ability(abilityName, 1, API.OFF_ACT_GeneralInterface_route, true) 
            if relevantIds.excalibur.hasExcalibur == true then API.DoAction_Inventory1(relevantIds.excalibur.id,0,1,API.OFF_ACT_GeneralInterface_route) end
            if #relevantIds.adrenaline.potionID > 0 then API.DoAction_Inventory2(relevantIds.adrenaline.potionID[1], 0, 1, API.OFF_ACT_GeneralInterface_route) end
        end
    else
        API.DoAction_Ability(abilityName, 1, API.OFF_ACT_GeneralInterface_route, true)
        --print("Executing ability: " .. abilityName)
    end
    globalCooldownActive = true
    lastAbilityTime = API.Get_tick()
end

local function timeTrack()
    local currentTime = API.Get_tick()

    if currentTime - lastAbilityTime >= globalCD and globalCooldownActive then
        globalCooldownActive = false
    end
    if currentTime - lastEatTime >= globalCD and foodCooldown then
        foodCooldown = false
        checkItem({"blubber"}, relevantIds.blubber)
    end
    if currentTime - lastMoveTime >= 2 and moveCooldown then
        moveCooldown = false 
    end
    if currentTime - lastGenericTime >= globalCD and genericCooldown then
        genericCooldown = false
    end
    if currentTime - lastDrinkTime >= globalCD and drinkCooldown then
        drinkCooldown = false
        checkItem({"brew"}, relevantIds.brew)
        checkItem({"overload"}, relevantIds.overload)
        checkItem({"restore"}, relevantIds.restore)
    end
    if currentTime - lastScrollTime >= 2 and scrollCooldown then
        scrollCooldown = false
        local vbValue = API.VB_FindPSettinOrder(4823).state -- Get the VB value for stored scrolls
        storedScrolls = vbValue - 1048576 -- Extract stored scroll count
    end
    if currentTime - lastVulnTime >= 100 and vulnCooldown then
        vulnCooldown = false
        checkItem({"vulnerability bomb"}, relevantIds.vulnbombs)
    end
end

local function openEquipmentInterface()
    API.DoAction_Interface(0xc2, 0xffffffff, 1, 1432, 5, 2, API.OFF_ACT_GeneralInterface_route)
end

local function isEquipmentInterfaceOpen()
    return API.VB_FindPSettinOrder(3074,1).state == 1
end

local function findNPC(npcid, distance)
    local distance = distance or 20
    local npcs = API.GetAllObjArrayInteract(type(npcid) == "table" and npcid or {npcid}, distance, {1})
    return #npcs > 0 and npcs[1] or false
end

local function hasTarget()
    local interacting = API.ReadLpInteracting()
    if interacting.Id ~= 0 and interacting.Life > 0 then
        return true
    elseif not interacting or not interacting.Id or not interacting.Life then
        return false
    end
end

local function waitForRasial(maxWaitTime)
    local timeWaited = 0
    local intervalCheck = 300

    while timeWaited < maxWaitTime do

        if findNPC(30165, 20) then
         --print("Rasial Found. Fighting.")
            API.DoAction_NPC(0x2a, API.OFF_ACT_AttackNPC_route, {30165}, 50)
            if hasTarget() then
                return true
            end
        end

        API.RandomSleep2(intervalCheck, 0, 0)
        timeWaited = timeWaited + intervalCheck
    end

   --print("Rasial did not spawn....")
    return false
end

local function findNpcOrObject(npcid, distance, objType)
    local distance = distance or 20

    return #API.GetAllObjArray1({npcid}, distance, {objType}) > 0
end

function UTILS.surge()
    local surgeAB = UTILS.getSkillOnBar("Surge")
    if surgeAB ~= nil then
        return API.DoAction_Ability_Direct(surgeAB, 1, API.OFF_ACT_GeneralInterface_route)
    end
    return false
end

local function WarsRoomTeleport()
    API.DoAction_Ability("War's Retreat Teleport", 1, API.OFF_ACT_GeneralInterface_route)
    API.RandomSleep2(1200, 1200, 1800)
    API.WaitUntilMovingandAnimEnds(1, 10)
end

local function moveToOffsetTile(offsetX, offsetY)
    local playerPos = API.PlayerCoord()  -- Get current player position
    local targetX = math.floor(playerPos.x + offsetX)
    local targetY = math.floor(playerPos.y + offsetY)
   --print("Moving to tile:", targetX, targetY)
    API.DoAction_Tile(WPOINT.new(targetX, targetY, 0))  -- Move to the calculated tile
end

local function eatNdrink()
    -- Use blubber if found
    if relevantIds.blubber and #relevantIds.blubber.potionID > 0 and not foodCooldown then
        if Inventory:IsOpen() then API.DoAction_Inventory2(relevantIds.blubber.potionID[1], 0, 1, API.OFF_ACT_GeneralInterface_route)
            lastEatTime = API.Get_tick()
            foodCooldown = true 
        end    
    end

    -- Use brew potion (Saradomin or Guthix) if found
    if relevantIds.brew and #relevantIds.brew.potionID > 0 and not drinkCooldown then
        if Inventory:IsOpen() then API.DoAction_Inventory2(relevantIds.brew.potionID[1], 0, 1, API.OFF_ACT_GeneralInterface_route) 
            lastDrinkTime = API.Get_tick()
            drinkCooldown = true
        end    
    end
end

local function hasScrollId(targetId)
    for _, id in ipairs(relevantIds.scroll.scrollID) do
        if id == targetId then
            return true
        end
    end
    return false
end

local function healthCheck()
    local hp = API.GetHPrecent()
    local pray = API.GetPray_()
    if pray < 100 then
        if relevantIds.restore and #relevantIds.restore.potionID > 0 and not drinkCooldown then
            if Inventory:IsOpen() then API.DoAction_Inventory2(relevantIds.restore.potionID[1], 0, 1, API.OFF_ACT_GeneralInterface_route)
                lastDrinkTime = API.Get_tick()
                drinkCooldown = true
            end
        end
    end
    if hp < percentHpToEat then
        eatNdrink()
    elseif hp < 5 then
        --print("Teleporting out")
        WarsRoomTeleport()
        --print("Something funky happened, resetting")
    end
    if usingScrolls and hasScrollId(49413) then
        local summonHP = API.VB_FindPSettinOrder(5194).state & 0xFFFF
        if summonHP < 2000 and not scrollCooldown then
            --print(summonHP)
            API.DoAction_Interface(0xffffffff,0xffffffff,1,1430,36,-1,API.OFF_ACT_GeneralInterface_route)
            lastScrollTime = API.Get_tick()
            scrollCooldown = true
        end
    end
end

local function isTileInBoundary(tile)
    return tile.x >= safeBoundary.minX and tile.x <= safeBoundary.maxX and
           tile.y >= safeBoundary.minY and tile.y <= safeBoundary.maxY
end

local function updateBadTiles()
    local currentTick = API.Get_tick()  -- Get the current tick
    badTiles = {}
    -- Step 1: Detect current bad tiles
    local detectedTiles = API.GetAllObjArray1({7862, 6974}, 20, {4})
    local currentDetectedKeys = {}  -- Store keys of currently detected tiles

    for _, item in ipairs(detectedTiles) do
        if item.Tile_XYZ then
            badTiles[#badTiles+1] = item.Tile_XYZ
            --print("Bad tile detected:", item.Tile_XYZ.x, item.Tile_XYZ.y)
        end
    end
end

local function isPlayerOnBadTile()
    local playerTile = API.PlayerCoordfloat()

    for _, badTile in ipairs(badTiles) do
        if badTile.x == playerTile.x and badTile.y == playerTile.y then
            --print("Player is standing on a bad tile!")
            return true
        end
    end

    --print("Player is safe.")
    return false
end

local function isTileBad(tile)
    for _, badTile in ipairs(badTiles) do
        if badTile.x == tile.x and badTile.y == tile.y then
            return true  -- Tile is bad
        end
    end
    return false  -- Tile is safe
end

local function isPathSafe(startTile, endTile, badTiles)
    local currentTick = API.Get_tick()
    local dx = endTile.x - startTile.x
    local dy = endTile.y - startTile.y
    local steps = math.max(math.abs(dx), math.abs(dy))  -- Total steps needed

    --print("Checking path from x=" .. startTile.x .. ", y=" .. startTile.y .. " to x=" .. endTile.x .. ", y=" .. endTile.y)

    -- Normalize step direction (-1, 0, 1) for both X and Y
    local stepX = dx ~= 0 and (dx / math.abs(dx)) or 0  
    local stepY = dy ~= 0 and (dy / math.abs(dy)) or 0  

    --print("Step direction: x=" .. stepX .. ", y=" .. stepY)

    -- Current tile starting point
    local checkTile = {x = startTile.x, y = startTile.y}

    -- Loop through each step and check if the path is clear
    for i = 1, steps do
        -- Move diagonally or in the current direction
        if stepX ~= 0 and stepY ~= 0 then
            checkTile.x = checkTile.x + stepX
            checkTile.y = checkTile.y + stepY
        elseif stepX ~= 0 then
            checkTile.x = checkTile.x + stepX
        elseif stepY ~= 0 then
            checkTile.y = checkTile.y + stepY
        end

        --print("Checking tile x=" .. checkTile.x .. ", y=" .. checkTile.y)

        -- Check if the tile is bad
        if isTileBad(checkTile, badTiles) then
            --print("Path blocked at x=" .. checkTile.x .. ", y=" .. checkTile.y)
            return false  -- Path is blocked by a bad tile
        end
    end

    --print("Path is safe")
    return true  -- Path is safe
end

local function turnOffPrayers()
    if API.Buffbar_GetIDstatus(relevantIds.deflectNecro.buffId, false).id > 0 then
        API.DoAction_Ability("Deflect Necromancy", 1, API.OFF_ACT_GeneralInterface_route)
    end
    if API.Buffbar_GetIDstatus(relevantIds.soulSplit.buffId, false).id > 0 then
        API.DoAction_Ability("Soul Split", 1, API.OFF_ACT_GeneralInterface_route)
    end
    if API.Buffbar_GetIDstatus(relevantIds.sorrow.buffId, false).id > 0 then
        API.DoAction_Ability("Sorrow", 1, API.OFF_ACT_GeneralInterface_route)
    end
end

local function loot()
    rasialDead = true
    inCombat = false
    turnOffPrayers()
    --print("Starting loot function")
    local loot = API.ReadAllObjectsArray({3}, {-1}, {})
    --print("Found " .. #loot .. " objects to loot")
    local lootNumber = 0
    while true do
        if #loot > 0 then
            local lootObj = loot[1].Id
            --print("Looting object " .. loot[1].Id)
            API.RandomSleep2(1200, 300, 600)
            API.DoAction_Interface(0xffffffff,0xffffffff,1,1678,8,-1,API.OFF_ACT_GeneralInterface_route)
            API.RandomSleep2(1200, 300, 600)
            API.DoAction_Interface(0x24,0xffffffff,1,1622,22,-1,API.OFF_ACT_GeneralInterface_route)
            API.RandomSleep2(1200, 300, 600)
            loot = API.ReadAllObjectsArray({3}, {-1}, {})
            --print("Updated loot list: " .. #loot .. " objects")
            lootNumber = lootNumber + 1
        else
            loot = API.ReadAllObjectsArray({3}, {-1}, {})
            --print("Updated loot list: " .. #loot .. " objects")
            API.RandomSleep2(600, 0, 600)
        end
        if #loot == 0 and lootNumber > 0 then
            return
        end
    end
end

local function findSafeTile()
    local safeTiles = API.Math_FreeTiles(badTiles, 0, 12, {})
    local playerPos = API.PlayerCoordfloat()
    local minDistance = 1
    local filteredSafeTiles = {}
    local blockAttempts = 0
    --print("safeTiles: " .. #safeTiles)

    for _, tile in ipairs(safeTiles) do
        local dx, dy = math.abs(tile.x - playerPos.x), math.abs(tile.y - playerPos.y)
        if (dx >= minDistance or dy >= minDistance) and isTileInBoundary(tile) then
            table.insert(filteredSafeTiles, tile)
        end
    end

    for _, tile in ipairs(filteredSafeTiles) do
        if blockAttempts < 5 then
            if not isPathSafe(playerPos, tile) then
                blockAttempts = blockAttempts + 1
            elseif isPathSafe(playerPos, tile) then
                return tile
            end
        else
            return tile
        end
    end
    return nil
end

local function handleMovement()
    if moveCooldown then 
        return 
    end
    if isPlayerOnBadTile() then
        --print("On bad tile, attempting to move")
        local bestTile = findSafeTile()
        if bestTile then
            API.DoAction_TileF(bestTile)
            --print("Moving to safe tile at x=" .. bestTile.x .. " y=" .. bestTile.y)
            lastMoveTime = API.Get_tick()   
            moveCooldown = true
        else
            --print("No suitable safe tile found!")
        end
    end
end

local function abilityTrack(abilityIndex)
    local abilityIndex = abilityIndex
    if abilityIndex <= #abilityRotation and not globalCooldownActive then
        local abilityName = abilityRotation[abilityIndex]
        --print("Using ability:", abilityName)
        executeAbility(abilityName)
        abilityIndex = abilityIndex + 1
        return abilityIndex
    end

end

local function establishSafeBoundary()
    local findRasial = getRasial()

        local rasialTile = findRasial.Tile_XYZ
        if rasialTile then
            local wallY = rasialTile.y - 3  -- Wall is 3 tiles south of Rasial

            safeBoundary = {
                minX = rasialTile.x - 6, maxX = rasialTile.x + 6,
                minY = rasialTile.y - 6, maxY = wallY -- Max Y is at the wall, no movement past it
            }

            --print("New safe boundary set:")
            --print("X:", safeBoundary.minX, "to", safeBoundary.maxX)
            --print("Y:", safeBoundary.minY, "to", safeBoundary.maxY, "(Wall at Y =", wallY, ")")
        end
end

-- Main ability rotation function
local function rasialFight()
   --print("Rasial has full HP, starting ability rotation...")
    local abilityIndex = 1
    inCombat = true
    local rasial = getRasial()

    while API.GetInCombBit() or rasial.Life > 0 do
        rasial = getRasial()
        if usingVulnBombs and not vulnCooldown then
            API.DoAction_Inventory2(relevantIds.vulnbombs.id[1],0,1,API.OFF_ACT_GeneralInterface_route)            
            lastVulnTime = API.Get_tick()
            vulnCooldown = true
            --print("Using vuln bomb")
        end
        if rasial.Life <= 200000 and not inP4 then
          --print("Target's life is at or below 20%. going to p4.")
            inP4 = true
        end
        if rasial.Life < 1 then
            loot()
            return
        end
        timeTrack()
        healthCheck()
        buffCheck()
        if API.VB_FindPSettinOrder(3102).state == 1 then checkAndStoreScrolls() end
        abilityIndex = abilityTrack(abilityIndex) or abilityIndex
        if inP4 then
            establishSafeBoundary()
            updateBadTiles()
            handleMovement()
        end
    end
end

local function preRasial() -- walking to the back of the instance
    if findNpcOrObject(126134, 30, 12) and not hasTarget() then
      --print("Encounter Started, moving to back")
        API.RandomSleep2(300, 300, 0)
        UTILS.surge()
        API.DoAction_Ability("Command Vengeful Ghost", 1, API.OFF_ACT_GeneralInterface_route)
        API.RandomSleep2(600, 600, 0)
        moveToOffsetTile(0, 12)
        API.RandomSleep2(1200, 600, 0)
        API.DoAction_Ability("Command Skeleton Warrior", 1, API.OFF_ACT_GeneralInterface_route)
    else
       --print(findNpcOrObject(126134, 50, 12))
    end
end

local function DungeonEntrance()
    if findNpcOrObject(127142, 5, 12) then
        buffCheck()
        if useEquilibriumAura then
            AURAS.EQUILIBRIUM:activate()
        end
        --print("Entrance Found, Conjuring and Extending")
        executeAbility("Conjure Undead Army")
        API.RandomSleep2(1800, 600, 0)
        API.DoAction_Ability("Life Transfer", 1, API.OFF_ACT_GeneralInterface_route)
        API.DoAction_Object1(0x39, API.OFF_ACT_GeneralObject_route0, {127142}, 50)
        API.RandomSleep2(1500, 300, 600)
        if API.Compare2874Status(12) then
        --print("Interface found, Trying to click on rasial option")
            API.RandomSleep2(600, 200, 400)
            API.DoAction_Interface(0xffffffff,0xffffffff,0,1188,13,-1,API.OFF_ACT_GeneralInterface_Choose_option)
            API.RandomSleep2(1200, 300, 600)
            if API.Compare2874Status(18) then
                API.DoAction_Interface(0x24,0xffffffff,1,1591,60,-1,API.OFF_ACT_GeneralInterface_route)
                API.RandomSleep2(1200, 300, 600)
                preRasial()
            end
        else
        --print("Did not find start button. Trying again.")
        end
    else
      --print("Did not find entrance... moving on")
      --print(findNpcOrObject(127142, 50, 12), findNpcOrObject(126134, 50, 12))
    end    
end

local function needBank()
    local hp = API.GetHPrecent()
    local pray = API.GetPray_()
    local adren = API.GetAdrenalineFromInterface()
    if not checkInventoryItems({"overload", "brew", "blubber", "adrenaline", "excalibur", "bindingContract", "scroll", "vulnBombs", "restore"}) or hp < 100 or pray < API.GetPrayMax_() or adren < 100 then
        return true
    end
end

local function warsBank()
    local shouldContinue = true
    local hp = API.GetHPrecent()
    API.RandomSleep2(500, 300, 500)
    API.DoAction_Object1(0x33, API.OFF_ACT_GeneralObject_route3, {114750}, 50) -- QUICKLOAD
    API.RandomSleep2(3000, 600, 1200)
    API.WaitUntilMovingEnds(1, 10)
    --if hasBankPin then API.DoBankPin(PIN) end
    
    if not checkInventoryItems({"overload", "brew", "blubber", "adrenaline", "excalibur", "bindingContract", "scroll", "vulnBombs", "restore"}) then
        shouldContinue = false
        API.Write_LoopyLoop(false)
        return
    end
    
    while hp < 100 do  -- Sleeping to heal off damage
        API.RandomSleep2(600, 200, 400)
        hp = API.GetHPrecent()
    end
    
    if shouldContinue then
        API.DoAction_Object1(0x3d, API.OFF_ACT_GeneralObject_route0, {114748}, 50) -- Prayer renewal
        API.RandomSleep2(2400, 300, 600)
        API.DoAction_Object1(0x29, API.OFF_ACT_GeneralObject_route0, {114749}, 50)
        while API.GetAdrenalineFromInterface() < 100 do
            API.RandomSleep2(600, 0, 0)
        end
    end
    if useEquilibriumAura then
        if not AURAS.isAuraEquipped() then
            if not captureAuraActivation() then
                print("aura on cooldown, resetting")
                RandomSleep2(1200,0,0)
                AURAS.openAuraInterface()
                RandomSleep2(1200,0,0)
                API.DoAction_Interface(0xffffffff,0x5716,1,1929,95,23,API.OFF_ACT_GeneralInterface_route)
                RandomSleep2(1200,0,0)
                API.DoAction_Interface(0xffffffff,0x7c68,1,1929,24,-1,API.OFF_ACT_GeneralInterface_route)
                RandomSleep2(1800,0,0)
                refreshStatus = API.ScanForInterfaceTest2Get(false, refreshInterface)
                auraRefreshes = API.ScanForInterfaceTest2Get(false, auraRefreshInterface2)
                if #refreshStatus > 0 and auraRefreshes[1].itemid1_size > 0 then
                    API.DoAction_Interface(0xffffffff,0xffffffff,0,1188,8,-1,API.OFF_ACT_GeneralInterface_Choose_option)
                end
                RandomSleep2(1800,0,0)
                AURAS.EQUILIBRIUM:activate()
                RandomSleep2(1800,0,0)
                AURAS.closeAuraInterface()
            end
        end
    end
end
local function WhereTfAreWe()
    local findSconce = findNpcOrObject(126134, 50, 12)
    local findWarAltar = findNpcOrObject(114748, 50, 0)
    if findSconce then
        if not hasTarget() and not rasialDead then
            if waitForRasial(7000) then
                rasialFight()
            end
        elseif rasialDead then
            WarsRoomTeleport()
        end
    else
        if findWarAltar then
            inP4 = false
            rasialDead = false
            if needBank() then
                warsBank()
            end
            if API.Read_LoopyLoop() then
                API.DoAction_Object1(0x39, API.OFF_ACT_GeneralObject_route0, {127138}, 50) -- Rasial war portal id
                API.RandomSleep2(600, 600, 1200)
                API.WaitUntilMovingEnds()
            else
                API.RandomSleep2(200, 200, 200)
            end
        end
    end
end

local function deathCheck()
    if findNPC(27299, 50) then
        API.RandomSleep2(2500, 1500, 2000)
        print("You managed to die... (idiot), do we grab your things and go home?")
        API.RandomSleep2(1000, 800, 600)
        API.DoAction_NPC(0x29, API.OFF_ACT_InteractNPC_route3, {27299}, 50)
        API.RandomSleep2(1500, 1500, 2000)
        API.DoAction_Interface(0xffffffff, 0xffffffff, 1, 1626, 47, -1, API.OFF_ACT_GeneralInterface_route)
        API.RandomSleep2(1500, 1500, 2000)
        API.DoAction_Interface(0xffffffff, 0xffffffff, 0, 1626, 72, -1, API.OFF_ACT_GeneralInterface_Choose_option)
        API.RandomSleep2(1500, 1500, 2000)
        WarsRoomTeleport()
    end
end

local started = false
local function scriptStart()
    if API.VB_FindPSettinOrder(3039).state == 1 then
        print("Inventory is open")
    else
        print("Open the damn inventory, dude. I'm not gonna do everything for you. Whats next? You want me to click the buttons too? Maybe hold your hand while we sort potions? Come on, just pop it open and lets get this over with before I start charging an hourly rate. 5b still gonna ask whats wrong.")
        API.Write_LoopyLoop(false)
        return
    end
    API.DoAction_Object1(0x33, API.OFF_ACT_GeneralObject_route3, {114750}, 50) -- QUICKLOAD
    API.RandomSleep2(1200, 300, 400)
    API.WaitUntilMovingEnds(1, 10)
    checkInventoryItems({"overload", "brew", "blubber", "adrenaline", "excalibur", "scroll", "bindingContract", "vulnBombs", "restore"})
    if API.VB_FindPSettinOrder(3102).state == 1 then
        checkAndStoreScrolls()
    else
        print("did not find store scroll button. Make sure familiar interface is open)")
        API.Write_LoopyLoop(false)
        return
    end
    started = true
end

while API.Read_LoopyLoop() do
    API.SetMaxIdleTime(5)
    if not started then scriptStart() end
    if API.Read_LoopyLoop() then
        deathCheck()
        DungeonEntrance()
        WhereTfAreWe()
        API.RandomSleep2(100, 100, 100)
    end
end
