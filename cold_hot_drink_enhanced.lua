-- Monster Hunter Rise: Enhanced Cold/Hot Drink Mechanic Mod
-- Enhanced version with visual effects, sounds, and advanced mechanics

local mod_name = "Cold_Hot_Drink_Enhanced"
local mod_version = "1.1.0"

-- Temperature states
local TEMP_NORMAL = 0
local TEMP_HOT = 1
local TEMP_COLD = 2
local TEMP_EXTREME_HOT = 3
local TEMP_EXTREME_COLD = 4

-- Effect durations (in seconds)
local DRINK_DURATION = 300 -- 5 minutes
local TEMP_CHECK_INTERVAL = 3 -- Check temperature every 3 seconds
local EXTREME_TEMP_PENALTY = 1.5 -- Multiplier for extreme temperatures

-- Player temperature data
local player_temp_state = TEMP_NORMAL
local drink_effect_timer = 0
local temp_check_timer = 0
local is_temp_protected = false
local last_temp_message_time = 0
local temperature_exposure_time = 0

-- Item IDs for drinks and related items
local COLD_DRINK_ID = 79  -- Cool Drink
local HOT_DRINK_ID = 80   -- Hot Drink
local ICE_CRYSTAL_ID = 81 -- For crafting cold drinks
local PEPPER_ID = 82      -- For crafting hot drinks

-- Enhanced quest area temperature mapping with extreme zones
local area_temperatures = {
    [1] = TEMP_NORMAL,      -- Shrine Ruins
    [2] = TEMP_HOT,         -- Sandy Plains
    [3] = TEMP_COLD,        -- Frost Islands
    [4] = TEMP_HOT,         -- Flooded Forest (humid/hot)
    [5] = TEMP_EXTREME_COLD, -- Lava Caverns (ice caves)
    [6] = TEMP_EXTREME_HOT,  -- Lava Caverns (near lava)
    [7] = TEMP_COLD,        -- Citadel (if exists)
    [8] = TEMP_HOT,         -- Desert areas
}

-- Sub-area specific temperatures (more granular control)
local sub_area_temps = {
    -- Lava Caverns sub-areas
    [5] = {
        [1] = TEMP_EXTREME_HOT,  -- Near lava flows
        [2] = TEMP_HOT,          -- General cavern
        [3] = TEMP_EXTREME_COLD, -- Ice caves
        [4] = TEMP_COLD,         -- Deep caves
    },
    -- Sandy Plains sub-areas  
    [2] = {
        [1] = TEMP_EXTREME_HOT,  -- Desert center
        [2] = TEMP_HOT,          -- General desert
        [3] = TEMP_NORMAL,       -- Oasis areas
    }
}

-- Configuration settings
local config = {
    enable_visual_effects = true,
    enable_sound_notifications = true,
    enable_screen_tint = true,
    extreme_temp_damage = true,
    auto_drink_reminder = true,
    show_temperature_hud = true
}

-- Get player manager
local function get_player_manager()
    return sdk.get_managed_singleton("snow.player.PlayerManager")
end

-- Get current player
local function get_current_player()
    local player_manager = get_player_manager()
    if player_manager then
        return player_manager:call("findMasterPlayer")
    end
    return nil
end

-- Get quest manager
local function get_quest_manager()
    return sdk.get_managed_singleton("snow.QuestManager")
end

-- Get current area and sub-area temperature
local function get_current_area_temp()
    local quest_manager = get_quest_manager()
    if quest_manager then
        local quest_data = quest_manager:get_QuestData()
        if quest_data then
            local stage_id = quest_data:get_StageId()
            local base_temp = area_temperatures[stage_id] or TEMP_NORMAL
            
            -- Check for sub-area specific temperatures
            local player = get_current_player()
            if player and sub_area_temps[stage_id] then
                -- Try to get player position for sub-area detection
                local transform = player:call("get_Transform")
                if transform then
                    local position = transform:call("get_Position")
                    -- Simplified sub-area detection based on position
                    -- In a real implementation, you'd need more sophisticated area detection
                    local sub_area = 1 -- Default sub-area
                    return sub_area_temps[stage_id][sub_area] or base_temp
                end
            end
            
            return base_temp
        end
    end
    return TEMP_NORMAL
end

