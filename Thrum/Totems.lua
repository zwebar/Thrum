-- Totems: four carved plaques above the mana trough, one per element (earth, fire, water,
-- air), each showing the totem that stands there and how long it has left.
--
-- A plaque lights up the moment you cast a totem (your own cast is never hidden) and then takes
-- the game's own timer for that slot (GetTotemDuration, a duration object the game keeps
-- counting even when the numbers are hidden from addons). Whether a totem still stands
-- may itself be secret in combat; then the plaque's look is set from it with the game's boolean
-- setters, so it is still right without the addon reading it.
-- This client has no Blizzard totem timer frame, so these plaques are the only ones you get.
local _, H = ...
local T = {}
H.Totems = T
local C = H.C

local ORDER = { "earth", "fire", "water", "air" }
local SMASH_DELAY = 0.35 -- a totem replaced by a new one is not "smashed": wait for the new cast
T.count = 0
local plaques, bySlot = {}, {}

local function Plaque(el, i)
    local HUD = H.HUD
    local P, body = HUD.PLAQUE, HUD.body
    local x = (i - (#ORDER + 1) / 2) * HUD.PITCH
    local f = CreateFrame("Frame", nil, T.row)
    f:SetSize(P, P)
    f:SetPoint("CENTER", body, "CENTER", x, HUD.TOTEM_Y)
    f:SetFrameLevel(body:GetFrameLevel() + 5)
    local s = { el = el, x = x, y = HUD.TOTEM_Y, frame = f, color = H.ELEMENT[el].color }

    s.shadow = H.Tex(f, "BACKGROUND", "totem", P, P, -1)
    s.shadow:SetPoint("CENTER", 2, -3)
    s.shadow:SetVertexColor(0, 0, 0, 0.5)
    s.back = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    s.back:SetSize(P * 0.5, P * 0.58)
    s.back:SetPoint("CENTER", 0, -3)
    s.back:SetColorTexture(C.bark[1], C.bark[2], C.bark[3], 0.9)
    s.glyph = H.Tex(f, "ARTWORK", "g_" .. el, P * 0.44, P * 0.44)
    s.glyph:SetPoint("CENTER", 0, -3)
    H.Tint(s.glyph, s.color)
    s.glyph:SetAlpha(0.45)

    -- what shows while a totem stands: its icon, the time on it, and a timer bar under the plaque
    local on = CreateFrame("Frame", nil, f)
    on:SetAllPoints(f)
    on:SetFrameLevel(f:GetFrameLevel() + 1)
    on:SetAlpha(0)
    s.active = on
    s.icon = on:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(P * 0.47, P * 0.54)
    s.icon:SetPoint("CENTER", f, "CENTER", 0, -3)
    s.icon:SetTexCoord(0.12, 0.88, 0.08, 0.92)

    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints(f)
    top:SetFrameLevel(f:GetFrameLevel() + 2)
    s.top = top
    s.frameTex = H.Tex(top, "ARTWORK", "totem", P, P)
    s.frameTex:SetPoint("CENTER")
    s.flash = H.Tex(top, "OVERLAY", "glow", P * 1.4, P * 1.4)
    s.flash:SetPoint("CENTER", 0, -3)
    s.flash:SetBlendMode("ADD")
    H.Tint(s.flash, s.color)
    s.flash:SetAlpha(0)

    local tf = CreateFrame("Frame", nil, on)
    tf:SetAllPoints(f)
    tf:SetFrameLevel(f:GetFrameLevel() + 3)
    s.time = H.Text(tf, "OVERLAY", 10, "OUTLINE")
    s.time:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)
    s.time:SetTextColor(C.bone[1], C.bone[2], C.bone[3])

    local track = on:CreateTexture(nil, "BACKGROUND")
    track:SetSize(P * 0.72, 5)
    track:SetPoint("TOP", f, "BOTTOM", 0, 1)
    track:SetColorTexture(C.bark[1], C.bark[2], C.bark[3], 0.9)
    local bar = CreateFrame("StatusBar", nil, on)
    bar:SetSize(P * 0.72 - 2, 3)
    bar:SetPoint("CENTER", track, "CENTER", 0, 0)
    bar:SetFrameLevel(f:GetFrameLevel() + 1)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(s.color[1], s.color[2], s.color[3], 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    s.bar = bar

    local ag = f:CreateAnimationGroup()
    local pop = ag:CreateAnimation("Scale")
    pop:SetDuration(0.22)
    pop:SetScaleFrom(1.25, 1.25)
    pop:SetScaleTo(1, 1)
    pop:SetOrigin("BOTTOM", 0, 0)
    pop:SetSmoothing("OUT")
    s.pop = ag
    return s
end

function T:Build()
    self.row = CreateFrame("Frame", nil, H.HUD.body)
    self.row:SetAllPoints(H.HUD.body)
    self.row:SetFrameLevel(H.HUD.body:GetFrameLevel() + 4)
    for i, el in ipairs(ORDER) do
        local s = Plaque(el, i)
        s.slot = H.Game.SLOT[el]
        plaques[i] = s
        bySlot[s.slot] = s
    end
    self.built = true
    self:ApplyOptions()
    H.Every(function(_, now) T:OnUpdate(now) end)
end

function T:ApplyOptions()
    self.row:SetShown(H.db.totems ~= false)
end

function T:Plaque(el)
    for _, s in ipairs(plaques) do
        if s.el == el then return s end
    end
end

local function Count()
    local n = 0
    for _, s in ipairs(plaques) do
        if s.on then n = n + 1 end
    end
    T.count = n
end

local function ShowActive(s, on)
    s.active:SetAlpha(on and 1 or 0)
    s.glyph:SetAlpha(on and 0 or 0.45)
end

local function Unbind(s)
    if s.bound then
        H.Game.Unbind(s.binding)
        s.bound, s.dur = false, nil
    end
end

-- The game's timer for this slot onto the plaque's bar and seconds.
local function Bind(s, d)
    if not d then return false end
    if not H.Game.BindBar(s.bar, d) then return false end
    local binding = H.Game.BindText(s.binding, s.time, d, "")
    if not binding then return false end
    s.binding, s.bound, s.dur = binding, true, d
    local rem, total = H.Game.Remaining(d), H.Game.Total(d)
    if rem and rem > 0 then
        s.expires = GetTime() + rem
        if total and total > 0 then
            s.duration = total
            if s.def then H.Timers.Learn("totem:" .. s.def.key, total) end
        end
    end
    return true
end

-- The totem went away. early: before its time was up (killed, or out of range of you).
local function Gone(s, early)
    s.on = false
    s.goneAt = GetTime()
    Count()
    local was = s.def
    H.Tween(0.3, function(p)
        s.active:SetAlpha(1 - p)
        s.glyph:SetAlpha(0.45 * p)
    end, function()
        if not s.on then
            ShowActive(s, false)
            Unbind(s)
        end
    end)
    if early then
        -- wait a moment: if a new totem is going down in its place, this was a replacement
        H.After(SMASH_DELAY, function()
            if s.on or (s.placedAt or 0) > s.goneAt then return end
            H.FX:Pop("SMASHED!", s.x, s.y + 30, C.red, 14, 16)
            H.FX:Element(s.el, s.x, s.y, 6, 30)
            H.HUD:Shake(2, 0.16)
        end)
    else
        H.FX:Ripple(s.x, s.y - 3, s.color, 14, 56, 0.35)
    end
    return was
end

-- You cast a totem: the plaque lights up at once, on our best guess of its time, then takes
-- the game's timer.
function T:Placed(def, quiet)
    local s = bySlot[H.Game.SLOT[def.totem]]
    if not s then return end
    local now = GetTime()
    Unbind(s)
    s.on, s.def, s.placedAt = true, def, now
    s.duration = H.Timers:Learned("totem:" .. def.key) or def.dur or 60
    s.expires = now + s.duration
    if def.icon then s.icon:SetTexture(def.icon) end
    s.time:SetTextColor(C.bone[1], C.bone[2], C.bone[3])
    s.bar:SetMinMaxValues(0, s.duration)
    s.bar:SetValue(s.duration)
    ShowActive(s, true)
    Count()
    if not quiet then
        s.pop:Stop()
        s.pop:Play()
        H.Cancel(s.flashTween)
        s.flashTween = H.Tween(0.45, function(p) s.flash:SetAlpha(0.9 * (1 - p)) end)
        H.FX:Element(s.el, s.x, s.y, 6, 34)
        H.FX:Ripple(s.x, s.y - 4, s.color, 16, 90, 0.4)
    end
    -- the game's own state for the slot (not in the demo: no real totem stands there)
    if not H.demo then H.After(0.05, function() T:Update(s.slot) end) end
end

-- The game says a slot changed (PLAYER_TOTEM_UPDATE), or we are catching up after a reload.
function T:Update(slot, quiet)
    local s = bySlot[slot]
    if not s or H.demo then return end
    local IsSecret = H.IsSecret
    local have, name, start, dur, icon = H.Game.TotemInfo(slot)
    local d = H.Game.TotemDuration(slot)
    if have == nil and not d then return end

    if IsSecret(have) then
        -- hidden in combat: let the game decide what shows; our own state stays on its estimate
        s.active:SetAlphaFromBoolean(have, 1, 0)
        s.glyph:SetAlphaFromBoolean(have, 0, 0.45)
        if IsSecret(icon) or icon ~= nil then s.icon:SetTexture(icon) end
        Bind(s, d)
        return
    end

    if not have then
        if s.on then Gone(s, s.expires and s.expires - GetTime() > 1.5) end
        return
    end

    -- a totem stands here
    local def = H.Spells:FindByName(name)
    if not s.on then
        -- one we did not see go down (a reload, or cast before the HUD existed)
        T:Placed(def or { key = "slot" .. slot, totem = s.el, dur = 60 }, true)
        s.def = def
    elseif def and s.def ~= def then
        s.def = def
    end
    if icon ~= nil and not IsSecret(icon) then s.icon:SetTexture(icon) end
    if not IsSecret(start) and not IsSecret(dur) and type(start) == "number" and type(dur) == "number" and dur > 0 then
        s.expires, s.duration = start + dur, dur
        if s.def then H.Timers.Learn("totem:" .. s.def.key, dur) end
    end
    ShowActive(s, true)
    if not Bind(s, d) then
        s.bar:SetMinMaxValues(0, s.duration or 1)
    end
end

function T:Refresh()
    for _, s in ipairs(plaques) do T:Update(s.slot, true) end
end

-- Clears every plaque (the demo ending).
function T:Clear()
    for _, s in ipairs(plaques) do
        s.on = false
        Unbind(s)
        ShowActive(s, false)
    end
    Count()
end

function T:OnUpdate(now)
    if now - (self.at or 0) < 0.1 then return end
    self.at = now
    for _, s in ipairs(plaques) do
        if s.on then
            local rem = s.bound and H.Game.Remaining(s.dur)
            if not rem then rem = s.expires - now end
            if rem <= 0 then
                -- its time ran out: gone quietly (the game's own update usually says so first)
                Gone(s, false)
            else
                if not s.bound then
                    s.bar:SetValue(rem)
                    if rem >= 60 then
                        s.time:SetFormattedText("%dm", math.ceil(rem / 60))
                    elseif rem >= 10 then
                        s.time:SetFormattedText("%d", math.floor(rem + 0.5))
                    else
                        s.time:SetFormattedText("%.1f", rem)
                    end
                end
                -- running out: the seconds turn ember, then red
                local c = rem < 5 and C.red or rem < 10 and C.ember or C.bone
                s.time:SetTextColor(c[1], c[2], c[3])
            end
        end
    end
end
