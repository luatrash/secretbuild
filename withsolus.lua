do
  local function now_seconds()
    if globals and globals.realtime then
      return globals.realtime() -- локальное время с плавающей точкой
    end
    if client and client.unix_time then
      return client.unix_time() -- фолбэк
    end
    return 0
  end

  local HOLD    = 2.5 
  local FADE    = 1.5
  local t0      = now_seconds()
  local t_fade  = t0 + HOLD
  local t_end   = t_fade + FADE

  local function smoothstep(u)
    if u <= 0 then return 0 end
    if u >= 1 then return 1 end
    return u * u * (3 - 2 * u)
  end

  local function splash_paint()
    local t = now_seconds()
    if t >= t_end then
      if client and client.unset_event_callback then
        client.unset_event_callback("paint", splash_paint)
      end
      return
    end

    local sw, sh = client.screen_size()
    if not sw or not sh or sw <= 0 or sh <= 0 then return end

    local alpha
    if t < t_fade then
      alpha = 1.0
    else
      local u = (t - t_fade) / (FADE > 0 and FADE or 1)
      alpha  = 1.0 - smoothstep(u)
    end

    local a_bg  = math.floor(210 * alpha + 0.5)
    local a_txt = math.floor(255 * alpha + 0.5)

    -- Затемнение всего экрана
    renderer.rectangle(0, 0, sw, sh, 8, 8, 10, a_bg)

    -- Центральный текст (без подложки за текстом)
    local text  = "Wind Renewed // Starfall Community"
    local flags = "+bdc" -- большой, жирный, центр, high-DPI
    local _, th = renderer.measure_text(flags, text)
    local cx = math.floor(sw * 0.5)
    local cy = math.floor(sh * 0.5 - (th or 0) * 0.5)

    renderer.text(cx, cy, 230, 230, 230, a_txt, flags, 0, text)
  end

  client.set_event_callback("paint", splash_paint)
end


local ffi = require("ffi")
local pui = require "gamesense/pui"
local http = require "gamesense/http"
local adata = require "gamesense/antiaim_funcs"
local vector = require "vector"
local msgpack = require "gamesense/msgpack"
local weapondata = require "gamesense/csgo_weapons"

local defer, error, getfenv, setfenv, getmetatable, setmetatable,
ipairs, pairs, next, printf, rawequal, rawset, rawlen, readfile, writefile, require, select,
tonumber, tostring, toticks, totime, type, unpack, pcall, xpcall =
defer, error, getfenv, setfenv, getmetatable, setmetatable,
ipairs, pairs, next, printf, rawequal, rawset, rawlen, readfile, writefile, require, select,
tonumber, tostring, toticks, totime, type, unpack, pcall, xpcall

local C = function (t)
    local c = {}
    if type(t) ~= "table" then return t end
    for k, v in next, t do c[k] = v end
    return c
end

local table, math, string = C(table), C(math), C(string)
local ui, client, database, entity, ffi, globals, panorama, renderer
= C(ui), C(client), C(database), C(entity), C(require "ffi"), C(globals), C(panorama), C(renderer)

table.clear = require "table.clear"

math.round = function (v) return math.floor(v + 0.5) end

math.clamp = function (x, a, b)
    if a > x then return a elseif b < x then return b else return x end
end

math.lerp = function (a, b, w) return a + (b - a) * w end

string.limit = function (s, l, c)
    local r, i = {}, 1
    for w in string.gmatch(s, ".[\128-\191]*") do
        i, r[i] = i + 1, w
        if i > l then
            if c then r[i] = c == true and "..." or c end
            break
        end
    end
    return table.concat(r)
end

local refs = {
    aa = {
        enabled = pui.reference("AA", "anti-aimbot angles", "enabled"),
        pitch = {pui.reference("AA", "anti-aimbot angles", "pitch")},
        yaw_base = {pui.reference("AA", "anti-aimbot angles", "Yaw base")},
        yaw = {pui.reference("AA", "anti-aimbot angles", "Yaw")},
        yaw_jitter = {pui.reference("AA", "anti-aimbot angles", "Yaw Jitter")},
        body_yaw = {pui.reference("AA", "anti-aimbot angles", "Body yaw")},
        body_free = {pui.reference("AA", "anti-aimbot angles", "Freestanding body yaw")},
        freestand = {pui.reference("AA", "anti-aimbot angles", "Freestanding")},
        roll = {pui.reference("AA", "anti-aimbot angles", "Roll")},
        edge_yaw = {pui.reference("AA", "anti-aimbot angles", "Edge yaw")},
        fake_peek = {pui.reference("AA", "other", "Fake peek")},
        slow_motion = {pui.reference("AA", "other", "Slow motion")},
        leg_movement = {pui.reference("AA", "other", "Leg movement")},
    },
    fl = {
        enabled = {pui.reference("AA", "fake lag", "enabled")},
        amount = {pui.reference("AA", "fake lag", "amount")},
        variance = {pui.reference("AA", "fake lag", "variance")},
        limit = {pui.reference("AA", "fake lag", "limit")},
    },
    rage = {
        aimbot = {
            damage = pui.reference("RAGE", "Aimbot", "Minimum damage"),
            damage_ovr = { pui.reference("RAGE", "Aimbot", "Minimum damage override") },
            double_tap = { pui.reference("RAGE", "Aimbot", "Double tap") },
            onshot = pui.reference("AA", "Other", "On shot anti-aim"),
        },
        other = {
            peek = pui.reference("RAGE", "Other", "Quick peek assist"),
            duck = pui.reference("RAGE", "Other", "Duck peek assist"),
        }
    },
    misc = {
        clantag = pui.reference("MISC", "Miscellaneous", "Clan tag spammer"),
        log_damage = pui.reference("MISC", "Miscellaneous", "Log damage dealt"),
        ping_spike = pui.reference("MISC", "Miscellaneous", "Ping spike"),
        settings = {
            dpi = pui.reference("MISC", "Settings", "DPI scale"),
            accent = pui.reference("MISC", "Settings", "Menu color"),
            maxshift = pui.reference("MISC", "Settings", "sv_maxusrcmdprocessticks2")
        }
    }
}

-- #region - Callbacks
local callbacks do
    local event_mt = {
        __call = function (self, bool, fn)
            local action = bool and client.set_event_callback or client.unset_event_callback
            action(self[1], fn)
        end,
        set = function (self, fn) client.set_event_callback(self[1], fn) end,
        unset = function (self, fn) client.unset_event_callback(self[1], fn) end,
        fire = function (self, ...) client.fire_event(self[1], ...) end,
    }
    event_mt.__index = event_mt
    callbacks = setmetatable({}, {
        __index = function (self, key)
            self[key] = setmetatable({key}, event_mt)
            return self[key]
        end,
    })
end

-- #region - Renderer
local DPI, _DPI = 1, {}
local sw, sh = client.screen_size()
local asw, ash = sw, sh
local sc = {x = sw * .5, y = sh * .5}
local asc = {x = asw * .5, y = ash * .5}

-- #region: Сustom colors
local a = function (...) return ... end
local color do
    local helpers = {
        RGBtoHEX = a(function (col, short)
            return string.format(short and "%02X%02X%02X" or "%02X%02X%02X%02X", col.r, col.g, col.b, col.a)
        end),
        HEXtoRGB = a(function (hex)
            hex = string.gsub(hex, "^#", "")
            return tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16), tonumber(string.sub(hex, 7, 8), 16) or 255
        end)
    }
    local create
    local mt = {
        __eq = a(function (a, b)
            return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
        end),
        lerp = a(function (f, t, w)
            return create(f.r + (t.r - f.r) * w, f.g + (t.g - f.g) * w, f.b + (t.b - f.b) * w, f.a + (t.a - f.a) * w)
        end),
        to_hex = helpers.RGBtoHEX,
        alphen = a(function (self, a, r)
            return create(self.r, self.g, self.b, r and a * self.a or a)
        end),
    }
    mt.__index = mt
    create = ffi.metatype(ffi.typeof("struct { uint8_t r; uint8_t g; uint8_t b; uint8_t a; }"), mt)
    color = setmetatable({
        rgb = a(function (r,g,b,a)
            r = math.min(r or 255, 255)
            return create(r, g and math.min(g, 255) or r, b and math.min(b, 255) or r, a and math.min(a, 255) or 255)
        end),
        hex = a(function (hex)
            local r,g,b,a = helpers.HEXtoRGB(hex)
            return create(r,g,b,a)
        end)
    }, {
        __call = a(function (self, r, g, b, a)
            return type(r) == "string" and self.hex(r) or self.rgb(r, g, b, a)
        end),
    })
end

