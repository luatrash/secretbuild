local safe = {}
function safe:require(module_name)
    local status, module = pcall(require, module_name)
    if status then
        return module
    else
        print('Error loading module "' .. module_name .. '": ' .. tostring(module))
        return nil
    end
end


if not entity.get_local_player() then
    print('You cannot load the lua until you join a map!')
    return
end

local vector        = safe:require ('vector')
local http          = safe:require ('gamesense/http')
local pui           = safe:require ('gamesense/pui')
local base64        = safe:require ('gamesense/base64')
local clipboard     = safe:require ('gamesense/clipboard')
local aa_func       = safe:require ('gamesense/antiaim_funcs')
local trace         = safe:require ('gamesense/trace')
local csgo_weapons  = safe:require ('gamesense/csgo_weapons')
local steamworks    = safe:require ('gamesense/steamworks')
local localize      = safe:require ('gamesense/localize')
local chat          = safe:require ('gamesense/chat')
local images        = safe:require ('gamesense/images')

if not pui then
    print('Failed to load PUI library. Script cannot continue.')
    return
end

local software = {
    antiaimbot = {
        angles = {
            enabled = ui.reference('AA', 'Anti-aimbot angles', 'Enabled'),
            
            pitch = {
                ui.reference('AA', 'Anti-aimbot angles', 'Pitch')
            },
            
            yaw_base = ui.reference('AA', 'Anti-aimbot angles', 'Yaw base'),
            
            yaw = {
                ui.reference('AA', 'Anti-aimbot angles', 'Yaw')
            },
            
            yaw_jitter = {
                ui.reference('AA', 'Anti-aimbot angles', 'Yaw jitter')
            },
            
            body_yaw = {
                ui.reference('AA', 'Anti-aimbot angles', 'Body yaw')
            },
            
            freestanding_body_yaw = ui.reference('AA', 'Anti-aimbot angles', 'Freestanding body yaw'),
            
            edge_yaw = ui.reference('AA', 'Anti-aimbot angles', 'Edge yaw'),
            
            freestanding = {
                ui.reference('AA', 'Anti-aimbot angles', 'Freestanding')
            },
            
            roll = ui.reference('AA', 'Anti-aimbot angles', 'Roll')
        }
    }
}

local json = {
    stringify = function(obj)
        if type(obj) == "table" then
            local is_array = true
            local max_index = 0
            local count = 0
            
            for k, v in pairs(obj) do
                count = count + 1
                if type(k) ~= "number" then
                    is_array = false
                    break
                end
                if k > max_index then
                    max_index = k
                end
            end
            
            if is_array and count == max_index then
                local result = "["
                for i = 1, max_index do
                    if i > 1 then result = result .. "," end
                    result = result .. json.stringify(obj[i])
                end
                return result .. "]"
            else
                local result = "{"
                local first = true
                for k, v in pairs(obj) do
                    if not first then result = result .. "," end
                    result = result .. '"' .. tostring(k) .. '":' .. json.stringify(v)
                    first = false
                end
                return result .. "}"
            end
        elseif type(obj) == "string" then
            return '"' .. obj:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
        elseif type(obj) == "boolean" then
            return obj and "true" or "false"
        elseif type(obj) == "number" then
            return tostring(obj)
        elseif obj == nil then
            return "null"
        else
            return '"' .. tostring(obj) .. '"'
        end
    end,
    
    parse = function(str)
        if not str then return nil end
        
        local pos = 1
        
        local function skip_whitespace()
            while pos <= #str and str:sub(pos, pos):match("%s") do
                pos = pos + 1
            end
        end
        
        local function parse_value()
            skip_whitespace()
            local char = str:sub(pos, pos)
            
            if char == '"' then
                pos = pos + 1
                local start_pos = pos
                while pos <= #str do
                    if str:sub(pos, pos) == '"' and str:sub(pos - 1, pos - 1) ~= '\\' then
                        local value = str:sub(start_pos, pos - 1)
                        pos = pos + 1
                        return value
                    end
                    pos = pos + 1
                end
                return nil
            elseif char == '{' then
                local obj = {}
                pos = pos + 1
                skip_whitespace()
                
                if str:sub(pos, pos) == '}' then
                    pos = pos + 1
                    return obj
                end
                
                while pos <= #str do
                    skip_whitespace()
                    
                    if str:sub(pos, pos) == '"' then
                        local key = parse_value()
                        if not key then return nil end
                        
                        skip_whitespace()
                        if str:sub(pos, pos) ~= ':' then return nil end
                        pos = pos + 1
                        
                        local value = parse_value()
                        obj[key] = value
                        
                        skip_whitespace()
                        if str:sub(pos, pos) == ',' then
                            pos = pos + 1
                        elseif str:sub(pos, pos) == '}' then
                            pos = pos + 1
                            return obj
                        end
                    elseif str:sub(pos, pos) == '}' then
                        pos = pos + 1
                        return obj
                    else
                        pos = pos + 1
                    end
                end
                return obj
            elseif char == '[' then
                local arr = {}
                pos = pos + 1
                skip_whitespace()
                
                if str:sub(pos, pos) == ']' then
                    pos = pos + 1
                    return arr
                end
                
                local index = 1
                while pos <= #str do
                    local value = parse_value()
                    if value ~= nil or str:sub(pos - 4, pos - 1) == 'null' then
                        arr[index] = value
                        index = index + 1
                    end
                    
                    skip_whitespace()
                    if str:sub(pos, pos) == ',' then
                        pos = pos + 1
                    elseif str:sub(pos, pos) == ']' then
                        pos = pos + 1
                        return arr
                    else
                        break
                    end
                end
                return arr
            elseif char:match('[%d%-]') then
                local start_pos = pos
                while pos <= #str and str:sub(pos, pos):match('[%d%.-]') do
                    pos = pos + 1
                end
                return tonumber(str:sub(start_pos, pos - 1))
            elseif str:sub(pos, pos + 3) == 'true' then
                pos = pos + 4
                return true
            elseif str:sub(pos, pos + 4) == 'false' then
                pos = pos + 5
                return false
            elseif str:sub(pos, pos + 3) == 'null' then
                pos = pos + 4
                return nil
            else
                return nil
            end
        end
        
        return parse_value()
    end
}

local script = {
    name = 'Althea',
    version = '3.0'
}

local ce_avatar = nil

pcall(function()
    if not _G.panorama then return end
    if not images then return end
    
    local panorama_api = _G.panorama.open()
    if not panorama_api then return end
    if not panorama_api.MyPersonaAPI then return end
    
    local xuid = panorama_api.MyPersonaAPI.GetXuid()
    if not xuid or xuid == 0 then return end
    
    ce_avatar = images.get_steam_avatar(xuid, 32)
end)

local menu = {
    group = {
        main = pui.group('AA', 'Anti-aimbot angles'),
        fakelag = pui.group('AA', 'Fake lag'),
        other = pui.group('AA', 'Other')
    }
}

do
    local function hide_all_aa()
        pcall(function()
            local aa_refs = {
                fakelag_enable = pui.reference("AA", "Fake lag", "Enabled"),
                fakelag_amount = pui.reference("AA", "Fake lag", "Amount"),
                fakelag_variance = pui.reference("AA", "Fake lag", "Variance"),
                fakelag_limit = pui.reference("AA", "Fake lag", "Limit"),
                
                other_slowmo = pui.reference("AA", "Other", "Slow motion"),
                other_legs = pui.reference("AA", "Other", "Leg movement"),
                other_onshot = pui.reference("AA", "Other", "On shot anti-aim"),
                other_fp = pui.reference("AA", "Other", "Fake peek"),
                
                aa_enable = pui.reference("AA", "Anti-aimbot angles", "Enabled"),
                aa_pitch = pui.reference("AA", "Anti-aimbot angles", "Pitch"),
                aa_yaw_base = pui.reference("AA", "Anti-aimbot angles", "Yaw base"),
                aa_yaw = pui.reference("AA", "Anti-aimbot angles", "Yaw"),
                aa_yaw_jitter = pui.reference("AA", "Anti-aimbot angles", "Yaw jitter"),
                aa_body_yaw = pui.reference("AA", "Anti-aimbot angles", "Body yaw"),
                aa_freestanding_body = pui.reference("AA", "Anti-aimbot angles", "Freestanding body yaw"),
                aa_freestanding = pui.reference("AA", "Anti-aimbot angles", "Freestanding"),
                aa_edge_yaw = pui.reference("AA", "Anti-aimbot angles", "Edge yaw"),
                aa_roll = pui.reference("AA", "Anti-aimbot angles", "Roll")
            }
            
            pui.traverse(aa_refs, function(ref)
                ref:set_visible(false)
            end)
        end)
        
        pcall(function()
            local yaw_refs = {ui.reference("AA", "Anti-aimbot angles", "Yaw")}
            local yaw_jitter_refs = {ui.reference("AA", "Anti-aimbot angles", "Yaw jitter")}
            local body_yaw_refs = {ui.reference("AA", "Anti-aimbot angles", "Body yaw")}
            local roll_refs = {ui.reference("AA", "Anti-aimbot angles", "Roll")}
            local pitch_refs = {ui.reference("AA", "Anti-aimbot angles", "Pitch")}
            local yaw_base_ref = ui.reference("AA", "Anti-aimbot angles", "Yaw base")
            local freestanding_refs = {ui.reference("AA", "Anti-aimbot angles", "Freestanding")}
            local freestanding_body_ref = ui.reference("AA", "Anti-aimbot angles", "Freestanding body yaw")
            local edge_yaw_ref = ui.reference("AA", "Anti-aimbot angles", "Edge yaw")
            local enabled_ref = ui.reference("AA", "Anti-aimbot angles", "Enabled")
            
            for i = 1, #yaw_refs do
                ui.set_visible(yaw_refs[i], false)
            end
            for i = 1, #yaw_jitter_refs do
                ui.set_visible(yaw_jitter_refs[i], false)
            end
            for i = 1, #body_yaw_refs do
                ui.set_visible(body_yaw_refs[i], false)
            end
            for i = 1, #roll_refs do
                ui.set_visible(roll_refs[i], false)
            end
            for i = 1, #pitch_refs do
                ui.set_visible(pitch_refs[i], false)
            end
            for i = 1, #freestanding_refs do
                ui.set_visible(freestanding_refs[i], false)
            end
            
            ui.set_visible(yaw_base_ref, false)
            ui.set_visible(freestanding_body_ref, false)
            ui.set_visible(edge_yaw_ref, false)
            ui.set_visible(enabled_ref, false)
        end)
    end
    
    hide_all_aa()
    
    client.set_event_callback("paint_ui", function()
        hide_all_aa()
    end)
end

local tab = {
    main = menu.group.main:combobox('Tab', {
        ' Home',
        ' Aimbot',
        ' Visual', 
        ' Anti-Aim',
        ' Misc'
    }),
    space = menu.group.fakelag:label(' '),
    aimbot_sub = menu.group.fakelag:combobox('\nAimbot Tab', {' Main', ' Rage'})
}



local db = {
    name = "Althea::data"
}
do
    db.data = database.read(db.name) or {}
    
    db.read = function(key)
        return db.data[key]
    end
    
    db.write = function(key, value)
        db.data[key] = value
        database.write(db.name, db.data)
    end
end

local function get_username()

    if _G.loader_get_username and type(_G.loader_get_username) == "function" then
        local loader_name = _G.loader_get_username()
        if loader_name and loader_name ~= "" then
            return loader_name
        end
    end
    

    return _USER_NAME or 'admin'
end

local configs = {
    db = db.read("configs") or {},
    data = {},
    maximum_count = 10,
    
    users_configs = {
        {
            name = "Default",
            author = "admin", 
            data = "Althea::gs::eyJkYXRhIjp7ImFudGlhaW0iOnsiYWFwaWNrIjoiT3RoZXIiLCJmcmVlc3RhbmQiOlsiT24gaG90a2V5IiwxOF0sInN0YXRlIjoiXHUwMDBiR2xvYmFsXHIiLCJzYWZlX2hlYWQiOnRydWUsImJ1aWxkZXIiOlt7ImVuYWJsZSI6ZmFsc2UsImJvZHlzbGlkZSI6MCwiZGVmYWFfZW5iIjpmYWxzZSwicGl0Y2giOiJEb3duIiwiY2VudGVyX2RlbGF5IjoyLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWF4X2dlbiI6MjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVsYXkiOjEsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X29mZnNldCI6MCwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZl95YXdfc3BlZWQiOjQsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsInJpZ2h0IjowLCJib2R5eWF3IjoiTm9uZSIsInlhd3R5cGUiOiJMXC9SIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfeWF3IjoiT2ZmIiwibGVmdCI6MCwiZGVmX3BpdGNoIjowLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZ3JlZSI6NDEsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfeWF3X2xlZnQiOjB9LHsiZW5hYmxlIjp0cnVlLCJib2R5c2xpZGUiOjAsImRlZmFhX2VuYiI6ZmFsc2UsInBpdGNoIjoiRG93biIsImNlbnRlcl9kZWxheSI6MiwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJkZWZfeWF3X21heF9nZW4iOjIwLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlbGF5IjoxLCJkZWZfcGl0Y2hfbWF4IjowLCJkZWZfeWF3X3JpZ2h0IjowLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwiZGVmX3lhd19vZmZzZXQiOjAsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWZfeWF3X3NwZWVkIjo0LCJmb3JjZV9kZWZlbnNpdmUiOmZhbHNlLCJkZWZfeWF3X2xlZnRfcmlnaHQiOmZhbHNlLCJyaWdodCI6MCwiYm9keXlhdyI6Ik5vbmUiLCJ5YXd0eXBlIjoiTFwvUiIsImRlZl9waXRjaF9zcGVlZCI6MiwiZGVmX3lhdyI6Ik9mZiIsImxlZnQiOjAsImRlZl9waXRjaCI6MCwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJkZWdyZWUiOjQxLCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwiZGVmX3lhd19sZWZ0IjowfSx7ImVuYWJsZSI6ZmFsc2UsImJvZHlzbGlkZSI6MCwiZGVmYWFfZW5iIjpmYWxzZSwicGl0Y2giOiJEb3duIiwiY2VudGVyX2RlbGF5IjoyLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWF4X2dlbiI6MjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVsYXkiOjEsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X29mZnNldCI6MCwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZl95YXdfc3BlZWQiOjQsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsInJpZ2h0IjowLCJib2R5eWF3IjoiTm9uZSIsInlhd3R5cGUiOiJMXC9SIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfeWF3IjoiT2ZmIiwibGVmdCI6MCwiZGVmX3BpdGNoIjowLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZ3JlZSI6NDEsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfeWF3X2xlZnQiOjB9LHsiZW5hYmxlIjpmYWxzZSwiYm9keXNsaWRlIjowLCJkZWZhYV9lbmIiOmZhbHNlLCJwaXRjaCI6IkRvd24iLCJjZW50ZXJfZGVsYXkiOjIsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwiZGVmX3lhd19tYXhfZ2VuIjoyMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWxheSI6MSwiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6MCwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfb2Zmc2V0IjowLCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVmX3lhd19zcGVlZCI6NCwiZm9yY2VfZGVmZW5zaXZlIjpmYWxzZSwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwicmlnaHQiOjAsImJvZHl5YXciOiJOb25lIiwieWF3dHlwZSI6IkxcL1IiLCJkZWZfcGl0Y2hfc3BlZWQiOjIsImRlZl95YXciOiJPZmYiLCJsZWZ0IjowLCJkZWZfcGl0Y2giOjAsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwiZGVncmVlIjo0MSwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl95YXdfbGVmdCI6MH0seyJlbmFibGUiOnRydWUsImJvZHlzbGlkZSI6MCwiZGVmYWFfZW5iIjpmYWxzZSwicGl0Y2giOiJEb3duIiwiY2VudGVyX2RlbGF5IjoyLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWF4X2dlbiI6MjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVsYXkiOjEsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X29mZnNldCI6MCwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZl95YXdfc3BlZWQiOjQsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsInJpZ2h0IjowLCJib2R5eWF3IjoiTm9uZSIsInlhd3R5cGUiOiJMXC9SIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfeWF3IjoiT2ZmIiwibGVmdCI6MCwiZGVmX3BpdGNoIjowLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZ3JlZSI6NDEsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfeWF3X2xlZnQiOjB9LHsiZW5hYmxlIjp0cnVlLCJib2R5c2xpZGUiOjAsImRlZmFhX2VuYiI6ZmFsc2UsInBpdGNoIjoiRG93biIsImNlbnRlcl9kZWxheSI6MiwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJkZWZfeWF3X21heF9nZW4iOjIwLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlbGF5IjoxLCJkZWZfcGl0Y2hfbWF4IjowLCJkZWZfeWF3X3JpZ2h0IjowLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwiZGVmX3lhd19vZmZzZXQiOjAsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWZfeWF3X3NwZWVkIjo0LCJmb3JjZV9kZWZlbnNpdmUiOmZhbHNlLCJkZWZfeWF3X2xlZnRfcmlnaHQiOmZhbHNlLCJyaWdodCI6MCwiYm9keXlhdyI6Ik5vbmUiLCJ5YXd0eXBlIjoiTFwvUiIsImRlZl9waXRjaF9zcGVlZCI6MiwiZGVmX3lhdyI6Ik9mZiIsImxlZnQiOjAsImRlZl9waXRjaCI6MCwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJkZWdyZWUiOjQxLCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwiZGVmX3lhd19sZWZ0IjowfSx7ImVuYWJsZSI6ZmFsc2UsImJvZHlzbGlkZSI6MCwiZGVmYWFfZW5iIjpmYWxzZSwicGl0Y2giOiJEb3duIiwiY2VudGVyX2RlbGF5IjoyLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWF4X2dlbiI6MjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVsYXkiOjEsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X29mZnNldCI6MCwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZl95YXdfc3BlZWQiOjQsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsInJpZ2h0IjowLCJib2R5eWF3IjoiTm9uZSIsInlhd3R5cGUiOiJMXC9SIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfeWF3IjoiT2ZmIiwibGVmdCI6MCwiZGVmX3BpdGNoIjowLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZ3JlZSI6NDEsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfeWF3X2xlZnQiOjB9LHsiZW5hYmxlIjp0cnVlLCJib2R5c2xpZGUiOjAsImRlZmFhX2VuYiI6ZmFsc2UsInBpdGNoIjoiRG93biIsImNlbnRlcl9kZWxheSI6MiwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJkZWZfeWF3X21heF9nZW4iOjIwLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlbGF5IjoxLCJkZWZfcGl0Y2hfbWF4IjowLCJkZWZfeWF3X3JpZ2h0IjowLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwiZGVmX3lhd19vZmZzZXQiOjAsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWZfeWF3X3NwZWVkIjo0LCJmb3JjZV9kZWZlbnNpdmUiOmZhbHNlLCJkZWZfeWF3X2xlZnRfcmlnaHQiOmZhbHNlLCJyaWdodCI6MCwiYm9keXlhdyI6Ik5vbmUiLCJ5YXd0eXBlIjoiTFwvUiIsImRlZl9waXRjaF9zcGVlZCI6MiwiZGVmX3lhdyI6Ik9mZiIsImxlZnQiOjAsImRlZl9waXRjaCI6MCwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJkZWdyZWUiOjQxLCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwiZGVmX3lhd19sZWZ0IjowfSx7ImVuYWJsZSI6ZmFsc2UsImJvZHlzbGlkZSI6MCwiZGVmYWFfZW5iIjpmYWxzZSwicGl0Y2giOiJEb3duIiwiY2VudGVyX2RlbGF5IjoyLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWF4X2dlbiI6MjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVsYXkiOjEsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X29mZnNldCI6MCwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZl95YXdfc3BlZWQiOjQsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsInJpZ2h0IjowLCJib2R5eWF3IjoiTm9uZSIsInlhd3R5cGUiOiJMXC9SIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfeWF3IjoiT2ZmIiwibGVmdCI6MCwiZGVmX3BpdGNoIjowLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZ3JlZSI6NDEsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfeWF3X2xlZnQiOjB9XX0sInZpc3VhbCI6eyJ3YXRlcm1hcmtfY3VzdG9tIjoiIiwidm1feiI6LTE1LCJ2bV95IjotNzEsInZpZXdtb2RlbCI6dHJ1ZSwiYXNwZWN0X3ZhbCI6MTY0LCJub3RpZmljYXRpb25zIjp0cnVlLCJhcnJvd3MiOmZhbHNlLCJkYW1hZ2UiOnRydWUsImNyb3NzaGFpciI6dHJ1ZSwidm1fZm92Ijo1OCwiYXNwZWN0X3JhdGlvIjp0cnVlLCJ2bV94Ijo1LCJ3YXRlcm1hcmsiOmZhbHNlLCJzY29wZV9saW5lcyI6dHJ1ZSwiYWNjZW50X2NvbG9yIjoiI0ZGRkZGRjcyIiwid2F0ZXJtYXJrX25pY2tuYW1lIjoiU3RlYW0iLCJ3YXRlcm1hcmtfZWxlbWVudHMiOlsiTmlja25hbWUiLCJGcmFtZXMgUGVyIFNlY29uZCIsIlBpbmciLCJUaWNrcmF0ZSIsIlRpbWUiXX0sImFpbWJvdCI6eyJwcmVkaWN0X3JlbmRlcl9ib3giOmZhbHNlLCJwcmVkaWN0X2JveF9jb2xvciI6IiMyRjc1RERGRiIsInVuc2FmZV9jaGFyZ2UiOnRydWUsImp1bXBfc2NvdXQiOnRydWUsImF1dG9fb3Nfc3RhdGVzIjpbIlN0YW5kaW5nIiwiU2xvdyBXYWxrIiwiQ3JvdWNoIiwiTW92ZS1Dcm91Y2giXSwicmVzb2x2ZXIiOnRydWUsImF1dG9fb3MiOmZhbHNlLCJwcmVkaWN0IjpmYWxzZSwiYXV0b19vc193ZWFwb25zIjpbIlNjb3V0Il0sInByZWRpY3RfbG93ZXJfNDBtcyI6ZmFsc2UsInByZWRpY3RfaG90a2V5IjpbIk9uIGhvdGtleSIsMF0sInByZWRpY3RfZGlzYWJsZV9sYyI6ZmFsc2V9LCJtaXNjIjp7ImRyb3BfZ3JlbmFkZXMiOmZhbHNlLCJkcm9wX2dyZW5hZGVzX3NlbGVjdGlvbiI6e30sImFtbV9icmVha2VyIjp0cnVlLCJjbGFudGFnIjpmYWxzZSwidHJhc2h0YWxrX2xhbmd1YWdlIjoiQmFpdCIsInRyYXNodGFsayI6dHJ1ZSwiY29uc29sZV9maWx0ZXIiOnRydWUsImFtbV9icmVha2VyX3R5cGUiOiJTdGF0aWMiLCJmYXN0X2xhZGRlciI6dHJ1ZSwidHJhc2h0YWxrX2V2ZW50cyI6WyJLaWxsIiwiRGVhdGgiXSwiZHJvcF9ncmVuYWRlc19ob3RrZXkiOlsiT24gaG90a2V5IiwwXX19LCJuYW1lIjoiMSJ9",
            protected = true
        },
        {
            name = "Poyola", 
            author = "admin", 
            data = "Althea::gs::eyJkYXRhIjp7ImFudGlhaW0iOnsiYWFwaWNrIjoiQnVpbGRlciIsImZyZWVzdGFuZCI6WzEsMTgsIn4iXSwic3RhdGUiOiJcdTAwMGJHbG9iYWxcciIsImJ1aWxkZXIiOlt7ImVuYWJsZSI6dHJ1ZSwiYm9keXNsaWRlIjoyNSwiZGVmYWFfZW5iIjp0cnVlLCJwaXRjaCI6IkRlZmF1bHQiLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfcGl0Y2hfbW9kZSI6IkppdHRlciIsImRlZl95YXdfbWF4X2dlbiI6MjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVsYXkiOjIsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X3NwZWVkIjo0LCJ5YXdtb2RpZmVyIjoiT2Zmc2V0IiwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJmb3JjZV9kZWZlbnNpdmUiOnRydWUsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsInJpZ2h0IjozNSwibGVmdCI6LTM1LCJ5YXd0eXBlIjoiRGVsYXkiLCJkZWZfeWF3IjoiU3BpbiIsImJvZHl5YXciOiJKaXR0ZXIiLCJkZWZfcGl0Y2hfc3BlZWQiOjIsImRlZl9waXRjaCI6MCwiZGVmX3lhd19vZmZzZXQiOjAsImRlZ3JlZSI6MTUsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJjZW50ZXJfZGVsYXkiOjQsImRlZl95YXdfbGVmdCI6MH0seyJlbmFibGUiOnRydWUsImJvZHlzbGlkZSI6MzUsImRlZmFhX2VuYiI6dHJ1ZSwicGl0Y2giOiJNaW5pbWFsIiwiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwiZGVmX3BpdGNoX21vZGUiOiJTcGluIiwiZGVmX3lhd19tYXhfZ2VuIjoyMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWxheSI6MywiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6MCwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfc3BlZWQiOjQsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImZvcmNlX2RlZmVuc2l2ZSI6dHJ1ZSwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwicmlnaHQiOjQ1LCJsZWZ0IjotNDUsInlhd3R5cGUiOiJEZWxheSIsImRlZl95YXciOiJEaXN0b3J0aW9uIiwiYm9keXlhdyI6Ik9wcG9zaXRlIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfcGl0Y2giOjAsImRlZl95YXdfb2Zmc2V0IjowLCJkZWdyZWUiOjI1LCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiY2VudGVyX2RlbGF5Ijo1LCJkZWZfeWF3X2xlZnQiOjB9XSwic2FmZV9oZWFkIjp0cnVlfSwiYWltYm90Ijp7InByZWRpY3RfcmVuZGVyX2JveCI6dHJ1ZSwicHJlZGljdF9ib3hfY29sb3IiOiIjMkY3NURERkYiLCJ1bnNhZmVfY2hhcmdlIjp0cnVlLCJqdW1wX3Njb3V0Ijp0cnVlLCJhdXRvX29zX3N0YXRlcyI6WyJTdGFuZGluZyIsIlNsb3cgV2FsayIsIkNyb3VjaCIsIk1vdmUtQ3JvdWNoIiwifiJdLCJyZXNvbHZlciI6dHJ1ZSwiYXV0b19vcyI6dHJ1ZSwicHJlZGljdCI6dHJ1ZSwiYXV0b19vc193ZWFwb25zIjpbIlNjb3V0IiwifiJdLCJwcmVkaWN0X2xvd2VyXzQwbXMiOmZhbHNlLCJwcmVkaWN0X2hvdGtleSI6WzEsMCwifiJdLCJwcmVkaWN0X2Rpc2FibGVfbGMiOmZhbHNlfSwidmlzdWFsIjp7IndhdGVybWFya19jdXN0b20iOiIiLCJ2bV96IjotMTUsInZtX3kiOjAsInZpZXdtb2RlbCI6ZmFsc2UsImFzcGVjdF92YWwiOjE3OCwibm90aWZpY2F0aW9ucyI6dHJ1ZSwiYXJyb3dzIjp0cnVlLCJzY29wZV9saW5lcyI6dHJ1ZSwiY3Jvc3NoYWlyIjp0cnVlLCJ2bV9mb3YiOjY4LCJhc3BlY3RfcmF0aW8iOmZhbHNlLCJ3YXRlcm1hcmtfbmlja25hbWUiOiJTdGVhbSIsImFjY2VudF9jb2xvciI6IiNGRjY0OTZGRiIsImRhbWFnZSI6dHJ1ZSwid2F0ZXJtYXJrIjp0cnVlLCJ2bV94IjowLCJ3YXRlcm1hcmtfZWxlbWVudHMiOlsiTmlja25hbWUiLCJGcmFtZXMgUGVyIFNlY29uZCIsIlBpbmciLCJUaWNrcmF0ZSIsIlRpbWUiLCJ+Il19LCJtaXNjIjp7ImRyb3BfZ3JlbmFkZXMiOmZhbHNlLCJkcm9wX2dyZW5hZGVzX3NlbGVjdGlvbiI6WyJ+Il0sImFtbV9icmVha2VyIjpmYWxzZSwiY2xhbnRhZyI6ZmFsc2UsInRyYXNodGFsa19sYW5ndWFnZSI6IkVuZ2xpc2giLCJ0cmFzaHRhbGsiOmZhbHNlLCJjb25zb2xlX2ZpbHRlciI6ZmFsc2UsImFtbV9icmVha2VyX3R5cGUiOiJTdGF0aWMiLCJmYXN0X2xhZGRlciI6ZmFsc2UsInRyYXNodGFsa19ldmVudHMiOlsifiJdLCJkcm9wX2dyZW5hZGVzX2hvdGtleSI6WzEsMCwifiJdfX0sIm5hbWUiOiJQb3lvbGEiLCJhdXRob3IiOiJhZG1pbiJ9",
            protected = true
        },
        {
            name = "Qwincy",
            author = "admin", 
            data = "Althea::gs::eyJkYXRhIjp7ImFudGlhaW0iOnsiYWFwaWNrIjoiT3RoZXIiLCJmcmVlc3RhbmQiOlsiT24gaG90a2V5IiwxOF0sInN0YXRlIjoiXHUwMDBiR2xvYmFsXHIiLCJidWlsZGVyIjpbeyJlbmFibGUiOmZhbHNlLCJib2R5c2xpZGUiOjAsImRlZmFhX2VuYiI6ZmFsc2UsInBpdGNoIjoiRG93biIsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwiZGVmX3lhd19tYXhfZ2VuIjoyMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWxheSI6MSwiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6MCwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfb2Zmc2V0IjowLCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwiZm9yY2VfZGVmZW5zaXZlIjpmYWxzZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJyaWdodCI6MCwibGVmdCI6MCwieWF3dHlwZSI6IkxcL1IiLCJkZWZfeWF3IjoiT2ZmIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJib2R5eWF3IjoiTm9uZSIsImRlZl9waXRjaCI6MCwiZGVmX3lhd19zcGVlZCI6NCwiZGVncmVlIjo0MSwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImNlbnRlcl9kZWxheSI6MiwiZGVmX3lhd19sZWZ0IjowfSx7ImVuYWJsZSI6dHJ1ZSwiYm9keXNsaWRlIjowLCJkZWZhYV9lbmIiOmZhbHNlLCJwaXRjaCI6IkRvd24iLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWF4X2dlbiI6MjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVsYXkiOjEsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X29mZnNldCI6MCwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwicmlnaHQiOjAsImxlZnQiOjAsInlhd3R5cGUiOiJMXC9SIiwiZGVmX3lhdyI6Ik9mZiIsImRlZl9waXRjaF9zcGVlZCI6MiwiYm9keXlhdyI6Ik5vbmUiLCJkZWZfcGl0Y2giOjAsImRlZl95YXdfc3BlZWQiOjQsImRlZ3JlZSI6NDEsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJjZW50ZXJfZGVsYXkiOjIsImRlZl95YXdfbGVmdCI6MH0seyJlbmFibGUiOmZhbHNlLCJib2R5c2xpZGUiOjAsImRlZmFhX2VuYiI6ZmFsc2UsInBpdGNoIjoiRG93biIsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwiZGVmX3lhd19tYXhfZ2VuIjoyMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWxheSI6MSwiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6MCwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfb2Zmc2V0IjowLCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwiZm9yY2VfZGVmZW5zaXZlIjpmYWxzZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJyaWdodCI6MCwibGVmdCI6MCwieWF3dHlwZSI6IkxcL1IiLCJkZWZfeWF3IjoiT2ZmIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJib2R5eWF3IjoiTm9uZSIsImRlZl9waXRjaCI6MCwiZGVmX3lhd19zcGVlZCI6NCwiZGVncmVlIjo0MSwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImNlbnRlcl9kZWxheSI6MiwiZGVmX3lhd19sZWZ0IjowfSx7ImVuYWJsZSI6ZmFsc2UsImJvZHlzbGlkZSI6MCwiZGVmYWFfZW5iIjpmYWxzZSwicGl0Y2giOiJEb3duIiwiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJkZWZfeWF3X21heF9nZW4iOjIwLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlbGF5IjoxLCJkZWZfcGl0Y2hfbWF4IjowLCJkZWZfeWF3X3JpZ2h0IjowLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwiZGVmX3lhd19vZmZzZXQiOjAsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWZfeWF3X2xlZnRfcmlnaHQiOmZhbHNlLCJmb3JjZV9kZWZlbnNpdmUiOmZhbHNlLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsInJpZ2h0IjowLCJsZWZ0IjowLCJ5YXd0eXBlIjoiTFwvUiIsImRlZl95YXciOiJPZmYiLCJkZWZfcGl0Y2hfc3BlZWQiOjIsImJvZHl5YXciOiJOb25lIiwiZGVmX3BpdGNoIjowLCJkZWZfeWF3X3NwZWVkIjo0LCJkZWdyZWUiOjQxLCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiY2VudGVyX2RlbGF5IjoyLCJkZWZfeWF3X2xlZnQiOjB9LHsiZW5hYmxlIjp0cnVlLCJib2R5c2xpZGUiOjAsImRlZmFhX2VuYiI6ZmFsc2UsInBpdGNoIjoiRG93biIsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwiZGVmX3lhd19tYXhfZ2VuIjoyMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWxheSI6MSwiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6MCwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfb2Zmc2V0IjowLCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwiZm9yY2VfZGVmZW5zaXZlIjpmYWxzZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJyaWdodCI6MCwibGVmdCI6MCwieWF3dHlwZSI6IkxcL1IiLCJkZWZfeWF3IjoiT2ZmIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJib2R5eWF3IjoiTm9uZSIsImRlZl9waXRjaCI6MCwiZGVmX3lhd19zcGVlZCI6NCwiZGVncmVlIjo0MSwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImNlbnRlcl9kZWxheSI6MiwiZGVmX3lhd19sZWZ0IjowfSx7ImVuYWJsZSI6dHJ1ZSwiYm9keXNsaWRlIjowLCJkZWZhYV9lbmIiOmZhbHNlLCJwaXRjaCI6IkRvd24iLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWF4X2dlbiI6MjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVsYXkiOjEsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X29mZnNldCI6MCwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwicmlnaHQiOjAsImxlZnQiOjAsInlhd3R5cGUiOiJMXC9SIiwiZGVmX3lhdyI6Ik9mZiIsImRlZl9waXRjaF9zcGVlZCI6MiwiYm9keXlhdyI6Ik5vbmUiLCJkZWZfcGl0Y2giOjAsImRlZl95YXdfc3BlZWQiOjQsImRlZ3JlZSI6NDEsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJjZW50ZXJfZGVsYXkiOjIsImRlZl95YXdfbGVmdCI6MH0seyJlbmFibGUiOmZhbHNlLCJib2R5c2xpZGUiOjAsImRlZmFhX2VuYiI6ZmFsc2UsInBpdGNoIjoiRG93biIsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwiZGVmX3lhd19tYXhfZ2VuIjoyMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWxheSI6MSwiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6MCwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfb2Zmc2V0IjowLCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwiZm9yY2VfZGVmZW5zaXZlIjpmYWxzZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJyaWdodCI6MCwibGVmdCI6MCwieWF3dHlwZSI6IkxcL1IiLCJkZWZfeWF3IjoiT2ZmIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJib2R5eWF3IjoiTm9uZSIsImRlZl9waXRjaCI6MCwiZGVmX3lhd19zcGVlZCI6NCwiZGVncmVlIjo0MSwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImNlbnRlcl9kZWxheSI6MiwiZGVmX3lhd19sZWZ0IjowfSx7ImVuYWJsZSI6dHJ1ZSwiYm9keXNsaWRlIjowLCJkZWZhYV9lbmIiOmZhbHNlLCJwaXRjaCI6IkRvd24iLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWF4X2dlbiI6MjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVsYXkiOjEsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X29mZnNldCI6MCwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwicmlnaHQiOjAsImxlZnQiOjAsInlhd3R5cGUiOiJMXC9SIiwiZGVmX3lhdyI6Ik9mZiIsImRlZl9waXRjaF9zcGVlZCI6MiwiYm9keXlhdyI6Ik5vbmUiLCJkZWZfcGl0Y2giOjAsImRlZl95YXdfc3BlZWQiOjQsImRlZ3JlZSI6NDEsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJjZW50ZXJfZGVsYXkiOjIsImRlZl95YXdfbGVmdCI6MH0seyJlbmFibGUiOmZhbHNlLCJib2R5c2xpZGUiOjAsImRlZmFhX2VuYiI6ZmFsc2UsInBpdGNoIjoiRG93biIsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwiZGVmX3lhd19tYXhfZ2VuIjoyMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWxheSI6MSwiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6MCwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfb2Zmc2V0IjowLCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwiZm9yY2VfZGVmZW5zaXZlIjpmYWxzZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJyaWdodCI6MCwibGVmdCI6MCwieWF3dHlwZSI6IkxcL1IiLCJkZWZfeWF3IjoiT2ZmIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJib2R5eWF3IjoiTm9uZSIsImRlZl9waXRjaCI6MCwiZGVmX3lhd19zcGVlZCI6NCwiZGVncmVlIjo0MSwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImNlbnRlcl9kZWxheSI6MiwiZGVmX3lhd19sZWZ0IjowfV0sInNhZmVfaGVhZCI6dHJ1ZX0sImFpbWJvdCI6eyJwcmVkaWN0X3JlbmRlcl9ib3giOmZhbHNlLCJwcmVkaWN0X2JveF9jb2xvciI6IiMyRjc1RERGRiIsInVuc2FmZV9jaGFyZ2UiOnRydWUsImp1bXBfc2NvdXQiOnRydWUsImF1dG9fb3Nfc3RhdGVzIjpbIlN0YW5kaW5nIiwiU2xvdyBXYWxrIiwiQ3JvdWNoIiwiTW92ZS1Dcm91Y2giXSwicmVzb2x2ZXIiOnRydWUsImF1dG9fb3MiOmZhbHNlLCJwcmVkaWN0IjpmYWxzZSwiYXV0b19vc193ZWFwb25zIjpbIlNjb3V0Il0sInByZWRpY3RfbG93ZXJfNDBtcyI6ZmFsc2UsInByZWRpY3RfaG90a2V5IjpbIk9uIGhvdGtleSIsMF0sInByZWRpY3RfZGlzYWJsZV9sYyI6ZmFsc2V9LCJ2aXN1YWwiOnsid2F0ZXJtYXJrX2N1c3RvbSI6IiIsInZtX3oiOi0xNSwidm1feSI6LTcxLCJ2aWV3bW9kZWwiOnRydWUsImFzcGVjdF92YWwiOjE2NCwibm90aWZpY2F0aW9ucyI6dHJ1ZSwid2F0ZXJtYXJrIjpmYWxzZSwic2NvcGVfbGluZXMiOnRydWUsImNyb3NzaGFpciI6dHJ1ZSwidm1fZm92Ijo1OCwiYXNwZWN0X3JhdGlvIjp0cnVlLCJ3YXRlcm1hcmtfbmlja25hbWUiOiJTdGVhbSIsImFjY2VudF9jb2xvciI6IiNGRkZGRkY3MiIsImRhbWFnZSI6dHJ1ZSwiYXJyb3dzIjpmYWxzZSwidm1feCI6NSwid2F0ZXJtYXJrX2VsZW1lbnRzIjpbIk5pY2tuYW1lIiwiRnJhbWVzIFBlciBTZWNvbmQiLCJQaW5nIiwiVGlja3JhdGUiLCJUaW1lIl19LCJtaXNjIjp7ImRyb3BfZ3JlbmFkZXMiOmZhbHNlLCJkcm9wX2dyZW5hZGVzX3NlbGVjdGlvbiI6e30sImFtbV9icmVha2VyIjp0cnVlLCJjbGFudGFnIjpmYWxzZSwidHJhc2h0YWxrX2xhbmd1YWdlIjoiQmFpdCIsInRyYXNodGFsayI6dHJ1ZSwiY29uc29sZV9maWx0ZXIiOnRydWUsImFtbV9icmVha2VyX3R5cGUiOiJTdGF0aWMiLCJmYXN0X2xhZGRlciI6dHJ1ZSwidHJhc2h0YWxrX2V2ZW50cyI6WyJLaWxsIiwiRGVhdGgiXSwiZHJvcF9ncmVuYWRlc19ob3RrZXkiOlsiT24gaG90a2V5IiwwXX19LCJuYW1lIjoiMSJ9",
            protected = true
        }
    }
}
do
    configs.compile = function(data)
        if data == nil then
            print('[Althea] An error occured with config!')
            return
        end
        
        local success, encoded = pcall(function()
            return base64.encode(json.stringify(data))
        end)
        
        if not success then
            print('[Althea] An error occured with config!')
            return
        end
        
        return ("Althea::gs::%s"):format(encoded:gsub("=", "_"):gsub("+", "Z1337Z"))
    end
    
    configs.decompile = function(data)
        if data == nil then
            return false, 'Config data is nil'
        end
        
        if not data:find("Althea::gs::") then
            return false, 'Invalid config format'
        end
        
        local clean_data = data:gsub("Althea::gs::", ""):gsub("_", "="):gsub("Z1337Z", "+")
        
        local success, decoded = pcall(function()
            local base64_decoded = base64.decode(clean_data)
            
            if _G.json and _G.json.decode then
                local json_decoded = _G.json.decode(base64_decoded)
                return json_decoded
            else
                local json_decoded = json.parse(base64_decoded)
                return json_decoded
            end
        end)
        
        if not success then
            return false, decoded
        end
        
        if decoded == nil then
            return false, 'Decoded config is nil'
        end
        
        return true, decoded
    end
    
    configs.load = function(id, tab)
        local db_data = configs.db[id]
        
        if db_data == nil then
            print('[Althea] Config not selected or something went wrong with database!')
            return
        end
        
        if db_data.data == nil or db_data.data == "" then
            print('[Althea] An error occured with database!')
            return
        end
        
        if id > #configs.db then
            print('[Althea] An error occured with database!')
            return
        end
        
        local name = db_data.name
        local data = db_data.data
        
        configs.data:load(data, tab)
    end
    
    configs.save = function(id)
        local db_data = configs.db[id]
        
        if db_data == nil then
            print('[Althea] Config not selected or something went wrong with database!')
            return
        end
        
        local name = db_data.name
        
        configs.db[id].data = configs.data:save()
        db.write("configs", configs.db)
    end
    
    configs.export = function(id)
        local db_data = configs.db[id]
        
        if db_data == nil then
            print('[Althea] Config not selected or something went wrong with database!')
            return
        end
        
        local name = db_data.name
        local data = configs.compile(db_data)
        
        if clipboard then
            clipboard.set(data)
            print('[Althea] ' .. name .. ' successfully exported!')
        end
    end
    
    configs.remove = function(id)
        local db_data = configs.db[id]
        
        if db_data == nil then
            print('[Althea] Config not selected or something went wrong with database!')
            return
        end
        
        local name = db_data.name
        
        table.remove(configs.db, id)
        db.write("configs", configs.db)
        
        print('[Althea] ' .. name .. ' successfully removed!')
    end
    
    configs.create = function(name, author, data)
        if type(name) ~= "string" then
            print('[Althea] An error occured with config!')
            return
        end
        
        if name == nil then
            print('[Althea] Name of config is invalid!')
            return
        end
        
        if #name == 0 or string.match(name, "%s%s") then
            print('[Althea] Name of config is empty!')
            return
        end
        
        if #name > 24 then
            print('[Althea] Name of config is too long!')
            return
        end
        

        if author == nil or author == "" then
            author = get_username()
        end
        
        local already_created = function()
            local val = true
            
            for i = 1, #configs.db do
                val = val and name ~= configs.db[i].name
            end
            
            return val
        end
        
        if not already_created() then
            print('[Althea] ' .. name .. ' is already created!')
            return
        end
        
        if #configs.db > configs.maximum_count then
            print('[Althea] Too much configs!')
            return
        end
        
        table.insert(configs.db, {
            name = name,
            author = author,
            data = data
        })
        
        db.write("configs", configs.db)
        
        print('[Althea] ' .. name .. ' successfully created!')
    end
    
    configs.import = function()
        if not clipboard then
            print('[Althea] Clipboard not available!')
            return
        end
        
        local clipboard_data = clipboard.get()
        
        if clipboard_data == nil then
            print('[Althea] An error occured with config!')
            return
        end
        
        local success, decompiled = configs.decompile(clipboard_data)
        
        if not success or decompiled == nil then
            print('[Althea] An error occured with config!')
            return
        end
        
        local name = decompiled.name
        local author = decompiled.author
        local data = decompiled.data
        
        if #configs.db > configs.maximum_count then
            print('[Althea] Too much configs!')
            return
        end
        
        table.insert(configs.db, {
            name = name,
            author = author,
            data = data
        })
        
        db.write("configs", configs.db)
        
        print('[Althea] ' .. name .. ' successfully imported!')
    end
    
    configs.update_list = function()
    end
