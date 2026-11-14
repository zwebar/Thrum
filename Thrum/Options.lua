-- Options: a small page under Options > AddOns > Thrum, built with Blizzard's Settings panel.
-- The settings live in ThrumDB (the same values the /thrum commands change), so the page and
-- the commands always agree.
local _, H = ...
local O = {}
H.Options = O

local function Percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
local function Times(v) return string.format("%.2fx", v) end
local function Pixels(v) return string.format("%d", math.floor(v + 0.5)) end

-- What to do when a setting changes (the rest are read live).
local APPLY = {
    scale = function() if H.built then H.HUD:ApplyPosition() end end,
    locked = function() if H.built then H.HUD:ApplyLock() end end,
    totems = function() if H.built then H.HUD:ApplyOptions() end end,
    imbue = function() if H.built then H.HUD:ApplyOptions() end end,
    fsr = function() if H.built then H.HUD:ApplyOptions() end end,
    castbar = function() if H.built then H.HUD:ApplyOptions() end end,
}

function O:Build()
    local db, D = ThrumDB, H.DEFAULTS
    local cat = Settings.RegisterVerticalLayoutCategory("Thrum")
    local layout = SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(cat)

    local function Register(key, kind, name)
        local s = Settings.RegisterAddOnSetting(cat, "THRUM_" .. key:upper(), key, db, kind, name, D[key])
        if APPLY[key] then s:SetValueChangedCallback(function() APPLY[key]() end) end
        return s
    end
    local function Header(text)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end
    local function Checkbox(key, name, tip)
        Settings.CreateCheckbox(cat, Register(key, Settings.VarType.Boolean, name), tip)
    end
    local function Slider(key, name, tip, lo, hi, step, fmt)
        local opts = Settings.CreateSliderOptions(lo, hi, step)
        if MinimalSliderWithSteppersMixin then
            opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
        end
        Settings.CreateSlider(cat, Register(key, Settings.VarType.Number, name), opts, tip)
    end
    local function Button(name, text, tip, fn)
        if layout and CreateSettingsButtonInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer(name, text, fn, tip, true))
        end
    end

    Header("HUD")
    Checkbox("locked", "Lock the HUD", "Untick to drag the HUD somewhere else, then tick again.")
    Slider("scale", "Size", "How big the HUD is.", 0.5, 2.5, 0.05, Times)
    Slider("idle", "Opacity when idle", "How visible the HUD is out of combat with nothing going on. 0% hides it.",
        0, 1, 0.05, Percent)
    Checkbox("totems", "Totem plaques", "Your four totems above the mana trough, with the time left on each.")
    Checkbox("imbue", "Weapon imbue badge", "Your weapon imbue and the minutes left on it, left of the totems.")
    Checkbox("fsr", "Five-second rule", "A thin line under the mana trough that runs out five seconds after you spend "
        .. "mana, when full regeneration starts again.")
    Checkbox("castbar", "Cast bar", "Your own cast, in a slim bar under the mana trough.")

    Header("Effects")
    Checkbox("words", "Spell words", "Carved words for your spells (EARTH SHOCK!, CHAIN HEAL!, SEARING!...).")
    Slider("fx", "Word size", "How big the word bursts are.", 0.5, 1.5, 0.05, Times)
    Checkbox("procs", "Procs", "CLEARCASTING! and FLURRY!, with a box while they last. The game only shows "
        .. "some buffs to addons in combat, so a proc can be missed.")
    Checkbox("hits", "CRIT! and RESISTED!", "Words for what happens to your target. Only when you are not in a group, "
        .. "since the game does not say whose hit it was.")
    Checkbox("prompt", "SHOCK IT! cast bar", "Shows what your target is casting, flags heals, and tells you to "
        .. "Earth Shock it (or War Stomp, or Grounding Totem for a harmful spell).")

    Header("")
    Button("Try it out", "Play demo", "A 15-second pretend fight showing every effect.", function()
        if SettingsPanel and SettingsPanel.Close then SettingsPanel:Close() end
        H.Build()
        H.Demo:Run()
    end)
    Button("Position", "Reset", "Puts the HUD back in its default spot and size.", function()
        SlashCmdList["THRUM"]("reset")
    end)

    Settings.RegisterAddOnCategory(cat)
    self.category = cat
end

-- Called once the saved settings are loaded.
function O:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
        return
    end
    local ok, err = pcall(O.Build, O)
    if not ok then
        self.failed = tostring(err)
    end
end

function O:Open()
    if self.category and Settings.OpenToCategory then
        local id = self.category.GetID and self.category:GetID() or self.category.ID
        Settings.OpenToCategory(id)
        return true
    end
    return false
end
