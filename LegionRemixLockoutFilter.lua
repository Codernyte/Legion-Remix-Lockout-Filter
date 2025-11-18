--######################################################################
-- LegionRemixLockoutFilter.lua
-- Main wiring, state, events, Timerunner gating
--######################################################################

local ADDON_NAME, ADDON_TABLE = ...

--------------------------------------------------
-- Local debug helper
--------------------------------------------------

local function DebugLog(msg)
    if type(LRLF_DebugLog) == "function" then
        LRLF_DebugLog(msg)
    end
end

--------------------------------------------------
-- Slash command stub (now toggles debug window)
--------------------------------------------------

SLASH_LRLFDEBUG1 = "/lrlfd"
SlashCmdList["LRLFDEBUG"] = function(msg)
    -- /lrlfd toggles the LRLF debug window (no extra args needed)
    DebugLog("Slash /lrlfd invoked. Toggling debug window.")
    if type(LRLF_ToggleDebugWindow) == "function" then
        LRLF_ToggleDebugWindow()
    else
        print("|cff00ff00[LRLF]|r Debug window not available.")
        DebugLog("Slash /lrlfd: Debug window not available (LRLF_ToggleDebugWindow missing).")
    end
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
    DebugLog("LRLF_HideAll: Hiding LRLF UI elements and resetting collapse state.")
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
        DebugLog("LRLF_TryHookLFG: Hooking LFGListFrame OnShow/OnHide.")
        LFGListFrame:HookScript("OnShow", function()
            DebugLog("LFGListFrame:OnShow -> LRLF_UpdateVisibility()")
            LRLF_UpdateVisibility()
        end)
        LFGListFrame:HookScript("OnHide", function()
            DebugLog("LFGListFrame:OnHide -> LRLF_UpdateVisibility()")
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
        DebugLog("LRLF_TryHookLFG: Installing hook for LFGListSearchPanel_UpdateResultList.")

        hooksecurefunc("LFGListSearchPanel_UpdateResultList", function(panel)
            -- Only operate:
            --  * On Timerunner characters
            --  * When our filter is enabled
            --  * On the main LFG search panel for raids/dungeons
            if not LRLF_IsTimerunner() then
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
                DebugLog("UpdateResultList hook: LRLF_FilterResults not available; skipping filter.")
                return
            end

            local beforeCount = #results
            DebugLog(("UpdateResultList hook: kind=%s, before filter=%d results.")
                :format(kind, beforeCount))

            -- Re-apply our filter to whatever Blizzard just gave us.
            LRLF_FilterResults(results, kind)
            panel.totalResults = #results

            local afterCount = #results
            DebugLog(("UpdateResultList hook: kind=%s, after filter=%d results.")
                :format(kind, afterCount))

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
    DebugLog("LRLF_UpdateVisibility: Evaluating visibility state.")

    if not LRLF_IsTimerunner() then
        DebugLog("LRLF_UpdateVisibility: Not a Timerunner. Hiding all.")
        LRLF_HideAll()
        return
    end

    if not LFGListFrame then
        DebugLog("LRLF_UpdateVisibility: LFGListFrame not available. Hiding all.")
        LRLF_HideAll()
        return
    end

    LRLF_TryHookLFG()

    if not LFGListFrame:IsShown() then
        DebugLog("LRLF_UpdateVisibility: LFGListFrame not shown. Hiding all.")
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
        DebugLog("LRLF_UpdateVisibility: Premade search not active or wrong category. Hiding all.")
        LRLF_HideAll()
        return
    end

    local kind = isDungeon and "dungeon" or "raid"
    DebugLog(("LRLF_UpdateVisibility: Premade search active. kind=%s, collapsed=%s.")
        :format(kind, tostring(LRLF_UserCollapsed)))

    LRLF_AttachToPremade()
    if not LRLF_ToggleButton then
        DebugLog("LRLF_UpdateVisibility: Creating toggle button.")
        LRLF_CreateToggleButton()
    end

    if LRLF_UserCollapsed then
        DebugLog("LRLF_UpdateVisibility: UserCollapsed=true -> hiding panel, showing toggle tab.")
        if LRLFFrame then LRLFFrame:Hide() end
        if LRLF_ToggleButton then LRLF_ToggleButton:Show() end
        if LRLF_FilterButtons.apply then LRLF_FilterButtons.apply:Hide() end
        if LRLF_FilterButtons.settings then LRLF_FilterButtons.settings:Hide() end
        if LRLF_FilterButtons.bg then LRLF_FilterButtons.bg:Hide() end
    else
        DebugLog("LRLF_UpdateVisibility: UserCollapsed=false -> showing side panel and icons.")
        if LRLFFrame then
            if LRLFFrame:IsShown() then
                -- Already visible: refresh contents for the current kind.
                LRLF_RefreshSidePanelText(kind)
            else
                -- First time showing: OnShow handler will call RefreshSidePanelText.
                LRLFFrame:Show()
            end
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
        DebugLog("EVENT: PLAYER_LOGIN fired for LRLF.")
        local isTimerunner = LRLF_IsTimerunner()

        if not isTimerunner then
            DebugLog("PLAYER_LOGIN: Character is NOT a Timerunner. Addon UI disabled.")
            print("|cff00ff00[LegionRemixLockoutFilter]|r This addon is only functional on Timerunner characters. UI is disabled on this character.")
            return
        end

        DebugLog("PLAYER_LOGIN: Character is a Timerunner. Initializing LRLF UI.")
        LRLF_CreateSideWindow()

        -- Hook PVE frame changes so we can attach/hide our panel correctly
        if type(PVEFrame_ToggleFrame) == "function" then
            DebugLog("PLAYER_LOGIN: Hooking PVEFrame_ToggleFrame for visibility updates.")
            hooksecurefunc("PVEFrame_ToggleFrame", function()
                DebugLog("PVEFrame_ToggleFrame hook -> LRLF_TryHookLFG() + LRLF_UpdateVisibility().")
                LRLF_TryHookLFG()
                LRLF_UpdateVisibility()
            end)
        end

        if type(LFGListFrame_SetActivePanel) == "function" then
            DebugLog("PLAYER_LOGIN: Hooking LFGListFrame_SetActivePanel for visibility updates.")
            hooksecurefunc("LFGListFrame_SetActivePanel", function(frame, panel)
                if frame == LFGListFrame then
                    DebugLog("LFGListFrame_SetActivePanel hook: Active panel changed -> LRLF_UpdateVisibility().")
                    LRLF_UpdateVisibility()
                end
            end)
        end

        LRLF_TryHookLFG()
        LRLF_UpdateVisibility()

    elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
        DebugLog("EVENT: LFG_LIST_AVAILABILITY_UPDATE fired.")
        if LRLF_IsTimerunner() then
            LRLF_UpdateVisibility()
        else
            DebugLog("LFG_LIST_AVAILABILITY_UPDATE: Ignored (not a Timerunner).")
        end

    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        -- We now rely on the LFGListSearchPanel_UpdateResultList hook
        -- to re-apply filtering whenever Blizzard updates results.
        -- No additional filtering is needed here, and we never trigger
        -- a new search from sign-ups.
        DebugLog("EVENT: LFG_LIST_SEARCH_RESULTS_RECEIVED fired (handled by UpdateResultList hook).")
        return
    end
end)
