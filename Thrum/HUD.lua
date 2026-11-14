-- HUD: the stone mana trough, the mana number, the five-second-rule line, your own cast bar,
-- the Lightning Shield orb, the weapon imbue badge and the SHOCK IT! cast bar.
-- Mana can be a "secret" value in combat (its maximum too), so it is only ever handed straight
-- to widgets (StatusBar:SetMinMaxValues / SetValue, FontString:SetFormattedText); nothing here
-- does maths on it.
local _, H = ...
local HUD = {}
H.HUD = HUD
local C = H.C

local W, HT = 380, 230                -- the HUD's frame
local BAR_W, BAR_H = 256, 32          -- the trough (its texture is 512x64)
local BAR_IN = 11                     -- trough inner edge, from each end
local BAR_Y = 0
local TOTEM_Y = 36                    -- the row of totem plaques
local PLAQUE, PITCH = 50, 56
local SIDE_X = 2 * PITCH + 30         -- imbue badge (left) and shield orb (right) beside the plaques
local FSR_Y, CAST_Y = -21, -33
local CAST_W, CAST_H = 214, 11
local PROMPT_W, PROMPT_H, PROMPT_Y = 214, 26, TOTEM_Y + 52
local CAP_H, CAP_OVERLAP = 20, 3      -- the caption tab, and how far it overlaps the bar
local LAG = 0.4                       -- how long the pale "just spent" chunk lingers
local NUM_EVERY = 0.25                -- while mana regenerates, the number changes at most this often
local NUM_FAST = 0.5                  -- after you spend, it follows every change for this long
local FSR = 5                         -- the five-second rule

HUD.BAR_Y, HUD.TOTEM_Y, HUD.CHIP_Y = BAR_Y, TOTEM_Y, -56
HUD.PLAQUE, HUD.PITCH, HUD.SIDE_X = PLAQUE, PITCH, SIDE_X

local EASE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local function Color(c)
    if CreateColor then return CreateColor(c[1], c[2], c[3], 1) end
    return { r = c[1], g = c[2], b = c[3], a = 1 }
end

