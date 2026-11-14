-- Game: the game's own timers. Cooldowns and auras come back as duration objects that the
-- game keeps counting; even when their numbers are hidden from addons ("secret" in combat),
-- status bars and font strings can be bound to them and the game draws the real value.
-- Every call is guarded: if this client lacks an API, callers fall back to estimates.
local _, H = ...
local G = {}
H.Game = G
local Safe, IsSecret = H.Safe, H.IsSecret

local function Enum2(group, name, default)
    return Enum and Enum[group] and Enum[group][name] or default
end

-- A spell's cooldown (not the global cooldown) as a duration object, or nil.
function G.SpellCooldown(spell)
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
    local d = Safe(C_Spell.GetSpellCooldownDuration, spell, true)
    if type(d) ~= "table" and type(d) ~= "userdata" then return nil end
    return d
end

-- The IDs of a unit's auras matching filter ("HARMFUL|PLAYER": debuffs you cast), or nil if the
-- game will not say. The IDs themselves are never hidden.
function G.AuraIDs(unit, filter)
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs) then return nil end
    local ids = Safe(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter)
    if type(ids) ~= "table" or IsSecret(ids) then return nil end
    return ids
end

-- One aura's duration object, or nil.
function G.AuraDuration(unit, id)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDuration) then return nil end
    local d = Safe(C_UnitAuras.GetAuraDuration, unit, id)
    if type(d) ~= "table" and type(d) ~= "userdata" then return nil end
    return d
end

-- Whether the addon itself may read the duration's numbers.
function G.Readable(d)
    if not d then return false end
    local ok, secret = pcall(d.HasSecretValues, d)
    return ok and not IsSecret(secret) and not secret
end

-- Seconds left (0 when over), or nil when hidden.
function G.Remaining(d)
    if not G.Readable(d) then return nil end
    local r = Safe(d.GetRemainingDuration, d)
    if type(r) ~= "number" or IsSecret(r) then return nil end
    return r
end

-- Whether the duration is still running: true/false, or nil when hidden.
function G.Active(d)
    if not d or not d.IsActive then return nil end
    local ok, v = pcall(d.IsActive, d)
    if not ok or IsSecret(v) or type(v) ~= "boolean" then return nil end
    return v
end

-- Total length in seconds, or nil when hidden.
function G.Total(d)
    if not G.Readable(d) then return nil end
    local r = Safe(d.GetTotalDuration, d)
    if type(r) ~= "number" or IsSecret(r) then return nil end
    return r
end

-- Fills bar from the duration (full at the start, empty at the end). Returns true if the game
-- took it.
function G.BindBar(bar, d)
    if not (bar.SetTimerDuration and d) then return false end
    local ok = pcall(bar.SetTimerDuration, bar, d,
        Enum2("StatusBarInterpolation", "Immediate", 0), Enum2("StatusBarTimerDirection", "RemainingTime", 1))
    return ok
end

local formatter
local function Formatter()
    if formatter ~= nil then return formatter or nil end
    formatter = false
    if C_StringUtil and C_StringUtil.CreateSecondsFormatter then
        local f = Safe(C_StringUtil.CreateSecondsFormatter)
        if f then
            -- "12s", and "3.4" in the last ten seconds
            Safe(f.SetDefaultAbbreviation, f, Enum2("SecondsFormatterAbbreviation", "OneLetter", 2))
            Safe(f.SetStripIntervalWhitespace, f, Enum2("SecondsFormatterIntervalWhitespace", "Strip", 1))
            Safe(f.SetMillisecondsThreshold, f, 10)
            Safe(f.SetDesiredUnitCount, f, 1)
            formatter = f
        end
    end
    return formatter or nil
end

