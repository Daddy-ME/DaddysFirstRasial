----print("Daddy's first Rasial 1.2")
----print("by Daddy")
local API = require("api")
local UTILS = require("utils")
-----------------------------------------------
-- Edit these. It will automatically combo eat, but no solid food. Make sure these match the names on the ability bar.
local percentHpToEat = 50
local hasBankPin = false
local PIN = 0000
-----------------------------------------------
local globalCD = 3

local globalCooldownActive, foodCooldown, moveCooldown, genericCooldown = false, false, false, false
local lastAbilityTime, lastEatTime, lastMoveTime, lastDrinkTime, lastSummonTime, lastGenericTime = 0, 0, 0, 0, 0, 0
local deflectTimer = 0
local inP4, inCombat, rasialDead = false, false, false

local badTiles = {}
local safeBoundary = {}

local abilityRotation = { -- Ability rotation order, change as needed!
"Vulnerability", "Death Skulls", "Bloat", "Soul Sap", "Touch of Death", "Basic<nbsp>Attack", "Soul Sap", "Command Skeleton Warrior", "Resonance", -- 
"Soul Sap", "Basic<nbsp>Attack", "Basic<nbsp>Attack", "Living Death", "Touch of Death", "Soul Sap", "Basic<nbsp>Attack", "Death Skulls", "Split Soul", --
"Command Skeleton Warrior", "Basic<nbsp>Attack", "Finger of Death", "Volley of Souls", "Weapon Special Attack", "Touch of Death", "Soul Sap", "Basic<nbsp>Attack", "Basic<nbsp>Attack", "Basic<nbsp>Attack", "Death Skulls", --
"Soul Sap", "Command Skeleton Warrior", "Basic<nbsp>Attack", "Soul Sap", "Touch of Death", "Basic<nbsp>Attack", "Soul Sap", "Bloat", "Vulnerability", "Soul Sap", "Volley of Souls", --
"Command Skeleton Warrior", "Soul Sap", "Weapon Special Attack", "Life Transfer", "Touch of Death", "Soul Sap", "Basic<nbsp>Attack", "Freedom", "Bloat", "Soul Sap", "Basic<nbsp>Attack", --
"Command Skeleton Warrior", "Death Skulls", "Soul Sap", "Basic<nbsp>Attack", "Basic<nbsp>Attack", "Soul Sap", "Bloat", "Volley of Souls", "Basic<nbsp>Attack", "Finger of Death", "Weapon Special Attack", --
"Command Skeleton Warrior", "Touch of Death",
}

local deflectCues = {
    "Suffer",
    "true",
}
local relevantIds = {
    overload = { id = 26093, potionID = {}, count = nil }, -- holy overloads
    summon = { id = 26095, pouchID = {} }, -- hellhound
    deflectNecro = { id = 30745 },
    soulSplit = { id = 26033 },
    sorrow = { id = 30771 },
    brew = { potionID = {}, count = nil },  -- Shared table for both Saradomin Brew and Guthix Rest
    blubber = { potionID = {}, count = nil },  
    adrenaline = { potionID = {}, count = nil }, -- Shared table for both Adrenaline and Renewals
    excalibur = { hasExcalibur = nil, id = nil },
}

