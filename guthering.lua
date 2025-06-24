local dataShortcut = sdk.create_instance("snow.data.DataShortcut", true):add_ref()
local function createDialogue(args, isPoint)
    local itemArg = sdk.to_int64(args[3])
    local numArg = sdk.to_int64(args[4])
    local num = numArg <= 1 and "" or " x" .. numArg
    
    local itemName = dataShortcut:call("getName(snow.data.ContentsIdSystem.ItemId)", itemArg)
    local stringArray = sdk.create_managed_array("System.String", 1):add_ref()
    local string = sdk.create_managed_string("<COL RED>" .. itemName .. num .. "</COL> obtained.")
    local isMax = sdk.to_int64(args[6])
    if isMax == 1 and not isPoint then
        string = "<COL RED>" .. itemName .. "</COL> is at max."
    end
    stringArray:set_Item(0, string)
    sdk.get_managed_singleton("snow.gui.GuiManager"):reqOpenDialog(
        1,
        stringArray
    )
    return sdk.PreHookResult.SKIP_ORIGINAL
end
sdk.hook(
    sdk.find_type_definition("snow.gui.ChatManager")
    :get_method("reqAddChatItemInfo"),
    function(args)
        return createDialogue(args, false)
    end
)
sdk.hook(
    sdk.find_type_definition("snow.gui.ChatManager")
    :get_method("reqAddChatItemPointInfo"),
    function(args)
        return createDialogue(args, true)
    end
)
local maxGather = 3
local minGather = 2
local obj
sdk.hook(
    sdk.find_type_definition("snow.access.ItemPopBehavior")
    :get_method("invokeAccessStart"),
    function(args)
        obj = sdk.to_managed_object(args[2])
    end,
    function(retval)
        local category = obj._PopCategory
        if category > 12 or category == 10 then return retval end
        local count = obj:get_PopUniqueId()
        if count == -1 then count = math.random(minGather, maxGather) end
        obj:set_PopUniqueId(count - 1)
        if obj:get_PopUniqueId() == 0 then
            obj:set_PopUniqueId(-1)
        else
            obj:repop()
        end
        return retval
    end
)
local args
sdk.hook(
    sdk.find_type_definition("snow.access.ItemPopBehavior")
    :get_method("getLotteryResult(System.Boolean)"),
    function(arg)
        args = arg
    end,
    function(retval)
        if sdk.to_int64(args[3]) == 0 then return retval end
        local results = sdk.to_managed_object(retval)
        local itemIndex = math.random(0, results:get_Count() - 1)
        local itemResult = sdk.create_managed_array("snow.data.ItemInventoryData", 1)
        itemResult:set_Item(0, results:get_Item(itemIndex))
        if itemResult:get_Item(0)._ItemCount._Num <= 5 then
            local resultLot = math.random()
            local resultCount = 1
            if resultLot < 0.1 then
                resultCount = 3
            elseif resultLot < 0.3 then
                resultCount = 2
            end
            log.debug(resultLot .. ": " .. resultCount)
            itemResult:get_Item(0)._ItemCount._Num = resultCount
        end
        return sdk.to_ptr(itemResult)
    end
)
sdk.hook(sdk.find_type_definition("snow.player.fsm.PlayerFsm2ConditionPopSensorCheckItemGatheringType")
    :get_method("evaluate"),
    function(args)
        obj = sdk.to_managed_object(args[2])
        --obj._IsCheckNowAccessMarker = false
        --obj._Type = 0
    end,
    function(retval)
        if obj._Type == 3 then
            retval = sdk.to_ptr(true)
        end
        return retval
    end
)