end

local presets = {}

presets.config_type = menu.group.main:combobox('Config type', {'Local', 'Staff'})
presets.config_name = menu.group.main:textbox('Config name')
presets.space1 = menu.group.main:label(' ')
presets.list = menu.group.main:listbox('Configs', {'Empty configs list'})
presets.space2 = menu.group.main:label(' ')

configs.update_list = function()

    configs.db = db.read("configs") or {}
    
    local tmp = {}
    
    if presets.config_type:get() == 'Local' then
        for _, configuration in pairs(configs.db) do
            table.insert(tmp, ("%s • %s"):format(configuration.name, configuration.author))
        end
    elseif presets.config_type:get() == 'Staff' then
        table.insert(tmp, "Default")
        table.insert(tmp, "Coder")
    end
    
    presets.list:update(#tmp ~= 0 and tmp or {"Empty configs list"})
end

presets.load = menu.group.main:button('Load', function()
    local key = presets.list:get() + 1
    
    if presets.config_type:get() == 'Local' then
        configs.load(key)
    elseif presets.config_type:get() == 'Staff' then
        local staff_key = presets.list:get()
        if staff_key == 1 then

            local coder_config = "Althea::gs::eyJkYXRhIjp7ImFudGlhaW0iOnsiYnVpbGRlciI6W3siZW5hYmxlIjpmYWxzZSwieWF3X3R5cGUiOiIxODAiLCJwaXRjaCI6Ik9mZiIsImRlZmFhX2VuYiI6ZmFsc2UsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwiZGVmX3lhd19taW5fZ2VuIjotMjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVmX3lhd19tYXhfZ2VuIjoyMCwiZGVmX3BpdGNoX21heCI6MCwieWF3X2xyX2RlbGF5IjoyLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfeWF3X3NwZWVkIjo0LCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwiZm9yY2VfZGVmZW5zaXZlIjpmYWxzZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJkZWZfeWF3X3JpZ2h0IjowLCJkZWZfeWF3X2xlZnQiOjAsInlhdyI6MCwiZGVmX3lhd19vZmZzZXQiOjAsImRlZl95YXciOiJPZmYiLCJkZWZfcGl0Y2hfc3BlZWQiOjIsImRlZl9waXRjaCI6MCwieWF3bW9kaWZlciI6Ik9mZiIsImRlZ3JlZSI6MCwieWF3X2xlZnQiOjAsImNlbnRlcl9kZWxheSI6MiwieWF3X3JpZ2h0IjowfSx7ImVuYWJsZSI6dHJ1ZSwieWF3X3R5cGUiOiIxODAiLCJwaXRjaCI6IkRlZmF1bHQiLCJkZWZhYV9lbmIiOnRydWUsImRlZl9waXRjaF9tb2RlIjoiU3BpbiIsImRlZl95YXdfbWluX2dlbiI6LTIwLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlZl95YXdfbWF4X2dlbiI6MjAsImRlZl9waXRjaF9tYXgiOjAsInlhd19scl9kZWxheSI6MiwiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwiZGVmX3lhd19zcGVlZCI6NCwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImRlZl95YXdfbGVmdF9yaWdodCI6dHJ1ZSwiZm9yY2VfZGVmZW5zaXZlIjp0cnVlLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZl95YXdfcmlnaHQiOjkwLCJkZWZfeWF3X2xlZnQiOi05MCwieWF3IjowLCJkZWZfeWF3X29mZnNldCI6NzksImRlZl95YXciOiIxODAiLCJkZWZfcGl0Y2hfc3BlZWQiOjYsImRlZl9waXRjaCI6LTI0LCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVncmVlIjotMzcsInlhd19sZWZ0IjowLCJjZW50ZXJfZGVsYXkiOjMsInlhd19yaWdodCI6MH0seyJlbmFibGUiOnRydWUsInlhd190eXBlIjoiMTgwIiwicGl0Y2giOiJEZWZhdWx0IiwiZGVmYWFfZW5iIjp0cnVlLCJkZWZfcGl0Y2hfbW9kZSI6IlNwaW4iLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWZfeWF3X21heF9nZW4iOjIwLCJkZWZfcGl0Y2hfbWF4IjowLCJ5YXdfbHJfZGVsYXkiOjIsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl95YXdfc3BlZWQiOjI2LCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwiZm9yY2VfZGVmZW5zaXZlIjp0cnVlLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbGVmdCI6MCwieWF3IjowLCJkZWZfeWF3X29mZnNldCI6MCwiZGVmX3lhdyI6IlNwaW4iLCJkZWZfcGl0Y2hfc3BlZWQiOjcsImRlZl9waXRjaCI6NTEsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWdyZWUiOi04MSwieWF3X2xlZnQiOjAsImNlbnRlcl9kZWxheSI6MiwieWF3X3JpZ2h0IjowfSx7ImVuYWJsZSI6dHJ1ZSwieWF3X3R5cGUiOiIxODAiLCJwaXRjaCI6IkRvd24iLCJkZWZhYV9lbmIiOmZhbHNlLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWluX2dlbiI6LTIwLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlZl95YXdfbWF4X2dlbiI6MjAsImRlZl9waXRjaF9tYXgiOjAsInlhd19scl9kZWxheSI6MiwiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwiZGVmX3lhd19zcGVlZCI6NCwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwiZGVmX3lhd19yaWdodCI6MCwiZGVmX3lhd19sZWZ0IjowLCJ5YXciOjAsImRlZl95YXdfb2Zmc2V0IjowLCJkZWZfeWF3IjoiT2ZmIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfcGl0Y2giOjAsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWdyZWUiOi00OCwieWF3X2xlZnQiOi0zMCwiY2VudGVyX2RlbGF5IjoyLCJ5YXdfcmlnaHQiOjM0fSx7ImVuYWJsZSI6dHJ1ZSwieWF3X3R5cGUiOiIxODAiLCJwaXRjaCI6Ik1pbmltYWwiLCJkZWZhYV9lbmIiOnRydWUsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwiZGVmX3lhd19taW5fZ2VuIjotMjAsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVmX3lhd19tYXhfZ2VuIjoyMCwiZGVmX3BpdGNoX21heCI6MCwieWF3X2xyX2RlbGF5IjoyLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJkZWZfeWF3X3NwZWVkIjo0LCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiZGVmX3lhd19sZWZ0X3JpZ2h0Ijp0cnVlLCJmb3JjZV9kZWZlbnNpdmUiOnRydWUsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwiZGVmX3lhd19yaWdodCI6LTkwLCJkZWZfeWF3X2xlZnQiOjkwLCJ5YXciOjAsImRlZl95YXdfb2Zmc2V0IjowLCJkZWZfeWF3IjoiMTgwIiwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfcGl0Y2giOi04OSwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZ3JlZSI6LTQ2LCJ5YXdfbGVmdCI6MCwiY2VudGVyX2RlbGF5IjoyLCJ5YXdfcmlnaHQiOjB9LHsiZW5hYmxlIjp0cnVlLCJ5YXdfdHlwZSI6IjE4MCIsInBpdGNoIjoiRG93biIsImRlZmFhX2VuYiI6dHJ1ZSwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWZfeWF3X21heF9nZW4iOjIwLCJkZWZfcGl0Y2hfbWF4IjowLCJ5YXdfbHJfZGVsYXkiOjIsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl95YXdfc3BlZWQiOjMwLCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiZGVmX3lhd19sZWZ0X3JpZ2h0IjpmYWxzZSwiZm9yY2VfZGVmZW5zaXZlIjp0cnVlLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZl95YXdfcmlnaHQiOjE1OCwiZGVmX3lhd19sZWZ0IjotMTMxLCJ5YXciOjAsImRlZl95YXdfb2Zmc2V0IjotMTIwLCJkZWZfeWF3IjoiU3BpbiIsImRlZl9waXRjaF9zcGVlZCI6MiwiZGVmX3BpdGNoIjotODksInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWdyZWUiOi02NiwieWF3X2xlZnQiOjAsImNlbnRlcl9kZWxheSI6MiwieWF3X3JpZ2h0IjowfSx7ImVuYWJsZSI6dHJ1ZSwieWF3X3R5cGUiOiIxODAiLCJwaXRjaCI6IkRvd24iLCJkZWZhYV9lbmIiOmZhbHNlLCJkZWZfcGl0Y2hfbW9kZSI6IlN0YXRpYyIsImRlZl95YXdfbWluX2dlbiI6LTIwLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlZl95YXdfbWF4X2dlbiI6MjAsImRlZl9waXRjaF9tYXgiOjAsInlhd19scl9kZWxheSI6MiwiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwiZGVmX3lhd19zcGVlZCI6NCwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImRlZl95YXdfbGVmdF9yaWdodCI6ZmFsc2UsImZvcmNlX2RlZmVuc2l2ZSI6dHJ1ZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJkZWZfeWF3X3JpZ2h0IjowLCJkZWZfeWF3X2xlZnQiOjAsInlhdyI6MCwiZGVmX3lhd19vZmZzZXQiOjAsImRlZl95YXciOiJPZmYiLCJkZWZfcGl0Y2hfc3BlZWQiOjIsImRlZl9waXRjaCI6MCwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZ3JlZSI6LTQzLCJ5YXdfbGVmdCI6MCwiY2VudGVyX2RlbGF5IjoyLCJ5YXdfcmlnaHQiOjB9LHsiZW5hYmxlIjp0cnVlLCJ5YXdfdHlwZSI6IjE4MCIsInBpdGNoIjoiRG93biIsImRlZmFhX2VuYiI6dHJ1ZSwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWZfeWF3X21heF9nZW4iOjIwLCJkZWZfcGl0Y2hfbWF4IjowLCJ5YXdfbHJfZGVsYXkiOjIsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl95YXdfc3BlZWQiOjMwLCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiZGVmX3lhd19sZWZ0X3JpZ2h0Ijp0cnVlLCJmb3JjZV9kZWZlbnNpdmUiOnRydWUsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwiZGVmX3lhd19yaWdodCI6MTQ1LCJkZWZfeWF3X2xlZnQiOi0xNDksInlhdyI6MCwiZGVmX3lhd19vZmZzZXQiOjAsImRlZl95YXciOiIxODAiLCJkZWZfcGl0Y2hfc3BlZWQiOjIsImRlZl9waXRjaCI6LTQ0LCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVncmVlIjotNjYsInlhd19sZWZ0IjowLCJjZW50ZXJfZGVsYXkiOjIsInlhd19yaWdodCI6MH0seyJlbmFibGUiOmZhbHNlLCJ5YXdfdHlwZSI6IjE4MCIsInBpdGNoIjoiT2ZmIiwiZGVmYWFfZW5iIjpmYWxzZSwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWZfeWF3X21heF9nZW4iOjIwLCJkZWZfcGl0Y2hfbWF4IjowLCJ5YXdfbHJfZGVsYXkiOjIsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsImRlZl95YXdfc3BlZWQiOjQsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJkZWZfeWF3X2xlZnRfcmlnaHQiOmZhbHNlLCJmb3JjZV9kZWZlbnNpdmUiOmZhbHNlLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZl95YXdfcmlnaHQiOjAsImRlZl95YXdfbGVmdCI6MCwieWF3IjowLCJkZWZfeWF3X29mZnNldCI6MCwiZGVmX3lhdyI6Ik9mZiIsImRlZl9waXRjaF9zcGVlZCI6MiwiZGVmX3BpdGNoIjowLCJ5YXdtb2RpZmVyIjoiT2ZmIiwiZGVncmVlIjowLCJ5YXdfbGVmdCI6MCwiY2VudGVyX2RlbGF5IjoyLCJ5YXdfcmlnaHQiOjB9XSwib3B0aW9ucyI6WyJFZGdlIE9uIEZEIiwiU2FmZSBLbmlmZSIsIlNhZmUgWmV1cyJdLCJzdGF0ZSI6Ilx1MDAwYkdsb2JhbFxyIiwiYWFwaWNrIjoiQnVpbGRlciIsInNhZmVoZWFkIjp0cnVlLCJrZXlfbGVmdCI6WyJPbiBob3RrZXkiLDkwXSwiZmFzdGxhZGRlciI6dHJ1ZSwia2V5X3Jlc2V0IjpbIk9uIGhvdGtleSIsMF0sImtleV9mcmVlc3RhbmQiOlsiT24gaG90a2V5IiwxOF0sImFudGliYWNrc3RhYiI6dHJ1ZSwia2V5X3JpZ2h0IjpbIk9uIGhvdGtleSIsNjddfSwiYWltYm90Ijp7InVuc2FmZV9jaGFyZ2UiOnRydWUsInJhZ2VfZm9yY2VfYmFpbSI6WyJMZXRoYWwiXSwianVtcF9zY291dCI6dHJ1ZSwiYXV0b19vc19zdGF0ZXMiOlsiU2xvdyBXYWxrIiwiTW92ZS1Dcm91Y2giXSwicmFnZV9mb3JjZV9zYWZldHkiOnt9LCJhdXRvX29zIjp0cnVlLCJyYWdlX2ZvcmNlX3NhZmV0eV9taXNzIjoxLCJyZXNvbHZlciI6dHJ1ZSwiYXV0b19vc193ZWFwb25zIjpbIlNjb3V0IiwiRGVzZXJ0IEVhZ2xlIl0sInJlc29sdmVyX3R5cGUiOiJKaXR0ZXIiLCJyYWdlX2xvZ2ljIjpbIkZvcmNlIGJvZHkgYWltIiwiQXV0byBkZWxheSBzaG90Il0sInJhZ2VfZGVsYXlfc2hvdCI6WyJJbmFjY3VyYWN5IiwiRW5lbXkgZGVmZW5zaXZlIl0sInJhZ2VfZm9yY2VfYmFpbV9taXNzIjoxfSwidmlzdWFsIjp7IndhdGVybWFya19kaXNwbGF5IjpbIk5pY2siLCJLRCIsIkZQUyIsIlBpbmciLCJUaW1lIl0sInNjcmVlbl9pbmRpY2F0b3JzIjp0cnVlLCJub3RpZmljYXRpb25zX3R5cGUiOnt9LCJ3YXRlcm1hcmtfc3R5bGUiOiJHUyIsIndhdGVybWFya19nc19jb2xvciI6IiM0OUI2RkY2NCIsIm5vdGlmaWNhdGlvbnNfY29sb3IiOiIjQTBGMEE5RkYiLCJzY3JlZW5faW5kaWNhdG9yc19jIjoiI0ZGRkZGRkZGIiwic2NyZWVuX2luZGljYXRvcnNfZ2xvdyI6dHJ1ZSwibm90aWZpY2F0aW9ucyI6ZmFsc2UsIndhdGVybWFyayI6dHJ1ZSwid2F0ZXJtYXJrX2dzX2xpbmUiOiJTb2xpZCIsInNjb3BlX2dhcCI6MywiZGFtYWdlIjp0cnVlLCJzY29wZV9zaXplIjo2NywiYXNwZWN0X3ZhbCI6MTk5LCJkYW1hZ2VfZm9udCI6IkRlZmF1bHQiLCJkYW1hZ2VfY29sb3IiOiIjRkZGRkZGRkYiLCJ2bV9mb3YiOjM3LCJhc3BlY3RfcmF0aW8iOnRydWUsInZtX3oiOi0xMiwidm1feSI6LTQ5LCJzY29wZV9pbnZlcnQiOmZhbHNlLCJ2aWV3bW9kZWwiOnRydWUsInNjb3BlX2NvbG9yIjoiIzgxODE4MTc1Iiwidm1feCI6NCwic2NvcGVfbGluZXMiOnRydWUsIndhdGVybWFya19wb3NpdGlvbiI6IlRvcCBSaWdodCIsImFycm93c19jb2xvciI6IiNBMEYwQTlGRiIsImFycm93cyI6ZmFsc2UsInZtX2ZsaXBfa25pZmUiOnRydWV9LCJtaXNjIjp7ImJ1eWJvdF9wcmltYXJ5IjoiU2NvdXQiLCJidXlib3Rfc2Vjb25kYXJ5IjoiTm9uZSIsImNsYW50YWciOmZhbHNlLCJ0cmFzaHRhbGtfbGFuZ3VhZ2UiOiJSdXNzaWFuIiwiZmFzdF9sYWRkZXIiOnRydWUsInRyYXNodGFsayI6dHJ1ZSwiY29uc29sZV9maWx0ZXIiOnRydWUsImFuaW1hdGlvbl9icmVha2VyIjp7ImluX2Fpcl9zdGF0aWNfdmFsdWUiOjEwMCwiZWFydGhxdWFrZV92YWx1ZSI6MTAwLCJhZGp1c3RfbGVhbiI6MCwib25ncm91bmRfaml0dGVyX21pbl92YWx1ZSI6NTAsIm9uZ3JvdW5kX2xlZ3MiOiJKaXR0ZXIiLCJwaXRjaF9vbl9sYW5kIjpmYWxzZSwiaW5fYWlyX2xlZ3MiOiJNb29ud2FsayIsImVhcnRocXVha2UiOmZhbHNlLCJlbmFibGVkIjp0cnVlLCJvbmdyb3VuZF9qaXR0ZXJfbWF4X3ZhbHVlIjo1MH0sImJ1eWJvdF9lcXVpcG1lbnQiOlsiVGFzZXIiLCJLZXZsYXIiLCJIZWxtZXQiLCJEZWZ1c2VyIl0sImJ1eWJvdF9lbmFibGVkIjp0cnVlLCJidXlib3RfdXRpbGl0eSI6WyJIRSIsIlNtb2tlIiwiTW9sb3RvdiJdLCJ0cmFzaHRhbGtfZXZlbnRzIjpbIktpbGwiLCJEZWF0aCJdLCJidXlib3RfcGlzdG9sX2tldmxhciI6dHJ1ZX19LCJuYW1lIjoiR0FMQVhZIiwiYXV0aG9yIjoiYWRtaW4ifQ__"
            local success, decompiled = configs.decompile(coder_config)
            if success and decompiled and decompiled.data then
                client.delay_call(0.2, function()
                    if configs.data and configs.data.load then
                        local load_ok = pcall(function()
                            configs.data:load(decompiled.data)
                        end)
                        if not load_ok then
                            print('[Althea] Failed to apply config')
                        end
                    else
                        print('[Althea] Config system not ready')
                    end
                end)
            else
                print('[Althea] Failed to decode config')
            end
        else
        local default_config = "Althea::gs::eyJkYXRhIjp7ImFudGlhaW0iOnsiYnVpbGRlciI6W3siZW5hYmxlIjpmYWxzZSwicGl0Y2giOiJEb3duIiwiZGVmYWFfZW5iIjpmYWxzZSwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJza2l0dGVyX29mZnNldCI6LTEsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6OTAsImRlZl95YXdfbWF4X2dlbiI6MjAsImRlZl95YXdfc3BlZWQiOjQsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsIm9mZnNldF92YWx1ZSI6NzMsImZvcmNlX2RlZmVuc2l2ZSI6ZmFsc2UsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfbGVmdCI6LTkwLCJ5YXciOjAsImRlZl95YXdfb2Zmc2V0IjowLCJkZWZfcGl0Y2hfc3BlZWQiOjIsImRlZl95YXciOiJPZmYiLCJkZWZfcGl0Y2giOjg5LCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVncmVlIjotNDksImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJjZW50ZXJfZGVsYXkiOjcsImRlZl95YXdfbGVmdF9yaWdodCI6dHJ1ZX0seyJlbmFibGUiOnRydWUsInBpdGNoIjoiRG93biIsImRlZmFhX2VuYiI6ZmFsc2UsImRlZl9waXRjaF9tb2RlIjoiU3dheSIsInNraXR0ZXJfb2Zmc2V0IjotMSwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWZfcGl0Y2hfbWF4IjowLCJkZWZfeWF3X3JpZ2h0Ijo5MCwiZGVmX3lhd19tYXhfZ2VuIjoyMCwiZGVmX3lhd19zcGVlZCI6NCwiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwib2Zmc2V0X3ZhbHVlIjo3MywiZm9yY2VfZGVmZW5zaXZlIjpmYWxzZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwiZGVmX3lhd19sZWZ0IjotOTAsInlhdyI6MCwiZGVmX3lhd19vZmZzZXQiOjAsImRlZl9waXRjaF9zcGVlZCI6MywiZGVmX3lhdyI6IjE4MCIsImRlZl9waXRjaCI6LTMwLCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVncmVlIjotNTYsImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJjZW50ZXJfZGVsYXkiOjIsImRlZl95YXdfbGVmdF9yaWdodCI6dHJ1ZX0seyJlbmFibGUiOnRydWUsInBpdGNoIjoiRG93biIsImRlZmFhX2VuYiI6dHJ1ZSwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJza2l0dGVyX29mZnNldCI6LTEsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6OTAsImRlZl95YXdfbWF4X2dlbiI6MjAsImRlZl95YXdfc3BlZWQiOjQsImRlZl95YXdfZ2VuZXJhdGlvbiI6ZmFsc2UsIm9mZnNldF92YWx1ZSI6NzMsImZvcmNlX2RlZmVuc2l2ZSI6dHJ1ZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwiZGVmX3lhd19sZWZ0IjotOTAsInlhdyI6MCwiZGVmX3lhd19vZmZzZXQiOjAsImRlZl9waXRjaF9zcGVlZCI6MiwiZGVmX3lhdyI6IjE4MCIsImRlZl9waXRjaCI6LTQ3LCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVncmVlIjotNDksImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJjZW50ZXJfZGVsYXkiOjcsImRlZl95YXdfbGVmdF9yaWdodCI6dHJ1ZX0seyJlbmFibGUiOnRydWUsInBpdGNoIjoiRG93biIsImRlZmFhX2VuYiI6ZmFsc2UsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwic2tpdHRlcl9vZmZzZXQiOi0xLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjkwLCJkZWZfeWF3X21heF9nZW4iOjIwLCJkZWZfeWF3X3NwZWVkIjo0LCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJvZmZzZXRfdmFsdWUiOjczLCJmb3JjZV9kZWZlbnNpdmUiOmZhbHNlLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X2xlZnQiOi05MCwieWF3IjowLCJkZWZfeWF3X29mZnNldCI6MCwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfeWF3IjoiT2ZmIiwiZGVmX3BpdGNoIjo4OSwieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZ3JlZSI6LTYzLCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiY2VudGVyX2RlbGF5IjozLCJkZWZfeWF3X2xlZnRfcmlnaHQiOnRydWV9LHsiZW5hYmxlIjp0cnVlLCJwaXRjaCI6IkRvd24iLCJkZWZhYV9lbmIiOnRydWUsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwic2tpdHRlcl9vZmZzZXQiOi0xLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjkwLCJkZWZfeWF3X21heF9nZW4iOjIwLCJkZWZfeWF3X3NwZWVkIjo0LCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJvZmZzZXRfdmFsdWUiOjczLCJmb3JjZV9kZWZlbnNpdmUiOnRydWUsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfbGVmdCI6LTkwLCJ5YXciOjAsImRlZl95YXdfb2Zmc2V0IjowLCJkZWZfcGl0Y2hfc3BlZWQiOjIsImRlZl95YXciOiIxODAiLCJkZWZfcGl0Y2giOjAsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWdyZWUiOi00OSwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImNlbnRlcl9kZWxheSI6NywiZGVmX3lhd19sZWZ0X3JpZ2h0Ijp0cnVlfSx7ImVuYWJsZSI6dHJ1ZSwicGl0Y2giOiJEb3duIiwiZGVmYWFfZW5iIjp0cnVlLCJkZWZfcGl0Y2hfbW9kZSI6IkppdHRlciIsInNraXR0ZXJfb2Zmc2V0IjotMSwieWF3YmFzZSI6IkF0IHRhcmdldHMiLCJkZWZfcGl0Y2hfbWluIjowLCJkZWZfcGl0Y2hfbWF4Ijo4OSwiZGVmX3lhd19yaWdodCI6OTAsImRlZl95YXdfbWF4X2dlbiI6MjAsImRlZl95YXdfc3BlZWQiOjMwLCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJvZmZzZXRfdmFsdWUiOjczLCJmb3JjZV9kZWZlbnNpdmUiOnRydWUsImRlZl9waXRjaF9taW5fbWF4Ijp0cnVlLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwiZGVmX3lhd19sZWZ0IjotOTAsInlhdyI6MCwiZGVmX3lhd19vZmZzZXQiOjAsImRlZl9waXRjaF9zcGVlZCI6MTQsImRlZl95YXciOiJTcGluIiwiZGVmX3BpdGNoIjowLCJ5YXdtb2RpZmVyIjoiQ2VudGVyIiwiZGVncmVlIjotNDksImRlZl9waXRjaF9oZWlnaHRfYmFzZWQiOmZhbHNlLCJjZW50ZXJfZGVsYXkiOjcsImRlZl95YXdfbGVmdF9yaWdodCI6dHJ1ZX0seyJlbmFibGUiOnRydWUsInBpdGNoIjoiRG93biIsImRlZmFhX2VuYiI6ZmFsc2UsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwic2tpdHRlcl9vZmZzZXQiOi0xLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjkwLCJkZWZfeWF3X21heF9nZW4iOjIwLCJkZWZfeWF3X3NwZWVkIjo0LCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJvZmZzZXRfdmFsdWUiOjczLCJmb3JjZV9kZWZlbnNpdmUiOmZhbHNlLCJkZWZfcGl0Y2hfbWluX21heCI6ZmFsc2UsImRlZl95YXdfbWluX2dlbiI6LTIwLCJkZWZfeWF3X2xlZnQiOi05MCwieWF3IjowLCJkZWZfeWF3X29mZnNldCI6MCwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfeWF3IjoiMTgwIiwiZGVmX3BpdGNoIjotNDcsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWdyZWUiOi00OSwiZGVmX3BpdGNoX2hlaWdodF9iYXNlZCI6ZmFsc2UsImNlbnRlcl9kZWxheSI6MywiZGVmX3lhd19sZWZ0X3JpZ2h0Ijp0cnVlfSx7ImVuYWJsZSI6dHJ1ZSwicGl0Y2giOiJEb3duIiwiZGVmYWFfZW5iIjpmYWxzZSwiZGVmX3BpdGNoX21vZGUiOiJTdGF0aWMiLCJza2l0dGVyX29mZnNldCI6LTEsInlhd2Jhc2UiOiJBdCB0YXJnZXRzIiwiZGVmX3BpdGNoX21pbiI6MCwiZGVmX3BpdGNoX21heCI6MCwiZGVmX3lhd19yaWdodCI6MTI0LCJkZWZfeWF3X21heF9nZW4iOjIwLCJkZWZfeWF3X3NwZWVkIjoxNywiZGVmX3lhd19nZW5lcmF0aW9uIjpmYWxzZSwib2Zmc2V0X3ZhbHVlIjo3MywiZm9yY2VfZGVmZW5zaXZlIjpmYWxzZSwiZGVmX3BpdGNoX21pbl9tYXgiOmZhbHNlLCJkZWZfeWF3X21pbl9nZW4iOi0yMCwiZGVmX3lhd19sZWZ0IjotMTUyLCJ5YXciOjAsImRlZl95YXdfb2Zmc2V0IjowLCJkZWZfcGl0Y2hfc3BlZWQiOjIsImRlZl95YXciOiIxODAiLCJkZWZfcGl0Y2giOi00NywieWF3bW9kaWZlciI6IkNlbnRlciIsImRlZ3JlZSI6LTY2LCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiY2VudGVyX2RlbGF5Ijo1LCJkZWZfeWF3X2xlZnRfcmlnaHQiOnRydWV9LHsiZW5hYmxlIjp0cnVlLCJwaXRjaCI6IkRvd24iLCJkZWZhYV9lbmIiOnRydWUsImRlZl9waXRjaF9tb2RlIjoiU3RhdGljIiwic2tpdHRlcl9vZmZzZXQiOi0xLCJ5YXdiYXNlIjoiQXQgdGFyZ2V0cyIsImRlZl9waXRjaF9taW4iOjAsImRlZl9waXRjaF9tYXgiOjAsImRlZl95YXdfcmlnaHQiOjkwLCJkZWZfeWF3X21heF9nZW4iOjIwLCJkZWZfeWF3X3NwZWVkIjo0LCJkZWZfeWF3X2dlbmVyYXRpb24iOmZhbHNlLCJvZmZzZXRfdmFsdWUiOjczLCJmb3JjZV9kZWZlbnNpdmUiOnRydWUsImRlZl9waXRjaF9taW5fbWF4IjpmYWxzZSwiZGVmX3lhd19taW5fZ2VuIjotMjAsImRlZl95YXdfbGVmdCI6LTkwLCJ5YXciOi0xLCJkZWZfeWF3X29mZnNldCI6MCwiZGVmX3BpdGNoX3NwZWVkIjoyLCJkZWZfeWF3IjoiMTgwIiwiZGVmX3BpdGNoIjotNDcsInlhd21vZGlmZXIiOiJDZW50ZXIiLCJkZWdyZWUiOi0xLCJkZWZfcGl0Y2hfaGVpZ2h0X2Jhc2VkIjpmYWxzZSwiY2VudGVyX2RlbGF5Ijo3LCJkZWZfeWF3X2xlZnRfcmlnaHQiOnRydWV9XSwib3B0aW9ucyI6WyJFZGdlIE9uIEZEIiwiU2FmZSBLbmlmZSIsIn4iXSwic3RhdGUiOiJcdTAwMGJBZXJvYmljK1xyIiwiYWFwaWNrIjoiQnVpbGRlciIsInNhZmVoZWFkIjp0cnVlLCJrZXlfbGVmdCI6WzEsOTAsIn4iXSwiZmFzdGxhZGRlciI6dHJ1ZSwia2V5X3Jlc2V0IjpbMSwwLCJZ1337ZIl0sImtleV9mcmVlc3RhbmQiOlsxLDE4LCJZ1337ZIl0sImFudGliYWNrc3RhYiI6dHJ1ZSwia2V5X3JpZ2h0IjpbMSw2NywifiJdfSwiYWltYm90Ijp7InByZWRpY3RfcmVuZGVyX2JveCI6dHJ1ZSwicHJlZGljdF9ib3hfY29sb3IiOiIjMkY3NURERkYiLCJ1bnNhZmVfY2hhcmdlIjp0cnVlLCJqdW1wX3Njb3V0Ijp0cnVlLCJhdXRvX29zX3N0YXRlcyI6WyJTbG93IFdhbGsiLCJZ1337ZIl0sInJlc29sdmVyIjp0cnVlLCJhdXRvX29zIjp0cnVlLCJwcmVkaWN0IjpmYWxzZSwiYXV0b19vc193ZWFwb25zIjpbIlNjb3V0IiwifiJdLCJwcmVkaWN0X2xvd2VyXzQwbXMiOnRydWUsInByZWRpY3RfaG90a2V5IjpbMCwwLCJZ1337ZIl0sInByZWRpY3RfZGlzYWJsZV9sYyI6dHJ1ZX0sInZpc3VhbCI6eyJ2bV96IjotMjAsIm5vdGlmaWNhdGlvbnNfdHlwZSI6WyJDb25zb2xlIiwifiJdLCJ2bV95IjotMywidmlld21vZGVsIjp0cnVlLCJhc3BlY3RfdmFsIjoxNDUsIndhdGVybWFya19oZWFfY29sb3IiOiIjNjk4Nzk3MzEiLCJub3RpZmljYXRpb25zIjp0cnVlLCJkYW1hZ2VfY29sb3IiOiIjRkZGRkZGRkYiLCJzY29wZV9nYXAiOjcsInNjb3BlX2xpbmVzIjpmYWxzZSwic2NvcGVfc2l6ZSI6NDcsImNyb3NzaGFpciI6dHJ1ZSwidm1fZm92Ijo2OCwiYXNwZWN0X3JhdGlvIjp0cnVlLCJ3YXRlcm1hcmtfaGlkZV9sb2dvIjpmYWxzZSwid2F0ZXJtYXJrX25hbWUiOiIiLCJkYW1hZ2UiOnRydWUsInNjb3BlX2NvbG9yIjoiI0E5QTlBOUZGIiwic2NvcGVfaW52ZXJ0IjpmYWxzZSwidm1feCI6NSwiY3Jvc3NoYWlyX3N0eWxlIjoiRGVmYXVsdCIsImNyb3NzaGFpcl9hbHRfY29sb3IiOiIjNzI5MUEzRkYiLCJhcnJvd3MiOnRydWUsIndhdGVybWFyayI6ZmFsc2UsImFjY2VudF9jb2xvciI6IiMyRkI1RkZGRiJ9LCJtaXNjIjp7ImRyb3BfZ3JlbmFkZXMiOmZhbHNlLCJkcm9wX2dyZW5hZGVzX3NlbGVjdGlvbiI6WyJZ1337ZIl0sImFtbV9icmVha2VyIjp0cnVlLCJmYXN0X2xhZGRlciI6dHJ1ZSwiY2xhbnRhZ190eXBlIjoiU2VyZW5pdHkiLCJ0cmFzaHRhbGsiOnRydWUsImNvbnNvbGVfZmlsdGVyIjp0cnVlLCJjbGFudGFnIjp0cnVlLCJhbW1fYnJlYWtlcl90eXBlIjoiU3RhdGljIiwidHJhc2h0YWxrX2xhbmd1YWdlIjoiUnVzc2lhbiIsInRyYXNodGFsa19ldmVudHMiOlsiS2lsbCIsIkRlYXRoIiwifiJdLCJkcm9wX2dyZW5hZGVzX2hvdGtleSI6WzEsMCwifiJdfX0sIm5hbWUiOiIxIiwiYXV0aG9yIjoiYWRtaW4ifQ__"
        
        local success, decompiled = configs.decompile(default_config)
        
        if success and decompiled and decompiled.data then
            client.delay_call(0.2, function()
                if configs.data and configs.data.load then
                    local load_ok = pcall(function()
                        configs.data:load(decompiled.data)
                    end)
                    if not load_ok then
                        print('[Althea] Failed to apply config')
                    end
                else
                    print('[Althea] Config system not ready')
                end
            end)
        else
            print('[Althea] Failed to decode config')
        end
        end 
    end
    
    configs.update_list()
end)

presets.save = menu.group.main:button('Save', function()
    local key = presets.list:get() + 1
    
    if presets.config_type:get() == 'Local' then
        configs.save(key)
    else
        print('[Althea] Users configs are protected and cannot be saved!')
    end
    
    configs.update_list()
end)

presets.delete = menu.group.main:button('Delete', function()
    local key = presets.list:get() + 1
    
    if presets.config_type:get() == 'Local' then
        configs.remove(key)
    else
        print('[Althea] Protected config')
    end
    
    configs.update_list()
end)

presets.export = menu.group.main:button('Export', function()
    local key = presets.list:get() + 1
    configs.export(key)
    configs.update_list()
end)

presets.space3 = menu.group.main:label(' ')

presets.create = menu.group.main:button('Create New', function()
    if presets.config_type:get() == 'Local' then
        configs.create(presets.config_name:get(), loader_username, configs.data:save())
    else
        print('[Althea] Cannot create in Staff')
    end
    
    configs.update_list()
end)

presets.import = menu.group.main:button('Import', function()
    if presets.config_type:get() == 'Local' then
        configs.import()
    else
        print('[Althea] Cannot import in Users')
    end
    
    configs.update_list()
end)

presets.config_type:set_callback(function()
    configs.update_list()
end)

local visual = {
    watermark = menu.group.main:checkbox('Watermark'),
    watermark_style = menu.group.main:combobox('  Style', {'AL', 'GS', 'CE'}),
    watermark_al_color = menu.group.main:color_picker('  AL Accent', 76, 32, 255, 255),
    watermark_gs_color = menu.group.main:color_picker('  GS Accent', 160, 240, 169, 255),
    watermark_gs_line = menu.group.main:combobox('  GS Line type', {'Gradient', 'Solid'}),
    watermark_display = menu.group.main:multiselect('  Display', {'Nick', 'KD', 'FPS', 'Ping', 'Time'}),
    watermark_position = menu.group.main:combobox('  Position', {
        'Top Left',
        'Top Right',
        'Bottom Center'
    }),
    
    notifications = menu.group.main:checkbox('Notifications'),
    notifications_color = menu.group.main:color_picker('Notifications color', 160, 240, 169, 255),
    notifications_type = menu.group.main:multiselect('  Type', {'Console', 'Screen'}),
    
    screen_indicators = menu.group.main:checkbox('Screen indicators', {142, 165, 255}),
    screen_indicators_glow = menu.group.main:checkbox('  Glow behind'),
    
    arrows = menu.group.main:checkbox('Arrows'),
    arrows_color = menu.group.main:color_picker('Arrows color', 160, 240, 169, 255),
    
    scope_lines = menu.group.main:checkbox('Scope lines'),
    scope_gap = menu.group.main:slider('  Gap', 0, 100, 10, true, 'px'),
    scope_size = menu.group.main:slider('  Size', 5, 200, 20, true, 'px'),
    scope_invert = menu.group.main:checkbox('  Invert'),
    scope_color = menu.group.main:color_picker('  Scope color', 255, 255, 255, 255),
    
    damage = menu.group.main:checkbox('Damage'),
    damage_color = menu.group.main:color_picker('  Damage color', 255, 255, 255, 255),
    damage_font = menu.group.main:combobox('  Font', {'Small', 'Default', 'Bold', 'Large'}),
    
    viewmodel = menu.group.main:checkbox('Viewmodel'),
    vm_fov = menu.group.main:slider('  FOV', 0, 120, 68, true, '°'),
    vm_x = menu.group.main:slider('  X', -100, 100, 0, true, 'u', 0.1),
    vm_y = menu.group.main:slider('  Y', -100, 100, 0, true, 'u', 0.1),
    vm_z = menu.group.main:slider('  Z', -100, 100, -15, true, 'u', 0.1),
    vm_flip_knife = menu.group.main:checkbox('  Flip knife'),
    
    aspect_ratio = menu.group.main:checkbox('Aspect ratio'),
    aspect_val = menu.group.main:slider('  Value', -300, 300, 178, true, 'x', 0.01)
}


visual.accent_color = {
    get = function()
        local style = visual.watermark_style:get()
        if style == 'GS' then
            return visual.watermark_gs_color:get()
        elseif style == 'AL' then
            return visual.watermark_al_color:get()
        else
            return 76, 32, 255, 255
        end
    end,
    set_callback = function() end
}

local colors = {
    get_accent = function()
        local r, g, b, a = visual.accent_color.get()
        r, g, b, a = r or 255, g or 255, b or 255, a or 255
        return string.format('\a%02X%02X%02XFF', r, g, b)
    end,
    
    get_accent_rgba = function()
        return visual.accent_color.get()
    end,
    
    get_accent_hex = function()
        local r, g, b, a = visual.accent_color.get()
        r, g, b, a = r or 255, g or 255, b or 255, a or 255
        return string.format('%02X%02X%02X%02X', r, g, b, a)
    end
}

do
    local function update_pui_accent()
        local r, g, b, a = visual.accent_color.get()
        r, g, b, a = r or 255, g or 255, b or 255, a or 255
        pui.accent = string.format('%02X%02X%02X%02X', r, g, b, a)
        pui.macros.accent = string.format('\a%02X%02X%02XFF', r, g, b)
    end
    
    update_pui_accent()
    
    visual.watermark_al_color:set_callback(update_pui_accent)
    visual.watermark_gs_color:set_callback(update_pui_accent)
    visual.watermark_style:set_callback(update_pui_accent)
end

local loader_username = get_username()

local function get_welcome_text()
    local accent = colors.get_accent()
    return '\aFFFFFFFFWelcome, ' .. accent .. loader_username .. '\aFFFFFFFF!'
end

local info = {
    welcome = menu.group.fakelag:label(get_welcome_text()),
    build_source = menu.group.fakelag:label('Your build: Developer')
}

local aimbot = {
    resolver = menu.group.main:checkbox('Resolver'),
    resolver_type = menu.group.main:combobox('\n', {'Jitter', 'Defensive', '1000$'}),
    unsafe_charge = menu.group.main:checkbox('Unsafe Charge'),
    
    auto_os = menu.group.main:checkbox('Auto OS'),
    auto_os_weapons = menu.group.main:multiselect('Weapons', {
        'Auto Snipers',
        'AWP', 
        'Scout',
        'Desert Eagle',
        'Pistols',
        'SMG',
        'Rifles'
    }),
    auto_os_states = menu.group.main:multiselect('States', {
        'Standing',
        'Moving', 
        'Slow Walk',
        'Air',
        'Air-Crouch',
        'Crouch',
        'Move-Crouch'
    }),
    
    jump_scout = menu.group.main:checkbox('Jump Scout')
}

local aimbot_rage = {
    logic = menu.group.main:multiselect('Rage helper', {'Force body aim', 'Force safety', 'Auto delay shot'}),
    
    force_baim = menu.group.main:multiselect('Force body aim', {'Lethal', 'After x misses'}),
    force_baim_miss = menu.group.main:slider('After x misses (baim)', 0, 5, 1, true, 'x', 1, { [0] = 'Always' }),
    
    force_safety = menu.group.main:multiselect('Force safety', {'Lethal', 'After x misses'}),
    force_safety_miss = menu.group.main:slider('After x misses (safety)', 0, 5, 1, true, 'x', 1, { [0] = 'Always' }),
    
    delay_shot = menu.group.main:multiselect('Delay shot if', {'Inaccuracy', 'Enemy defensive'})
}

local aimbot_info = {
}

local antiaim = {
    states = {
        {"global", "\vGlobal\r", "\vG\r"},
        {"stand", "\vStand\r", "\vS\r"},
        {"walk", "\vWalking\r", "\vW\r"}, 
        {"run", "\vRunning\r", "\vR\r"},
        {"air", "\vAerobic\r", "\vA\r"}, 
        {"airduck", "\vAerobic+\r", "\vA+C\r"},
        {"crouch", "\vCrouch\r", "\vC\r"},
        {"duckmoving", "\vCrouchMove\r", "\vD+M\r"},
        {"fakelag", "\vFakelag\r", "\vFL\r"}, 
    },
}

local b_3 = {}
b_3.b_4 = function (t, r, k) local result = {} for i, v in ipairs(t) do n = k and v[k] or i result[n] = r == nil and i or v[r] end return result end

local enums = {
    states = b_3.b_4(antiaim.states, nil, 1),
    name_states = b_3.b_4(antiaim.states, 2),
    short_states = b_3.b_4(antiaim.states, 3),
}

local state_aa = enums.name_states

local b_2 = {}

b_2.aa = {
    aapick = menu.group.main:combobox("\n",{"Builder", "Other"} ),
    main = {
        labpick = menu.group.main:label("Builder"),
        labpickss = menu.group.main:label("\a373737FF‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"),
        state = menu.group.main:combobox("\n", state_aa),
    },
    advanced = {
        labpick1 = menu.group.main:label("Binds"),
        space = menu.group.main:label("\a373737FF‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"),
        key_left = menu.group.main:hotkey('Manual Left'),
        key_right = menu.group.main:hotkey('Manual Right'),
        key_reset = menu.group.main:hotkey('Manual Reset'),
        key_freestand = menu.group.main:hotkey('Freestanding'),
        spacee = menu.group.main:label("\n"),
        labpick2 = menu.group.main:label("Other"),
        space3 = menu.group.main:label("\a373737FF‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"),
        antibackstab = menu.group.main:checkbox("Anti-Backstab"),
        safehead = menu.group.main:checkbox("Safe Head"),
        options = menu.group.main:multiselect("\n",{"Edge On FD", "Safe Knife", "Safe Zeus"}),
        fastladder = menu.group.main:checkbox("God mode"),
    }
}



local builder = {}

for i=1, #state_aa do
    builder[i] = {    
        enable = menu.group.main:checkbox('Enable '..state_aa[i]),
        pitch = menu.group.main:combobox("Pitch \v»\r Type", {"Off", "Default", "Up", "Down", "Minimal", "Random"}),
        yawbase = menu.group.main:combobox("Yawbase \v»\r Type", {"At targets", "Local View"}),
        yaw_type = menu.group.main:combobox("Yaw \v»\r Type", {"180", "L/R"}),
        yaw = menu.group.main:slider("\v~\r Yaw", -180, 180, 0, true, "°"),
        yaw_left = menu.group.main:slider("\v~\r Yaw Left", -180, 180, 0, true, "°"),
        yaw_right = menu.group.main:slider("\v~\r Yaw Right", -180, 180, 0, true, "°"),
        yaw_lr_delay = menu.group.main:slider("\v~\r L/R Delay", 2, 14, 2, true, "t"),
        yawmodifer = menu.group.main:combobox("Yaw \v»\r Modifer", {"Off", "Center"}),
        degree = menu.group.main:slider("\v~\r Degree", -180, 180, 0, true,"°"),
        center_delay = menu.group.main:slider("\v~\r Center Delay", 2, 14, 2, true, "t"),
        
        force_defensive = menu.group.main:checkbox("Enable \vForce Defensive"),
        defaa_enb = menu.group.main:checkbox("Defensive Anti-Aim"),
        
        def_pitch_mode = menu.group.main:combobox("\vDefensive ·\r Pitch Mode", {"Static", "Spin", "Sway", "Jitter", "Cycling", "Random"}),
        def_pitch_speed = menu.group.main:slider("Pitch Speed", 1, 17, 2, true, "t"),
        def_pitch = menu.group.main:slider("Pitch", -89, 89, 0, true, "°"),
        def_pitch_min = menu.group.main:slider("Pitch Min", -89, 89, 0, true, "°"),
        def_pitch_max = menu.group.main:slider("Pitch Max", -89, 89, 0, true, "°"),
        def_pitch_min_max = menu.group.other:checkbox("Pitch Min-Max Mode"),
        def_pitch_height_based = menu.group.other:checkbox("Pitch Height Based"),
        
        def_yaw = menu.group.main:combobox("\vDefensive ·\r Yaw Type", {"Off", "180", "Spin", "Distortion", "Sway", "Freestand"}),
        def_yaw_speed = menu.group.main:slider("Yaw Speed", 1, 30, 4, true, "t"),
        def_yaw_offset = menu.group.main:slider("Yaw Offset", -180, 180, 0, true, "°"),
        def_yaw_left = menu.group.main:slider("Yaw Left", -180, 180, 0, true, "°"),
        def_yaw_right = menu.group.main:slider("Yaw Right", -180, 180, 0, true, "°"),
        def_yaw_min_gen = menu.group.main:slider("Yaw Min Gen", -180, 180, -20, true, "°"),
        def_yaw_max_gen = menu.group.main:slider("Yaw Max Gen", -180, 180, 20, true, "°"),
        def_yaw_left_right = menu.group.other:checkbox("Yaw Left-Right Mode"),
        def_yaw_generation = menu.group.main:checkbox("Yaw Generation"),
    }
end

local antiaim_state = {
    manual_direction = nil,
    freestanding_active = false,
    edge_yaw_active = false,
    last_manual_time = 0
}

local pitch_add = 0

local center_delay_data = {}
for i = 1, 9 do
    center_delay_data[i] = {
        tick = 0,
        inverted = 1
    }
end

local lr_delay_data = {}
for i = 1, 9 do
    lr_delay_data[i] = {
        tick = 0,
        inverted = 1
    }
end

local gram_create = function(value, count) local gram = { }; for i=1, count do gram[i] = value; end return gram; end
local gram_update = function(tab, value, forced) local new_tab = tab; if forced or new_tab[#new_tab] ~= value then table.insert(new_tab, value); table.remove(new_tab, 1); end; tab = new_tab; end
local get_average = function(tab) local elements, sum = 0, 0; for k, v in pairs(tab) do sum = sum + v; elements = elements + 1; end return sum / elements; end

local function get_velocity(player)
    local x,y,z = entity.get_prop(player, "m_vecVelocity")
    if x == nil then return 0 end
    return math.sqrt(x*x + y*y + z*z)
end

local breaker = {
    defensive = 0,
    defensive_check = 0,
    cmd = 0,
    last_origin = nil,
    origin = nil,
    body_yaw = 0,
    switch = false,
    tp_dist = 0,
    tp_data = gram_create(0,3),
    mapname = globals.mapname()
}

local last_press_t_dir = 0
local manual_dir = 0
local id = 1

antiknife = function (x1, y1, z1, x2, y2, z2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2)
end

local run_direction = function()
    ui.set(software.antiaimbot.angles.freestanding[1], b_2.aa.advanced.key_freestand:get())
    ui.set(software.antiaimbot.angles.freestanding[2], b_2.aa.advanced.key_freestand:get() and 'Always on' or 'On hotkey')

    if manual_dir ~= 0 then
        ui.set(software.antiaimbot.angles.freestanding[1], false)
    end

    if b_2.aa.advanced.key_right:get() and last_press_t_dir + 0.2 < globals.curtime() then
        manual_dir = manual_dir == 2 and 0 or 2
        last_press_t_dir = globals.curtime()
    elseif b_2.aa.advanced.key_left:get() and last_press_t_dir + 0.2 < globals.curtime() then
        manual_dir = manual_dir == 1 and 0 or 1
        last_press_t_dir = globals.curtime()
    elseif b_2.aa.advanced.key_reset:get() and last_press_t_dir + 0.2 < globals.curtime() then
        manual_dir = manual_dir == 0
        last_press_t_dir = globals.curtime()
    elseif last_press_t_dir > globals.curtime() then
        last_press_t_dir = globals.curtime()
    end
end

forrealtime = 0
local function smoothJitter(switchyaw1, switchyaw2, switchingspeed)
    if globals.curtime() > forrealtime + 1 / (switchingspeed * 2) then
        finalyawgg = switchyaw1
        if globals.curtime() - forrealtime > 2 / (switchingspeed * 2) then
            forrealtime = globals.curtime()
        end
    else
        finalyawgg = switchyaw2
    end
    return finalyawgg
end

local function desyncside()
    if not entity.get_local_player() or not entity.is_alive(entity.get_local_player()) then
        return 1
    end
    local bodyyaw = entity.get_prop(entity.get_local_player(), "m_flPoseParameter", 11) * 120 - 60
    local side = bodyyaw > 0 and 1 or -1
    return side
end


local aa_inverter = {
    inverted = false,
    delay_ticks = 0
}

local function update_inverter(delay)
    delay = math.max(1, delay or 1)
    
    aa_inverter.delay_ticks = aa_inverter.delay_ticks + 1
    
    if aa_inverter.delay_ticks < delay then
        return
    end
    
    aa_inverter.inverted = not aa_inverter.inverted
    aa_inverter.delay_ticks = 0
end

local defensive_inverter = {
    side = 1,
    delay_tick = 0
}

local function get_defensive_inverter(cmd)
    local me = entity.get_local_player()
    if not me then return 1 end
    
    local body_yaw = math.floor(entity.get_prop(me, 'm_flPoseParameter', 11) * 120 - 60)
    
    if cmd.chokedcommands == 0 then
        local current_tick = globals.tickcount()
        local delay = 2
        
        if defensive_inverter.delay_tick < current_tick - delay then
            defensive_inverter.delay_tick = current_tick
            defensive_inverter.side = defensive_inverter.side == 1 and -1 or 1
        end
    end
    
    return defensive_inverter.side
end

local function calculate_body_yaw(cmd, state_id)
    if not builder[state_id] then return nil end
    
    local des_config = builder[state_id].des
    if not des_config or not des_config.on or not des_config.on:get() then
        return nil
    end
    
    local left_value = des_config.l and des_config.l:get() or 60
    local right_value = des_config.r and des_config.r:get() or 60
    local use_jitter = des_config.j and des_config.j:get() or false
    
    local body_yaw_value
    
    if use_jitter then
        body_yaw_value = breaker.switch and right_value or -left_value
    else
        local invert_ref = ui.reference('AA', 'Fake angles', 'Hide real angle')
        local is_inverted = ui.get(invert_ref)
        body_yaw_value = is_inverted and right_value or -left_value
    end
    
    return body_yaw_value
end

local function player_state(cmd)
    local lp = entity.get_local_player()
    if lp == nil then return "Global" end
    local vecvelocity = { entity.get_prop(lp, 'm_vecVelocity') }
    local flags = entity.get_prop(lp, 'm_fFlags')
    local velocity = math.sqrt(vecvelocity[1]^2+vecvelocity[2]^2)
    local groundcheck = bit.band(flags, 1) == 1
    local jumpcheck = bit.band(flags, 1) == 0 or cmd.in_jump == 1
    local ducked = entity.get_prop(lp, 'm_flDuckAmount') > 0.7
    local duckcheck = ducked
    local slow_motion_refs = {ui.reference("AA", "Other", "Slow motion")}
    local slowwalk_key = slow_motion_refs[1] and slow_motion_refs[2] and ui.get(slow_motion_refs[1]) and ui.get(slow_motion_refs[2]) or false

    if jumpcheck and duckcheck then return "Aerobic+"
    elseif jumpcheck then return "Aerobic"
    elseif duckcheck and velocity > 10 then return "CrouchMove"
    elseif duckcheck and velocity < 10 then return "Crouch"
    elseif groundcheck and slowwalk_key and velocity > 10 then return "Walking"
    elseif groundcheck and velocity > 5 then return "Running"
    elseif groundcheck and velocity < 5 then return "Stand"
    else return "Global" end
end

local function aa_setup(cmd)
    local lp = entity.get_local_player()
    if not lp then return end
    

    if cmd.chokedcommands == 0 then
        breaker.switch = not breaker.switch
    end
    
    local tp_amount = get_average(breaker.tp_data)/get_velocity(lp)*100 
    local dt_refs = {ui.reference('RAGE', 'Aimbot', 'Double tap')}
    local os_refs = {ui.reference('AA', 'Other', 'On shot anti-aim')}
    local is_dt_active = dt_refs[1] and dt_refs[2] and ui.get(dt_refs[1]) and ui.get(dt_refs[2])
    local is_os_active = os_refs[1] and os_refs[2] and ui.get(os_refs[1]) and ui.get(os_refs[2])
    
    local is_defensive = false
    if is_dt_active or is_os_active then
        is_defensive = (breaker.defensive > 1) and not (tp_amount >= 25 and breaker.defensive >= 13)
    end
    local threat = client.current_threat()
    local weapon = entity.get_player_weapon(lp)
    local lp_orig_x, lp_orig_y, lp_orig_z = entity.get_prop(lp, "m_vecOrigin")
    local flags = entity.get_prop(lp, 'm_fFlags')
    local jumpcheck = bit.band(flags, 1) == 0 or cmd.in_jump == 1
    local ducked = entity.get_prop(lp, 'm_flDuckAmount') > 0.7


    if player_state(cmd) == "CrouchMove" and builder[8] and builder[8].enable:get() then id = 8
    elseif player_state(cmd) == "Fakelag" and builder[9] and builder[9].enable:get() then id = 9
    elseif player_state(cmd) == "Crouch" and builder[7] and builder[7].enable:get() then id = 7
    elseif player_state(cmd) == "Aerobic+" and builder[6] and builder[6].enable:get() then id = 6
    elseif player_state(cmd) == "Aerobic" and builder[5] and builder[5].enable:get() then id = 5
    elseif player_state(cmd) == "Running" and builder[4] and builder[4].enable:get() then id = 4
    elseif player_state(cmd) == "Walking" and builder[3] and builder[3].enable:get() then id = 3
    elseif player_state(cmd) == "Stand" and builder[2] and builder[2].enable:get() then id = 2
    else id = 1 end

    run_direction()


    if not builder[id] then
        id = 1
    end

    cmd.force_defensive = builder[id].force_defensive:get()


    local safe_head_active = false
    if b_2.aa.advanced.safehead:get() then
        local me = entity.get_local_player()
        if me and entity.is_alive(me) then
            local enemies = entity.get_players(true)
            local my_origin = vector(entity.get_origin(me))
            
            for i = 1, #enemies do
                local enemy = enemies[i]
                if entity.is_alive(enemy) and not entity.is_dormant(enemy) then
                    local enemy_origin = vector(entity.get_origin(enemy))
                    local distance = my_origin:dist(enemy_origin)
                    
                    local weapon = entity.get_player_weapon(enemy)
                    if weapon then
                        local weapon_classname = entity.get_classname(weapon)
                        
                        if (weapon_classname == 'CKnife' and distance < 300) or 
                           (weapon_classname == 'CWeaponTaser' and distance < 300) then
                            safe_head_active = true
                            break
                        end
                    end
                end
            end
        end
    end

    if safe_head_active then
        ui.set(software.antiaimbot.angles.enabled, true)
        ui.set(software.antiaimbot.angles.pitch[1], "Down")
        ui.set(software.antiaimbot.angles.yaw[1], "180")
        ui.set(software.antiaimbot.angles.yaw[2], 180)
        ui.set(software.antiaimbot.angles.yaw_base, "Local view")
    elseif builder[id].defaa_enb:get() and is_defensive then

        ui.set(software.antiaimbot.angles.enabled, true)
        local pitch_mode = builder[id].def_pitch_mode:get()
        local pitch_offset = builder[id].def_pitch:get()
        
        if builder[id].def_pitch_height_based:get() then

            local my_pos = vector(entity.get_origin(entity.get_local_player()))
            local threat = client.current_threat()
            
            local height_based_min = -89
            local height_based_max = 89
            
            if threat and entity.is_alive(threat) then
                local threat_pos = vector(entity.get_origin(threat))
                local height_diff = my_pos.z - threat_pos.z
                height_based_min = math.max(-89, -89 - height_diff)
                height_based_max = math.min(89, 89 + height_diff)
            end
            
            if pitch_mode == 'Jitter' then
                local speed = math.max(1, math.min(builder[id].def_pitch_speed:get(), 15))
                local interval = math.floor(math.floor(1 / globals.tickinterval()) / speed)
                local phase = math.floor(globals.tickcount() / interval) % 2
                pitch_offset = (phase == 0) and height_based_min or height_based_max
            elseif pitch_mode == 'Random' then
                pitch_offset = client.random_int(height_based_min, height_based_max)
            elseif pitch_mode == 'Cycling' then
                local cycle_speed = builder[id].def_pitch_speed:get()
                if pitch_add >= height_based_max then pitch_add = height_based_min else pitch_add = pitch_add + cycle_speed end
                pitch_offset = pitch_add
            elseif pitch_mode == 'Spin' then
                local spin_speed = builder[id].def_pitch_speed:get()
                local mid = (height_based_min + height_based_max) / 2
                local amp = math.abs(height_based_max - height_based_min) / 2
                pitch_offset = mid + math.sin(globals.realtime() * spin_speed) * amp
            elseif pitch_mode == 'Sway' then
                local sway_speed = builder[id].def_pitch_speed:get()
                local mid = (height_based_min + height_based_max) / 2
                local amp = math.abs(height_based_max - height_based_min) / 2
                pitch_offset = mid + math.sin(globals.realtime() * sway_speed) * amp * (math.cos(globals.realtime() * sway_speed * 0.5) + 1) / 2
            else
                pitch_offset = height_based_min
            end
        elseif builder[id].def_pitch_min_max:get() then

            if pitch_mode == 'Jitter' then
                local speed = math.max(1, math.min(builder[id].def_pitch_speed:get(), 15))
                local interval = math.floor(math.floor(1 / globals.tickinterval()) / speed)
                local phase = math.floor(globals.tickcount() / interval) % 2
                pitch_offset = (phase == 0) and builder[id].def_pitch_min:get() or builder[id].def_pitch_max:get()
            elseif pitch_mode == 'Random' then
                pitch_offset = client.random_int(builder[id].def_pitch_min:get(), builder[id].def_pitch_max:get())
            elseif pitch_mode == 'Cycling' then
                local cycle_speed = builder[id].def_pitch_speed:get()
                if pitch_add >= builder[id].def_pitch_max:get() then pitch_add = builder[id].def_pitch_min:get() else pitch_add = pitch_add + cycle_speed end
                pitch_offset = pitch_add
            elseif pitch_mode == 'Spin' then
                local spin_speed = builder[id].def_pitch_speed:get()
                local mid = (builder[id].def_pitch_min:get() + builder[id].def_pitch_max:get()) / 2
                local amp = math.abs(builder[id].def_pitch_max:get() - builder[id].def_pitch_min:get()) / 2
                pitch_offset = mid + math.sin(globals.realtime() * spin_speed) * amp
            elseif pitch_mode == 'Sway' then
                local sway_speed = builder[id].def_pitch_speed:get()
                local mid = (builder[id].def_pitch_min:get() + builder[id].def_pitch_max:get()) / 2
                local amp = math.abs(builder[id].def_pitch_max:get() - builder[id].def_pitch_min:get()) / 2
                pitch_offset = mid + math.sin(globals.realtime() * sway_speed) * amp * (math.cos(globals.realtime() * sway_speed * 0.5) + 1) / 2
            else
                pitch_offset = builder[id].def_pitch_min:get()
            end
        else

            if pitch_mode == 'Spin' then
                local spin_speed = builder[id].def_pitch_speed:get()
                pitch_offset = math.sin(globals.realtime() * spin_speed) * pitch_offset
            elseif pitch_mode == 'Sway' then
                local sway_speed = builder[id].def_pitch_speed:get()
                local sway_amplitude = pitch_offset * 0.5
                pitch_offset = math.sin(globals.realtime() * sway_speed) * sway_amplitude * (math.cos(globals.realtime() * sway_speed * 0.5) + 1)
            elseif pitch_mode == 'Jitter' then
                local speed = math.max(1, math.min(builder[id].def_pitch_speed:get(), 15))
                local interval = math.floor(math.floor(1 / globals.tickinterval()) / speed)
                local phase = math.floor(globals.tickcount() / interval) % 2
                local switch_amount = (phase == 0) and pitch_offset or -pitch_offset
                pitch_offset = switch_amount
            elseif pitch_mode == 'Cycling' then
                local cycle_speed = builder[id].def_pitch_speed:get()
                if pitch_add >= 89 then pitch_add = -89 else pitch_add = pitch_add + cycle_speed end
                pitch_offset = pitch_add
            elseif pitch_mode == 'Random' then
                pitch_offset = client.random_int(-89, 89)
            end
        end
        

        pitch_offset = math.max(-89, math.min(89, pitch_offset))
        
        ui.set(software.antiaimbot.angles.pitch[1], "Custom")
        ui.set(software.antiaimbot.angles.pitch[2], pitch_offset)
        

        local yaw_type = builder[id].def_yaw:get()
        local yaw_offset = builder[id].def_yaw_offset:get()
        
        if yaw_type == "Off" then
            ui.set(software.antiaimbot.angles.yaw[1], "Off")
            ui.set(software.antiaimbot.angles.yaw[2], 0)
        elseif yaw_type == "180" then
            ui.set(software.antiaimbot.angles.yaw[1], "180")

            if builder[id].def_yaw_left_right:get() then

                local d_inverted = get_defensive_inverter(cmd)
                
                if d_inverted == 1 then
                    ui.set(software.antiaimbot.angles.yaw[2], builder[id].def_yaw_left:get())
                else
                    ui.set(software.antiaimbot.angles.yaw[2], builder[id].def_yaw_right:get())
                end
            else

                ui.set(software.antiaimbot.angles.yaw[2], yaw_offset)
            end
        elseif yaw_type == "Spin" then
            ui.set(software.antiaimbot.angles.yaw[1], "Spin")
            ui.set(software.antiaimbot.angles.yaw[2], builder[id].def_yaw_speed:get())
        elseif yaw_type == "Distortion" then
            if builder[id].def_yaw_generation:get() then
                local yaw_gen = client.random_int(builder[id].def_yaw_min_gen:get(), builder[id].def_yaw_max_gen:get())
                ui.set(software.antiaimbot.angles.yaw[1], "180")
                ui.set(software.antiaimbot.angles.yaw[2], yaw_gen)
            else
                ui.set(software.antiaimbot.angles.yaw[1], "180")
                ui.set(software.antiaimbot.angles.yaw[2], yaw_offset)
            end
        elseif yaw_type == "Sway" then
            local sway_speed = builder[id].def_yaw_speed:get()
            local sway_yaw = math.sin(globals.realtime() * sway_speed) * yaw_offset
            ui.set(software.antiaimbot.angles.yaw[1], "180")
            ui.set(software.antiaimbot.angles.yaw[2], sway_yaw)
        elseif yaw_type == "Freestand" then
            ui.set(software.antiaimbot.angles.freestanding[1], true)
            ui.set(software.antiaimbot.angles.freestanding[2], 'Always on')
        end
        

        local body_yaw_value = calculate_body_yaw(cmd, id)
        if body_yaw_value ~= nil then
            ui.set(software.antiaimbot.angles.body_yaw[1], "Static")
            ui.set(software.antiaimbot.angles.body_yaw[2], body_yaw_value > 0 and 1 or body_yaw_value < 0 and -1 or 0)
        else
            ui.set(software.antiaimbot.angles.body_yaw[1], "Off")
            ui.set(software.antiaimbot.angles.body_yaw[2], 0)
        end
    else

        ui.set(software.antiaimbot.angles.enabled, true)
        

        local pitch_mode = builder[id].pitch:get()
        if pitch_mode == "Off" then
            ui.set(software.antiaimbot.angles.pitch[1], "Off")
        elseif pitch_mode == "Default" then
            ui.set(software.antiaimbot.angles.pitch[1], "Default")
        elseif pitch_mode == "Up" then
            ui.set(software.antiaimbot.angles.pitch[1], "Up")
        elseif pitch_mode == "Down" then
            ui.set(software.antiaimbot.angles.pitch[1], "Down")
        elseif pitch_mode == "Minimal" then
            ui.set(software.antiaimbot.angles.pitch[1], "Minimal")
        elseif pitch_mode == "Random" then
            local random_pitches = {"Up", "Down", "Minimal"}
            ui.set(software.antiaimbot.angles.pitch[1], random_pitches[math.random(1, #random_pitches)])
        end
        
        ui.set(software.antiaimbot.angles.yaw_base, builder[id].yawbase:get())
        

        local modifier = builder[id].yawmodifer:get()
        local degree = builder[id].degree:get()
        local center_offset = 0
        
        if modifier == "Center" then

            local delay = builder[id].center_delay:get()
            local tick = globals.tickcount()
            local state_data = center_delay_data[id]
            
            if tick - state_data.tick >= delay then
                state_data.inverted = state_data.inverted * -1
                state_data.tick = tick
            end
            

            center_offset = (state_data.inverted == 1 and -degree / 2 or state_data.inverted == -1 and degree / 2) or 0
            

            ui.set(software.antiaimbot.angles.yaw_jitter[1], "Off")
            ui.set(software.antiaimbot.angles.yaw_jitter[2], 0)
        elseif modifier == "Skitter" then
            ui.set(software.antiaimbot.angles.yaw_jitter[1], "Offset")
            ui.set(software.antiaimbot.angles.yaw_jitter[2], degree)
            center_offset = builder[id].skitter_offset:get()
        elseif modifier == "Offset" then
            ui.set(software.antiaimbot.angles.yaw_jitter[1], "Offset")
            ui.set(software.antiaimbot.angles.yaw_jitter[2], degree)
            center_offset = builder[id].offset_value:get()
        else

            ui.set(software.antiaimbot.angles.yaw_jitter[1], modifier)
            ui.set(software.antiaimbot.angles.yaw_jitter[2], degree)
        end
        

        local yaw_type = builder[id].yaw_type:get()
        local yaw_value = 0
        
        if yaw_type == "L/R" then

            local delay = builder[id].yaw_lr_delay:get()
            local tick = globals.tickcount()
            local state_data = lr_delay_data[id]
            
            if tick - state_data.tick >= delay then
                state_data.inverted = state_data.inverted * -1
                state_data.tick = tick
            end
            
            if state_data.inverted == 1 then
                yaw_value = builder[id].yaw_left:get()
            else
                yaw_value = builder[id].yaw_right:get()
            end
        else

            yaw_value = builder[id].yaw:get() + center_offset
        end
       
        if yaw_value > 180 then yaw_value = 180 end
        if yaw_value < -180 then yaw_value = -180 end
        
        ui.set(software.antiaimbot.angles.yaw[1], "180")
        ui.set(software.antiaimbot.angles.yaw[2], yaw_value)
        

        local body_yaw_value = calculate_body_yaw(cmd, id)
        if body_yaw_value ~= nil then
            ui.set(software.antiaimbot.angles.body_yaw[1], "Static")
            ui.set(software.antiaimbot.angles.body_yaw[2], body_yaw_value > 0 and 1 or body_yaw_value < 0 and -1 or 0)
        else
            ui.set(software.antiaimbot.angles.body_yaw[1], "Off")
            ui.set(software.antiaimbot.angles.body_yaw[2], 0)
        end
    end


    if manual_dir == 2 then
        ui.set(software.antiaimbot.angles.pitch[1], "Minimal")
        ui.set(software.antiaimbot.angles.yaw_base, "Local view")
        ui.set(software.antiaimbot.angles.yaw[1], "180")
        ui.set(software.antiaimbot.angles.yaw[2], 90)
        ui.set(software.antiaimbot.angles.yaw_jitter[1], "Offset")
        ui.set(software.antiaimbot.angles.yaw_jitter[2], 0)
        ui.set(software.antiaimbot.angles.body_yaw[1], "Off")
        ui.set(software.antiaimbot.angles.body_yaw[2], 0)
        ui.set(software.antiaimbot.angles.freestanding_body_yaw, false)
    end

    if manual_dir == 1 then
        ui.set(software.antiaimbot.angles.pitch[1], "Minimal")
        ui.set(software.antiaimbot.angles.yaw_base, "Local view")
        ui.set(software.antiaimbot.angles.yaw[1], "180")
        ui.set(software.antiaimbot.angles.yaw[2], -90)
        ui.set(software.antiaimbot.angles.yaw_jitter[1], "Offset")
        ui.set(software.antiaimbot.angles.yaw_jitter[2], 0)
        ui.set(software.antiaimbot.angles.body_yaw[1], "Off")
        ui.set(software.antiaimbot.angles.body_yaw[2], 0)
        ui.set(software.antiaimbot.angles.freestanding_body_yaw, false)
    end


    if b_2.aa.advanced.safehead:get() then
        if b_2.aa.advanced.options:get("Edge On FD") then
            local fakeduck_ref = ui.reference('RAGE', 'Other', 'Duck peek assist')
            if ui.get(fakeduck_ref) then
                ui.set(software.antiaimbot.angles.edge_yaw, true)
            else
                ui.set(software.antiaimbot.angles.edge_yaw, false)
            end
        end
        
        if b_2.aa.advanced.options:get("Safe Knife") then
            if jumpcheck and ducked and weapon and entity.get_classname(weapon) == "CKnife" then
                if not is_defensive then
                    ui.set(software.antiaimbot.angles.pitch[1], "Minimal")
                    ui.set(software.antiaimbot.angles.yaw_base, "At targets")
                    ui.set(software.antiaimbot.angles.yaw[1], "180")
                    ui.set(software.antiaimbot.angles.yaw[2], 14)
                    ui.set(software.antiaimbot.angles.yaw_jitter[1], "Off")
                    ui.set(software.antiaimbot.angles.yaw_jitter[2], 0)
                    ui.set(software.antiaimbot.angles.body_yaw[1], "Static")
                    ui.set(software.antiaimbot.angles.body_yaw[2], 1)
                    ui.set(software.antiaimbot.angles.freestanding_body_yaw, false)
                else
                    cmd.force_defensive = 1
                    ui.set(software.antiaimbot.angles.pitch[1], "Minimal")
                    ui.set(software.antiaimbot.angles.pitch[2], 0)
                    ui.set(software.antiaimbot.angles.yaw_base, "At targets")
                    ui.set(software.antiaimbot.angles.yaw[1], "180")
                    ui.set(software.antiaimbot.angles.yaw[2], 14)
                    ui.set(software.antiaimbot.angles.yaw_jitter[1], "Off")
                    ui.set(software.antiaimbot.angles.yaw_jitter[2], 0)
                    ui.set(software.antiaimbot.angles.body_yaw[1], "Static")
                    ui.set(software.antiaimbot.angles.body_yaw[2], 1)
                    ui.set(software.antiaimbot.angles.freestanding_body_yaw, false)
                end
            end
        end
        
        if b_2.aa.advanced.options:get("Safe Zeus") then
            if jumpcheck and ducked and weapon and entity.get_classname(weapon) == "CWeaponTaser" then
                if not is_defensive then
                    ui.set(software.antiaimbot.angles.pitch[1], "Minimal")
                    ui.set(software.antiaimbot.angles.yaw_base, "At targets")
                    ui.set(software.antiaimbot.angles.yaw[1], "180")
                    ui.set(software.antiaimbot.angles.yaw[2], 14)
                    ui.set(software.antiaimbot.angles.yaw_jitter[1], "Off")
                    ui.set(software.antiaimbot.angles.yaw_jitter[2], 0)
                    ui.set(software.antiaimbot.angles.body_yaw[1], "Static")
                    ui.set(software.antiaimbot.angles.body_yaw[2], 1)
                    ui.set(software.antiaimbot.angles.freestanding_body_yaw, false)
                else
                    cmd.force_defensive = 1
                    ui.set(software.antiaimbot.angles.pitch[1], "Minimal")
                    ui.set(software.antiaimbot.angles.pitch[2], 0)
                    ui.set(software.antiaimbot.angles.yaw_base, "At targets")
                    ui.set(software.antiaimbot.angles.yaw[1], "180")
                    ui.set(software.antiaimbot.angles.yaw[2], 14)
                    ui.set(software.antiaimbot.angles.yaw_jitter[1], "Off")
                    ui.set(software.antiaimbot.angles.yaw_jitter[2], 0)
                    ui.set(software.antiaimbot.angles.body_yaw[1], "Static")
                    ui.set(software.antiaimbot.angles.body_yaw[2], 1)
                    ui.set(software.antiaimbot.angles.freestanding_body_yaw, false)
                end
            end
        end
    end


    local players = entity.get_players(true)
    if b_2.aa.advanced.antibackstab:get() then
        lp_orig_x, lp_orig_y, lp_orig_z = entity.get_prop(lp, "m_vecOrigin")
        for i=1, #players do
            if players == nil then return end
            local enemy_orig_x, enemy_orig_y, enemy_orig_z = entity.get_prop(players[i], "m_vecOrigin")
            if enemy_orig_x then
                local distance_to = antiknife(lp_orig_x, lp_orig_y, lp_orig_z, enemy_orig_x, enemy_orig_y, enemy_orig_z)
                local enemy_weapon = entity.get_player_weapon(players[i])
                if enemy_weapon and entity.get_classname(enemy_weapon) == "CKnife" and distance_to <= 250 then
                    ui.set(software.antiaimbot.angles.yaw[2], "180")
                    ui.set(software.antiaimbot.angles.yaw_base, "At targets")
                end
            end
        end
    end
end

local antiaim_funcs = {}

do
    function antiaim_funcs.update_freestanding(cmd)
        local pressed = b_2.aa.advanced.key_freestand:get()
        
        if pressed then
            ui.set(software.antiaimbot.angles.freestanding[1], true)
            ui.set(software.antiaimbot.angles.freestanding[2], 'Always on')
            return true
        else
            ui.set(software.antiaimbot.angles.freestanding[1], false)
            return false
        end
    end
end

do
    function antiaim_funcs.safe_head(cmd)
        if not b_2.aa.advanced.safehead:get() then
            return false
        end
        
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then
            return false
        end
        
        local enemies = entity.get_players(true)
        local my_origin = vector(entity.get_origin(me))
        
        for i = 1, #enemies do
            local enemy = enemies[i]
            if entity.is_alive(enemy) and not entity.is_dormant(enemy) then
                local enemy_origin = vector(entity.get_origin(enemy))
                local distance = my_origin:dist(enemy_origin)
                
                local weapon = entity.get_player_weapon(enemy)
                if weapon then
                    local weapon_classname = entity.get_classname(weapon)
                    local is_dangerous = false
                    

                    if weapon_classname == 'CKnife' and distance < 300 then
                        is_dangerous = true
                    elseif weapon_classname == 'CWeaponTaser' and distance < 200 then
                        is_dangerous = true
                    end
                    
                    if is_dangerous then

                        ui.set(software.antiaimbot.angles.pitch[1], 'Down')
                        ui.set(software.antiaimbot.angles.yaw[1], '180')
                        ui.set(software.antiaimbot.angles.yaw[2], 180)
                        ui.set(software.antiaimbot.angles.yaw_base, 'Local view')
                        return true
                    end
                end
            end
        end
        
        return false
    end
end

function antiaim_funcs.update(cmd)
    aa_setup(cmd)
    antiaim_funcs.update_freestanding(cmd)
    
    if b_2.aa.advanced.fastladder:get() then
        local lp = entity.get_local_player()
        if not lp then return end
        
        local pitch, yaw = client.camera_angles()
        if entity.get_prop(lp, "m_MoveType") == 9 then
            cmd.yaw = math.floor(cmd.yaw+0.5)
            cmd.roll = 0
            
            if cmd.forwardmove > 0 then
                if pitch < 45 then
                    cmd.pitch = 89
                    cmd.in_moveright = 1
                    cmd.in_moveleft = 0
                    cmd.in_forward = 0
                    cmd.in_back = 1
                    if cmd.sidemove == 0 then
                        cmd.yaw = cmd.yaw + 90
                    end
                    if cmd.sidemove < 0 then
                        cmd.yaw = cmd.yaw + 150
                    end
                    if cmd.sidemove > 0 then
                        cmd.yaw = cmd.yaw + 30
                    end
                end
            end
            
            if cmd.forwardmove < 0 then
                cmd.pitch = 89
                cmd.in_moveleft = 1
                cmd.in_moveright = 0
                cmd.in_forward = 1
                cmd.in_back = 0
                if cmd.sidemove == 0 then
                    cmd.yaw = cmd.yaw + 90
                end
                if cmd.sidemove > 0 then
                    cmd.yaw = cmd.yaw + 150
                end
                if cmd.sidemove < 0 then
                    cmd.yaw = cmd.yaw + 30
                end
            end
        end
    end
end

local misc = {

    clantag = menu.group.main:checkbox('Clantag'),
    trashtalk = menu.group.main:checkbox('Trashtalk'),
    trashtalk_events = menu.group.main:multiselect('  Events', {'Kill', 'Death'}),
    trashtalk_language = menu.group.main:combobox('  Language', {'English', 'Russian', 'Bait'}),
    
    console_filter = menu.group.main:checkbox('Console filter'),
    
    fast_ladder = menu.group.main:checkbox('Fast ladder'),
    
    buybot = {
        enabled = menu.group.main:checkbox('Buybot'),
        primary = menu.group.main:combobox('  Primary', {'None', 'AWP', 'Scout', 'Autosnipers'}),
        secondary = menu.group.main:combobox('  Secondary', {'None', 'Duals', 'P-250', 'R8/Deagle', 'Tec-9/Five-S'}),
        utility = menu.group.main:multiselect('  Utility', {'HE', 'Flash', 'Smoke', 'Molotov'}),
        equipment = menu.group.main:multiselect('  Equipment', {'Taser', 'Kevlar', 'Helmet', 'Defuser'}),
        pistol_kevlar = menu.group.main:checkbox('  Kevlar on pistol round')
    },
    
    animation_breaker = {
        enabled = menu.group.main:checkbox('Animation breaker'),
        in_air_legs = menu.group.main:combobox('  In-air legs', {'Off', 'Static', 'Moonwalk'}),
        in_air_static_value = menu.group.main:slider('    Static value', 0, 100, 100, true, '%'),
        onground_legs = menu.group.main:combobox('  On-ground legs', {'Off', 'Static', 'Jitter', 'Moonwalk'}),
        onground_jitter_min_value = menu.group.main:slider('    Min. value', 0, 100, 50, true, '%'),
        onground_jitter_max_value = menu.group.main:slider('    Max. value', 0, 100, 50, true, '%'),
        adjust_lean = menu.group.main:slider('  Adjust lean', 0, 100, 0, true, '%'),
        pitch_on_land = menu.group.main:checkbox('  Pitch on land'),
        earthquake = menu.group.main:checkbox('  Earthquake'),
        earthquake_value = menu.group.main:slider('    Earthquake value', 1, 100, 100, true, '%')
    }
}

do

    pui.traverse(presets, function(ref)
        ref:depend({tab.main, ' Home'})
    end)
    

    presets.config_name:depend({tab.main, ' Home'}, {presets.config_type, 'Local'})
    
    pui.traverse(info, function(ref)
        ref:depend({tab.main, ' Home'})
    end)
    
    tab.aimbot_sub:depend({tab.main, ' Aimbot'})
    

    pui.traverse(aimbot, function(ref)
        ref:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Main'})
    end)
    
    aimbot.resolver_type:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Main'}, {aimbot.resolver, true})
    

    aimbot.auto_os_weapons:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Main'}, {aimbot.auto_os, true})
    aimbot.auto_os_states:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Main'}, {aimbot.auto_os, true})
    
    pui.traverse(aimbot_info, function(ref)
        ref:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Main'})
    end)
    
    pui.traverse(aimbot_rage, function(ref)
        ref:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Rage'})
    end)
    
    aimbot_rage.force_baim:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Rage'}, {aimbot_rage.logic, 'Force body aim'})
    aimbot_rage.force_baim_miss:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Rage'}, {aimbot_rage.logic, 'Force body aim'}, {aimbot_rage.force_baim, 'After x misses'})
    
    aimbot_rage.force_safety:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Rage'}, {aimbot_rage.logic, 'Force safety'})
    aimbot_rage.force_safety_miss:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Rage'}, {aimbot_rage.logic, 'Force safety'}, {aimbot_rage.force_safety, 'After x misses'})
    
    aimbot_rage.delay_shot:depend({tab.main, ' Aimbot'}, {tab.aimbot_sub, ' Rage'}, {aimbot_rage.logic, 'Auto delay shot'})
    

    pui.traverse(visual, function(ref)

        if type(ref) == "table" and ref.depend and type(ref.depend) == "function" then
            ref:depend({tab.main, ' Visual'})
        end
    end)
    
    visual.watermark_style:depend({tab.main, ' Visual'}, {visual.watermark, true})
    visual.watermark_al_color:depend({tab.main, ' Visual'}, {visual.watermark, true}, {visual.watermark_style, 'AL'})
    visual.watermark_gs_color:depend({tab.main, ' Visual'}, {visual.watermark, true}, {visual.watermark_style, 'GS'})
    visual.watermark_gs_line:depend({tab.main, ' Visual'}, {visual.watermark, true}, {visual.watermark_style, 'GS'})
    visual.watermark_display:depend({tab.main, ' Visual'}, {visual.watermark, true})
    visual.watermark_position:depend({tab.main, ' Visual'}, {visual.watermark, true})
    visual.watermark_style:set_callback(function()
        local style = visual.watermark_style:get()
        local is_ce = style == 'CE'
        local is_al = style == 'AL'
        local is_gs = style == 'GS'
        
        visual.watermark_display:set_visible(not is_ce)
        visual.watermark_position:set_visible(not is_ce)
        visual.watermark_al_color:set_visible(is_al)
        visual.watermark_gs_color:set_visible(is_gs)
        visual.watermark_gs_line:set_visible(is_gs)
    end)
    local initial_style = visual.watermark_style:get()
    visual.watermark_al_color:set_visible(initial_style == 'AL')
    visual.watermark_gs_color:set_visible(initial_style == 'GS')
    visual.watermark_gs_line:set_visible(initial_style == 'GS')
    

    visual.vm_fov:depend({tab.main, ' Visual'}, {visual.viewmodel, true})
    visual.vm_x:depend({tab.main, ' Visual'}, {visual.viewmodel, true})
    visual.vm_y:depend({tab.main, ' Visual'}, {visual.viewmodel, true})
    visual.vm_z:depend({tab.main, ' Visual'}, {visual.viewmodel, true})
    visual.vm_flip_knife:depend({tab.main, ' Visual'}, {visual.viewmodel, true})
    

    visual.aspect_val:depend({tab.main, ' Visual'}, {visual.aspect_ratio, true})
    
    
    visual.screen_indicators:depend({tab.main, ' Visual'})
    visual.screen_indicators_glow:depend({tab.main, ' Visual'}, {visual.screen_indicators, true})
    
    visual.arrows_color:depend({tab.main, ' Visual'}, {visual.arrows, true})
    
    visual.scope_gap:depend({tab.main, ' Visual'}, {visual.scope_lines, true})
    visual.scope_size:depend({tab.main, ' Visual'}, {visual.scope_lines, true})
    visual.scope_invert:depend({tab.main, ' Visual'}, {visual.scope_lines, true})
    visual.scope_color:depend({tab.main, ' Visual'}, {visual.scope_lines, true})
    

    visual.damage_color:depend({tab.main, ' Visual'}, {visual.damage, true})
    visual.damage_font:depend({tab.main, ' Visual'}, {visual.damage, true})
    

    visual.notifications_color:depend({tab.main, ' Visual'}, {visual.notifications, true})
    visual.notifications_type:depend({tab.main, ' Visual'}, {visual.notifications, true})
    

    pui.traverse(misc, function(ref)
        ref:depend({tab.main, ' Misc'})
    end)
    

    misc.trashtalk_events:depend({tab.main, ' Misc'}, {misc.trashtalk, true})
    misc.trashtalk_language:depend({tab.main, ' Misc'}, {misc.trashtalk, true})
    pui.traverse(misc.buybot, function(ref)
        ref:depend({tab.main, ' Misc'})
    end)
    
    misc.buybot.primary:depend({tab.main, ' Misc'}, {misc.buybot.enabled, true})
    misc.buybot.secondary:depend({tab.main, ' Misc'}, {misc.buybot.enabled, true})
    misc.buybot.utility:depend({tab.main, ' Misc'}, {misc.buybot.enabled, true})
    misc.buybot.equipment:depend({tab.main, ' Misc'}, {misc.buybot.enabled, true})
    misc.buybot.pistol_kevlar:depend({tab.main, ' Misc'}, {misc.buybot.enabled, true})
    

    pui.traverse(misc.animation_breaker, function(ref)
        ref:depend({tab.main, ' Misc'})
    end)
    
    misc.animation_breaker.in_air_legs:depend({tab.main, ' Misc'}, {misc.animation_breaker.enabled, true})
    misc.animation_breaker.in_air_static_value:depend({tab.main, ' Misc'}, {misc.animation_breaker.enabled, true}, {misc.animation_breaker.in_air_legs, 'Static'})
    misc.animation_breaker.onground_legs:depend({tab.main, ' Misc'}, {misc.animation_breaker.enabled, true})
    misc.animation_breaker.onground_jitter_min_value:depend({tab.main, ' Misc'}, {misc.animation_breaker.enabled, true}, {misc.animation_breaker.onground_legs, 'Jitter'})
    misc.animation_breaker.onground_jitter_max_value:depend({tab.main, ' Misc'}, {misc.animation_breaker.enabled, true}, {misc.animation_breaker.onground_legs, 'Jitter'})
    misc.animation_breaker.adjust_lean:depend({tab.main, ' Misc'}, {misc.animation_breaker.enabled, true})
    misc.animation_breaker.pitch_on_land:depend({tab.main, ' Misc'}, {misc.animation_breaker.enabled, true})
    misc.animation_breaker.earthquake:depend({tab.main, ' Misc'}, {misc.animation_breaker.enabled, true})
    misc.animation_breaker.earthquake_value:depend({tab.main, ' Misc'}, {misc.animation_breaker.enabled, true}, {misc.animation_breaker.earthquake, true})
end

do

    b_2.aa.advanced.key_freestand:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.safehead:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    

    b_2.aa.main.labpick:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Builder'})
    b_2.aa.main.labpickss:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Builder'})
    b_2.aa.main.state:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Builder'})
    
    for i=1, #state_aa do

        cond_check = {b_2.aa.main.state, function() return (i ~= 1) end}
        tab_cond = {b_2.aa.main.state, state_aa[i]}
        check_tab = {tab.main, " Anti-Aim"}
        menut_tab = {b_2.aa.aapick, "Builder"}
        delay = {builder[i].yawtype, "Delay"}
        lrcheck = {builder[i].yawtype, "L/R"}
        default = {builder[i].yawmodifer, "Center"}
        
        defaa = {builder[i].defaa_enb, true}
        defensive = {builder[i].force_defensive, true}
        cnd_en = {builder[i].enable, function() if (i == 1) then return true else return builder[i].enable:get() end end}
        

        builder[i].enable:depend(cond_check, tab_cond,check_tab, menut_tab)
        builder[i].pitch:depend( tab_cond, cnd_en,check_tab, menut_tab)
        builder[i].yawbase:depend( tab_cond,cnd_en, check_tab, menut_tab)
        builder[i].yaw_type:depend( tab_cond, cnd_en,check_tab, menut_tab)
        builder[i].yaw:depend( tab_cond, cnd_en,check_tab, menut_tab, {builder[i].yaw_type, "180"})
        builder[i].yaw_left:depend( tab_cond, cnd_en,check_tab, menut_tab, {builder[i].yaw_type, "L/R"})
        builder[i].yaw_right:depend( tab_cond, cnd_en,check_tab, menut_tab, {builder[i].yaw_type, "L/R"})
        builder[i].yaw_lr_delay:depend( tab_cond, cnd_en,check_tab, menut_tab, {builder[i].yaw_type, "L/R"})
        builder[i].yawmodifer:depend(tab_cond, cnd_en, check_tab, menut_tab, {builder[i].yaw_type, "180"})
        builder[i].degree:depend(tab_cond, cnd_en,check_tab, menut_tab, default, {builder[i].yaw_type, "180"})
        builder[i].center_delay:depend(tab_cond, cnd_en,check_tab, menut_tab, {builder[i].yawmodifer, "Center"}, {builder[i].yaw_type, "180"})
        
        builder[i].force_defensive:depend( tab_cond,check_tab, cnd_en, menut_tab)
        builder[i].defaa_enb:depend(tab_cond,check_tab, cnd_en, menut_tab, defensive)
        

        builder[i].def_pitch_mode:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive)
        builder[i].def_pitch_speed:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_pitch_mode, function() 
            local mode = builder[i].def_pitch_mode:get()
            return mode == 'Spin' or mode == 'Sway' or mode == 'Jitter' or mode == 'Cycling'
        end})
        builder[i].def_pitch:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_pitch_min_max, false}, {builder[i].def_pitch_height_based, false})
        builder[i].def_pitch_min:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_pitch_min_max, true}, {builder[i].def_pitch_height_based, false})
        builder[i].def_pitch_max:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_pitch_min_max, true}, {builder[i].def_pitch_height_based, false})
        builder[i].def_pitch_min_max:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive)
        builder[i].def_pitch_height_based:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive)
        

        builder[i].def_yaw:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive)
        builder[i].def_yaw_speed:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_yaw, function()
            local yaw = builder[i].def_yaw:get()
            return yaw == 'Spin' or yaw == 'Sway'
        end})
        builder[i].def_yaw_offset:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_yaw, function()
            local yaw = builder[i].def_yaw:get()
            return yaw == '180' or yaw == 'Distortion' or yaw == 'Sway'
        end}, {builder[i].def_yaw_left_right, false})
        builder[i].def_yaw_left:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_yaw_left_right, true}, {builder[i].def_yaw, '180'})
        builder[i].def_yaw_right:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_yaw_left_right, true}, {builder[i].def_yaw, '180'})
        builder[i].def_yaw_min_gen:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_yaw_generation, true})
        builder[i].def_yaw_max_gen:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_yaw_generation, true})
        builder[i].def_yaw_left_right:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_yaw, '180'})
        builder[i].def_yaw_generation:depend(tab_cond,check_tab, cnd_en, menut_tab, defaa, defensive, {builder[i].def_yaw, 'Distortion'})
    end
    

    b_2.aa.advanced.labpick1:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.space:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.key_left:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.key_right:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.key_reset:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.spacee:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.labpick2:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.space3:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.antibackstab:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.options:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    b_2.aa.advanced.fastladder:depend({tab.main, ' Anti-Aim'}, {b_2.aa.aapick, 'Other'})
    

    b_2.aa.aapick:depend({tab.main, ' Anti-Aim'})
