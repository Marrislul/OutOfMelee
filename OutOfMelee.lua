local OutOfMelee = LibStub("AceAddon-3.0"):NewAddon("OutOfMelee", "AceEvent-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDB = LibStub("AceDB-3.0")

local UPDATE_INTERVAL = 0.1

-- Melee abilities per class. They are checked by name, so every rank counts
-- (Forever replaces the old rank when you learn a new one). The first one the
-- character knows answers the range check; unknown spells return nil and are skipped.
-- Spell range checks are not secret, so this keeps working in combat.
local MELEE_SPELLS = {
    WARRIOR = {
        78,     -- Heroic Strike
        1715,   -- Hamstring
        772,    -- Rend
        6552,   -- Pummel
        1464,   -- Slam
        23922,  -- Shield Slam
    },
    ROGUE = {
        1752,   -- Sinister Strike
        1766,   -- Kick
        2098,   -- Eviscerate
        53,     -- Backstab
    },
    PALADIN = {
        679,    -- Holy Strike (Forever)
        35395,  -- Crusader Strike
        96231,  -- Rebuke
        53595,  -- Hammer of the Righteous
        85256,  -- Templar's Verdict
        383328, -- Final Verdict
    },
    DRUID = {
        1082,   -- Claw
        5221,   -- Shred
        6807,   -- Maul
        22568,  -- Ferocious Bite
        33917,  -- Mangle
    },
    SHAMAN = {
        17364,  -- Stormstrike
        73899,  -- Primal Strike
        60103,  -- Lava Lash
    },
    DEATHKNIGHT = {
        49998,  -- Death Strike
        45462,  -- Plague Strike
        49020,  -- Obliterate
        55090,  -- Scourge Strike
        206930, -- Heart Strike
    },
    MONK = {
        100780, -- Tiger Palm
        100784, -- Blackout Kick
    },
    DEMONHUNTER = {
        162794, -- Chaos Strike
        203782, -- Shear
        162243, -- Demon's Bite
    },
}

-- Checked by ID only: classic hunters have a Raptor Strike too, but they fight
-- at range and would see the "!" all the time.
local MELEE_SPELL_IDS = {
    HUNTER = {
        186270, -- Raptor Strike (retail Survival)
        259387, -- Mongoose Bite (retail Survival)
    },
}

-- Cat Form, Bear Form, Dire Bear Form (classic)
local DRUID_MELEE_FORMS = { [1] = true, [5] = true, [8] = true }

local GetSpellName = C_Spell and C_Spell.GetSpellName or function(spellID)
    return (GetSpellInfo(spellID))
end

local SpellInRange
if C_Spell and C_Spell.IsSpellInRange then
    SpellInRange = C_Spell.IsSpellInRange
else
    SpellInRange = function(spell, unit)
        local result = IsSpellInRange(spell, unit)
        if result == nil then return nil end
        return result == 1
    end
end

local playerClass
local spellNames = {}
local indicator, label, anchorFrame, ticker
local inCombat = false
local sessionState = { showAnchor = false }

local defaults = {
    profile = {
        size = 28,
        color = { r = 1, g = 0.1, b = 0.1 },
        onlyInCombat = false,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = -60,
    },
    char = {
        enabled = true,
    },
}

local options = {
    name = "Out of Melee",
    type = "group",
    args = {
        enabled = {
            type = "toggle",
            name = "Enable on this character",
            desc = "Turn it off on characters that don't fight in melee.",
            width = "full",
            get = function() return OutOfMelee.db.char.enabled end,
            set = function(_, value)
                OutOfMelee.db.char.enabled = value
                OutOfMelee:Refresh()
            end,
            order = 1,
        },
        showAnchor = {
            type = "toggle",
            name = "Show Anchor",
            desc = "Drag the box to move the \"!\". Uncheck to hide it again.",
            width = "full",
            get = function() return sessionState.showAnchor end,
            set = function(_, value)
                sessionState.showAnchor = value
                anchorFrame:SetShown(value)
                OutOfMelee:Refresh()
            end,
            order = 2,
        },
        onlyInCombat = {
            type = "toggle",
            name = "Only in combat",
            desc = "Only show the \"!\" while you are in combat.",
            width = "full",
            get = function() return OutOfMelee.db.profile.onlyInCombat end,
            set = function(_, value)
                OutOfMelee.db.profile.onlyInCombat = value
                OutOfMelee:Refresh()
            end,
            order = 3,
        },
        size = {
            type = "range",
            name = "Size",
            min = 10,
            max = 80,
            step = 1,
            get = function() return OutOfMelee.db.profile.size end,
            set = function(_, value)
                OutOfMelee.db.profile.size = value
                OutOfMelee:ApplyLook()
            end,
            order = 4,
        },
        color = {
            type = "color",
            name = "Color",
            hasAlpha = false,
            get = function()
                local c = OutOfMelee.db.profile.color
                return c.r, c.g, c.b
            end,
            set = function(_, r, g, b)
                local c = OutOfMelee.db.profile.color
                c.r, c.g, c.b = r, g, b
                OutOfMelee:ApplyLook()
            end,
            order = 5,
        },
    },
}

local function SpellName(spellID)
    local name = spellNames[spellID]
    if name == nil then
        name = GetSpellName(spellID) or false
        spellNames[spellID] = name
    end
    return name
end

-- true = in melee range, false = out of range, nil = no melee ability to check with
local function CheckMeleeRange()
    local spells = MELEE_SPELLS[playerClass]
    if spells then
        for _, spellID in ipairs(spells) do
            local name = SpellName(spellID)
            if name then
                local inRange = SpellInRange(name, "target")
                if inRange ~= nil then return inRange end
            end
        end
    end
    spells = MELEE_SPELL_IDS[playerClass]
    if spells then
        for _, spellID in ipairs(spells) do
            local inRange = SpellInRange(spellID, "target")
            if inRange ~= nil then return inRange end
        end
    end
    return nil
end

local function FormAllowsMelee()
    if playerClass ~= "DRUID" then return true end
    local formID = GetShapeshiftFormID()
    return formID ~= nil and DRUID_MELEE_FORMS[formID] == true
end

local function HasHostileTarget()
    return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
end

function OutOfMelee:IsActive()
    return self.db.char.enabled
        and (MELEE_SPELLS[playerClass] or MELEE_SPELL_IDS[playerClass]) ~= nil
end

function OutOfMelee:ShouldShow()
    if sessionState.showAnchor then return true end
    if self.db.profile.onlyInCombat and not inCombat then return false end
    if not HasHostileTarget() or not FormAllowsMelee() then return false end
    return CheckMeleeRange() == false
end

-- The ticker only runs while there is a target, so nothing polls in town.
function OutOfMelee:Refresh()
    local active = self:IsActive()
    local watch = active and UnitExists("target")
    if watch and not ticker then
        ticker = C_Timer.NewTicker(UPDATE_INTERVAL, function() self:Refresh() end)
    elseif not watch and ticker then
        ticker:Cancel()
        ticker = nil
    end
    indicator:SetShown(sessionState.showAnchor or (active and self:ShouldShow()))
end

local function PositionAnchor()
    local p = OutOfMelee.db.profile
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
end

function OutOfMelee:ApplyLook()
    local p = self.db.profile
    label:SetFont(STANDARD_TEXT_FONT, p.size, "OUTLINE")
    label:SetText("!")
    label:SetTextColor(p.color.r, p.color.g, p.color.b)
    indicator:SetSize(p.size, p.size)
    anchorFrame:SetSize(p.size + 12, p.size + 12)
end

function OutOfMelee:CreateFrames()
    anchorFrame = CreateFrame("Frame", "OutOfMeleeAnchor", UIParent, "BackdropTemplate")
    anchorFrame:SetMovable(true)
    anchorFrame:EnableMouse(true)
    anchorFrame:RegisterForDrag("LeftButton")
    anchorFrame:SetClampedToScreen(true)
    anchorFrame:SetFrameStrata("HIGH")
    anchorFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    anchorFrame:SetBackdropColor(0.1, 0.1, 0.8, 0.8)
    anchorFrame:SetBackdropBorderColor(0.4, 0.4, 0.9, 1)

    anchorFrame:SetScript("OnDragStart", function(frame)
        frame:StartMoving()
    end)
    anchorFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        local p = OutOfMelee.db.profile
        p.point, p.relativePoint, p.x, p.y = point, relativePoint, x, y
    end)
    anchorFrame:Hide()

    indicator = CreateFrame("Frame", "OutOfMeleeIndicator", UIParent)
    indicator:SetPoint("CENTER", anchorFrame, "CENTER")
    indicator:SetFrameStrata("HIGH")
    indicator:SetFrameLevel(anchorFrame:GetFrameLevel() + 5)
    indicator:EnableMouse(false)
    label = indicator:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    indicator:Hide()

    PositionAnchor()
    self:ApplyLook()
end

function OutOfMelee:OnInitialize()
    self.db = AceDB:New("OutOfMeleeDB", defaults, true)
    AceConfig:RegisterOptionsTable("OutOfMelee", options)
    self.optionsFrame = AceConfigDialog:AddToBlizOptions("OutOfMelee", "Out of Melee")
    playerClass = select(2, UnitClass("player"))
    self:CreateFrames()
end

function OutOfMelee:OnEnable()
    inCombat = InCombatLockdown()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "Refresh")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "Refresh")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        inCombat = true
        self:Refresh()
    end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        inCombat = false
        self:Refresh()
    end)
    self:Refresh()
end
