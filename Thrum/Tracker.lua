-- Tracker: listens to the game and turns what happens into HUD effects.
--
-- This client has no combat log for addons and hides some numbers in combat ("secret"
-- values: mana, aura, cooldown and totem data). So:
--   * mana goes straight to the widgets; spending is known from your own casts and their
--     mana cost (never hidden), which also starts the five-second-rule line;
--   * what you did comes from your own spell casts (never hidden), matched by spell name;
--   * cooldown, totem and aura boxes run on the game's own timers (duration objects bound to
--     the widgets), starting from an estimate until the game hands one over;
--   * the auras your casts create are found by their instance IDs, which are never hidden.
local _, H = ...
local T = {}
H.Tracker = T
local C = H.C
local IsSecret = H.IsSecret
local HUD, FX, Timers, Spells, Totems, Game

-- The other modules, once the HUD is built.
function T.Bind()
    HUD, FX, Timers, Spells, Totems, Game = H.HUD, H.FX, H.Timers, H.Spells, H.Totems, H.Game
    Spells:Init()
end

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

-- Spells that stop a cast: if the target's cast breaks right as one lands, BROKEN!
local STOPPERS = { earth = true, stomp = true }

local MISSES = {
    DODGE = "DODGED!", PARRY = "PARRIED!", MISS = "MISSED!", BLOCK = "BLOCKED!",
    IMMUNE = "IMMUNE!", RESIST = "RESISTED!", EVADE = "EVADED!", DEFLECT = "DEFLECTED!",
}

local M = {}       -- mana, when readable
T.lastUse = {}     -- when each spell was last cast (a fallback for cooldowns we cannot read)

-- A plain true/false out of something that might be hidden.
local function Bool(v)
    if IsSecret(v) then return false end
    return v and true or false
end

-- In a party or raid. Some things cannot be told apart from what your groupmates do
-- (whose crit that was, who got the kill, whose dispel), so those only show when you are alone.
local function Grouped()
    return IsInGroup and Bool(IsInGroup()) or false
end
T.Grouped = Grouped

--------------------------------------------------------------------------------
-- The bigger moments (shared with the demo)
--------------------------------------------------------------------------------
local Show = {}
T.Show = Show

-- amount: a number (it may be secret: it only goes to a font string), or nil.
function Show.Crit(amount)
    local x, y = FX:Word("CRIT!", { color = C.storm, shape = "bolt", size = 0.95, subValue = amount, textColor = C.bone })
    if x then FX:Particles("zap", x, y, C.storm, 5, 44) end
    HUD:Shake(3, 0.18)
end

function Show.Miss(word)
    FX:Word(word, { color = C.grey, shape = "wisp", size = 0.7, textColor = C.bone, hold = 0.3 })
end

function Show.Broken()
    local x, y = FX:Word("BROKEN!", { color = C.earth, shape = "stone", size = 1.1, sub = "INTERRUPTED", hold = 0.6 })
    if x then FX:Flourish(x, y, "earth", 1) end
    HUD:Shake(4, 0.22)
end

function Show.Slain()
    local x, y = FX:Word("SLAIN!", { color = C.bone, shape = "rune", size = 1.1, textColor = C.red, hold = 0.6 })
    if x then FX:Flourish(x, y, "air", 1) end
end

-- A proc came up (Clearcasting, Flurry): its word in the element's shape.
function Show.Proc(p)
    local el = H.ELEMENT[p.el] or H.ELEMENT.storm
    local x, y = FX:Word(p.word, { color = p.color, shape = el.shape, size = 0.85, hold = 0.5 })
    if x then FX:Element(p.el, x, y, 5, 34) end
end

function Show.Purged()
    local x, y = FX:Word("PURGED!", { color = C.air, shape = "rune", size = 1.0, textColor = C.storm, hold = 0.55 })
    if x then FX:Flourish(x, y, "air", 0.9) end
end