end



local auto_os = {}
do

    local override = {}
    local override_data = {}
    
    local e_hotkey_mode = {
        [0] = 'Always on',
        [1] = 'On hotkey', 
        [2] = 'Toggle',
        [3] = 'Off hotkey'
    }
    
    local function get_value(item)
        local item_type = ui.type(item)
        local value = {ui.get(item)}
        
        if item_type == 'hotkey' then
            local mode = e_hotkey_mode[value[2]]
            local keycode = value[3] or 0
            return {mode, keycode}
        end
        
        return value
    end
    
    function override.set(item, ...)
        if override_data[item] == nil then
            override_data[item] = get_value(item)
        end
        ui.set(item, ...)
    end
    
    function override.unset(item)
        local value = override_data[item]
        if value == nil then return end
        
        ui.set(item, unpack(value))
        override_data[item] = nil
    end
    

    local ragebot = {}
    local ragebot_data = {}
    
    function ragebot.set(item, ...)
        if ragebot_data[item] == nil then
            ragebot_data[item] = get_value(item)
        end
        ui.set(item, ...)
    end
    
    function ragebot.unset(item)
        local value = ragebot_data[item]
        if value == nil then return end
        
        ui.set(item, unpack(value))
        ragebot_data[item] = nil
    end
    

    local ref_duck_peek_assist = ui.reference('Rage', 'Other', 'Duck peek assist')
    local ref_quick_peek_assist = {ui.reference('Rage', 'Other', 'Quick peek assist')}
    local ref_double_tap = {ui.reference('Rage', 'Aimbot', 'Double tap')}
    local ref_on_shot_antiaim = {ui.reference('AA', 'Other', 'On shot anti-aim')}
    local ref_slow_motion = {ui.reference('AA', 'Other', 'Slow motion')}
    

    local function get_state()
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return nil end
        
        local flags = entity.get_prop(me, 'm_fFlags')
        local velocity = vector(entity.get_prop(me, 'm_vecVelocity')):length2d()
        
        local on_ground = bit.band(flags, 1) == 1
        local is_crouched = bit.band(flags, 4) == 4
        local is_moving = velocity > 5
        

        local is_slow_walk = false
        if ref_slow_motion[1] and ref_slow_motion[2] then
            is_slow_walk = ui.get(ref_slow_motion[1]) and ui.get(ref_slow_motion[2])
        end
        
        if not on_ground then
            if is_crouched then
                return 'Air-Crouch'
            end
            return 'Air'
        end
        
        if is_crouched then
            if is_moving then
                return 'Move-Crouch'
            end
            return 'Crouch'
        end
        
        if is_moving then
            if is_slow_walk then
                return 'Slow Walk'
            end
            return 'Moving'
        end
        
        return 'Standing'
    end
    

    local function get_weapon_type(weapon)
        local weapon_info = csgo_weapons(weapon)
        
        if weapon_info == nil then
            return nil
        end
        
        local weapon_type = weapon_info.type
        local weapon_index = weapon_info.idx
        
        if weapon_type == 'smg' then
            return 'SMG'
        end
        
        if weapon_type == 'rifle' then
            return 'Rifles'
        end
        
        if weapon_type == 'pistol' then
            if weapon_index == 1 then
                return 'Desert Eagle'
            end
            
            if weapon_index == 64 then
                return 'Revolver R8'
            end
            
            return 'Pistols'
        end
        
        if weapon_type == 'sniperrifle' then
            if weapon_index == 40 then
                return 'Scout'
            end
            
            if weapon_index == 9 then
                return 'AWP'
            end
            
            return 'Auto Snipers'
        end
        
        return nil
    end
    
    
    local function restore_values()
        ragebot.unset(ref_double_tap[1])
        
        override.unset(ref_on_shot_antiaim[1])
        override.unset(ref_on_shot_antiaim[2])
    end
    

    local function update_values()
        ragebot.set(ref_double_tap[1], false)
        
        override.set(ref_on_shot_antiaim[1], true)
        override.set(ref_on_shot_antiaim[2], 'Always on')
    end
    

    local function should_update()
        if ui.get(ref_duck_peek_assist) then
            return false
        end
        
        local is_quick_peek_assist = (
            ui.get(ref_quick_peek_assist[1]) and
            ui.get(ref_quick_peek_assist[2])
        )
        
        if is_quick_peek_assist then
            return false
        end
        
        if not ui.get(ref_double_tap[2]) then
            return false
        end
        
        local me = entity.get_local_player()
        
        if me == nil then
            return false
        end
        
        local weapon = entity.get_player_weapon(me)
        
        if weapon == nil then
            return false
        end
        
        local weapon_type = get_weapon_type(weapon)
        
        if weapon_type == nil then
            return false
        end
        

        local selected_weapons = aimbot.auto_os_weapons:get()
        local weapon_selected = false
        for _, selected in pairs(selected_weapons) do
            if selected == weapon_type then
                weapon_selected = true
                break
            end
        end
        if not weapon_selected then
            return false
        end
        
        local state = get_state()
        
        if state == nil then
            return false
        end
        

        local selected_states = aimbot.auto_os_states:get()
        local state_selected = false
        for _, selected in pairs(selected_states) do
            if selected == state then
                state_selected = true
                break
            end
        end
        if not state_selected then
            return false
        end
        
        return true
    end
    

    local function on_shutdown()
        restore_values()
    end
    
    
    

    local function on_setup_command(cmd)
        if not should_update() then
            restore_values()
            return
        end
        
        update_values()
    end
    

    local function on_enabled(item)
        local value = item:get()
        
        if not value then
            restore_values()
        end
        
        if value then
            client.set_event_callback('shutdown', on_shutdown)
            client.set_event_callback('setup_command', on_setup_command)
        else
            client.unset_event_callback('shutdown', on_shutdown)
            client.unset_event_callback('setup_command', on_setup_command)
        end
    end
    

    aimbot.auto_os:set_callback(on_enabled, true)