-- Global variables to store the count of each item
local globalCounts = {
    overloadCount = nil,
    brewCount = nil,
    blubberCount = nil,
    adrenalineCount = nil,
    excaliburFound = nil, 
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

-- General function to check for items
local function checkItem(itemNames, itemTable)
    local itemFound = false
    itemTable.count = 0  -- Reset count each time the function is called
    local allItems = Inventory:GetItems()

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
                        itemTable.count = itemTable.count + item.amount
                    elseif itemTable.hasExcalibur ~= nil then
                        -- **Excalibur Handling**: Only set if not already set
                        if itemTable.hasExcalibur == nil then
                            itemTable.hasExcalibur = true
                            itemTable.id = item.id
                            --print("Found Excalibur with ID: " .. item.id)
                        end
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

    if itemFound then
        if itemTable.hasExcalibur == nil and itemTable.id then
            --print("Excalibur found and recorded.")
        elseif not itemTable.globalCount then
            itemTable.globalCount = itemTable.count
            --print("Set initial count for " .. table.concat(itemNames, " or ") .. ": " .. itemTable.globalCount)
        else
            --print("Updated count for " .. table.concat(itemNames, " or ") .. ": " .. itemTable.count)
        end
    else
        --print("No " .. table.concat(itemNames, " or ") .. " found in inventory.")
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
        else
            --print("Invalid category specified: " .. itemCategory)
        end
    end

    -- Compare current inventory counts to stored global counts
    for category, itemTable in pairs(relevantIds) do
        if itemTable.globalCount and itemTable.potionID and (itemTable.count or 0) < itemTable.globalCount then
            --print("Insufficient " .. category .. " items. Expected " .. itemTable.globalCount .. ", found " .. (itemTable.count or 0))
            return false
        end
    end

    -- **Check for Excalibur: It must be present if it was found initially**
    if relevantIds.excalibur.hasExcalibur and not Inventory:ContainsID(relevantIds.excalibur.id) then
        --print("Excalibur is missing from inventory!")
        return false
    end

    return true
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
    if API.Buffbar_GetIDstatus(relevantIds.overload.id, false).id <= 0 and (API.Get_tick() - lastAbilityTime >= 2) and (API.Get_tick() - lastDrinkTime >= globalCD) then --Do not want to interfere in ability use, so make sure 2 ticks after using ability
        lastDrinkTime = API.Get_tick()
        if relevantIds.overload and #relevantIds.overload.potionID > 0 then
            API.DoAction_Inventory1(relevantIds.overload.potionID[1], 0, 1, API.OFF_ACT_GeneralInterface_route)
            checkItem({"overload"}, relevantIds.overload, "overload")
            return
        end
    end

    -- Summon Check
    --if API.Buffbar_GetIDstatus(relevantIds.summon.id, false).id <= 0 and (API.Get_tick() - lastAbilityTime >=2) and (API.Get_tick() - lastSummonTime >= 1) then 
       -- lastSummonTime = API.Get_tick()
      --  API.DoAction_Inventory2({ relevantIds.summon.pouchID }, 0, 1, API.OFF_ACT_GeneralInterface_route)

    --    return
 --  end

    -- Chat Cue Based Prayer Handling
    if inCombat then
        if checkCues() then
            if API.Buffbar_GetIDstatus(relevantIds.deflectNecro.id, false).id <= 0 then
                API.DoAction_Ability("Deflect Necromancy", 1, API.OFF_ACT_GeneralInterface_route)
                deflectTimer = API.Get_tick() + 6
            end
        elseif API.Get_tick() >= deflectTimer and not genericCooldown then
            if API.Buffbar_GetIDstatus(relevantIds.soulSplit.id, false).id <= 0 then
                API.DoAction_Ability("Soul Split", 1, API.OFF_ACT_GeneralInterface_route)
                genericCooldown = true
                lastGenericTime = API.Get_tick()
            end
        end
        -- Sorrow Check
        if API.Buffbar_GetIDstatus(relevantIds.sorrow.id, false).id <= 0 and not genericCooldown then
            API.DoAction_Ability("Sorrow", 1, API.OFF_ACT_GeneralInterface_route)
            genericCooldown = true
            lastGenericTime = API.Get_tick()
        end
    end
end

local function executeAbility(abilityName)
    if abilityName == "Living Death" then
        API.DoAction_Ability(abilityName, 1, API.OFF_ACT_GeneralInterface_route, true) 
        if relevantIds.excalibur.hasExcalibur == true then API.DoAction_Inventory1(relevantIds.excalibur.id,0,1,API.OFF_ACT_GeneralInterface_route) end
        if #relevantIds.adrenaline.potionID > 0 then API.DoAction_Inventory2(relevantIds.adrenaline.potionID[1], 0, 1, API.OFF_ACT_GeneralInterface_route) end
    else
        API.DoAction_Ability(abilityName, 1, API.OFF_ACT_GeneralInterface_route, true)
        ----print("Executing ability: " .. abilityName)
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
        checkItem({"brew"}, relevantIds.brew, "brew")
        checkItem({"blubber"}, relevantIds.blubber, "blubber")
    end
    if currentTime - lastMoveTime >= 2 and moveCooldown then
        moveCooldown = false 
    end
    if currentTime - lastGenericTime >= globalCD then
        genericCooldown = false
    end
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
    local intervalCheck = 200

    while timeWaited < maxWaitTime do

        if findNPC(30165, 20) then
         ----print("Rasial Found. Fighting.")
            API.DoAction_NPC(0x2a, API.OFF_ACT_AttackNPC_route, {30165}, 50)
            if hasTarget() then
                return true
            end
        end

        API.RandomSleep2(intervalCheck, 0, 0)
        timeWaited = timeWaited + intervalCheck
    end

   ----print("Rasial did not spawn....")
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
   ----print("Moving to tile:", targetX, targetY)
    API.DoAction_Tile(WPOINT.new(targetX, targetY, 0))  -- Move to the calculated tile
end

local function eatNdrink()
    -- Use blubber if found
    if relevantIds.blubber and #relevantIds.blubber.potionID > 0 then
        if Inventory:IsOpen() then API.DoAction_Inventory2(relevantIds.blubber.potionID[1], 0, 1, API.OFF_ACT_GeneralInterface_route) end    
    end

    -- Use brew potion (Saradomin or Guthix) if found
    if relevantIds.brew and #relevantIds.brew.potionID > 0 then
        if Inventory:IsOpen() then API.DoAction_Inventory2(relevantIds.brew.potionID[1], 0, 1, API.OFF_ACT_GeneralInterface_route) end    
    end

    -- Set last eaten time and start food cooldown
    lastEatTime = API.Get_tick()
    foodCooldown = true

    -- Recheck and update IDs for both brew and blubber
    checkItem({"saradomin brew", "guthix rest"}, relevantIds.brew, "brew")
    checkItem({"blubber"}, relevantIds.blubber, "blubber")
end

local function healthCheck()
    local hp = API.GetHPrecent()
    if not foodCooldown then
        if hp < percentHpToEat then
            eatNdrink()
        elseif hp < 5 then
            ----print("Teleporting out")
            WarsRoomTeleport()
            ----print("Something funky happened, resetting")
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
            ----print("Bad tile detected:", item.Tile_XYZ.x, item.Tile_XYZ.y)
        end
    end
end

local function isPlayerOnBadTile()
    local playerTile = API.PlayerCoordfloat()

    for _, badTile in ipairs(badTiles) do
        if badTile.x == playerTile.x and badTile.y == playerTile.y then
            ----print("Player is standing on a bad tile!")
            return true
        end
    end

    ----print("Player is safe.")
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

    ----print("Checking path from x=" .. startTile.x .. ", y=" .. startTile.y .. " to x=" .. endTile.x .. ", y=" .. endTile.y)

    -- Normalize step direction (-1, 0, 1) for both X and Y
    local stepX = dx ~= 0 and (dx / math.abs(dx)) or 0  
    local stepY = dy ~= 0 and (dy / math.abs(dy)) or 0  

    ----print("Step direction: x=" .. stepX .. ", y=" .. stepY)

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

        ----print("Checking tile x=" .. checkTile.x .. ", y=" .. checkTile.y)

        -- Check if the tile is bad
        if isTileBad(checkTile, badTiles) then
            ----print("Path blocked at x=" .. checkTile.x .. ", y=" .. checkTile.y)
            return false  -- Path is blocked by a bad tile
        end
    end

    ----print("Path is safe")
    return true  -- Path is safe
end

local function turnOffPrayers()
    if API.Buffbar_GetIDstatus(relevantIds.deflectNecro.id, false).id > 0 then
        API.DoAction_Ability("Deflect Necromancy", 1, API.OFF_ACT_GeneralInterface_route)
    end
    if API.Buffbar_GetIDstatus(relevantIds.soulSplit.id, false).id > 0 then
        API.DoAction_Ability("Soul Split", 1, API.OFF_ACT_GeneralInterface_route)
    end
    if API.Buffbar_GetIDstatus(relevantIds.sorrow.id, false).id > 0 then
        API.DoAction_Ability("Sorrow", 1, API.OFF_ACT_GeneralInterface_route)
    end
end

local function loot()
    rasialDead = true
    inCombat = false
    turnOffPrayers()
    ----print("Starting loot function")
    local loot = API.ReadAllObjectsArray({3}, {-1}, {})
    ----print("Found " .. #loot .. " objects to loot")
    local lootNumber = 0
    while true do
        if #loot > 0 then
            local lootObj = loot[1].Id
            ----print("Looting object " .. loot[1].Id)
            API.RandomSleep2(1200, 300, 600)
            API.DoAction_Interface(0xffffffff,0xffffffff,1,1678,8,-1,API.OFF_ACT_GeneralInterface_route)
            API.RandomSleep2(1200, 300, 600)
            API.DoAction_Interface(0x24,0xffffffff,1,1622,22,-1,API.OFF_ACT_GeneralInterface_route)
            API.RandomSleep2(1200, 300, 600)
            loot = API.ReadAllObjectsArray({3}, {-1}, {})
            ----print("Updated loot list: " .. #loot .. " objects")
            lootNumber = lootNumber + 1
        else
            loot = API.ReadAllObjectsArray({3}, {-1}, {})
            ----print("Updated loot list: " .. #loot .. " objects")
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
    ----print("safeTiles: " .. #safeTiles)

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
        ----print("On bad tile, attempting to move")
        local bestTile = findSafeTile()
        if bestTile then
            API.DoAction_TileF(bestTile)
            ----print("Moving to safe tile at x=" .. bestTile.x .. " y=" .. bestTile.y)
            lastMoveTime = API.Get_tick()   
            moveCooldown = true
        else
            ----print("No suitable safe tile found!")
        end
    end
end

local function abilityTrack(abilityIndex)
    local abilityIndex = abilityIndex
    if abilityIndex <= #abilityRotation and not globalCooldownActive then
        local abilityName = abilityRotation[abilityIndex]
        ----print("Using ability:", abilityName)
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

            ----print("New safe boundary set:")
            ----print("X:", safeBoundary.minX, "to", safeBoundary.maxX)
            ----print("Y:", safeBoundary.minY, "to", safeBoundary.maxY, "(Wall at Y =", wallY, ")")
        end
end

-- Main ability rotation function
local function rasialFight()
   ----print("Rasial has full HP, starting ability rotation...")
    local abilityIndex = 1
    inCombat = true
    local rasial = getRasial()

    while API.GetInCombBit() or rasial.Life > 0 do
        rasial = getRasial()
        if rasial.Life <= 200000 and not inP4 then
          ----print("Target's life is at or below 20%. going to p4.")
            inP4 = true
        end
        if rasial.Life < 1 then
            loot()
            return
        end
        timeTrack()
        healthCheck()
        buffCheck()
        abilityIndex = abilityTrack(abilityIndex) or abilityIndex
        if inP4 then
            establishSafeBoundary()
            updateBadTiles()
            handleMovement()
        end

    end
    ----print("Rotation complete. Target is either gone or below 20% HP.")
end

local function preRasial() -- walking to the back of the instance
    if findNpcOrObject(126134, 30, 12) and not hasTarget() then
      ----print("Encounter Started, moving to back")
        API.RandomSleep2(600, 100, 0)
        UTILS.surge()
        API.DoAction_Ability("Command Vengeful Ghost", 1, API.OFF_ACT_GeneralInterface_route)
        API.RandomSleep2(1200, 100, 0)
        moveToOffsetTile(0, 12)
        API.RandomSleep2(1200, 600, 0)
        API.DoAction_Ability("Command Skeleton Warrior", 1, API.OFF_ACT_GeneralInterface_route)
    else
       ----print(findNpcOrObject(126134, 50, 12))
    end
end

local function DungeonEntrance()
    if findNpcOrObject(127142, 5, 12) then
        buffCheck()
        ----print("Entrance Found, Conjuring and Extending")
        executeAbility("Conjure Undead Army")
        API.RandomSleep2(1800, 600, 0)
        API.DoAction_Ability("Life Transfer", 1, API.OFF_ACT_GeneralInterface_route)
        API.DoAction_Object1(0x39, API.OFF_ACT_GeneralObject_route0, {127142}, 50)
        API.RandomSleep2(1500, 300, 600)
        if API.Compare2874Status(12) then
        ----print("Interface found, Trying to click on rasial option")
            API.RandomSleep2(600, 200, 400)
            API.DoAction_Interface(0xffffffff,0xffffffff,0,1188,13,-1,API.OFF_ACT_GeneralInterface_Choose_option)
            API.RandomSleep2(1200, 300, 600)
            if API.Compare2874Status(18) then
                API.DoAction_Interface(0x24,0xffffffff,1,1591,60,-1,API.OFF_ACT_GeneralInterface_route)
                API.RandomSleep2(1200, 300, 600)
                preRasial()
            end
        else
        ----print("Did not find start button. Trying again.")
        end
    else
      ----print("Did not find entrance... moving on")
      ----print(findNpcOrObject(127142, 50, 12), findNpcOrObject(126134, 50, 12))
    end    
end

local function needBank()
    local hp = API.GetHPrecent()
    local pray = API.GetPray_()
    local adren = API.GetAdrenalineFromInterface()
    if not checkInventoryItems({"overload", "brew", "blubber", "adrenaline", "excalibur"}) or hp < 100 or pray < 900 or adren < 100 then
        return true
    end
end

local function warsBank()
    local shouldContinue = true
    local hp = API.GetHPrecent()
    API.RandomSleep2(500, 300, 500)
    
    API.DoAction_Object1(0x33, API.OFF_ACT_GeneralObject_route3, {114750}, 50) -- QUICKLOAD
    API.RandomSleep2(1200, 300, 400)
    API.WaitUntilMovingEnds(1, 10)
    if hasBankPin then API.DoBankPin(PIN) end
    
    if not checkInventoryItems({"overload", "brew", "blubber", "adrenaline", "excalibur"}) then
        shouldContinue = false
        API.Write_LoopyLoop(false)
        return
    end
    
    while hp < 100 do  -- Sleeping to heal off damage
        API.RandomSleep2(600, 200, 400)
        hp = API.GetHPrecent()
    end
    
    if shouldContinue then
        if API.GetPray_() < 900 then
            API.DoAction_Object1(0x3d, API.OFF_ACT_GeneralObject_route0, {114748}, 50) -- Prayer renewal
            API.RandomSleep2(2400, 300, 600)
        end
        if API.GetAdrenalineFromInterface() < 100 then
            API.DoAction_Object1(0x29, API.OFF_ACT_GeneralObject_route0, {114749}, 50)
            while API.GetAdrenalineFromInterface() < 100 do
                API.RandomSleep2(600, 0, 0)
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
       ----print("You managed to die... (idiot), do we grab your things and go home?")
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

local function scriptStart()
    if not Inventory:IsOpen() then
        --print("Open the damn inventory, dude. I'm not gonna do everything for you. Whats next? You want me to click the buttons too? Maybe hold your hand while we sort potions? Come on, just pop it open and lets get this over with before I start charging an hourly rate. 5b still gonna ask whats wrong.")
        API.Write_LoopyLoop(false)
        return
    end
    API.DoAction_Object1(0x33, API.OFF_ACT_GeneralObject_route3, {114750}, 50) -- QUICKLOAD
    API.RandomSleep2(1200, 300, 400)
    API.WaitUntilMovingEnds(1, 10)
    checkInventoryItems({"overload", "brew", "blubber", "adrenaline", "excalibur"})
end

while API.Read_LoopyLoop() do
    API.SetMaxIdleTime(5)
    scriptStart()
    if API.Read_LoopyLoop() then
        deathCheck()
        DungeonEntrance()
        WhereTfAreWe()
        API.RandomSleep2(100, 100, 100)
    end
end
