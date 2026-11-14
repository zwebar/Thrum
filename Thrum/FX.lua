-- FX: the carved, elemental effects. Word bursts cut into stone, flame, leaf or water shapes,
-- small floating pops, ripples, spirit rays, lightning arcs, and element particles (pebbles,
-- embers, droplets, motes of air, sparks, leaves). Everything is placed relative to the centre
-- of the HUD.
local _, H = ...
local FX = {}
H.FX = FX
local C = H.C

-- Word bursts land to the left and right, a little above the HUD: clear of the middle of the
-- screen (your character and your target) and of the unit frames lower down at the sides.
-- Each slot: side (-1 left, 1 right), how far its inner edge sits from the HUD's centre, height.
local WORD_SLOTS = { { -1, 170, 124 }, { 1, 178, 128 }, { -1, 194, 170 }, { 1, 202, 174 }, { -1, 178, 214 }, { 1, 186, 218 } }

local words, pops, sprites = {}, {}, {}
local slot, seq = 0, 0

function FX:Build()
    self.layer = H.HUD.fx
end

local SetFontSize = H.SetFont

--------------------------------------------------------------------------------
-- Word bursts
--------------------------------------------------------------------------------
local function NewWord()
    local f = CreateFrame("Frame", nil, FX.layer)
    f:SetSize(10, 10)

    f.shadow = H.Tex(f, "BACKGROUND", "stone", 160)
    f.shadow:SetPoint("CENTER", 5, -6)
    f.shadow:SetVertexColor(0, 0, 0, 0.45)
    f.shape = H.Tex(f, "BORDER", "stone", 160)
    f.shape:SetPoint("CENTER")

    f.back = H.Text(f, "ARTWORK", 24)
    f.back:SetPoint("CENTER", 2, -3)
    f.back:SetTextColor(C.bark[1], C.bark[2], C.bark[3])
    f.text = H.Text(f, "OVERLAY", 24)
    f.text:SetPoint("CENTER")
    f.sub = H.Text(f, "OVERLAY", 12, "OUTLINE")
    f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, 0)

    local ag = f:CreateAnimationGroup()
    ag:SetToFinalAlpha(true)

    -- rises out of the ground rather than punching in: a quick grow with a little overshoot
    local grow = ag:CreateAnimation("Scale")
    grow:SetOrder(1)
    grow:SetDuration(0.16)
    grow:SetScaleFrom(0.3, 0.3)
    grow:SetScaleTo(1.1, 1.1)
    grow:SetOrigin("BOTTOM", 0, 0)
    grow:SetSmoothing("OUT")

    local settle = ag:CreateAnimation("Scale")
    settle:SetOrder(2)
    settle:SetDuration(0.12)
    settle:SetScaleFrom(1.1, 1.1)
    settle:SetScaleTo(1, 1)
    settle:SetOrigin("BOTTOM", 0, 0)
    settle:SetSmoothing("IN_OUT")

    local fade = ag:CreateAnimation("Alpha")
    fade:SetOrder(3)
    fade:SetDuration(0.3)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)

    local drift = ag:CreateAnimation("Translation")
    drift:SetOrder(3)
    drift:SetDuration(0.3)
    drift:SetOffset(0, 16)
    drift:SetSmoothing("IN")

    f.ag, f.tail = ag, { fade, drift }
    ag:SetScript("OnFinished", function()
        f:Hide()
        f.busy = false
    end)
    return f
end

