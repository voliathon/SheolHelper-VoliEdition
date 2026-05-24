--[[ BSD 3-Clause License

Copyright (c) 2022, Marian Arlt
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of this software nor the name of the copyright holder nor the
   names of its contributors may be used to endorse or promote products derived
   from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. ]]

_addon.name = 'SheolHelper'
_addon.author = 'Deridjian'
_addon.version = 2.0
_addon.commands = {'sheolhelper', 'sheol', 'shh'}

-- Localized requires to prevent global namespace pollution
local config = require('config')
local defaults = require('defaults')
local images = require('images')
local packets = require('packets')
local resources = require('resources')
local strings = require('strings')
local texts = require('texts')
local resistances = require('resistances')
local types = require('types')
require('logger')

local settings = config.load(defaults)
local disclaimer = texts.new([[
[Important]

This addon is for your sole convenience while farming segments. Overlays will only be shown in Odyssey.
Try to always load before entering. You can drag segments and resistances around individually.
The resistance table is not a completely accurate representation of actual game data.
Segments might get lost to "lag" but will catch up if you keep killing mobs.
This means that the last (few) mob(s) you kill in a run might not count if you lag too much.
Use as orientation only!

Type '//shh understood' to remove this message permanently and '//shh h' for commands.]],
settings.disclaimer, settings
)
local res_box = texts.new('${type}\n${resistances}${crueljoke}', settings.res_box, settings)
local seg_box = texts.new('Segments: ${segments}', settings.seg_box, settings)
local last_target = ''
local segments = 0
local player_total = 0
local sheolzone

-- Pre-declare our event monitor variables locally
local res_monitor, seg_monitor, floor_monitor, rabao_monitor, sheolzone_fetcher

local translocators = {{1,3,5}, {1,3,6}, {1,2}}
local instances = {{1019,1020}, {1021,1022}, {1023,1024}}
local map = images.new(settings.map, settings)

function center_disclaimer()
    local x, y = disclaimer:extents()
    disclaimer:pos(windower.get_windower_settings().ui_x_res/2-x/2,settings.disclaimer.pos.y); disclaimer:bg_alpha(255); disclaimer:alpha(255)
end

function set_up_entry()
    -- Unregister existing events to prevent duplicates if manual command is used multiple times
    if res_monitor then windower.unregister_event(res_monitor); res_monitor = nil end
    if seg_monitor then windower.unregister_event(seg_monitor); seg_monitor = nil end
    if floor_monitor then windower.unregister_event(floor_monitor); floor_monitor = nil end

    -- reset segments; in case of two consecutive runs
    segments = 0
    seg_box.segments = segments
    -- show segment counter (default: true, user option)
    if settings.seg_box.show then
        seg_box:show()
    end

    -- show general addon disclaimer if it hasn't yet (addon was autoloaded on startup e.g.)
    if settings.disclaimer.show then
        disclaimer:show()
        center_disclaimer:schedule(0.1)
    end

    -- initiate running functions
    res_monitor = windower.register_event('target change', print_resistances)
    seg_monitor = windower.register_event('incoming chunk', count_segments)
    floor_monitor = windower.register_event('outgoing chunk', watch_floor_change)
end

function watch_for_entry(id, data, modified, injected, blocked)
    -- the rabao conflux will send an NPC interaction with our character upon/before zoning that tells us the zone we'll be in (A/B/C/Gaol)
    if id == 0x034 and not injected then
        local packet = packets.parse('incoming', data)
        if packet['Menu ID'] == 173 and packet['NPC'] == windower.ffxi.get_player().id then
            local i = packet['Menu Parameters']:unpack('i', 1)
            sheolzone = i < 4 and i > 0 and i or nil
        end
    end
end

function clean_up_exit(zoned_to)
    -- keep segments from last run displayed in Rabao (default: true, user option)
    if settings.seg_box.conserve and zoned_to == 247 then
        res_box:hide()
        seg_box.segments = segments..' (last run)'

        -- show disclaimer about retaining option if it hasn't yet
        if settings.seg_box.disclaimer then
            disclaimer:text('Segments from last run are by default conserved in Rabao\nYou can disable this behavior with //shh conserve [on/off]\nType //shh understood to hide this message permanently.')
            disclaimer:show()
        end
    else
        res_box:hide(); seg_box:hide()
    end

    -- unset sheol zone
    sheolzone = nil