local function MakeBar(parent, texture, level, mask)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", BAR_IN, 0)
    bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -BAR_IN, 0)
    bar:SetFrameLevel(level)
    bar:SetStatusBarTexture(texture)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    if mask then
        -- clip the fill to the trough's carved shape (the mask spans the whole trough)
        local m = bar:CreateMaskTexture()
        m:SetTexture(H.ART .. "bar_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(parent)
        local tex = bar:GetStatusBarTexture()
        if tex and tex.AddMaskTexture then tex:AddMaskTexture(m) end
    end
    return bar
end

function HUD:Build()
    local root = CreateFrame("Frame", "ThrumHUD", UIParent)
    root:SetSize(W, HT)
    root:SetFrameStrata("MEDIUM")
    root:SetMovable(true)
    root:SetClampedToScreen(true)
    self.root = root

    -- Everything sits on "body", which is what shakes.
    local body = CreateFrame("Frame", nil, root)
    body:SetSize(W, HT)
    body:SetPoint("CENTER")
    self.body = body

    local fx = CreateFrame("Frame", nil, root)
    fx:SetSize(W, HT)
    fx:SetPoint("CENTER")
    fx:SetFrameLevel(body:GetFrameLevel() + 20)
    self.fx = fx

    local base = body:GetFrameLevel()

    -- The mana trough
    local trough = CreateFrame("Frame", nil, body)
    trough:SetSize(BAR_W, BAR_H)
    trough:SetPoint("CENTER", body, "CENTER", 0, BAR_Y)
    trough:SetFrameLevel(base + 1)
    self.trough = trough
    local shadow = H.Tex(trough, "BACKGROUND", "bar_mask", BAR_W, BAR_H, -2)
    shadow:SetPoint("CENTER", 3, -4)
    shadow:SetVertexColor(0, 0, 0, 0.5)
    local bed = H.Tex(trough, "BACKGROUND", "bar_mask", BAR_W, BAR_H, -1)
    bed:SetPoint("CENTER")
    H.Tint(bed, C.deep, 0.92)

    self.lag = MakeBar(trough, "Interface\\Buttons\\WHITE8X8", base + 2, true)
    self.lag:SetStatusBarColor(0.86, 0.94, 1, 0.9)
    self.fill = MakeBar(trough, H.ART .. "bar_fill", base + 3, true)

    local top = CreateFrame("Frame", nil, trough)
    top:SetAllPoints(trough)
    top:SetFrameLevel(base + 4)
    self.flash = H.Tex(top, "ARTWORK", "bar_mask")
    self.flash:SetAllPoints()
    self.flash:SetBlendMode("ADD")
    self.flash:SetAlpha(0)
    self.shimmer = H.Tex(top, "ARTWORK", "bar_mask", nil, nil, 1)
    self.shimmer:SetAllPoints()
    self.shimmer:SetBlendMode("ADD")
    H.Tint(self.shimmer, C.storm)
    self.shimmer:SetAlpha(0)
    local frame = H.Tex(top, "OVERLAY", "bar_frame")
    frame:SetAllPoints()

    -- Mana number, hugging the left end of the trough
    local num = CreateFrame("Frame", nil, body)
    num:SetSize(70, 34)
    num:SetPoint("RIGHT", body, "CENTER", -BAR_W / 2 - 1, BAR_Y + 1)
    num:SetFrameLevel(base + 6)
    num.back = H.Text(num, "ARTWORK", 22)
    num.back:SetPoint("RIGHT", 1, -3)
    num.back:SetTextColor(C.bark[1], C.bark[2], C.bark[3])
    num.text = H.Text(num, "OVERLAY", 22)
    num.text:SetPoint("RIGHT")
    local bump = num:CreateAnimationGroup()
    local b = bump:CreateAnimation("Scale")
    b:SetDuration(0.16)
    b:SetScaleFrom(1.2, 1.2)
    b:SetScaleTo(1, 1)
    b:SetOrigin("RIGHT", 0, 0)
    b:SetSmoothing("OUT")
    num.bump = bump
    self.num = num

    -- Five-second rule: a thin line under the trough that runs out over five seconds after you
    -- spend mana (regeneration is slowed until it does). Quiet: no pops at either end.
    local fsr = CreateFrame("Frame", nil, body)
    fsr:SetSize(BAR_W - 2 * BAR_IN - 20, 4)
    fsr:SetPoint("CENTER", body, "CENTER", 0, FSR_Y)
    fsr:SetFrameLevel(base + 2)
    fsr.track = fsr:CreateTexture(nil, "BACKGROUND")
    fsr.track:SetAllPoints()
    fsr.track:SetColorTexture(C.bark[1], C.bark[2], C.bark[3], 0.75)
    fsr.line = fsr:CreateTexture(nil, "ARTWORK")
    fsr.line:SetPoint("LEFT", fsr, "LEFT", 0, 0)
    fsr.line:SetHeight(2)
    fsr.line:SetColorTexture(C.storm[1], C.storm[2], C.storm[3], 0.85)
    fsr.mote = H.Tex(fsr, "OVERLAY", "mote", 12, 12)
    fsr.mote:SetBlendMode("ADD")
    H.Tint(fsr.mote, C.spirit)
    fsr.w = BAR_W - 2 * BAR_IN - 20
    fsr:Hide()
    self.fsr = fsr

    -- Your own cast: a slim carved bar under the trough
    local cast = CreateFrame("Frame", nil, body)
    cast:SetSize(CAST_W, CAST_H)
    cast:SetPoint("CENTER", body, "CENTER", 0, CAST_Y)
    cast:SetFrameLevel(base + 3)
    cast.border = cast:CreateTexture(nil, "BACKGROUND", nil, -1)
    cast.border:SetColorTexture(C.bark[1], C.bark[2], C.bark[3], 0.95)
    cast.border:SetPoint("TOPLEFT", -2, 2)
    cast.border:SetPoint("BOTTOMRIGHT", 2, -2)
    cast.bg = cast:CreateTexture(nil, "BACKGROUND", nil, 0)
    cast.bg:SetAllPoints()
    cast.bg:SetColorTexture(C.deep[1], C.deep[2], C.deep[3], 0.9)
    local cbar = CreateFrame("StatusBar", nil, cast)
    cbar:SetAllPoints(cast)
    cbar:SetFrameLevel(base + 4)
    cbar:SetStatusBarTexture(H.ART .. "tablet")
    cbar:SetMinMaxValues(0, 1)
    cbar:SetValue(0)
    cast.bar = cbar
    local cface = CreateFrame("Frame", nil, cast)
    cface:SetAllPoints(cast)
    cface:SetFrameLevel(base + 5)
    cast.text = H.Text(cface, "OVERLAY", 10, "OUTLINE")
    cast.text:SetPoint("CENTER", 0, 0)
    cast.text:SetWidth(CAST_W - 10)
    cast.text:SetWordWrap(false)
    cast.text:SetTextColor(C.bone[1], C.bone[2], C.bone[3])
    cast:Hide()
    self.cast = cast

    -- Lightning Shield: an orb right of the totems, with the charges left on it
    local orb = CreateFrame("Frame", nil, body)
    orb:SetSize(36, 36)
    orb:SetPoint("CENTER", body, "CENTER", SIDE_X, TOTEM_Y)
    orb:SetFrameLevel(base + 6)
    orb.glow = H.Tex(orb, "BACKGROUND", "glow", 70, 70)
    orb.glow:SetPoint("CENTER")
    orb.glow:SetBlendMode("ADD")
    H.Tint(orb.glow, C.storm)
    orb.glow:SetAlpha(0)
    orb.ball = H.Tex(orb, "ARTWORK", "orb", 36, 36)
    orb.ball:SetPoint("CENTER")
    orb.count = H.Text(orb, "OVERLAY", 17)
    orb.count:SetPoint("CENTER", 1, -1)
    orb.count:SetTextColor(C.bone[1], C.bone[2], C.bone[3])
    orb.pips = {}
    for i = 1, 3 do
        local a = math.rad(-90 - 40 + (i - 1) * 40)
        local p = H.Tex(orb, "OVERLAY", "mote", 12, 12)
        p:SetPoint("CENTER", orb, "CENTER", math.cos(a) * 22, math.sin(a) * 22)
        p:SetBlendMode("ADD")
        H.Tint(p, C.storm)
        p:SetAlpha(0)
        orb.pips[i] = p
    end
    self.orb = orb
    self:SetShield(false)

    -- Weapon imbue: a carved badge left of the totems
    local badge = CreateFrame("Frame", nil, body)
    badge:SetSize(38, 38)
    badge:SetPoint("CENTER", body, "CENTER", -SIDE_X, TOTEM_Y)
    badge:SetFrameLevel(base + 6)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetSize(25, 25)
    badge.icon:SetPoint("CENTER")
    badge.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    badge.ring = H.Tex(badge, "OVERLAY", "badge", 40, 40)
    badge.ring:SetPoint("CENTER")
    badge.empty = H.Text(badge, "OVERLAY", 16)
    badge.empty:SetPoint("CENTER", 0, 0)
    badge.empty:SetTextColor(C.grey[1], C.grey[2], C.grey[3])
    badge.empty:SetText("?")
    badge.time = H.Text(badge, "OVERLAY", 10, "OUTLINE")
    badge.time:SetPoint("BOTTOM", badge, "BOTTOM", 0, 4)
    badge.time:SetTextColor(C.bone[1], C.bone[2], C.bone[3])
    self.badge = badge
    self:SetImbue(nil)

    -- Prompt: a carved cast bar. A tablet on top says what to do (SHOCK IT!); the bar below
    -- carries the spell's icon and name and fills as the cast goes on; a HEAL! leaf sits on its
    -- right end when the spell is a heal.
    local prompt = CreateFrame("Frame", nil, body)
    prompt:SetSize(PROMPT_W, PROMPT_H + CAP_H - CAP_OVERLAP)
    prompt:SetPoint("CENTER", body, "CENTER", 0, PROMPT_Y)
    prompt:SetFrameLevel(base + 10)

    local bar = H.Panel(prompt, PROMPT_W, PROMPT_H)
    bar:SetPoint("BOTTOM", prompt, "BOTTOM", 0, 0)
    bar:SetFrameLevel(base + 10)
    H.Tint(bar.bg, C.red)
    prompt.body = bar

    local fill = CreateFrame("StatusBar", nil, bar)
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", PROMPT_H, -2)
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -2, 2)
    fill:SetFrameLevel(base + 11)
    fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetStatusBarColor(1, 1, 1, 0.25)
    fill:SetMinMaxValues(0, 1)
    fill:Hide()
    prompt.bar = fill

    local face = CreateFrame("Frame", nil, bar)
    face:SetAllPoints(bar)
    face:SetFrameLevel(base + 12)
    local iconInk = face:CreateTexture(nil, "BORDER")
    iconInk:SetColorTexture(C.bark[1], C.bark[2], C.bark[3], 1)
    iconInk:SetSize(PROMPT_H, PROMPT_H)
    iconInk:SetPoint("LEFT", bar, "LEFT", 0, 0)
    prompt.icon = face:CreateTexture(nil, "ARTWORK")
    prompt.icon:SetSize(PROMPT_H - 4, PROMPT_H - 4)
    prompt.icon:SetPoint("CENTER", iconInk, "CENTER", 0, 0)
    prompt.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    prompt.spell = H.Text(face, "OVERLAY", 13, "OUTLINE")
    prompt.spell:SetPoint("LEFT", iconInk, "RIGHT", 7, 0)
    prompt.spell:SetWidth(PROMPT_W - PROMPT_H - 60) -- room for the tag on the right
    prompt.spell:SetJustifyH("LEFT")
    prompt.spell:SetWordWrap(false)
    prompt.spell:SetTextColor(1, 1, 1)

    local cap = H.Panel(prompt, 80, CAP_H)
    cap:SetPoint("TOPLEFT", prompt, "TOPLEFT", PROMPT_H - 6, 0)
    cap:SetFrameLevel(base + 14)
    H.Tint(cap.bg, C.gold)
    cap.text = H.Text(cap, "OVERLAY", 14, "")
    cap.text:SetPoint("CENTER", 0, 0)
    cap.text:SetTextColor(C.bark[1], C.bark[2], C.bark[3])
    prompt.cap = cap
    prompt.text = cap.text

    local tag = CreateFrame("Frame", nil, prompt)
    tag:SetSize(10, 10)
    tag:SetPoint("CENTER", bar, "RIGHT", -16, 1)
    tag:SetFrameLevel(base + 15)
    tag.shadow = H.Tex(tag, "BACKGROUND", "leaf", 72, 56)
    tag.shadow:SetPoint("CENTER", 3, -3)
    tag.shadow:SetVertexColor(0, 0, 0, 0.5)
    tag.shape = H.Tex(tag, "BORDER", "leaf", 72, 56)
    tag.shape:SetPoint("CENTER")
    H.Tint(tag.shape, C.heal)
    tag.text = H.Text(tag, "OVERLAY", 14, "OUTLINE")
    tag.text:SetPoint("CENTER", 0, 0)
    tag.text:SetRotation(-0.1)
    tag:Hide()
    prompt.tag = tag
    local pp = prompt:CreateAnimationGroup()
    pp:SetLooping("BOUNCE")
    local ps = pp:CreateAnimation("Scale")
    ps:SetDuration(0.22)
    ps:SetScaleFrom(1, 1)
    ps:SetScaleTo(1.05, 1.05)
    ps:SetOrigin("CENTER", 0, 0)
    ps:SetSmoothing("IN_OUT")
    prompt.pulse = pp
    prompt:Hide()
    self.prompt = prompt

    -- Mover, shown while unlocked
    local mover = CreateFrame("Frame", nil, root)
    mover:SetAllPoints(root)
    mover:SetFrameLevel(base + 40)
    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints()
    mover.bg:SetColorTexture(C.storm[1], C.storm[2], C.storm[3], 0.16)
    mover.text = H.Text(mover, "OVERLAY", 13, "OUTLINE")
    mover.text:SetPoint("TOP", 0, -4)
    mover.text:SetText("Thrum - drag me, then /thrum lock")
    mover:Hide()
    self.mover = mover

    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function(f)
        if not H.db.locked then f:StartMoving() end
    end)
    root:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local cx, cy = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local s = f:GetScale()
        if cx and ux and s and s > 0 then
            H.db.x = math.floor(cx - ux / s + 0.5)
            H.db.y = math.floor(cy - uy / s + 0.5)
        end
        HUD:ApplyPosition()
    end)

    self.alpha = 1
    self:SetPalette("normal")
    self:ApplyPosition()
    self:ApplyLock()
    self:ApplyOptions()

    H.Every(function(dt, now) HUD:OnUpdate(dt, now) end)
