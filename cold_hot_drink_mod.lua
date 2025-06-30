-- Monster Hunter Rise: Cold/Hot Drink Mechanic Mod
-- Adds temperature effects and cold/hot drink mechanics to the game

local mod_name = "Cold_Hot_Drink_Mod"
local mod_version = "1.0.0"

-- Temperature states
local TEMP_NORMAL = 0
local TEMP_HOT = 1
local TEMP_COLD = 2

-- Effect durations (in seconds)
local DRINK_DURATION = 300 -- 5 minutes
local TEMP_CHECK_INTERVAL = 5 -- Check temperature every 5 seconds

-- Player temperature data
local player_temp_state = TEMP_NORMAL
local drink_effect_timer = 0
local temp_check_timer = 0
local is_temp_protected = false

-- Item IDs for cold and hot drinks (using existing item IDs from MHR)
local COLD_DRINK_ID = 79  -- Cool Drink
local HOT_DRINK_ID = 80   -- Hot Drink

-- Quest area temperature mapping
local area_temperatures = {
    [1] = TEMP_NORMAL,  -- Shrine Ruins
    [2] = TEMP_HOT,     -- Sandy Plains
    [3] = TEMP_COLD,    -- Frost Islands
    [4] = TEMP_HOT,     -- Flooded Forest (humid/hot)
    [5] = TEMP_COLD,    -- Lava Caverns (cold areas)
    [6] = TEMP_HOT,     -- Lava Caverns (hot areas)
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

-- Get current area temperature
local function get_current_area_temp()
    local quest_manager = get_quest_manager()
    if quest_manager then
        local quest_data = quest_manager:get_QuestData()
        if quest_data then
            local stage_id = quest_data:get_StageId()
            return area_temperatures[stage_id] or TEMP_NORMAL
        end
    end
    return TEMP_NORMAL
end

-- Apply temperature effects to player
local function apply_temperature_effects(player, temp_state)
    if not player or is_temp_protected then
        return
    end
    
    local success, err = pcall(function()
        local vital_manager = player:call("getVitalManager")
        if not vital_manager then
            return
        end
        
        if temp_state == TEMP_HOT then
            -- Hot environment: gradual stamina drain
            local current_stamina = vital_manager:call("getStamina")
            if current_stamina and current_stamina > 10 then
                vital_manager:call("addStamina", -2.0)
            end
            
            -- Show hot effect message occasionally
            if temp_check_timer % 30 == 0 then
                show_temperature_message("You feel the scorching heat...", "RED")
            end
            
        elseif temp_state == TEMP_COLD then
            -- Cold environment: slower health regeneration and movement
            local current_health = vital_manager:call("getHp")
            local max_health = vital_manager:call("getMaxHp")
            
            -- Reduce natural health regeneration
            if current_health and max_health and current_health < max_health then
                vital_manager:call("addHp", -1.0)
            end
            
            -- Show cold effect message occasionally
            if temp_check_timer % 30 == 0 then
                show_temperature_message("You shiver from the cold...", "CYAN")
            end
        end
    end)
    
    if not success then
        log.error("Error applying temperature effects: " .. tostring(err))
    end
end

-- Show temperature-related messages
local function show_temperature_message(message, color)
    -- Add nil checks to prevent runtime errors
    if not message or not color then
        return
    end
    
    local success, err = pcall(function()
        local string_array = sdk.create_managed_array("System.String", 1)
        if not string_array then
            return
        end
        
        string_array = string_array:add_ref()
        local colored_message = string.format("<COL %s>%s</COL>", color, message)
        local managed_string = sdk.create_managed_string(colored_message)
        
        if managed_string then
            string_array:set_Item(0, managed_string)
            
            local gui_manager = sdk.get_managed_singleton("snow.gui.GuiManager")
            if gui_manager then
                gui_manager:reqOpenDialog(1, string_array)
            end
        end
    end)
    
    if not success then
        log.error("Error showing temperature message: " .. tostring(err))
    end
end

-- Use cold drink
local function use_cold_drink()
    if player_temp_state == TEMP_HOT then
        is_temp_protected = true
        drink_effect_timer = DRINK_DURATION
        show_temperature_message("Cool Drink used! You feel refreshed.", "CYAN")
        return true
    else
        show_temperature_message("Cool Drink has no effect in this environment.", "YELLOW")
        return false
    end
end

-- Use hot drink
local function use_hot_drink()
    if player_temp_state == TEMP_COLD then
        is_temp_protected = true
        drink_effect_timer = DRINK_DURATION
        show_temperature_message("Hot Drink used! You feel warmed up.", "ORANGE")
        return true
    else
        show_temperature_message("Hot Drink has no effect in this environment.", "YELLOW")
        return false
    end
end

-- Update temperature system
local function update_temperature_system()
    local player = get_current_player()
    if not player then
        return
    end
    
    -- Update timers
    if drink_effect_timer > 0 then
        drink_effect_timer = drink_effect_timer - 1
        if drink_effect_timer <= 0 then
            is_temp_protected = false
            show_temperature_message("Temperature protection has worn off.", "YELLOW")
        end
    end
    
    temp_check_timer = temp_check_timer + 1
    
    -- Check temperature every interval
    if temp_check_timer >= TEMP_CHECK_INTERVAL then
        temp_check_timer = 0
        player_temp_state = get_current_area_temp()
        apply_temperature_effects(player, player_temp_state)
    end
end

-- Hook into item usage to detect cold/hot drink consumption
local player_item_manager_type = sdk.find_type_definition("snow.player.PlayerItemManager")
if player_item_manager_type then
    local use_item_method = player_item_manager_type:get_method("useItem")
    if use_item_method then
        sdk.hook(
            use_item_method,
            function(args)
                local success, err = pcall(function()
                    if not args or not args[3] then
                        return
                    end
                    
                    local item_id = sdk.to_int64(args[3])
                    
                    if item_id == COLD_DRINK_ID then
                        if use_cold_drink() then
                            -- Prevent normal item consumption if drink was effective
                            return sdk.PreHookResult.SKIP_ORIGINAL
                        end
                    elseif item_id == HOT_DRINK_ID then
                        if use_hot_drink() then
                            -- Prevent normal item consumption if drink was effective
                            return sdk.PreHookResult.SKIP_ORIGINAL
                        end
                    end
                end)
                
                if not success then
                    log.error("Error in item usage hook: " .. tostring(err))
                end
            end
        )
    else
        log.error("Could not find useItem method")
    end
else
    log.error("Could not find PlayerItemManager type")
end

-- Hook into game update loop for temperature system
local game_manager_type = sdk.find_type_definition("snow.GameManager")
if game_manager_type then
    local late_update_method = game_manager_type:get_method("lateUpdate")
    if late_update_method then
        sdk.hook(
            late_update_method,
            function(args)
                local success, err = pcall(function()
                    update_temperature_system()
                end)
                
                if not success then
                    log.error("Error in temperature system update: " .. tostring(err))
                end
            end
        )
    else
        log.error("Could not find lateUpdate method")
    end
else
    log.error("Could not find GameManager type")
end

-- Hook quest start to reset temperature state
local quest_manager_type = sdk.find_type_definition("snow.QuestManager")
if quest_manager_type then
    local quest_start_method = quest_manager_type:get_method("questStart")
    if quest_start_method then
        sdk.hook(
            quest_start_method,
            function(args)
                local success, err = pcall(function()
                    player_temp_state = TEMP_NORMAL
                    drink_effect_timer = 0
                    temp_check_timer = 0
                    is_temp_protected = false
                    show_temperature_message("Temperature system initialized for this quest.", "WHITE")
                end)
                
                if not success then
                    log.error("Error in quest start hook: " .. tostring(err))
                end
            end
        )
    else
        log.error("Could not find questStart method")
    end
    
    -- Hook quest end to clean up
    local quest_end_method = quest_manager_type:get_method("questEnd")
    if quest_end_method then
        sdk.hook(
            quest_end_method,
            function(args)
                local success, err = pcall(function()
                    player_temp_state = TEMP_NORMAL
                    drink_effect_timer = 0
                    temp_check_timer = 0
                    is_temp_protected = false
                end)
                
                if not success then
                    log.error("Error in quest end hook: " .. tostring(err))
                end
            end
        )
    else
        log.error("Could not find questEnd method")
    end
else
    log.error("Could not find QuestManager type")
end

-- ImGui interface for mod configuration
re.on_draw_ui(function()
    local success, err = pcall(function()
        if imgui.tree_node(mod_name .. " v" .. mod_version) then
            imgui.text("Current Temperature State: " .. 
                (player_temp_state == TEMP_HOT and "HOT" or 
                 player_temp_state == TEMP_COLD and "COLD" or "NORMAL"))
            
            imgui.text("Protection Active: " .. (is_temp_protected and "YES" or "NO"))
            
            if is_temp_protected then
                imgui.text("Protection Time Left: " .. math.floor(drink_effect_timer) .. " seconds")
            end
            
            imgui.separator()
            
            if imgui.button("Test Cold Drink") then
                use_cold_drink()
            end
            
            imgui.same_line()
            
            if imgui.button("Test Hot Drink") then
                use_hot_drink()
            end
            
            imgui.separator()
            imgui.text("Area Temperature Mapping:")
            for area_id, temp in pairs(area_temperatures) do
                local temp_name = temp == TEMP_HOT and "HOT" or 
                                 temp == TEMP_COLD and "COLD" or "NORMAL"
                imgui.text("Area " .. area_id .. ": " .. temp_name)
            end
            
            imgui.tree_pop()
        end
    end)
    
    if not success then
        log.error("Error in ImGui interface: " .. tostring(err))
    end
end)

log.info(mod_name .. " v" .. mod_version .. " loaded successfully!")