end

function build_res_strings(target, target_index)
    local name = target.name
    local is_agon = name:find('Agon')
    local job = (name:find('Nostos') or is_agon) and name:gsub('^%a+%s', '') or name
    
    -- SAFETY CHECK: Ensure we know what zone we are in and that the zone data exists
    if not sheolzone or not resistances[sheolzone] then return end
    
    local zone_res = resistances[sheolzone]

    local type
    -- loop over mobs, find current, and get its family key
    for k, v in pairs(types) do
        if table.find(v, job) then
            type = k
            break
        end
    end

    -- RESOLVE CLERIC CONFLICT: Quadav (Sheol A) vs Mamool (Sheol C)
    if job == 'Cleric' then
        if sheolzone == 1 then type = 'Quadav'
        elseif sheolzone == 3 then type = 'Mamool'
        end
    end

    -- SAFETY CHECK: Ensure we found a type for this mob to prevent nil crashes
    if not type then return end

    -- FIX: Job Lookup Trap
    -- Nostos uses job ('Crab') in resistances. Agon uses type ('Tonberry').
    local lookup_key = is_agon and type or job

    -- SAFETY CHECK: Ensure we actually have data for this family in this specific zone
    if not zone_res[lookup_key] then return end

    local res_string = ''
    local ele_string = ''
    
    -- Dynamically calculate resistance penalties based on Zone and Mob Type
    local phys_penalty = 0
    local magic_penalty = 0
    local secondary_phys_penalty = 0
    local secondary_phys_type = ''

    if is_agon then
        if sheolzone == 2 then
            phys_penalty = 0.375
        elseif sheolzone == 3 then
            phys_penalty = 0.625
            magic_penalty = 0.125
            secondary_phys_penalty = 0.125
            if type == 'Mamool' then secondary_phys_type = 'Slashing' end
            if type == 'Troll' then secondary_phys_type = 'Piercing' end
        end
    else
        if sheolzone == 2 then
            phys_penalty = 0.25
            magic_penalty = 0.25
        elseif sheolzone == 3 then
            phys_penalty = 0.50
            magic_penalty = 0.50
        end
    end

    -- Calculate the true max magic element dynamically, factoring in Odyssey magic resistance
    local max_ele = -999
    for i = 5, 12 do
        local base_val = zone_res[lookup_key][i]
        local penalty = types[type][1] == 'Magic' and magic_penalty or 0
        if is_agon and sheolzone == 3 then penalty = magic_penalty end
        local modified_val = base_val - penalty
        if modified_val > max_ele then max_ele = modified_val end
    end

    -- loop over weapon types
    for i = 1, 3 do
        local weapon = zone_res['Legend'][i]
        local resistance = zone_res[lookup_key][i]
        
        if weapon == types[type][1] then
            resistance = resistance - phys_penalty
        elseif weapon == secondary_phys_type then
            resistance = resistance - secondary_phys_penalty
        end
        
        local color = resistance > 1 and [[\cs(0, 255, 0)]] or resistance < 1 and [[\cs(255, 0, 0)]] or [[\cs(255, 255, 255)]]
        res_string = res_string..'\n'..color..string.rpad(weapon..':', ' ', 10)..string.lpad(tostring(resistance*100), ' ', 3)..[[%\cr]]
    end

    -- loop over elements
    for i = 5, 12 do
        local ele = string.slice(zone_res['Legend'][i], 1, 2)
        local base_val = zone_res[lookup_key][i]
        local penalty = types[type][1] == 'Magic' and magic_penalty or 0
        if is_agon and sheolzone == 3 then penalty = magic_penalty end
        local val = base_val - penalty
        local color = val == max_ele and [[\cs(0, 255, 0)]] or val < 1 and [[\cs(255, 0, 0)]] or [[\cs(255, 255, 255)]]

        if i == 9 then
            ele_string = ele_string..'\n'..color..ele..':'..string.lpad(tostring(math.round(val * 100, 0)), ' ', 3)..[[%\cr]]
        elseif i == 5 then
            ele_string = ele_string..color..ele..':'..string.lpad(tostring(math.round(val * 100, 0)), ' ', 3)..[[%\cr]]
        else
            ele_string = ele_string..' '..color..ele..':'..string.lpad(tostring(math.round(val * 100, 0)), ' ', 3)..[[%\cr]]
        end
    end

    res_box.name = name
    res_box.type = type
    res_box.resistances = res_string..'\n\n'..ele_string

    if settings.res_box.joke then
        local color = zone_res[lookup_key][4] == 0.000 and [[\cs(255, 0, 0)]] or [[\cs(0, 255, 0)]]
        res_box.crueljoke = color..'\n\nCruel Joke'..[[\cr]]
    end
