-- Thrum: a carved, elemental HUD for shamans.
-- Core: shared namespace, colours, the tween driver, saved settings and the slash command.
local ADDON, H = ...

H.ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
-- Lettering: Thrum Runes, made for this addon (SIL Open Font License, see Fonts\\OFL.txt).
-- If it cannot be loaded the game's own chunky damage-number font stands in.
H.FONT = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\ThrumRunes.ttf"
H.FONT_FALLBACK = "Fonts\\skurri.ttf"

H.C = {
    bark   = { 0.09, 0.06, 0.04 },  -- the dark everything is cut with
    bone   = { 0.96, 0.90, 0.76 },
    white  = { 1.00, 1.00, 1.00 },
    earth  = { 0.72, 0.52, 0.28 },
    moss   = { 0.52, 0.76, 0.30 },
    fire   = { 1.00, 0.50, 0.14 },
    ember  = { 1.00, 0.78, 0.30 },
    water  = { 0.26, 0.60, 1.00 },
    deep   = { 0.10, 0.22, 0.42 },
    air    = { 0.80, 0.92, 1.00 },
    storm  = { 0.52, 0.76, 1.00 },
    heal   = { 0.42, 0.92, 0.50 },
    red    = { 1.00, 0.24, 0.20 },
    gold   = { 1.00, 0.84, 0.36 },
    grey   = { 0.62, 0.60, 0.56 },
    spirit = { 0.66, 0.86, 1.00 },
}
local C = H.C

-- Each element's colour and particle.
H.ELEMENT = {
    earth = { color = C.earth, particle = "pebble", shape = "stone" },
    fire  = { color = C.fire,  particle = "ember",  shape = "flame" },
    water = { color = C.water, particle = "drop",   shape = "splash" },
    air   = { color = C.air,   particle = "mote",   shape = "wisp" },
    storm = { color = C.storm, particle = "zap",    shape = "bolt" },
    life  = { color = C.heal,  particle = "leaf",   shape = "leaf" },
}