--------------------------------------------------------------------------------
-- Mana
--------------------------------------------------------------------------------
function T:Mana(instant)
    if H.demo then return end
    local v = UnitPower("player", MANA)
    local m = UnitPowerMax("player", MANA)
    HUD:SetMana(v, m, instant)
    if not IsSecret(v) and not IsSecret(m) and type(v) == "number" and type(m) == "number" and m > 0 then
        local prev = M.val
        M.val = v
        -- regeneration stays quiet; only a big gain at once (Mana Tide, a potion) shows
        if prev and not instant and v - prev >= math.max(150, m * 0.12) then HUD:Refill(v - prev) end
        HUD:SetFull(v >= m)
    else
        M.val = nil
        HUD:SetFull(nil)
    end
end

--------------------------------------------------------------------------------
-- Your casts
--------------------------------------------------------------------------------
local function Announce(def)
    if not H.db.words then return end
    local size = def.size or 1
    local x, y = FX:Word(def.word, {
        color = def.color, size = size, shape = def.shape, sub = def.sub,
        textColor = def.textColor, hold = def.big and 0.55 or nil,
    })
    if not x then return end
    if def.streak then
        FX:Lightning(x, y - 2, C.storm, (math.random() - 0.5) * 0.9, (100 * size + 60) * (H.db.fx or 1))
    end
    if def.big then
        FX:Flourish(x, y, def.el, 1)
        HUD:Shake(3, 0.2)
    elseif not def.totem then
        FX:Element(def.el, x, y, 4, 30)
    end
end
T.Announce = Announce