end

local unsafe_charge = {}
do

    local function event_callback(event_name, callback, value)
        local fn = value and client.set_event_callback or client.unset_event_callback
        fn(event_name, callback)
    end
    

    local ragebot = {}
    local ragebot_data = {}
    
    local ref_weapon_type = ui.reference('Rage', 'Weapon type', 'Weapon type')
    
    local e_hotkey_mode = {
        [0] = 'Always on',
        [1] = 'On hotkey',
        [2] = 'Toggle', 
        [3] = 'Off hotkey'
    }
    
    local function get_value(item)
        local item_type = ui.type(item)
        local value = {ui.get(item)}
        
        if item_type == 'hotkey' then
            local mode = e_hotkey_mode[value[2]]
            local keycode = value[3] or 0
            return {mode, keycode}
        end
        
        return value
    end
    
    function ragebot.set(item, ...)
        local weapon_type = ui.get(ref_weapon_type)
        
        if ragebot_data[item] == nil then
            ragebot_data[item] = {}
        end
        
        local data = ragebot_data[item]
        
        if data[weapon_type] == nil then
            data[weapon_type] = {
                type = weapon_type,
                value = get_value(item)
            }
        end
        
        ui.set(item, ...)
    end
    
    function ragebot.unset(item)
        local data = ragebot_data[item]
        
        if data == nil then
            return
        end
        
        local weapon_type = ui.get(ref_weapon_type)
        
        for k, v in pairs(data) do
            ui.set(ref_weapon_type, v.type)
            ui.set(item, unpack(v.value))
            
            data[k] = nil
        end
        
        ui.set(ref_weapon_type, weapon_type)
        ragebot_data[item] = nil
    end
    

    local prev_state = false
    
    local ref_enabled = {
        ui.reference('Rage', 'Aimbot', 'Enabled')
    }
    
    local ref_double_tap = {
        ui.reference('Rage', 'Aimbot', 'Double tap')
    }
    
    local ref_on_shot_antiaim = {
        ui.reference('AA', 'Other', 'On shot anti-aim')
    }
    
    local function is_double_tap_active()
        return ui.get(ref_double_tap[1])
            and ui.get(ref_double_tap[2])
    end
    
    local function is_on_shot_antiaim_active()
        return ui.get(ref_on_shot_antiaim[1])
            and ui.get(ref_on_shot_antiaim[2])
    end
    
    local function is_tickbase_changed(player)
        return (globals.tickcount() - entity.get_prop(player, 'm_nTickBase')) > 0
    end
    
    local function should_change()
        local me = entity.get_local_player()
        
        if me == nil then
            return false
        end
        
        local state = is_double_tap_active()
        local charged = is_tickbase_changed(me)
        
        if prev_state ~= state then
            if state and not charged then
                return true
            end
            
            prev_state = state
        end
        
        if is_on_shot_antiaim_active() then
            return not is_tickbase_changed(me)
        end
        
        return false
    end
    
    local function on_shutdown()
        ragebot.unset(ref_enabled[1])
    end
    
    local function on_setup_command()
        if should_change() then
            ragebot.set(ref_enabled[1], false)
        else
            ragebot.unset(ref_enabled[1])
        end
    end
    
    local function on_enabled(item)
        local value = item:get()
        
        if not value then
            ragebot.unset(ref_enabled[1])
        end
        
        event_callback('shutdown', on_shutdown, value)
        event_callback('run_command', on_setup_command, value)
    end
    

    aimbot.unsafe_charge:set_callback(on_enabled, true)
