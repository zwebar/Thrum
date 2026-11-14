-- Mock WoW UI for Thrum's tools/test.js. DOC (from Blizzard's API docs), ART, FILES and VERBOSE are
-- defined by the runner before this file.
local OUT, ERRORS, WARNED, LOG = {}, {}, {}, {}
local function say(s) OUT[#OUT + 1] = s end
local function warn(s)
    if not WARNED[s] then
        WARNED[s] = true
        WARNED[#WARNED + 1] = s
    end
end
local function fail(s) ERRORS[#ERRORS + 1] = s end

local clock, t0 = 100.0, 100.0
local G
local function log(s) LOG[#LOG + 1] = string.format("  %6.2f  %s", clock - t0, s) end

--------------------------------------------------------------------------------
-- Secret values: any maths, ordering, concatenation or indexing is an error.
-- (Lua cannot trap `secret == 5` or `if secret then`; those slip through here.)
--------------------------------------------------------------------------------
local SecretMT = {}
local function secretErr() error("attempt to use a secret value", 2) end
for _, m in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__unm", "__lt", "__le", "__concat",
    "__len", "__index", "__newindex", "__call", "__idiv", "__pow" }) do
    SecretMT[m] = secretErr
end
local function secret(v)
    local s = {}
    rawset(s, "__real", v) -- what the game would draw; the addon cannot reach it
    return setmetatable(s, SecretMT)
end
function issecretvalue(v) return getmetatable(v) == SecretMT end
local function real(v) if issecretvalue(v) then return rawget(v, "__real") end return v end
local function hide(v) if G.secret then return secret(v) end return v end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------
local BASE = { "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleObjectAPI",
    "SimpleFrameScriptObjectAPI", "SimpleAnimatableObjectAPI" }
local function chain(...)
    local t = { ... }
    for _, b in ipairs(BASE) do t[#t + 1] = b end
    return t
end
local ANIM = { "SimpleAnimAPI", "SimpleObjectAPI", "SimpleFrameScriptObjectAPI" }
local CHAINS = {
    Frame = chain("SimpleFrameAPI"),
    StatusBar = chain("SimpleStatusBarAPI", "SimpleFrameAPI"),
    Texture = chain("SimpleTextureAPI", "SimpleTextureBaseAPI", "SimpleRegionAPI"),
    MaskTexture = chain("SimpleMaskTextureAPI", "SimpleTextureBaseAPI", "SimpleRegionAPI"),
    FontString = chain("SimpleFontStringAPI", "SimpleRegionAPI"),
    AnimationGroup = { "SimpleAnimGroupAPI", "SimpleObjectAPI", "SimpleFrameScriptObjectAPI" },
    Scale = { "SimpleAnimScaleAPI", ANIM[1], ANIM[2], ANIM[3] },
    Alpha = { "SimpleAnimAlphaAPI", ANIM[1], ANIM[2], ANIM[3] },
    Translation = { "SimpleAnimTranslationAPI", ANIM[1], ANIM[2], ANIM[3] },
}
for kind, list in pairs(CHAINS) do
    for _, api in ipairs(list) do
        if not DOC.methods[api] then warn("docs have no script object " .. api .. " (for " .. kind .. ")") end
    end
end

local function docFlag(kind, k)
    for _, api in ipairs(CHAINS[kind]) do
        local m = DOC.methods[api]
        if m and m[k] then return m[k] end
    end
end

local EVENTS, UPDATERS, PLAYING, TIMERS = {}, {}, {}, {}
local COUNT = { frames = 0, textures = 0, fontstrings = 0 }
local IMPL = {}
local WidgetMT = {}
local methodCache = {}

local ALL = {}
local function new(kind, parent)
    local o = setmetatable({ __kind = kind, __parent = parent, __shown = true, __v = {}, __scripts = {}, __points = {} }, WidgetMT)
    ALL[#ALL + 1] = o
    o.__id = #ALL
    return o
end

local function num(v, what)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
        error(what .. " must be a number, got " .. tostring(v), 3)
    end
end

WidgetMT.__index = function(o, k)
    local kind = rawget(o, "__kind")
    local flag = type(k) == "string" and docFlag(kind, k)
    if not flag then return nil end -- a plain field, or a method the client does not have
    local id = kind .. ":" .. k
    local fn = methodCache[id]
    if not fn then
        fn = function(self, ...)
            if getmetatable(self) ~= WidgetMT then error(id .. " called with '.' instead of ':'", 2) end
            for i = 1, select("#", ...) do
                if issecretvalue((select(i, ...))) and flag ~= "T" then
                    error(id .. " does not accept secret values", 2)
                end
            end
            local p3 = k:sub(1, 3)
            if p3 == "Set" then self.__v[k:sub(4)] = { ... } end
            local impl = IMPL[k]
            if impl then return impl(self, ...) end
            if p3 == "Set" then
                return true
            elseif p3 == "Get" then
                local v = self.__v[k:sub(4)]
                if v then return table.unpack(v) end
                return 0
            elseif k:sub(1, 2) == "Is" then
                return false
            elseif k:sub(1, 6) == "Create" then
                error("mock: " .. id .. " is not implemented", 2)
            end
        end
        methodCache[id] = fn
    end
    return fn
end

local LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }
local POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function checkArt(file)
    if type(file) == "string" then
        local name = file:match("AddOns\\Thrum\\Art\\(.+)$")
        if file:find("Thrum", 1, true) and not (name and ART[name]) then
            error("missing art file: " .. file, 3)
        end
    end
end

function IMPL.SetScript(self, name, fn)
    if fn ~= nil and type(fn) ~= "function" then error("SetScript needs a function", 2) end
    self.__scripts[name] = fn
    if name == "OnUpdate" then UPDATERS[self] = fn and true or nil end
end
function IMPL.GetScript(self, name) return self.__scripts[name] end
function IMPL.RegisterEvent(self, e)
    if not DOC.events[e] then error("unknown event " .. tostring(e), 2) end
    EVENTS[e] = EVENTS[e] or {}
    EVENTS[e][self] = "*"
    return true
end
function IMPL.RegisterUnitEvent(self, e, ...)
    if not DOC.events[e] then error("unknown event " .. tostring(e), 2) end
    if not e:find("^UNIT_") then error("not a unit event: " .. e, 2) end
    local units = {}
    for i = 1, select("#", ...) do units[(select(i, ...))] = true end
    EVENTS[e] = EVENTS[e] or {}
    EVENTS[e][self] = units
    return true
end
function IMPL.SetParent(self, p)
    if p ~= nil and getmetatable(p) ~= WidgetMT then error("SetParent: bad parent " .. tostring(p), 2) end
    self.__parent = p
end
function IMPL.GetParent(self) return self.__parent end
function IMPL.Show(self) self.__shown = true end
function IMPL.Hide(self) self.__shown = false end
function IMPL.SetShown(self, s)
    if type(s) ~= "boolean" then error("SetShown needs a boolean, got " .. tostring(s), 2) end
    self.__shown = s
end
function IMPL.IsShown(self) return self.__shown end
function IMPL.EnableMouse(self, on) self.__v.MouseEnabled = { on and true or false } end
function IMPL.CreateTexture(self, name, layer, template, sub)
    if layer and not LAYERS[layer] then error("bad draw layer " .. tostring(layer), 2) end
    if sub and (type(sub) ~= "number" or sub < -8 or sub > 7) then error("bad sublevel " .. tostring(sub), 2) end
    COUNT.textures = COUNT.textures + 1
    local t = new("Texture", self)
    t.__layer, t.__sub = layer or "ARTWORK", sub or 0
    return t
end
function IMPL.CreateFontString(self, name, layer)
    if layer and not LAYERS[layer] then error("bad draw layer " .. tostring(layer), 2) end
    COUNT.fontstrings = COUNT.fontstrings + 1
    local t = new("FontString", self)
    t.__layer, t.__sub = layer or "ARTWORK", 0
    return t
end
function IMPL.CreateMaskTexture(self) return new("MaskTexture", self) end
function IMPL.CreateAnimationGroup(self)
    local ag = new("AnimationGroup", self)
    ag.__anims = {}
    return ag
end
function IMPL.CreateAnimation(self, kind)
    if not CHAINS[kind] or not kind then error("mock: animation type " .. tostring(kind), 2) end
    local a = new(kind, self)
    self.__anims[#self.__anims + 1] = a
    return a
end
function IMPL.SetTexture(self, file)
    checkArt(file)
    self.__file, self.__color = file, nil
    return true
end
function IMPL.SetStatusBarTexture(self, file)
    checkArt(file)
    self.__sbtex = self.__sbtex or new("Texture", self)
    self.__sbtex.__file, self.__sbtex.__fill = file, true
    return true
end
function IMPL.GetStatusBarTexture(self) return self.__sbtex end
function IMPL.AddMaskTexture(self, mask)
    if getmetatable(mask) ~= WidgetMT or mask.__kind ~= "MaskTexture" then error("AddMaskTexture needs a MaskTexture", 2) end
    self.__mask = mask
end
local FLAGS = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true }
function IMPL.SetFont(self, file, size, flags)
    if type(file) ~= "string" then error("SetFont: bad font file " .. tostring(file), 2) end
    local own = file:match("AddOns\\Thrum\\Fonts\\(.+)$")
    if file:find("Thrum", 1, true) and not (own and FONTFILES[own]) then
        error("missing font file: " .. file, 2)
    end
    num(size, "font size")
    if size <= 0 then error("SetFont: size " .. size, 2) end
    for f in (flags or ""):gmatch("[^,%s]+") do
        if not FLAGS[f] then error("SetFont: bad flag " .. f, 2) end
    end
    return true
end
function IMPL.GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function IMPL.SetFontObject(self, obj)
    if obj == nil then error("SetFontObject(nil)", 2) end
end
function IMPL.SetText(self, t)
    self.__text = t
end
function IMPL.SetFormattedText(self, fmt, ...)
    local hidden = false
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then hidden = true end
    end
    local a = { ... }
    for i = 1, #a do a[i] = real(a[i]) end
    local text = string.format(fmt, table.unpack(a))
    self.__text = hidden and secret(text) or text
end
function IMPL.GetStringWidth(self)
    if issecretvalue(self.__text) then error("GetStringWidth on secret text", 2) end
    return #(tostring(self.__text or "")) * 7
end
function IMPL.SetPoint(self, point, a, b, c, d)
    if not POINTS[point] then error("SetPoint: bad point " .. tostring(point), 2) end
    local rel, relPoint, x, y = nil, point, 0, 0
    if type(a) == "number" then
        num(a, "SetPoint x"); num(b, "SetPoint y")
        x, y = a, b
    elseif a ~= nil then
        if getmetatable(a) ~= WidgetMT then error("SetPoint: bad relative frame " .. tostring(a), 2) end
        rel = a
        if type(b) == "string" then
            if not POINTS[b] then error("SetPoint: bad relative point " .. b, 2) end
            relPoint = b
            if c ~= nil then num(c, "SetPoint x"); num(d, "SetPoint y"); x, y = c, d end
        elseif b ~= nil then
            num(b, "SetPoint x"); num(c, "SetPoint y")
            x, y = b, c
        end
    end
    local p = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    for i, old in ipairs(self.__points) do
        if old.point == point then self.__points[i] = p return end
    end
    self.__points[#self.__points + 1] = p
end
function IMPL.ClearAllPoints(self) self.__points = {} end
function IMPL.SetAllPoints(self, rel)
    if rel ~= nil and getmetatable(rel) ~= WidgetMT then error("SetAllPoints: bad frame", 2) end
    self.__points = {
        { point = "TOPLEFT", rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 },
        { point = "BOTTOMRIGHT", rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
    }
end
function IMPL.SetSize(self, w, h)
    num(w, "width"); num(h, "height")
    if w < 0 or h < 0 then error("negative size", 2) end
    self.__v.Size = { w, h }
end
function IMPL.SetWidth(self, w)
    num(w, "width"); if w < 0 then error("negative width", 2) end
    self.__v.Size = { w, self.__v.Size and self.__v.Size[2] or 0 }
end
function IMPL.SetHeight(self, h)
    num(h, "height"); if h < 0 then error("negative height", 2) end
    self.__v.Size = { self.__v.Size and self.__v.Size[1] or 0, h }
end
function IMPL.SetFrameLevel(self, n)
    num(n, "frame level")
    if n < 0 or n > 10000 then error("frame level " .. n, 2) end
    self.__level = n
end
function IMPL.GetFrameLevel(self)
    return self.__level or ((self.__parent and self.__parent ~= self and self.__parent:GetFrameLevel() or 0) + 1)
end
function IMPL.SetScale(self, s)
    num(s, "scale")
    if s <= 0 then error("scale " .. s, 2) end
    self.__scale = s
end
function IMPL.GetScale(self) return self.__scale or 1 end
function IMPL.GetCenter() return 640, 360 end
function IMPL.SetAlpha(self, a)
    if not issecretvalue(a) then
        num(a, "alpha")
        if a < -0.001 or a > 1.001 then warn("alpha out of range: " .. a) end
    end
end
local function colour(self, r, g, b, a)
    num(r, "red"); num(g, "green"); num(b, "blue")
    if a ~= nil then num(a, "alpha") end
end
IMPL.SetVertexColor, IMPL.SetTextColor, IMPL.SetStatusBarColor = colour, colour, colour
function IMPL.SetColorTexture(self, r, g, b, a)
    colour(self, r, g, b, a)
    self.__color, self.__file = { r, g, b, a or 1 }, nil
end
local BLEND = { BLEND = true, ADD = true, DISABLE = true, ALPHAKEY = true, MOD = true }
-- The boolean setters take a (possibly secret) true/false; the game applies it, the addon never
-- learns which. Here the real value picks, so snapshots show what the player would see.
function IMPL.SetVertexColorFromBoolean(self, v, yes, no)
    if type(yes) ~= "table" or type(no) ~= "table" then error("SetVertexColorFromBoolean needs colours", 2) end
    local c = real(v) and yes or no
    self.__v.VertexColor = { c.r, c.g, c.b, c.a or 1 }
end
function IMPL.SetAlphaFromBoolean(self, v, yes, no)
    num(yes, "alpha"); num(no, "alpha")
    if yes > 1 or no > 1 then warn("SetAlphaFromBoolean given alpha above 1") end
    self.__v.Alpha = { real(v) and yes or no }
end
function IMPL.SetBlendMode(self, m) if not BLEND[m] then error("blend mode " .. tostring(m), 2) end end
function IMPL.SetRotation(self, r) num(r, "rotation") end
function IMPL.SetTexCoord(self, a, b, c, d) num(a, "tc"); num(b, "tc"); num(c, "tc"); num(d, "tc") end
function IMPL.SetMinMaxValues(self, a, b)
    if not issecretvalue(a) then num(a, "min") end
    if not issecretvalue(b) then num(b, "max") end
end
function IMPL.SetValue(self, v) if not issecretvalue(v) then num(v, "value") end end

-- The game's duration objects: they keep counting on the game clock. With hidden values, the
-- addon gets secrets back from them, but widgets bound to them still show the real thing.
local DurMT = {}
DurMT.__index = DurMT
local function newDur(start, total, hidden) return setmetatable({ s = start, t = total, hid = hidden }, DurMT) end
local function durLeft(d) return math.max(0, d.s + d.t - clock) end
local function durWrap(d, v) if d.hid then return secret(v) end return v end
function DurMT:HasSecretValues() return self.hid and true or false end
function DurMT:GetRemainingDuration() return durWrap(self, durLeft(self)) end
function DurMT:GetTotalDuration() return durWrap(self, self.t) end
function DurMT:IsActive() return durWrap(self, durLeft(self) > 0) end
function DurMT:HasExpired() return durWrap(self, durLeft(self) <= 0) end
function DurMT:IsZero() return self.t <= 0 end
local function isDur(d) return getmetatable(d) == DurMT end

function IMPL.SetTimerDuration(self, d, interp, dir)
    if not isDur(d) then error("SetTimerDuration needs a duration object", 2) end
    if interp ~= nil then num(interp, "interpolation") end
    if dir ~= nil then num(dir, "direction") end
    self.__timer = d
end

-- Text bindings: the game rewrites the font string from the duration every tick.
local BINDINGS = {}
local BindMT = {}
BindMT.__index = BindMT
local function bindText(b)
    if not (b.on and b.fs and b.d) then return end
    local r = durLeft(b.d)
    local text
    if r <= 0 then text = b.zero or "" elseif r >= 10 then text = string.format("%ds", math.floor(r + 0.5)) else text = string.format("%.1f", r) end
    b.fs.__text = text
end
function BindMT:SetFontString(fs)
    if getmetatable(fs) ~= WidgetMT or fs.__kind ~= "FontString" then error("SetFontString needs a font string", 2) end
    self.fs = fs
end
function BindMT:SetFormatter(f) if type(f) ~= "table" then error("SetFormatter needs a formatter", 2) end end
function BindMT:SetUpdateInterval(n) num(n, "interval") end
function BindMT:SetZeroDurationText(t) self.zero = t end
function BindMT:SetExpiredText(t) self.zero = t end
function BindMT:SetDuration(d)
    if not isDur(d) then error("SetDuration needs a duration object", 2) end
    self.d = d
    bindText(self)
end
function BindMT:SetEnabled(on) self.on = on and true or false; bindText(self) end
local STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true, FULLSCREEN = true, TOOLTIP = true }
function IMPL.SetFrameStrata(self, s) if not STRATA[s] then error("strata " .. tostring(s), 2) end end
local LOOP = { NONE = true, REPEAT = true, BOUNCE = true }
function IMPL.SetLooping(self, m)
    if not LOOP[m] then error("looping " .. tostring(m), 2) end
    self.__loop = m
end
local SMOOTH = { NONE = true, IN = true, OUT = true, IN_OUT = true, OUT_IN = true }
function IMPL.SetSmoothing(self, m) if not SMOOTH[m] then error("smoothing " .. tostring(m), 2) end end
function IMPL.SetOrder(self, n) num(n, "order"); self.__order = n end
function IMPL.SetDuration(self, n) num(n, "duration"); self.__dur = n end
function IMPL.SetStartDelay(self, n) num(n, "delay"); self.__delay = n end
function IMPL.SetScaleFrom(self, x, y) num(x, "scale"); num(y, "scale") end
function IMPL.SetScaleTo(self, x, y) num(x, "scale"); num(y, "scale") end
function IMPL.SetOrigin(self, p, x, y)
    if not POINTS[p] then error("origin point " .. tostring(p), 2) end
    num(x, "origin"); num(y, "origin")
end
function IMPL.SetOffset(self, x, y) num(x, "offset"); num(y, "offset") end
function IMPL.SetFromAlpha(self, a) num(a, "alpha") end
function IMPL.SetToAlpha(self, a) num(a, "alpha") end
function IMPL.Play(self)
    local byOrder, total = {}, 0
    for _, a in ipairs(self.__anims) do
        local o = a.__order or 1
        byOrder[o] = math.max(byOrder[o] or 0, (a.__dur or 0) + (a.__delay or 0))
    end
    for _, d in pairs(byOrder) do total = total + d end
    self.__total, self.__t = total, 0
    PLAYING[self] = true
end
function IMPL.Stop(self) PLAYING[self] = nil end
function IMPL.IsPlaying(self) return PLAYING[self] and true or false end
function IMPL.RegisterForDrag(self, b) if b ~= "LeftButton" and b ~= "RightButton" then error("drag button", 2) end end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------
local function define(name, fn)
    if not DOC.globals[name] then warn("global function not in the client's API docs: " .. name) end
    _G[name] = fn
end
local function defineNS(ns, name, fn)
    if not (DOC.ns[ns] and DOC.ns[ns][name]) then warn("not in the client's API docs: " .. ns .. "." .. name) end
    _G[ns] = _G[ns] or {}
    _G[ns][name] = fn
end

-- Spells the tests use. Rank 2 Lightning Bolt (529) and Searing Totem (6363) are only known by
-- name to the addon: they check that other ranks are matched by name.
local NAMES = {
    [8042] = "Earth Shock", [8044] = "Earth Shock", [8050] = "Flame Shock", [8056] = "Frost Shock",
    [403] = "Lightning Bolt", [529] = "Lightning Bolt", [421] = "Chain Lightning", [324] = "Lightning Shield",
    [331] = "Healing Wave", [8004] = "Lesser Healing Wave", [1064] = "Chain Heal", [370] = "Purge",
    [2645] = "Ghost Wolf", [20549] = "War Stomp", [17364] = "Stormstrike", [16166] = "Elemental Mastery",
    [16188] = "Nature's Swiftness", [8017] = "Rockbiter Weapon", [8024] = "Flametongue Weapon",
    [8033] = "Frostbrand Weapon", [8232] = "Windfury Weapon",
    [8075] = "Strength of Earth Totem", [5730] = "Stoneclaw Totem", [8071] = "Stoneskin Totem",
    [3599] = "Searing Totem", [6363] = "Searing Totem", [5675] = "Mana Spring Totem", [5394] = "Healing Stream Totem",
    [8512] = "Windfury Totem", [8177] = "Grounding Totem",
    [16246] = "Clearcasting", [16257] = "Flurry", [6603] = "Attack",
    [133] = "Fireball", [2050] = "Lesser Heal", [2054] = "Heal", [168] = "Frost Armor",
}
local COSTS = {
    ["Lightning Bolt"] = 105, ["Chain Lightning"] = 280, ["Earth Shock"] = 140, ["Flame Shock"] = 120,
    ["Frost Shock"] = 150, ["Healing Wave"] = 250, ["Lesser Healing Wave"] = 100, ["Chain Heal"] = 260,
    ["Lightning Shield"] = 45, Purge = 80, ["Strength of Earth Totem"] = 80, ["Searing Totem"] = 70,
    ["Mana Spring Totem"] = 60, ["Windfury Totem"] = 90, ["Grounding Totem"] = 50, ["Stoneclaw Totem"] = 40,
    ["Windfury Weapon"] = 60, ["Ghost Wolf"] = 40,
}
-- Damage spells that Clearcasting makes free.
local CLEARCAST = { ["Lightning Bolt"] = true, ["Chain Lightning"] = true, ["Earth Shock"] = true,
    ["Flame Shock"] = true, ["Frost Shock"] = true }
local SHOCKS = { ["Earth Shock"] = true, ["Flame Shock"] = true, ["Frost Shock"] = true }
-- The game's real durations here differ from Thrum's built-in guesses on purpose (as if talented
-- or a higher rank), so the test shows which one the HUD follows.
local REAL_SHOCK_CD = 5
local TOTEMS = {
    ["Strength of Earth Totem"] = { slot = 2, t = 120 }, ["Stoneclaw Totem"] = { slot = 2, t = 15 },
    ["Stoneskin Totem"] = { slot = 2, t = 120 },
    ["Searing Totem"] = { slot = 1, t = 55 }, ["Mana Spring Totem"] = { slot = 3, t = 60 },
    ["Healing Stream Totem"] = { slot = 3, t = 60 },
    ["Windfury Totem"] = { slot = 4, t = 120 }, ["Grounding Totem"] = { slot = 4, t = 45 },
}

local function setup()
    CreateFrame = function(kind, name, parent)
        if not CHAINS[kind] or kind == "Texture" then error("CreateFrame: type " .. tostring(kind), 2) end
        COUNT.frames = COUNT.frames + 1
        local f = new(kind, parent)
        if name then rawset(_G, name, f) end
        return f
    end
    UIParent = new("Frame")

    -- Blizzard's Settings panel is Lua in the client, not in the API docs: enough of it here
    -- to build Thrum's page and flip its settings, with the same arguments the real one takes.
    SETTINGS = { cats = {}, settings = {} }
    local VarType = { Boolean = "boolean", String = "string", Number = "number" }
    local function add(cat, init) table.insert(cat.inits, init) return init end
    Settings = {
        VarType = VarType,
        RegisterVerticalLayoutCategory = function(name)
            if type(name) ~= "string" then error("category name", 2) end
            return { name = name, inits = {}, ID = 7, GetID = function(c) return c.ID end }
        end,
        RegisterAddOnCategory = function(cat) table.insert(SETTINGS.cats, cat) end,
        RegisterAddOnSetting = function(cat, variable, key, tbl, kind, name, default)
            if type(cat) ~= "table" or type(variable) ~= "string" or type(key) ~= "string" or type(tbl) ~= "table"
                or type(name) ~= "string" then
                error("RegisterAddOnSetting arguments", 2)
            end
            if kind ~= "boolean" and kind ~= "string" and kind ~= "number" then error("variable type " .. tostring(kind), 2) end
            if type(default) ~= kind then error("default for " .. key .. " is " .. type(default) .. ", not " .. kind, 2) end
            if tbl[key] == nil then tbl[key] = default end
            if type(tbl[key]) ~= kind then error("saved " .. key .. " is not a " .. kind, 2) end
            local s = { key = key, kind = kind, name = name, default = default }
            function s:GetValue() return tbl[key] end
            function s:SetValue(v)
                if type(v) ~= kind then error("setting " .. key .. " to a " .. type(v), 2) end
                tbl[key] = v
                if s.cb then s.cb(s, v) end
            end
            function s:SetValueChangedCallback(fn) s.cb = fn end
            SETTINGS.settings[key] = s
            return s
        end,
        CreateCheckbox = function(cat, s, tip)
            if s.kind ~= "boolean" then error("checkbox for a " .. s.kind, 2) end
            return add(cat, { kind = "checkbox", setting = s })
        end,
        CreateSliderOptions = function(lo, hi, step)
            return { lo = lo, hi = hi, step = step, SetLabelFormatter = function(o, label, fn)
                if type(fn) ~= "function" then error("label formatter", 2) end
                o.fmt = fn
            end }
        end,
        CreateSlider = function(cat, s, o, tip)
            if s.kind ~= "number" then error("slider for a " .. s.kind, 2) end
            if s.default < o.lo or s.default > o.hi then error("default " .. s.key .. " outside the slider", 2) end
            if o.fmt and type(o.fmt(s:GetValue())) ~= "string" then error("label formatter must return text", 2) end
            return add(cat, { kind = "slider", setting = s, options = o })
        end,
        CreateDropdown = function(cat, s, optionsFn, tip)
            local data = optionsFn()
            local ok = false
            for _, d in ipairs(data) do if d.value == s.default then ok = true end end
            if not ok then error("dropdown default not among its options", 2) end
            return add(cat, { kind = "dropdown", setting = s, data = data })
        end,
        CreateControlTextContainer = function()
            local c = { data = {} }
            function c:Add(v, label, tip) table.insert(self.data, { value = v, label = label, tooltip = tip }) end
            function c:GetData() return self.data end
            return c
        end,
        OpenToCategory = function(id) SETTINGS.opened = id end,
    }
    SettingsPanel = {
        GetLayout = function(_, cat) return { AddInitializer = function(_, init) add(cat, init) end } end,
        Close = function() SETTINGS.closed = true end,
    }
    MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
    CreateSettingsListSectionHeaderInitializer = function(name) return { kind = "header", name = name } end
    CreateSettingsButtonInitializer = function(name, text, click, tip)
        if type(click) ~= "function" then error("button needs a click handler", 2) end
        return { kind = "button", name = name, text = text, click = click }
    end
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) log("chat: " .. msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end }
    GameFontNormalLarge = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 16, "" end }
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    SlashCmdList = {}
    Enum = DOC.enums
    ERR_OUT_OF_MANA = "Not enough mana"
    FIRE_TOTEM_SLOT, EARTH_TOTEM_SLOT, WATER_TOTEM_SLOT, AIR_TOTEM_SLOT = 1, 2, 3, 4

    define("GetTime", function() return clock end)
    defineNS("C_Timer", "After", function(sec, fn)
        if type(sec) ~= "number" or type(fn) ~= "function" then error("C_Timer.After(sec, fn)", 2) end
        TIMERS[#TIMERS + 1] = { at = clock + sec, fn = fn }
    end)
    define("UnitClass", function() return "Whatever", G.class, 7 end)
    define("UnitPower", function(unit, kind)
        if unit ~= "player" then error("UnitPower for " .. tostring(unit), 2) end
        if kind == Enum.PowerType.Mana then return hide(G.mana) end
        return 0
    end)
    define("UnitPowerMax", function(unit, kind)
        if kind == Enum.PowerType.Mana then return hide(G.maxMana) end
        return 0
    end)
    -- used by Blizzard's own UI code in this client, though missing from the generated docs
    IsInGroup = function() return G.grouped end
    -- Blizzard's Edit Mode (Lua in the client, Blizzard_EditMode\Shared\EditModeManager.lua):
    -- it fires EventRegistry callbacks "EditMode.Enter" and "EditMode.Exit".
    local callbacks = {}
    EventRegistry = {
        RegisterCallback = function(self, event, fn, owner)
            if type(event) ~= "string" or type(fn) ~= "function" then error("RegisterCallback(event, fn, owner)", 2) end
            callbacks[event] = callbacks[event] or {}
            table.insert(callbacks[event], fn)
        end,
        TriggerEvent = function(self, event, ...)
            for _, fn in ipairs(callbacks[event] or {}) do fn(nil, ...) end
        end,
    }
    EditModeManagerFrame = { IsEditModeActive = function() return G.editMode or false end }
    define("UnitGUID", function(unit) return unit == "player" and "Player-1-0001" or hide("Creature-0-1") end)
    define("UnitExists", function() return G.target end)
    define("UnitCanAttack", function() return G.target end)
    define("UnitIsDead", function() return G.dead end)
    define("UnitAffectingCombat", function() return G.combat end)
    -- What enemies cast in these tests (spell id -> helpful?, description)
    local CASTS = {
        [133] = { false, "Hurls a fiery ball that causes 16 to 25 Fire damage." },
        [2050] = { true, "Heal your target for 47 to 58." },
        [2054] = { true, "Heal your target for 295 to 341." },
        [168] = { true, "Increases Armor by 30 for 30 min." },
    }
    define("UnitCastingInfo", function(unit)
        if unit == "player" then
            -- your own cast is never hidden
            local c = G.selfCast
            if not c then return nil end
            return NAMES[c.id], NAMES[c.id], 136000 + c.id % 100, c.s * 1000, (c.s + c.t) * 1000, false, "Cast-P",
                false, c.id
        end
        if unit ~= "target" or not G.casting then return nil end
        local id = G.castID or 133
        local function h(v) if G.secret then return secret(v) end return v end
        local start = G.castAt or clock
        return h(NAMES[id]), h(NAMES[id]), h(136000 + id % 100), h(start * 1000), h((start + 2.5) * 1000),
            h(false), h("Cast-9"), h(G.castNoKick or false), h(id)
    end)
    define("UnitChannelInfo", function() return nil end)
    defineNS("C_Spell", "IsSpellHelpful", function(id)
        local v = CASTS[real(id)] and CASTS[real(id)][1] or false
        if issecretvalue(id) then return secret(v) end
        return v
    end)
    defineNS("C_Spell", "GetSpellDescription", function(id)
        local d = CASTS[real(id)] and CASTS[real(id)][2] or ""
        if issecretvalue(id) then return secret(d) end
        return d
    end)
    CreateColor = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a, GetRGBA = function(c) return c.r, c.g, c.b, c.a end }
    end
    defineNS("C_Spell", "GetSpellName", function(id) return NAMES[id] end)
    defineNS("C_Spell", "GetSpellTexture", function(id) return NAMES[id] and 136000 + id % 100 or nil end)
    local BYNAME = {}
    for id, n in pairs(NAMES) do BYNAME[n] = BYNAME[n] or id end
    local function nameOf(spell) return type(spell) == "string" and spell or NAMES[spell] end
    defineNS("C_Spell", "GetSpellPowerCost", function(spell)
        local name = nameOf(spell)
        if not name or not BYNAME[name] then return nil end
        local c = COSTS[name]
        if not c then return {} end
        if G.clearcasting and CLEARCAST[name] then c = 0 end
        return { { type = Enum.PowerType.Mana, cost = c, minCost = c, name = "MANA" } }
    end)
    local function cooldownOf(spell)
        local name = nameOf(spell)
        if name and SHOCKS[name] then name = "Shock" end
        local cd = name and G.cds[name]
        if cd and cd.s + cd.t > clock then return cd end
    end
    defineNS("C_Spell", "IsSpellUsable", function(spell)
        local name = nameOf(spell)
        if not name or not BYNAME[name] then return false, false end -- not a spell you know
        if name == "War Stomp" and not G.tauren then return false, false end
        local enough = G.mana >= (COSTS[name] or 0)
        return enough, not enough
    end)
    defineNS("C_Spell", "GetSpellCooldown", function(id)
        local cd = cooldownOf(id) or { s = 0, t = 0 }
        if G.secret then return { startTime = secret(cd.s), duration = secret(cd.t), isEnabled = secret(true), modRate = 1 } end
        return { startTime = cd.s, duration = cd.t, isEnabled = true, modRate = 1 }
    end)
    defineNS("C_Spell", "GetSpellCooldownDuration", function(id, ignoreGCD)
        local cd = cooldownOf(id)
        if cd then return newDur(cd.s, cd.t, G.secret) end
        return newDur(clock, 0, G.secret)
    end)

    -- Auras. The player's list holds your buffs; the target's "mine" list your debuffs on it,
    -- its "buffs" list what it has on itself (for Purge).
    local FILTERS = { player = { ["HELPFUL|PLAYER"] = "player" },
        target = { ["HARMFUL|PLAYER"] = "target", ["HELPFUL"] = "targetBuffs" } }
    local function auraList(unit, filter)
        if unit == "target" and not G.target then return {} end
        local key = FILTERS[unit] and FILTERS[unit][filter]
        if not key then error("aura filter " .. tostring(filter) .. " for " .. tostring(unit), 3) end
        return G.auraList[key] or {}
    end
    local function findAura(unit, id)
        local lists = unit == "player" and { G.auraList.player } or { G.auraList.target, G.auraList.targetBuffs }
        for _, l in ipairs(lists) do
            for _, a in ipairs(l) do
                if a.id == id then return a end
            end
        end
    end
    defineNS("C_UnitAuras", "GetUnitAuraInstanceIDs", function(unit, filter)
        local ids = {}
        for _, a in ipairs(auraList(unit, filter)) do ids[#ids + 1] = a.id end
        return ids
    end)
    defineNS("C_UnitAuras", "GetAuraDuration", function(unit, id)
        local a = findAura(unit, id)
        if a then return newDur(a.s, a.t, G.secret) end
        error("RequiresValidUnitAuraInstance: no aura " .. tostring(id) .. " on " .. tostring(unit), 2)
    end)
    defineNS("C_UnitAuras", "GetAuraApplicationDisplayCount", function(unit, id, min, max)
        local a = findAura(unit, id)
        if not a then error("RequiresValidUnitAuraInstance: no aura " .. tostring(id) .. " on " .. tostring(unit), 2) end
        local n = a.stacks or 0
        local s = (n >= (min or 2)) and ((max and n > max) and "*" or tostring(n)) or ""
        return hide(s)
    end)
    -- RequiresNonSecretAura: nothing comes back for auras that are hidden
    defineNS("C_UnitAuras", "GetAuraDataBySpellName", function(unit, name, filter)
        if filter ~= "HELPFUL" and filter ~= "HARMFUL|PLAYER" then error("aura filter " .. tostring(filter), 2) end
        if G.secret then return nil end
        local list = unit == "player" and G.auraList.player or (G.target and G.auraList.target or {})
        for _, a in ipairs(list) do
            if a.name == name then
                return { auraInstanceID = a.id, expirationTime = a.s + a.t, duration = a.t, applications = a.stacks or 0 }
            end
        end
    end)
    defineNS("C_UnitAuras", "GetPlayerAuraBySpellID", function(spellID)
        if G.secret then return nil end
        for _, a in ipairs(G.auraList.player) do
            if a.spellID == spellID or (NAMES[spellID] and a.name == NAMES[spellID]) then
                return { auraInstanceID = a.id, expirationTime = a.s + a.t, duration = a.t, applications = a.stacks or 0 }
            end
        end
    end)
    defineNS("C_DurationUtil", "CreateDurationTextBinding", function()
        local b = setmetatable({}, BindMT)
        BINDINGS[#BINDINGS + 1] = b
        return b
    end)
    defineNS("C_StringUtil", "CreateSecondsFormatter", function()
        return setmetatable({}, { __index = function() return function() end end })
    end)
    defineNS("C_Secrets", "ShouldAurasBeSecret", function() return G.secret end)

    -- Totems: GetTotemInfo is secret in combat; GetTotemDuration is a duration object.
    define("GetTotemInfo", function(slot)
        if type(slot) ~= "number" or slot < 1 or slot > 4 then error("GetTotemInfo slot " .. tostring(slot), 2) end
        local t = G.totems[slot]
        local have = t ~= nil and t.s + t.t > clock
        if not have then return hide(false), hide(""), hide(0), hide(0), hide(0) end
        return hide(true), hide(t.name), hide(t.s), hide(t.t), hide(136000 + slot)
    end)
    define("GetTotemDuration", function(slot)
        if type(slot) ~= "number" or slot < 1 or slot > 4 then error("GetTotemDuration slot " .. tostring(slot), 2) end
        local t = G.totems[slot]
        if t and t.s + t.t > clock then return newDur(t.s, t.t, G.secret) end
        return newDur(clock, 0, G.secret)
    end)

    -- The weapon imbue
    defineNS("C_Item", "GetWeaponEnchantInfo", function(slot)
        if slot ~= Enum.WeaponSlot.MainHand and slot ~= Enum.WeaponSlot.OffHand and slot ~= Enum.WeaponSlot.Ranged then
            error("GetWeaponEnchantInfo slot " .. tostring(slot), 2)
        end
        local w = G.imbue
        if slot == Enum.WeaponSlot.MainHand and w and w.s + w.t > clock then
            return { { hasEnchant = true, enchantType = Enum.ItemEnchantType.Imbue, timeLeft = (w.s + w.t - clock) * 1000,
                charges = 0, enchantID = w.id, enchantIconID = 136018 } }
        end
        return { { hasEnchant = false, enchantType = Enum.ItemEnchantType.None, timeLeft = 0, charges = 0, enchantID = 0,
            enchantIconID = 0 } }
    end)
end

--------------------------------------------------------------------------------
-- Driving it
--------------------------------------------------------------------------------
local function call(what, fn, ...)
    local ok, err = xpcall(fn, function(e) return tostring(e) .. debug.traceback("", 2) end, ...)
    if not ok then fail(string.format("[%s at %.2f] %s", what, clock - t0, err)) end
end

local function fire(event, ...)
    if not DOC.events[event] then fail("test fires an event the client does not have: " .. event) end
    local regs = EVENTS[event]
    if not regs then return end
    local unit = ...
    local list = {}
    for frame, units in pairs(regs) do
        if units == "*" or units[unit] then list[#list + 1] = frame end
    end
    for _, frame in ipairs(list) do
        local h = frame.__scripts.OnEvent
        if h then call(event, h, frame, event, ...) end
    end
end

local function step(seconds)
    local dt = 1 / 30
    for _ = 1, math.floor(seconds / dt + 0.5) do
        clock = clock + dt
        local due = {}
        for i = #TIMERS, 1, -1 do
            if TIMERS[i].at <= clock then due[#due + 1] = table.remove(TIMERS, i) end
        end
        table.sort(due, function(a, b) return a.at < b.at end)
        for _, t in ipairs(due) do call("C_Timer", t.fn) end
        for _, b in ipairs(BINDINGS) do bindText(b) end
        for key, list in pairs(G.auraList) do
            local gone = false
            for i = #list, 1, -1 do
                if list[i].s + list[i].t <= clock then table.remove(list, i); gone = true end
            end
            if gone then fire("UNIT_AURA", key == "player" and "player" or "target", {}) end
        end
        for slot, t in pairs(G.totems) do
            if t.s + t.t <= clock then
                G.totems[slot] = nil
                fire("PLAYER_TOTEM_UPDATE", slot)
            end
        end
        local ups = {}
        for f in pairs(UPDATERS) do ups[#ups + 1] = f end
        for _, f in ipairs(ups) do
            if f.__scripts.OnUpdate then call("OnUpdate", f.__scripts.OnUpdate, f, dt) end
        end
        local done = {}
        for ag in pairs(PLAYING) do
            ag.__t = ag.__t + dt
            if ag.__t >= ag.__total and (ag.__loop or "NONE") == "NONE" then done[#done + 1] = ag end
        end
        for _, ag in ipairs(done) do
            PLAYING[ag] = nil
            if ag.__scripts.OnFinished then call("OnFinished", ag.__scripts.OnFinished, ag) end
        end
    end
end

local H
local function str(v) return issecretvalue(v) and "<secret>" or tostring(v) end

local function boot(class)
    EVENTS, UPDATERS, PLAYING, TIMERS = {}, {}, {}, {}
    for i = #ALL, 1, -1 do ALL[i] = nil end
    G = { mana = 1800, maxMana = 1800, secret = false, target = false, dead = false, casting = false,
        combat = false, auraList = { player = {}, target = {}, targetBuffs = {} }, cds = {}, totems = {},
        nextAura = 100, class = class }
    ThrumDB, ThrumCharDB, ThrumHUD = nil, nil, nil
    BINDINGS = {}
    setup()
    H = {}
    for _, f in ipairs(FILES) do
        local chunk, err = load(f.code, "@" .. f.name)
        if not chunk then
            fail("syntax: " .. tostring(err))
        else
            call("load " .. f.name, chunk, "Thrum", H)
        end
    end
    -- watch what the addon decides to show
    local function spy(tbl, name, fmt)
        local orig = tbl[name]
        if not orig then fail("missing function " .. name) return end
        tbl[name] = function(self, ...)
            local s = fmt(...)
            if s then log(s) end
            return orig(self, ...)
        end
    end
    spy(H.FX, "Word", function(text, o)
        local sub = o and (o.subValue ~= nil and str(o.subValue) or o.sub)
        return "WORD  " .. text .. (sub and ("  [" .. sub .. "]") or "")
    end)
    spy(H.FX, "Pop", function(text) return "pop   " .. text end)
    spy(H.Timers, "Start", function(key, o)
        return string.format("box   %s  %s %s", key, o.label, o.untimed and "(untimed)" or string.format("%.1fs", o.duration))
    end)
    spy(H.Timers, "Stop", function(key) return H.Timers:Get(key) and ("box   " .. key .. " removed") or nil end)
    spy(H.Timers, "Adjust", function(key, exp) return string.format("box   %s corrected to %.1fs left", key, exp - clock) end)
    spy(H.Timers, "Bind", function(key, d)
        local t = H.Timers:Get(key)
        if t and not t.bound and isDur(d) and not t.untimed then
            return string.format("box   %s on the game's timer: %.1fs left%s", key, durLeft(d), d.hid and " (hidden from addon)" or "")
        end
    end)
    spy(H.HUD, "SetPrompt", function(text, cast, ...)
        if text == H.HUD.promptText and cast == H.HUD.promptCast and (... or "go") == (H.HUD.promptMode or "go") then return nil end
        if not text then return H.HUD.promptText and "prompt hidden" or nil end
        local c = cast or {}
        local hidden = issecretvalue(c.name) and " [hidden from addon]" or ""
        local tag = real(c.helpful) and (c.heal == false and "BUFF!" or "HEAL!") or "-"
        local noKick = real(c.notInterruptible) and "  (box invisible: can't be interrupted)" or ""
        local quiet = ((...) == "wait") and "  (dim, no pulse)" or ""
        return string.format("prompt %s  spell=%s  tag=%s%s%s%s", text, tostring(real(c.name)), tag, hidden, noKick, quiet)
    end)
    spy(H.HUD, "Spend", function(cost) return "spend " .. str(cost) end)
    spy(H.HUD, "Refill", function(amount) return "refill +" .. str(amount) end)
    spy(H.HUD, "Error", function() return "error flash" end)
    spy(H.HUD, "SetPalette", function(m) if m ~= H.HUD.palette then return "palette " .. m end end)
    spy(H.HUD, "SetShield", function(on, count, n)
        if on ~= H.HUD.shieldOn or (on and n ~= H.HUD.shieldN) then
            H.HUD.shieldN = n
            return on and ("shield up, charges " .. str(count)) or "shield gone"
        end
    end)
    spy(H.HUD, "ShieldCharge", function() return "shield charge used" end)
    spy(H.HUD, "SetImbue", function(info)
        if info then return string.format("imbue %s (%.0fs)", tostring(info.id or "?"), info.seconds or -1) end
        return H.HUD.imbue and "imbue gone" or nil
    end)
    spy(H.HUD, "SetClearcasting", function(on) if on ~= H.HUD.clearcasting then return "clearcasting " .. tostring(on) end end)
    spy(H.HUD, "StartCast", function(info) return "cast  " .. str(info.name) .. (info.kind and (" (" .. info.kind .. ")") or "") end)
    spy(H.HUD, "EndCast", function(result) if H.HUD.casting then return "cast  " .. result end end)
    spy(H.Totems, "Placed", function(def, quiet) return "totem " .. def.totem .. ": " .. def.key .. (quiet and " (quietly)" or "") end)
    local update = H.Totems.Update
    H.Totems.Update = function(self, slot, ...)
        local s
        for _, el in ipairs({ "earth", "fire", "water", "air" }) do
            local p = self:Plaque(el)
            if p and p.slot == slot then s = p end
        end
        local wasBound = s and s.bound
        local r = update(self, slot, ...)
        if s and s.bound and not wasBound and s.dur then
            log(string.format("totem %s on the game's timer: %.1fs left%s", s.el, durLeft(s.dur), s.dur.hid and " (hidden from addon)" or ""))
        end
        return r
    end

    fire("ADDON_LOADED", "Thrum")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", true, false)
    step(0.5)
end

local function power()
    fire("UNIT_POWER_FREQUENT", "player", "MANA")
    fire("UNIT_POWER_UPDATE", "player", "MANA")
end
local function mana(v) G.mana = math.max(0, math.min(G.maxMana, v)); power() end

-- Puts an aura on a unit's list, as if the game applied it.
local function aura(list, name, dur, stacks)
    G.nextAura = G.nextAura + 1
    table.insert(G.auraList[list], { id = G.nextAura, name = name, s = clock, t = dur, stacks = stacks })
    fire("UNIT_AURA", list == "player" and "player" or "target", {})
    return G.nextAura
end
local function unaura(list, name)
    for i, a in ipairs(G.auraList[list]) do
        if a.name == name then table.remove(G.auraList[list], i) break end
    end
    fire("UNIT_AURA", list == "player" and "player" or "target", {})
end
local function findAura(list, name)
    for _, a in ipairs(G.auraList[list]) do
        if a.name == name then return a end
    end
end

-- One of your spells goes off (UNIT_SPELLCAST_SUCCEEDED), with what the game does around it.
-- castFirst: whether the cast event arrives before the mana change.
local function cast(id, castFirst)
    local name = NAMES[id] or ""
    local c = COSTS[name] or 0
    if G.clearcasting and CLEARCAST[name] then
        c = 0
        G.clearcasting = false
        unaura("player", "Clearcasting")
    end
    if SHOCKS[name] then G.cds.Shock = { s = clock, t = REAL_SHOCK_CD } end
    if name == "Chain Lightning" then G.cds[name] = { s = clock, t = 6 } end
    local function ev() fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0", id) end
    if castFirst then ev() end
    if c > 0 then mana(G.mana - c) end
    if not castFirst then ev() end
    local totem = TOTEMS[name]
    if totem then
        G.totems[totem.slot] = { s = clock, t = totem.t, name = name }
        fire("PLAYER_TOTEM_UPDATE", totem.slot)
    end
end
-- A spell with a cast time: the bar runs, then it goes off.
local function castTime(id, secs)
    G.selfCast = { id = id, s = clock, t = secs }
    fire("UNIT_SPELLCAST_START", "player", "Cast-3-1", id)
    step(secs)
    G.selfCast = nil
    cast(id, true)
    fire("UNIT_SPELLCAST_STOP", "player", "Cast-3-1", id)
end

local function logHas(text)
    for _, l in ipairs(LOG) do
        if l:find(text, 1, true) then return true end
    end
    return false
end
local function plaque(el) return H.Totems:Plaque(el) end

local function fight(label, hidden)
    say("")
    say("--- " .. label .. " ---")
    LOG = {}
    t0 = clock
    G.target, G.dead = true, false
    G.auraList.targetBuffs = {}
    fire("PLAYER_TARGET_CHANGED")
    mana(G.maxMana)
    -- buffing up out of combat
    cast(324, true)
    step(0.05)
    aura("player", "Lightning Shield", 600, 3)
    step(0.3)
    if not H.HUD.shieldOn then fail("Lightning Shield orb did not light up") end
    if tostring(real(H.HUD.orb.count.__text)) ~= "3" then fail("shield orb shows " .. tostring(real(H.HUD.orb.count.__text)) .. ", expected 3") end
    cast(8232, true)
    G.imbue = { s = clock, t = 300, id = 283 }
    fire("WEAPON_ENCHANT_CHANGED")
    fire("UNIT_INVENTORY_CHANGED", "player")
    step(0.5)
    if not H.HUD.imbue then fail("imbue badge is empty after Windfury Weapon") end
    if tostring(real(H.HUD.badge.time.__text)) ~= "5m" then fail("imbue shows " .. tostring(real(H.HUD.badge.time.__text)) .. ", expected 5m") end
    -- the four totems
    cast(8075, false) step(1)
    cast(6363, false) step(1) -- rank 2 Searing: matched by name; the game says 55s, not 30
    cast(5675, false) step(1)
    cast(8512, false) step(1)
    local sear = plaque("fire")
    if not (sear and sear.on and sear.bound) then fail("Searing Totem plaque is not on the game's timer") end
    local st = sear and tostring(real(sear.time.__text))
    if not (st and st:find("^5%d")) then fail("Searing plaque shows " .. tostring(st) .. ", expected the real ~52s") end
    if H.Totems.count ~= 4 then fail("expected 4 totems standing, the HUD counts " .. tostring(H.Totems.count)) end

    -- the fight
    G.secret = hidden
    G.combat = true
    fire("PLAYER_REGEN_DISABLED")
    castTime(529, 2.0) -- rank 2 Lightning Bolt
    if not H.HUD.fsr.__shown then fail("five-second-rule line not shown after spending mana") end
    fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", secret(412), 8)
    step(0.4)
    log("(you are hit: a Lightning Shield charge goes off)")
    findAura("player", "Lightning Shield").stacks = 2
    fire("UNIT_AURA", "player", {})
    step(0.4)
    -- the target casts a heal; shock it
    G.casting, G.castID, G.castAt = true, 2054, clock
    fire("UNIT_SPELLCAST_START", "target", "Cast-1", 2054, 1)
    step(0.5)
    cast(8042, false)
    G.casting = false
    fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 2054)
    fire("UNIT_SPELLCAST_STOP", "target", "Cast-1", 2054)
    step(0.3)
    if not logHas("WORD  BROKEN!") then fail("no BROKEN! for an Earth Shock interrupt") end
    local sb = H.Timers:Get("cd:shock")
    if not (sb and sb.bound) then fail("shock cooldown box is not on the game's timer") end
    step(0.5)
    -- Clearcasting
    log("(Clearcasting procs)")
    G.clearcasting = true
    aura("player", "Clearcasting", 15)
    step(0.3)
    if not H.Timers:Get("proc:clear") then fail("no Clearcasting box") end
    castTime(421, 1.5) -- Chain Lightning, free
    step(0.3)
    if H.Timers:Get("proc:clear") then fail("Clearcasting box stayed after it was used") end
    step(4)
    cast(8050, true) -- Flame Shock, once the shocks are back
    step(0.05)
    aura("target", "Flame Shock", 12)
    step(0.4)
    local fb = H.Timers:Get("aura:flame")
    if not (fb and fb.bound) then fail("Flame Shock box did not take the game's timer") end
    -- the fire totem is killed
    log("(the Searing Totem is killed)")
    G.totems[1] = nil
    fire("PLAYER_TOTEM_UPDATE", 1)
    step(0.6)
    if hidden then
        if logHas("SMASHED!") then fail("SMASHED! while totem state is hidden") end
    elseif not logHas("pop   SMASHED!") then
        fail("no SMASHED! when the Searing Totem was killed")
    end
    -- swap the earth totem: a replacement is not a smash
    local before = #LOG
    log("(Stoneclaw replaces Strength of Earth)")
    G.totems[2] = nil
    fire("PLAYER_TOTEM_UPDATE", 2)
    cast(5730, false)
    step(0.6)
    for i = before + 1, #LOG do
        if LOG[i]:find("SMASHED", 1, true) then fail("SMASHED! when a totem was replaced") end
    end
    -- Purge a buff off the target
    log("(the target has a buff; Purge takes it)")
    aura("targetBuffs", "Frost Armor", 1800)
    step(0.3)
    cast(370, true)
    unaura("targetBuffs", "Frost Armor")
    step(0.3)
    if not logHas("WORD  PURGED!") then fail("no PURGED! when Purge took a buff") end
    -- out of mana, then a big refill
    fire("UI_ERROR_MESSAGE", 52, "Not enough mana")
    step(0.5)
    mana(G.mana + 700)
    step(0.5)
    fire("UNIT_COMBAT", "target", "RESIST", "", secret(0), 8)
    step(0.5)
    -- the target dies
    G.dead = true
    fire("UNIT_HEALTH", "target")
    step(1)
    G.target = false
    fire("PLAYER_TARGET_CHANGED")
    G.combat = false
    G.secret = false
    fire("PLAYER_REGEN_ENABLED")
    mana(G.mana)
    step(6)
    if H.HUD.fsr.__shown then fail("five-second-rule line still shown long after the last spend") end
    -- the imbue runs out, the totems run down
    log("(waiting for the imbue and the totems to run out)")
    G.imbue.t = clock - G.imbue.s + 2
    step(130)
    if not logHas("IMBUE FADED!") then fail("no IMBUE FADED! when the imbue ran out") end
    if H.Totems.count ~= 0 then fail("totems still counted after they all ran out: " .. tostring(H.Totems.count)) end
    for _, l in ipairs(LOG) do say(l) end
    G.auraList = { player = {}, target = {}, targetBuffs = {} }
    G.cds, G.totems, G.imbue = {}, {}, nil
    H.Tracker.shieldID = nil
end

-- In a party: effects that cannot be pinned on you stay off.
local function grouped()
    say("")
    say("--- in a group (expect: no CRIT!/RESISTED!/SLAIN!/PURGED!, BROKEN! only for your own shock) ---")
    LOG = {}
    t0 = clock
    G.grouped = true
    G.target, G.dead, G.combat = true, false, true
    fire("PLAYER_TARGET_CHANGED")
    fire("PLAYER_REGEN_DISABLED")
    mana(1800)
    cast(403, true)
    fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", secret(300), 8)
    fire("UNIT_COMBAT", "target", "RESIST", "", secret(0), 8)
    step(1)
    log("(someone else interrupts as you shock)")
    G.casting, G.castID, G.castAt = true, 133, clock
    fire("UNIT_SPELLCAST_START", "target", "Cast-2", 133, 1)
    step(0.3)
    cast(8042, false)
    G.casting = false
    fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-2", 133, "Player-1-0002")
    step(1)
    log("(an interrupt with no name on it)")
    G.casting, G.castAt = true, clock
    fire("UNIT_SPELLCAST_START", "target", "Cast-3", 133, 1)
    step(5)
    cast(8042, false)
    G.casting = false
    fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-3", 133)
    step(6)
    log("(your shock interrupts)")
    G.casting, G.castAt = true, clock
    fire("UNIT_SPELLCAST_START", "target", "Cast-4", 133, 1)
    step(0.3)
    cast(8042, false)
    G.casting = false
    fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-4", 133, "Player-1-0001")
    step(1)
    log("(purge in a group)")
    aura("targetBuffs", "Frost Armor", 1800)
    step(0.2)
    cast(370, true)
    unaura("targetBuffs", "Frost Armor")
    step(0.5)
    G.dead = true
    fire("UNIT_HEALTH", "target")
    step(1)
    for _, l in ipairs(LOG) do
        if l:find("CRIT!", 1, true) or l:find("RESISTED!", 1, true) or l:find("SLAIN!", 1, true) or l:find("PURGED!", 1, true) then
            fail("grouped: " .. l)
        end
    end
    local broken = 0
    for _, l in ipairs(LOG) do if l:find("BROKEN!", 1, true) then broken = broken + 1 end end
    if broken ~= 1 then fail("grouped: expected one BROKEN! (your own shock), got " .. broken) end
    G.grouped, G.combat, G.target = false, false, false
    fire("PLAYER_REGEN_ENABLED")
    fire("PLAYER_TARGET_CHANGED")
    step(10)
    for _, l in ipairs(LOG) do say(l) end
    G.auraList = { player = {}, target = {}, targetBuffs = {} }
    G.cds = {}
end

-- Mana regenerating in small steps, readable and hidden: no effects, and the number changes calmly.
local function regen()
    say("")
    say("--- mana regenerating (expect: no refill pops, number at most ~4 changes/s) ---")
    local shows = 0
    local orig = H.HUD.ShowNumber
    H.HUD.ShowNumber = function(self, ...) shows = shows + 1 return orig(self, ...) end
    for _, hidden in ipairs({ false, true }) do
        LOG = {}
        t0 = clock
        G.secret = hidden
        G.combat = hidden
        mana(200)
        step(3)
        shows = 0
        for _ = 1, 50 do
            G.mana = G.mana + 6
            power()
            step(0.1)
        end
        local pops = 0
        for _, l in ipairs(LOG) do if l:find("refill", 1, true) or l:find("pop", 1, true) then pops = pops + 1 end end
        say(string.format("  %s: %d pops, number changed %d times in 5s", hidden and "hidden" or "readable", pops, shows))
        if pops > 0 then fail("regeneration made noise (" .. pops .. " pops)") end
        if shows > 24 then fail("mana number changes too often (" .. shows .. " in 5s)") end
        -- spending still shows straight away
        shows = 0
        cast(403, true)
        step(0.05)
        if shows == 0 then fail("mana number did not follow a spend") end
    end
    G.secret, G.combat = false, false
    H.HUD.ShowNumber = orig
end

-- What the target casts: the SHOCK IT! box names it and flags heals.
local function casts()
    say("")
    say("--- target casts (expect: name every time, HEAL!/BUFF! tags, no box for uninterruptible) ---")
    LOG = {}
    t0 = clock
    G.target, G.dead, G.combat, G.grouped = true, false, true, false
    fire("PLAYER_TARGET_CHANGED")
    mana(1800)
    local function try(id, hidden, noKick, label)
        log("(" .. label .. ")")
        G.secret, G.castID, G.castNoKick, G.castAt = hidden, id, noKick, clock
        G.casting = true
        fire("UNIT_SPELLCAST_START", "target", "Cast-9", id, 1)
        step(0.4)
        if not H.HUD.prompt.__shown and not noKick then fail("no SHOCK IT! box for " .. label) end
        G.casting = false
        fire("UNIT_SPELLCAST_STOP", "target", "Cast-9", id, 1)
        step(0.2)
    end
    try(133, false, false, "Fireball, readable")
    try(2050, false, false, "Lesser Heal, readable")
    try(168, false, false, "Frost Armor, readable")
    try(2050, true, false, "Lesser Heal, hidden")
    try(133, true, false, "Fireball, hidden")
    log("(shocks on cooldown, Grounding Totem known: ground the Fireball, wait on the heal)")
    G.cds.Shock = { s = clock, t = 6 }
    H.Timers:Start("cd:shock", { label = "SHOCKS", duration = 6, kind = "cd" })
    try(133, false, false, "Fireball, readable")
    try(2050, false, false, "Lesser Heal, readable")
    log("(a tauren: War Stomp)")
    G.tauren = true
    try(2050, false, false, "Lesser Heal, readable")
    G.tauren = false
    log("(shocks back mid-cast: the box switches to SHOCK IT!)")
    G.cds.Shock = { s = clock, t = 1 }
    H.Timers:Start("cd:shock", { label = "SHOCKS", duration = 1, kind = "cd" })
    G.casting, G.castID, G.castAt = true, 2050, clock
    fire("UNIT_SPELLCAST_START", "target", "Cast-9", 2050, 1)
    step(1.5)
    G.casting = false
    fire("UNIT_SPELLCAST_STOP", "target", "Cast-9", 2050, 1)
    step(0.3)
    try(133, false, true, "shielded Fireball, readable")
    try(2050, true, true, "shielded Lesser Heal, hidden")
    G.secret, G.combat, G.target, G.castNoKick = false, false, false, false
    fire("PLAYER_TARGET_CHANGED")
    step(1)
    for _, l in ipairs(LOG) do say(l) end
end

local function slash(msg)
    call("/thrum " .. msg, SlashCmdList.THRUM, msg)
end

-- The page under Options > AddOns > Thrum: built, and every setting takes effect.
local function options()
    say("")
    say("--- options page ---")
    LOG = {}
    t0 = clock
    local cat = SETTINGS.cats[1]
    if not cat then
        fail("no options page registered" .. (H.Options.failed and (": " .. H.Options.failed) or ""))
        return
    end
    local items = {}
    for _, init in ipairs(cat.inits) do
        items[#items + 1] = init.kind .. ":" .. (init.setting and init.setting.key or init.name or "")
    end
    say("  " .. cat.name .. ": " .. table.concat(items, ", "))
    local S = SETTINGS.settings
    for _, key in ipairs({ "locked", "x", "y", "combatOnly", "scale", "idle", "totems", "imbue", "fsr", "castbar", "words", "fx", "procs", "hits", "prompt" }) do
        if not S[key] then fail("no setting for " .. key) end
    end
    S.scale:SetValue(1.4)
    if ThrumHUD.__scale ~= 1.4 then fail("Size did not resize the HUD") end
    S.x:SetValue(-300)
    S.y:SetValue(150)
    local p = ThrumHUD.__points[1]
    if not (p and p.x == -300 and p.y == 150) then fail("Across / Up and down did not move the HUD") end
    S.combatOnly:SetValue(false)
    if ThrumDB.combatOnly ~= false then fail("Only in combat did not change the saved setting") end
    S.combatOnly:SetValue(true)
    S.locked:SetValue(false)
    if not H.HUD.mover.__shown then fail("unlocking did not show the mover") end
    S.locked:SetValue(true)
    S.totems:SetValue(false)
    if H.Totems.row.__shown then fail("totem plaques still shown") end
    S.totems:SetValue(true)
    if not H.Totems.row.__shown then fail("totem plaques did not come back") end
    S.fsr:SetValue(false)
    H.HUD:SetFSR(clock)
    if H.HUD.fsr.__shown then fail("five-second line still shown") end
    S.fsr:SetValue(true)
    S.castbar:SetValue(false)
    H.HUD:StartCast({ name = "Healing Wave", startMs = clock * 1000, endMs = clock * 1000 + 1500 })
    if H.HUD.cast.__shown then fail("cast bar still shown") end
    S.castbar:SetValue(true)
    H.HUD.imbueKnown = true
    S.imbue:SetValue(false)
    if H.HUD.badge.__shown then fail("imbue badge still shown") end
    S.imbue:SetValue(true)
    if not H.HUD.badge.__shown then fail("imbue badge did not come back") end
    S.words:SetValue(false)
    if ThrumDB.words ~= false then fail("Spell words did not change the saved setting") end
    S.words:SetValue(true)
    slash("options")
    if SETTINGS.opened ~= 7 then fail("/thrum options did not open the page") end
    for _, init in ipairs(cat.inits) do
        if init.kind == "button" and init.name == "Try it out" then init.click() end
    end
    if not H.demo then fail("Play demo did not start the demo") end
    step(16)
    say("  every setting applied")
    for _, l in ipairs(LOG) do say(l) end
end

-- Out of combat the HUD hides; Edit Mode shows it and lets it be dragged.
local function placing()
    say("")
    say("--- out of combat, and Edit Mode (expect: hidden out of combat, shown and draggable in Edit Mode) ---")
    LOG = {}
    t0 = clock
    local root = ThrumHUD
    local function alpha() return root.__v.Alpha and real(root.__v.Alpha[1]) or 1 end
    G.combat, G.target = false, false
    fire("PLAYER_TARGET_CHANGED")
    fire("PLAYER_REGEN_ENABLED")
    step(1.5)
    say(string.format("  out of combat: alpha %.2f", alpha()))
    if alpha() > 0.01 then fail("HUD not hidden out of combat (alpha " .. alpha() .. ")") end
    G.combat = true
    fire("PLAYER_REGEN_DISABLED")
    step(0.2)
    say(string.format("  0.2s into combat: alpha %.2f", alpha()))
    if alpha() < 0.99 then fail("HUD not shown straight away in combat (alpha " .. alpha() .. ")") end
    G.combat = false
    fire("PLAYER_REGEN_ENABLED")
    step(1)
    log("(Edit Mode opens)")
    G.editMode = true
    EventRegistry:TriggerEvent("EditMode.Enter")
    step(0.3)
    if alpha() < 0.99 then fail("HUD hidden in Edit Mode") end
    if not (H.HUD.mover.__shown and root.__v.MouseEnabled and root.__v.MouseEnabled[1]) then
        fail("HUD cannot be dragged in Edit Mode")
    end
    say("  Edit Mode: shown, highlighted, mouse on: " .. tostring(H.HUD.mover.__shown))
    call("OnDragStart", root.__scripts.OnDragStart, root)
    call("OnDragStop", root.__scripts.OnDragStop, root)
    log("(Edit Mode closes)")
    G.editMode = false
    EventRegistry:TriggerEvent("EditMode.Exit")
    step(1.5)
    if H.HUD.mover.__shown or (root.__v.MouseEnabled and root.__v.MouseEnabled[1]) then
        fail("Edit Mode mover stayed after Edit Mode closed")
    end
    if alpha() > 0.01 then fail("HUD not hidden again after Edit Mode") end
    log("(only in combat off: idle opacity once mana is full)")
    mana(G.maxMana)
    slash("combat")
    step(2)
    say(string.format("  only in combat off, idle: alpha %.2f", alpha()))
    if math.abs(alpha() - 0.35) > 0.02 then fail("idle opacity not used with only-in-combat off") end
    slash("combat")
    slash("pos 120 -200")
    if ThrumDB.x ~= 120 or ThrumDB.y ~= -200 then fail("/thrum pos did not move the HUD") end
    local p = root.__points[1]
    if not (p and p.x == 120 and p.y == -200) then fail("/thrum pos did not reposition the frame") end
    slash("pos 9999 -9999")
    if ThrumDB.x ~= 1000 or ThrumDB.y ~= -600 then fail("/thrum pos not kept within range: " .. ThrumDB.x .. ", " .. ThrumDB.y) end
    slash("pos left")
    slash("reset")
    for _, l in ipairs(LOG) do say(l) end
end

local function commands()
    say("")
    say("--- slash commands ---")
    LOG = {}
    t0 = clock
    slash("")
    slash("test")
    step(16.5)
    slash("unlock")
    local root = ThrumHUD
    if root then
        call("OnDragStart", root.__scripts.OnDragStart, root)
        call("OnDragStop", root.__scripts.OnDragStop, root)
    else
        fail("ThrumHUD frame was not created")
    end
    slash("lock")
    slash("scale 1.3")
    slash("scale 9")
    slash("idle 0")
    slash("idle 0.35")
    slash("fx 0.8")
    slash("fx 1")
    for _, c in ipairs({ "words", "words", "hits", "hits", "prompt", "prompt", "procs", "procs", "totems", "totems",
        "imbue", "imbue", "castbar", "castbar", "fsr", "fsr", "reset" }) do
        slash(c)
    end
    step(1)
    for _, l in ipairs(LOG) do say(l) end
end

--------------------------------------------------------------------------------
-- Snapshots: resolve the layout the addon built and list what would be drawn, so the
-- runner can paint it (tools/test.js --snap out.html).
--------------------------------------------------------------------------------
local LAYER_RANK = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 }

local function scaleOf(o)
    local s, f = 1, o
    while f do
        if f.__scale then s = s * f.__scale end
        f = f.__parent
    end
    return s
end

local function alphaOf(o)
    local a, f = 1, o
    while f do
        if not f.__shown then return nil end
        local v = f.__v.Alpha
        if v and real(v[1]) then a = a * real(v[1]) end
        f = f.__parent
    end
    return a
end

local function anchor(l, b, r, t, point)
    local x = point:find("LEFT") and l or point:find("RIGHT") and r or (l + r) / 2
    local y = point:find("BOTTOM") and b or point:find("TOP") and t or (b + t) / 2
    return x, y
end

local function sizeOf(o, s)
    local sz = o.__v.Size
    local w, h = sz and sz[1] or 0, sz and sz[2] or 0
    if o.__kind == "FontString" and w == 0 then
        local font = o.__v.Font and o.__v.Font[2] or 12
        w, h = #tostring(real(o.__text) or "") * font * 0.5, font
    end
    return w * s, h * s
end

local function rect(o, depth)
    depth = depth or 0
    if o == UIParent or depth > 30 then return 0, 0, 1280, 720 end
    local s = scaleOf(o)
    local pts = o.__points
    local parent = o.__parent or UIParent
    if #pts == 0 then
        local l, b, r, t = rect(parent, depth + 1)
        return (l + r) / 2, (b + t) / 2, (l + r) / 2, (b + t) / 2
    end
    local pos = {}
    for _, p in ipairs(pts) do
        local l, b, r, t = rect(p.rel or parent, depth + 1)
        local x, y = anchor(l, b, r, t, p.relPoint)
        pos[p.point] = { x + p.x * s, y + p.y * s }
    end
    if pos.TOPLEFT and pos.BOTTOMRIGHT then
        return pos.TOPLEFT[1], pos.BOTTOMRIGHT[2], pos.BOTTOMRIGHT[1], pos.TOPLEFT[2]
    end
    local p = pts[1]
    local x, y = pos[p.point][1], pos[p.point][2]
    local w, h = sizeOf(o, s)
    local l = p.point:find("LEFT") and x or p.point:find("RIGHT") and x - w or x - w / 2
    local b = p.point:find("BOTTOM") and y or p.point:find("TOP") and y - h or y - h / 2
    return l, b, l + w, b + h
end

local function json(v)
    local t = type(v)
    if t == "number" then return string.format("%.3f", v) end
    if t == "string" then return '"' .. v:gsub('[\\"]', "\\%0") .. '"' end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return "null" end
    local out = {}
    if #v > 0 or next(v) == nil then
        for i = 1, #v do out[i] = json(v[i]) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    for k, x in pairs(v) do out[#out + 1] = '"' .. k .. '":' .. json(x) end
    return "{" .. table.concat(out, ",") .. "}"
end

local function artName(file)
    if type(file) == "number" then return "icon" end
    if type(file) ~= "string" then return nil end
    if file:find("WHITE8X8") then return "white" end
    return file:match("([^\\]+)$")
end

local function snapshot(label)
    local frames, byParent, items = {}, {}, {}
    for _, o in ipairs(ALL) do
        if (o.__kind == "Frame" or o.__kind == "StatusBar") and o ~= UIParent then
            frames[#frames + 1] = o
        elseif (o.__kind == "Texture" or o.__kind == "FontString") and o.__parent then
            byParent[o.__parent] = byParent[o.__parent] or {}
            table.insert(byParent[o.__parent], o)
        end
    end
    table.sort(frames, function(a, b)
        local la, lb = a:GetFrameLevel(), b:GetFrameLevel()
        if la ~= lb then return la < lb end
        return a.__id < b.__id
    end)
    for _, f in ipairs(frames) do
        local regs = byParent[f] or {}
        local function rank(r) return LAYER_RANK[r.__layer or "ARTWORK"] * 100 + (r.__sub or 0) end
        table.sort(regs, function(a, b)
            if rank(a) ~= rank(b) then return rank(a) < rank(b) end
            return a.__id < b.__id
        end)
        for _, r in ipairs(regs) do
            local a = alphaOf(r)
            if a and a > 0.004 then
                local l, b, rr, t
                local it = {}
                if r.__kind == "Texture" then
                    local tint = r.__v.VertexColor or { 1, 1, 1, 1 }
                    if r.__fill then
                        l, b, rr, t = rect(f)
                        local mm, val = f.__v.MinMaxValues or { 0, 1 }, real((f.__v.Value or { 0 })[1]) or 0
                        local lo, hi = real(mm[1]) or 0, real(mm[2]) or 1
                        local frac = (val - lo) / math.max(0.0001, hi - lo)
                        if f.__timer then frac = durLeft(f.__timer) / math.max(0.0001, f.__timer.t) end
                        frac = math.max(0, math.min(1, frac))
                        rr = l + (rr - l) * frac
                        it.crop = frac
                        tint = f.__v.StatusBarColor or tint
                    else
                        l, b, rr, t = rect(r)
                    end
                    it.kind = "tex"
                    it.art = artName(r.__file)
                    if r.__color then
                        it.color = { r.__color[1], r.__color[2], r.__color[3] }
                        a = a * (r.__color[4] or 1)
                    end
                    it.tint = { tint[1], tint[2], tint[3] }
                    a = a * (tint[4] or 1)
                    it.blend = r.__v.BlendMode and r.__v.BlendMode[1] or "BLEND"
                    it.rot = r.__v.Rotation and r.__v.Rotation[1] or 0
                    if r.__mask then
                        local ml, mb, mr, mt = rect(r.__mask)
                        it.mask = { art = artName(r.__mask.__file), x = ml, y = mb, w = mr - ml, h = mt - mb }
                    end
                else
                    l, b, rr, t = rect(r)
                    local font = r.__v.Font or { "", 12, "" }
                    local c = r.__v.TextColor or { 1, 0.82, 0 }
                    it.kind = "text"
                    it.text = tostring(real(r.__text) or "")
                    it.size = font[2] * scaleOf(r)
                    it.flags = font[3] or ""
                    it.color = { c[1], c[2], c[3] }
                    it.rot = r.__v.Rotation and r.__v.Rotation[1] or 0
                    local p = r.__points[1] and r.__points[1].point or "CENTER"
                    it.align = p:find("LEFT") and "left" or p:find("RIGHT") and "right" or "center"
                end
                it.x, it.y, it.w, it.h, it.a = l, b, rr - l, t - b, a
                if it.kind == "text" and it.text == "" then it = nil end
                if it and (it.kind == "text" or (it.w > 0.05 and it.h > 0.05)) then items[#items + 1] = it end
            end
        end
    end
    return { label = label, items = items }
end

-- Catch reads of globals that do not exist (typos, APIs the mock does not provide).
local UNDEF = {}
setmetatable(_G, { __index = function(_, k)
    if not UNDEF[k] then
        UNDEF[k] = true
        UNDEF[#UNDEF + 1] = tostring(k)
    end
    return nil
end })

boot("SHAMAN")
fight("fight, everything readable", false)
fight("fight, mana, auras, cooldowns and totems secret in combat", true)
grouped()
casts()
regen()
placing()
commands()
options()
local counts = string.format("%d frames, %d textures, %d font strings", COUNT.frames, COUNT.textures, COUNT.fontstrings)

boot("WARRIOR")
say("")
say("--- not a shaman ---")
LOG = {}
t0 = clock
if ThrumHUD then fail("HUD was built for a non-shaman at login") end
slash("test")
step(16.5)
slash("")
for _, l in ipairs(LOG) do say(l) end

local head = {}
if #ERRORS == 0 then
    head[#head + 1] = "PASS: no Lua errors, every check held (" .. counts .. ")"
else
    head[#head + 1] = "FAIL: " .. #ERRORS .. " error(s)"
    for i = 1, math.min(#ERRORS, 16) do head[#head + 1] = ERRORS[i] end
end
if #WARNED > 0 then
    head[#head + 1] = "warnings:"
    for _, w in ipairs(WARNED) do head[#head + 1] = "  " .. w end
end
table.sort(UNDEF)
head[#head + 1] = "globals read but not defined: " .. (#UNDEF > 0 and table.concat(UNDEF, ", ") or "none")
if not VERBOSE and #ERRORS > 0 then OUT = {} end
local result = table.concat(head, "\n") .. "\n" .. table.concat(OUT, "\n")

if SNAP then
    boot("SHAMAN")
    G.target = true
    fire("PLAYER_TARGET_CHANGED")
    slash("test")
    local shots, last = {}, 0
    for _, t in ipairs(SNAP) do
        step(t - last)
        last = t
        shots[#shots + 1] = snapshot(string.format("demo at %.1fs", t))
    end
    if #ERRORS > 0 then result = result .. "\nFAIL: errors while taking snapshots\n" .. table.concat(ERRORS, "\n") end
    result = result .. "\n@@SNAP@@\n" .. json(shots)
end
return result
