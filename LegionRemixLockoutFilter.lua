-- LegionRemixLockoutFilter.lua
-- Main wiring, state, events, Timerunner gating

local ADDON_NAME, ADDON_TABLE = ...

-- Modules
local LRLF_FilterMod = ADDON_TABLE.Filter or {}
local LRLF_LFG      = ADDON_TABLE.LFG or {}

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

LRLF_FilterState           = LRLF_FilterState           or { raid = {}, dungeon = {} }
LRLF_SystemSelection       = LRLF_SystemSelection       or { raid = {}, dungeon = {} }
LRLF_Rows                  = LRLF_Rows                  or { raid = {}, dungeon = {} }

LRLF_FilterButtons         = LRLF_FilterButtons         or { apply = nil, bg = nil, wts = nil }
LRLF_FilterEnabled         = (LRLF_FilterEnabled ~= false) -- default true
LRLF_SearchButton          = LRLF_SearchButton          or nil

-- Hide WTS/BuY/SELL groups by default
LRLF_WTSFilterEnabled      = (LRLF_WTSFilterEnabled ~= false) -- default true (hiding WTS groups)

-- IMPORTANT: now treated as "filter active for this panel", not one-shot.
LRLF_LastSearchWasFiltered = LRLF_LastSearchWasFiltered or false

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
    if LRLF_FilterButtons.wts then LRLF_FilterButtons.wts:Hide() end
    if LRLF_FilterButtons.bg then LRLF_FilterButtons.bg:Hide() end
end

--------------------------------------------------
-- Hook LFGListFrame show/hide once it exists
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
        if LRLF_FilterButtons.wts then LRLF_FilterButtons.wts:Hide() end
        if LRLF_FilterButtons.bg then LRLF_FilterButtons.bg:Hide() end
    else
        if LRLFFrame then
            LRLFFrame:Show()
            LRLF_RefreshSidePanelText(kind)
        end
        if LRLF_ToggleButton then LRLF_ToggleButton:Hide() end
        if LRLF_FilterButtons.apply then LRLF_FilterButtons.apply:Show() end
        if LRLF_FilterButtons.wts then LRLF_FilterButtons.wts:Show() end
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
        -- Only affect results if:
        --  * This is a Timerunner
        --  * Our filter is currently active (LastSearchWasFiltered)
        --  * The master filter toggle is enabled
        if not LRLF_IsTimerunner() then
            return
        end
        if not LRLF_LastSearchWasFiltered then
            return
        end
        if not LRLF_FilterEnabled then
            return
        end

        if not LFGListFrame or not LFGListFrame.SearchPanel then
            return
        end

        local searchPanel = LFGListFrame.SearchPanel
        if not searchPanel:IsShown() then
            return
        end

        local categoryID = searchPanel.categoryID
        local kind = (categoryID == 2 and "dungeon")
                  or (categoryID == 3 and "raid")
                  or nil
        if not kind then
            return
        end

        -- Operate directly on searchPanel.results so we don't fight Blizzard's
        -- internal bookkeeping. That list may be refreshed multiple times per search,
        -- so we re-filter on every event while LRLF_LastSearchWasFiltered is true.
        local results = searchPanel.results
        if not results or type(results) ~= "table" then
            return
        end

        LRLF_FilterMod.FilterResults(results, kind)
        searchPanel.totalResults = #results

        if type(LFGListSearchPanel_UpdateResults) == "function" then
            LFGListSearchPanel_UpdateResults(searchPanel)
        end
    end
end)