-- Has the game keep fontString showing the time left on d; zeroText once it is over.
-- Returns the binding (reuse it for the same font string), or nil if not possible.
function G.BindText(binding, fontString, d, zeroText)
    if not binding then
        if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then return nil end
        binding = Safe(C_DurationUtil.CreateDurationTextBinding)
        if not binding then return nil end
        local fmt = Formatter()
        if not fmt then return nil end
        local ok = pcall(function()
            binding:SetFontString(fontString)
            binding:SetFormatter(fmt)
            binding:SetUpdateInterval(0.1)
        end)
        if not ok then return nil end
    end
    local ok = pcall(function()
        binding:SetZeroDurationText(zeroText or "")
        binding:SetExpiredText(zeroText or "")
        binding:SetDuration(d)
        binding:SetEnabled(true)
    end)
    if not ok then return nil end
    return binding
end

function G.Unbind(binding)
    if binding then pcall(binding.SetEnabled, binding, false) end
end

--------------------------------------------------------------------------------
-- Shaman things
--------------------------------------------------------------------------------
-- Totem slots, as the game numbers them (Blizzard's constants when present).
G.SLOT = {
    fire = FIRE_TOTEM_SLOT or 1, earth = EARTH_TOTEM_SLOT or 2,
    water = WATER_TOTEM_SLOT or 3, air = AIR_TOTEM_SLOT or 4,
}

-- What stands in a totem slot: haveTotem, name, startTime, duration, icon. Any of them may be
-- secret in combat (and all nil if the game will not answer).
function G.TotemInfo(slot)
    if not GetTotemInfo then return nil end
    local ok, have, name, start, dur, icon = pcall(GetTotemInfo, slot)
    if not ok then return nil end
    return have, name, start, dur, icon
end

-- A totem slot's time as a duration object (empty when no totem stands there), or nil.
function G.TotemDuration(slot)
    if not GetTotemDuration then return nil end
    local d = Safe(GetTotemDuration, slot)
    if type(d) ~= "table" and type(d) ~= "userdata" then return nil end
    return d
end

-- The temporary enchant on the main-hand weapon (a shaman's imbue), as
-- { seconds = time left, icon = fileID, id = enchantID }, or false when there is none, or nil
-- when the game will not say.
function G.WeaponImbue()
    if not (C_Item and C_Item.GetWeaponEnchantInfo) then return nil end
    local slot = Enum2("WeaponSlot", "MainHand", 0)
    local list = Safe(C_Item.GetWeaponEnchantInfo, slot)
    if type(list) ~= "table" or IsSecret(list) then return nil end
    local PERMANENT = Enum2("ItemEnchantType", "Permanent", 1)
    for _, e in ipairs(list) do
        if type(e) == "table" and not IsSecret(e.hasEnchant) and e.hasEnchant
            and not IsSecret(e.enchantType) and e.enchantType ~= PERMANENT then
            local left = e.timeLeft
            if IsSecret(left) or type(left) ~= "number" then left = nil else left = left / 1000 end
            local icon = e.enchantIconID
            if IsSecret(icon) or icon == 0 then icon = nil end
            return { seconds = left, icon = icon, id = (not IsSecret(e.enchantID)) and e.enchantID or nil }
        end
    end
    return false
end

-- The number of stacks or charges on an aura as a string to display ("3"; "" below min). It may
-- be secret: it is only ever handed to a font string.
function G.AuraCount(unit, id, min)
    if not (C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount) then return nil end
    return Safe(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, min or 1, 9)
end

-- The instance ID of one of your buffs, found by spell ID (any of ids) or by name, or nil.
-- Only works for buffs the game does not hide from addons; callers fall back otherwise.
function G.PlayerAuraID(ids, name)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, id in ipairs(ids or {}) do
            local aura = Safe(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if type(aura) == "table" and not IsSecret(aura) and not IsSecret(aura.auraInstanceID)
                and aura.auraInstanceID then
                return aura.auraInstanceID
            end
        end
    end
    if name and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local aura = Safe(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if type(aura) == "table" and not IsSecret(aura) and not IsSecret(aura.auraInstanceID) then
            return aura.auraInstanceID
        end
    end
    return nil
end
