-- LegionRemixLockoutFilter_Filter.lua
-- Search result post-filtering using activityIDs

local ADDON_NAME, ADDON_TABLE = ...

local LRLF_Filter = ADDON_TABLE.Filter or {}
ADDON_TABLE.Filter = LRLF_Filter

--------------------------------------------------
-- Local debug helper (no-op if LRLF_DebugLog is missing)
--------------------------------------------------

local function DebugLog(msg)
    if type(LRLF_DebugLog) == "function" then
        LRLF_DebugLog(msg)
    end
end

--------------------------------------------------
-- Local helpers
--------------------------------------------------

-- Returns true if any difficulty is selected for any instance.
-- If modeKey is provided, only that difficulty key is considered.
local function HasAnySelectedDifficulty(filterKind, modeKey)
    if not filterKind then
        return false
    end

    for _, instState in pairs(filterKind) do
        if type(instState) == "table" then
            if modeKey then
                if instState[modeKey] then
                    return true
                end
            else
                for _, v in pairs(instState) do
                    if v then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- Normalize dungeon mode for filtering:
--   "Mythic"         -> "Mythic"
--   "MYTHIC"         -> "Mythic"
--   "KEYSTONE"       -> "MythicKeystone"
--   "MythicKeystone" -> "MythicKeystone"
--   "Mythic Keystone"-> "MythicKeystone"
local function GetDungeonModeKey()
    local mode = LRLF_DungeonMode

    if mode == "KEYSTONE"
        or mode == "MythicKeystone"
        or mode == "Mythic Keystone"
    then
        return "MythicKeystone"
    end

    -- Default anything else to plain Mythic
    return "Mythic"
end

-- Build a normalized index of Legion instances for this kind
-- kind: "raid" or "dungeon"
local function BuildInstanceIndex(kind)
    local instanceList

    if kind == "dungeon" then
        instanceList = select(1, LRLF_GetLegionDungeons())
    else
        instanceList = select(1, LRLF_GetLegionRaids())
    end

    local instances = {}
    if instanceList then
        for _, inst in ipairs(instanceList) do
            table.insert(instances, {
                name = inst.name,
                key  = LRLF_NormalizeName(inst.name),
            })
        end
    end

    return instances
end

-- Check whether this search result matches the current selection
local function ResultMatchesSelection(resultID, kind, filterKind, instances)
    if not C_LFGList
        or not C_LFGList.GetSearchResultInfo
        or not C_LFGList.GetActivityInfoTable
    then
        return false
    end

    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info then
        return false
    end

    --------------------------------------------------
    -- activityIDs-first rule
    --------------------------------------------------
    local activityIDs = info.activityIDs
    if not activityIDs or type(activityIDs) ~= "table" or #activityIDs == 0 then
        -- Legacy fallback
        if info.activityID then
            activityIDs = { info.activityID }
        else
            return false
        end
    end

    local dungeonMode = nil
    if kind == "dungeon" then
        dungeonMode = GetDungeonModeKey()  -- "Mythic" or "MythicKeystone"
    end

    -- OR across all activityIDs for this listing
    for _, activityID in ipairs(activityIDs) do
        local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
        if activityInfo and activityInfo.fullName then
            local diffLabel    = LRLF_ClassifyDifficulty(activityInfo) -- "Mythic" / "MythicKeystone" / etc
            local fullNameNorm = LRLF_NormalizeName(activityInfo.fullName)

            if diffLabel then
                -- Dungeons: only consider activities matching the current mode
                if dungeonMode and diffLabel ~= dungeonMode then
                    -- skip
                else
                    for _, inst in ipairs(instances) do
                        if fullNameNorm:find(inst.key, 1, true) then
                            local instState = filterKind[inst.name]
                            if instState and instState[diffLabel] then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

--------------------------------------------------
-- Filter a resultID list in-place based on current filter state
-- kind: "raid" or "dungeon"
--------------------------------------------------

function LRLF_Filter.FilterResults(results, kind)
    local kindLabel = kind or "unknown"

    if not results or type(results) ~= "table" or #results == 0 then
        DebugLog(string.format("Filter: kind=%s – no results passed to filter.", kindLabel))
        return
    end
    if not LRLF_FilterState or not kind then
        DebugLog(string.format("Filter: kind=%s – missing LRLF_FilterState or kind; aborting.", kindLabel))
        return
    end

    local filterKind = LRLF_FilterState[kind]
    if not filterKind then
        DebugLog(string.format("Filter: kind=%s – no filterKind for this kind; aborting.", kindLabel))
        return
    end

    local original_size = #results
    local modeKey       = (kind == "dungeon") and GetDungeonModeKey() or nil
    local anySelected   = HasAnySelectedDifficulty(filterKind, modeKey)

    DebugLog(string.format(
        "Filter: start – kind=%s, modeKey=%s, original=%d, anySelected=%s",
        kindLabel,
        modeKey or "-",
        original_size,
        anySelected and "true" or "false"
    ))

    -- If nothing selected, clear all results
    if not anySelected then
        for i = #results, 1, -1 do
            results[i] = nil
        end
        DebugLog(string.format(
            "Filter: kind=%s – no difficulties selected; cleared all %d results.",
            kindLabel,
            original_size
        ))
        return
    end

    --------------------------------------------------
    -- Build Legion instance list for this kind
    --------------------------------------------------
    local instances = BuildInstanceIndex(kind)
    local instanceCount = instances and #instances or 0
    DebugLog(string.format(
        "Filter: kind=%s – built instance index with %d entries.",
        kindLabel,
        instanceCount
    ))

    --------------------------------------------------
    -- In-place filtering using shift-down pattern
    --------------------------------------------------
    local shift_down = 0

    for idx = 1, original_size do
        local id   = results[idx]
        local keep = ResultMatchesSelection(id, kind, filterKind, instances)

        if keep then
            if shift_down > 0 then
                results[idx - shift_down] = id
            end
        else
            shift_down = shift_down + 1
        end
    end

    if shift_down > 0 then
        for idx = original_size - shift_down + 1, original_size do
            results[idx] = nil
        end
    end

    local finalCount  = #results
    local removedCount = original_size - finalCount

    DebugLog(string.format(
        "Filter: done – kind=%s, modeKey=%s, kept=%d, removed=%d (from %d).",
        kindLabel,
        modeKey or "-",
        finalCount,
        removedCount,
        original_size
    ))
end

--------------------------------------------------
-- Global wrapper
--------------------------------------------------
function LRLF_FilterResults(results, kind)
    return LRLF_Filter.FilterResults(results, kind)
end