end

local resolver_system = {}
do

    local resolver = {
        records = {},
        max_records = 32
    }
    

    local function is_bot(ent)
        return entity.get_steam64(ent) == 0
    end
    

    local function get_record(player)
        if not resolver.records[player] then
            resolver.records[player] = {
                last_update = 0,
                yaw_history = {},
                side = 0,
                shots = 0,
                hits = 0,
                misses = 0
            }
        end
        return resolver.records[player]
    end
    

    local function update_resolver_data()
        if not aimbot.resolver:get() then return end
        
        local players = entity.get_players(true)
        if not players then return end
        
        for _, player in pairs(players) do
            if entity.is_alive(player) and not entity.is_dormant(player) and not is_bot(player) then
                local record = get_record(player)
                local current_time = globals.curtime()
                

                local pose_param = entity.get_prop(player, 'm_flPoseParameter', 11)
                if pose_param then
                    local yaw = pose_param * 120 - 60
                    

                    table.insert(record.yaw_history, {
                        yaw = yaw,
                        time = current_time
                    })
                    

                    if #record.yaw_history > 10 then
                        table.remove(record.yaw_history, 1)
                    end
                    
                    record.last_update = current_time
                end
            end
        end
        

        for player, record in pairs(resolver.records) do
            if globals.curtime() - record.last_update > 5.0 then
                resolver.records[player] = nil
            end
        end
    end
    

    local function on_aim_fire(e)
        if not aimbot.resolver:get() then return end
        
        local target = e.target
        if target and not is_bot(target) then
            local record = get_record(target)
            record.shots = record.shots + 1
        end
    end
    

    local function on_aim_hit(e)
        if not aimbot.resolver:get() then return end
        
        local target = e.target
        if target and not is_bot(target) then
            local record = get_record(target)
            record.hits = record.hits + 1
        end
    end
    

    local function on_aim_miss(e)
        if not aimbot.resolver:get() then return end
        
        local target = e.target
        if target and not is_bot(target) then
            local record = get_record(target)
            record.misses = record.misses + 1
            

            record.side = record.side == 0 and 1 or 0
        end
    end
    

    local function on_enabled(item)
        local value = item:get()
        
        if value then
            client.set_event_callback('net_update_end', update_resolver_data)
            client.set_event_callback('aim_fire', on_aim_fire)
            client.set_event_callback('aim_hit', on_aim_hit)
            client.set_event_callback('aim_miss', on_aim_miss)
        else
            client.unset_event_callback('net_update_end', update_resolver_data)
            client.unset_event_callback('aim_fire', on_aim_fire)
            client.unset_event_callback('aim_hit', on_aim_hit)
            client.unset_event_callback('aim_miss', on_aim_miss)
            

            resolver.records = {}
        end
    end
    

    aimbot.resolver:set_callback(on_enabled, true)
end

local jump_scout_system = {}
do

    local function event_callback(event_name, callback, value)
        local fn = value and client.set_event_callback or client.unset_event_callback
        fn(event_name, callback)
    end
    

    local override = {}
    local override_data = {}
    
    local e_hotkey_mode = {
        [0] = 'Always on',
        [1] = 'On hotkey',
        [2] = 'Toggle',
        [3] = 'Off hotkey'
    }
    
    local function get_value(item)
        local item_type = ui.type(item)
        local value = {ui.get(item)}
        
        if item_type == 'hotkey' then
            local mode = e_hotkey_mode[value[2]]
            local keycode = value[3] or 0
            return {mode, keycode}
        end
        
        return value
    end
    
    function override.set(item, ...)
        if override_data[item] == nil then
            override_data[item] = get_value(item)
        end
        ui.set(item, ...)
    end
    
    function override.unset(item)
        local value = override_data[item]
        if value == nil then return end
        
        ui.set(item, unpack(value))
        override_data[item] = nil
    end
    

    local ref_air_strafe = ui.reference('Misc', 'Movement', 'Air strafe')
    

    local function should_update()
        local me = entity.get_local_player()
        
        if me == nil then
            return false
        end
        
        local weapon = entity.get_player_weapon(me)
        
        if weapon == nil then
            return false
        end
        
        local weapon_info = csgo_weapons and csgo_weapons(weapon)
        
        if weapon_info == nil then
            return false
        end
        

        if weapon_info.idx ~= 40 then
            return false
        end
        

        local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))
        local velocity2d_sqr = velocity.x * velocity.x + velocity.y * velocity.y
        
        if velocity2d_sqr > (10 * 10) then
            return false
        end
        
        return true
    end
    

    local function restore_values()
        if ref_air_strafe then
            override.unset(ref_air_strafe)
        end
    end
    

    local function on_shutdown()
        restore_values()
    end
    

    local function on_paint_ui()
        restore_values()
    end
    

    local function on_setup_command(cmd)
        if should_update() then
            if ref_air_strafe then
                override.set(ref_air_strafe, false)
            end
        else
            if ref_air_strafe then
                override.unset(ref_air_strafe)
            end
        end
    end
    

    local function on_enabled(item)
        local value = item:get()
        
        if not value then
            restore_values()
        end
        
        event_callback('shutdown', on_shutdown, value)
        event_callback('paint_ui', on_paint_ui, value)
        event_callback('setup_command', on_setup_command, value)
    end
    

    aimbot.jump_scout:set_callback(on_enabled, true)
end