local function AcquireWord()
    for i = 1, #words do
        if not words[i].busy then return words[i] end
    end
    if #words >= 8 then
        -- All in use: recycle the oldest.
        local oldest = words[1]
        for i = 2, #words do
            if words[i].born < oldest.born then oldest = words[i] end
        end
        oldest.ag:Stop()
        return oldest
    end
    local f = NewWord()
    words[#words + 1] = f
    return f
end

-- FX:Word("EARTH SHOCK!", { color = C.earth, size = 1, shape = "stone", sub = "TOTEM", hold = 0.45 })
-- subValue: a number shown under the word that may be secret (it goes straight to the font string).
function FX:Word(text, o)
    if not self.layer then return end
    o = o or {}
    local f = AcquireWord()
    f.busy = true
    seq = seq + 1
    f.born = seq

    local size = o.size or 1
    local font = math.floor(20 * size + 0.5)
    SetFontSize(f.text, font)
    SetFontSize(f.back, font)
    f.text:SetText(text)
    f.back:SetText(text)
    local tc = o.textColor or C.bone
    f.text:SetTextColor(tc[1], tc[2], tc[3])

    local hasSub = o.sub ~= nil or o.subValue ~= nil
    if o.subValue ~= nil then
        f.sub:SetFormattedText("%d", o.subValue)
    elseif o.sub then
        f.sub:SetText(o.sub)
    end
    f.sub:SetTextColor(C.bone[1], C.bone[2], C.bone[3])
    f.sub:SetShown(hasSub)

    local w = math.max(f.text:GetStringWidth() or 0, #text * font * 0.5)
    local sw = math.max(w * 1.35 + 34, 90 * size)
    local sh = math.max(font * 3.1, sw * 0.58) + (hasSub and 12 or 0)
    local art = H.ART .. (o.shape or "stone")
    f.shape:SetTexture(art)
    f.shadow:SetTexture(art)
    f.shape:SetSize(sw, sh)
    f.shadow:SetSize(sw, sh)
    H.Tint(f.shape, o.color or C.earth)

    local tilt = o.tilt or ((math.random() * 2 - 1) * 0.08)
    f.text:SetRotation(tilt)
    f.back:SetRotation(tilt)

    -- /thrum fx: the whole burst can be made smaller or larger. Offsets are in the frame's
    -- own scale, hence the division below.
    local s = H.db.fx or 1
    slot = slot % #WORD_SLOTS + 1
    local side, edge, height = WORD_SLOTS[slot][1], WORD_SLOTS[slot][2], WORD_SLOTS[slot][3]
    -- placed by its inner edge, so a wide burst grows outward instead of over the HUD
    local x = side * (edge + sw * s / 2 + math.random() * 8)
    local y = height + (math.random() * 2 - 1) * 6
    f:SetScale(s)
    f:ClearAllPoints()
    f:SetPoint("CENTER", self.layer, "CENTER", x / s, y / s)
    f:SetFrameLevel(self.layer:GetFrameLevel() + 1 + (seq % 30))

    local hold = o.hold or 0.45
    for i = 1, #f.tail do f.tail[i]:SetStartDelay(hold) end
    f.ag:Stop()
    f:SetAlpha(1)
    f:Show()
    f.ag:Play()

    -- The carving sways a little while it is up, like a sign on a post.
    H.Cancel(f.sway)
    local total = 0.28 + hold + 0.3
    local base = (math.random() * 2 - 1) * 0.12
    local phase = math.random() * 6.28
    f.sway = H.Tween(total, function(p)
        local r = base + 0.035 * math.sin(phase + p * total * 9)
        f.shape:SetRotation(r)
        f.shadow:SetRotation(r)
    end)
    return x, y
end

--------------------------------------------------------------------------------
-- Pops: small floating text
--------------------------------------------------------------------------------
local function NewPop()
    local f = CreateFrame("Frame", nil, FX.layer)
    f:SetSize(10, 10)
    f.back = H.Text(f, "ARTWORK", 14)
    f.back:SetPoint("CENTER", 1, -2)
    f.back:SetTextColor(C.bark[1], C.bark[2], C.bark[3])
    f.text = H.Text(f, "OVERLAY", 14)
    f.text:SetPoint("CENTER")

    local ag = f:CreateAnimationGroup()
    ag:SetToFinalAlpha(true)
    local pop = ag:CreateAnimation("Scale")
    pop:SetOrder(1)
    pop:SetDuration(0.12)
    pop:SetScaleFrom(1.5, 1.5)
    pop:SetScaleTo(1, 1)
    pop:SetOrigin("CENTER", 0, 0)
    pop:SetSmoothing("OUT")
    local rise = ag:CreateAnimation("Translation")
    rise:SetOrder(2)
    rise:SetDuration(0.6)
    rise:SetOffset(0, 22)
    rise:SetSmoothing("OUT")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetOrder(2)
    fade:SetDuration(0.32)
    fade:SetStartDelay(0.28)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    f.ag, f.rise = ag, rise
    ag:SetScript("OnFinished", function()
        f:Hide()
        f.busy = false
    end)
    return f
end

function FX:Pop(text, x, y, color, size, rise)
    if not self.layer then return end
    local f
    for i = 1, #pops do
        if not pops[i].busy then f = pops[i]; break end
    end
    if not f then
        if #pops >= 14 then return end
        f = NewPop()
        pops[#pops + 1] = f
    end
    f.busy = true
    size = size or 14
    SetFontSize(f.text, size)
    SetFontSize(f.back, size)
    f.text:SetText(text)
    f.back:SetText(text)
    color = color or C.bone
    f.text:SetTextColor(color[1], color[2], color[3])
    local tilt = (math.random() * 2 - 1) * 0.06
    f.text:SetRotation(tilt)
    f.back:SetRotation(tilt)
    f.rise:SetOffset(0, rise or 22)
    f:ClearAllPoints()
    f:SetPoint("CENTER", self.layer, "CENTER", x, y)
    f.ag:Stop()
    f:SetAlpha(1)
    f:Show()
    f.ag:Play()
end

--------------------------------------------------------------------------------
-- Sprites: pooled textures moved by tweens
--------------------------------------------------------------------------------
local function Sprite(file, blend)
    local t
    for i = 1, #sprites do
        if not sprites[i].busy then t = sprites[i]; break end
    end
    if not t then
        if #sprites >= 80 then return nil end
        t = FX.layer:CreateTexture(nil, "ARTWORK")
        sprites[#sprites + 1] = t
    end
    t.busy = true
    t:SetTexture(H.ART .. file)
    t:SetBlendMode(blend or "BLEND")
    t:SetRotation(0)
    t:SetVertexColor(1, 1, 1, 1)
    t:SetAlpha(1)
    t:Show()
    return t
end

local function Release(t)
    t:Hide()
    t.busy = false
end

local function Place(t, x, y)
    t:ClearAllPoints()
    t:SetPoint("CENTER", FX.layer, "CENTER", x, y)
end

-- An expanding ripple, like a stone dropped in water.
function FX:Ripple(x, y, color, from, to, dur)
    if not self.layer then return end
    local t = Sprite("ripple")
    if not t then return end
    H.Tint(t, color or C.white)
    Place(t, x, y)
    H.Tween(dur or 0.4, function(p)
        local e = H.Ease.outCubic(p)
        local s = from + (to - from) * e
        t:SetSize(s, s * 0.82)
        t:SetAlpha(1 - p * p)
    end, function() Release(t) end)
end

-- How each particle moves: speed out, gravity (negative falls), spin, life, size.
local MOTION = {
    pebble = { out = 1.0, grav = -160, spin = 4, life = 0.5, size = 11 },
    ember  = { out = 0.55, grav = 110, spin = 0, life = 0.65, size = 12 },
    drop   = { out = 0.9, grav = -220, spin = 0, life = 0.55, size = 12 },
    mote   = { out = 0.8, grav = 30, spin = 0, life = 0.7, size = 14, swirl = 2.4, blend = "ADD" },
    zap    = { out = 1.0, grav = 0, spin = 2, life = 0.3, size = 14 },
    leaf_p = { out = 0.8, grav = -60, spin = 5, life = 0.85, size = 14, sway = 26 },
}
local PARTICLE = { pebble = "pebble", ember = "ember", drop = "drop", mote = "mote", zap = "zap", leaf = "leaf_p" }

-- Element particles thrown outward: kind is pebble, ember, drop, mote, zap or leaf.
function FX:Particles(kind, x, y, color, n, reach)
    if not self.layer then return end
    local file = PARTICLE[kind] or "pebble"
    local m = MOTION[file]
    reach = reach or 34
    n = n or 5
    local a0 = math.random() * 6.28
    for i = 1, n do
        local t = Sprite(file, m.blend)
        if not t then return end
        H.Tint(t, color or C.white)
        local a = a0 + (i / n) * 6.28 + (math.random() - 0.5) * 0.5
        local d = reach * (0.7 + math.random() * 0.6) * m.out
        local s0 = m.size * (0.8 + math.random() * 0.5)
        local spin = (math.random() - 0.5) * m.spin
        local life = m.life * (0.85 + math.random() * 0.3)
        local rot0 = math.random() * 6.28
        H.Tween(life, function(p)
            local e = H.Ease.outCubic(p)
            local px = x + math.cos(a) * d * e
            local py = y + math.sin(a) * d * e + 0.5 * m.grav * (p * life) ^ 2
            if m.swirl then
                local aa = a + m.swirl * p
                px = x + math.cos(aa) * d * e
                py = y + math.sin(aa) * d * e + m.grav * p * life
            end
            if m.sway then px = px + math.sin(p * 9 + i) * m.sway * p end
            Place(t, px, py)
            local s = s0 * (1 - p * 0.5)
            t:SetSize(s, s)
            if m.spin > 0 then t:SetRotation(rot0 + spin * p * 3) end
            t:SetAlpha(1 - p * p * p)
        end, function() Release(t) end)
    end
end

-- The particles of an element (earth, fire, water, air, storm, life).
function FX:Element(el, x, y, n, reach)
    local e = H.ELEMENT[el] or H.ELEMENT.earth
    self:Particles(e.particle, x, y, e.color, n, reach)
end

-- Spirit rays that turn slowly and fade.
function FX:Rays(x, y, color, size, dur)
    if not self.layer then return end
    local t = Sprite("rays", "ADD")
    if not t then return end
    H.Tint(t, color or C.white)
    Place(t, x, y)
    local r0 = math.random() * 6.28
    H.Tween(dur or 0.6, function(p)
        local s = size * (0.75 + 0.35 * H.Ease.outCubic(p))
        t:SetSize(s, s)
        t:SetRotation(r0 + p * 0.35)
        t:SetAlpha(0.55 * math.sin(p * math.pi))
    end, function() Release(t) end)
end

-- A lightning arc that cracks across and flickers out.
function FX:Lightning(x, y, color, angle, length)
    if not self.layer then return end
    local t = Sprite("arc", "ADD")
    if not t then return end
    H.Tint(t, color or C.storm)
    Place(t, x, y)
    t:SetRotation(angle or 0.3)
    length = length or 170
    H.Tween(0.3, function(p)
        local s = length * (0.4 + 0.6 * H.Ease.outCubic(math.min(1, p * 3)))
        t:SetSize(s, s)
        local flicker = (math.floor(p * 14) % 2 == 0) and 1 or 0.55
        t:SetAlpha((p < 0.5 and 1 or (1 - (p - 0.5) / 0.5)) * flicker)
    end, function() Release(t) end)
end

-- A soft additive flash.
function FX:Glow(x, y, color, size, dur)
    if not self.layer then return end
    local t = Sprite("glow", "ADD")
    if not t then return end
    H.Tint(t, color or C.white)
    Place(t, x, y)
    H.Tween(dur or 0.35, function(p)
        local s = size * (0.6 + 0.6 * H.Ease.outCubic(p))
        t:SetSize(s, s)
        t:SetAlpha(0.9 * (1 - p))
    end, function() Release(t) end)
end

-- The big moment: rays, a ripple and the element's particles.
function FX:Flourish(x, y, el, size)
    size = (size or 1) * (H.db.fx or 1)
    local e = H.ELEMENT[el] or H.ELEMENT.earth
    self:Rays(x, y, e.color, 160 * size, 0.6)
    self:Ripple(x, y, e.color, 24 * size, 110 * size, 0.42)
    self:Particles(e.particle, x, y, e.color, 7, 50 * size)
end
