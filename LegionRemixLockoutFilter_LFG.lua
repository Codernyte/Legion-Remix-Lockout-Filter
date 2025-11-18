-- LegionRemixLockoutFilter_LFG.lua
-- EJ + LFG integration and difficulty/lockout data

local ADDON_NAME, ADDON_TABLE = ...

-- Namespace table for LFG-related helpers
LRLF_LFG = ADDON_TABLE.LFG or {}
ADDON_TABLE.LFG = LRLF_LFG

--------------------------------------------------
-- Local debug helper
--------------------------------------------------

local function DebugLog(msg)
    if type(LRLF_DebugLog) == "function" then
        LRLF_DebugLog(msg)
    end
end

--------------------------------------------------
-- Shared EJ helper: select Legion tier
--------------------------------------------------

local function LRLF_SelectLegionTier()
    if not EJ_GetInstanceByIndex or not EJ_SelectTier or not EJ_GetNumTiers or not EJ_GetTierInfo then
        DebugLog("LRLF_SelectLegionTier: Encounter Journal API not available.")
        return false, "Encounter Journal API not available."
    end

    local legionTierIndex, tierErr = LRLF_FindLegionTierIndex()
    if not legionTierIndex then
        DebugLog("LRLF_SelectLegionTier: Could not find Legion tier: " .. (tierErr or "unknown reason"))
        return false, tierErr or "Could not find a Legion tier in the Encounter Journal."
    end

    EJ_SelectTier(legionTierIndex)
    DebugLog("LRLF_SelectLegionTier: Selected Legion tier index " .. tostring(legionTierIndex))
    return true, nil
end

--------------------------------------------------
-- Caches (per session) for static EJ/LFG data
--------------------------------------------------

local cachedRaids, cachedRaidsErr
local cachedDungeons, cachedDungeonsErr
local cachedRaidAvailability, cachedRaidAvailabilityErr
local cachedDungeonAvailability, cachedDungeonAvailabilityErr

--------------------------------------------------
-- Apply saved-instance lockouts onto a difficulty info map
--------------------------------------------------