local watermark_system = {}
do
    local last_fps = 0
    local update_time = 0
    local wm_kills = 0
    local wm_deaths = 0

    client.set_event_callback('player_death', function(e)
        local lp = entity.get_local_player()
        if not lp then return end
        local attacker = client.userid_to_entindex(e.attacker)
        local userid   = client.userid_to_entindex(e.userid)
        if attacker == lp then wm_kills = wm_kills + 1 end
        if userid   == lp then wm_deaths = wm_deaths + 1 end
    end)

    local function update_frametime()
        local dt = globals.frametime()
        update_time = update_time - dt
        if update_time <= 0 then
            update_time = 1.0
            last_fps = math.floor(1 / dt)
        end
    end
    
    local function get_position(width, height)
        local value = visual.watermark_position:get()
        local screen_w, screen_h = client.screen_size()
        
        local x, y = 8, 8
        
        if value == 'Top Left' then
            x, y = 8, 8
        elseif value == 'Top Right' then
            x, y = screen_w - width - 8, 8
        elseif value == 'Bottom Center' then
            x, y = (screen_w - width) / 2, screen_h - height - 8
        end
        
        return x, y
    end
    
    local function draw_rounded_box(x, y, w, h, rad, r, g, b, a)
        renderer.rectangle(x + rad, y, w - rad * 2, h, r, g, b, a)
        renderer.rectangle(x, y + rad, rad, h - rad * 2, r, g, b, a)
        renderer.rectangle(x + w - rad, y + rad, rad, h - rad * 2, r, g, b, a)
        for i = 0, rad - 1 do
            local offset = rad - i
            local width = math.floor(math.sqrt(rad * rad - offset * offset) + 0.5)

            renderer.rectangle(x + rad - width, y + i, width, 1, r, g, b, a)
            renderer.rectangle(x + w - rad, y + i, width, 1, r, g, b, a)
            renderer.rectangle(x + rad - width, y + h - i - 1, width, 1, r, g, b, a)
            renderer.rectangle(x + w - rad, y + h - i - 1, width, 1, r, g, b, a)
        end
    end

    local function draw_watermark()
        update_frametime()
        
        local style = visual.watermark_style:get()
        
        if style == 'GS' then
            local parts = {}
            local wm_r, wm_g, wm_b, wm_a = visual.watermark_gs_color:get()
            local display_alpha = wm_a == 0 and 255 or wm_a
            
            table.insert(parts, {text = 'alt', color = {255, 255, 255, 255}})
            table.insert(parts, {text = 'hea', color = {wm_r, wm_g, wm_b, display_alpha}})

            if visual.watermark_display:get('Nick') then
                table.insert(parts, {text = ' | ' .. get_username(), color = {200, 200, 200, 255}})
            end
            
            if visual.watermark_display:get('FPS') then
                table.insert(parts, {text = string.format(' | %d fps', last_fps), color = {200, 200, 200, 255}})
            end
            
            if visual.watermark_display:get('Ping') then
                table.insert(parts, {text = string.format(' | %d ms', math.floor(client.latency() * 1000)), color = {200, 200, 200, 255}})
            end
            
            if visual.watermark_display:get('Time') then
                local h, m, s = client.system_time()
                table.insert(parts, {text = string.format(' | %02d:%02d:%02d', h, m, s), color = {200, 200, 200, 255}})
            end
            
            if visual.watermark_display:get('KD') then
                local lp = entity.get_local_player()
                local kills, deaths = 0, 0
                if lp then
                    local pr = entity.get_player_resource()
                    if pr then
                        kills  = entity.get_prop(pr, 'm_iKills',  lp) or 0
                        deaths = entity.get_prop(pr, 'm_iDeaths', lp) or 0
                    end
                end
                local kd = deaths == 0 and tostring(kills) or string.format('%.1f', kills / deaths)
                table.insert(parts, {text = ' | ' .. kd .. ' kd', color = {200, 200, 200, 255}})
            end
            
            local total_width = 0
            for i = 1, #parts do
                local w = renderer.measure_text('bd', parts[i].text)
                total_width = total_width + w
            end
            
            local box_w = total_width + 15
            local box_h = 22
            local x, y = get_position(box_w, box_h)
            
            local border_width = 2
            local margin = 3
            local radius = 4
            
            local function draw_rounded_rect(x, y, w, h, r, g, b, a, rad)
                renderer.rectangle(x + rad, y, w - rad * 2, h, r, g, b, a)
                renderer.rectangle(x, y + rad, rad, h - rad * 2, r, g, b, a)
                renderer.rectangle(x + w - rad, y + rad, rad, h - rad * 2, r, g, b, a)
                
                for i = 0, rad - 1 do
                    local offset = rad - i
                    local width = math.floor(math.sqrt(rad * rad - offset * offset))
                    renderer.rectangle(x + rad - width, y + i, width, 1, r, g, b, a)
                    renderer.rectangle(x + w - rad, y + i, width, 1, r, g, b, a)
                    renderer.rectangle(x + rad - width, y + h - i - 1, width, 1, r, g, b, a)
                    renderer.rectangle(x + w - rad, y + h - i - 1, width, 1, r, g, b, a)
                end
            end
            
            draw_rounded_rect(x, y, box_w, box_h, 18, 18, 18, 255, radius)
            draw_rounded_rect(x+1, y+1, box_w-2, box_h-2, 62, 62, 62, 255, radius-1)
            draw_rounded_rect(x+2, y+2, box_w-4, box_h-4, 44, 44, 44, 255, radius-1)
            draw_rounded_rect(x+border_width+2, y+border_width+2, box_w-border_width*2-4, box_h-border_width*2-4, 62, 62, 62, 255, radius-2)
            
            local header_y = y + margin
            local header_w = box_w - margin * 2
            local line_type = visual.watermark_gs_line:get()
            
            if line_type == 'Gradient' then
                local half_w = math.floor(header_w / 2)
                local remaining_w = header_w - half_w
                renderer.gradient(x + margin, header_y, half_w, 1, 59, 175, 222, wm_a, 202, 70, 205, wm_a, true)
                renderer.gradient(x + margin + half_w, header_y, remaining_w, 1, 202, 70, 205, wm_a, 201, 227, 58, wm_a, true)
                local half_alpha = math.floor(wm_a * 0.5)
                renderer.gradient(x + margin, header_y + 1, half_w, 1, 59, 175, 222, half_alpha, 202, 70, 205, half_alpha, true)
                renderer.gradient(x + margin + half_w, header_y + 1, remaining_w, 1, 202, 70, 205, half_alpha, 201, 227, 58, half_alpha, true)
            else
                renderer.rectangle(x + margin, header_y, header_w, 1, wm_r, wm_g, wm_b, wm_a)
                renderer.rectangle(x + margin, header_y + 1, header_w, 1, wm_r, wm_g, wm_b, math.floor(wm_a * 0.5))
            end
            
            local bg_y = header_y + 3
            local bg_h = box_h - margin * 2 - 3
            renderer.rectangle(x + margin, bg_y, header_w, bg_h, 16, 16, 16, 255)
            
            local current_x = x + 6
            local text_y = y + 7
            for i = 1, #parts do
                local part = parts[i]
                local r, g, b, a = unpack(part.color)
                renderer.text(current_x, text_y, r, g, b, a, 'bd', nil, part.text)
                local w = renderer.measure_text('bd', part.text)
                current_x = current_x + w
            end
            
        elseif style == 'CE' then
            local screen_w, screen_h = client.screen_size()
            local pos_x, pos_y = 15, screen_h / 2
            
            local text_lines = {
                'ALTHEA.LUA',
                '[DEV]'
            }
            local text = table.concat(text_lines, '\n')
            local text_w, text_h = renderer.measure_text('b', text)
            
            local avatar_size = 32
            
            if ce_avatar ~= nil then
                pos_y = pos_y - avatar_size / 2
                
                ce_avatar:draw(
                    pos_x, pos_y,
                    avatar_size, avatar_size,
                    255, 255, 255, 255, 'f'
                )
                
                pos_x = pos_x + avatar_size + 5
                pos_y = pos_y + (avatar_size - text_h) / 2
            else
                pos_y = pos_y - text_h / 2
            end
            
            renderer.text(pos_x, pos_y, 255, 255, 255, 255, 'b', nil, text)
            
        else
            local wm_r, wm_g, wm_b, wm_a = visual.watermark_al_color:get()
        local blocks = {}
        table.insert(blocks, {label = 'althea', is_logo = true})

        if visual.watermark_display:get('KD') then
            local lp = entity.get_local_player()
            local kills, deaths = 0, 0
            if lp then
                local pr = entity.get_player_resource()
                if pr then
                    kills  = entity.get_prop(pr, 'm_iKills',  lp) or 0
                    deaths = entity.get_prop(pr, 'm_iDeaths', lp) or 0
                end
            end
            local kd = deaths == 0 and tostring(kills) or string.format('%.1f', kills / deaths)
            table.insert(blocks, {icon = '', label = kd .. ' KD'})
        end
        if visual.watermark_display:get('FPS') then
            table.insert(blocks, {icon = '', label = last_fps .. ' FPS'})
        end
        if visual.watermark_display:get('Ping') then
            table.insert(blocks, {icon = '', label = math.floor(client.latency() * 1000) .. ' MS'})
        end
        if visual.watermark_display:get('Nick') then
            table.insert(blocks, {icon = '', label = get_username()})
        end
        if visual.watermark_display:get('Time') then
            local h, m, s = client.system_time()
            table.insert(blocks, {icon = '', label = string.format('%02d:%02d:%02d', h, m, s)})
        end

        local pad   = 10
        local box_h = 25
        local rad   = 4
        local ty    = 7

        local widths = {}
        local total_w = 0
        for i, b in ipairs(blocks) do
            local txt = b.icon and (b.icon .. ' ' .. b.label) or b.label
            local w = renderer.measure_text('bd', txt) + pad * 2
            widths[i] = w
            total_w = total_w + w
        end

        local box_w = total_w
        local x, y = get_position(box_w, box_h)
        local function draw_althea_box(x, y, w, h, bg_r, bg_g, bg_b, bg_a, rounding, border_r, border_g, border_b, border_a, thickness)
            renderer.circle(x + rounding, y + rounding, bg_r, bg_g, bg_b, bg_a, rounding, 180, 0.25)
            renderer.rectangle(x + rounding, y, w - rounding * 2, rounding, bg_r, bg_g, bg_b, bg_a)
            renderer.circle(x + w - rounding, y + rounding, bg_r, bg_g, bg_b, bg_a, rounding, 90, 0.25)
            renderer.rectangle(x, y + rounding, w, h - rounding * 2 + 1, bg_r, bg_g, bg_b, bg_a)
            renderer.circle(x + rounding, y + h - rounding + 1, bg_r, bg_g, bg_b, bg_a, rounding, 270, 0.25)
            renderer.rectangle(x + rounding, y + h - rounding + 1, w - rounding * 2, rounding, bg_r, bg_g, bg_b, bg_a)
            renderer.circle(x + w - rounding, y + h - rounding + 1, bg_r, bg_g, bg_b, bg_a, rounding, 0, 0.25)
            local hs = thickness or 2
            renderer.rectangle(x + rounding, y, w - rounding * 2, hs, border_r, border_g, border_b, border_a)
            renderer.gradient(x - 1, y + rounding, hs, h - rounding * 2.7, border_r, border_g, border_b, border_a, border_r, border_g, border_b, 0, false)
            renderer.gradient(x + w - 1, y + rounding, hs, h - rounding * 2.7, border_r, border_g, border_b, border_a, border_r, border_g, border_b, 0, false)
            renderer.circle_outline(x + w - rounding, y + rounding, border_r, border_g, border_b, border_a, rounding, 270, 0.25, hs)
            renderer.circle_outline(x + rounding, y + rounding, border_r, border_g, border_b, border_a, rounding, 180, 0.25, hs)
        end
        pcall(function() renderer.blur(x, y, box_w, box_h) end)


        draw_althea_box(x, y, box_w, box_h, 0, 0, 0, 26, rad, wm_r, wm_g, wm_b, wm_a, 2)

        local cx = x
        for i, b in ipairs(blocks) do
            local bw  = widths[i]
            local txt = b.icon and (b.icon .. ' ' .. b.label) or b.label
            local tw  = renderer.measure_text('bd', txt)
            local tx  = cx + math.floor((bw - tw) / 2)

            if b.is_logo then
                renderer.text(tx, y + ty, 255, 255, 255, 255, 'bd', nil, b.label)
            elseif b.icon then
                local iw = renderer.measure_text('bd', b.icon .. ' ')
                renderer.text(tx,      y + ty, wm_r, wm_g, wm_b, wm_a, 'bd', nil, b.icon)
                renderer.text(tx + iw, y + ty, 220, 220, 220, 255,      'bd', nil, b.label)
            else
                renderer.text(tx, y + ty, 220, 220, 220, 255, 'bd', nil, txt)
            end

            cx = cx + bw
        end
        end
    end
    
    local function on_enabled()
        local value = visual.watermark:get()
        
        if value then
            client.set_event_callback('paint_ui', draw_watermark)
        else
            client.unset_event_callback('paint_ui', draw_watermark)
        end
    end
    
    visual.watermark:set_callback(on_enabled)
end

local animations = {}

local function lerp(name, target_value, speed, tolerance, easing_style)
    if animations[name] == nil then
        animations[name] = target_value
    end

    speed = speed or 8
    tolerance = tolerance or 0.005
    easing_style = easing_style or 'linear'
    
    local current_value = animations[name]
    local delta = globals.absoluteframetime() * speed
    local new_value
    
    if easing_style == 'linear' then
        new_value = current_value + (target_value - current_value) * delta
    elseif easing_style == 'smooth' then
        new_value = current_value + (target_value - current_value) * (delta * delta * (3 - 2 * delta))
    elseif easing_style == 'ease_in' then
        new_value = current_value + (target_value - current_value) * (delta * delta)
    elseif easing_style == 'ease_out' then
        local progress = 1 - (1 - delta) * (1 - delta)
        new_value = current_value + (target_value - current_value) * progress
    elseif easing_style == 'ease_in_out' then
        local progress = delta < 0.5 and 2 * delta * delta or 1 - math.pow(-2 * delta + 2, 2) / 2
        new_value = current_value + (target_value - current_value) * progress
    else
        new_value = current_value + (target_value - current_value) * delta
    end

    if math.abs(target_value - new_value) <= tolerance then
        animations[name] = target_value
    else
        animations[name] = new_value
    end
    
    return animations[name]
end

local exploits = (function()
    local g_ctx = {
        local_player = nil,
        weapon = nil,
        aimbot = ui.reference("RAGE", "Aimbot", "Enabled"),
        doubletap = {ui.reference("RAGE", "Aimbot", "Double tap")},
        hideshots = {ui.reference("AA", "Other", "On shot anti-aim")},
        fakeduck = ui.reference("RAGE", "Other", "Duck peek assist")
    }
    
    local clamp = function(value, min, max)
        return math.min(math.max(value, min), max)
    end
    
    local exploits_obj = {
        max_process_ticks = (math.abs(client.get_cvar("sv_maxusrcmdprocessticks") or 16) - 1),
        tickbase_difference = 0,
        ticks_processed = 0,
        command_number = 0,
        choked_commands = 0,
        need_force_defensive = false,
        current_shift_amount = 0,
        
        reset_vars = function(self)
            self.ticks_processed = 0
            self.tickbase_difference = 0
            self.choked_commands = 0
            self.command_number = 0
        end,
        
        store_vars = function(self, ctx)
            self.command_number = ctx.command_number or 0
            self.choked_commands = ctx.chokedcommands or 0
        end,
        
        store_tickbase_difference = function(self, ctx)
            if ctx.command_number == self.command_number then
                local tickbase = entity.get_prop(g_ctx.local_player, "m_nTickBase") or 0
                self.ticks_processed = clamp(math.abs(tickbase - (self.tickbase_difference or 0)), 0, (self.max_process_ticks or 0) - (self.choked_commands or 0))
                self.tickbase_difference = math.max(tickbase, self.tickbase_difference or 0)
                self.command_number = 0
            end
        end,
        
        is_doubletap = function(self)
            return ui.get(g_ctx.doubletap[2])
        end,
        
        is_active = function(self)
            return self:is_doubletap()
        end,
        
        in_defensive = function(self, max)
            max = max or self.max_process_ticks
            return self:is_active() and (self.ticks_processed > 1 and self.ticks_processed < max)
        end,
        
        is_defensive_ended = function(self)
            return not self:in_defensive() or ((self.ticks_processed >= 0 and self.ticks_processed <= 5) and (self.tickbase_difference or 0) > 0)
        end,
        
        can_recharge = function(self)
            if not self:is_active() then return false end
            local tickbase = entity.get_prop(g_ctx.local_player, "m_nTickBase") or 0
            local curtime = globals.tickinterval() * (tickbase - 16)
            if curtime < (entity.get_prop(g_ctx.local_player, "m_flNextAttack") or 0) then return false end
            if curtime < (entity.get_prop(g_ctx.weapon, "m_flNextPrimaryAttack") or 0) then return false end
            return true
        end,
        
        in_recharge = function(self)
            if not (self:is_active() and self:can_recharge()) or self:in_defensive() then return false end
            local latency_shift = math.ceil(client.latency() / globals.tickinterval() * 1.25)
            local current_shift_amount = (((self.tickbase_difference or 0) - globals.tickcount()) * -1) + latency_shift
            local max_shift_amount = (self.max_process_ticks - 1) - latency_shift
            local min_shift_amount = -(self.max_process_ticks - 1) + latency_shift
            if latency_shift ~= 0 then
                return current_shift_amount > min_shift_amount and current_shift_amount < max_shift_amount
            else
                return current_shift_amount > (min_shift_amount / 2) and current_shift_amount < (max_shift_amount / 2)
            end
        end
    }
    

    client.set_event_callback('setup_command', function(ctx)
        if not (entity.get_local_player() and entity.is_alive(entity.get_local_player()) and entity.get_player_weapon(entity.get_local_player())) then return end
        g_ctx.local_player = entity.get_local_player()
        g_ctx.weapon = entity.get_player_weapon(g_ctx.local_player)
        exploits_obj:store_vars(ctx)
    end)
    
    client.set_event_callback('predict_command', function(ctx)
        exploits_obj:store_tickbase_difference(ctx)
    end)
    
    client.set_event_callback('player_death', function(ctx)
        if not (ctx.userid and ctx.attacker) then return end
        if g_ctx.local_player ~= client.userid_to_entindex(ctx.userid) then return end
        exploits_obj:reset_vars()
    end)
    
    client.set_event_callback('round_start', function() exploits_obj:reset_vars() end)
    client.set_event_callback('round_end', function() exploits_obj:reset_vars() end)
    
    return exploits_obj
end)()


local arrows_system = {}
do
    local arrows = {
        left_value = 0,
        right_value = 0,
        forward_value = 0
    }
    
    local PADDING = 40
    
    local function round(num)
        return math.floor(num + 0.5)
    end
    
    local function draw_left_arrow(x, y, r, g, b, a, alpha)
        if alpha <= 0 then return end
        
        local flags, text = '+', '<'
        local text_w, text_h = renderer.measure_text(flags, text)
        
        x = x - round(text_w - 1)
        y = y - round(text_h / 2)
        
        renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)
    end
    
    local function draw_right_arrow(x, y, r, g, b, a, alpha)
        if alpha <= 0 then return end
        
        local flags, text = '+', '>'
        local text_w, text_h = renderer.measure_text(flags, text)
        
        y = y - round(text_h / 2)
        
        renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)
    end
    
    local function draw_forward_arrow(x, y, r, g, b, a, alpha)
        if alpha <= 0 then return end
        
        local flags, text = '+', '^'
        local text_w, text_h = renderer.measure_text(flags, text)
        
        x = x - round(text_w / 2)
        y = y - round(text_h * 0.5)
        
        renderer.text(x, y, r, g, b, a * alpha, flags, nil, text)
    end
    
    local function draw_arrows()
        if not visual.arrows:get() then return end
        
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        
        local screen_w, screen_h = client.screen_size()
        local center_x = screen_w / 2
        local center_y = screen_h / 2
        

        local r, g, b, a = visual.arrows_color:get()
        
 
        local manual_left = manual_dir == 1
        local manual_right = manual_dir == 2
        local manual_forward = manual_dir == 3

        local function lerp(current, target, speed)
            return current + (target - current) * globals.frametime() * speed
        end
        
        arrows.left_value = lerp(arrows.left_value, manual_left and 1 or 0, 10)
        arrows.right_value = lerp(arrows.right_value, manual_right and 1 or 0, 10)
        arrows.forward_value = lerp(arrows.forward_value, manual_forward and 1 or 0, 10)

        draw_left_arrow(center_x - PADDING * arrows.left_value, center_y, r, g, b, a, arrows.left_value)
        draw_right_arrow(center_x + PADDING * arrows.right_value, center_y, r, g, b, a, arrows.right_value)
        draw_forward_arrow(center_x, center_y - PADDING * arrows.forward_value, r, g, b, a, arrows.forward_value)
    end
    
    local function on_arrows_enabled(item)
        local value = item:get()
        
        if value then
            client.set_event_callback('paint_ui', draw_arrows)
        else
            client.unset_event_callback('paint_ui', draw_arrows)
        end
    end
    
    visual.arrows:set_callback(on_arrows_enabled, true)
end

local damage_system = {}
do
    local damage_alpha = 0
    local damage_value = 0
    local override_alpha = 0
    local dragging = false
    local drag_offset_x = 0
    local drag_offset_y = 0
    

    local saved_pos = db.read("damage_position") or {x = 35, y = -8}
    
    local function lerp(a, b, t)
        return a + (b - a) * t
    end
    
    local font_flags = {
        ['Small'] = 'c-',
        ['Default'] = 'c',
        ['Bold'] = 'c+',
        ['Large'] = 'cb'
    }
    
    local function draw_damage_indicator()
        if not visual.damage:get() then return end
        
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        
        local screen_w, screen_h = client.screen_size()
        local center_x = screen_w / 2
        local center_y = screen_h / 2
        
       
        local damage_ref = ui.reference("RAGE", "Aimbot", "Minimum damage")
        local damage_override = {ui.reference("RAGE", "Aimbot", "Minimum damage override")}
        

        local is_override = ui.get(damage_override[1]) and ui.get(damage_override[2])
        local target_damage = is_override and ui.get(damage_override[3]) or ui.get(damage_ref)
        

        damage_value = lerp(damage_value, target_damage, globals.frametime() * 16)

        override_alpha = lerp(override_alpha, is_override and 1 or 0, globals.frametime() * 8)
        
  
        local rounded_damage = math.floor(damage_value + 0.5)
        local text = rounded_damage == 0 and "A" or rounded_damage > 100 and "+" .. (rounded_damage - 100) or tostring(rounded_damage)
        
    
        local base_alpha = lerp(96, 255, override_alpha)
        
      
        local r, g, b = visual.damage_color:get()
        

        local x = center_x + saved_pos.x
        local y = center_y + saved_pos.y
        

        local font_name = visual.damage_font:get()
        local font = font_flags[font_name] or 'c-'
        

        if ui.is_menu_open() then
            local mouse_x, mouse_y = ui.mouse_position()
            local text_w, text_h = renderer.measure_text(font, text)
            
    
            if mouse_x >= x - text_w/2 - 5 and mouse_x <= x + text_w/2 + 5 and
               mouse_y >= y - text_h/2 - 5 and mouse_y <= y + text_h/2 + 5 then
                

                if client.key_state(0x01) then
                    if not dragging then
                        dragging = true
                        drag_offset_x = mouse_x - x
                        drag_offset_y = mouse_y - y
                    end
                end
            end
            

            if dragging then
                if client.key_state(0x01) then
                    local new_x = mouse_x - drag_offset_x - center_x
                    local new_y = mouse_y - drag_offset_y - center_y
                    saved_pos.x = new_x
                    saved_pos.y = new_y
                    db.write("damage_position", saved_pos)
                    x = center_x + new_x
                    y = center_y + new_y
                else
                    dragging = false
                end
            end
            
   
            renderer.rectangle(x - text_w/2 - 3, y - text_h/2 - 3, text_w + 6, text_h + 6, 255, 255, 255, 30)
            renderer.rectangle(x - text_w/2 - 2, y - text_h/2 - 2, text_w + 4, text_h + 4, 255, 255, 255, 60)
        end
        
        renderer.text(x, y, r, g, b, base_alpha, font, nil, text)
    end
    
    local function on_damage_enabled(item)
        local value = item:get()
        
        if value then
            client.set_event_callback('paint_ui', draw_damage_indicator)
        else
            client.unset_event_callback('paint_ui', draw_damage_indicator)
        end
    end
    
    visual.damage:set_callback(on_damage_enabled, true)
end

local scope_lines_system = {}
do
    local function lerp(a, b, t)
        return a + (b - a) * t
    end
    
    local alpha_value = 0
    

    local scope_overlay_ref = pui.reference('visuals', 'effects', 'remove scope overlay')
    
    local function on_paint_ui()
        if visual.scope_lines:get() then
            scope_overlay_ref:override(true)
        else
            scope_overlay_ref:override()
        end
    end
    
    local function draw_scope_lines()
        if not visual.scope_lines:get() then 
            scope_overlay_ref:override()
            return 
        end
        
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        
        local weapon = entity.get_player_weapon(me)
        if not weapon then return end
        

        scope_overlay_ref:override(false)
        
        local scope_level = entity.get_prop(weapon, 'm_zoomLevel')
        local scoped = entity.get_prop(me, 'm_bIsScoped') == 1
        local resume_zoom = entity.get_prop(me, 'm_bResumeZoom') == 1
        local is_valid = scope_level ~= nil
        local act = is_valid and scope_level > 0 and scoped and not resume_zoom
        
        alpha_value = lerp(alpha_value, act and 255 or 0, globals.frametime() * 4)
        
        if alpha_value < 1 then return end
        
        local screen_x, screen_y = client.screen_size()
        local x, y = screen_x / 2, screen_y / 2
        
        local gap = visual.scope_gap:get()
        local length = visual.scope_size:get()
        local inverted = visual.scope_invert:get()
        

        local r, g, b, a = visual.scope_color:get()
        r, g, b = r or 255, g or 255, b or 255
        

        renderer.gradient(x - gap, y, -length * (alpha_value / 255), 1, 
            r, g, b, inverted and 0 or alpha_value, 
            r, g, b, inverted and alpha_value or 0, true)
        

        renderer.gradient(x + gap, y, length * (alpha_value / 255), 1, 
            r, g, b, inverted and 0 or alpha_value, 
            r, g, b, inverted and alpha_value or 0, true)
        

        renderer.gradient(x, y - gap, 1, -length * (alpha_value / 255), 
            r, g, b, inverted and 0 or alpha_value, 
            r, g, b, inverted and alpha_value or 0, false)
        

        renderer.gradient(x, y + gap, 1, length * (alpha_value / 255), 
            r, g, b, inverted and 0 or alpha_value, 
            r, g, b, inverted and alpha_value or 0, false)
    end
    
    local function on_scope_lines_enabled(item)
        local value = item:get()
        
        if value then
            client.set_event_callback('paint_ui', on_paint_ui)
            client.set_event_callback('paint', draw_scope_lines)
        else
            client.unset_event_callback('paint_ui', on_paint_ui)
            client.unset_event_callback('paint', draw_scope_lines)
            scope_overlay_ref:override()
        end
    end
    
    visual.scope_lines:set_callback(on_scope_lines_enabled, true)
end

local fallback_text_system = {}
do
    local gradient_time = 0
    
    local function draw_fallback_text()
 
        if visual.watermark:get() then
            return
        end
        
        local screen_w, screen_h = client.screen_size()
        local text = "althea"
        local r, g, b, a = visual.accent_color.get()
        
      
        if a == 0 then
            a = 255
        end
        
      
        local x = screen_w / 2
        local y = screen_h - 30
        
      
        gradient_time = gradient_time + globals.frametime() * 2
        
        
        local text_width = renderer.measure_text('cb', text)
        local char_count = #text
        local start_x = x - text_width / 2
        
        for i = 1, char_count do
            local char = text:sub(i, i)
            local progress = (i - 1) / (char_count - 1)
            
          
            local wave = (math.sin(gradient_time - progress * 6) + 1) / 2
            
           
            local char_r = math.floor(0 + (r - 0) * wave)
            local char_g = math.floor(0 + (g - 0) * wave)
            local char_b = math.floor(0 + (b - 0) * wave)
            
            local char_x = start_x + renderer.measure_text('b', text:sub(1, i-1))
            renderer.text(char_x, y, char_r, char_g, char_b, a, 'b', nil, char)
        end
    end
    

    client.set_event_callback('paint_ui', draw_fallback_text)
end

local viewmodel_system = {}
do
    local viewmodel = { fov = 68, x = 2.5, y = 0, z = -1.5 }
    
    local function lerp(a, b, t)
        return a + (b - a) * t
    end
    

    local cvar_righthand = client.get_cvar("cl_righthand")
    
    local function update_viewmodel()
        if visual.viewmodel:get() then
            viewmodel.fov = visual.vm_fov:get()
            viewmodel.x = visual.vm_x:get() / 10
            viewmodel.y = visual.vm_y:get() / 10
            viewmodel.z = visual.vm_z:get() / 10
        else
            viewmodel.fov = 68
            viewmodel.x = 2.5
            viewmodel.y = 0
            viewmodel.z = -1.5
        end
        
        cvar.viewmodel_fov:set_raw_float(viewmodel.fov)
        cvar.viewmodel_offset_x:set_raw_float(viewmodel.x)
        cvar.viewmodel_offset_y:set_raw_float(viewmodel.y)
        cvar.viewmodel_offset_z:set_raw_float(viewmodel.z)
        
      
        if visual.viewmodel:get() and visual.vm_flip_knife:get() then
            local me = entity.get_local_player()
            if me and entity.is_alive(me) then
                local weapon = entity.get_player_weapon(me)
                if weapon then
                    local weapon_classname = entity.get_classname(weapon)
                    if weapon_classname == "CKnife" or weapon_classname:find("Knife") then
                        client.exec("cl_righthand 0")
                    else
                        client.exec("cl_righthand 1")
                    end
                end
            end
        else
            client.exec("cl_righthand 1")
        end
    end
    
    local function on_enabled(item)
        local value = item:get()
        
        if value then
            client.set_event_callback('paint', update_viewmodel)
        else
            client.unset_event_callback('paint', update_viewmodel)
            client.exec("cl_righthand 1")
        end
    end
    

    visual.viewmodel:set_callback(on_enabled, true)
end

local aspect_system = {}
do
    local function update_aspect()
        local enabled = visual.aspect_ratio:get()
        
        if not enabled then
            cvar.r_aspectratio:set_int(0)
            return
        end
        
        local target = visual.aspect_val:get() / 100
        cvar.r_aspectratio:set_float(target)
    end
    
    local function on_enabled(item)
        local value = item:get()
        
        if value then
            client.set_event_callback('paint', update_aspect)
        else
            client.unset_event_callback('paint', update_aspect)
            cvar.r_aspectratio:set_int(0)
        end
    end
    

    visual.aspect_ratio:set_callback(on_enabled, true)
    visual.aspect_val:set_callback(update_aspect)
end

local notifications_system = {}