end

function HUD:ApplyPosition()
    local root = self.root
    root:SetScale(H.db.scale or 1)
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", H.db.x or 0, H.db.y or -190)
end

function HUD:ApplyLock()
    local unlocked = not H.db.locked
    self.root:EnableMouse(unlocked)
    self.mover:SetShown(unlocked)
end

-- The parts that can be switched off.
function HUD:ApplyOptions()
    self.badge:SetShown(H.db.imbue ~= false and self.imbueKnown == true)
    if H.db.fsr == false then self.fsr:Hide() end
    if H.db.castbar == false then self.cast:Hide() end
    if H.Totems.built then H.Totems:ApplyOptions() end
end

-- "normal" water, or "spirit" (Ghost Wolf): pale and ghostly.
function HUD:SetPalette(mode)
    self.palette = mode
    local c = mode == "spirit" and C.spirit or C.water
    self.fill:SetStatusBarColor(c[1], c[2], c[3], 1)
    local t = mode == "spirit" and C.spirit or C.bone
    self.num.text:SetTextColor(t[1], t[2], t[3])
end

--------------------------------------------------------------------------------
-- Mana
--------------------------------------------------------------------------------
-- value and maxValue may both be secret.
function HUD:SetMana(value, maxValue, instant)
    -- Re-setting the range every update would restart the bar's smoothing, so it is only set
    -- when the maximum changes. A hidden maximum cannot be compared: it is used only until a
    -- readable one has been seen (it rarely changes mid-fight).
    local hidden = H.IsSecret(maxValue)
    if (hidden and self.maxM == nil) or (not hidden and maxValue ~= self.maxM) then
        self.maxM = (not hidden) and maxValue or nil
        self.fill:SetMinMaxValues(0, maxValue)
        self.lag:SetMinMaxValues(0, maxValue)
    end
    self.fill:SetValue(value, (not instant) and EASE or nil)
    -- The number: spending shows at once; regeneration is shown in calm steps rather than
    -- every few milliseconds. (The value may be secret, so this goes by time, not by size.)
    self.numValue = value
    local now = GetTime()
    if instant or now < (self.numFastUntil or 0) or now - (self.numAt or 0) >= NUM_EVERY then
        self:ShowNumber(now)
    else
        self.numDirty = true
    end

    self.lagValue = value
    if instant then
        self.lagDue = nil
        self.lag:SetValue(value)
    elseif not self.lagDue then
        self.lagDue = now + LAG
    end
