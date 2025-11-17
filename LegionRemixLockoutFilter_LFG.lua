-- LegionRemixLockoutFilter_LFG.lua
-- EJ + LFG integration and difficulty/lockout data

local ADDON_NAME, ADDON_TABLE = ...

-- Namespace table for LFG-related helpers
LRLF_LFG = ADDON_TABLE.LFG or {}
ADDON_TABLE.LFG = LRLF_LFG

--------------------------------------------------
-- Apply saved-instance lockouts onto a difficulty info map
--------------------------------------------------

local function LRLF_ApplyLockouts(infoMap, isRaidFlag)
    if not infoMap then return end
    if not GetNumSavedInstances or not GetSavedInstanceInfo then return end

    local num = GetNumSavedInstances()
    if not num or num <= 0 then return end

    local lockouts = {}
    for i = 1, num do
        local name, instanceID, reset, difficulty, locked, extended, _, isRaid = GetSavedInstanceInfo(i)
        if name and reset and reset > 0 and (locked or extended) and (isRaid == isRaidFlag) then
            local label = LRLF_MapSavedDifficultyToLabel(difficulty, isRaid)
            if label then
                table.insert(lockouts, {
                    normName = LRLF_NormalizeName(name),
                    diff     = label,
                    reset    = reset,
                })
            end
        end
    end

    if #lockouts == 0 then return end

    local normByName = {}
    for instName in pairs(infoMap) do
        normByName[instName] = LRLF_NormalizeName(instName)
    end

    for instName, entry in pairs(infoMap) do
        local instNorm = normByName[instName]
        if instNorm and entry.difficulties then
            for _, lock in ipairs(lockouts) do
                if lock.normName:find(instNorm, 1, true) or instNorm:find(lock.normName, 1, true) then
                    local d = entry.difficulties[lock.diff]
                    if d then
                        d.hasLockout = true
                        if not d.lockoutReset or lock.reset > d.lockoutReset then
                            d.lockoutReset = lock.reset
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------
-- Get Legion raids from the Encounter Journal
--------------------------------------------------

function LRLF_GetLegionRaids()
    local raids = {}

    if not EJ_GetInstanceByIndex or not EJ_SelectTier or not EJ_GetNumTiers or not EJ_GetTierInfo then
        return raids, "Encounter Journal API not available."
    end

    local legionTierIndex, tierErr = LRLF_FindLegionTierIndex()
    if not legionTierIndex then
        return raids, tierErr or "Could not find a Legion tier in the Encounter Journal."
    end

    EJ_SelectTier(legionTierIndex)

    local excludeByName = {
        ["Broken Isles"]    = true,
        ["Invasion Points"] = true,
    }

    local index = 1
    while true do
        local instanceID, name = EJ_GetInstanceByIndex(index, true) -- raids
        if not instanceID then
            break
        end

        if name and not excludeByName[name] then
            table.insert(raids, { id = instanceID, name = name })
        end

        index = index + 1
    end

    if #raids == 0 then
        return raids, "No raids found for the Legion tier."
    end

    return raids, nil
end

--------------------------------------------------
-- Get Legion dungeons from the Encounter Journal
--------------------------------------------------

function LRLF_GetLegionDungeons()
    local dungeons = {}

    if not EJ_GetInstanceByIndex or not EJ_SelectTier or not EJ_GetNumTiers or not EJ_GetTierInfo then
        return dungeons, "Encounter Journal API not available."
    end

    local legionTierIndex, tierErr = LRLF_FindLegionTierIndex()
    if not legionTierIndex then
        return dungeons, tierErr or "Could not find a Legion tier in the Encounter Journal."
    end

    EJ_SelectTier(legionTierIndex)

    local index = 1
    while true do
        local instanceID, name = EJ_GetInstanceByIndex(index, false) -- dungeons
        if not instanceID then
            break
        end

        if name then
            table.insert(dungeons, { id = instanceID, name = name })
        end

        index = index + 1
    end

    -- Return to Karazhan: inject Lower/Upper if needed
    if #dungeons > 0 then
        local karaID = nil
        local hasLower, hasUpper = false, false

        for _, d in ipairs(dungeons) do
            if d.name == "Return to Karazhan" then
                karaID = d.id
            elseif d.name == "Return to Karazhan: Lower" then
                hasLower = true
            elseif d.name == "Return to Karazhan: Upper" then
                hasUpper = true
            end
        end

        if karaID then
            if not hasLower then
                table.insert(dungeons, { id = karaID, name = "Return to Karazhan: Lower" })
            end
            if not hasUpper then
                table.insert(dungeons, { id = karaID, name = "Return to Karazhan: Upper" })
            end
        end
    end

    if #dungeons == 0 then
        return dungeons, "No dungeons found for the Legion tier."
    end

    return dungeons, nil