end

function print_resistances(target_index)
    if settings.res_box.show then
        local target = windower.ffxi.get_mob_by_index(target_index)
        local is_halo = target and target.name:contains('Halo')
    
        -- only redraw if the mob is different from last one
        if
            target_index > 0 and
            target and 
            not is_halo and
            target.name ~= last_target and
            target.spawn_type == 16 and
            target.valid_target
        then
            build_res_strings(target, target_index)
            last_target = target.name
        end
    
        -- only show when enemy is a mob
        if target and target.spawn_type == 16 and target.valid_target and not is_halo then
            res_box:show()
        else
            res_box:hide()
        end
    end
end

function count_segments(id, data, modified, injected, blocked)
    -- resting message is used for segment count besides other things like odyssey queue messages
    if sheolzone and sheolzone > 0 and sheolzone < 4 and id == 0x02A and not injected then
        local packet = packets.parse('incoming', data)
        -- message ID is subject to change with future retail updates;
        -- changed: April 2022 (40001>40002), September 2022 (40002>40005)
        -- luckily the players total is also passed here
        -- this makes it possible to prevent duplicates and account for packet loss at the same time
        -- we only count segments that also show a difference in total to exclude duplicated chunks
        if packet['Message ID'] == 40015 and player_total ~= packet['Param 2'] then
            -- make an exception if the total does not match the current count, i.e. one ore more former packets got lost
            if packet['Param 2'] - packet['Param 1'] ~= player_total and player_total ~= 0 then
                segments = segments + packet['Param 2'] - player_total
            else
                segments = segments + packet['Param 1']
            end
            player_total = packet['Param 2']
            seg_box.segments = segments
        end
    end
end

function watch_floor_change(id, data, modified, injected, blocked)
    if id == 0x05B and not injected then
        local packet = packets.parse('outgoing', data)
        local new_floor
        
        -- Safely query the target ID to check its name instead of using an expensive tostring() on the packet
        local target = windower.ffxi.get_mob_by_id(packet['Target'])
        if not target then return end

        local target_name = target.name or ''
        
        -- conflux menu was used
        if target_name:contains('Conflux') then
            -- even numbered confluxes always teleport one floor down where that floor equals the confluxes number divided by two
            if packet['Option Index'] % 2 == 0 then
                new_floor = packet['Option Index'] / 2 == 0 and 1 or packet['Option Index'] / 2
            -- odd numbered confluxes always teleport one floor up
            else
                -- store lowest floor
                local f = 1
                -- loop over odd conflux values
                for i = 1, 11, 2 do
                    -- increase floor by one each step
                    f = f + 1
                    -- stop at actual conflux that was used
                    if i == packet['Option Index'] then
                        new_floor = f
                        break
                    end
                end
            end

        -- translocator menu was used
        elseif target_name:contains('Translocator') then
            -- 'option index' is the translocator that was warped to, corresponding floors are known values
            new_floor = translocators[sheolzone] and translocators[sheolzone][packet['Option Index']]
        end

        if new_floor and sheolzone then
            map:path(windower.addon_path..'maps/'..sheolzone..'-'..new_floor..'.png')
        end
    end
end

function set_sheolzone_inside(id, data, modified, injected, blocked)
    -- checking any NPC update in range while sheolzone is not set
    if id == 0x00E and not injected then

        local packet = packets.parse('incoming', data)
        local mob = windower.ffxi.get_mob_by_index(packet['Index'])
        local sender = mob and mob.spawn_type or nil

        if sender == 16 or sender == 2 then
            -- grab unique instance bit
            local instance = bit.band(bit.rshift(mob.id, 12), 0xFFF)
            -- find out if current instance is Sheol A, B or C
            for k, v in pairs(instances) do
                if table.find(v, instance) then
                    sheolzone = k
                    map:path(windower.addon_path..'maps/'..sheolzone..'-1.png')
                    set_up_entry()
                    break
                end
            end

            -- stop all of this from firing over and over again since we now know what instance we are in
            if sheolzone_fetcher then
                windower.unregister_event(sheolzone_fetcher)
                sheolzone_fetcher = nil
            end
        end
    end