end

function HUD:ShowNumber(now)
    self.numAt, self.numDirty = now, false
    self.num.text:SetFormattedText("%d", self.numValue)
    self.num.back:SetFormattedText("%d", self.numValue)
end

-- Mana is about to drop (a cast went off): let the number follow every change for a moment.
function HUD:ExpectSpend()
    local now = GetTime()
    self.numFastUntil = now + NUM_FAST
    if self.numDirty then self:ShowNumber(now) end
end

local function Flash(tex, color, alpha, dur, holder)
    H.Tint(tex, color)
    H.Cancel(holder.flashTween)
    holder.flashTween = H.Tween(dur or 0.25, function(p)
        tex:SetAlpha(alpha * (1 - p))
    end)
end

-- A cast spent mana (cost from the spell, never from the hidden value).
function HUD:Spend(cost)
    if cost and cost > 0 then
        H.FX:Pop("-" .. math.floor(cost + 0.5), -BAR_W / 2 - 34, BAR_Y - 22, C.storm, 12, -14)
    end
    self:ExpectSpend()
    self.num.bump:Stop()
    self.num.bump:Play()
    if H.db.fsr ~= false then self:SetFSR(GetTime()) end
end

-- A big gain at once (Mana Tide, a potion): that one is worth a ripple.
function HUD:Refill(amount)
    Flash(self.flash, C.white, 0.5, 0.35, self)
    H.FX:Ripple(0, BAR_Y, C.water, 40, 260, 0.5)
    if amount then
        H.FX:Pop("+" .. math.floor(amount + 0.5), BAR_W / 2 + 26, BAR_Y - 4, C.water, 14, 18)
    end
