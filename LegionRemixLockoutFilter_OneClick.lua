-- LegionRemixLockoutFilter_OneClick.lua
-- Isolated 1-click signup module for Legion Remix Lockout Filter
--
-- Behavior when LRLF_OneClickSignupEnabled is true:
--   Left-click:          open role selection dialog (no auto-confirm).
--   Shift + Left-click:  auto-confirm with your current spec's role.
--   Ctrl + Shift + Left: auto-confirm with all roles your class can perform.

local addonName = ...

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local clickHooked      = false
local dialogHooked     = false

-- autoConfirmMode:
--   0 = no auto-confirm (left click)
--   1 = auto-confirm with current spec's role (Shift+Left)
--   2 = auto-confirm with all roles class can perform (Ctrl+Shift+Left)
local AUTO_MODE_NONE     = 0
local AUTO_MODE_SPEC     = 1
local AUTO_MODE_ALLROLES = 2

local autoConfirmMode = AUTO_MODE_NONE

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function IsTimerunnerAndOneClickEnabled()
    if not LRLF_IsTimerunner or not LRLF_IsTimerunner() then
        return false
    end
    if not LRLF_OneClickSignupEnabled then
        return false
    end
    return true
end

local function GetSearchPanel()
    if not LFGListFrame then
        return nil
    end
    return LFGListFrame.SearchPanel
end

----------------------------------------------------------------------
-- Helpers for role selection
----------------------------------------------------------------------

local function GetRolesForCurrentSpec()
    local tank, heal, dps = false, false, false

    if not GetSpecialization or not GetSpecializationRole then
        return tank, heal, dps
    end

    local specIndex = GetSpecialization()
    if not specIndex then
        return tank, heal, dps
    end

    local role = GetSpecializationRole(specIndex) -- "TANK", "HEALER", "DAMAGER" or nil
    if role == "TANK" then
        tank = true
    elseif role == "HEALER" then
        heal = true
    elseif role == "DAMAGER" then
        dps = true
    end

    return tank, heal, dps
end

local function GetAllRolesForClass()
    local tank, heal, dps = false, false, false

    if not GetNumSpecializations or not GetSpecializationRole then
        return tank, heal, dps
    end

    local numSpecs = GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local role = GetSpecializationRole(i)
        if role == "TANK" then
            tank = true
        elseif role == "HEALER" then
            heal = true
        elseif role == "DAMAGER" then
            dps = true
        end
    end

    return tank, heal, dps
end

local function ApplyRolesToDialog(mode)
    local dialog = LFGListApplicationDialog
    if not dialog then
        return false
    end

    local tankBtn   = dialog.TankButton    and dialog.TankButton.CheckButton
    local healerBtn = dialog.HealerButton  and dialog.HealerButton.CheckButton
    local dpsBtn    = dialog.DamagerButton and dialog.DamagerButton.CheckButton

    if not (tankBtn or healerBtn or dpsBtn) then
        return false
    end

    local tank, heal, dps = false, false, false

    if mode == AUTO_MODE_SPEC then
        tank, heal, dps = GetRolesForCurrentSpec()
    elseif mode == AUTO_MODE_ALLROLES then
        tank, heal, dps = GetAllRolesForClass()
    end

    -- If nothing ended up selected, don't auto-confirm
    if not (tank or heal or dps) then
        return false
    end

    -- Apply, respecting visibility of buttons
    if tankBtn then
        tankBtn:SetChecked(tank and tankBtn:IsShown())
    end
    if healerBtn then
        healerBtn:SetChecked(heal and healerBtn:IsShown())
    end
    if dpsBtn then
        dpsBtn:SetChecked(dps and dpsBtn:IsShown())
    end

    return true
end

----------------------------------------------------------------------
-- Click handling
----------------------------------------------------------------------

local function DetermineAutoConfirmMode()
    local shiftDown = IsShiftKeyDown and IsShiftKeyDown()
    local ctrlDown  = IsControlKeyDown and IsControlKeyDown()

    if shiftDown and ctrlDown then
        return AUTO_MODE_ALLROLES
    elseif shiftDown then
        return AUTO_MODE_SPEC
    end

    return AUTO_MODE_NONE
end

local function HandleSearchEntryClick(self, button)
    -- Only alter left-click behavior; right-click stays default
    if button == "RightButton" then
        return
    end

    if not IsTimerunnerAndOneClickEnabled() then
        return
    end

    if not self or not self.resultID then
        return
    end

    local panel = GetSearchPanel()
    if not panel or not panel.SignUpButton then
        return
    end

    -- Determine auto-confirm mode based on modifiers:
    --   No modifiers         => AUTO_MODE_NONE
    --   Shift only           => AUTO_MODE_SPEC
    --   Ctrl + Shift         => AUTO_MODE_ALLROLES
    autoConfirmMode = DetermineAutoConfirmMode()

    -- Check if this result can be selected (if the helper exists)
    local canSelect = true
    if type(LFGListSearchPanelUtil_CanSelectResult) == "function" then
        canSelect = LFGListSearchPanelUtil_CanSelectResult(self.resultID)
    end

    if not canSelect or not panel.SignUpButton:IsEnabled() then
        -- If we can't sign up, don't auto-confirm anything.
        autoConfirmMode = AUTO_MODE_NONE
        return
    end

    -- Make sure the clicked result is selected
    if panel.selectedResult ~= self.resultID then
        LFGListSearchPanel_SelectResult(panel, self.resultID)
    end

    -- Trigger Blizzard's sign-up logic.
    -- Role handling + possible auto-confirm will be done in the dialog's OnShow hook.
    LFGListSearchPanel_SignUp(panel)
end

local function HandleApplicationDialogOnShow(self)
    -- If this was a plain left-click, we don't auto-confirm.
    if autoConfirmMode == AUTO_MODE_NONE then
        autoConfirmMode = AUTO_MODE_NONE
        return
    end

    if not self.SignUpButton or not self.SignUpButton:IsEnabled() then
        autoConfirmMode = AUTO_MODE_NONE
        return
    end

    -- Apply roles for the chosen mode (spec-only or all roles).
    local ok = ApplyRolesToDialog(autoConfirmMode)
    autoConfirmMode = AUTO_MODE_NONE

    if ok then
        self.SignUpButton:Click()
    end
end

----------------------------------------------------------------------
-- Setup hooks
----------------------------------------------------------------------

local function SetupOneClickHooks()
    -- Only hook once
    if clickHooked and dialogHooked then
        return
    end

    ------------------------------------------------------------------
    -- Hook the premade group row click handler
    ------------------------------------------------------------------
    if not clickHooked and type(LFGListSearchEntry_OnClick) == "function" then
        clickHooked = true

        hooksecurefunc("LFGListSearchEntry_OnClick", function(self, button)
            HandleSearchEntryClick(self, button)
        end)
    end

    ------------------------------------------------------------------
    -- Hook the application dialog to optionally auto-click Sign Up
    ------------------------------------------------------------------
    if not dialogHooked and LFGListApplicationDialog and LFGListApplicationDialog.SignUpButton then
        dialogHooked = true

        LFGListApplicationDialog:HookScript("OnShow", function(self)
            HandleApplicationDialogOnShow(self)
        end)
    end
end

----------------------------------------------------------------------
-- Event frame: hook once the relevant Blizzard UI is loaded
----------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName or arg1 == "Blizzard_LFGList" then
            SetupOneClickHooks()
        end
    elseif event == "PLAYER_LOGIN" then
        SetupOneClickHooks()
    end
end)

-- Try once at file load in case everything is already present
SetupOneClickHooks()