end

windower.register_event('load', function()
    -- addon loaded in Sheol A, B, C, Gaol and Selbina HTMBs: Scan instance
    if windower.ffxi.get_info().zone == 298 or windower.ffxi.get_info().zone == 279 then
        sheolzone_fetcher = windower.register_event('incoming chunk', set_sheolzone_inside)
    -- loaded in Rabao
    elseif windower.ffxi.get_info().zone == 247 then
        rabao_monitor = windower.register_event('incoming chunk', watch_for_entry)
    end
end)

windower.register_event('zone change', function(new_id, old_id)
    -- when coming to Rabao start watching for Odyssey entry
    if new_id == 247 then
        rabao_monitor = windower.register_event('incoming chunk', watch_for_entry)

    -- Odyssey can be instanced in either 'Walk of Echoes [P1]' or 'Walk of Echoes [P2]'
    -- we explicitely specify to zone from Rabao because 298 and 279 are also used by Selbina's HTMB
    elseif old_id == 247 and (new_id == 298 or new_id == 279) then
        -- this should be the default path when the addon was already loaded before going in
        if sheolzone then
            set_up_entry()
            map:path(windower.addon_path..'maps/'..sheolzone..'-1.png')
        -- if for whatever reason sheolzone wasn't set on entry then scan instance and set everything up if necessary
        else
            sheolzone_fetcher = windower.register_event('incoming chunk', set_sheolzone_inside)
        end
    end

    -- leaving Sheol A, B or C
    if sheolzone and (old_id == 298 or old_id == 279) then
        if seg_monitor then windower.unregister_event(seg_monitor); seg_monitor = nil end
        if res_monitor then windower.unregister_event(res_monitor); res_monitor = nil end
        if floor_monitor then windower.unregister_event(floor_monitor); floor_monitor = nil end
        clean_up_exit(new_id)
    end
    
    -- leaving Rabao to anywhere else
    if rabao_monitor and old_id == 247 then
        windower.unregister_event(rabao_monitor)
        rabao_monitor = nil
        if not sheolzone and seg_box:visible() then
            seg_box:hide()
        end
    end
end)