end

--------------------------------------------------
-- Difficulty classification
--
-- For raids:
--   Normal / Heroic / Mythic (unchanged)
--
-- For dungeons:
--   "Mythic"        = base Mythic (M0) with saved-instance lockouts
--   "MythicKeystone"= Mythic Keystone / Mythic+ (no lockouts)
--------------------------------------------------

function LRLF_ClassifyDifficulty(info)
    if not info then
        return nil
    end

    -- Prefer explicit flags if available
    if info.isMythicPlusActivity then
        return "MythicKeystone"
    end

    if info.isMythicActivity then
        -- Base Mythic raid or dungeon (M0)
        return "Mythic"
    end

    local id = info.difficultyID
    if id then
        if id == 16 or id == 23 then
            return "Mythic"
        elseif id == 15 or id == 2 then
            return "Heroic"
        elseif id == 14 or id == 1 then
            return "Normal"
        end
    end

    -- Fallback: use the name if it's not a protected string
    local name = info.fullName and info.fullName:lower() or ""
    if name:find("mythic keystone") or name:find("mythic%+") then
        return "MythicKeystone"
    elseif name:find("mythic") then
        return "Mythic"
    elseif name:find("heroic") then
        return "Heroic"
    elseif name:find("normal") then
        return "Normal"
    end

    return nil
end

--------------------------------------------------
-- Build per-raid availability info from LFGList
--------------------------------------------------

function LRLF_GetLegionRaidAvailability()
    local raids, basicErr = LRLF_GetLegionRaids()
    local byName = {}

    for _, r in ipairs(raids) do
        byName[r.name] = {
            id = r.id,
            activities = {},
        }
    end

    if basicErr and #raids == 0 then
        return byName, basicErr
    end

    if not C_LFGList
        or not C_LFGList.GetAvailableActivities
        or not C_LFGList.GetActivityInfoTable
    then
        return byName, "LFGList API not available."
    end

    local activities = C_LFGList.GetAvailableActivities()
    if not activities then
        return byName, "No LFG activities are currently available (nil returned)."
    end

    local searchKeys = {}
    for raidName in pairs(byName) do
        searchKeys[raidName] = LRLF_NormalizeName(raidName)
    end

    for _, activityID in ipairs(activities) do
        local info = C_LFGList.GetActivityInfoTable(activityID)
        if info and info.fullName then
            local fullNameNorm    = LRLF_NormalizeName(info.fullName)
            local difficultyLabel = LRLF_ClassifyDifficulty(info)

            for raidName, raidData in pairs(byName) do
                local key = searchKeys[raidName]
                if key and fullNameNorm:find(key, 1, true) then
                    table.insert(raidData.activities, {
                        activityID      = activityID,
                        fullName        = info.fullName,
                        categoryID      = info.categoryID,
                        groupID         = info.groupFinderActivityGroupID,
                        minLevel        = info.minLevel,
                        maxNumPlayers   = info.maxNumPlayers,
                        isMythic        = info.isMythicActivity,
                        isCurrentRaid   = info.isCurrentRaidActivity,
                        difficultyID    = info.difficultyID,
                        difficulty      = difficultyLabel,
                    })
                end
            end
        end
    end

    return byName, nil
end

--------------------------------------------------
-- Build per-dungeon availability info from LFGList
--------------------------------------------------