end

function HUD:Shake(strength, dur)
    local body, root = self.body, self.root
    H.Cancel(self.shake)
    self.shake = H.Tween(dur or 0.22, function(p)
        local a = (1 - p) * strength
        body:SetPoint("CENTER", root, "CENTER", (math.random() * 2 - 1) * a, (math.random() * 2 - 1) * a)
    end, function()
        body:SetPoint("CENTER", root, "CENTER", 0, 0)
    end)
end

-- "Not enough mana"
function HUD:Error()
    local now = GetTime()
    Flash(self.flash, C.red, 0.75, 0.35, self)
    self:Shake(4, 0.25)
    if not self.lastError or now - self.lastError > 0.9 then
        self.lastError = now
        H.FX:Pop("NO MANA!", 0, BAR_Y + 4, C.red, 15, 14)
    end
end

-- Full or not (only known while mana is readable); only the idle fade uses it.
function HUD:SetFull(full)
    self.full = full
end

-- Clearcasting: the water shimmers while the next spell is free.
function HUD:SetClearcasting(on)
    self.clearcasting = on
    if not on then self.shimmer:SetAlpha(0) end
end

-- start: GetTime() of the last mana spend, or nil to hide the line.
function HUD:SetFSR(start)
    self.fsrStart = start
    if start and H.db.fsr ~= false then
        self.fsr:SetAlpha(1)
        self.fsr:Show()
    else
        self.fsr:Hide()
    end