-- Cooldown boxes: start on the cooldown learned last time (or the spell's base value), then
-- take the game's own cooldown timer as soon as it exists.
local function BindCooldown(key, spell)
    local d = Game.SpellCooldown(spell)
    if d then return Timers:Bind(key, d) end
    -- no duration objects in this client: read the numbers if they are not hidden
    if not (C_Spell and C_Spell.GetSpellCooldown) then return false end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
    if not ok or IsSecret(info) or type(info) ~= "table" then return false end
    local start, dur = info.startTime, info.duration
    if IsSecret(start) or IsSecret(dur) or type(start) ~= "number" or type(dur) ~= "number" then return false end
    if dur > 2 and start + dur > GetTime() + 1 then Timers:Adjust(key, start + dur, dur) end
    return true
end

-- The three shocks share one cooldown, so they share one box.
local function StartCooldown(def, spellID)
    local key = def.shock and "cd:shock" or ("cd:" .. def.key)
    local label = def.shock and "SHOCKS" or def.short
    Timers:Start(key, {
        label = label, icon = def.icon, kind = "cd", learn = key, spell = def.name or spellID,
        ready = def.shock and "SHOCK READY" or (label .. " READY"), quietReady = def.shock,
        duration = Timers:Learned(key) or (def.shock and 6) or def.cd,
    })
    H.After(0.15, function() BindCooldown(key, def.name or spellID) end)
end

-- Cooldowns changed (a reset, a talent): re-read every cooldown box.
function T:CooldownsChanged()
    Timers:Each(function(t)
        if t.kind == "cd" and t.spell then BindCooldown(t.key, t.spell) end
    end)
end

--------------------------------------------------------------------------------
-- Aura boxes
--
-- The IDs of a unit's auras are never hidden, so the debuff (or buff) a cast created shows up
-- as a new ID on that unit right after the cast. The box is then bound to the game's timer for
-- that aura, and goes away when the aura does (broken, dispelled, or over). Without IDs the
-- box falls back to the estimate, checked against the aura by name when that is readable.
-- Lightning Shield is found the same way, and Purge watches the target's buffs.
--------------------------------------------------------------------------------
local AURAS = {
    player = { filter = "HELPFUL|PLAYER", seen = {}, present = {} },
    target = { filter = "HARMFUL|PLAYER", seen = {}, present = {} },
}
local CLAIM_WINDOW = 1.5 -- seconds for a cast's aura to appear before we decide it did not land

local function StartAura(def, spellID)
    local a = def.aura
    local key = "aura:" .. def.key
    local learnKey = key
    local dur = Timers:Learned(learnKey) or a.dur
    -- recasting on the same unit may refresh the aura it already has
    local old = Timers:Get(key)
    local prev = old and old.onUnit and old.auraID or nil
    local t = Timers:Start(key, {
        label = a.short, icon = def.icon, duration = dur, kind = a.kind, learn = learnKey, untimed = a.untimed,
        unit = a.unit, spell = def.name, born = GetTime(), onUnit = true,
    })
    if not t then return end
    t.auraID, t.prevID = nil, prev
    T:ScanAuras(a.unit)
    H.After(0.1, function() T:ScanAuras(a.unit) end)
    H.After(0.5, function() T:ScanAuras(a.unit) end)
    H.After(CLAIM_WINDOW + 0.05, function() T:ScanAuras(a.unit) end)
end

-- Fallback when the game gives no aura IDs: match by name when that is readable.
local function RefineByName(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return end
    local now = GetTime()
    local filter = (unit == "player") and "HELPFUL" or "HARMFUL|PLAYER"
    Timers:Each(function(t)
        if t.unit ~= unit or not t.spell or not t.onUnit then return end
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, t.spell, filter)
        if not ok or IsSecret(aura) then return end
        if aura == nil and now - (t.born or now) > CLAIM_WINDOW then
            Timers:Stop(t.key)
            return
        end
        if type(aura) ~= "table" then return end
        local exp, dur = aura.expirationTime, aura.duration
        if not IsSecret(exp) and not IsSecret(dur) and type(exp) == "number" and type(dur) == "number"
            and dur > 0 and exp > now then
            Timers:Adjust(t.key, exp, dur)
        end
    end)
end

-- fresh: the unit just changed (new target); auras it already has are not new.
function T:ScanAuras(unit, fresh)
    local a = AURAS[unit]
    if not a then return end
    local ids = Game.AuraIDs(unit, a.filter)
    if not ids then
        RefineByName(unit)
        if unit == "player" then T:Shield() end
        return
    end
    local now = GetTime()
    if fresh then
        for id in pairs(a.seen) do a.seen[id] = nil end
    end
    local present = {}
    for _, id in ipairs(ids) do
        if not IsSecret(id) then
            present[id] = true
            if not a.seen[id] then a.seen[id] = fresh and 0 or now end
        end
    end
    for id in pairs(a.seen) do
        if not present[id] then a.seen[id] = nil end
    end
    a.present, a.scanned = present, true

    -- boxes on this unit, oldest first
    local boxes, claimed = {}, {}
    Timers:Each(function(t)
        if t.unit == unit and t.onUnit then
            boxes[#boxes + 1] = t
            if t.auraID then claimed[t.auraID] = true end
        end
    end)
    if unit == "player" and T.shieldID then claimed[T.shieldID] = true end
    for _, st in pairs(T.procState or {}) do
        if st.id then claimed[st.id] = true end
    end
    table.sort(boxes, function(x, y) return (x.born or 0) < (y.born or 0) end)

    for _, t in ipairs(boxes) do
        if t.auraID then
            if present[t.auraID] then
                -- still there: re-read its timer (it may have been refreshed)
                if not t.untimed then Timers:Bind(t.key, Game.AuraDuration(unit, t.auraID)) end
            else
                Timers:Stop(t.key) -- the aura is gone: broken early, dispelled, or over
            end
        else
            local pick
            if t.prevID and present[t.prevID] and not claimed[t.prevID] then
                pick = t.prevID
            else
                local best
                for id, seenAt in pairs(a.seen) do
                    if not claimed[id] and seenAt >= (t.born or now) - 0.3 and (not best or seenAt < best) then
                        pick, best = id, seenAt
                    end
                end
            end
            if pick then
                claimed[pick] = true
                t.auraID, t.watched = pick, true
                if not t.untimed then Timers:Bind(t.key, Game.AuraDuration(unit, pick)) end
            elseif now - (t.born or now) > CLAIM_WINDOW then
                Timers:Stop(t.key) -- it never landed (missed, resisted, immune)
            end
        end
    end

    if unit == "player" then
        -- a Lightning Shield just cast takes the newest unclaimed buff
        if T.shieldPending then
            local pick, best
            for id, seenAt in pairs(a.seen) do
                if not claimed[id] and seenAt >= T.shieldPending - 0.3 and (not best or seenAt < best) then
                    pick, best = id, seenAt
                end
            end
            if pick then
                T.shieldID, T.shieldPending, T.shieldN = pick, nil, nil
            elseif now - T.shieldPending > CLAIM_WINDOW then
                T.shieldPending = nil
            end
        end
        T:Shield()
    end
end

--------------------------------------------------------------------------------
-- Lightning Shield
--------------------------------------------------------------------------------
function T:Shield()
    local id = T.shieldID
    if not id then
        -- not found by casting it: look it up by name/id when the game lets us (after a reload)
        local def = Spells:Get("shield")
        id = def and Game.PlayerAuraID({ def.id }, def.name)
        if id then T.shieldID = id end
    end
    if id and AURAS.player.scanned and not AURAS.player.present[id] then
        id = nil
    end
    if not id then
        if T.shieldID or HUD.shieldOn then
            T.shieldID, T.shieldN = nil, nil
            if HUD.shieldOn and HUD.inCombat and not H.demo then
                FX:Pop("SHIELD DOWN", HUD.SIDE_X, HUD.TOTEM_Y + 28, C.storm, 12, 14)
            end
            HUD:SetShield(false)
        end
        return
    end
    local count = Game.AuraCount("player", id, 1)
    local n = (not IsSecret(count)) and tonumber(count) or nil
    if n and T.shieldN and n < T.shieldN then HUD:ShieldCharge() end
    T.shieldN = n
    HUD:SetShield(true, count, n)
end

--------------------------------------------------------------------------------
-- Procs (Clearcasting, Flurry)
--------------------------------------------------------------------------------
T.procState = {}

function T:Procs()
    if H.demo then return end
    local now = GetTime()
    local present = AURAS.player.present or {}
    for _, p in ipairs(Spells.procs) do
        local st = T.procState[p.key]
        local id = Game.PlayerAuraID(p.ids, p.name)
        local on = id ~= nil
        if not on and st and st.id and present[st.id] then
            -- the game hides it now, but its ID is still on you
            on, id = true, st.id
        end
        if not on and p.costFree and Spells:CostsNothing(p.costFree) == true then on = true end
        local key = "proc:" .. p.key
        if on and not st then
            T.procState[p.key] = { id = id, at = now }
            if H.db.procs then
                if H.db.words then Show.Proc(p) end
                Timers:Start(key, { label = p.short, icon = p.icon, kind = "proc", learn = key,
                    duration = Timers:Learned(key) or p.dur })
                local t = Timers:Get(key)
                if t then t.watched = id ~= nil end
                if id then Timers:Bind(key, Game.AuraDuration("player", id)) end
            end
            if p.key == "clear" then HUD:SetClearcasting(true) end
        elseif on and st then
            if id and id ~= st.id then
                st.id = id
                Timers:Bind(key, Game.AuraDuration("player", id))
            end
        elseif not on and st then
            T.procState[p.key] = nil
            Timers:Stop(key)
            if p.key == "clear" then HUD:SetClearcasting(false) end
        end
        if on and p.stacks and id then Timers:SetCount(key, Game.AuraCount("player", id, 2)) end
    end
end

--------------------------------------------------------------------------------
-- Weapon imbue
--------------------------------------------------------------------------------
function T:Imbue()
    local info = Game.WeaponImbue()
    if info == nil then return end -- the game would not say
    local had = T.imbue
    if info then
        ThrumCharDB = ThrumCharDB or {}
        ThrumCharDB.imbueSeen = true
        if not HUD.imbueKnown then
            HUD.imbueKnown = true
            HUD:ApplyOptions()
        end
        local drift = had and had.seconds and info.seconds and math.abs((had.at + had.seconds - GetTime()) - info.seconds) or 99
        if not had or had.id ~= info.id or drift > 2 then
            info.at = GetTime()
            T.imbue = info
            HUD:SetImbue(info, T.imbueIcon)
        end
    else
        if had and H.db.words and H.db.imbue and not H.demo then
            FX:Word("IMBUE FADED!", { color = C.grey, shape = "stone", size = 0.7, textColor = C.bone })
        end
        T.imbue = false
        if had ~= false then HUD:SetImbue(nil) end
    end
end

--------------------------------------------------------------------------------
-- Purge: did a buff leave the target right as it went off?
--------------------------------------------------------------------------------
local targetBuffs, buffGoneAt = {}, -10

function T:TargetBuffs(fresh)
    local ids = Game.AuraIDs("target", "HELPFUL")
    if not ids then return end
    local now, present = GetTime(), {}
    for _, id in ipairs(ids) do
        if not IsSecret(id) then present[id] = true end
    end
    if not fresh then
        for id in pairs(targetBuffs) do
            if not present[id] then buffGoneAt = now end
        end
    end
    targetBuffs = present
    if T.purgeAt and now - T.purgeAt < 0.8 and buffGoneAt >= T.purgeAt - 0.4 then
        T.purgeAt = nil
        if H.db.words and not Grouped() then Show.Purged() end
    end
end

local function Purge(now)
    T.purgeAt = now
    T:TargetBuffs()
end

--------------------------------------------------------------------------------
-- The cast itself
--------------------------------------------------------------------------------
local function Broken()
    T.stopAt, T.interruptAt = nil, nil
    if H.db.words then Show.Broken() end
end

function T:Cast(spellID)
    if IsSecret(spellID) or type(spellID) ~= "number" then return end
    local now = GetTime()
    T.lastCastAt = now
    if HUD.casting then HUD:EndCast("done") end

    local cost = Spells:ManaCost(spellID)
    if cost > 0 then HUD:Spend(cost) end
    H.After(0.1, function() T:Procs() end)

    local def = Spells:Find(spellID)
    if not def then return end
    T.lastUse[def.key] = now
    Announce(def)
    if def.shock or (def.cd and not def.noBox) then StartCooldown(def, spellID) end
    if def.aura then StartAura(def, spellID) end
    if def.totem then Totems:Placed(def) end
    if def.imbue then
        T.imbueIcon = def.icon
        H.After(0.3, function() T:Imbue() end)
    end
    if def.lightningShield then
        T.shieldPending = now
        T:ScanAuras("player")
        H.After(0.1, function() T:ScanAuras("player") end)
        H.After(0.5, function() T:ScanAuras("player") end)
    end
    if def.key == "purge" then Purge(now) end
    if STOPPERS[def.key] then
        T.stopAt = now
        if T.interruptAt and now - T.interruptAt < 0.5 then Broken() end
    end
    T:UpdatePrompt()
end

-- Your own cast bar.
function T:OwnCast(channel)
    local name, s, e, spellID, ok, _
    if channel then
        ok, name, _, _, s, e, _, _, spellID = pcall(UnitChannelInfo, "player")
    else
        ok, name, _, _, s, e, _, _, _, spellID = pcall(UnitCastingInfo, "player")
    end
    if not ok then return end
    local def = (not IsSecret(spellID) and type(spellID) == "number") and Spells:Find(spellID) or nil
    local kind = def and (def.heal and "heal" or (def.el == "storm" and "storm")) or nil
    HUD:StartCast({ name = name, startMs = s, endMs = e, channel = channel, kind = kind })
end

function T:OwnCastMoved(channel)
    local s, e, ok, _
    if channel then
        ok, _, _, _, s, e = pcall(UnitChannelInfo, "player")
    else
        ok, _, _, _, s, e = pcall(UnitCastingInfo, "player")
    end
    if ok then HUD:MoveCast(s, e) end
end

--------------------------------------------------------------------------------
-- The target
--------------------------------------------------------------------------------
local function IsCasting(unit)
    if UnitCastingInfo then
        local ok, name = pcall(UnitCastingInfo, unit)
        if ok and (IsSecret(name) or name ~= nil) then return true end
    end
    if UnitChannelInfo then
        local ok, name = pcall(UnitChannelInfo, unit)
        if ok and (IsSecret(name) or name ~= nil) then return true end
    end
    return false
end

local function Present(v) return IsSecret(v) or v ~= nil end

-- What the target is casting, or nil. Parts the game hides stay secret: the HUD can still show
-- the name and icon, and turn "helpful" and "can't be interrupted" into colour and visibility.
local function ReadCast()
    local channel = false
    local ok, name, _, icon, startMs, endMs, _, _, notInt, spellID = pcall(UnitCastingInfo, "target")
    if not ok or not Present(name) then
        if not UnitChannelInfo then return nil end
        local ok2, n, _, i, s, e, _, ni, sid = pcall(UnitChannelInfo, "target")
        if not ok2 or not Present(n) then return nil end
        name, icon, startMs, endMs, notInt, spellID, channel = n, i, s, e, ni, sid, true
    end
    local cast = { name = name, icon = icon, startMs = startMs, endMs = endMs,
        notInterruptible = notInt, channel = channel }
    if Present(spellID) and C_Spell and C_Spell.IsSpellHelpful then
        local helpful = H.Safe(C_Spell.IsSpellHelpful, spellID)
        if IsSecret(helpful) then
            cast.helpful = helpful
        else
            cast.helpful = helpful and true or false
            -- readable: a helpful spell is a heal if it says so, otherwise a buff
            if cast.helpful then
                local desc = C_Spell.GetSpellDescription and H.Safe(C_Spell.GetSpellDescription, spellID)
                if type(desc) == "string" and not IsSecret(desc) and desc ~= "" then
                    cast.heal = desc:lower():find("heal", 1, true) ~= nil
                else
                    cast.heal = true
                end
            end
        end
    end
    return cast
end

-- Seconds until a spell's cooldown is over: the game's own timer when it may be read, else
-- its box, else when we last cast it.
local function CooldownLeft(key)
    local def = Spells:Get(key)
    if not def then return 0 end
    local rem = Game.Remaining(Game.SpellCooldown(def.name or def.id))
    if rem then return rem end
    local box = def.shock and "cd:shock" or ("cd:" .. key)
    if Timers:Get(box) then return math.max(0, Timers:Remaining(box)) end
    local last = def.shock and math.max(T.lastUse.earth or -999, T.lastUse.flame or -999, T.lastUse.frost or -999)
        or T.lastUse[key]
    local cd = def.shock and (Timers:Learned("cd:shock") or 6) or def.cd
    if last and cd then return math.max(0, last + cd - GetTime()) end
    return 0
end

-- Known, off cooldown, and enough mana.
local function Ready(key)
    local def = Spells:Get(key)
    if not def or CooldownLeft(key) > 0.1 then return false end
    if not (C_Spell and C_Spell.IsSpellUsable) then return false end
    -- by name, so the highest rank you know is the one checked
    local ok, usable = pcall(C_Spell.IsSpellUsable, def.name or def.id)
    return ok and Bool(usable)
end

-- Ways to stop a cast, best first. Grounding Totem only for harmful spells (it eats one).
local STOP_WITH = {
    { "earth", "SHOCK IT!" },
    { "stomp", "STOMP IT!" },
    { "t_grounding", "GROUND IT!", harmful = true },
}

-- While the target casts something that can be stopped: SHOCK IT!, or with the shocks on
-- cooldown STOMP IT! / GROUND IT!, or failing all of those a quieter "SHOCK IN 3".
function T:UpdatePrompt()
    local text, mode
    if T.casting and H.db.prompt and HUD.hasTarget then
        local cast = T.cast
        local shielded = cast and not IsSecret(cast.notInterruptible) and cast.notInterruptible
        if not shielded then
            for _, way in ipairs(STOP_WITH) do
                local fits = not way.harmful or (cast and not IsSecret(cast.helpful) and cast.helpful == false)
                if fits and Ready(way[1]) then
                    text, mode = way[2], "go"
                    break
                end
            end
            if not text and Spells:Get("earth") then
                local wait = CooldownLeft("earth")
                text = wait > 0 and string.format("SHOCK IN %d", math.ceil(wait)) or "NEED MANA"
                mode = "wait"
            end
        end
    end
    HUD:SetPrompt(text, text and T.cast or nil, mode)
end

function T:TargetCasting(on)
    T.casting = on
    T.castStart = on and GetTime() or nil
    T.cast = on and ReadCast() or nil
    T:UpdatePrompt()
end

-- The cast became interruptible or stopped being so.
function T:CastChanged()
    if T.casting then T:TargetCasting(true) end
end

-- by: who broke the cast, when the game says (it may be missing or hidden).
function T:Interrupted(by)
    local now = GetTime()
    T:TargetCasting(false)
    local mine -- true, false, or nil when we cannot tell
    if not IsSecret(by) and type(by) == "string" then
        local me = UnitGUID and UnitGUID("player")
        if not IsSecret(me) and type(me) == "string" then mine = (by == me) end
    end
    -- Without a name on it, an interrupt that lands as you shock is yours when you are
    -- alone; in a group it could be anyone's, so it does not count.
    if mine == nil then mine = not Grouped() end
    if not mine then
        T.interruptAt = nil
        return
    end
    T.interruptAt = now
    if T.stopAt and now - T.stopAt < 0.7 then Broken() end
end

function T:TargetChanged()
    local exists = Bool(UnitExists("target"))
    local hostile = exists and Bool(UnitCanAttack("player", "target")) and not Bool(UnitIsDead("target"))
    HUD.hasTarget = hostile
    T.slainDone = not hostile
    T.casting = hostile and IsCasting("target")
    T.castStart = T.casting and GetTime() or nil
    T.cast = T.casting and ReadCast() or nil
    T.purgeAt = nil
    T:UpdatePrompt()
    -- Boxes for the old target keep running on the game's timer; they just can no longer be
    -- checked against the unit, which is someone else now.
    Timers:Each(function(t)
        if t.unit == "target" then t.onUnit, t.watched = false, false end
    end)
    T:ScanAuras("target", true)
    T:TargetBuffs(true)
end

function T:TargetHealth()
    if T.slainDone or not HUD.hasTarget then return end
    if Bool(UnitIsDead("target")) then
        T.slainDone = true
        HUD.hasTarget = false
        T:TargetCasting(false)
        local now = GetTime()
        -- alone, a target that dies mid-fight is your kill; in a group it may not be
        if H.db.words and not Grouped() and (HUD.inCombat or now - (T.lastCastAt or -10) < 6) then
            Show.Slain()
        end
    end
end

-- What just happened to the target: CRIT!, RESISTED!... The game does not say who dealt the
-- hit, so this is only shown when you are alone and it can only be yours.
function T:TargetHit(action, flag, amount)
    if not H.db.hits or IsSecret(action) or Grouped() then return end
    local now = GetTime()
    if action == "WOUND" then
        if not IsSecret(flag) and flag == "CRITICAL" and now - (T.lastCrit or -10) > 0.25 then
            T.lastCrit = now
            local sub
            if IsSecret(amount) or (type(amount) == "number" and amount > 0) then sub = amount end
            Show.Crit(sub)
        end
    else
        local word = MISSES[action]
        if word and now - (T.lastMiss or -10) > 0.4 then
            T.lastMiss = now
            Show.Miss(word)
        end
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
function T:Refresh()
    HUD.inCombat = Bool(UnitAffectingCombat("player"))
    M.val = nil
    T:Mana(true)
    T:TargetChanged()
    T:ScanAuras("player", true)
    Totems:Refresh()
    T:Imbue()
    T:Procs()
end

function T:OnUpdate(now)
    if H.demo then return end

    -- Ghost Wolf turns the water pale
    local wolf = Timers:Get("aura:wolf") ~= nil
    if wolf ~= (HUD.palette == "spirit") then HUD:SetPalette(wolf and "spirit" or "normal") end

    -- the imbue's time, and Clearcasting by its mana cost, every second
    if now - (T.slowAt or 0) > 1 then
        T.slowAt = now
        T:Imbue()
        if T.procState.clear or (Spells:Get("bolt") and HUD.inCombat) then T:Procs() end
    end

    -- keep the prompt honest
    if T.casting and now - (T.promptAt or 0) > 0.2 then
        T.promptAt = now
        if T.castStart and now - T.castStart > 12 then
            T:TargetCasting(false)
        else
            T:UpdatePrompt()
        end
    end
end

function T:Start()
    T.Bind()
    T.started = true
    HUD.imbueKnown = ThrumCharDB and ThrumCharDB.imbueSeen or false
    HUD:ApplyOptions()

    local main = CreateFrame("Frame")
    main:RegisterEvent("PLAYER_ENTERING_WORLD")
    main:RegisterEvent("PLAYER_TARGET_CHANGED")
    main:RegisterEvent("PLAYER_REGEN_DISABLED")
    main:RegisterEvent("PLAYER_REGEN_ENABLED")
    main:RegisterEvent("UI_ERROR_MESSAGE")
    main:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    main:RegisterEvent("PLAYER_TOTEM_UPDATE")
    main:RegisterEvent("WEAPON_ENCHANT_CHANGED")
    main:SetScript("OnEvent", function(_, event, a, b)
        if event == "PLAYER_ENTERING_WORLD" then
            T:Refresh()
        elseif event == "PLAYER_TARGET_CHANGED" then
            T:TargetChanged()
        elseif event == "PLAYER_REGEN_DISABLED" then
            HUD.inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            HUD.inCombat = false
            T:Mana()
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            T:CooldownsChanged()
        elseif event == "PLAYER_TOTEM_UPDATE" then
            if not H.demo and not IsSecret(a) and type(a) == "number" then Totems:Update(a) end
        elseif event == "WEAPON_ENCHANT_CHANGED" then
            if not H.demo then T:Imbue() end
        elseif event == "UI_ERROR_MESSAGE" then
            if not IsSecret(b) and b ~= nil and b == ERR_OUT_OF_MANA then HUD:Error() end
        end
    end)

    local me = CreateFrame("Frame")
    me:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    me:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    me:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    me:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    me:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    me:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    me:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    me:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    me:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
    me:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    me:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    me:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    me:RegisterUnitEvent("UNIT_AURA", "player")
    me:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    me:SetScript("OnEvent", function(_, event, _, a, b)
        if H.demo and event ~= "UNIT_AURA" then return end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            T:Cast(b)
        elseif event == "UNIT_SPELLCAST_START" then
            T:OwnCast(false)
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            T:OwnCast(true)
        elseif event == "UNIT_SPELLCAST_DELAYED" then
            T:OwnCastMoved(false)
        elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            T:OwnCastMoved(true)
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            HUD:EndCast("interrupted")
        elseif event == "UNIT_SPELLCAST_FAILED" then
            HUD:EndCast("failed")
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            HUD:EndCast(event == "UNIT_SPELLCAST_CHANNEL_STOP" and "done" or "stopped")
        elseif event == "UNIT_AURA" then
            if not H.demo then
                T:ScanAuras("player")
                T:Procs()
            end
        elseif event == "UNIT_INVENTORY_CHANGED" then
            T:Imbue()
        elseif event == "UNIT_MAXPOWER" then
            T:Mana()
        else
            -- a: the power type token
            if IsSecret(a) or a == "MANA" then T:Mana() end
        end
    end)

    -- Registered for the target only, so the handlers never need the unit argument (which
    -- may be hidden). The one argument used, who interrupted, is checked before use.
    local them = CreateFrame("Frame")
    them:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
    them:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    them:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
    them:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
    them:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "target")
    them:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
    them:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "target")
    them:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
    them:RegisterUnitEvent("UNIT_AURA", "target")
    them:RegisterUnitEvent("UNIT_HEALTH", "target")
    them:SetScript("OnEvent", function(_, event, _, _, _, by)
        if H.demo then return end
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            T:TargetCasting(true)
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            T:Interrupted(by)
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            T:CastChanged()
        elseif event == "UNIT_AURA" then
            T:ScanAuras("target")
            T:TargetBuffs()
        elseif event == "UNIT_HEALTH" then
            T:TargetHealth()
        else
            T:TargetCasting(false)
        end
    end)

    local hitThem = CreateFrame("Frame")
    hitThem:RegisterUnitEvent("UNIT_COMBAT", "target")
    hitThem:SetScript("OnEvent", function(_, _, _, action, flag, amount)
        if H.demo then return end
        T:TargetHit(action, flag, amount)
    end)

    H.Every(function(_, now) T:OnUpdate(now) end)
    T:Refresh()
end