local function LRLF_ApplyLockouts(infoMap, isRaidFlag)
    if not infoMap then return end
    if not GetNumSavedInstances or not GetSavedInstanceInfo then return end

    local num = GetNumSavedInstances()
    if not num or num <= 0 then
        DebugLog("LRLF_ApplyLockouts: No saved instances found (isRaid=" .. tostring(isRaidFlag) .. ").")
        return
    end

    DebugLog("LRLF_ApplyLockouts: Scanning " .. tostring(num) .. " saved instances (isRaid=" .. tostring(isRaidFlag) .. ").")

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

    DebugLog("LRLF_ApplyLockouts: Found " .. tostring(#lockouts) .. " relevant lockouts.")

    if #lockouts == 0 then return end

    local normByName = {}
    for instName in pairs(infoMap) do
        normByName[instName] = LRLF_NormalizeName(instName)
    end

    local appliedCount = 0

    for instName, entry in pairs(infoMap) do
        local instNorm = normByName[instName]
        if instNorm and entry.difficulties then
            for _, lock in ipairs(lockouts) do
                if lock.normName:find(instNorm, 1, true) or instNorm:find(lock.normName, 1, true) then
                    local d = entry.difficulties[lock.diff]
                    if d then
                        appliedCount = appliedCount + 1
                        d.hasLockout = true
                        if not d.lockoutReset or lock.reset > d.lockoutReset then
                            d.lockoutReset = lock.reset
                        end
                    end
                end
            end
        end
    end

    DebugLog("LRLF_ApplyLockouts: Applied lockouts to " .. tostring(appliedCount) .. " difficulty entries.")
end

--------------------------------------------------
-- Get Legion raids from the Encounter Journal
-- (cached per login; raids are static for the session)
--------------------------------------------------

function LRLF_GetLegionRaids()
    if cachedRaids then
        return cachedRaids, cachedRaidsErr
    end

    local raids = {}

    DebugLog("LRLF_GetLegionRaids: Starting raid discovery.")
    local ok, err = LRLF_SelectLegionTier()
    if not ok then
        DebugLog("LRLF_GetLegionRaids: Failed to select Legion tier: " .. tostring(err))
        cachedRaids = raids
        cachedRaidsErr = err
        return raids, err
    end

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
        DebugLog("LRLF_GetLegionRaids: No raids found for the Legion tier.")
        cachedRaids = raids
        cachedRaidsErr = "No raids found for the Legion tier."
        return raids, cachedRaidsErr
    end

    DebugLog("LRLF_GetLegionRaids: Found " .. tostring(#raids) .. " Legion raids.")
    cachedRaids = raids
    cachedRaidsErr = nil
    return raids, nil
end

--------------------------------------------------
-- Get Legion dungeons from the Encounter Journal
-- (cached per login; dungeons are static for the session)
--------------------------------------------------

function LRLF_GetLegionDungeons()
    if cachedDungeons then
        return cachedDungeons, cachedDungeonsErr
    end

    local dungeons = {}

    DebugLog("LRLF_GetLegionDungeons: Starting dungeon discovery.")
    local ok, err = LRLF_SelectLegionTier()
    if not ok then
        DebugLog("LRLF_GetLegionDungeons: Failed to select Legion tier: " .. tostring(err))
        cachedDungeons = dungeons
        cachedDungeonsErr = err
        return dungeons, err
    end

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
                DebugLog("LRLF_GetLegionDungeons: Injecting 'Return to Karazhan: Lower'.")
                table.insert(dungeons, { id = karaID, name = "Return to Karazhan: Lower" })
            end
            if not hasUpper then
                DebugLog("LRLF_GetLegionDungeons: Injecting 'Return to Karazhan: Upper'.")
                table.insert(dungeons, { id = karaID, name = "Return to Karazhan: Upper" })
            end
        end
    end

    if #dungeons == 0 then
        DebugLog("LRLF_GetLegionDungeons: No dungeons found for the Legion tier.")
        cachedDungeons = dungeons
        cachedDungeonsErr = "No dungeons found for the Legion tier."
        return dungeons, cachedDungeonsErr
    end

    DebugLog("LRLF_GetLegionDungeons: Found " .. tostring(#dungeons) .. " Legion dungeons.")
    cachedDungeons = dungeons
    cachedDungeonsErr = nil
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

    DebugLog("LRLF_ClassifyDifficulty: Could not classify difficulty for activity '" .. (info.fullName or ("ID " .. tostring(info.activityID or "?"))) .. "'.")
    return nil
end

--------------------------------------------------
-- Build per-raid availability info from LFGList
-- (cached per login; activity definitions are static per character)
--------------------------------------------------

function LRLF_GetLegionRaidAvailability()
    if cachedRaidAvailability then
        return cachedRaidAvailability, cachedRaidAvailabilityErr
    end

    DebugLog("LRLF_GetLegionRaidAvailability: Building raid availability map.")

    local raids, basicErr = LRLF_GetLegionRaids()
    local byName = {}

    for _, r in ipairs(raids) do
        byName[r.name] = {
            id         = r.id,
            activities = {},
        }
    end

    if basicErr and #raids == 0 then
        DebugLog("LRLF_GetLegionRaidAvailability: Early error (no raids): " .. tostring(basicErr))
        cachedRaidAvailability = byName
        cachedRaidAvailabilityErr = basicErr
        return byName, basicErr
    end

    if not C_LFGList
        or not C_LFGList.GetAvailableActivities
        or not C_LFGList.GetActivityInfoTable
    then
        DebugLog("LRLF_GetLegionRaidAvailability: LFGList API not available.")
        cachedRaidAvailability = byName
        cachedRaidAvailabilityErr = "LFGList API not available."
        return byName, cachedRaidAvailabilityErr
    end

    local activities = C_LFGList.GetAvailableActivities()
    if not activities then
        DebugLog("LRLF_GetLegionRaidAvailability: GetAvailableActivities() returned nil.")
        cachedRaidAvailability = byName
        cachedRaidAvailabilityErr = "No LFG activities are currently available (nil returned)."
        return byName, cachedRaidAvailabilityErr
    end

    DebugLog("LRLF_GetLegionRaidAvailability: Found " .. tostring(#activities) .. " total LFG activities.")

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

    for raidName, raidData in pairs(byName) do
        DebugLog(("LRLF_GetLegionRaidAvailability: %s -> %d activities."):format(raidName, #raidData.activities))
    end

    cachedRaidAvailability = byName
    cachedRaidAvailabilityErr = basicErr
    return byName, basicErr
end

--------------------------------------------------
-- Build per-dungeon availability info from LFGList
-- (cached per login; activity definitions are static per character)
--------------------------------------------------

function LRLF_GetLegionDungeonAvailability()
    if cachedDungeonAvailability then
        return cachedDungeonAvailability, cachedDungeonAvailabilityErr
    end

    DebugLog("LRLF_GetLegionDungeonAvailability: Building dungeon availability map.")

    local dungeons, basicErr = LRLF_GetLegionDungeons()
    local byName = {}

    for _, d in ipairs(dungeons) do
        byName[d.name] = {
            id         = d.id,
            activities = {},
        }
    end

    if basicErr and #dungeons == 0 then
        DebugLog("LRLF_GetLegionDungeonAvailability: Early error (no dungeons): " .. tostring(basicErr))
        cachedDungeonAvailability = byName
        cachedDungeonAvailabilityErr = basicErr
        return byName, basicErr
    end

    if not C_LFGList
        or not C_LFGList.GetAvailableActivities
        or not C_LFGList.GetActivityInfoTable
    then
        DebugLog("LRLF_GetLegionDungeonAvailability: LFGList API not available.")
        cachedDungeonAvailability = byName
        cachedDungeonAvailabilityErr = "LFGList API not available."
        return byName, cachedDungeonAvailabilityErr
    end

    local activities = C_LFGList.GetAvailableActivities()
    if not activities then
        DebugLog("LRLF_GetLegionDungeonAvailability: GetAvailableActivities() returned nil.")
        cachedDungeonAvailability = byName
        cachedDungeonAvailabilityErr = "No LFG activities are currently available (nil returned)."
        return byName, cachedDungeonAvailabilityErr
    end

    DebugLog("LRLF_GetLegionDungeonAvailability: Found " .. tostring(#activities) .. " total LFG activities.")

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

    for dungeonName, dungeonData in pairs(byName) do
        DebugLog(("LRLF_GetLegionDungeonAvailability: %s -> %d activities."):format(dungeonName, #dungeonData.activities))
    end

    cachedDungeonAvailability = byName
    cachedDungeonAvailabilityErr = basicErr
    return byName, basicErr
end

--------------------------------------------------
-- Build per-raid per-difficulty info
--------------------------------------------------

function LRLF_BuildRaidDifficultyInfo()
    DebugLog("LRLF_BuildRaidDifficultyInfo: Building raid difficulty info.")

    local raids, ejErr             = LRLF_GetLegionRaids()
    local availability, lfgErr     = LRLF_GetLegionRaidAvailability()
    local raidInfo                 = {}

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
    DebugLog(("LRLF_BuildRaidDifficultyInfo: Completed. raids=%d, ejErr=%s, lfgErr=%s")
        :format(#raids, tostring(ejErr), tostring(lfgErr)))

    return raidInfo, raids, ejErr, lfgErr
end

--------------------------------------------------
-- Build per-dungeon per-difficulty info
-- Dungeons care only about:
--   "Mythic"        = base Mythic (M0, with lockouts)
--   "MythicKeystone"= Mythic Keystone / Mythic+ (no lockouts)
--------------------------------------------------

function LRLF_BuildDungeonDifficultyInfo()
    DebugLog("LRLF_BuildDungeonDifficultyInfo: Building dungeon difficulty info.")

    local dungeons, ejErr          = LRLF_GetLegionDungeons()
    local availability, lfgErr     = LRLF_GetLegionDungeonAvailability()
    local dungeonInfo              = {}

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
    DebugLog(("LRLF_BuildDungeonDifficultyInfo: Completed. dungeons=%d, ejErr=%s, lfgErr=%s")
        :format(#dungeons, tostring(ejErr), tostring(lfgErr)))

    return dungeonInfo, dungeons, ejErr, lfgErr
end

--------------------------------------------------
-- Namespace wrappers used by UI
--------------------------------------------------

LRLF_LFG.BuildRaidDifficultyInfo    = LRLF_BuildRaidDifficultyInfo
LRLF_LFG.BuildDungeonDifficultyInfo = LRLF_BuildDungeonDifficultyInfo