end

--------------------------------------------------------------------------------
-- Lightning Shield
--------------------------------------------------------------------------------
-- on: shield up or not. count: what the game says about its charges (a string, maybe secret).
-- n: the number of charges when readable, to light the little pips.
function HUD:SetShield(on, count, n)
    local orb = self.orb
    local was = self.shieldOn
    self.shieldOn = on
    if on then
        orb.ball:SetDesaturated(false)
        H.Tint(orb.ball, C.storm)
        orb.ball:SetAlpha(1)
        if count ~= nil then orb.count:SetText(count) else orb.count:SetText("") end
        for i = 1, 3 do orb.pips[i]:SetAlpha((n and i <= n) and 0.9 or 0) end
        if not was then
            H.FX:Ripple(SIDE_X, TOTEM_Y, C.storm, 20, 80, 0.35)
            H.FX:Particles("zap", SIDE_X, TOTEM_Y, C.storm, 4, 26)
        end
    else
        orb.ball:SetDesaturated(true)
        H.Tint(orb.ball, C.grey)
        orb.ball:SetAlpha(0.35)
        orb.count:SetText("")
        for i = 1, 3 do orb.pips[i]:SetAlpha(0) end
        orb.glow:SetAlpha(0)
    end
end

-- A charge went off (you were hit): a crackle at the orb, no words.
function HUD:ShieldCharge()
    H.FX:Particles("zap", SIDE_X, TOTEM_Y, C.storm, 3, 22)
    H.FX:Glow(SIDE_X, TOTEM_Y, C.storm, 60, 0.3)
end

--------------------------------------------------------------------------------
-- Weapon imbue
--------------------------------------------------------------------------------
-- info: { seconds, icon } from the game, or nil/false for none.
function HUD:SetImbue(info, fallbackIcon)
    local badge = self.badge
    self.imbue = info or nil
    if info then
        badge.icon:SetTexture(info.icon or fallbackIcon or 136018)
        badge.icon:SetAlpha(1)
        badge.icon:SetDesaturated(false)
        badge.empty:Hide()
        badge.ring:SetVertexColor(1, 1, 1, 1)
        self.imbueEnds = info.seconds and (GetTime() + info.seconds) or nil
        self:ImbueText(GetTime())
    else
        badge.icon:SetTexture(nil)
        badge.empty:Show()
        badge.ring:SetVertexColor(0.6, 0.6, 0.6, 0.7)
        badge.time:SetText("")
        self.imbueEnds = nil
    end
end

function HUD:ImbueText(now)
    local ends = self.imbueEnds
    if not ends then
        self.badge.time:SetText("")
        return
    end
    local left = math.max(0, ends - now)
    if left >= 60 then
        self.badge.time:SetFormattedText("%dm", math.ceil(left / 60))
    else
        self.badge.time:SetFormattedText("%ds", math.floor(left + 0.5))
    end
    local warn = left < 30 and C.red or C.bone
    self.badge.time:SetTextColor(warn[1], warn[2], warn[3])
end

