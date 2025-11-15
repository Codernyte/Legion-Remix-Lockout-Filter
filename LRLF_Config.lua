-- LRLF_Config.lua
-- Shared configuration and generic helpers for LRLF

local ADDON_NAME, ADDON_TABLE = ...

--------------------------------------------------
-- Static: Legion dungeon difficulty support
-- Describes which difficulties exist in general
-- for each Legion dungeon.
--------------------------------------------------

LEGION_DUNGEON_DIFFICULTIES = LEGION_DUNGEON_DIFFICULTIES or {
    -- Normal + Heroic + Mythic
    ["Black Rook Hold"]         = { Normal = true, Heroic = true, Mythic = true },
    ["Darkheart Thicket"]       = { Normal = true, Heroic = true, Mythic = true },
    ["Eye of Azshara"]          = { Normal = true, Heroic = true, Mythic = true },
    ["Halls of Valor"]          = { Normal = true, Heroic = true, Mythic = true },
    ["Neltharion's Lair"]       = { Normal = true, Heroic = true, Mythic = true },
    ["Vault of the Wardens"]    = { Normal = true, Heroic = true, Mythic = true },
    ["Maw of Souls"]            = { Normal = true, Heroic = true, Mythic = true },
    ["Assault on Violet Hold"]  = { Normal = true, Heroic = true, Mythic = true },

    -- Heroic + Mythic only (no Normal)
    ["Court of Stars"]              = { Heroic = true, Mythic = true },
    ["The Arcway"]                  = { Heroic = true, Mythic = true },
    ["Cathedral of Eternal Night"]  = { Heroic = true, Mythic = true },
    ["Seat of the Triumvirate"]     = { Heroic = true, Mythic = true },

    -- Return to Karazhan special handling:
    -- Mythic = full mega-dungeon
    -- Normal/Heroic = split Upper/Lower
    ["Return to Karazhan"]          = { Mythic = true },
    ["Return to Karazhan: Lower"]   = { Normal = true, Heroic = true },
    ["Return to Karazhan: Upper"]   = { Normal = true, Heroic = true },
}

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
    s = s:gsub("^the%s+", "")   -- strip leading "the "
    s = s:gsub("[:,%-]", "")    -- strip basic punctuation
    s = s:gsub("%s+", " ")      -- collapse repeated spaces
    return s
end

--------------------------------------------------
-- Helper: map saved-instance difficulty IDs to "Normal"/"Heroic"/"Mythic"
--------------------------------------------------

function LRLF_MapSavedDifficultyToLabel(difficultyID, isRaid)
    if not difficultyID then return nil end

    -- 5-man
    -- 1: 5-player (Normal)
    -- 2: 5-player (Heroic)
    -- 23: 5-player (Mythic)
    -- Raids
    -- 14: Normal
    -- 15: Heroic
    -- 16: Mythic

    if isRaid then
        if difficultyID == 14 then
            return "Normal"
        elseif difficultyID == 15 then
            return "Heroic"
        elseif difficultyID == 16 then
            return "Mythic"
        end
    else
        if difficultyID == 1 then
            return "Normal"
        elseif difficultyID == 2 then
            return "Heroic"
        elseif difficultyID == 23 then
            return "Mythic"
        end
    end

    -- Fallbacks, just in case
    if difficultyID == 14 or difficultyID == 1 or difficultyID == 3 or difficultyID == 4 then
        return "Normal"
    elseif difficultyID == 15 or difficultyID == 2 then
        return "Heroic"
    elseif difficultyID == 16 or difficultyID == 23 then
        return "Mythic"
    end

    return nil
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