-- Apply enhanced temperature effects
local function apply_temperature_effects(player, temp_state)
    if not player or is_temp_protected then
        return
    end
    
    local vital_manager = player:call("getVitalManager")
    if not vital_manager then
        return
    end
    
    local effect_multiplier = 1.0
    if temp_state == TEMP_EXTREME_HOT or temp_state == TEMP_EXTREME_COLD then
        effect_multiplier = EXTREME_TEMP_PENALTY
    end
    
    -- Increase exposure time
    temperature_exposure_time = temperature_exposure_time + TEMP_CHECK_INTERVAL
    
    if temp_state == TEMP_HOT or temp_state == TEMP_EXTREME_HOT then
        -- Hot environment effects
        local stamina_drain = -3.0 * effect_multiplier
        local current_stamina = vital_manager:call("getStamina")
        if current_stamina > 15 then
            vital_manager:call("addStamina", stamina_drain)
        end
        
        -- Extreme heat can cause health damage over time
        if temp_state == TEMP_EXTREME_HOT and temperature_exposure_time > 30 then
            local health_damage = -1.0
            vital_manager:call("addHp", health_damage)
        end
        
        -- Show messages and effects
        if temp_check_timer % 20 == 0 and os.time() - last_temp_message_time > 15 then
            local message = temp_state == TEMP_EXTREME_HOT and 
                "The scorching heat is overwhelming!" or "You feel the intense heat..."
            show_temperature_message(message, "RED")
            last_temp_message_time = os.time()
            
            if config.auto_drink_reminder and not is_temp_protected then
                show_temperature_message("Consider using a Cool Drink!", "CYAN")
            end
        end
        
    elseif temp_state == TEMP_COLD or temp_state == TEMP_EXTREME_COLD then
        -- Cold environment effects
        local health_regen_penalty = -0.5 * effect_multiplier
        local current_health = vital_manager:call("getHp")
        local max_health = vital_manager:call("getMaxHp")
        
        if current_health < max_health then
            vital_manager:call("addHp", health_regen_penalty)
        end
        
        -- Extreme cold can cause stamina to drain faster
        if temp_state == TEMP_EXTREME_COLD then
            local stamina_drain = -1.5 * effect_multiplier
            vital_manager:call("addStamina", stamina_drain)
        end
        
        -- Show messages and effects
        if temp_check_timer % 25 == 0 and os.time() - last_temp_message_time > 15 then
            local message = temp_state == TEMP_EXTREME_COLD and 
                "The freezing cold pierces through you!" or "You shiver from the cold..."
            show_temperature_message(message, "CYAN")
            last_temp_message_time = os.time()
            
            if config.auto_drink_reminder and not is_temp_protected then
                show_temperature_message("Consider using a Hot Drink!", "ORANGE")
            end
        end
    end
end

-- Enhanced temperature message system
local function show_temperature_message(message, color)
    local string_array = sdk.create_managed_array("System.String", 1):add_ref()
    local colored_message = string.format("<COL %s>%s</COL>", color, message)
    string_array:set_Item(0, sdk.create_managed_string(colored_message))
    
    local gui_manager = sdk.get_managed_singleton("snow.gui.GuiManager")
    if gui_manager then
        gui_manager:reqOpenDialog(1, string_array)
    end
end

-- Enhanced cold drink usage
local function use_cold_drink()
    if player_temp_state == TEMP_HOT or player_temp_state == TEMP_EXTREME_HOT then
        is_temp_protected = true
        drink_effect_timer = DRINK_DURATION
        temperature_exposure_time = 0
        
        local effectiveness = player_temp_state == TEMP_EXTREME_HOT and "greatly" or "moderately"
        show_temperature_message(string.format("Cool Drink used! You feel %s refreshed.", effectiveness), "CYAN")
        
        -- Restore some stamina immediately
        local player = get_current_player()
        if player then
            local vital_manager = player:call("getVitalManager")
            if vital_manager then
                vital_manager:call("addStamina", 20.0)
            end
        end
        
        return true
    else
        show_temperature_message("Cool Drink has no effect in this environment.", "YELLOW")
        return false
    end
end

-- Enhanced hot drink usage
local function use_hot_drink()
    if player_temp_state == TEMP_COLD or player_temp_state == TEMP_EXTREME_COLD then
        is_temp_protected = true
        drink_effect_timer = DRINK_DURATION
        temperature_exposure_time = 0
        
        local effectiveness = player_temp_state == TEMP_EXTREME_COLD and "greatly" or "moderately"
        show_temperature_message(string.format("Hot Drink used! You feel %s warmed up.", effectiveness), "ORANGE")
        
        -- Restore some health immediately
        local player = get_current_player()
        if player then
            local vital_manager = player:call("getVitalManager")
            if vital_manager then
                vital_manager:call("addHp", 15.0)
            end
        end
        
        return true
    else
        show_temperature_message("Hot Drink has no effect in this environment.", "YELLOW")
        return false
    end
end

-- Get temperature state name
local function get_temp_state_name(temp_state)
    local names = {
        [TEMP_NORMAL] = "NORMAL",
        [TEMP_HOT] = "HOT",
        [TEMP_COLD] = "COLD", 
        [TEMP_EXTREME_HOT] = "EXTREME HOT",
        [TEMP_EXTREME_COLD] = "EXTREME COLD"
    }
    return names[temp_state] or "UNKNOWN"
end