--------------------------------------------------------------------------------
-- Your own cast
--------------------------------------------------------------------------------
-- info: { name, startMs, endMs, channel, kind = "heal"|"storm"|nil }
function HUD:StartCast(info)
    if H.db.castbar == false then return end
    local cast = self.cast
    local IsSecret = H.IsSecret
    if IsSecret(info.startMs) or IsSecret(info.endMs) or type(info.startMs) ~= "number" or type(info.endMs) ~= "number"
        or info.endMs <= info.startMs then
        return
    end
    H.Cancel(self.castFade)
    cast.s, cast.e, cast.channel = info.startMs / 1000, info.endMs / 1000, info.channel
    cast.bar:SetMinMaxValues(cast.s, cast.e)
    cast.bar:SetValue(info.channel and cast.e or cast.s)
    local c = info.kind == "heal" and C.heal or info.kind == "storm" and C.storm or C.bone
    cast.color = c
    cast.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    if info.name ~= nil then cast.text:SetText(info.name) else cast.text:SetText("") end
    cast:SetAlpha(1)
    cast:Show()
    self.casting = true
end

-- result: "done", "failed" or "interrupted".
function HUD:EndCast(result)
    local cast = self.cast
    if not self.casting then return end
    self.casting = false
    if result == "done" then
        cast.bar:SetValue(cast.channel and cast.s or cast.e)
        H.FX:Glow(0, CAST_Y, cast.color or C.bone, 120, 0.3)
    elseif result ~= "stopped" then
        cast.bar:SetStatusBarColor(C.red[1], C.red[2], C.red[3], 1)
        cast.text:SetText(result == "interrupted" and "INTERRUPTED" or "FAILED")
        self:Shake(2.5, 0.18)
    end
    H.Cancel(self.castFade)
    self.castFade = H.Tween(result == "done" and 0.25 or 0.6, function(p)
        cast:SetAlpha(1 - p * p)
    end, function() cast:Hide() end)
end

-- The spell's cast time moved (pushback).
function HUD:MoveCast(startMs, endMs)
    local cast = self.cast
    if not self.casting or H.IsSecret(startMs) or H.IsSecret(endMs) or type(endMs) ~= "number" then return end
    cast.s, cast.e = startMs / 1000, endMs / 1000
    cast.bar:SetMinMaxValues(cast.s, cast.e)
end

--------------------------------------------------------------------------------
-- The SHOCK IT! box
--------------------------------------------------------------------------------
local QUESTION_MARK = 134400

