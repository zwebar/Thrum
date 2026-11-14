-- Spells: what each shaman spell looks like on the HUD.
-- Listed by rank-1 spell id; other ranks (and Forever's own spell versions) are matched by
-- name, so this works in any language.
local _, H = ...
local S = {}
H.Spells = S
local C = H.C

--   word/color/size/shape  the word burst shown when you cast it (shape defaults to the element's)
--   el                     element: earth, fire, water, air, storm or life (particles and colour)
--   streak                 throw a lightning arc too
--   shock                  one of the three shocks (they share a cooldown)
--   totem                  drops a totem in that element's slot; dur is a first guess in seconds,
--                          replaced by the game's own totem timer as soon as it exists
--   imbue                  a weapon imbue
--   heal                   a heal (green cast bar, leaves)
--   cd, short              show a cooldown box (only for short cooldowns worth watching)
--   aura = { unit, kind, short, dur, untimed }  a countdown box on you or the target; dur is a
--                          first guess, replaced by the real aura's timer when it appears
S.list = {
    -- Shocks
    { key = "earth",  id = 8042,  word = "EARTH SHOCK!", el = "earth", size = 0.95, shock = true },
    { key = "flame",  id = 8050,  word = "FLAME SHOCK!", el = "fire", size = 0.95, shock = true,
      aura = { unit = "target", kind = "dot", short = "FLAME", dur = 12 } },
    { key = "frost",  id = 8056,  word = "FROST SHOCK!", el = "water", color = C.air, textColor = C.water, size = 0.95,
      shock = true, aura = { unit = "target", kind = "cc", short = "SLOWED", dur = 8 } },

    -- Lightning
    { key = "bolt",   id = 403,   word = "BOLT!", el = "storm", size = 0.7, streak = true },
    { key = "chain",  id = 421,   word = "CHAIN LIGHTNING!", el = "storm", size = 1.0, streak = true, big = true,
      cd = 6, short = "CHAIN" },
    { key = "shield", id = 324,   word = "LIGHTNING SHIELD!", el = "storm", size = 0.75, lightningShield = true },

    -- Heals
    { key = "wave",   id = 331,   word = "HEALING WAVE!", el = "life", size = 0.9, heal = true },
    { key = "lesser", id = 8004,  word = "LESSER WAVE!", el = "life", size = 0.8, heal = true },
    { key = "cheal",  id = 1064,  word = "CHAIN HEAL!", el = "life", size = 1.0, heal = true },
    { key = "curep",  id = 526,   word = "CLEANSED!", el = "life", size = 0.7 },
    { key = "cured",  id = 2870,  word = "CLEANSED!", el = "life", size = 0.7 },

    -- Utility
    { key = "purge",  id = 370,   word = "PURGE!", el = "air", shape = "rune", size = 0.9 },
    { key = "wolf",   id = 2645,  word = "GHOST WOLF!", el = "air", size = 0.85,
      aura = { unit = "player", kind = "buff", short = "WOLF", dur = 3600, untimed = true } },
    { key = "stomp",  id = 20549, word = "STOMP!", el = "earth", size = 1.0, cd = 120, noBox = true,
      aura = { unit = "target", kind = "cc", short = "STUNNED", dur = 2 } },
    { key = "recall", id = 556,   word = "HOME!", el = "air", size = 0.8 },
    { key = "reborn", id = 20608, word = "REBORN!", el = "life", shape = "rune", size = 1.1, big = true },

    -- Talents
    { key = "storm",  id = 17364, word = "STORMSTRIKE!", el = "storm", size = 1.1, big = true, streak = true,
      cd = 20, short = "STORM", aura = { unit = "target", kind = "dot", short = "STORMSTRIKE", dur = 12 } },
    { key = "mastery", id = 16166, word = "MASTERY!", el = "storm", shape = "rune", size = 1.0, big = true,
      aura = { unit = "player", kind = "buff", short = "MASTERY", dur = 3600, untimed = true } },
    { key = "swift",  id = 16188, word = "SWIFTNESS!", el = "life", size = 0.95,
      aura = { unit = "player", kind = "buff", short = "SWIFT", dur = 3600, untimed = true } },

    -- Weapon imbues
    { key = "rockbiter",   id = 8017, word = "ROCKBITER!", el = "earth", size = 0.8, imbue = true },
    { key = "flametongue", id = 8024, word = "FLAMETONGUE!", el = "fire", size = 0.8, imbue = true },
    { key = "frostbrand",  id = 8033, word = "FROSTBRAND!", el = "water", size = 0.8, imbue = true },
    { key = "windfury",    id = 8232, word = "WINDFURY!", el = "air", size = 0.8, imbue = true },

    -- Totems: earth
    { key = "t_earthbind", id = 2484,  word = "EARTHBIND!", totem = "earth", dur = 45 },
    { key = "t_stoneclaw", id = 5730,  word = "STONECLAW!", totem = "earth", dur = 15 },
    { key = "t_stoneskin", id = 8071,  word = "STONESKIN!", totem = "earth", dur = 120 },
    { key = "t_strength",  id = 8075,  word = "STRENGTH OF EARTH!", totem = "earth", dur = 120 },
    { key = "t_tremor",    id = 8143,  word = "TREMOR!", totem = "earth", dur = 120 },
    -- fire
    { key = "t_searing",   id = 3599,  word = "SEARING!", totem = "fire", dur = 30 },
    { key = "t_nova",      id = 1535,  word = "FIRE NOVA!", totem = "fire", dur = 5 },
    { key = "t_magma",     id = 8190,  word = "MAGMA!", totem = "fire", dur = 20 },
    { key = "t_frostres",  id = 8181,  word = "FROST WARD!", totem = "fire", dur = 120 },
    { key = "t_flametongue", id = 8227, word = "FLAMETONGUE!", totem = "fire", dur = 120 },
    -- water
    { key = "t_stream",    id = 5394,  word = "HEALING STREAM!", totem = "water", dur = 60 },
    { key = "t_spring",    id = 5675,  word = "MANA SPRING!", totem = "water", dur = 60 },
    { key = "t_poison",    id = 8166,  word = "POISON CLEANSING!", totem = "water", dur = 120 },
    { key = "t_disease",   id = 8170,  word = "DISEASE CLEANSING!", totem = "water", dur = 120 },
    { key = "t_fireres",   id = 8184,  word = "FIRE WARD!", totem = "water", dur = 120 },
    { key = "t_tide",      id = 16190, word = "MANA TIDE!", totem = "water", dur = 12, big = true },
    -- air
    { key = "t_grounding", id = 8177,  word = "GROUNDING!", totem = "air", dur = 45 },
    { key = "t_natureres", id = 10595, word = "NATURE WARD!", totem = "air", dur = 120 },
    { key = "t_windfury",  id = 8512,  word = "WINDFURY!", totem = "air", dur = 120 },
    { key = "t_grace",     id = 8835,  word = "GRACE OF AIR!", totem = "air", dur = 120 },
    { key = "t_windwall",  id = 15107, word = "WINDWALL!", totem = "air", dur = 120 },
    { key = "t_tranquil",  id = 25908, word = "TRANQUIL AIR!", totem = "air", dur = 120 },
    { key = "t_sentry",    id = 6495,  word = "SENTRY!", totem = "air", dur = 300 },
}

-- Buffs that come on their own (procs). Found by spell id or name, when the game lets addons
-- see that buff. Clearcasting also shows itself as Lightning Bolt costing no mana.
--   costFree  a spell whose mana cost drops to 0 while the proc is up
--   stacks    show the number of charges on the box
S.procs = {
    { key = "clear",  ids = { 16246 }, word = "CLEARCASTING!", el = "storm", short = "CLEAR", dur = 15, costFree = 403 },
    { key = "flurry", ids = { 16257, 16277, 16278, 16279, 16280 }, word = "FLURRY!", el = "air", short = "FLURRY",
      dur = 15, stacks = true },
}

local byID, byName, byKey = {}, {}, {}

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return H.Safe(C_Spell.GetSpellName, id) end
    if GetSpellInfo then return (H.Safe(GetSpellInfo, id)) end
end
S.SpellName = SpellName

local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return (H.Safe(C_Spell.GetSpellTexture, id)) end
    if GetSpellTexture then return (H.Safe(GetSpellTexture, id)) end
end

function S:Init()
    if self.ready then return end
    self.ready = true
    for _, def in ipairs(self.list) do
        if def.totem then
            def.el = def.totem
            def.size = def.size or 0.75
            def.sub = def.sub or "TOTEM"
        end
        local el = H.ELEMENT[def.el or "earth"]
        def.color = def.color or el.color
        def.shape = def.shape or el.shape
        byID[def.id] = def
        byKey[def.key] = def
        local name = SpellName(def.id)
        if name and not H.IsSecret(name) then
            def.name = name
            byName[name] = byName[name] or def
        end
        def.icon = SpellIcon(def.id)
    end
    for _, p in ipairs(self.procs) do
        local name = SpellName(p.ids[1])
        if name and not H.IsSecret(name) then p.name = name end
        p.icon = SpellIcon(p.ids[1])
        p.color = H.ELEMENT[p.el].color
    end
end

function S:Get(key)
    return byKey[key]
end

-- The definition for a spell the player just cast, or nil if it is not one of ours.
function S:Find(spellID)
    local def = byID[spellID]
    if def ~= nil then return def or nil end
    local name = SpellName(spellID)
    def = name and not H.IsSecret(name) and byName[name] or false
    byID[spellID] = def -- remember misses too
    return def or nil
end

-- By name (a totem's name as the game reports it: "Searing Totem").
function S:FindByName(name)
    if not name or H.IsSecret(name) then return nil end
    return byName[name]
end

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local costs = {}

-- Mana cost of a spell, or 0. Not hidden in combat.
function S:ManaCost(spell)
    local list = C_Spell and C_Spell.GetSpellPowerCost and H.Safe(C_Spell.GetSpellPowerCost, spell)
    if type(list) == "table" then
        for i = 1, #list do
            local c = list[i]
            if type(c) == "table" and not H.IsSecret(c.type) and c.type == MANA
                and not H.IsSecret(c.cost) and type(c.cost) == "number" then
                costs[spell] = c.cost
                return c.cost
            end
        end
        return 0
    end
    return costs[spell] or 0
end

-- true when the spell normally costs mana but right now costs none (Clearcasting), false when
-- it costs mana, nil when the game does not say (spell not known).
function S:CostsNothing(spell)
    local list = C_Spell and C_Spell.GetSpellPowerCost and H.Safe(C_Spell.GetSpellPowerCost, spell)
    if type(list) ~= "table" or H.IsSecret(list) then return nil end
    for i = 1, #list do
        local c = list[i]
        if type(c) == "table" and not H.IsSecret(c.type) and c.type == MANA
            and not H.IsSecret(c.cost) and type(c.cost) == "number" then
            if c.cost > 0 then costs[spell] = c.cost end
            return c.cost <= 0
        end
    end
    -- no mana entry at all: free now, if we have seen it cost mana before
    if #list == 0 and (costs[spell] or 0) > 0 then return true end
    return nil
end
