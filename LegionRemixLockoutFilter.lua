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

LRLF_FilterState           = LRLF_FilterState           or { raid = {}, dungeon = {} }
LRLF_SystemSelection       = LRLF_SystemSelection       or { raid = {}, dungeon = {} }
LRLF_Rows                  = LRLF_Rows                  or { raid = {}, dungeon = {} }

-- Right-hand icon strip: spyglass + settings (one-click toggle)
LRLF_FilterButtons         = LRLF_FilterButtons         or { apply = nil, bg = nil, settings = nil }
LRLF_FilterEnabled         = (LRLF_FilterEnabled ~= false) -- default true
LRLF_SearchButton          = LRLF_SearchButton          or nil

-- One-click signup toggle (settings icon controls this elsewhere)
LRLF_OneClickSignupEnabled = (LRLF_OneClickSignupEnabled == true)

-- Kept for possible future use, but NOT used to gate filtering anymore
LRLF_LastSearchWasFiltered = LRLF_LastSearchWasFiltered or false

-- Internal: ensure we only hook the search entry once
LRLF_SearchEntryHookDone   = LRLF_SearchEntryHookDone   or false

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
-- One-click signup helpers
--------------------------------------------------

-- Determine all roles this class/spec can reasonably sign up as
local function LRLF_GetAllEligibleRoles()
    local canTank, canHeal, canDPS = false, false, false

    if GetNumSpecializations and GetSpecializationInfo then
        local num = GetNumSpecializations()
        for i = 1, num do
            local _, _, _, _, role = GetSpecializationInfo(i)
            if role == "TANK" then
                canTank = true
            elseif role == "HEALER" then
                canHeal = true
            elseif role == "DAMAGER" then
                canDPS = true
            end
        end
    end

    -- Fallback: if nothing detected, assume DPS at least.
    if not (canTank or canHeal or canDPS) then
        canDPS = true
    end

    return canTank, canHeal, canDPS
end

-- Core handler for one-click signup logic.
-- Called from our hook on LFGListSearchEntry_OnClick.
local function LRLF_HandleSearchEntryClick_OneClick(button, mouseButton)
    -- Hard gating
    if not LRLF_IsTimerunner() then
        return
    end
    if not LRLF_OneClickSignupEnabled then
        return
    end
    if not button or not button.resultID then
        return
    end
    if mouseButton and mouseButton ~= "LeftButton" then
        return
    end
    if not C_LFGList
        or not C_LFGList.ApplyToGroup
        or not C_LFGList.GetSearchResultInfo
    then
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
    local isDungeon  = (categoryID == 2)
    local isRaid     = (categoryID == 3)
    if not (isDungeon or isRaid) then
        return
    end

    --------------------------------------------------
    -- Modifier behavior:
    --   * Left-click: one-click signup with CURRENT Blizzard role selection.
    --   * SHIFT + Left-click: one-click signup with ALL ELIGIBLE ROLES.
    --
    --   (Right-click / other buttons: Blizzard behavior only.)
    --------------------------------------------------
    local shiftDown = IsShiftKeyDown and IsShiftKeyDown()

    local resultID     = button.resultID
    local allRolesMode = false

    if shiftDown then
        allRolesMode = true
    end

    -- Determine roles to apply with
    local tank, heal, dps

    if allRolesMode then
        -- SHIFT: all roles this class/spec can perform
        tank, heal, dps = LRLF_GetAllEligibleRoles()
    else
        -- Plain left-click: use Blizzard's current LFG role selection if exposed
        if C_LFGList.GetRoles then
            tank, heal, dps = C_LFGList.GetRoles()
        elseif GetLFGRoles then
            local lfgTank, lfgHeal, lfgDps = GetLFGRoles()
            tank, heal, dps = lfgTank, lfgHeal, lfgDps
        else
            -- Fallback: use current assigned role
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") or "NONE"
            tank = (role == "TANK")
            heal = (role == "HEALER")
            dps  = (role == "DAMAGER")
        end
    end

    -- Safety: ensure at least one role is true so we don't send a blank apply
    if not (tank or heal or dps) then
        -- Fallback: DPS only
        tank, heal, dps = false, false, true
    end

    C_LFGList.ApplyToGroup(resultID, "", false, tank, heal, dps)
end

-- Hook that runs after Blizzard's click handler.
local function LRLF_SearchEntry_OnClick_Hook(button, mouseButton)
    -- Blizzard already did its default behavior; we optionally do our one-click apply.
    LRLF_HandleSearchEntryClick_OneClick(button, mouseButton)
end

--------------------------------------------------
-- Hook LFGListFrame show/hide and search entry click
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

    -- Hook the entry click once (for one-click signup)
    if not LRLF_SearchEntryHookDone and type(LFGListSearchEntry_OnClick) == "function" then
        hooksecurefunc("LFGListSearchEntry_OnClick", LRLF_SearchEntry_OnClick_Hook)
        LRLF_SearchEntryHookDone = true
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
        -- Only affect results if:
        --  * This is a Timerunner
        --  * The master filter toggle (spyglass) is enabled
        if not LRLF_IsTimerunner() then
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

        local results = searchPanel.results
        if not results or type(results) ~= "table" then
            return
        end

        -- Call the global wrapper defined in LegionRemixLockoutFilter_Filter.lua
        if type(LRLF_FilterResults) ~= "function" then
            print("|cff00ff00[LegionRemixLockoutFilter]|r Filter function missing; skipping filtering.")
            return
        end

        local beforeCount = #results
        LRLF_FilterResults(results, kind)
        local afterCount = #results

        -- Debug instrumentation: see whether filtering is actually happening
        print(string.format(
            "|cff00ff00[LegionRemixLockoutFilter]|r Filtered %s results: %d -> %d",
            kind, beforeCount, afterCount
        ))

        searchPanel.totalResults = #results

        -- IMPORTANT: Just update the visual list from the *current* results table.
        if type(LFGListSearchPanel_UpdateResults) == "function" then
            LFGListSearchPanel_UpdateResults(searchPanel)
        end
    end
end)
