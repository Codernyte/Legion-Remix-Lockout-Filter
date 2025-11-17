-- LRLF_Config.lua
-- Shared configuration and generic helpers for LRLF

local ADDON_NAME, ADDON_TABLE = ...

--------------------------------------------------
-- Config namespace (optional convenience)
--------------------------------------------------

ADDON_TABLE.Config = ADDON_TABLE.Config or {}
local Config = ADDON_TABLE.Config

--------------------------------------------------
-- Helper: format time from seconds as "Xd Yh Zm"
--------------------------------------------------

function LRLF_FormatTimeRemaining(seconds)
    if not seconds or seconds <= 0 then
        return "0m"
    end

    local days = math.floor(seconds / 86400)
    seconds = seconds % 86400
    local hours = math.floor(seconds / 3600)
    seconds = seconds % 3600
    local mins = math.floor(seconds / 60)

    local parts = {}
    if days > 0 then table.insert(parts, days .. "d") end
    if hours > 0 then table.insert(parts, hours .. "h") end
    if mins > 0 or #parts == 0 then table.insert(parts, mins .. "m") end

    return table.concat(parts, " ")
end

--------------------------------------------------
-- Helper: normalize a name across EJ/LFG/lockouts
--------------------------------------------------

function LRLF_NormalizeName(s)
    if not s then return "" end
    s = s:lower()
    s = s:gsub("^%s*(.-)%s*$", "%1")  -- trim whitespace
    s = s:gsub("^the%s+", "")        -- strip leading "the "
    s = s:gsub("[:,%-]", "")         -- strip basic punctuation
    s = s:gsub("%s+", " ")           -- collapse repeated spaces

    --------------------------------------------------
    -- Special handling for Karazhan Lower/Upper names
    -- Goal: make these equivalent:
    --   "Return to Karazhan: Lower"
    --   "Return to Karazhan Lower"
    --   "Lower Karazhan"
    --
    -- All should normalize to "karazhan lower"
    -- Similarly for Upper -> "karazhan upper"
    --------------------------------------------------
    if s:find("karazhan") then
        if s:find("lower") then
            s = "karazhan lower"
        elseif s:find("upper") then
            s = "karazhan upper"
        end
    end

    return s
end

--------------------------------------------------
-- Helper: map saved-instance difficulty IDs to "Normal"/"Heroic"/"Mythic"
--------------------------------------------------

-- Primary mappings
local RAID_DIFF_LABELS = {
    [14] = "Normal",  -- Raid Normal
    [15] = "Heroic",  -- Raid Heroic
    [16] = "Mythic",  -- Raid Mythic
}

local DUNGEON_DIFF_LABELS = {
    [1]  = "Normal",  -- 5-player Normal
    [2]  = "Heroic",  -- 5-player Heroic
    [23] = "Mythic",  -- 5-player Mythic
}

-- Fallback mappings (same as original logic)
local FALLBACK_DIFF_LABELS = {
    [1]  = "Normal",
    [2]  = "Heroic",
    [3]  = "Normal",
    [4]  = "Normal",
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [23] = "Mythic",
}

function LRLF_MapSavedDifficultyToLabel(difficultyID, isRaid)
    if not difficultyID then
        return nil
    end

    if isRaid then
        local label = RAID_DIFF_LABELS[difficultyID]
        if label then
            return label
        end
    else
        local label = DUNGEON_DIFF_LABELS[difficultyID]
        if label then
            return label
        end
    end

    -- Fallbacks, just in case (unchanged semantics)
    return FALLBACK_DIFF_LABELS[difficultyID]
end

--------------------------------------------------
-- Helper: find the Legion tier index in the Encounter Journal
-- Returns:
--   legionTierIndex, nil           on success
--   nil, "error message string"    on failure
--------------------------------------------------

function LRLF_FindLegionTierIndex()
    if not EJ_GetNumTiers or not EJ_GetTierInfo then
        return nil, "Encounter Journal API not available."
    end

    local numTiers = EJ_GetNumTiers() or 0
    local legionTierIndex = nil

    for i = 1, numTiers do
        local tierName = EJ_GetTierInfo(i)
        local nameOnly = tierName
        if type(tierName) == "table" then
            nameOnly = tierName[1]
        end

        if nameOnly and tostring(nameOnly):find("Legion") then
            legionTierIndex = i
            break
        end
    end

    -- Fallback: Legion is tier 7 on live DF/early TWW
    if not legionTierIndex then
        if numTiers >= 7 then
            legionTierIndex = 7
        else
            return nil, "Could not find a Legion tier in the Encounter Journal."
        end
    end

    return legionTierIndex, nil
end
