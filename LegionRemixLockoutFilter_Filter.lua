-- LegionRemixLockoutFilter_Filter.lua
-- Search result post-filtering using activityIDs

local ADDON_NAME, ADDON_TABLE = ...

local LRLF_Filter = ADDON_TABLE.Filter or {}
ADDON_TABLE.Filter = LRLF_Filter

--------------------------------------------------
-- Filter a resultID list in-place based on current filter state
-- kind: "raid" or "dungeon"
--
-- Uses:
--   LRLF_FilterState[kind][instanceName][diffName] = true/false
--   LRLF_NormalizeName, LRLF_ClassifyDifficulty
--   LRLF_GetLegionRaids / LRLF_GetLegionDungeons
--
-- IMPORTANT:
--   * Uses info.activityIDs (plural) as the primary activity reference.
--   * Optionally hides WTS/BUY/SELL-style listings when LRLF_WTSFilterEnabled is true.
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

    -- Check if at least one difficulty is selected anywhere
    local anySelected = false
    for _, instState in pairs(filterKind) do
        if type(instState) == "table" then
            for _, v in pairs(instState) do
                if v then
                    anySelected = true
                    break
                end
            end
        end
        if anySelected then break end
    end

    -- If nothing selected, clear all results
    if not anySelected then
        for i = #results, 1, -1 do
            results[i] = nil
        end
        return
    end

    -- Build Legion instance list for this kind
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

    local function ResultMatchesSelection(resultID)
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

        -- Optional WTS filter: hide buy/sell/WTS listings by title.
        -- We:
        --   * lower-case the title
        --   * strip WoW color/texture codes
        --   * build "lettersOnly" (non-letters removed)
        --   * look for wts/buy/sell in either plain or lettersOnly
        if LRLF_WTSFilterEnabled ~= false then
            local title = (info.name or info.activityName or "")
            title = title:lower()

            -- Strip common markup: color codes and texture tags
            local plain = title
            plain = plain:gsub("|c%x%x%x%x%x%x%x%x", "")
            plain = plain:gsub("|r", "")
            plain = plain:gsub("|T.-|t", "")

            -- Remove everything that's not a–z to catch "w t s", "w{star}t{s}" etc.
            local lettersOnly = plain:gsub("[^a-z]", "")

            if plain:find("wts", 1, true)
                or lettersOnly:find("wts", 1, true)
                or plain:find("buy", 1, true)
                or lettersOnly:find("buy", 1, true)
                or plain:find("sell", 1, true)
                or lettersOnly:find("sell", 1, true)
            then
                return false
            end
        end

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

    -- In-place filtering using shift-down pattern
    local shift_down    = 0
    local original_size = #results

    for idx = 1, original_size do
        local id   = results[idx]
        local keep = ResultMatchesSelection(id)

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
