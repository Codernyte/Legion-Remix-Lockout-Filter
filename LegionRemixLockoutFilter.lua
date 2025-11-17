-- LegionRemixLockoutFilter.lua
-- Main wiring, state, events, Timerunner gating

local ADDON_NAME, ADDON_TABLE = ...

-- Modules (looked up lazily where needed)
local LRLF_LFG = ADDON_TABLE.LFG or {}

--------------------------------------------------
-- Slash command stub (infra only, no behavior yet)
--------------------------------------------------

SLASH_LRLFDEBUG1 = "/lrlfd"
SlashCmdList["LRLFDEBUG"] = function(msg)
    -- Reserved for future debug or commands
end

--------------------------------------------------
-- Global state shared across modules
--------------------------------------------------

LRLF_UserCollapsed         = LRLF_UserCollapsed         or false
LRLF_ToggleButton          = LRLF_ToggleButton          or nil
LRLF_LFGHooksDone          = LRLF_LFGHooksDone          or false
LRLF_ResultListHookDone    = LRLF_ResultListHookDone    or false

LRLF_FilterState           = LRLF_FilterState           or { raid = {}, dungeon = {} }
LRLF_SystemSelection       = LRLF_SystemSelection       or { raid = {}, dungeon = {} }
LRLF_Rows                  = LRLF_Rows                  or { raid = {}, dungeon = {} }

-- Right-hand icon strip: spyglass + settings (one-click toggle)
LRLF_FilterButtons         = LRLF_FilterButtons         or { apply = nil, bg = nil, settings = nil }
LRLF_FilterEnabled         = (LRLF_FilterEnabled ~= false) -- default true
LRLF_SearchButton          = LRLF_SearchButton          or nil

-- One-click signup toggle (settings icon controls this elsewhere)
LRLF_OneClickSignupEnabled = (LRLF_OneClickSignupEnabled == true)

-- Dungeon mode: "Mythic" (M0) or "MythicKeystone" (Mythic+)
LRLF_DungeonMode           = LRLF_DungeonMode or "Mythic"

-- Kept for possible future use with search button
LRLF_LastSearchWasFiltered = LRLF_LastSearchWasFiltered or false

--------------------------------------------------
-- Shared helper: update the "All" checkbox from per-difficulty state
--------------------------------------------------

function LRLF_UpdateRowAllCheckbox(row, instState)
    if not row or not row.allCheck then
        return
    end

    local anyTrue = false
    if instState then
        for _, v in pairs(instState) do
            if v then
                anyTrue = true
                break
            end
        end
    end

    row.allCheck:SetChecked(anyTrue)
end

--------------------------------------------------
-- Global override: exclusive raid instance selection by name
-- Right-clicking the raid name should:
--   * Clear all existing raid selections
--   * Select ONLY "ready" difficulties for that instance
--   * Never auto-select locked difficulties
--   * Never auto-select unavailable difficulties
--------------------------------------------------

function LRLF_ExclusiveRaidInstanceAllDiffs(row)
    if not row or row.kind ~= "raid" or not row.instanceName then
        return
    end

    local kind     = "raid"
    local instName = row.instanceName

    LRLF_FilterState[kind]     = LRLF_FilterState[kind]     or {}
    LRLF_SystemSelection[kind] = LRLF_SystemSelection[kind] or {}

    local filterKind = LRLF_FilterState[kind]
    local sysKind    = LRLF_SystemSelection[kind]

    -- Clear all existing raid selections first
    for otherInstName, instState in pairs(filterKind) do
        if type(instState) == "table" then
            local sysInst = sysKind[otherInstName] or {}
            sysKind[otherInstName] = sysInst

            for diffName in pairs(instState) do
                instState[diffName] = false
                sysInst[diffName]   = false -- mark as user-owned so system won't auto-restore
            end
        end
    end

    -- Ensure tables exist for the clicked instance
    filterKind[instName] = filterKind[instName] or {}
    sysKind[instName]    = sysKind[instName]    or {}

    local instState = filterKind[instName]
    local sysInst   = sysKind[instName]

    -- We only care about these three raid diffs
    local DIFF_ORDER = { "Normal", "Heroic", "Mythic" }

    for _, diffName in ipairs(DIFF_ORDER) do
        local status = row.diffStatus and row.diffStatus[diffName]
        local isReady       = status and status.isReady
        local isLocked      = status and status.isLocked
        local isUnavailable = status and status.isUnavailable

        -- Only auto-select "ready" difficulties.
        -- Locked or unavailable ones remain unselected.
        if isReady and not isLocked and not isUnavailable then
            instState[diffName] = true
        else
            instState[diffName] = false
        end

        -- Mark as user-managed so the system won't overwrite it later.
        sysInst[diffName] = false
    end

    -- Refresh the raid side panel to reflect the new selection
    LRLF_RefreshSidePanelText(kind)
end

--------------------------------------------------
-- Timerunner check
--------------------------------------------------

function LRLF_IsTimerunner()
    if type(PlayerGetTimerunningSeasonID) == "function" then
        local season = PlayerGetTimerunningSeasonID()
        if season and season ~= 0 then
            return true
        end
    end
    return false
end

--------------------------------------------------
-- Utility: hide panel, toggle, and icons, reset collapse
--------------------------------------------------

function LRLF_HideAll()
    LRLF_UserCollapsed = false
    if LRLFFrame then LRLFFrame:Hide() end
    if LRLF_ToggleButton then LRLF_ToggleButton:Hide() end
    if LRLF_FilterButtons.apply then LRLF_FilterButtons.apply:Hide() end
    if LRLF_FilterButtons.settings then LRLF_FilterButtons.settings:Hide() end
    if LRLF_FilterButtons.bg then LRLF_FilterButtons.bg:Hide() end