do

    local color do
        local helpers = {
            RGBtoHEX = function (col, short)
                return string.format(short and "%02X%02X%02X" or "%02X%02X%02X%02X", col.r, col.g, col.b, col.a)
            end,
            HEXtoRGB = function (hex)
                hex = string.gsub(hex, "^#", "")
                return tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16), tonumber(string.sub(hex, 7, 8), 16) or 255
            end
        }
        
        local create
        local mt = {
            __eq = function (a, b)
                return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
            end,
            lerp = function (f, t, w)
                return create(f.r + (t.r - f.r) * w, f.g + (t.g - f.g) * w, f.b + (t.b - f.b) * w, f.a + (t.a - f.a) * w)
            end,
            to_hex = helpers.RGBtoHEX,
            alphen = function (self, a, r)
                return create(self.r, self.g, self.b, r and a * self.a or a)
            end,
        }
        mt.__index = mt
        
        create = function(r, g, b, a)
            return setmetatable({r = r, g = g, b = b, a = a}, mt)
        end
        
        color = setmetatable({
            rgb = function (r,g,b,a)
                r = math.min(r or 255, 255)
                return create(r, g and math.min(g, 255) or r, b and math.min(b, 255) or r, a and math.min(a, 255) or 255)
            end,
            hex = function (hex)
                local r,g,b,a = helpers.HEXtoRGB(hex)
                return create(r,g,b,a)
            end
        },{
            __call = function (self, r, g, b, a)
                return type(r) == "string" and self.hex(r) or self.rgb(r, g, b, a)
            end,
        })
    end
    
    local colors = {
        hex = "\a74A6A9FF",
        accent = color.hex("74A6A9"),
        back = color.rgb(23, 26, 28),
        dark = color.rgb(5, 6, 8),
        white = color.rgb(255),
        black = color.rgb(0),
        null = color.rgb(0, 0, 0, 0),
        text = color.rgb(230),
        panel = {
            l1 = color.rgb(5, 6, 8, 180),
            g1 = color.rgb(5, 6, 8, 140),
            l2 = color.rgb(23, 26, 28, 96),
            g2 = color.rgb(23, 26, 28, 140),
        }
    }
    
 
    local anima do
        local animators = setmetatable({}, {__mode = "kv"})
        local frametime = globals.absoluteframetime()
        local g_speed = 1
        
      
        local function clamp(val, min, max)
            return math.min(math.max(val, min), max)
        end
        
        anima = {
            pulse = 0,
            
            easings = {
                pow = {
                    function (x, p) return 1 - ((1 - x) ^ (p or 3)) end,
                    function (x, p) return x ^ (p or 3) end,
                    function (x, p) return x < 0.5 and 4 * math.pow(x, p or 3) or 1 - math.pow(-2 * x + 2, p or 3) * 0.5 end,
                }
            },
            
            lerp = function (a, b, s, t)
                local c = a + (b - a) * frametime * (s or 8) * g_speed
                return math.abs(b - c) < (t or .005) and b or c
            end,
            
            condition = function (id, c, s, e)
                local ctx = id[1] and id or animators[id]
                if not ctx then animators[id] = { c and 1 or 0, c }; ctx = animators[id] end
                
                s = s or 4
                local cur_s = s
                if type(s) == "table" then cur_s = c and s[1] or s[2] end
                
                ctx[1] = clamp(ctx[1] + ( frametime * math.abs(cur_s) * g_speed * (c and 1 or -1) ), 0, 1)
                
                return (ctx[1] % 1 == 0 or cur_s < 0) and ctx[1] or
                anima.easings.pow[e and (c and e[1][1] or e[2][1]) or (c and 1 or 3)](ctx[1], e and (c and e[1][2] or e[2][2]) or 3)
            end
        }
        
        client.set_event_callback('paint_ui', function ()
            anima.pulse = math.abs(globals.realtime() * 1 % 2 - 1)
            frametime = globals.absoluteframetime()
        end)
    end
    
  
    local render do
        local alpha = 1
        local astack = {}
        local blurs = {}
        
        client.set_event_callback('paint', function ()
            for i = 1, #blurs do
                local v = blurs[i]
                if v then renderer.blur(v[1], v[2], v[3], v[4]) end
            end
            blurs = {}
        end)
        
        render = {
            push_alpha = function (v)
                local len = #astack
                astack[len+1] = v
                alpha = alpha * astack[len+1] * (astack[len] or 1)
            end,
            pop_alpha = function ()
                local len = #astack
                astack[len], len = nil, len-1
                alpha = len == 0 and 1 or astack[len] * (astack[len-1] or 1)
            end,
            get_alpha = function ()  return alpha  end,
            
            blur = function (x, y, w, h, a, s)
                blurs[#blurs+1] = {math.floor(x), math.floor(y), math.floor(w), math.floor(h)}
            end,
            
            rectangle = function (x, y, w, h, c, n)
                x, y, w, h, n = math.floor(x), math.floor(y), math.floor(w), math.floor(h), n and math.floor(n) or 0
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
            end,
            
            text = function (x, y, c, flags, width, ...)
                renderer.text(x, y, c.r, c.g, c.b, c.a * alpha, flags or "", width or 0, ...)
            end,
            
            measure_text = function (flags, text)
                if not text or text == "" then return 0, 0 end
                text = text:gsub("\a%x%x%x%x%x%x%x%x", "")
                return renderer.measure_text(flags, text)
            end,
        }
    end
    
   
    local enums = {
        hitgroups = {'generic', 'head', 'chest', 'stomach', 'left arm', 'right arm', 'left leg', 'right leg', 'neck', '?', 'gear'},
    }
    
    local logger = {
        list = {},
        stack = {},
        colors = {
            ["hit"] = {"\aA3D350", "\aA3D350\x01", "\x06", color.hex("A3D350")},
            ["miss"] = {"\aA67CCF", "\aA67CCF\x01", "\x03", color.hex("A67CCF")},
            ["harm"] = {"\ad35050", "\ad35050\x01", "\x07", color.hex("d35050")},
        },
    }
    
    local ternary = function (c, a, b)  if c then return a else return b end  end
    local lerp = function (a, b, t) return a + (b - a) * t end
    
   
    local function render_log_part(log, offset, progress, condition, i, center_x)
        local text = string.gsub(log.text, "[\x01\x02]", {
            ["\x01"] = string.format("%02x", progress * render.get_alpha() * 255),
            ["\x02"] = string.format("%02x", progress * render.get_alpha() * 128),
        })
        
       
        local clean_text = text:gsub("•\aE6E6E6\x02 ", "")
        local tw, th = renderer.measure_text('b', clean_text)
        
     
        local notif_r, notif_g, notif_b, notif_a = visual.notifications_color:get()
        local notif_color = color.rgb(notif_r or 160, notif_g or 240, notif_b or 169, math.floor((notif_a or 255) * progress))
        
     
        local logo_text = "althea"
        local logo_w = renderer.measure_text('b', logo_text)
        local left_w = logo_w + 20 
        local right_w = tw + 20  
        local h = 24
        local gap = 10  
        
        local total_w = left_w + gap + right_w
        local x = center_x - total_w / 2
        local y = offset
        
        
        if not condition then
            x = x + (1 - progress) * (total_w * 0.5) * (i % 2 == 0 and -1 or 1)
        end
        
       
        renderer.blur(x, y, total_w, h)
        local mask_alpha = math.floor(progress * 30)
        renderer.rectangle(x, y, total_w, h, 0, 0, 0, mask_alpha)
        renderer.rectangle(x, y, total_w, 1, notif_r or 160, notif_g or 240, notif_b or 169, math.floor((notif_a or 255) * progress * 0.3))
        renderer.rectangle(x, y + h - 1, total_w, 1, notif_r or 160, notif_g or 240, notif_b or 169, math.floor((notif_a or 255) * progress * 0.3))
        
        
        local logo_x = x + 10
        local logo_y = y + 6
        
        renderer.text(logo_x + 1, logo_y + 1, 0, 0, 0, math.floor((notif_a or 255) * progress * 0.5), 'b', nil, logo_text)
        
        renderer.text(logo_x, logo_y, notif_r or 160, notif_g or 240, notif_b or 169, math.floor((notif_a or 255) * progress), 'b', nil, logo_text)
        
        
        local separator_x = x + left_w + gap / 2
        renderer.rectangle(separator_x, y + 4, 1, h - 8, notif_r or 160, notif_g or 240, notif_b or 169, math.floor((notif_a or 255) * progress * 0.2))
        
        
        local text_x = x + left_w + gap + 10
        local text_y = y + 6
    
        renderer.text(text_x + 1, text_y + 1, 0, 0, 0, math.floor((notif_a or 255) * progress * 0.5), 'b', nil, clean_text)
      
        renderer.text(text_x, text_y, notif_r or 160, notif_g or 240, notif_b or 169, math.floor((notif_a or 255) * progress), 'b', nil, clean_text)
    end
    
    
    local function render_notifications()
        if not (visual.notifications:get() and visual.notifications_type:get('Screen')) then return end
        
        local screen_w, screen_h = client.screen_size()
        local center_x = screen_w / 2
        local y = screen_h - 240 + 4  
        
        local continue
        
        for i = 1, #logger.list do
            local v = logger.list[i]
            local ascend = (globals.realtime() - v.time) < 4 and i < 10
            
            local progress = anima.condition(v.progress, ascend)
            if progress == 0 then continue = i end
            
            render.push_alpha(progress)
            render_log_part(v, y, progress, ascend, i, center_x)
            render.pop_alpha()
            
            y = y + 35 * (ascend and progress or 1) 
        end
        
        if continue then
            table.remove(logger.list, continue)
        end
    end
    
    
    local function on_notifications_enabled()
        local enabled = visual.notifications:get()
        local screen_enabled = enabled and visual.notifications_type:get('Screen')
        
        if screen_enabled then
            client.set_event_callback('paint', render_notifications)
        else
            client.unset_event_callback('paint', render_notifications)
        end
    end
    
    visual.notifications:set_callback(on_notifications_enabled, true)
    visual.notifications_type:set_callback(on_notifications_enabled, true)
end



config.configs = {}

local function update_colors()
    if not colors or not colors.get_accent then return end
    
    local accent = colors.get_accent()
    
    if info and info.welcome then
        info.welcome:set('\aFFFFFFFFWelcome, ' .. accent .. loader_username .. '\aFFFFFFFF!')
    end
    if info and info.build_source then
        info.build_source:set('\aFFFFFFFFYour build: ' .. accent .. 'Developer')
    end
end


client.delay_call(0.1, update_colors)

client.delay_call(0.1, function()
    configs.data = pui.setup({
        visual = {
            watermark = visual.watermark,
            watermark_style = visual.watermark_style,
            watermark_gs_color = visual.watermark_gs_color,
            watermark_gs_line = visual.watermark_gs_line,
            watermark_display = visual.watermark_display,
            watermark_position = visual.watermark_position,
            notifications = visual.notifications,
            notifications_color = visual.notifications_color,
            notifications_type = visual.notifications_type,
            screen_indicators = visual.screen_indicators,
            screen_indicators_glow = visual.screen_indicators_glow,
            arrows = visual.arrows,
            arrows_color = visual.arrows_color,
            damage = visual.damage,
            damage_color = visual.damage_color,
            damage_font = visual.damage_font,
            scope_lines = visual.scope_lines,
            scope_gap = visual.scope_gap,
            scope_size = visual.scope_size,
            scope_invert = visual.scope_invert,
            scope_color = visual.scope_color,
            viewmodel = visual.viewmodel,
            vm_fov = visual.vm_fov,
            vm_x = visual.vm_x,
            vm_y = visual.vm_y,
            vm_z = visual.vm_z,
            vm_flip_knife = visual.vm_flip_knife,
            aspect_ratio = visual.aspect_ratio,
            aspect_val = visual.aspect_val
        },
        aimbot = {
            resolver = aimbot.resolver,
            resolver_type = aimbot.resolver_type,
            unsafe_charge = aimbot.unsafe_charge,
            auto_os = aimbot.auto_os,
            auto_os_weapons = aimbot.auto_os_weapons,
            auto_os_states = aimbot.auto_os_states,
            jump_scout = aimbot.jump_scout,
            rage_logic = aimbot_rage.logic,
            rage_force_baim = aimbot_rage.force_baim,
            rage_force_baim_miss = aimbot_rage.force_baim_miss,
            rage_force_safety = aimbot_rage.force_safety,
            rage_force_safety_miss = aimbot_rage.force_safety_miss,
            rage_delay_shot = aimbot_rage.delay_shot
        },
        antiaim = {
            aapick = b_2.aa.aapick,
            state = b_2.aa.main.state,
            key_left = b_2.aa.advanced.key_left,
            key_right = b_2.aa.advanced.key_right,
            key_reset = b_2.aa.advanced.key_reset,
            key_freestand = b_2.aa.advanced.key_freestand,
            antibackstab = b_2.aa.advanced.antibackstab,
            safehead = b_2.aa.advanced.safehead,
            options = b_2.aa.advanced.options,
            fastladder = b_2.aa.advanced.fastladder,
            builder = builder
        },
        misc = {
            clantag = misc.clantag,
            trashtalk = misc.trashtalk,
            trashtalk_events = misc.trashtalk_events,
            trashtalk_language = misc.trashtalk_language,
            console_filter = misc.console_filter,
            fast_ladder = misc.fast_ladder,
            buybot_enabled = misc.buybot.enabled,
            buybot_primary = misc.buybot.primary,
            buybot_secondary = misc.buybot.secondary,
            buybot_utility = misc.buybot.utility,
            buybot_equipment = misc.buybot.equipment,
            buybot_pistol_kevlar = misc.buybot.pistol_kevlar,
            animation_breaker = misc.animation_breaker
        }
    }, true)
    

    configs.update_list()
end)

local clantag_system = {}
do
    local animation_frames = {
        "",
        "6", 
        "a7", 
        "alt", 
        "alt3", 
        "alth1", 
        "althe", 
        "atlhea", 
        "althea$", 
        "althea.7", 
        "althea.l9", 
        "althea.lu#", 
        "althea.lua"
    }
    
    local current_frame = 1
    local last_update = 0
    local frame_delay = 0.3
    local direction = 1
    
    local function update_clantag()
        if not misc.clantag:get() then
            client.set_clan_tag('')
            return
        end
        
        local current_time = globals.realtime()
        
        if current_time - last_update >= frame_delay then
            client.set_clan_tag(animation_frames[current_frame])
            
            current_frame = current_frame + direction
            
            if current_frame > #animation_frames then
                current_frame = #animation_frames - 1
                direction = -1
            elseif current_frame < 1 then
                current_frame = 2
                direction = 1
            end
            
            last_update = current_time
        end
    end
    
    local function on_enabled(item)
        local value = item:get()
        
        if value then
            client.set_event_callback('paint', update_clantag)
        else
            client.unset_event_callback('paint', update_clantag)
            client.set_clan_tag('')
        end
    end
    
    misc.clantag:set_callback(on_enabled, true)
end

local trashtalk_system = {}
do
    local phrases = {
        english = {
            kill = {
                "by althea",
                "Bruh, you aiming or praying?",
                "Is your mouse broken or are you just that bad?",
                "althea lifetime key in morse : # # # # / # # # / # # # # # # # # # / # # # / # # # # # # # / # # # # # / # # # / ..... ----- ----. ----- / # / .---- --... / # # # / # # # #",
                "ⓐⓛⓣⓗⓔⓐ ⓡⓔⓒⓞⓓⓔ",
                "bruh, your aim is like a potato on a spin cycle",
                "член в заднице у cullinan A L T H E A R E C O D E",
                " [A L T H E A - R E C O D E ] ",
                "₳₤₮Ⱨ€₳ ฿€₦Đ ₲Ɽ€€₮ł₦₲$ ₱₳Ɽ₳₳ ₵Ø₦₳ Đ₳ ₮Ʉ₳ ₥₳€"
            },
            death = {
                "lucky",
                "i can't believe i can die"
            }
        },
        russian = {
            kill = {
                "летит крузак 300 позади крики бассоты",
                "ответы на ОГЭ/ЕГЭ в шапке профиля",
                "1",
                "тебе ключ на althea дать?",
                "найс я антипопадайки сделал куртые",
                "убил тебя нищ без 5090",
                "подбил тебя как отца твоего в окопе",
                "хватит надеется на удачу купи алфею",
                "убил тебя",
                "тебя только время исправит",
                "поиграй с алфеей я хз",
                "кто скинет ножки?",
                "у тебя лаги или ты по жизни такой медленный?",
                "спи моча",
                "во дебил опять умер"
            },
            death = {
                "пидорас ебаный",
                "просто бред",
                "хуеглот блядь",
                "ну ебанат блядь",
                "ну маму ебал ты как убил меня",
                "фу блядота с нлом убивает опять",
                "а тимейт как всегда встал словно камень",
                "КАК ТЫ УБИЛ МЕНЯ Я ЖЕ БРИКНУЛ",
                "это в сколько тиков?",
                "ублюдина",
                "потужно",
                "ты так бонуска в собаках редко,но метко",
                "урод",
                "чит еще не научился предиктить такого долбаеба"
            }
        }
    }
    
    local function send_message(message)
        client.exec('say ' .. message)
    end
    
    local function get_random_phrase(event_type)
        if not misc.trashtalk:get() then return end
        
        local events = misc.trashtalk_events:get()
        local language_setting = misc.trashtalk_language:get()
        

        local event_enabled = false
        for _, selected_event in pairs(events) do
            if (event_type == 'kill' and selected_event == 'Kill') or 
               (event_type == 'death' and selected_event == 'Death') then
                event_enabled = true
                break
            end
        end
        
        if not event_enabled then return end
        

        if language_setting == 'Bait' then
            if event_type == 'kill' then
                client.delay_call(2.0, function()
                    send_message('1')
                end)
            end

            return
        end
        

        local language = language_setting == 'English' and 'english' or 'russian'
        local phrase_list = phrases[language][event_type]
        if phrase_list and #phrase_list > 0 then
            local random_phrase = phrase_list[client.random_int(1, #phrase_list)]
            if random_phrase then
                client.delay_call(2.0, function()
                    send_message(random_phrase)
                end)
            end
        end
    end
    
    local function on_player_death(e)
        local me = entity.get_local_player()
        if not me then return end
        
        local attacker = client.userid_to_entindex(e.attacker)
        local victim = client.userid_to_entindex(e.userid)
        

        if attacker == me and victim ~= me then
            get_random_phrase('kill')
        end
        

        if victim == me and attacker ~= me then
            get_random_phrase('death')
        end
    end
    
    local function on_enabled(item)
        local value = item:get()
        
        if value then
            client.set_event_callback('player_death', on_player_death)
        else
            client.unset_event_callback('player_death', on_player_death)
        end
    end
    

    misc.trashtalk:set_callback(on_enabled, true)
end

local console_filter_system = {}
do
    local function on_enabled(item)
        local value = item:get()
        
        client.delay_call(0, function()
            cvar.con_filter_enable:set_int(value and 1 or 0)
            cvar.con_filter_text:set_string(value and 'althea [1.0]' or '')
        end)
    end
    

    misc.console_filter:set_callback(on_enabled, true)
    

    client.set_event_callback('shutdown', function()
        cvar.con_filter_enable:set_int(0)
        cvar.con_filter_text:set_string('')
    end)
end

local buybot_system = {}
do
    buybot_system.commands = {
        primary = {
            ['AWP'] = 'buy awp',
            ['Scout'] = 'buy ssg08',
            ['Autosnipers'] = 'buy scar20; buy g3sg1'
        },
        secondary = {
            ['Duals'] = 'buy elite',
            ['P-250'] = 'buy p250',
            ['R8/Deagle'] = 'buy revolver; buy deagle',
            ['Tec-9/Five-S'] = 'buy tec9; buy fiveseven'
        },
        utility = {
            ['HE'] = 'buy hegrenade',
            ['Flash'] = 'buy flashbang',
            ['Smoke'] = 'buy smokegrenade',
            ['Molotov'] = 'buy molotov; buy incgrenade'
        },
        equipment = {
            ['Taser'] = 'buy taser',
            ['Kevlar'] = 'buy vest',
            ['Helmet'] = 'buy vesthelm',
            ['Defuser'] = 'buy defuser'
        }
    }
    
    buybot_system.is_pistol_round = function()
        local game_rules = entity.get_game_rules()
        if not game_rules then return false end
        
        local game_phase = entity.get_prop(game_rules, 'm_gamePhase')
        if game_phase ~= 2 then return false end
        
        local total_rounds = entity.get_prop(game_rules, 'm_totalRoundsPlayed')
        if total_rounds == 0 or total_rounds == 15 or total_rounds == 30 then
            return true
        end
        
        return false
    end
    
    buybot_system.generate_commands = function()
        local result = {}
        
        local primary_weapon = misc.buybot.primary:get()
        local secondary_weapon = misc.buybot.secondary:get()
        local primary_utility = misc.buybot.utility:get()
        local primary_equipment = misc.buybot.equipment:get()

        if misc.buybot.pistol_kevlar:get() and buybot_system.is_pistol_round() then
            local has_kevlar = false
            for i = 1, #primary_equipment do
                if primary_equipment[i] == 'Kevlar' or primary_equipment[i] == 'Helmet' then
                    has_kevlar = true
                    break
                end
            end
            
            if has_kevlar then
                table.insert(result, buybot_system.commands.equipment['Kevlar'])
                return result
            end
        end

        if primary_weapon ~= 'None' then
            table.insert(result, buybot_system.commands.primary[primary_weapon])
        end

        if secondary_weapon ~= 'None' then
            table.insert(result, buybot_system.commands.secondary[secondary_weapon])
        end
 
        for i = 1, #primary_utility do
            table.insert(result, buybot_system.commands.utility[primary_utility[i]])
        end

        for i = 1, #primary_equipment do
            table.insert(result, buybot_system.commands.equipment[primary_equipment[i]])
        end
        
        return result
    end
    
    buybot_system.executed = false
    
    local function on_item_purchase(e)
        if not misc.buybot.enabled:get() then
            buybot_system.executed = false
            return
        end
        
        local me = entity.get_local_player()
        if not me then return end
        
        local userid = client.userid_to_entindex(e.userid)
        if userid ~= me then return end
        
        if buybot_system.executed then return end
        
        local commands = buybot_system.generate_commands()
        
        for i = 1, #commands do
            client.exec(commands[i])
        end
        
        buybot_system.executed = true
    end
    
    local function on_round_start()
        buybot_system.executed = false
    end
    
    client.set_event_callback('item_purchase', on_item_purchase)
    client.set_event_callback('round_start', on_round_start)
end

local fast_ladder_system = {}
do
    local function on_setup_command(cmd)
        if not misc.fast_ladder:get() then return end
        
        local me = entity.get_local_player()
        if not me then return end
        
        if entity.get_prop(me, 'm_MoveType') ~= 9 then return end
    
        local weapon = entity.get_player_weapon(me)
        if not weapon then return end
    
        local throw_time = entity.get_prop(weapon, 'm_fThrowTime')
    
        if throw_time ~= nil and throw_time ~= 0 then
            return
        end
        
        if cmd.forwardmove > 0 then
            if cmd.pitch < 45 then
                cmd.pitch = 89
                cmd.in_moveright = 1
                cmd.in_moveleft = 0
                cmd.in_forward = 0
                cmd.in_back = 1
        
                if cmd.sidemove == 0 then
                    cmd.yaw = cmd.yaw + 90
                end
        
                if cmd.sidemove < 0 then
                    cmd.yaw = cmd.yaw + 150
                end
        
                if cmd.sidemove > 0 then
                    cmd.yaw = cmd.yaw + 30
                end
            end
        elseif cmd.forwardmove < 0 then
            cmd.pitch = 89
            cmd.in_moveleft = 1
            cmd.in_moveright = 0
            cmd.in_forward = 1
            cmd.in_back = 0
        
            if cmd.sidemove == 0 then
                cmd.yaw = cmd.yaw + 90
            end
        
            if cmd.sidemove > 0 then
                cmd.yaw = cmd.yaw + 150
            end
        
            if cmd.sidemove < 0 then
                cmd.yaw = cmd.yaw + 30
            end
        end
    end
    
    local function on_enabled(item)
        local value = item:get()
        
        if value then
            client.set_event_callback('setup_command', on_setup_command)
        else
            client.unset_event_callback('setup_command', on_setup_command)
        end
    end
    

    misc.fast_ladder:set_callback(on_enabled, true)
end

local anim_breaker_system = {}
do
    local c_entity = require('gamesense/entity')
    local leg_movement_ref = ui.reference('AA', 'Other', 'Leg movement')
    
    local MOVETYPE_WALK = 2
    local ANIMATION_LAYER_MOVEMENT_MOVE = 6
    local ANIMATION_LAYER_LEAN = 12
    
    local localplayer = {
        is_onground = false,
        is_moving = false
    }
    
    local function update_localplayer()
        local me = entity.get_local_player()
        if me == nil or not entity.is_alive(me) then return end
        
        local flags = entity.get_prop(me, 'm_fFlags')
        localplayer.is_onground = bit.band(flags, 1) == 1
        
        local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))
        localplayer.is_moving = velocity:length2d() > 5
    end
    
    local function update_onground(player)
        local entity_info = c_entity(player)
        if entity_info == nil then return end
        
        if localplayer.is_onground then
            local value = misc.animation_breaker.onground_legs:get()
            
            if value == 'Static' then
                ui.set(leg_movement_ref, 'Always slide')
                entity.set_prop(player, 'm_flPoseParameter', 0, 0)
                return
            end
            
            if value == 'Jitter' then
                local mul = client.random_float(
                    misc.animation_breaker.onground_jitter_min_value:get() * 0.01,
                    misc.animation_breaker.onground_jitter_max_value:get() * 0.01
                )
                
                ui.set(leg_movement_ref, 'Always slide')
                entity.set_prop(player, 'm_flPoseParameter', 1, globals.tickcount() % 4 > 1 and mul or 1)
                return
            end
            
            if value == 'Moonwalk' then
                ui.set(leg_movement_ref, 'Never slide')
                entity.set_prop(player, 'm_flPoseParameter', 0, 7)
                
                local layer_move = entity_info:get_anim_overlay(ANIMATION_LAYER_MOVEMENT_MOVE)
                if layer_move ~= nil then
                    layer_move.weight = 1
                end
                return
            end
        end
        
        ui.set(leg_movement_ref, 'Off')
    end
    
    local function update_in_air(player)
        local value = misc.animation_breaker.in_air_legs:get()
        
        if value == 'Off' then
            return
        end
        
        if localplayer.is_onground then
            return
        end
        
        if value == 'Static' then
            entity.set_prop(player, 'm_flPoseParameter', misc.animation_breaker.in_air_static_value:get() * 0.01, 6)
            return
        end
        
        if value == 'Moonwalk' then
            if not localplayer.is_moving then
                return
            end
            
            local entity_info = c_entity(player)
            if entity_info == nil then return end
            
            local layer_move = entity_info:get_anim_overlay(ANIMATION_LAYER_MOVEMENT_MOVE)
            if layer_move ~= nil then
                layer_move.weight = 1
            end
            return
        end
    end
    
    local function update_earthquake(player)
        if not misc.animation_breaker.earthquake:get() then
            return
        end
        
        local entity_info = c_entity(player)
        if entity_info == nil then return end
        
        local layer_lean = entity_info:get_anim_overlay(ANIMATION_LAYER_LEAN)
        if layer_lean == nil then return end
        
        local function lerp(a, b, t)
            return a + t * (b - a)
        end
        
        layer_lean.weight = lerp(
            layer_lean.weight,
            client.random_float(0, 1),
            misc.animation_breaker.earthquake_value:get() * 0.01
        )
    end
    
    local function update_body_lean(player)
        local value = misc.animation_breaker.adjust_lean:get()
        
        if value == 0 then
            return
        end
        
        local entity_info = c_entity(player)
        if entity_info == nil then return end
        
        local layer_lean = entity_info:get_anim_overlay(ANIMATION_LAYER_LEAN)
        if layer_lean == nil then return end
        
        
        layer_lean.weight = value * 0.01
    end
    
    local function update_pitch_on_land(player)
        if not misc.animation_breaker.pitch_on_land:get() then
            return
        end
        
        if not localplayer.is_onground then
            return
        end
        
        local entity_info = c_entity(player)
        if entity_info == nil then return end
        
        local animstate = entity_info:get_anim_state()
        if animstate == nil or not animstate.hit_in_ground_animation then
            return
        end
        
        entity.set_prop(player, 'm_flPoseParameter', 0.5, 12)
    end
    
    local function on_pre_render()
        local me = entity.get_local_player()
        if me == nil then return end
        
        update_localplayer()
        
        local movetype = entity.get_prop(me, 'm_MoveType')
        
        if movetype == MOVETYPE_WALK then
            update_onground(me)
            update_in_air(me)
            update_pitch_on_land(me)
        end
        
        update_body_lean(me)
        update_earthquake(me)
    end
    
    local function on_enabled()
        local value = misc.animation_breaker.enabled:get()
        
        if value then
            client.set_event_callback('pre_render', on_pre_render)
        else
            client.unset_event_callback('pre_render', on_pre_render)
            ui.set(leg_movement_ref, 'Off')
        end
    end
    
    misc.animation_breaker.enabled:set_callback(on_enabled)
end

local resolver_system = {}
do
    local ffi = require('ffi')
    local c_entity = require('gamesense/entity')
    
    local native_GetClientEntity = vtable_bind('client.dll', 'VClientEntityList003', 3, 'void*(__thiscall*)(void*, int)')
    
    local function toticks(time)
        return math.floor(0.5 + time / globals.tickinterval())
    end
    
    local expres = {}
    
    expres.get_prev_simtime = function(ent)
        local ent_ptr = native_GetClientEntity(ent)    
        if ent_ptr ~= nil then 
            return ffi.cast('float*', ffi.cast('uintptr_t', ent_ptr) + 0x26C)[0] 
        end
    end
    
    expres.restore = function()
        for i = 1, 64 do
            plist.set(i, "Force body yaw", false)
        end
    end
    
    expres.body_yaw, expres.eye_angles = {}, {}
    
    expres.get_max_desync = function (animstate)
        local speedfactor = math.max(0, math.min(1, animstate.feet_speed_forwards_or_sideways))
        local avg_speedfactor = (animstate.stop_to_full_running_fraction * -0.3 - 0.2) * speedfactor + 1
        
        local duck_amount = animstate.duck_amount
        if duck_amount > 0 then
            avg_speedfactor = avg_speedfactor + (duck_amount * speedfactor * (0.5 - avg_speedfactor))
        end
        
        return math.max(0.5, math.min(1, avg_speedfactor))
    end
    
    local function is_defensive_resolver(lp)
        if lp == nil or not entity.is_alive(lp) then return false end
        local m_flOldSimulationTime = ffi.cast("float*", ffi.cast("uintptr_t", native_GetClientEntity(lp)) + 0x26C)[0]
        local m_flSimulationTime = entity.get_prop(lp, "m_flSimulationTime")
        local delta = toticks(m_flOldSimulationTime - m_flSimulationTime)
        return delta > 0
    end
    
    expres.handle = function(current_threat)
        if current_threat == nil or not entity.is_alive(current_threat) or entity.is_dormant(current_threat) then 
            return 
        end
        
        if expres.body_yaw[current_threat] == nil then 
            expres.body_yaw[current_threat], expres.eye_angles[current_threat] = {}, {}
        end
        
        local simtime = toticks(entity.get_prop(current_threat, 'm_flSimulationTime'))
        local prev_simtime = toticks(expres.get_prev_simtime(current_threat))
        expres.body_yaw[current_threat][simtime] = entity.get_prop(current_threat, 'm_flPoseParameter', 11) * 120 - 60
        expres.eye_angles[current_threat][simtime] = select(2, entity.get_prop(current_threat, "m_angEyeAngles"))
        
        if expres.body_yaw[current_threat][prev_simtime] ~= nil then
            local ent = c_entity.new(current_threat)
            local animstate = ent:get_anim_state()
            local max_desync = expres.get_max_desync(animstate)
            local Pitch = entity.get_prop(current_threat, "m_angEyeAngles[0]")
            local pitch_e = Pitch > -30 and Pitch < 49
            local curr_side = globals.tickcount() % 4 > 1 and 1 or -1
            local value_body = 0
            
            if aimbot.resolver_type:get() == "Jitter" then
                local should_correct = (simtime - prev_simtime >= 1) and math.abs(max_desync) < 45 and expres.body_yaw[current_threat][prev_simtime] ~= 0
                if should_correct then
                    local value = math.random(0, expres.body_yaw[current_threat][prev_simtime] * math.random(-1, 1)) * .25
                    plist.set(current_threat, 'Force body yaw', true)  
                    plist.set(current_threat, 'Force body yaw value', value) 
                else
                    plist.set(current_threat, 'Force body yaw', false)  
                end
            elseif aimbot.resolver_type:get() == "Defensive" then
                if not is_defensive_resolver(current_threat) then return end
                if pitch_e then
                    value_body = 0
                else
                    value_body = math.random(0, expres.body_yaw[current_threat][prev_simtime] * math.random(-1, 1)) * .25
                end
                plist.set(current_threat, 'Force body yaw', true)  
                plist.set(current_threat, 'Force body yaw value', value_body) 
            elseif aimbot.resolver_type:get() == "1000$" then
                if pitch_e then
                    value_body = 0
                else
                    value_body = curr_side * (max_desync * math.random(0, 58))
                end
                plist.set(current_threat, 'Force body yaw', true)  
                plist.set(current_threat, 'Force body yaw value', value_body) 
            end
        end
        plist.set(current_threat, 'Correction active', true)
    end
    
    local function resolver_update()
        if not aimbot.resolver:get() then
            expres.restore()
            return
        end
        
        local lp = entity.get_local_player()
        if not lp then return end
        local entities = entity.get_players(true)
        if not entities then return end
        
        for i = 1, #entities do
            local target = entities[i]
            if target and entity.is_alive(target) then
                expres.handle(target)
            end
        end
    end
    
    client.set_event_callback('setup_command', resolver_update)
    
    aimbot.resolver:set_callback(function(self)
        if not self:get() then
            expres.restore()
        end
    end)
end

local function on_antiaim_setup_command(cmd)
    if not entity.get_local_player() or not entity.is_alive(entity.get_local_player()) then
        return
    end
    

    antiaim_funcs.update(cmd)
end

client.set_event_callback("predict_command", function(cmd)
    if cmd.command_number == breaker.cmd then
        local tickbase = entity.get_prop(entity.get_local_player(), "m_nTickBase")
        breaker.defensive = math.abs(tickbase - breaker.defensive_check)
        breaker.defensive_check = math.max(tickbase, breaker.defensive_check)
        breaker.cmd = 0
    end
end)

client.set_event_callback("run_command", function(cmd)
    breaker.cmd = cmd.command_number
    if cmd.chokedcommands == 0 then
        breaker.origin = vector(entity.get_origin(entity.get_local_player()))
        if breaker.last_origin ~= nil then
            breaker.tp_dist = (breaker.origin - breaker.last_origin):length2dsqr()
            gram_update(breaker.tp_data, breaker.tp_dist, true)
        end
        breaker.last_origin = breaker.origin
    end
end)

client.set_event_callback("round_start", function()
    breaker.cmd = 0
    breaker.defensive = 0
    breaker.defensive_check = 0
end)

client.set_event_callback("player_death", function(e)
    local ent = client.userid_to_entindex(e.userid)
    if ent == entity.get_local_player() then
        breaker.cmd = 0
        breaker.defensive = 0
        breaker.defensive_check = 0
    end
end)

client.set_event_callback("level_init", function()
    if (globals.mapname() ~= breaker.mapname) then
        breaker.cmd = 0
        breaker.defensive = 0
        breaker.defensive_check = 0
        breaker.mapname = globals.mapname()
    end
end)

client.set_event_callback('setup_command', on_antiaim_setup_command)


local animations = {}
animations.data = {}

animations.new = function(name, value, speed)
    speed = speed or 0.095
    
    if animations.data[name] == nil then
        animations.data[name] = value
    end
    
    local data = animations.data[name]
    
    if data ~= value then
        data = data + (value - data) * speed
        
        if math.abs(data - value) < 0.01 then
            data = value
        end
        
        animations.data[name] = data
    end
    
    return data
end

local utils = {}

utils.rgb_to_hex = function(color)
    return string.format("%02X%02X%02X%02X", color[1], color[2], color[3], color[4] or 255)
end

utils.animate_text = function(time, string, r, g, b, a, r1, g1, b1, a1)
    local t_out, t_out_iter = {}, 1
    local l = string:len() - 1

    local r_add = (r1 - r)
    local g_add = (g1 - g)
    local b_add = (b1 - b)
    local a_add = (a1 - a)

    for i = 1, #string do
        local iter = (i - 1)/(#string - 1) + time
        t_out[t_out_iter] = "\a" .. utils.rgb_to_hex({r + r_add * math.abs(math.cos( iter )), g + g_add * math.abs(math.cos( iter )), b + b_add * math.abs(math.cos( iter )), a + a_add * math.abs(math.cos( iter ))})

        t_out[t_out_iter+1] = string:sub(i, i)
        t_out_iter = t_out_iter + 2
    end

    return table.concat(t_out)
end

local render = renderer

render.rec = function(x, y, w, h, radius, color)
    radius = math.min(x/2, y/2, radius)
    local r, g, b, a = unpack(color)
    renderer.rectangle(x, y + radius, w, h - radius*2, r, g, b, a)
    renderer.rectangle(x + radius, y, w - radius*2, radius, r, g, b, a)
    renderer.rectangle(x + radius, y + h - radius, w - radius*2, radius, r, g, b, a)
    renderer.circle(x + radius, y + radius, r, g, b, a, radius, 180, 0.25)
    renderer.circle(x - radius + w, y + radius, r, g, b, a, radius, 90, 0.25)
    renderer.circle(x - radius + w, y - radius + h, r, g, b, a, radius, 0, 0.25)
    renderer.circle(x + radius, y - radius + h, r, g, b, a, radius, -90, 0.25)
end

render.rec_outline = function(x, y, w, h, radius, thickness, color)
    radius = math.min(w/2, h/2, radius)
    local r, g, b, a = unpack(color)
    if radius == 1 then
        renderer.rectangle(x, y, w, thickness, r, g, b, a)
        renderer.rectangle(x, y + h - thickness, w , thickness, r, g, b, a)
    else
        renderer.rectangle(x + radius, y, w - radius*2, thickness, r, g, b, a)
        renderer.rectangle(x + radius, y + h - thickness, w - radius*2, thickness, r, g, b, a)
        renderer.rectangle(x, y + radius, thickness, h - radius*2, r, g, b, a)
        renderer.rectangle(x + w - thickness, y + radius, thickness, h - radius*2, r, g, b, a)
        renderer.circle_outline(x + radius, y + radius, r, g, b, a, radius, 180, 0.25, thickness)
        renderer.circle_outline(x + radius, y + h - radius, r, g, b, a, radius, 90, 0.25, thickness)
        renderer.circle_outline(x + w - radius, y + radius, r, g, b, a, radius, -90, 0.25, thickness)
        renderer.circle_outline(x + w - radius, y + h - radius, r, g, b, a, radius, 0, 0.25, thickness)
    end
end

render.shadow = function(x, y, w, h, width, rounding, accent, accent_inner)
    local thickness = 1
    local Offset = 1
    local r, g, b, a = unpack(accent)
    if accent_inner then
        render.rec(x, y, w, h + 1, rounding, accent_inner)
    end
    for k = 0, width do
        if a * (k/width)^(1) > 5 then
            local accent = {r, g, b, a * (k/width)^(2)}
            render.rec_outline(x + (k - width - Offset)*thickness, y + (k - width - Offset) * thickness, w - (k - width - Offset)*thickness*2, h + 1 - (k - width - Offset)*thickness*2, rounding + thickness * (width - k + Offset), thickness, accent)
        end
    end
end

local screen_indication = {}
screen_indication.indicators_height = 0

screen_indication.handle = function()
    if not visual.screen_indicators:get() then
        return
    end
    
    local anim = {}
    local indication_enable = visual.screen_indicators:get()
    local accent_color = {visual.screen_indicators.color:get()}

    anim.main = animations.new('screen_indication_main', indication_enable and 255 or 0)

    local x, y = client.screen_size()
    local center = {x*0.5, y*0.5+25}

    local plocal = entity.get_local_player()
    if plocal == nil or not entity.is_alive(plocal) then
        return
    end

    if anim.main < 0.1 then
        return
    end

    local gamesense_refs = {
        dt = {ui.reference('RAGE', 'Aimbot', 'Double tap')},
        os = {ui.reference('AA', 'Other', 'On shot anti-aim')},
        safePoint = ui.reference('RAGE', 'Aimbot', 'Force safe point'),
        forceBaim = ui.reference('RAGE', 'Aimbot', 'Force body aim'),
        dmgOverride = {ui.reference('RAGE', 'Aimbot', 'Minimum damage override')},
        freestanding = {ui.reference('AA', 'Anti-aimbot angles', 'Freestanding')}
    }

    local binds = {
        {'dt', ui.get(gamesense_refs.dt[1]) and ui.get(gamesense_refs.dt[2])},
        {'hide', ui.get(gamesense_refs.os[1]) and ui.get(gamesense_refs.os[2])},
        {'safe', ui.get(gamesense_refs.safePoint)},
        {'body', ui.get(gamesense_refs.forceBaim)},
        {'dmg', ui.get(gamesense_refs.dmgOverride[1]) and ui.get(gamesense_refs.dmgOverride[2]) and ui.get(gamesense_refs.dmgOverride[3])},
        {'fs', ui.get(gamesense_refs.freestanding[1]) and ui.get(gamesense_refs.freestanding[2])}
    }

    local state_names = {
        [1] = 'global',
        [2] = 'stand',
        [3] = 'walk',
        [4] = 'run',
        [5] = 'air',
        [6] = 'air+duck',
        [7] = 'crouch',
        [8] = 'duck+move',
        [9] = 'fakelag'
    }

    local scope_based = entity.get_prop(plocal, 'm_bIsScoped') ~= 0
    local add_y = 0

    anim.name = {}
    anim.name.alpha = animations.new('lua_name_alpha', indication_enable and 255 or 0)
    anim.name.move = animations.new('binds_move_name', indication_enable and not scope_based and -renderer.measure_text(nil, 'althea')*0.5 or 15)
    anim.name.glow = animations.new('glow_name_alpha', (indication_enable and visual.screen_indicators_glow:get()) and 50 or 0)
    
    if anim.name.alpha > 1 then
        local text = 'althea'
        local start_x = center[1] + string.format('%.0f', anim.name.move)
        local char_duration = 0.35    
        local pause_duration = 5.0    
        local total_wave = #text * char_duration
        local total_cycle = total_wave + pause_duration
        local current_time = globals.curtime() % total_cycle

        local function ease_in_out_sine(t)
            return -(math.cos(math.pi * t) - 1) / 2
        end
        
        for i = 1, #text do
            local char = text:sub(i, i)
            local char_base_x = renderer.measure_text('b', text:sub(1, i-1))

            local char_start_time = (i - 1) * char_duration
            local char_end_time = i * char_duration
            
            local wave_offset = 0

            if current_time >= char_start_time and current_time < char_end_time then
                local char_progress = (current_time - char_start_time) / char_duration
                wave_offset = -math.sin(ease_in_out_sine(char_progress) * math.pi) * 6
            end
            local iter = (i - 1)/(#text - 1) + globals.curtime()*2
            local color_wave = math.abs(math.cos(iter))
            local char_r = accent_color[1]
            local char_g = accent_color[2]
            local char_b = accent_color[3]
            local char_a = anim.main + (150 - anim.main) * color_wave
            if anim.name.glow > 1 then
                local char_w = renderer.measure_text('b', char)
                render.shadow(start_x + char_base_x, 
                             center[2] + wave_offset + 7, 
                             char_w - 1, 0, 10, 0, 
                             {accent_color[1], accent_color[2], accent_color[3], anim.name.glow}, 
                             {accent_color[1], accent_color[2], accent_color[3], anim.name.glow})
            end
            
            renderer.text(start_x + char_base_x, 
                         center[2] + wave_offset, 
                         char_r, char_g, char_b, char_a, 'b', 0, char)
        end
        
        add_y = add_y + string.format('%.0f', anim.name.alpha / 255 * 12)
    end

    anim.state = {}
    anim.state.text = state_names[id] or 'global'
    anim.state.alpha = animations.new('state_alpha', indication_enable and 200 or 0)
    anim.state.scoped_check = animations.new('scoped_check', indication_enable and not scope_based and 1 or 0) ~= 1
    anim.state.move = anim.state.scoped_check and string.format('%.0f',animations.new('binds_move_state', indication_enable and not scope_based and -renderer.measure_text(nil, anim.state.text)*0.5 or 15)) or -renderer.measure_text(nil, anim.state.text)*0.5
    
    if anim.state.alpha > 1 then
        renderer.text(center[1] + anim.state.move, center[2] + add_y, 255, 255, 255, anim.state.alpha, nil, 0, anim.state.text)
        add_y = add_y + string.format('%.0f', anim.state.alpha / 255 * 15)
    end

    anim.binds = {}
    for k, v in pairs(binds) do
        anim.binds[v[1]] = {}
        anim.binds[v[1]].alpha = animations.new('binds_alpha_'..v[1], indication_enable and v[2] and 255 or 0)
        anim.binds[v[1]].move = animations.new('binds_move_'..v[1], indication_enable and not scope_based and -renderer.measure_text(nil, v[1])*0.5 or 15)

        if anim.binds[v[1]].alpha > 1 then
            renderer.text(center[1] + string.format('%.0f', anim.binds[v[1]].move), center[2] + add_y, 255, 255, 255, anim.binds[v[1]].alpha, nil, 0, v[1])
            add_y = add_y + string.format('%.0f', anim.binds[v[1]].alpha / 255 * 12)
        end
    end
    
    screen_indication.indicators_height = 10 + add_y
end

client.set_event_callback('paint', screen_indication.handle)

local shot_logger = {}

shot_logger.add = function(...)
    local args = {...}
    local len = #args
    for i = 1, len do
        local arg = args[i]
        local r, g, b = unpack(arg)
        local msg = {}

        if #arg == 3 then
            table.insert(msg, " ")
        else
            for j = 4, #arg do
                table.insert(msg, arg[j])
            end
        end
        msg = table.concat(msg)

        if len > i then
            msg = msg .. "\0"
        end

        client.color_log(r, g, b, msg)
    end
end

shot_logger.bullet_impacts = {}
shot_logger.bullet_impact = function(e)
    local tick = globals.tickcount()
    local me = entity.get_local_player()
    local user = client.userid_to_entindex(e.userid)
    
    if user ~= me then
        return
    end

    if #shot_logger.bullet_impacts > 150 then
        shot_logger.bullet_impacts = {}
    end

    shot_logger.bullet_impacts[#shot_logger.bullet_impacts+1] = {
        tick = tick,
        eye = vector(client.eye_position()),
        shot = vector(e.x, e.y, e.z)
    }
end

shot_logger.get_inaccuracy_tick = function(pre_data, tick)
    local spread_angle = -1
    for k, impact in pairs(shot_logger.bullet_impacts) do
        if impact.tick == tick then
            local aim, shot = 
                (pre_data.eye-pre_data.shot_pos):angles(),
                (pre_data.eye-impact.shot):angles()

            spread_angle = vector(aim-shot):length2d()
            break
        end
    end

    return spread_angle
end

shot_logger.get_safety = function(aim_data, target)
    local gamesense_refs_safety = {
        prefer_safe_point = ui.reference('RAGE', 'Aimbot', 'Prefer safe point'),
        force_safe_point = ui.reference('RAGE', 'Aimbot', 'Force safe point')
    }
    
    local has_been_boosted = aim_data.boosted
    local plist_safety = plist.get(target, 'Override safe point')
    local ui_safety = {ui.get(gamesense_refs_safety.prefer_safe_point), ui.get(gamesense_refs_safety.force_safe_point) or plist_safety == 'On'}

    if not has_been_boosted then
        return -1
    end

    if plist_safety == 'Off' or not (ui_safety[1] or ui_safety[2]) then
        return 0
    end

    return ui_safety[2] and 2 or (ui_safety[1] and 1 or 0)
end

shot_logger.generate_flags = function(pre_data)
    return {
        pre_data.self_choke > 1 and 1 or 0,
        pre_data.velocity_modifier < 1.00 and 1 or 0,
        pre_data.flags.boosted and 1 or 0
    }
end

shot_logger.hitboxes = {"generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", "?", "gear"}

shot_logger.on_aim_fire = function(e)
    local p_ent = e.target
    local me = entity.get_local_player()

    shot_logger[e.id] = {
        original = e,
        dropped_packets = {},

        handle_time = globals.realtime(),
        self_choke = globals.chokedcommands(),

        flags = {
            boosted = e.boosted
        },

        feet_yaw = entity.get_prop(p_ent, 'm_flPoseParameter', 11)*120-60,
        correction = plist.get(p_ent, 'Correction active'),

        safety = shot_logger.get_safety(e, p_ent),
        shot_pos = vector(e.x, e.y, e.z),
        eye = vector(client.eye_position()),
        view = vector(client.camera_angles()),

        velocity_modifier = entity.get_prop(me, 'm_flVelocityModifier'),
        total_hits = entity.get_prop(me, 'm_totalHitsOnServer'),

        history = globals.tickcount() - e.tick
    }
end

shot_logger.on_aim_hit = function(e)
    if not (visual.notifications:get() and visual.notifications_type:get('Console')) then
        return
    end

    if shot_logger[e.id] == nil then
        return 
    end

    local info = {
        type = math.max(0, entity.get_prop(e.target, 'm_iHealth')) > 0,
        prefix = {visual.notifications_color:get()},
        hit = {visual.notifications_color:get()},
        name = entity.get_player_name(e.target),
        hitgroup = shot_logger.hitboxes[e.hitgroup + 1] or '?',
        flags = string.format('%s', table.concat(shot_logger.generate_flags(shot_logger[e.id]))),
        aimed_hitgroup = shot_logger.hitboxes[shot_logger[e.id].original.hitgroup + 1] or '?',
        aimed_hitchance = string.format('%d%%', math.floor(shot_logger[e.id].original.hit_chance + 0.5)),
        hp = math.max(0, entity.get_prop(e.target, 'm_iHealth')),
        spread_angle = string.format('%.2f°', shot_logger.get_inaccuracy_tick(shot_logger[e.id], globals.tickcount())),
        correction = string.format('%d:%d°', shot_logger[e.id].correction and 1 or 0, (shot_logger[e.id].feet_yaw < 10 and shot_logger[e.id].feet_yaw > -10) and 0 or shot_logger[e.id].feet_yaw)
    }

    shot_logger.add({info.prefix[1], info.prefix[2], info.prefix[3], '[ALTHEA]'}, 
                    {134, 134, 134, ' » '}, 
                    {200, 200, 200, info.type and 'Damaged ' or 'Killed '}, 
                    {info.hit[1], info.hit[2], info.hit[3], info.name}, 
                    {200, 200, 200, ' in the '}, 
                    {info.hit[1], info.hit[2], info.hit[3], info.hitgroup}, 
                    {200, 200, 200, info.type and info.hitgroup ~= info.aimed_hitgroup and ' (' or ''},
                    {info.hit[1], info.hit[2], info.hit[3], info.type and (info.hitgroup ~= info.aimed_hitgroup and info.aimed_hitgroup) or ''},
                    {200, 200, 200, info.type and info.hitgroup ~= info.aimed_hitgroup and ')' or ''},
                    {200, 200, 200, info.type and ' for ' or ''},
                    {info.hit[1], info.hit[2], info.hit[3], info.type and e.damage or ''},
                    {200, 200, 200, info.type and e.damage ~= shot_logger[e.id].original.damage and ' (' or ''},
                    {info.hit[1], info.hit[2], info.hit[3], info.type and (e.damage ~= shot_logger[e.id].original.damage and shot_logger[e.id].original.damage) or ''},
                    {200, 200, 200, info.type and e.damage ~= shot_logger[e.id].original.damage and ')' or ''},
                    {200, 200, 200, info.type and ' damage' or ''},
                    {200, 200, 200, info.type and ' (' or ''}, {info.hit[1], info.hit[2], info.hit[3], info.type and info.hp or ''}, {200, 200, 200, info.type and ' hp remaning)' or ''},
                    {200, 200, 200, ' ['}, {info.hit[1], info.hit[2], info.hit[3], info.spread_angle}, {200, 200, 200, ' | '}, {info.hit[1], info.hit[2], info.hit[3], info.correction}, {200, 200, 200, ']'},
                    {200, 200, 200, ' (hc: '}, {info.hit[1], info.hit[2], info.hit[3], info.aimed_hitchance}, {200, 200, 200, ' | safety: '}, {info.hit[1], info.hit[2], info.hit[3], shot_logger[e.id].safety},
                    {200, 200, 200, ' | history(Δ): '}, {info.hit[1], info.hit[2], info.hit[3], shot_logger[e.id].history}, {200, 200, 200, ' | flags: '}, {info.hit[1], info.hit[2], info.hit[3], info.flags},
                    {200, 200, 200, ')'})
end

shot_logger.on_aim_miss = function(e)
    if not (visual.notifications:get() and visual.notifications_type:get('Console')) then
        return
    end

    local me = entity.get_local_player()
    local info = {
        prefix = {visual.notifications_color:get()},
        hit = {visual.notifications_color:get()},
        name = entity.get_player_name(e.target),
        hitgroup = shot_logger.hitboxes[e.hitgroup + 1] or '?',
        flags = string.format('%s', table.concat(shot_logger.generate_flags(shot_logger[e.id]))),
        aimed_hitgroup = shot_logger.hitboxes[shot_logger[e.id].original.hitgroup + 1] or '?',
        aimed_hitchance = string.format('%d%%', math.floor(shot_logger[e.id].original.hit_chance + 0.5)),
        hp = math.max(0, entity.get_prop(e.target, 'm_iHealth')),
        reason = e.reason,
        spread_angle = string.format('%.2f°', shot_logger.get_inaccuracy_tick(shot_logger[e.id], globals.tickcount())),
        correction = string.format('%d:%d°', shot_logger[e.id].correction and 1 or 0, (shot_logger[e.id].feet_yaw < 10 and shot_logger[e.id].feet_yaw > -10) and 0 or shot_logger[e.id].feet_yaw)
    }

    if info.reason == '?' then
        info.reason = 'unknown'

        if shot_logger[e.id].total_hits ~= entity.get_prop(me, 'm_totalHitsOnServer') then
            info.reason = 'damage rejection'
        end
    end

    shot_logger.add({info.prefix[1], info.prefix[2], info.prefix[3], '[ALTHEA]'}, 
                    {134, 134, 134, ' » '}, 
                    {200, 200, 200, 'Missed shot at '}, 
                    {info.hit[1], info.hit[2], info.hit[3], info.name}, 
                    {200, 200, 200, ' in the '}, 
                    {info.hit[1], info.hit[2], info.hit[3], info.hitgroup}, 
                    {200, 200, 200, ' due to '},
                    {info.hit[1], info.hit[2], info.hit[3], info.reason},
                    {200, 200, 200, ' ['}, {info.hit[1], info.hit[2], info.hit[3], info.spread_angle}, {200, 200, 200, ' | '}, {info.hit[1], info.hit[2], info.hit[3], info.correction}, {200, 200, 200, ']'},
                    {200, 200, 200, ' (hc: '}, {info.hit[1], info.hit[2], info.hit[3], info.aimed_hitchance}, {200, 200, 200, ' | safety: '}, {info.hit[1], info.hit[2], info.hit[3], shot_logger[e.id].safety},
                    {200, 200, 200, ' | history(Δ): '}, {info.hit[1], info.hit[2], info.hit[3], shot_logger[e.id].history}, {200, 200, 200, ' | flags: '}, {info.hit[1], info.hit[2], info.hit[3], info.flags},
                    {200, 200, 200, ')'})
end

client.set_event_callback('aim_fire', shot_logger.on_aim_fire)
client.set_event_callback('aim_miss', shot_logger.on_aim_miss)
client.set_event_callback('aim_hit', shot_logger.on_aim_hit)
client.set_event_callback('bullet_impact', shot_logger.bullet_impact)

local render_helpers = {
    measures = function(self, plus, arg, name) 
        return {renderer.measure_text(arg, name) + plus, name}
    end,
    
    rect_althea = function(self, x, y, w, h, clr, rounding, clr2, thickness)
        local r, g, b, a = unpack(clr)
        local r1, g1, b1, a1

        renderer.circle(x + rounding, y + rounding, r, g, b, a, rounding, 180, 0.25)
        renderer.rectangle(x + rounding, y, w - rounding - rounding, rounding, r, g, b, a)
        renderer.circle(x + w - rounding, y + rounding, r, g, b, a, rounding, 90, 0.25)
        renderer.rectangle(x, y + rounding, w, h - rounding*2 + 1, r, g, b, a)
        
        renderer.circle(x + rounding, y + h - rounding + 1, r, g, b, a, rounding, 270, 0.25)
        renderer.rectangle(x + rounding, y + h - rounding + 1, w - rounding - rounding, rounding, r, g, b, a)
        renderer.circle(x + w - rounding, y + h - rounding + 1, r, g, b, a, rounding, 0, 0.25)

        if clr2 then 
            r1, g1, b1, a1 = unpack(clr2)
            local hs = thickness or 2

            renderer.rectangle(x + rounding, y, w - rounding * 2, hs, r1, g1, b1, a1)
            renderer.gradient(x - 1, y + rounding, hs, h - rounding * 2.7, r1, g1, b1, a1, r1, g1, b1, 0, false)
            renderer.gradient(x + w - 1, y + rounding, hs, h - rounding * 2.7, r1, g1, b1, a1, r1, g1, b1, 0, false)
            renderer.circle_outline(x + w - rounding, y + rounding, r1, g1, b1, a1, rounding, 270, 0.25, hs)
            renderer.circle_outline(x + rounding, y + rounding, r1, g1, b1, a1, rounding, 180, .25, hs)
        end
    end,
    
    glow_work = function(x, y, w, h, radius, thickness, color)
        radius = math.min(w/2, h/2, radius)
        local r, g, b, a = unpack(color)
        if radius == 1 then
            renderer.rectangle(x, y, w, thickness, r, g, b, a)
            renderer.rectangle(x, y + h - thickness, w , thickness, r, g, b, a)
        else
            renderer.rectangle(x + radius, y, w - radius*2, thickness, r, g, b, a)
            renderer.rectangle(x + radius, y + h - thickness, w - radius*2, thickness, r, g, b, a)
            renderer.rectangle(x, y + radius, thickness, h - radius*2, r, g, b, a)
            renderer.rectangle(x + w - thickness, y + radius, thickness, h - radius*2, r, g, b, a)
            renderer.circle_outline(x + radius, y + radius, r, g, b, a, radius, 180, 0.25, thickness)
            renderer.circle_outline(x + radius, y + h - radius, r, g, b, a, radius, 90, 0.25, thickness)
            renderer.circle_outline(x + w - radius, y + radius, r, g, b, a, radius, -90, 0.25, thickness)
            renderer.circle_outline(x + w - radius, y + h - radius, r, g, b, a, radius, 0, 0.25, thickness)
        end
    end,
    
    glow_run = function(self, x, y, w, h, width, clr, rounding, thickness)
        local Offset = 1
        local r, g, b, a = unpack(clr)

        for k = 0, width do
            if a * (k/width)^(1) > 5 then
                local accent = {r, g, b, a * (k/width)^(2)}
                render_helpers.glow_work(x + (k - width - Offset)*thickness, y + (k - width - Offset) * thickness, w - (k - width - Offset)*thickness*2, h + 1 - (k - width - Offset)*thickness*2, rounding + thickness * (width - k + Offset), thickness, accent)
            end
        end
    end
}

local event_logger = {}
event_logger.list = {}
event_logger.last_aim_data = {backtrack = 0, hitgroup = 0, damage = 0}
event_logger.last_hit_data = {hit_chance = 70}

event_logger.hitgroup_names = {
    [0] = 'generic', 'head', 'chest', 'stomach',
    'left arm', 'right arm', 'left leg', 'right leg',
    'neck', '?', 'gear'
}

local MISS_COLOR = { r = 255, g = 50, b = 50 }
local MISS_SPREAD_COLOR = { r = 255, g = 50, b = 50 }

event_logger.on_aim_fire = function(e)
    if not (visual.notifications:get() and visual.notifications_type:get('Screen')) then
        return
    end

    event_logger.last_aim_data = {
        backtrack = globals.tickcount() - e.tick or 0,
        hitgroup = e.hitgroup or 0,
        damage = e.damage or 0
    }
end

event_logger.on_aim_hit = function(e)
    if not (visual.notifications:get() and visual.notifications_type:get('Screen')) then
        return
    end

    event_logger.last_hit_data = {
        hit_chance = e.hit_chance or 70
    }
end

event_logger.on_player_hurt = function(e)
    if not (visual.notifications:get() and visual.notifications_type:get('Screen')) then
        return
    end

    local attacker = client.userid_to_entindex(e.attacker)
    local local_player = entity.get_local_player()
    
    if attacker ~= local_player then
        return
    end
    
    local victim = client.userid_to_entindex(e.userid)
    local victim_name = entity.get_player_name(victim) or 'unknown'
    local damage = e.dmg_health or 0
    local hitgroup = e.hitgroup or 0
    local group = event_logger.hitgroup_names[hitgroup] or 'unknown'
    local wanted_hitgroup = event_logger.hitgroup_names[event_logger.last_aim_data.hitgroup] or 'unknown'
    local wanted_damage = event_logger.last_aim_data.damage or 0
    local hit_chance = event_logger.last_hit_data.hit_chance or 0
    local backtrack = event_logger.last_aim_data.backtrack or 0
    local health = e.health or 0
    
    local weapon = e.weapon
    local hit_type = 'hit'
    if weapon == 'hegrenade' then 
        hit_type = 'naded'
    elseif weapon == 'inferno' then
        hit_type = 'burned'
    elseif weapon == 'knife' then 
        hit_type = 'knifed'
    end
    
    local text = ''
    local r, g, b, a = visual.notifications_color:get()
    
    if health ~= 0 then
        if hit_type == 'hit' then
            text = string.format('Hit %s in %s for %d damage (%d hp)', 
                victim_name:lower(), group, damage, health)
            
            if group ~= wanted_hitgroup then
                text = text .. string.format(' [aimed: %s for %d dmg]', wanted_hitgroup, wanted_damage)
            end
        else
            text = string.format('%s %s for %d damage (%d hp)', 
                hit_type, victim_name:lower(), damage, health)
        end
    else
        if hit_type == 'hit' then
            text = string.format('Killed %s in %s', 
                victim_name:lower(), group)
        else
            text = string.format('Killed %s', victim_name:lower())
        end
    end
    
    table.insert(event_logger.list, 1, {
        text = text,
        time = globals.realtime(),
        type = 'hit',
        alpha = 0,
        y_offset = 0,
        color = {r = r, g = g, b = b}
    })
end

event_logger.on_aim_miss = function(e)
    if not (visual.notifications:get() and visual.notifications_type:get('Screen')) then
        return
    end

    local victim_name = entity.get_player_name(e.target) or 'unknown'
    local wanted_hitgroup = event_logger.hitgroup_names[event_logger.last_aim_data.hitgroup] or 'unknown'
    local wanted_damage = event_logger.last_aim_data.damage or 0
    local hit_chance = e.hit_chance or 0
    local backtrack = event_logger.last_aim_data.backtrack or 0
    
    local text = string.format('Missed %s in %s due to %s [dmg: %d / hc: %d%% / bt: %dt]', 
        victim_name:lower(), wanted_hitgroup, e.reason, wanted_damage, math.ceil(hit_chance), backtrack)
    
    local color
    if e.reason == 'spread' or e.reason == 'prediction error' then
        color = MISS_SPREAD_COLOR
    else
        color = MISS_COLOR
    end
    
    table.insert(event_logger.list, 1, {
        text = text,
        time = globals.realtime(),
        type = 'miss',
        alpha = 0,
        y_offset = 0,
        color = color
    })
end

event_logger.render = function()
    if not (visual.notifications:get() and visual.notifications_type:get('Screen')) then
        return
    end
    
    local screen_w, screen_h = client.screen_size()
    local base_x = screen_w / 2
    local base_y = screen_h / 2 + 250
    
    local max_logs = 6
    local display_time = 4.0
    
    for i = #event_logger.list, 1, -1 do
        local log = event_logger.list[i]
        local time_alive = globals.realtime() - log.time
        
        if time_alive > display_time or i > max_logs then
            table.remove(event_logger.list, i)
        else
            log.y_offset = log.y_offset + ((i - 1) * 32 - log.y_offset) * globals.frametime() * 8
            
            local progress = 1
            if time_alive < 0.3 then
                progress = time_alive / 0.3
            elseif time_alive > (display_time - 0.5) then
                progress = 1 - ((time_alive - (display_time - 0.5)) / 0.5)
            end
            
            log.alpha = log.alpha + (progress - log.alpha) * globals.frametime() * 5
            
            if log.alpha > 0.01 then
                local alpha = log.alpha
                local r, g, b = log.color.r, log.color.g, log.color.b
                local current_y = base_y + log.y_offset
                local brightness_correction = (25 - 25 * alpha) * -1
                

                local icon_text = "althea"
                local icon = render_helpers:measures(8, "b", icon_text)
                local text = render_helpers:measures(9, "bd", log.text)
                
                local icon_x = base_x - text[1]/2 - 7
                local text_x = base_x - text[1]/2 + icon[1]
                renderer.blur(icon_x, current_y - 12 - brightness_correction, icon[1], 25)
                renderer.blur(text_x, current_y - 12 - brightness_correction, text[1] + 4, 25)
                render_helpers:rect_althea(icon_x, current_y - 12 - brightness_correction, icon[1], 25, {0, 0, 0, alpha * 25.5}, 4, {r, g, b, alpha * 255}, 2)
                render_helpers:rect_althea(text_x, current_y - 12 - brightness_correction, text[1] + 4, 25, {0, 0, 0, alpha * 25.5}, 4, {r, g, b, alpha * 255}, 2)
                renderer.text(icon_x + 4, current_y - 5 - brightness_correction, 255, 255, 255, alpha * 255, "b", nil, icon[2])
                renderer.text(text_x + 5, current_y - 4 - brightness_correction, 255, 255, 255, alpha * 255, "bd", nil, text[2])
            end
        end
    end
end

client.set_event_callback('aim_fire', event_logger.on_aim_fire)
client.set_event_callback('aim_hit', event_logger.on_aim_hit)
client.set_event_callback('aim_miss', event_logger.on_aim_miss)
client.set_event_callback('player_hurt', event_logger.on_player_hurt)
client.set_event_callback('paint', event_logger.render)

print('Althea loaded!')