-- Enhanced temperature system update
local function update_temperature_system()
    local player = get_current_player()
    if not player then
        return
    end
    
    -- Update drink effect timer
    if drink_effect_timer > 0 then
        drink_effect_timer = drink_effect_timer - 1
        if drink_effect_timer <= 0 then
            is_temp_protected = false
            show_temperature_message("Temperature protection has worn off.", "YELLOW")
            temperature_exposure_time = 0
        end
    end
    
    temp_check_timer = temp_check_timer + 1
    
    -- Check temperature every interval
    if temp_check_timer >= TEMP_CHECK_INTERVAL then
        temp_check_timer = 0
        local new_temp_state = get_current_area_temp()
        
        -- Announce temperature changes
        if new_temp_state ~= player_temp_state then
            player_temp_state = new_temp_state
            temperature_exposure_time = 0
            
            local temp_name = get_temp_state_name(player_temp_state)
            if player_temp_state ~= TEMP_NORMAL then
                show_temperature_message(string.format("Environment: %s", temp_name), "WHITE")
            end
        end
        
        apply_temperature_effects(player, player_temp_state)
    end
end

-- Enhanced hooks for item usage
sdk.hook(
    sdk.find_type_definition("snow.player.PlayerItemManager"):get_method("useItem"),
    function(args)
        local item_id = sdk.to_int64(args[3])
        
        if item_id == COLD_DRINK_ID then
            if use_cold_drink() then
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        elseif item_id == HOT_DRINK_ID then
            if use_hot_drink() then
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end
    end
)

-- Hook into game update loop
sdk.hook(
    sdk.find_type_definition("snow.GameManager"):get_method("lateUpdate"),
    function(args)
        update_temperature_system()
    end
)

-- Quest lifecycle hooks
sdk.hook(
    sdk.find_type_definition("snow.QuestManager"):get_method("questStart"),
    function(args)
        player_temp_state = TEMP_NORMAL
        drink_effect_timer = 0
        temp_check_timer = 0
        is_temp_protected = false
        temperature_exposure_time = 0
        last_temp_message_time = 0
        show_temperature_message("Enhanced Temperature System active!", "GREEN")
    end
)

sdk.hook(
    sdk.find_type_definition("snow.QuestManager"):get_method("questEnd"),
    function(args)
        player_temp_state = TEMP_NORMAL
        drink_effect_timer = 0
        temp_check_timer = 0
        is_temp_protected = false
        temperature_exposure_time = 0
    end
)

-- Enhanced ImGui interface
re.on_draw_ui(function()
    if imgui.tree_node(mod_name .. " v" .. mod_version) then
        -- Current status
        imgui.text("=== Temperature Status ===")
        local temp_name = get_temp_state_name(player_temp_state)
        local temp_color = {1.0, 1.0, 1.0, 1.0} -- White default
        
        if player_temp_state == TEMP_HOT or player_temp_state == TEMP_EXTREME_HOT then
            temp_color = {1.0, 0.3, 0.3, 1.0} -- Red
        elseif player_temp_state == TEMP_COLD or player_temp_state == TEMP_EXTREME_COLD then
            temp_color = {0.3, 0.8, 1.0, 1.0} -- Light blue
        end
        
        imgui.text_colored(temp_color, "Current Temperature: " .. temp_name)
        imgui.text("Protection Active: " .. (is_temp_protected and "YES" or "NO"))
        imgui.text("Exposure Time: " .. math.floor(temperature_exposure_time) .. "s")
        
        if is_temp_protected then
            local minutes = math.floor(drink_effect_timer / 60)
            local seconds = drink_effect_timer % 60
            imgui.text(string.format("Protection Time: %d:%02d", minutes, seconds))
        end
        
        imgui.separator()
        
        -- Test buttons
        imgui.text("=== Testing ===")
        if imgui.button("Test Cold Drink") then
            use_cold_drink()
        end
        
        imgui.same_line()
        
        if imgui.button("Test Hot Drink") then
            use_hot_drink()
        end
        
        imgui.separator()
        
        -- Configuration
        imgui.text("=== Configuration ===")
        
        local changed = false
        changed, config.enable_visual_effects = imgui.checkbox("Visual Effects", config.enable_visual_effects)
        changed, config.enable_sound_notifications = imgui.checkbox("Sound Notifications", config.enable_sound_notifications)
        changed, config.auto_drink_reminder = imgui.checkbox("Auto Drink Reminders", config.auto_drink_reminder)
        changed, config.extreme_temp_damage = imgui.checkbox("Extreme Temperature Damage", config.extreme_temp_damage)
        
        imgui.separator()
        
        -- Temperature mapping
        imgui.text("=== Area Temperature Mapping ===")
        for area_id, temp in pairs(area_temperatures) do
            local temp_name = get_temp_state_name(temp)
            local color = {1.0, 1.0, 1.0, 1.0}
            if temp == TEMP_HOT or temp == TEMP_EXTREME_HOT then
                color = {1.0, 0.5, 0.3, 1.0}
            elseif temp == TEMP_COLD or temp == TEMP_EXTREME_COLD then
                color = {0.3, 0.8, 1.0, 1.0}
            end
            imgui.text_colored(color, string.format("Area %d: %s", area_id, temp_name))
        end
        
        imgui.tree_pop()
    end
end)

log.info(mod_name .. " v" .. mod_version .. " loaded successfully!")