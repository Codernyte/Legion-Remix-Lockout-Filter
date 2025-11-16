-- LegionRemixLockoutFilter_Filter.lua
-- Search result post-filtering using activityIDs

local ADDON_NAME, ADDON_TABLE = ...

local LRLF_Filter = ADDON_TABLE.Filter or {}
ADDON_TABLE.Filter = LRLF_Filter

--------------------------------------------------
-- Local helpers
--------------------------------------------------

-- Returns true if any difficulty is selected for any instance
local function HasAnySelectedDifficulty(filterKind)
    if not filterKind then
        return false
    end

    for _, instState in pairs(filterKind) do
        if type(instState) == "table" then
            for _, v in pairs(instState) do
                if v then
                    return true
                end
            end
        end
    end

    return false
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
        -- Modern clients use activityIDs; treat single activityID as legacy fallback
        if info.activityID then
            activityIDs = { info.activityID }
        else
            return false
        end
    end

    -- OR across all activityIDs for this listing
    for _, activityID in ipairs(activityIDs) do
        local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
        if activityInfo and activityInfo.fullName then
            local diffLabel    = LRLF_ClassifyDifficulty(activityInfo)
            local fullNameNorm = LRLF_NormalizeName(activityInfo.fullName)

            if diffLabel then
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

    return false
end

--------------------------------------------------
-- Filter a resultID list in-place based on current filter state
-- kind: "raid" or "dungeon"
--
-- Uses:
--   LRLF_FilterState[kind][instanceName][diffName] = true/false
--   LRLF_NormalizeName, LRLF_ClassifyDifficulty
--   LRLF_GetLegionRaids / LRLF_GetLegionDungeons
--
-- IMPORTANT: Uses info.activityIDs (plural) as the primary activity reference.
--------------------------------------------------

function LRLF_Filter.FilterResults(results, kind)
    if not results or type(results) ~= "table" or #results == 0 then
        return
    end
    if not LRLF_FilterState or not kind then
        return
    end

    local filterKind = LRLF_FilterState[kind]
    if not filterKind then
        return
    end

    --------------------------------------------------
    -- Check if at least one difficulty is selected anywhere
    --------------------------------------------------
    local anySelected = HasAnySelectedDifficulty(filterKind)

    -- If nothing selected, clear all results
    if not anySelected then
        for i = #results, 1, -1 do
            results[i] = nil
        end
        return
    end

    --------------------------------------------------
    -- Build Legion instance list for this kind
    --------------------------------------------------
    local instances = BuildInstanceIndex(kind)

    --------------------------------------------------
    -- In-place filtering using shift-down pattern
    --------------------------------------------------
    local shift_down    = 0
    local original_size = #results

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
end

--------------------------------------------------
-- Global wrapper so other modules can call filtering
-- without depending on ADDON_TABLE wiring quirks.
--------------------------------------------------
function LRLF_FilterResults(results, kind)
    return LRLF_Filter.FilterResults(results, kind)
end
