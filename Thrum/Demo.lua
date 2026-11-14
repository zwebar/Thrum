-- Demo: /thrum test plays a short scripted fight so every effect can be seen (and the HUD
-- placed) without pulling a mob. Live updates are paused while it runs.
local _, H = ...
local Demo = {}
H.Demo = Demo
local C = H.C

local MAX = 1800

function Demo:Run()
    if H.demo then return end
    H.demo = true
    local HUD, FX, Timers, S, T, Totems = H.HUD, H.FX, H.Timers, H.Spells, H.Tracker, H.Totems
    T.Bind()
    HUD.root:Show()
    Timers:Clear()
    Totems:Clear()
    H.Print("demo: a 15-second pretend fight")

    local mana = MAX

    local function at(time, fn)
        H.After(time, function()
            if H.demo then fn() end
        end)
    end
    local function setMana(v, instant)
        mana = v
        HUD:SetMana(v, MAX, instant)
    end
    local function spend(cost)
        setMana(math.max(0, mana - cost))
        HUD:Spend(cost)
    end
    local function cast(key)
        local def = S:Get(key)
        if def then T.Announce(def) end
        return def
    end
    local function box(key, label, kind, duration, o)
        local def = S:Get(key)
        local opts = { label = label, icon = def and def.icon, duration = duration, kind = kind }
        for k, v in pairs(o or {}) do opts[k] = v end
        Timers:Start("demo:" .. label, opts)
    end
    local function totem(key, dur)
        local def = S:Get(key)
        if not def then return end
        cast(key)
        Totems:Placed({ key = def.key, totem = def.totem, icon = def.icon, dur = dur })
    end
    local function castBar(key, secs)
        local def = S:Get(key)
        local now = GetTime() * 1000
        HUD:StartCast({ name = def and def.name or key, startMs = now, endMs = now + secs * 1000,
            kind = def and (def.heal and "heal" or def.el == "storm" and "storm") or nil })
    end
    local function heal(name)
        local now = GetTime() * 1000
        return {
            name = name, icon = C_Spell and C_Spell.GetSpellTexture and H.Safe(C_Spell.GetSpellTexture, 331),
            startMs = now, endMs = now + 2500, helpful = true, heal = true,
        }
    end

    setMana(MAX, true)
    HUD:SetPrompt(nil)
    HUD:SetShield(false)
    HUD.imbueKnown = true
    HUD:ApplyOptions()
    HUD:SetImbue(nil)
    HUD:SetPalette("spirit")

    at(0.2, function() cast("wolf") end)
    at(0.9, function() HUD:SetPalette("normal") end)
    at(1.0, function()
        spend(45)
        cast("shield")
        HUD:SetShield(true, "3", 3)
    end)
    at(1.5, function()
        spend(60)
        local def = cast("windfury")
        HUD:SetImbue({ seconds = 300, icon = def and def.icon })
    end)
    at(2.0, function() spend(80); totem("t_strength", 120) end)
    at(2.3, function() spend(70); totem("t_searing", 30) end)
    at(2.6, function() spend(60); totem("t_spring", 60) end)
    at(2.9, function() spend(90); totem("t_windfury", 120) end)
    at(3.2, function() castBar("bolt", 1.2) end)
    at(4.4, function() HUD:EndCast("done"); spend(105); cast("bolt") end)
    at(4.6, function() T.Show.Crit(412) end)
    at(5.0, function() HUD:SetPrompt("SHOCK IT!", heal("Healing Wave"), "go") end)
    at(5.6, function()
        HUD:SetPrompt(nil)
        spend(140)
        cast("earth")
        box("earth", "SHOCKS", "cd", 6, { ready = "SHOCK READY", quietReady = true })
    end)
    at(5.75, function() T.Show.Broken() end)
    at(6.3, function()
        T.Show.Proc(S.procs[1])
        box("bolt", "CLEAR", "proc", 15)
        HUD:SetClearcasting(true)
    end)
    at(7.0, function() castBar("chain", 1.5) end)
    at(8.5, function()
        HUD:EndCast("done")
        cast("chain")
        HUD:SetClearcasting(false)
        Timers:Stop("demo:CLEAR")
    end)
    at(8.8, function() HUD:SetShield(true, "2", 2); HUD:ShieldCharge() end)
    at(9.3, function()
        local s = Totems:Plaque("fire")
        if s then
            s.on = false
            H.Tween(0.3, function(p) s.active:SetAlpha(1 - p); s.glyph:SetAlpha(0.45 * p) end)
            FX:Pop("SMASHED!", s.x, s.y + 30, C.red, 14, 16)
            FX:Element("fire", s.x, s.y, 6, 30)
            HUD:Shake(2, 0.16)
        end
    end)
    at(9.8, function() castBar("wave", 1.5) end)
    at(11.3, function() HUD:EndCast("done"); spend(250); cast("wave") end)
    at(11.8, function()
        spend(120)
        cast("flame")
        box("flame", "FLAME", "dot", 12)
        box("earth", "SHOCKS", "cd", 6, { ready = "SHOCK READY", quietReady = true })
    end)
    at(12.4, function() T.Show.Miss("RESISTED!") end)
    at(13.0, function() spend(80); cast("purge") end)
    at(13.2, function() T.Show.Purged() end)
    at(13.9, function() T.Show.Slain() end)
    at(14.4, function() HUD:Error() end)
    at(15.0, function() Demo:Stop() end)
end

function Demo:Stop()
    if not H.demo then return end
    H.demo = false
    local HUD, T = H.HUD, H.Tracker
    H.Timers:Clear()
    H.Totems:Clear()
    HUD:SetPrompt(nil)
    HUD:SetFSR(nil)
    HUD:SetClearcasting(false)
    HUD:SetShield(false)
    HUD:SetPalette("normal")
    if T.started then
        HUD.imbueKnown = ThrumCharDB and ThrumCharDB.imbueSeen or false
        T.imbue = nil
        HUD:SetImbue(nil)
        HUD:ApplyOptions()
        T:Refresh()
    else
        -- not a shaman: put the HUD away again
        HUD:SetMana(MAX, MAX, true)
        HUD:SetImbue(nil)
        HUD.root:Hide()
    end
    H.Print("demo over. /thrum unlock to move the HUD.")
end
