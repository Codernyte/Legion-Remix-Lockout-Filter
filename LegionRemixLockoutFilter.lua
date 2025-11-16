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

-- Kept for possible future use with search button
LRLF_LastSearchWasFiltered = LRLF_LastSearchWasFiltered or false

--------------------------------------------------
-- Helpers
--------------------------------------------------

-- Map LFGList category ID -> our internal "kind" label
local function LRLF_GetKindFromCategory(categoryID)
    if categoryID == 2 then
        return "dungeon"
    elseif categoryID == 3 then
        return "raid"
    end
    return nil
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

            local kind = LRLF_GetKindFromCategory(panel.categoryID)
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
            local beforeCount = #results
            LRLF_FilterResults(results, kind)
            local afterCount = #results

            panel.totalResults = #results

            -- Update the visual list ONLY; do NOT trigger a new search.
            if type(LFGListSearchPanel_UpdateResults) == "function" then
                LFGListSearchPanel_UpdateResults(panel)
            end

            -- (Optional) Debug: comment out if noisy.
            -- print(string.format(
            --     "|cff00ff00[LegionRemixLockoutFilter]|r Hooked result update (%s): %d -> %d",
            --     kind, beforeCount, afterCount
            -- ))
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
    local kind        = categoryID and LRLF_GetKindFromCategory(categoryID)
    local isDungeonOrRaid = (kind ~= nil)

    local premadeSearchActive =
        searchPanel
        and searchPanel:IsShown()
        and isDungeonOrRaid

    if not premadeSearchActive then
        LRLF_HideAll()
        return
    end

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
            LRLF_RefreshSidePanelText(kind or "raid")
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