function LRLF_GetLegionDungeonAvailability()
    local dungeons, basicErr = LRLF_GetLegionDungeons()
    local byName = {}

    for _, d in ipairs(dungeons) do
        byName[d.name] = {
            id = d.id,
            activities = {},
        }
    end

    if basicErr and #dungeons == 0 then
        return byName, basicErr
    end

    if not C_LFGList
        or not C_LFGList.GetAvailableActivities
        or not C_LFGList.GetActivityInfoTable
    then
        return byName, "LFGList API not available."
    end

    local activities = C_LFGList.GetAvailableActivities()
    if not activities then
        return byName, "No LFG activities are currently available (nil returned)."
    end

    local searchKeys = {}
    for dungeonName in pairs(byName) do
        searchKeys[dungeonName] = LRLF_NormalizeName(dungeonName)
    end

    for _, activityID in ipairs(activities) do
        local info = C_LFGList.GetActivityInfoTable(activityID)
        if info and info.fullName then
            local fullNameNorm    = LRLF_NormalizeName(info.fullName)
            local difficultyLabel = LRLF_ClassifyDifficulty(info)

            for dungeonName, dungeonData in pairs(byName) do
                local key = searchKeys[dungeonName]
                if key and fullNameNorm:find(key, 1, true) then
                    table.insert(dungeonData.activities, {
                        activityID      = activityID,
                        fullName        = info.fullName,
                        categoryID      = info.categoryID,
                        groupID         = info.groupFinderActivityGroupID,
                        minLevel        = info.minLevel,
                        maxNumPlayers   = info.maxNumPlayers,
                        isMythic        = info.isMythicActivity,
                        isCurrentRaid   = info.isCurrentRaidActivity,
                        difficultyID    = info.difficultyID,
                        difficulty      = difficultyLabel,
                    })
                end
            end
        end
    end

    return byName, nil
end

--------------------------------------------------
-- Build per-raid per-difficulty info
--------------------------------------------------

function LRLF_BuildRaidDifficultyInfo()
    local raids, ejErr = LRLF_GetLegionRaids()
    local availability, lfgErr = LRLF_GetLegionRaidAvailability()

    local raidInfo = {}

    for _, raid in ipairs(raids) do
        local data = availability[raid.name]
        local acts = data and data.activities or {}

        local entry = {
            id = raid.id,
            name = raid.name,
            difficulties = {
                Normal = { available = false, activities = {} },
                Heroic = { available = false, activities = {} },
                Mythic = { available = false, activities = {} },
            },
        }

        for _, act in ipairs(acts) do
            local diff = act.difficulty
            if diff and entry.difficulties[diff] then
                table.insert(entry.difficulties[diff].activities, act)
                entry.difficulties[diff].available = true
            end
        end

        raidInfo[raid.name] = entry
    end

    LRLF_ApplyLockouts(raidInfo, true)

    return raidInfo, raids, ejErr, lfgErr
end

--------------------------------------------------
-- Build per-dungeon per-difficulty info
-- Dungeons care only about:
--   "Mythic"        = base Mythic (M0, with lockouts)
--   "MythicKeystone"= Mythic Keystone / Mythic+ (no lockouts)
--------------------------------------------------

function LRLF_BuildDungeonDifficultyInfo()
    local dungeons, ejErr = LRLF_GetLegionDungeons()
    local availability, lfgErr = LRLF_GetLegionDungeonAvailability()

    local dungeonInfo = {}

    for _, dungeon in ipairs(dungeons) do
        local data = availability[dungeon.name]
        local acts = data and data.activities or {}

        local diffs = {
            Mythic         = { available = false, activities = {} },
            MythicKeystone = { available = false, activities = {} },
        }

        local entry = {
            id = dungeon.id,
            name = dungeon.name,
            difficulties = diffs,
        }

        for _, act in ipairs(acts) do
            local diff = act.difficulty
            if diff and entry.difficulties[diff] then
                table.insert(entry.difficulties[diff].activities, act)
                entry.difficulties[diff].available = true
            end
        end

        dungeonInfo[dungeon.name] = entry
    end

    -- Apply lockouts only to Mythic (M0) where saved-instance data exists.
    LRLF_ApplyLockouts(dungeonInfo, false)

    return dungeonInfo, dungeons, ejErr, lfgErr
end

--------------------------------------------------
-- Namespace wrappers used by UI
--------------------------------------------------

function LRLF_LFG.BuildRaidDifficultyInfo()
    return LRLF_BuildRaidDifficultyInfo()
end

function LRLF_LFG.BuildDungeonDifficultyInfo()
    return LRLF_BuildDungeonDifficultyInfo()
end