local DEFAULTS = {
    x = 0, y = -190,   -- offset from the centre of the screen
    scale = 1,
    locked = true,
    combatOnly = true, -- hidden out of combat (shown while unlocked, in Edit Mode and in the demo)
    idle = 0.35,       -- HUD opacity out of combat with nothing going on, when combatOnly is off
    fx = 1,            -- size of the word bursts
    words = true,      -- word bursts for your spells
    hits = true,       -- CRIT! / RESISTED! from what happens to the target
    prompt = true,     -- SHOCK IT! when the target starts casting
    totems = true,     -- the four totem plaques
    fsr = true,        -- the five-second-rule line under the mana trough
    castbar = true,    -- your own cast under the mana trough
    procs = true,      -- CLEARCASTING! and friends
    imbue = true,      -- the weapon imbue badge
}
H.DEFAULTS = DEFAULTS
-- the position range the options page offers (offsets from the screen's centre)
H.HUD_X_RANGE, H.HUD_Y_RANGE = 1000, 600

-- Some values are hidden from addons in combat ("secret"): they can be handed to widgets,
-- but any maths or comparison on them is an error. Everything that reads the game checks first.
local issecretvalue = issecretvalue
function H.IsSecret(v)
    if issecretvalue then return issecretvalue(v) and true or false end
    return false
end

-- Calls fn and swallows errors; returns nil if it failed.
function H.Safe(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
    return nil
end

function H.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fc8ffThrum|r " .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Easing
--------------------------------------------------------------------------------
H.Ease = {}
function H.Ease.outCubic(p) p = 1 - p; return 1 - p * p * p end
function H.Ease.inCubic(p) return p * p * p end
function H.Ease.outBack(p)
    local c = 2.0
    p = p - 1
    return 1 + (c + 1) * p * p * p + c * p * p
end

--------------------------------------------------------------------------------
-- Tween driver: one OnUpdate for everything that moves.
--------------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local tweens, tickers = {}, {}

-- Runs step(p) with p going 0..1 over dur seconds, then done().
function H.Tween(dur, step, done)
    local t = { t = 0, dur = dur, step = step, done = done }
    tweens[#tweens + 1] = t
    step(0)
    return t
end

function H.Cancel(t)
    if t then t.dead = true end
end

-- fn(elapsed, now) on every frame.
function H.Every(fn)
    tickers[#tickers + 1] = fn
end

function H.After(sec, fn)
    C_Timer.After(sec, fn)
end

driver:SetScript("OnUpdate", function(_, dt)
    if dt > 0.1 then dt = 0.1 end
    local now = GetTime()
    for i = 1, #tickers do tickers[i](dt, now) end
    for i = 1, #tweens do
        local t = tweens[i]
        if t and not t.dead then
            t.t = t.t + dt
            local p = t.t / t.dur
            if p >= 1 then
                t.dead = true
                t.step(1)
                if t.done then t.done() end
            else
                t.step(p)
            end
        end
    end
    local k = 0
    for i = 1, #tweens do
        local t = tweens[i]
        if not t.dead then
            k = k + 1
            tweens[k] = t
        end
    end
    for i = #tweens, k + 1, -1 do tweens[i] = nil end
end)

--------------------------------------------------------------------------------
-- Small widget helpers
--------------------------------------------------------------------------------
function H.Tex(parent, layer, file, w, h, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    if file then t:SetTexture(H.ART .. file) end
    if w then t:SetSize(w, h or w) end
    return t
end

function H.Tint(tex, c, a)
    tex:SetVertexColor(c[1], c[2], c[3], a or 1)
end

function H.SetFont(fs, size, flags)
    flags = flags or "THICKOUTLINE"
    if fs:SetFont(H.FONT, math.floor(size + 0.5), flags) then return end
    if fs:SetFont(H.FONT_FALLBACK, size, flags) then return end
    fs:SetFont(STANDARD_TEXT_FONT, size, flags)
end

function H.Text(parent, layer, size, flags)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(GameFontNormalLarge)
    H.SetFont(fs, size, flags)
    fs:SetShadowOffset(0, 0)
    return fs
end

-- A plank with a bark border and a soft drop shadow: the carved "caption tablet".
function H.Panel(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    f.shadow:SetColorTexture(0, 0, 0, 0.5)
    f.shadow:SetPoint("TOPLEFT", 2, -3)
    f.shadow:SetPoint("BOTTOMRIGHT", 2, -3)
    f.border = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.border:SetColorTexture(C.bark[1], C.bark[2], C.bark[3], 1)
    f.border:SetAllPoints()
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.bg:SetPoint("TOPLEFT", 2, -2)
    f.bg:SetPoint("BOTTOMRIGHT", -2, 2)
    f.bg:SetTexture(H.ART .. "tablet")
    H.Tint(f.bg, C.bone)
    return f
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------
local function InitDB()
    ThrumDB = ThrumDB or {}
    for k, v in pairs(DEFAULTS) do
        if ThrumDB[k] == nil then ThrumDB[k] = v end
    end
    H.db = ThrumDB
    H.Options:Register()
end

-- Builds the HUD the first time it is needed.
function H.Build()
    if H.built then return end
    H.built = true
    H.HUD:Build()
    H.FX:Build()
    H.Timers:Build()
    H.Totems:Build()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then InitDB() end
    elseif event == "PLAYER_LOGIN" then
        if not H.db then InitDB() end
        H.Options:Register() -- no-op if already done when the settings loaded
        local _, class = UnitClass("player")
        H.isShaman = (class == "SHAMAN")
        if H.isShaman then
            H.Build()
            H.Tracker:Start()
        end
    end
end)

--------------------------------------------------------------------------------
-- /thrum
--------------------------------------------------------------------------------
local TOGGLES = {
    combatOnly = "only in combat",
    words = "spell words", hits = "crit/resist words", prompt = "SHOCK IT! prompt", totems = "totem plaques",
    fsr = "five-second-rule line", castbar = "cast bar", procs = "proc words", imbue = "weapon imbue badge",
}

local function Toggle(key)
    H.db[key] = not H.db[key]
    H.Print(TOGGLES[key] .. (H.db[key] and " on" or " off"))
    if H.built then H.HUD:ApplyOptions() end
end

SLASH_THRUM1 = "/thrum"
SlashCmdList["THRUM"] = function(msg)
    msg = (msg or ""):lower()
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if not H.db then InitDB() end
    if cmd == "options" or cmd == "config" or cmd == "settings" then
        if not H.Options:Open() then H.Print("the options page is not available in this client; use the commands below") end
    elseif cmd == "test" or cmd == "demo" then
        H.Build()
        H.Demo:Run()
    elseif cmd == "unlock" or cmd == "move" then
        H.Build()
        H.db.locked = false
        H.HUD:ApplyLock()
        H.Print("unlocked: drag the HUD, then /thrum lock")
    elseif cmd == "lock" then
        H.Build()
        H.db.locked = true
        H.HUD:ApplyLock()
        H.Print("locked")
    elseif cmd == "scale" then
        local s = tonumber(arg)
        if s and s >= 0.5 and s <= 2.5 then
            H.db.scale = s
            if H.built then H.HUD:ApplyPosition() end
            H.Print("scale " .. s)
        else
            H.Print("scale takes a number from 0.5 to 2.5")
        end
    elseif cmd == "idle" then
        local a = tonumber(arg)
        if a and a >= 0 and a <= 1 then
            H.db.idle = a
            H.Print("idle opacity " .. a)
        else
            H.Print("idle takes a number from 0 (hidden) to 1")
        end
    elseif cmd == "fx" then
        local s = tonumber(arg)
        if s and s >= 0.5 and s <= 1.5 then
            H.db.fx = s
            H.Print("word burst size " .. s)
        else
            H.Print("fx takes a number from 0.5 (small bursts) to 1.5")
        end
    elseif cmd == "combat" then
        Toggle("combatOnly")
    elseif cmd == "pos" or cmd == "position" then
        local x, y = arg:match("^(%-?%d+)%s+(%-?%d+)$")
        if x then
            H.db.x, H.db.y = tonumber(x), tonumber(y)
            if H.built then
                H.db.x, H.db.y = H.HUD.ClampX(H.db.x), H.HUD.ClampY(H.db.y)
                H.HUD:ApplyPosition()
            end
            H.Print("position " .. H.db.x .. ", " .. H.db.y)
        else
            H.Print("pos takes two numbers: across and up from the centre of the screen, e.g. /thrum pos 0 -190")
        end
    elseif TOGGLES[cmd] and cmd ~= "combatOnly" then
        Toggle(cmd)
    elseif cmd == "reset" then
        H.db.x, H.db.y, H.db.scale = DEFAULTS.x, DEFAULTS.y, DEFAULTS.scale
        if H.built then H.HUD:ApplyPosition() end
        H.Print("position and scale reset")
    else
        H.Print("commands (or Options > AddOns > Thrum):")
        H.Print("  /thrum options - open the options page")
        H.Print("  /thrum test - play a demo of every effect")
        H.Print("  /thrum unlock | lock - move the HUD (or drag it in Edit Mode)   /thrum pos 0 -190 - place it exactly")
        H.Print("  /thrum combat - toggle showing the HUD only in combat")
        H.Print("  /thrum scale 1.2 - resize   /thrum idle 0.35 - opacity out of combat")
        H.Print("  /thrum fx 0.8 - size of the word bursts")
        H.Print("  /thrum words | hits | prompt | procs - toggle spell words, CRIT!/RESISTED!, SHOCK IT!, proc words")
        H.Print("  /thrum totems | imbue | castbar | fsr - toggle totem plaques, imbue badge, cast bar, five-second line")
        H.Print("  /thrum reset - back to the default spot")
        if H.isShaman == false then H.Print("(not a shaman: the HUD only runs for shamans, but the demo works)") end
    end
end