end

--------------------------------------------------
-- LFG hooks for show/hide & result-list filtering
--------------------------------------------------

function LRLF_TryHookLFG()
    if LFGListFrame and not LRLF_LFGHooksDone then
        LFGListFrame:HookScript("OnShow", function()
            LRLF_UpdateVisibility()
        end)
        LFGListFrame:HookScript("OnHide", function()
            LRLF_UpdateVisibility()
        end)
        LRLF_LFGHooksDone = true
    end

    -- Hook the Blizzard results updater so that ANY time Blizzard
    -- refreshes the results (including after a signup), we re-apply
    -- our lockout filtering *in place* without triggering a new search.
    if not LRLF_ResultListHookDone
        and type(LFGListSearchPanel_UpdateResultList) == "function"
    then
        LRLF_ResultListHookDone = true

        hooksecurefunc("LFGListSearchPanel_UpdateResultList", function(panel)
            -- Only operate:
            --  * On Timerunner characters
            --  * When our filter is enabled
            --  * On the main LFG search panel for raids/dungeons
            if not LRLF_IsTimerunner or not LRLF_IsTimerunner() then
                return
            end
            if not LRLF_FilterEnabled then
                return
            end
            if not LFGListFrame or not LFGListFrame.SearchPanel then
                return
            end
            if panel ~= LFGListFrame.SearchPanel then
                return
            end

            local categoryID = panel.categoryID
            local kind = (categoryID == 2 and "dungeon")
                      or (categoryID == 3 and "raid")
                      or nil
            if not kind then
                return
            end

            local results = panel.results
            if not results or type(results) ~= "table" then
                return
            end

            if type(LRLF_FilterResults) ~= "function" then
                return
            end

            -- Re-apply our filter to whatever Blizzard just gave us.
            LRLF_FilterResults(results, kind)
            panel.totalResults = #results

            -- Update the visual list ONLY; do NOT trigger a new search.
            if type(LFGListSearchPanel_UpdateResults) == "function" then
                LFGListSearchPanel_UpdateResults(panel)
            end
        end)
    end
end

--------------------------------------------------
-- Visibility logic for the side panel and toggle tab
--------------------------------------------------

function LRLF_UpdateVisibility()
    if not LRLF_IsTimerunner() then
        LRLF_HideAll()
        return
    end

    if not LFGListFrame then
        LRLF_HideAll()
        return
    end

    LRLF_TryHookLFG()

    if not LFGListFrame:IsShown() then
        LRLF_HideAll()
        return
    end

    local searchPanel = LFGListFrame.SearchPanel
    local categoryID  = searchPanel and searchPanel.categoryID
    local isDungeon   = (categoryID == 2)
    local isRaid      = (categoryID == 3)
    local isDungeonOrRaid = isDungeon or isRaid

    local premadeSearchActive =
        searchPanel
        and searchPanel:IsShown()
        and isDungeonOrRaid

    if not premadeSearchActive then
        LRLF_HideAll()
        return
    end

    local kind = isDungeon and "dungeon" or "raid"

    LRLF_AttachToPremade()
    if not LRLF_ToggleButton then
        LRLF_CreateToggleButton()
    end

    if LRLF_UserCollapsed then
        if LRLFFrame then LRLFFrame:Hide() end
        if LRLF_ToggleButton then LRLF_ToggleButton:Show() end
        if LRLF_FilterButtons.apply then LRLF_FilterButtons.apply:Hide() end
        if LRLF_FilterButtons.settings then LRLF_FilterButtons.settings:Hide() end
        if LRLF_FilterButtons.bg then LRLF_FilterButtons.bg:Hide() end
    else
        if LRLFFrame then
            LRLFFrame:Show()
            LRLF_RefreshSidePanelText(kind)
        end
        if LRLF_ToggleButton then LRLF_ToggleButton:Hide() end
        if LRLF_FilterButtons.apply then LRLF_FilterButtons.apply:Show() end
        if LRLF_FilterButtons.settings then LRLF_FilterButtons.settings:Show() end
        if LRLF_FilterButtons.bg then LRLF_FilterButtons.bg:Show() end
    end
end

--------------------------------------------------
-- Event handler
--------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
eventFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if not LRLF_IsTimerunner() then
            print("|cff00ff00[LegionRemixLockoutFilter]|r This addon is only functional on Timerunner characters. UI is disabled on this character.")
            return
        end

        LRLF_CreateSideWindow()

        -- Hook PVE frame changes so we can attach/hide our panel correctly
        if type(PVEFrame_ToggleFrame) == "function" then
            hooksecurefunc("PVEFrame_ToggleFrame", function()
                LRLF_TryHookLFG()
                LRLF_UpdateVisibility()
            end)
        end

        if type(LFGListFrame_SetActivePanel) == "function" then
            hooksecurefunc("LFGListFrame_SetActivePanel", function(frame, panel)
                if frame == LFGListFrame then
                    LRLF_UpdateVisibility()
                end
            end)
        end

        LRLF_TryHookLFG()
        LRLF_UpdateVisibility()

    elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
        if LRLF_IsTimerunner() then
            LRLF_UpdateVisibility()
        end

    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        -- We now rely on the LFGListSearchPanel_UpdateResultList hook
        -- to re-apply filtering whenever Blizzard updates results.
        -- No additional filtering is needed here, and we never trigger
        -- a new search from sign-ups.
        return
    end
end)