-- The box above the HUD, or nil text to hide it. cast describes what the target is casting
-- (Tracker's ReadCast); any part of it may be secret, so it is only handed to widgets: the name
-- and icon are displayed, and "helpful" / "can't be interrupted" pick colours and visibility
-- through the game's boolean setters without the addon ever reading them.
-- mode "wait" (nothing to stop it with right now) shows the box dimmer and without pulsing.
function HUD:SetPrompt(text, cast, mode)
    local prompt = self.prompt
    if not text then
        if self.promptText then
            prompt.pulse:Stop()
            prompt:Hide()
        end
        self.promptText, self.promptCast, self.promptMode = nil, nil, nil
        return
    end
    mode = mode or "go"
    if text == self.promptText and cast == self.promptCast and mode == self.promptMode then return end
    local nowGo = mode == "go" and self.promptMode ~= "go"
    self.promptText, self.promptCast, self.promptMode = text, cast, mode
    local alpha = mode == "go" and 1 or 0.8
    cast = cast or {}
    local IsSecret = H.IsSecret

    prompt.text:SetText(text)
    prompt.cap:SetWidth(math.max(64, (prompt.text:GetStringWidth() or 60) + 18))
    H.Tint(prompt.cap.bg, mode == "go" and C.gold or C.grey)
    if IsSecret(cast.name) or cast.name ~= nil then
        prompt.spell:SetText(cast.name)
    else
        prompt.spell:SetText("")
    end
    if IsSecret(cast.icon) or cast.icon ~= nil then
        prompt.icon:SetTexture(cast.icon)
    else
        prompt.icon:SetTexture(QUESTION_MARK)
    end

    -- heal or not
    local tag = prompt.tag
    if IsSecret(cast.helpful) then
        -- hidden: a helpful spell cast by an enemy is all but always a heal
        tag.text:SetText("HEAL!")
        tag.text:SetTextColor(C.bone[1], C.bone[2], C.bone[3])
        tag:Show()
        tag:SetAlphaFromBoolean(cast.helpful, 1, 0)
        prompt.body.bg:SetVertexColorFromBoolean(cast.helpful, Color(C.heal), Color(C.red))
    else
        local label = (cast.heal and "HEAL!") or (cast.helpful and "BUFF!") or nil
        tag:SetAlpha(1)
        tag:SetShown(label ~= nil)
        if label then
            H.Tint(tag.shape, cast.heal and C.heal or C.gold)
            tag.text:SetText(label)
            tag.text:SetTextColor(C.bone[1], C.bone[2], C.bone[3])
        end
        H.Tint(prompt.body.bg, cast.helpful and C.heal or C.red)
    end

    -- a shielded cast cannot be interrupted: the box stays out of the way
    if IsSecret(cast.notInterruptible) then
        prompt:SetAlphaFromBoolean(cast.notInterruptible, 0, alpha)
    else
        prompt:SetAlpha(alpha)
    end

    -- how far along the cast is
    local s, e = cast.startMs, cast.endMs
    if not IsSecret(s) and not IsSecret(e) and type(s) == "number" and type(e) == "number" and e > s then
        prompt.bar:SetMinMaxValues(s / 1000, e / 1000)
        prompt.bar:SetValue(GetTime())
        prompt.bar:Show()
        prompt.bar.reverse = cast.channel
        self.castBar = true
    else
        prompt.bar:Hide()
        self.castBar = false
    end

    prompt:Show()
    if mode ~= "go" then
        prompt.pulse:Stop()
    elseif nowGo then
        -- just became something you can do: pulse and a ripple to catch the eye
        prompt.pulse:Play()
        H.FX:Ripple(0, PROMPT_Y, cast.helpful == true and C.heal or C.earth, 50, 170, 0.35)
    end
end

--------------------------------------------------------------------------------
-- Per frame
--------------------------------------------------------------------------------
function HUD:OnUpdate(dt, now)
    -- the cast bar in the SHOCK IT! box
    if self.castBar and self.promptText then
        local bar = self.prompt.bar
        local lo, hi = bar:GetMinMaxValues()
        local v = math.min(hi, math.max(lo, now))
        bar:SetValue(bar.reverse and (hi - (v - lo)) or v)
    end

    -- your own cast
    if self.casting then
        local cast = self.cast
        local v = math.min(cast.e, math.max(cast.s, now))
        cast.bar:SetValue(cast.channel and (cast.e - (v - cast.s)) or v)
        if now > cast.e + 0.5 then self:EndCast("stopped") end
    end

    -- the number catches up after a quiet spell
    if self.numDirty and now - (self.numAt or 0) >= NUM_EVERY then self:ShowNumber(now) end

    -- the pale chunk catches up with the real value
    if self.lagDue and now >= self.lagDue then
        self.lagDue = nil
        self.lag:SetValue(self.lagValue, EASE)
    end

    -- five-second rule: the line runs out, then fades
    if self.fsrStart then
        local p = (now - self.fsrStart) / FSR
        local fsr = self.fsr
        if p >= 1 then
            local fade = (p - 1) * FSR / 0.4
            if fade >= 1 then
                self:SetFSR(nil)
            else
                fsr:SetAlpha(1 - fade)
                fsr.line:SetWidth(0.01)
            end
        else
            local w = math.max(0.01, fsr.w * (1 - p))
            fsr.line:SetWidth(w)
            fsr.mote:SetPoint("CENTER", fsr, "LEFT", w, 0)
        end
    end

    -- Clearcasting: the water shimmers
    if self.clearcasting then
        self.shimmer:SetAlpha(0.22 + 0.16 * math.sin(now * 5))
    end

    -- the shield orb breathes while it holds charges
    if self.shieldOn then
        self.orb.glow:SetAlpha(0.25 + 0.15 * math.sin(now * 3))
    end

    -- the imbue's minutes
    if self.imbueEnds and now - (self.imbueTextAt or 0) > 0.5 then
        self.imbueTextAt = now
        self:ImbueText(now)
    end

    -- fade when idle
    local busy = H.demo or self.inCombat or self.hasTarget or not H.db.locked or self.casting
        or self.full == false or (H.Timers.count or 0) > 0 or (H.Totems.count or 0) > 0
    local target = busy and 1 or (H.db.idle or 0.35)
    if self.alpha ~= target then
        local step = dt * 3
        if self.alpha < target then
            self.alpha = math.min(target, self.alpha + step)
        else
            self.alpha = math.max(target, self.alpha - step)
        end
        self.root:SetAlpha(self.alpha)
    end
end