windower.register_event('addon command', function(command, ...)
    local cmd = command and command:lower()
    local arg = {...}

    if cmd == 'understood' then
        disclaimer:hide()
        if settings.disclaimer.show then
            settings.disclaimer.show = false
        elseif settings.seg_box.disclaimer then
            settings.seg_box.disclaimer = false
        end
        settings:save()

    elseif cmd == 'toggle' then
        if arg[1] == 'segments' then
            if settings.seg_box.show then
                seg_box:hide()
                notice("Segments will now be hidden.")
            else
                seg_box.segments = segments
                seg_box:show()
                notice("Segments will now be shown.")
            end
            settings.seg_box.show = not settings.seg_box.show
            settings:save()
            
        elseif arg[1] == 'resistances' then
            local target = windower.ffxi.get_mob_by_target('t')
            if settings.res_box.show then
                res_box:hide()
                notice("Resistances will now be hidden.")
            elseif
                (windower.ffxi.get_info().zone == 298 or windower.ffxi.get_info().zone == 279) and
                target and target.spawn_type == 16 and
                target.valid_target
            then
                res_box:show()
            end
            if not settings.res_box.show then
                notice("Resistances will now be shown.")
            end
            settings.res_box.show = not settings.res_box.show
            settings:save()

        elseif arg[1] == 'joke' then
            if settings.res_box.joke then
                notice("Cruel Joke compatability will now be hidden.")
            else
                notice("Cruel Joke compatability will now be shown.")
            end
            settings.res_box.joke = not settings.res_box.joke
            settings:save()
            last_target = ''
        else
            error("Accepts either 'segments' or 'resistances'.")
        end

    elseif cmd == 'bg' then
        arg[2] = tonumber(arg[2])
        if arg[1] == 'all' or arg[1] == 'segments' or arg[1] == 'resistances' then
            if not arg[2] or arg[2] < 0 or arg[2] > 255 then
                error("Transparency value must be between 0 and 255.")
            else
                if arg[1] == 'all' or arg[1] == 'segments' then
                    settings.seg_box.bg.alpha = arg[2]
                    settings:save()
                    seg_box:bg_alpha(arg[2])
                end
                if arg[1] == 'all' or arg[1] == 'resistances' then
                    settings.res_box.bg.alpha = arg[2]
                    settings:save()
                    res_box:bg_alpha(arg[2])
                end
            end
        else
            error("Accepts either 'segments', 'resistances' or 'all'.")
        end

    elseif cmd == 'conserve' then
        settings.seg_box.conserve = not settings.seg_box.conserve
        settings:save()

    elseif cmd == 'map' then
        if not sheolzone then
            error("Must be in either Sheol A, B or C to interact with maps.")
        elseif arg[1] == 'center' then
            map:pos_x(windower.get_windower_settings().ui_x_res / 2 - settings.map.size.width / 2)
            map:pos_y(windower.get_windower_settings().ui_y_res / 2 - settings.map.size.height / 2)
        elseif arg[1] == 'size' then
            if not tonumber(arg[2]) then
                error("[size] must be an integer.")
            else
                settings.map.size.width = tonumber(arg[2])
                settings.map.size.height = tonumber(arg[2])
                map:size(settings.map.size.width, settings.map.size.height)
                settings:save()
                config.reload(settings)
            end
        elseif arg[1] == 'floor' then
            if not tonumber(arg[2]) then
                error("[floor] must be an integer fitting this Sheol.")
            else
                map:path(windower.addon_path..'maps/'..sheolzone..'-'..arg[2]..'.png')
            end
        else
            if map and map:visible() then
                map:hide()
            else
                map:show()
            end
        end

    elseif cmd == 'zone' then
        local current_zone = windower.ffxi.get_info().zone
        if current_zone ~= 298 and current_zone ~= 279 then
            error("You must be inside an Odyssey instance to manually set the zone.")
            return
        end

        if not arg[1] then
            error("Please specify a zone: a, b, or c.")
            return
        end
        
        local target_zone = arg[1]:lower()
        if target_zone == 'a' then
            sheolzone = 1
        elseif target_zone == 'b' then
            sheolzone = 2
        elseif target_zone == 'c' then
            sheolzone = 3
        else
            error("Invalid zone. Please use 'a', 'b', or 'c'.")
            return
        end

        notice("Sheol zone manually set to: " .. target_zone:upper())
        map:path(windower.addon_path..'maps/'..sheolzone..'-1.png')
        set_up_entry()
        
        -- Turn off the automatic fetcher if it's currently running
        if sheolzone_fetcher then
            windower.unregister_event(sheolzone_fetcher)
            sheolzone_fetcher = nil
        end

    else
        -- Creative standby message when outside of Odyssey
        if not sheolzone then
            windower.add_to_chat(167, "--> [SheolHelper is on Standby] <--")
            windower.add_to_chat(207, "Tracking and mob analysis are currently hibernating.")
            windower.add_to_chat(207, "Systems will automatically engage upon entering Odyssey.")
            windower.add_to_chat(207, " ") -- Blank line for spacing
        end

        windower.add_to_chat(200, "SheolHelper Commands:")
        windower.add_to_chat(207, "//shh zone [a/b/c] : Manually sets the current Sheol zone")
        windower.add_to_chat(207, "//shh toggle [segments/resistances/joke] : Shows/hides either info")
        windower.add_to_chat(207, "//shh bg [segments/resistances/all] [0-255] : Sets the alpha channel for backgrounds")
        windower.add_to_chat(207, "//shh conserve : Toggles segments being shown in Rabao after a run")
        windower.add_to_chat(207, "//shh map : Toggle the current floor's map")
        windower.add_to_chat(207, "//shh map center : Repositions the map to the center of the screen")
        windower.add_to_chat(207, "//shh map size [size] : Sets the map to the new [size].")
        windower.add_to_chat(207, "//shh map floor [floor] : Sets the map to reflect [floor].")
    end
end)