-- #region: Сustom renderer
local render do
    local alpha = 1
    local astack = {}
    local measurements = setmetatable({}, { __mode = "kv" })

    -- #region - dpi
    local dpi_flag = ""
    local dpi_ref = ui.reference("MISC", "Settings", "DPI scale")
    _DPI.scalable = false
    _DPI.callback = function ()
        local old = DPI
        DPI = _DPI.scalable and tonumber(ui.get(dpi_ref):sub(1, -2)) * .01 or 1
        sw, sh = client.screen_size()
        sw, sh = sw / DPI, sh / DPI
        sc.x, sc.y = sw * .5, sh * .5
        dpi_flag = DPI ~= 1 and "d" or ""
        if old ~= DPI then
            callbacks["wind::render_dpi"]:fire(DPI)
            old = DPI
        end
    end
    _DPI.callback()
    ui.set_callback(dpi_ref, _DPI.callback)

    -- #region - blur
    local blurs = setmetatable({}, {__mode = "kv"})
    do
        local function check_screen ()
            if sw == 0 or sh == 0 then
                _DPI.callback()
                asw, ash = client.screen_size()
                sw, sh = render.screen_size()
            else
                callbacks.paint_ui:unset(check_screen)
            end
        end
        callbacks.paint_ui:set(check_screen)
    end
    callbacks.paint:set(function ()
        for i = 1, #blurs do
            local v = blurs[i]
            if v then renderer.blur(v[1], v[2], v[3], v[4]) end
        end
        table.clear(blurs)
    end)
    callbacks.paint_ui:set(function ()
        table.clear(blurs)
    end)

    local F, C, R = math.floor, math.ceil, math.round
    render = setmetatable({
        cheap = false,
        push_alpha = a(function (v)
            local len = #astack
            astack[len+1] = v
            alpha = alpha * astack[len+1] * (astack[len] or 1)
            if len > 255 then error "alpha stack exceeded 255 objects, report to developers" end
        end),
        pop_alpha = a(function ()
            local len = #astack
            astack[len], len = nil, len-1
            alpha = len == 0 and 1 or astack[len] * (astack[len-1] or 1)
        end),
        get_alpha = a(function () return alpha end),
        blur = a(function (x, y, w, h, a, s)
            if not render.cheap and my.valid and (a or 1) * alpha > .25 then
                blurs[#blurs+1] = {F(x * DPI), F(y * DPI), F(w * DPI), F(h * DPI)}
            end
        end),
        gradient = a(function (x, y, w, h, c1, c2, dir)
            renderer.gradient(F(x * DPI), F(y * DPI), F(w * DPI), F(h * DPI), c1.r, c1.g, c1.b, c1.a * alpha, c2.r, c2.g, c2.b, c2.a * alpha, dir or false)
        end),
        line = a(function (xa, ya, xb, yb, c)
            renderer.line(F(xa * DPI), F(ya * DPI), F(xb * DPI), F(yb * DPI), c.r, c.g, c.b, c.a * alpha)
        end),
        rectangle = a(function (x, y, w, h, c, n)
            x, y, w, h, n = F(x * DPI), F(y * DPI), F(w * DPI), F(h * DPI), n and F(n * DPI) or 0
            local r, g, b, a = c.r, c.g, c.b, c.a * alpha
            if n == 0 then
                renderer.rectangle(x, y, w, h, r, g, b, a)
            else
                renderer.circle(x + n, y + n, r, g, b, a, n, 180, 0.25)
                renderer.rectangle(x + n, y, w - n - n, n, r, g, b, a)
                renderer.circle(x + w - n, y + n, r, g, b, a, n, 90, 0.25)
                renderer.rectangle(x, y + n, w, h - n - n, r, g, b, a)
                renderer.circle(x + n, y + h - n, r, g, b, a, n, 270, 0.25)
                renderer.rectangle(x + n, y + h - n, w - n - n, n, r, g, b, a)
                renderer.circle(x + w - n, y + h - n, r, g, b, a, n, 0, 0.25)
            end
        end),
        rect_outline = a(function (x, y, w, h, c, n, t)
            x, y, w, h, n, t = F(x * DPI), F(y * DPI), F(w * DPI), F(h * DPI), n and F(n * DPI) or 0, t and F(t * DPI) or 1
            local r, g, b, a = c.r, c.g, c.b, c.a * alpha
            if n == 0 then
                renderer.rectangle(x, y, w - t, t, r, g, b, a)
                renderer.rectangle(x, y + t, t, h - t, r, g, b, a)
                renderer.rectangle(x + w - t, y, t, h - t, r, g, b, a)
                renderer.rectangle(x + t, y + h - t, w - t, t, r, g, b, a)
            else
                renderer.circle_outline(x + n, y + n, r, g, b, a, n, 180, 0.25, t)
                renderer.rectangle(x + n, y, w - n - n, t, r, g, b, a)
                renderer.circle_outline(x + w - n, y + n, r, g, b, a, n, 270, 0.25, t)
                renderer.rectangle(x, y + n, t, h - n - n, r, g, b, a)
                renderer.circle_outline(x + n, y + h - n, r, g, b, a, n, 90, 0.25, t)
                renderer.rectangle(x + n, y + h - t, w - n - n, t, r, g, b, a)
                renderer.circle_outline(x + w - n, y + h - n, r, g, b, a, n, 0, 0.25, t)
                renderer.rectangle(x + w - t, y + n, t, h - n - n, r, g, b, a)
            end
        end),
        triangle = a(function (x1, y1, x2, y2, x3, y3, c)
            x1, y1, x2, y2, x3, y3 = x1 * DPI, y1 * DPI, x2 * DPI, y2 * DPI, x3 * DPI, y3 * DPI
            renderer.triangle(x1, y1, x2, y2, x3, y3, c.r, c.g, c.b, c.a * alpha)
        end),
        circle = a(function (x, y, c, radius, start, percentage)
            renderer.circle(x * DPI, y * DPI, c.r, c.g, c.b, c.a * alpha, radius * DPI, start or 0, percentage or 1)
        end),
        circle_outline = a(function (x, y, c, radius, start, percentage, thickness)
            renderer.circle(x * DPI, y * DPI, c.r, c.g, c.b, c.a * alpha, radius * DPI, start or 0, percentage or 1, thickness * DPI)
        end),
        screen_size = a(function (raw)
            local w, h = client.screen_size()
            if raw then return w, h else return w / DPI, h / DPI end
        end),
        load_rgba = a(function (c, w, h) return renderer.load_rgba(c, w, h) end),
        load_jpg = a(function (c, w, h) return renderer.load_jpg(c, w, h) end),
        load_png = a(function (c, w, h) return renderer.load_png(c, w, h) end),
        load_svg = a(function (c, w, h) return renderer.load_svg(c, w, h) end),
        texture = a(function (id, x, y, w, h, c, mode)
            if not id then return end
            renderer.texture(id, F(x * DPI), F(y * DPI), F(w * DPI), F(h * DPI), c.r, c.g, c.b, c.a * alpha, mode or "f")
        end),
        text = a(function (x, y, c, flags, width, ...)
            renderer.text(x * DPI, y * DPI, c.r, c.g, c.b, c.a * alpha, (flags or "") .. dpi_flag, width or 0, ...)
        end),
        measure_text = a(function (flags, text)
            if not text or text == "" then return 0, 0 end
            text = text:gsub("\a%x%x%x%x%x%x%x%x", "")
            flags = (flags or "")
            local key = string.format("<%s>%s", flags, text)
            if not measurements[key] or measurements[key][1] == 0 then
                measurements[key] = { renderer.measure_text(flags, text) }
            end
            return measurements[key][1], measurements[key][2]
        end),
    }, {__index = renderer})
end

-- #region: anima
local anima do
    local mt, animators = {}, setmetatable({}, {__mode = "kv"})
    local frametime, g_speed = globals.absoluteframetime(), 1
    anima = {
        pulse = 0,
        easings = {
            pow = {
                function (x, p) return 1 - ((1 - x) ^ (p or 3)) end,
                function (x, p) return x ^ (p or 3) end,
                function (x, p) return x < 0.5 and 4 * math.pow(x, p or 3) or 1 - math.pow(-2 * x + 2, p or 3) * 0.5 end,
            }
        },
        lerp = a(function (a, b, s, t)
            local c = a + (b - a) * frametime * (s or 8) * g_speed
            return math.abs(b - c) < (t or .005) and b or c
        end),
        condition = a(function (id, c, s, e)
            local ctx = id[1] and id or animators[id]
            if not ctx then animators[id] = { c and 1 or 0, c }; ctx = animators[id] end
            s = s or 4
            local cur_s = s
            if type(s) == "table" then cur_s = c and s[1] or s[2] end
            ctx[1] = math.clamp(ctx[1] + ( frametime * math.abs(cur_s) * g_speed * (c and 1 or -1) ), 0, 1)
            return (ctx[1] % 1 == 0 or cur_s < 0) and ctx[1] or
            anima.easings.pow[e and (c and e[1][1] or e[2][1]) or (c and 1 or 3)](ctx[1], e and (c and e[1][2] or e[2][2]) or 3)
        end)
    }
    mt = { __call = anima.condition }
    callbacks.paint_ui:set(function ()
        anima.pulse = math.abs(globals.realtime() * 1 % 2 - 1)
        frametime = globals.absoluteframetime()
    end)
end

-- #region: misc
local mouse = { x = 0, y = 0 } do
    local unlock_cursor = vtable_bind("vguimatsurface.dll", "VGUI_Surface031", 66, "void(__thiscall*)(void*)")
    local lock_cursor = vtable_bind("vguimatsurface.dll", "VGUI_Surface031", 67, "void(__thiscall*)(void*)")
    mouse.lock = function (bool) if bool then lock_cursor() else unlock_cursor() end end
    mouse.in_bounds = function (x, y, w, h) return (mouse.x >= x and mouse.y >= y) and (mouse.x <= (x + w) and mouse.y <= (y + h)) end
    mouse.pressed = function (key) return client.key_state(key or 1) end
    callbacks.pre_render:set(function () mouse.x, mouse.y = ui.mouse_position(); mouse.x, mouse.y = mouse.x / DPI, mouse.y / DPI end)
end

do
    local native_get_client_entity = vtable_bind("client.dll", "VClientEntityList003", 3, "void*(__thiscall*)(void*, int)")
    entity.get_simtime = function (ent)
        local pointer = native_get_client_entity(ent)
        if pointer then return entity.get_prop(ent, "m_flSimulationTime"), ffi.cast("float*", ffi.cast("uintptr_t", pointer) + 0x26C)[0] else return 0 end
    end
end

local colors = {
    accent	= color.hex("ffffff"),
    white	= color.rgb(255),
    text	= color.rgb(230),
    panel = {
        l1 = color.rgb(5, 6, 8, 96),
        g1 = color.rgb(5, 6, 8, 140),
        l2 = color.rgb(23, 26, 28, 96),
    }
}

local players = {}

my = {
    entity = entity.get_local_player(),
    origin = vector(),
    valid = false,
    threat = client.current_threat(),
    velocity = 0,
    exploit = {
        active = nil,
        defensive = false,
        lagpeek = false,
        shifted = false,
        ready = false,
        diff = 0,
    },
    side = 0,
} do
    local tickbase_max = 0
    local last_commandnumber
    callbacks.predict_command:set(function (cmd)
        if not my.valid or last_commandnumber ~= cmd.command_number then return end
        local tickbase = entity.get_prop(my.entity, "m_nTickBase") or 0
        if tickbase_max ~= nil then
            my.exploit.diff = tickbase - tickbase_max
            my.exploit.defensive = my.exploit.diff < -3
            if math.abs(tickbase - tickbase_max) > 64 then tickbase_max = 0 end
        end
        tickbase_max = math.max(tickbase, tickbase_max or 0)
    end)
    callbacks.finish_command:set(function (cmd)
        if my.valid then last_commandnumber = cmd.command_number end
    end)
    callbacks.run_command:set(function (cmd)
        my.entity = entity.get_local_player()
        my.valid = (my.entity and entity.is_alive(my.entity)) and true or false
        my.threat = my.valid and client.current_threat() or nil
        my.weapon = my.valid and entity.get_player_weapon(my.entity) or nil
        my.in_game = globals.mapname() ~= nil
        players = entity.get_players()
        if my.valid then
            local velocity = vector(entity.get_prop(my.entity, "m_vecVelocity"))
            my.velocity = velocity:length2d()
            my.origin = vector(entity.get_prop(my.entity, "m_vecOrigin"))
        end
    end)
    callbacks.pre_render:set(function ()
        my.valid = my.valid and globals.mapname() ~= nil
    end)
    callbacks.net_update_end:set(function ()
        my.entity = entity.get_local_player()
        my.valid = (my.entity and entity.is_alive(my.entity)) and true or false
        my.game_rules = entity.get_game_rules()
        if my.valid then
            local st_cur, st_old = entity.get_simtime(my.entity)
            my.exploit.lagpeek = st_cur < st_old
        end
    end)
    callbacks.setup_command:set(function (cmd)
        my.entity = entity.get_local_player()
        my.valid = (my.entity and entity.is_alive(my.entity)) and true or false
        my.threat = my.valid and client.current_threat() or nil
        my.weapon = my.valid and entity.get_player_weapon(my.entity) or nil
        players = entity.get_players()
        if my.valid then
            my.exploit.active =
            (refs.rage.aimbot.double_tap[1].value and refs.rage.aimbot.double_tap[1].hotkey:get()) and 0 or
            (refs.rage.aimbot.onshot.value and refs.rage.aimbot.onshot.hotkey:get()) and 1 or nil
            if refs.rage.other.duck:get() then my.exploit.active = nil end
            my.exploit.shifted = my.exploit.diff <= 0 or adata.get_double_tap()
            local flags = entity.get_prop(my.entity, "m_fFlags")
            my.using, my.in_score = cmd.in_use == 1, cmd.in_score == 1
            my.jumping = not my.on_ground or (cmd.in_jump == 1)
            my.walking = my.velocity > 5 and (cmd.in_speed == 1)
            my.on_ground = bit.band(flags, bit.lshift(1, 0)) == 1
            my.crouching = cmd.in_duck == 1
            my.side = (cmd.in_moveright == 1) and -1 or (cmd.in_moveleft == 1) and 1 or 0
        end
    end)
end

local function steam_name()
    local me = entity.get_local_player()
    if not me then return "krytoi chelik" end
    local name = entity.get_player_name(me)
    if not name or name == "" or name == "unknown" then return "krytoi chelik" end
    return name
end

pui.accent = "6495EDFF"
pui.macros.a = "\v"
pui.macros.gray = "\a909090FF"
pui.macros.lgray = "\aB0B0B0FF"
pui.macros.red = "\aFF0000FF"
pui.macros.dred = "\a800000FF"
pui.macros.d = "\a808080FF•\r  "

local gaa = pui.group("AA", "anti-aimbot angles")
local gfl = pui.group("AA", "Fake lag")
local goh = pui.group("AA", "Other")

local wind_version = "0.0.1"

local textures = {}

local menu = {
    x = 0, y = 0, w = 0, h = 0,
    feature = function (main, settings)
        main = main.__type == "pui::element" and {main} or main
        local feature, g_depend = settings(main[1])
        for k, v in pairs(feature) do
            v:depend({main[1], g_depend})
        end
        feature[main.key or "on"] = main[1]
        return feature
    end,
}
callbacks.paint_ui:set(function ()
    menu.x, menu.y = ui.menu_position()
    menu.w, menu.h = ui.menu_size()
end)

menu.name = gaa:label("\f<a>Wind Renewed\r ~ Source")
menu.tab = gaa:combobox("\n wind-tab-main", {
    " Home",
    " Ragebot",
    " Anti-Aims",
    " Visuals",
    " Miscellaneous"
})

menu.drag = {}

local function gui_show(visible)
    pui.traverse(refs.aa, function(ac)
        ac:set_visible(visible)
    end)
    pui.traverse(refs.fl, function(fl)
        fl:set_visible(visible)
    end)
end

local function paint_tab(tab, subtabs, icons)
    local selected = tab:get()
    for i, subtab in ipairs(subtabs) do
        if selected == subtab then
            return "\f<a>" .. icons[i] .. "\f<gray>  •  " .. subtab:gsub(".* ", "")
        end
    end
    return "\f<a>" .. icons[1] .. "\f<gray>  •  " .. subtabs[1]:gsub(".* ", "")
end

local function render_tab_indicator()
    if not menu.visuals.indicator.enable:get() then return end
    local selected_tab = menu.tab:get()
    local tab_names = {" Home", " Ragebot", " Anti-Aims", " Visuals", " Miscellaneous"}
    local r, g, b, a = menu.visuals.color.accent:get()
    
    local base_x = 50
    local base_y = 30
    local tab_width = 100
    local line_height = 2
    
    for i, tab_name in ipairs(tab_names) do
        if tab_name == selected_tab then
            local x = base_x + (i - 1) * tab_width
            renderer.rectangle(x, base_y, tab_width - 10, line_height, r, g, b, a)
        end
    end
end

menu.home = {
    tab_1 = gfl:label("\f<a>\f<gray>  •  Welcome"),
    subtab = gfl:combobox("\nwind-home-subtab", {" Welcome", " Updates"}),
    space = gfl:label("\n "),
    info = {
        welcome = gfl:label("\v\r Welcome back, \v" .. steam_name() .. "!"),
        build = gfl:label("\v\r Your build is \v" .. wind_version),
        textion = gfl:label("Feel the wind. That's \vWind Renewed"),
    },
    updates = {
        logs_button = gfl:button(" View Update Logs", function()
            client.log("[upd. log] v0.0.1 — TabManager, watermark, positions, third person, autobuy (no cost-based)")
            client.log("[upd. log] v0.0.0 — Project initialized")
        end),
    }
}

menu.aa = {
    tab_1 = gfl:label("\f<a>\f<gray>  •  General"),
    subtab = gfl:combobox("\nwind-aa-subtab", {" General", " Advanced"}),
    space = gfl:label("\n "),
    general = {
        label = gaa:label("\v\r Anti-Aims Settings (Coming Soon)"),
    },
    advanced = {
        label = gaa:label("\v\r Advanced Anti-Aims (Coming Soon)"),
    }
}


menu.visuals = {
    tab_1 = gfl:label("\f<a>\f<gray>  •  Visuals"),
    subtab = gfl:combobox("\nwind-vis-subtab", {" Main", " Alternative"}),
    space = gfl:label("\n "),
    color = {
        accent = gaa:color_picker("\nwind-accent-color", colors.accent.r, colors.accent.g, colors.accent.b, 255, "Menu Accent Color"),
    },
    indicator = {
        enable = gaa:checkbox("\nwind-indicator-enable", false, "Show Tab Indicator"),
    },
    watermark = {
        enable = gaa:checkbox("\v\r Enable Texted Watermark"),
        color_start = gaa:color_picker("\nwind-wm-start", 255, 255, 255, 255, "Gradient Start"),
        color_end = gaa:color_picker("\nwind-wm-end", 160, 160, 160, 255, "Gradient End"),
        position = gaa:combobox("\nwind-wm-pos", {"Left center", "Right center", "Bottom center"}),
    },
    soluswatermark = {
        enable = gaa:checkbox("\v\r Enable Watermark"),
    },
    damage = {
        enable = gaa:checkbox("\v\r Damage Indicator"),
    },
    keylist = {
        enable = gaa:checkbox("\v\r Keylist"),
    },
    speclist = {
        enable = gaa:checkbox("\v\r Speclist"),
    },
    slowdown = {
        enable = gaa:checkbox("\v\r Slowdown Warning"), 
    },
    potato = {
        enable = gaa:checkbox("\v\rPerformance Mode"),
    },
    thirdperson = {
        enable = gaa:checkbox("\v\r Enable Thirdperson"),
        distance = gaa:slider("\nwind-tp-dist", 30, 200, 125, true, "Distance"),
    }
}

menu.ragebot = {
    tab_1 = gfl:label("\f<a>\f<gray>  •  General Rage"),
    subtab = gfl:combobox("\nwind-ragebot-subtab", {" General Rage"}),
    space = gfl:label("\n "),
    general = {
        label = gaa:label("\v\r Ragebot Settings (Coming Soon)"),
    }
}

menu.misc = {
    tab_1 = gfl:label("\f<a>\f<gray>  •  Autobuy"),
    subtab = gfl:combobox("\nwind-misc-subtab", {" Autobuy", " Other"}),
    space = gfl:label("\n "),
    autobuy = {
        enable = gaa:checkbox("\v\r Autobuy"),
        primary = gaa:combobox("\nwind-ab-primary", {
            "-", "AWP", "SCAR20/G3SG1", "Scout", "M4/AK47", "Famas/Galil", "Aug/SG553",
            "M249/Negev", "Mag7/SawedOff", "Nova", "XM1014", "MP9/Mac10", "UMP45", "PPBizon", "MP7"
        }),
        secondary = gaa:combobox("\nwind-ab-secondary", {"-", "CZ75/Tec9/FiveSeven", "P250", "Deagle/Revolver", "Dualies"}),
        grenades = gaa:multiselect("\nwind-ab-grenades", {"HE Grenade", "Molotov", "Smoke"}),
        utilities = gaa:multiselect("\nwind-ab-utilities", {"Armor", "Helmet", "Zeus", "Defuser"}),
    },
    other = {
        label = gaa:label("\v\r Other Misc (Coming Soon)"),
    }
}

local function update_accent_color()
    local r, g, b, a = menu.visuals.color.accent:get()
    pui.accent = string.format("%02X%02X%02X%02X", r, g, b, a)
end
menu.visuals.color.accent:set_callback(update_accent_color)


local function update_visual_visibility()
    local wm_enable = menu.visuals.watermark.enable:get()
    local solus_wm_enable = menu.visuals.soluswatermark.enable:get()
    local tp_enable = menu.visuals.thirdperson.enable:get()
    local vis_sub = menu.visuals.subtab:get()
    local is_main = vis_sub == " Main"

    menu.visuals.watermark.color_start:set_visible(is_main and wm_enable)
    menu.visuals.watermark.color_end:set_visible(is_main and wm_enable)
    menu.visuals.watermark.position:set_visible(is_main and wm_enable)

    menu.visuals.thirdperson.distance:set_visible(is_main and tp_enable)

    menu.visuals.color.accent:set_visible(is_main)
    menu.visuals.indicator.enable:set_visible(is_main)
    menu.visuals.watermark.enable:set_visible(is_main)
    menu.visuals.soluswatermark.enable:set_visible(is_main)
    menu.visuals.thirdperson.enable:set_visible(is_main)
    menu.visuals.damage.enable:set_visible(is_main)
    menu.visuals.keylist.enable:set_visible(is_main)
    menu.visuals.speclist.enable:set_visible(is_main)
    menu.visuals.slowdown.enable:set_visible(is_main)
    menu.visuals.potato.enable:set_visible(is_main)
end

menu.visuals.watermark.enable:set_callback(update_visual_visibility)
menu.visuals.soluswatermark.enable:set_callback(update_visual_visibility)
menu.visuals.thirdperson.enable:set_callback(update_visual_visibility)
menu.visuals.subtab:set_callback(update_visual_visibility)

local function update_visibility()
    local main_tab = menu.tab:get()

    gui_show(false)

    for _, tab_group in pairs(menu) do
        if type(tab_group) == "table" and tab_group.space then
            tab_group.space:set_visible(false)
            tab_group.tab_1:set_visible(false)
            if tab_group.subtab then
                tab_group.subtab:set_visible(false)
            end
            for _, sub in pairs(tab_group) do
                if type(sub) == "table" then
                    for _, elem in pairs(sub) do
                        if type(elem) == "table" and elem.set_visible then
                            elem:set_visible(false)
                        end
                    end
                end
            end
        end
    end

    if main_tab == " Home" then
        menu.home.tab_1:set(paint_tab(menu.home.subtab, {" Welcome", " Updates"}, {"", ""}))
        menu.home.space:set_visible(true)
        menu.home.tab_1:set_visible(true)
        menu.home.subtab:set_visible(true)
        local home_sub = menu.home.subtab:get()
        if home_sub == " Welcome" then
            for _, elem in pairs(menu.home.info) do
                if type(elem) == "table" and elem.set_visible then
                    elem:set_visible(true)
                end
            end
        elseif home_sub == " Updates" then
            for _, elem in pairs(menu.home.updates) do
                if type(elem) == "table" and elem.set_visible then
                    elem:set_visible(true)
                end
            end
        end
    elseif main_tab == " Ragebot" then
        menu.ragebot.tab_1:set(paint_tab(menu.ragebot.subtab, {" General Rage"}, {""}))
        menu.ragebot.space:set_visible(true)
        menu.ragebot.tab_1:set_visible(true)
        menu.ragebot.subtab:set_visible(true)
        local ragebot_sub = menu.ragebot.subtab:get()
        if ragebot_sub == " General Rage" then
            for _, elem in pairs(menu.ragebot.general) do
                if type(elem) == "table" and elem.set_visible then
                    elem:set_visible(true)
                end
            end
        end
    elseif main_tab == " Anti-Aims" then
        menu.aa.tab_1:set(paint_tab(menu.aa.subtab, {" General", " Advanced"}, {"", ""}))
        menu.aa.space:set_visible(true)
        menu.aa.tab_1:set_visible(true)
        menu.aa.subtab:set_visible(true)
        local aa_sub = menu.aa.subtab:get()
        if aa_sub == " General" then
            for _, elem in pairs(menu.aa.general) do
                if type(elem) == "table" and elem.set_visible then
                    elem:set_visible(true)
                end
            end
        elseif aa_sub == " Advanced" then
            for _, elem in pairs(menu.aa.advanced) do
                if type(elem) == "table" and elem.set_visible then
                    elem:set_visible(true)
                end
            end
        end
    elseif main_tab == " Visuals" then
        menu.visuals.tab_1:set(paint_tab(menu.visuals.subtab, {" Main", " Alternative"}, {"", ""}))
        menu.visuals.space:set_visible(true)
        menu.visuals.tab_1:set_visible(true)
        menu.visuals.subtab:set_visible(true)
        local vis_sub = menu.visuals.subtab:get()
        if vis_sub == " Main" then
            menu.visuals.color.accent:set_visible(true)
            menu.visuals.indicator.enable:set_visible(true)
            menu.visuals.watermark.enable:set_visible(true)
            menu.visuals.soluswatermark.enable:set_visible(true)
            menu.visuals.thirdperson.enable:set_visible(true)
            menu.visuals.damage.enable:set_visible(true)
            menu.visuals.keylist.enable:set_visible(true)
            menu.visuals.speclist.enable:set_visible(true)
            menu.visuals.slowdown.enable:set_visible(true)
            menu.visuals.potato.enable:set_visible(true)
            update_visual_visibility()
        elseif vis_sub == " Alternative" then

        end
    elseif main_tab == " Miscellaneous" then
        menu.misc.tab_1:set(paint_tab(menu.misc.subtab, {" Autobuy", " Other"}, {"", ""}))
        menu.misc.space:set_visible(true)
        menu.misc.tab_1:set_visible(true)
        menu.misc.subtab:set_visible(true)
        local misc_sub = menu.misc.subtab:get()
        if misc_sub == " Autobuy" then
            for _, elem in pairs(menu.misc.autobuy) do
                if type(elem) == "table" and elem.set_visible then
                    elem:set_visible(true)
                end
            end
        elseif misc_sub == " Other" then
            for _, elem in pairs(menu.misc.other) do
                if type(elem) == "table" and elem.set_visible then
                    elem:set_visible(true)
                end
            end
        end
    end
end

menu.tab:set_callback(update_visibility)
for _, tab_group in pairs(menu) do
    if type(tab_group) == "table" and tab_group.subtab then
        tab_group.subtab:set_callback(update_visibility)
    end
end
update_visibility()

-- #region :: Screen
textures = {
    corner_v = render.load_svg('<svg width="5.87" height="4" viewBox="0 0 6 4"><path fill="#fff" d="M2 0H0c0 2 2 4 4 4h2C4 4 2 2 2 0Z"/></svg>', 12, 8),
    logo_l = render.load_png("\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x1A\x00\x00\x00\x0F\x08\x06\x00\x00\x00\xFA\x51\xDF\xE6\x00\x00\x00\x04\x73\x42\x49\x54\x08\x08\x08\x08\x7C\x08\x64\x88\x00\x00\x02\x69\x49\x44\x41\x54\x38\x4F\xBD\x54\x3D\x88\x92\x71\x18\xFF\xBF\x57\x04\xC7\x09\xBA\x58\xE1\xE2\x3B\x35\xE5\x17\x58\x4E\x0D\xA1\x34\x54\xD0\x20\x09\x22\x4D\x3A\x98\xA3\xC3\xA9\xE0\x39\x34\x08\x1A\x77\x43\x21\x2E\x0A\x92\x25\x74\x20\x74\x58\x8B\xF8\xD2\xE2\x90\x60\x29\x4E\x77\x3A\xA4\x83\x11\xB6\xA8\xDC\x71\x9B\xF6\x7B\x5E\xFF\x7F\xBB\x24\x32\xE2\xB8\x07\x1E\x7C\xBE\xDE\xDF\xEF\xF9\x78\x5F\x25\x76\x41\x22\x5D\x10\x0F\x53\x89\x46\xA3\xD1\x7B\xBD\x5E\xFF\x80\xEC\x7A\xBD\x7E\x74\x07\x02\xF3\xC7\x79\x36\x41\x44\x5B\x7E\xBF\xFF\xD8\xEB\xF5\x32\xA7\xD3\xC9\x02\x81\x00\xCB\xE7\xF3\xE7\x31\xA9\x6F\x3C\x1E\xBF\x6E\x36\x9B\xCC\xE5\x72\x99\x08\xD0\x01\xFD\xD4\xEF\xF7\x99\xD1\x68\x64\x92\x24\xED\xC3\x7F\x46\x83\xAE\x4C\xA5\x87\x7F\x15\x7A\x02\xED\xAF\x4C\x7B\x13\xFE\x9C\xC7\x29\x2F\x0F\x87\xC3\x23\x83\xC1\x70\x25\x9D\x4E\xB3\x48\x24\x22\x11\x11\x01\xEC\xCE\xE7\xF3\x27\x83\xC1\x80\xE9\x74\x3A\xA6\xD5\x6A\x55\x1C\xF8\x4A\xB9\x5C\x3E\x0D\x87\xC3\x0F\x05\x30\x1A\x61\xAD\x56\x8B\x59\xAD\x56\x16\x8F\xC7\xBF\x44\xA3\x51\x8B\x46\xA3\xB9\x24\xF2\x9D\x4E\xE7\x9B\xD9\x6C\x36\x9C\x6D\xA4\xDD\x6E\x2F\x6E\x94\xCD\x66\xBF\x07\x83\xC1\x6B\x64\x53\x07\xDD\x6E\x97\xE5\x72\x39\xBA\xD7\x69\xA1\x50\xD8\xA4\x38\xF9\x8A\xA2\xD0\x1A\x5A\xD3\xE9\xD4\x32\x9B\xCD\x36\x6A\xB5\xDA\x89\xDB\xED\xDE\x2A\x95\x4A\xCC\xE7\xF3\x2D\xB1\x71\x0A\xB5\x9E\x08\x6C\x36\x9B\x1A\x27\x22\x19\x0F\x7C\xA5\xFB\x70\xA0\x65\xC7\xE8\xFE\x10\xF9\x0E\xF2\x1E\x71\x3F\xBB\xDD\x4E\x4D\x5D\x17\xB5\xB8\xC3\x72\x03\x93\xC9\x84\x36\xD2\x46\xBD\x95\xEA\xF9\xDA\xB6\x13\x89\x84\x9B\x88\x9C\xB8\x4F\x8D\xDF\x87\x25\x93\x49\x25\x16\x8B\x39\x39\xD0\x2B\xE4\xCB\x00\x3B\x20\x40\x59\x96\x99\x00\x6E\x34\x1A\xCC\xE1\x70\x30\x31\x0D\xC0\xD5\x97\x29\x95\x4A\x55\xD1\xC8\x3D\x9A\x82\xCE\xD0\xEB\xF5\xA6\xC5\x62\xF1\x50\xCA\x64\x32\xFB\xA1\x50\xE8\x31\x1F\xF3\x25\xF2\x9B\xB8\x57\x40\xEC\x61\x67\x67\xE7\xB3\xC7\xE3\xB1\x98\x4C\xA6\xCB\x14\xA3\xAE\xE9\x86\x98\xF6\x18\x0D\x6A\xA8\x41\x21\xBC\xB9\x32\x48\xDD\x44\x4A\x42\xB8\xD5\x6A\x55\x5D\xDD\x5B\xA8\x87\x17\x3F\xC2\xEF\x2D\x68\x5C\x3C\x8C\x7B\xCC\x2A\x95\xCA\x06\xDD\x40\xEC\x9E\x03\x7E\x44\xCD\xDD\x25\xCB\x2F\xE3\x29\xCC\xEC\x4A\xFC\x0D\x11\xBD\x38\x13\xDC\x83\x4D\x1F\x6A\x14\x4A\xAD\x1A\x30\xDD\xA2\x35\x2E\xE2\x36\x70\x6F\x43\x6F\x40\xE9\xF3\x10\x72\x00\x43\xE1\x31\xF1\x76\x34\xE0\xAB\x44\x7F\x93\x0F\x48\xDE\xFF\x43\xC1\x36\x62\xCF\xD7\x3C\xFB\x5B\x7A\x1D\x11\x4D\x43\x80\x8B\x77\x94\xB1\x16\x74\x17\xFA\x0E\x4A\x1F\xE6\x3F\xCB\x3A\x22\x01\x24\x73\xE0\xFF\xFE\xFF\xFB\x09\x1C\xFB\x05\x79\x31\x12\xE3\x6C\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82", 26, 15),
    logo_r = render.load_png("\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x18\x00\x00\x00\x0F\x08\x06\x00\x00\x00\xFE\xA4\x0F\xDB\x00\x00\x00\x04\x73\x42\x49\x54\x08\x08\x08\x08\x7C\x08\x64\x88\x00\x00\x02\x08\x49\x44\x41\x54\x38\x4F\xD5\x53\x3D\x68\x5A\x51\x14\x3E\xCF\x60\x97\x24\x28\x11\x87\xB8\xF8\x08\xB5\x60\x92\x16\x25\x85\xBA\x89\x3F\x25\x63\xA1\xA3\xC6\x80\xE8\x50\x02\x5D\x32\xE8\x54\x34\xA3\x42\x3B\xB4\x0E\x19\xD4\x4D\x09\x41\x68\x93\xA9\x50\x95\x62\x07\xC9\x20\x15\x92\x41\x9C\x74\x90\x52\x84\x60\x0B\xA5\x58\x68\x5F\xBF\x73\x73\x1F\x3C\x29\xA4\x20\x64\xC8\x85\x8F\x73\xEE\x79\xE7\x9C\xEF\xBB\x1F\x3C\x85\x6E\xF8\x28\x37\xBC\x9F\xE6\x21\x58\x9C\x4E\xA7\x63\x93\xC9\xF4\xC7\x6C\x36\x2F\xFD\x4F\xE0\x3C\x04\xAF\x35\x4D\x7B\x3E\x1C\x0E\x49\x55\xD5\x27\x20\x38\xBD\x8E\xC4\x48\xB0\x88\x46\x15\xF8\x01\x0C\x0C\x43\x9B\xC8\x35\x79\xE7\xFA\x27\xC0\x2B\xEF\x3B\x88\x15\x99\xDB\x11\x79\x87\x71\x56\x58\xF4\xB4\xDD\x6E\x1F\xF8\x7C\x3E\x5E\x24\x4E\xAD\x56\xEB\x04\x02\x81\x7B\x36\x9B\x6D\xD9\xA8\x6E\x3C\x1E\xFF\xB6\xDB\xED\x0B\x5C\x93\x2F\x08\x23\xFD\x3A\x1A\x8D\x3A\x0E\x87\xE3\x0E\xD7\xBB\xDD\x2E\x79\x3C\x1E\xAA\x56\xAB\x14\x8D\x46\x15\xA5\xDF\xEF\x7F\x77\xB9\x5C\xCB\xF9\x7C\x9E\x90\x53\xB1\x58\x14\x4D\x5E\xAF\x97\x26\x93\x09\x59\x2C\x16\x52\x94\xAB\x87\x26\x12\x09\x0A\x06\x83\x14\x89\x44\x88\xFB\xD3\xE9\xF4\x16\x7A\x3A\xDC\x93\x4C\x26\xA9\x54\x2A\xD1\x60\x30\x20\xAB\xD5\xCA\x78\xCB\xE2\x15\xF8\xA9\x3F\x5F\x2C\xD1\x97\xF3\x32\x26\x93\x4A\x3E\x4B\x5B\xBE\x60\xE1\x2A\xF7\x61\x41\xAB\x52\xA9\xD8\x40\xB6\xD1\x68\x34\x28\x1C\x0E\x1F\x97\xCB\xE5\x87\xF1\x78\x7C\x4D\xDE\x85\x7D\x82\x40\x5F\x6A\xB0\xE3\x55\xBD\x5E\xDF\x0F\x85\x42\xBA\xB2\xFB\xF8\x76\xD1\x6C\x36\xDF\xC3\xBA\xED\x56\xAB\xF5\xCB\xEF\xF7\x1F\xE5\x72\xB9\xDD\x54\x2A\xA5\x8B\x78\x06\xF2\x43\xC3\x8B\x7D\x98\x39\x53\xA0\x42\xE3\x27\x1B\x4F\xA1\x50\xB8\x8C\xC5\x62\x2B\x52\xE9\x39\xE2\x03\xCE\x33\x99\x4C\x3B\x9B\xCD\xF2\xA0\x38\x6C\x1D\x5B\xE2\x74\x3A\xC5\x9D\x95\xB3\x28\x3E\xBD\x5E\xEF\xA7\xDB\xED\x5E\x67\x73\x67\x2C\x92\xB3\x1F\x10\x1F\x03\xDF\x80\x37\xC0\x0B\x59\x7F\x89\xB8\x6F\x10\xD3\x41\xBE\x35\xA3\x6E\xF6\xB2\xC3\x04\x8F\x80\xA8\xAC\xF3\xC2\x8F\xC0\x5D\x60\x43\xD6\x4E\x58\x9C\xCC\x55\xC4\x04\x60\x01\xCE\x80\x77\xC0\x1E\xC0\x16\x0E\x59\x38\xB0\x0D\x4C\x00\x31\x37\xCF\x8F\x76\x8D\xE0\x7F\x3F\xDD\x7E\x82\xBF\x29\x2E\xBB\x8B\x1E\xD2\x13\xD3\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82", 24, 15),
}

render.logo = function (x, y)
    render.texture(textures.logo_l, x, y, 26, 15, colors.accent)
    render.texture(textures.logo_r, x + 26, y, 24, 15, colors.text)
end

render.edge_v = function (x, y, length, col)
    col = col or colors.accent
    render.texture(textures.corner_v, x, y + 4, 6, -4, col, "f")
    render.rectangle(x, y + 4, 2, length - 8, col)
    render.texture(textures.corner_v, x, y + length - 4, 6, 4, col, "f")
end

render.rounded_side_v = function (x, y, w, h, c, n)
    x, y, w, h, n = x * DPI, y * DPI, w * DPI, h * DPI, (n or 0) * DPI
    local r, g, b, a = c.r, c.g, c.b, c.a * render.get_alpha()
    renderer.circle(x + n, y + n, r, g, b, a, n, 180, 0.25)
    renderer.rectangle(x + n, y, w - n, n, r, g, b, a)
    renderer.rectangle(x, y + n, w, h - n - n, r, g, b, a)
    renderer.circle(x + n, y + h - n, r, g, b, a, n, 270, 0.25)
    renderer.rectangle(x + n, y + h - n, w - n, n, r, g, b, a)
end

-- #region - Widgets
local drag do
    local current
    local in_bounds = a(function (x, y, xa, ya, xb, yb)
        return (x >= xa and y >= ya) and (x <= xb and y <= yb)
    end)
    local progress = { menu = {0}, bg = {0}, }
    callbacks.paint_ui:set(function ()
        local p1 = anima.condition(progress.bg, current ~= nil, 2)
        if p1 == 0 then return end
        render.push_alpha(p1)
        render.rectangle(0, 0, sw, sh, colors.panel.l1)
        render.pop_alpha()
    end)
    local process = a(function (self)
        local ctx = self.__drag
        if ctx.locked or not pui.menu_open then return end
        local held = mouse.pressed()
        local hovered = mouse.in_bounds(self.x, self.y, self.w, self.h) and not mouse.in_bounds(menu.x, menu.y, menu.w, menu.h)
        if held and ctx.ready == nil then
            ctx.ready = hovered
            ctx.ix, ctx.iy = self.x, self.y
            ctx.px, ctx.py = self.x - mouse.x, self.y - mouse.y
        end
        if held and ctx.ready then
            if current == nil and ctx.on_held then ctx.on_held(self, ctx) end
            current = (ctx.ready and current == nil) and self.id or current
            ctx.active = current == self.id
        elseif not held then
            if ctx.active and ctx.on_release then ctx.on_release(self, ctx) end
            ctx.active = false
            current, ctx.ready, ctx.aligning, ctx.px, ctx.py, ctx.ix, ctx.iy = nil, nil, nil, nil, nil, nil, nil
        end
        ctx.hovered = hovered or ctx.active
        local prefer = { nil, nil }
        local dx, dy, dw, dh = self.x * DPI, self.y * DPI, self.w * DPI, self.h * DPI
        local wx, wy = ctx.px and (ctx.px + mouse.x) * DPI or dx, ctx.py and (ctx.py + mouse.y) * DPI or dy
        local cx, cy = dx + dw * .5, dy + dh * .5
        local p1 = anima.condition(ctx.progress[1], ctx.hovered, 4)
        local p2 = anima.condition(ctx.progress[2], ctx.active, 4)
        render.rectangle(self.x - 3, self.y - 3, self.w + 6, self.h + 6, colors.white:alphen(12 + 24 * p1), 6)
        render.push_alpha(p2)
        if not client.key_state(0xA2) then
            local wcx, wcy = (wx + dw * .5) / DPI, (wy + dh * .5) / DPI
            for i, v in ipairs(ctx.rulers) do
                local spx, spy = v[2] / DPI, v[3] / DPI
                local dist = math.abs(v[1] and wcx - spx or wcy - spy)
                local allowed = dist < (10 * DPI)
                local pxy = v[1] and 1 or 2
                if not prefer[pxy] then
                    prefer[pxy] = allowed and (v[1] and spx - self.w * .5 or spy - self.h * .5) or nil
                end
                v.p = v.p or {0}
                local adist = math.abs(v[1] and cx - spx or cy - spy)
                local pp = anima.condition(v.p, allowed or adist < (10 * DPI), -8) * .35 + 0.1
                render.rectangle(spx, spy, v[1] and 1 or v[4], v[1] and v[4] or 1, colors.white:alphen(pp, true))
            end
            if ctx.border[5] then
                local xa, ya, xb, yb = ctx.border[1], ctx.border[2], ctx.border[3], ctx.border[4]
                local inside = in_bounds(self.x, self.y, xa, ya, xb - self.w * .5 - 1, yb - self.h * .5 - 1)
                local p3 = anima.condition(ctx.progress[3], not inside)
                render.rect_outline(xa, ya, xb - xa, yb - ya, colors.white:alphen(p3 * .75 + .25, true), 4)
            end
        end
        render.pop_alpha()
        if ctx.active then
            local fx, fy = prefer[1] or wx / DPI, prefer[2] or wy / DPI
            local min_x, min_y = (ctx.border[1] - dw * .5) / DPI, (ctx.border[2] - dh * .5) / DPI
            local max_x, max_y = (ctx.border[3] - dw * .5) / DPI, (ctx.border[4] - dh * .5) / DPI
            local x, y = math.clamp(fx, math.max(min_x, 0), math.min(max_x, sw - self.w)), math.clamp(fy, math.max(min_y, 0), math.min(max_y, sh - self.h))
            self:set_position(x, y)
            if ctx.on_active then ctx.on_active(self, ctx, fin) end
        end
    end)
    drag = {
        new = a(function (widget, props)
            menu.drag[widget.id] = {
                x = pui.slider("MISC", "Settings", widget.id ..":x", 0, 10000, (widget.x / sw) * 10000),
                y = pui.slider("MISC", "Settings", widget.id ..":y", 0, 10000, (widget.y / sh) * 10000),
            }
            menu.drag[widget.id].x:set_visible(false)
            menu.drag[widget.id].y:set_visible(false)
            menu.drag[widget.id].x:set_callback(function (this) widget.x = math.round(this.value * .0001 * sw) end, true)
            menu.drag[widget.id].y:set_callback(function (this) widget.y = math.round(this.value * .0001 * sh) end, true)
            props = type(props) == "table" and props or {}
            widget.__drag = {
                locked = false, active = false, hovered = nil, aligning = nil,
                progress = {{0}, {0}, {0}},
                ix, iy = widget.x, widget.y,
                px, py = nil, nil,
                border = props.border or {0, 0, asw, ash},
                rulers = props.rulers or {},
                on_release = props.on_release, on_held = props.on_held, on_active = props.on_active,
                config = menu.drag[widget.id],
                work = process,
            }
            callbacks["wind::render_dpi"]:set(function (new)
                menu.drag[widget.id].x:set(menu.drag[widget.id].x.value)
                menu.drag[widget.id].y:set(menu.drag[widget.id].y.value)
            end)
            callbacks.setup_command:set(function (cmd)
                if pui.menu_open and (widget.__drag.hovered or widget.__drag.active) then cmd.in_attack = 0 end
            end)
        end)
    }
end

local widget do
    local mt; mt = {
        update = function (self) return 1 end,
        paint = function (self, x, y, w, h) end,
        set_position = function (self, x, y)
            if self.__drag then
                if x then
                    self.__drag.config.x:set( x / sw * 10000 )
                    self.x = x
                end
                if y then
                    self.__drag.config.y:set( y / sh * 10000 )
                    self.y = y
                end
            else
                self.x, self.y = x or self.x, y or self.y
            end
        end,
        get_position = function (self)
            local ctx = self.__drag and self.__drag.config
            if not ctx then return self.x, self.y end
            return ctx.x.value * .0001 * sw, ctx.y.value * .0001 * sh
        end,
        __call = a(function (self)
            local __list, __drag = self.__list, self.__drag
            if __list then
                __list.items, __list.active = __list.collect(), 0
                for i = 1, #__list.items do
                    if __list.items[i].active then __list.active = __list.active + 1 end
                end
            end
            self.alpha = self:update()
            render.push_alpha(self.alpha)
            if self.alpha > 0 then
                if __drag then __drag.work(self) end
                if __list then mt.traverse(self) end
                self:paint(self.x, self.y, self.w, self.h)
            end
            render.pop_alpha()
        end),
        enlist = function (self, collector, painter)
            self.__list = {
                items = {}, progress = setmetatable({}, { __mode = "k" }),
                longest = 0, active = 0, minwidth = self.w,
                collect = collector, paint = painter,
            }
        end,
        traverse = function (self)
            local ctx, offset = self.__list, 0
            local lx, ly = 0, 0
            ctx.active, ctx.longest = 0, 0
            for i = 1, #ctx.items do
                local v = ctx.items[i]
                local id = v.name or i
                ctx.progress[id] = ctx.progress[id] or {0}
                local p = anima.condition(ctx.progress[id], v.active)
                if p > 0 then
                    render.push_alpha(p)
                    lx, ly = ctx.paint(self, v, offset, p)
                    render.pop_alpha()
                    ctx.active, offset = ctx.active + 1, offset + (ly * p)
                    ctx.longest = math.max(ctx.longest, lx)
                end
            end
            self.w = anima.lerp(self.w, math.max(ctx.longest, ctx.minwidth), 10, .5)
        end,
        lock = function (self, b)
            if not self.__drag then return end
            self.__drag.locked = b and true or false
        end,
    }
    mt.__index = mt
    widget = {
        new = function (id, x, y, w, h, draggable)
            local self = {
                id = id, type = 0,
                x = x or 0, y = y or 0, w = w or 0, h = h or 0,
                alpha = 0, progress = {0}
            }
            if draggable then drag.new(self, draggable) end
            return setmetatable(self, mt)
        end,
    }
end

-- #region : HUD
local hud = {}

-- #region - Watermark
hud.watermark = widget.new("watermark", sw - 24, 24, 160, 24, {
    rulers = {
        { true, asc.x, 0, ash },
        { false, 0, ash - 32, asw },
        { false, 0, 32, asw },
    },
    on_release = function (self, ctx)
        local partition = sw / 3
        local pos = self.x + self.w * .5

        local align = math.floor(pos / partition)
        if align == self.align then return end
        self.align = align

        if self.align == 1 then
            self:set_position(pos)
            self.x = self.x - self.w * .5
        elseif self.align == 2 then
            self:set_position(self.x + self.w)
            self.x = self.x - self.w
        end

        ctx.config.a:set(align)
    end,
    on_held = function (self, ctx)
        self.align = 0
        ctx.config.a:set(0)
    end,
})

hud.watermark.align, hud.watermark.logop, hud.watermark.logo = 2, {0}, 0
hud.watermark.__drag.config.a = pui.slider("MISC", "Settings", "watermark:align", 0, 2, hud.watermark.align)
hud.watermark.__drag.config.a:set_visible(false)
hud.watermark.__drag.config.a:set_callback(function (this)
    hud.watermark.align = this.value
end, true)
hud.watermark.items = {
    {
        0, function (self, x, y)
            local text = "Wind ~ Renewed"
            local tw, th = render.measure_text("", text)
            local icon_width = 16
            local text_offset = icon_width + 8
            
            local total_width = tw + 16 + icon_width + 4

            if self[1] > 0 then
                render.blur(x, y + 1, total_width, 22, 1, 8)
                render.rectangle(x, y + 1, total_width, 22, colors.panel.l1, 4)
                render.text(x + 8, y + 6, colors.text, nil, nil, "☁️")
                render.text(x + text_offset, y + 6, colors.text, nil, nil, text)
            end

            return true, total_width
        end, {}
    },
    {
        0, function (self, x, y)
            local username = steam_name()
            local t = string.format("Renewed" and "%s" or "%s %s%02x— %s", username, colors.hexs, render.get_alpha() * self[1] * 255, "Renewed")
            local tw, th = render.measure_text("", t)

            if self[1] > 0 then
                render.blur(x, y + 1, tw + 16, 22, 1, 8)
                render.rectangle(x, y + 1, tw + 16, 22, colors.panel.l2, 4)
                render.text(x + 8, y + 6, colors.text, nil, nil, t)
            end

            return true, tw + 16
        end, {}
    },
    {
        0, function (self, x, y)
            local hours, minutes = client.system_time()
            local text = string.format("%02d:%02d", hours, minutes)
            
            local time_of_day = ""
            
            if hours >= 5 and hours < 12 then
                time_of_day = "Morning"
            elseif hours >= 12 and hours < 17 then
                time_of_day = "Day"
            elseif hours >= 17 and hours < 21 then
                time_of_day = "Evening"
            else
                time_of_day = "Night"
            end
            
            local time_text = string.format(" %s", time_of_day)
            local tw, th = render.measure_text("", text)
            local time_tw, time_th = render.measure_text("", time_text)
            local total_width = tw + time_tw + 16

            if self[1] > 0 then
                render.blur(x, y + 1, total_width, 22, 1, 8)
                render.rectangle(x, y + 1, total_width, 22, colors.panel.l2, 4)
                render.text(x + 8, y + 6, colors.text, nil, nil, text)
                local grey_color = color(colors.text.r * 0.7, colors.text.g * 0.7, colors.text.b * 0.7, colors.text.a)
                render.text(x + 8 + tw, y + 6, grey_color, nil, nil, time_text)
            end

            return true, total_width
        end, {}
    },
    {
        0, function (self, x, y)
            local ping = client.latency() * 1000
            local text = string.format("%dms", ping)
            local tw, th = render.measure_text("", text)

            if self[1] > 0 then
                render.blur(x, y + 1, tw + 16, 22, 1, 8)
                render.rectangle(x, y + 1, tw + 16, 22, colors.panel.l2, 4)
                render.text(x + 8, y + 6, colors.text, nil, nil, text)
            end

            return ping > 5, tw + 16
        end, {}
    },
}

hud.watermark.enumerate = function (self)
    local total = self.logo * ((86 or 64) + 4)
    for i, v in ipairs(self.items) do
        render.push_alpha(v[1])
        local state, length = v[2](v, self.x + total, self.y)
        render.pop_alpha()

        v[1] = anima.condition(v[3], state)

        total = total + (length + 2) * v[1]
    end
    self.w = anima.lerp(self.w, total, nil, .5)
end

hud.watermark.update = function (self)
    local cx, cy = self:get_position()

    if self.align == 2 then
        self.x = cx - self.w * self.alpha
    elseif self.align == 1 then
        self.x = cx - self.w * .5
    end

    return anima.condition(self.progress, menu.visuals.soluswatermark.enable.value, 3)
end

hud.watermark.paint = function (self, x, y, w, h)
    self.logo = anima.condition(self.logop)

    if self.logo > 0 then
        local wl = 86 or 64
        render.push_alpha(self.logo)
        render.blur(x, y, wl, h, 1, 8)
        render.rounded_side_v(x, y, wl, h, colors.panel.g1, 4)
        render.rectangle(x + wl, y, 2, h, colors.panel.g1)
        render.logo(x + 8, y + 5)
        render.edge_v(x + wl, y, 24)
        render.pop_alpha()
    end

    self:enumerate()
end

-- #region - Damage indicator
hud.damage = widget.new("damage", sc.x + 4, sc.y + 4, 6, 4, {
    border = { asc.x - 40, asc.y - 40, asc.x + 40, asc.y + 40, true }
})

hud.damage.dmg = refs.rage.aimbot.damage.value
hud.damage.ovr_alpha = 0

hud.damage.update = function (self)
    if not menu.visuals.damage.enable.value then
        return anima.condition(self.progress, false, -4)
    end
    local overridden = (refs.rage.aimbot.damage_ovr[1].value and refs.rage.aimbot.damage_ovr[1]:get_hotkey())
    local minimum_damage = overridden and refs.rage.aimbot.damage_ovr[2].value or refs.rage.aimbot.damage.value
    self.dmg = anima.lerp(self.dmg, minimum_damage, 16)
    self.ovr_alpha = anima.condition("hud::damage.ovr_alpha", overridden, -8)
    local weapon_t = my.weapon and weapondata(my.weapon)
    local weapon_valid = weapon_t and weapon_t.weapon_type_int ~= 9 and weapon_t.weapon_type_int ~= 0
    return anima.condition(self.progress, my.valid and (weapon_valid or pui.menu_open) and not my.in_score and globals.mapname(), -8)
end

hud.damage.paint = function (self, x, y, w, h)
    local dmg = math.round(self.dmg)
    dmg = dmg == 0 and "A" or dmg > 100 and ("+" .. (dmg - 100)) or tostring(dmg)
    self.w, self.h = render.measure_text("-", dmg)
    self.h, self.w = self.h - 3, self.w + 1
    render.text(x - 1, y - 2, colors.text:alphen( math.lerp(96, 255, self.ovr_alpha) ), "-", nil, dmg)
end

-- #region - Slowdown
hud.slowdown = widget.new("slowdown", sc.x - 120 * 0.5, sc.y - 160, 120, 32, {
    rulers = { { true, asc.x, 0, ash } }
})
hud.slowdown.speed = 0.5
hud.slowdown.update = function (self)
    if not menu.visuals.slowdown.enable.value or not my.valid then
        return anima.condition(self.progress, false, -4)
    end
    self.speed = entity.get_prop(my.entity, "m_flVelocityModifier")
    return anima.condition(self.progress, pui.menu_open or (my.valid and self.speed < 1), -8)
end
hud.slowdown.paint = function (self, x, y, w, h)
    local gray_color = colors.text:lerp(color.rgb(150, 150, 150), self.speed)
    render.blur(x, y, 32, h)
    render.rectangle(x, y, 32, h, colors.panel.l1, 4)
    render.text(x + 16, y + 14, colors.text, "c", nil, "")
    render.blur(x + 36, y, w - 36, h)
    render.rectangle(x + 36, y, w - 36, h, colors.panel.l1, 4)
    render.text(x + 36 + (w - 36) * 0.5, y + 16, gray_color, "c", nil, string.format("slowed: %d%%", self.speed * 100))
end

-- #region - Keylist
hud.keylist = widget.new("keylist", sc.x - 400, sc.y, 120, 22, true)
hud.keylist.binds = {
    {
        name = "Minimum damage",
        ref = refs.rage.aimbot.damage_ovr[1],
        state = function () return refs.rage.aimbot.damage_ovr[2].value end
    }, {
        name = "Double tap",
        ref = refs.rage.aimbot.double_tap[1],
    }, {
        name = "Hide shots",
        ref = refs.rage.aimbot.onshot,
    }, {
        name = "Quick peek",
        ref = refs.rage.other.peek,
    }, {
        name = "Edge yaw",
        ref = refs.aa.edge_yaw,
    }, {
        name = "Freestanding",
        ref = refs.aa.freestand,
    },
}

hud.keylist:enlist(function ()
    local list = {}
    for i = 1, #hud.keylist.binds do
        local v = hud.keylist.binds[i]
        local active, state = false, "on"
        if type(v.ref) == "function" then
            active = v.ref()
        elseif v.ref ~= nil then
            active = v.ref.value
            if v.ref.hotkey then
                local __active, __mode = v.ref.hotkey:get()
                active = active and __active and __mode ~= 0
            end
        end
        if v.state then
            if type(v.state) == "function" then
                state = v.state()
            else
                state = v.state
            end
        end
        list[i] = {
            name = v.name,
            active = active,
            state = state,
        }
    end
    return list
end, function (self, item, offset, progress)
    local x, y, w, h = self.x + 4, self.y + offset + (self.h + 4) * progress, self.w - 8, 20
    render.blur(x, y, w, h)
    render.rectangle(x, y, w, h, colors.panel.l1, 4)
    render.text(x + 6, y + 3, colors.text, nil, nil, item.name)
    local gray_color = { r = 150, g = 150, b = 150, a = 255 }
    render.text(x + w - 6, y + 3, gray_color, "r", nil, item.state)
    local length = render.measure_text(nil, item.name .. item.state)
    return length + 32, h + 2
end)

hud.keylist.update = function (self)
    return anima.condition(self.progress, menu.visuals.keylist.enable.value and (pui.menu_open or self.__list.active > 0))
end

hud.keylist.paint = function (self, x, y, w, h)
    render.blur(x, y, w, 24)
    render.rectangle(x, y, w, 24, colors.panel.l1, 8)
    render.text(x + w * .5, y + 11, colors.text, "c", nil, " Hotkeys")
end

-- #region - Speclist
hud.speclist = widget.new("speclist", sc.x - 400, sc.y, 120, 22, true)
hud.speclist:enlist(function ()
    local list = {}
    if my.valid then
        local target
        local ob_target, ob_mode = entity.get_prop(my.entity, "m_hObserverTarget"), entity.get_prop(my.entity, "m_iObserverMode")
        if ob_target and (ob_mode == 4 or ob_mode == 5) then
            target = ob_target
        else
            target = my.entity
        end
        for ent = 1, 64 do
            if entity.get_classname(ent) == "CCSPlayer" and ent ~= my.entity then
                local cob_target, cob_mode = entity.get_prop(ent, "m_hObserverTarget"), entity.get_prop(ent, "m_iObserverMode")
                list[#list+1] = {
                    name = ent, nick = string.limit(entity.get_player_name(ent), 20, "..."),
                    active = cob_target and cob_target == target and (cob_mode == 4 or cob_mode == 5)
                }
            end
        end
    end
    return list
end, function (self, item, offset, progress)
    local x, y, w, h = self.x + 4, self.y + offset + (self.h + 4) * progress, self.w - 8, 20
    render.blur(x, y, w, h)
    render.rectangle(x, y, w, h, colors.panel.l1, 4)
    render.text(x + 6, y + 3, colors.text, nil, nil, item.nick)
    local gray_color = { r = 150, g = 150, b = 150, a = 255 }
    if item.active then
        render.text(x + w - 6, y + 3, gray_color, "r", nil, "spec")
    end
    local length = render.measure_text(nil, item.nick)
    return length + 32, h + 2
end)

hud.speclist.update = function (self)
    return anima.condition(self.progress, menu.visuals.speclist.enable.value and (pui.menu_open or self.__list.active > 0))
end

hud.speclist.paint = function (self, x, y, w, h)
    render.blur(x, y, w, 24)
    render.rectangle(x, y, w, 24, colors.panel.l1, 8)
    render.text(x + w * .5, y + 11, colors.text, "c", nil, string.format(" Spectators (%d)", self.__list.active))
end

do
    local fn = a(function ()
        if menu.visuals.soluswatermark.enable.value or hud.watermark.alpha > 0 then
            hud.watermark()
        end
        if menu.visuals.damage.enable.value or hud.damage.alpha > 0 then
            hud.damage()
        end
        if menu.visuals.slowdown.enable.value or hud.slowdown.alpha > 0 then
            hud.slowdown()
        end
        if menu.visuals.speclist.enable.value or hud.speclist.alpha > 0 then
            hud.speclist()
        end
        if menu.visuals.keylist.enable.value or hud.keylist.alpha > 0 then
            hud.keylist()
        end
    end)
    callbacks.paint_ui:set(fn)
end

local function apply_thirdperson()
    local on = menu.visuals.thirdperson.enable:get()
    if cvar and cvar.cam_collision then cvar.cam_collision:set_int(on and 1 or 0) end
    if on then
        local dist = menu.visuals.thirdperson.distance:get()
        if cvar and cvar.c_mindistance then cvar.c_mindistance:set_int(dist) end
        if cvar and cvar.c_maxdistance then cvar.c_maxdistance:set_int(dist) end
    end
end

menu.visuals.thirdperson.enable:set_callback(apply_thirdperson)
menu.visuals.thirdperson.distance:set_callback(apply_thirdperson)

client.set_event_callback("paint", function()
    if not menu.visuals.watermark.enable:get() then return end
    local left_text = "Wind Renewed"
    local right_text = " / " .. steam_name()
    local w, h = client.screen_size()
    local lw, lh = renderer.measure_text("", left_text)
    local rw, rh = renderer.measure_text("", right_text)
    local total_w = lw + rw
    local x = 16
    local y = (h - lh) / 2
    local pos = menu.visuals.watermark.position:get()
    if pos == "Right center" then
        x = w - 16 - total_w
        y = (h - lh) / 2
    elseif pos == "Bottom center" then
        x = (w - total_w) / 2
        y = h - lh - 16
    end
    local r0, g0, b0, a0 = menu.visuals.watermark.color_start:get()
    local r1, g1, b1, a1 = menu.visuals.watermark.color_end:get()
    local speed = 0.5
    local phase = (globals.realtime() * speed) % 1
    local cursor = 0
    for i = 1, #left_text do
        local ch = left_text:sub(i, i)
        local cw = select(1, renderer.measure_text("", ch))
        local center = cursor + cw * 0.5
        local t = (lw > 0) and ((center / lw - phase) % 1) or 0
        local r = r0 + (r1 - r0) * t
        local g = g0 + (g1 - g0) * t
        local b = b0 + (b1 - b0) * t
        local a = a0 + (a1 - a0) * t
        renderer.text(x + cursor, y, r, g, b, a, "", 0, ch)
        cursor = cursor + cw
    end
    renderer.text(x + cursor, y, 255, 255, 255, 255, "", 0, right_text)
end)

local commands = {
    ["AWP"] = "buy awp", ["SCAR20/G3SG1"] = "buy scar20", ["Scout"] = "buy ssg08",
    ["M4/AK47"] = "buy m4a1", ["Famas/Galil"] = "buy famas", ["Aug/SG553"] = "buy aug",
    ["M249"] = "buy m249", ["Negev"] = "buy negev", ["Mag7/SawedOff"] = "buy mag7",
    ["Nova"] = "buy nova", ["XM1014"] = "buy xm1014", ["MP9/Mac10"] = "buy mp9",
    ["UMP45"] = "buy ump45", ["PPBizon"] = "buy bizon", ["MP7"] = "buy mp7",
    ["CZ75/Tec9/FiveSeven"] = "buy tec9", ["P250"] = "buy p250", ["Deagle/Revolver"] = "buy deagle",
    ["Dualies"] = "buy elite", ["HE Grenade"] = "buy hegrenade", ["Molotov"] = "buy molotov",
    ["Smoke"] = "buy smokegrenade", ["Armor"] = "buy vest", ["Helmet"] = "buy vesthelm", 
    ["Zeus"] = "buy taser 34", ["Defuser"] = "buy defuser"
}

client.set_event_callback("round_prestart", function()
    if not menu.misc.autobuy.enable:get() then return end
    local util = menu.misc.autobuy.utilities:get() or {}
    for i = 1, #util do
        local n = util[i]
        local cmd = commands[n]
        if cmd then client.exec(cmd) end
    end
    do
        local cmd = commands[menu.misc.autobuy.secondary:get()]
        if cmd then client.exec(cmd) end
    end
    do
        local cmd = commands[menu.misc.autobuy.primary:get()]
        if cmd then client.exec(cmd) end
    end
    local nades = menu.misc.autobuy.grenades:get() or {}
    for i = 1, #nades do
        local n = nades[i]
        local cmd = commands[n]
        if cmd then client.exec(cmd) end
    end
end)

client.set_event_callback("paint_ui", function()
    update_accent_color()
    update_visibility()
    render_tab_indicator()
end)

client.set_event_callback("shutdown", function()
    gui_show(true)
end)