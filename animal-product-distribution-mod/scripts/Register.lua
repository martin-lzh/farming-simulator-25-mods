local modName = g_currentModName

-- Engine class tables survive map changes. Refresh callbacks without stacking hooks.
local function installHook(class, method, prepend, callback)
    local key = "apd_" .. modName .. "_" .. method
    if class[key] == nil then
        local dispatch = function(...)
            if g_modIsLoaded[modName] then
                return class[key](...)
            end
        end
        local wrap = prepend and Utils.prependedFunction or Utils.appendedFunction
        class[method] = wrap(class[method], dispatch)
    end
    class[key] = callback
end

installHook(TypeManager, "validateTypes", true, function(manager)
    -- Mods receive a proxy manager; compare its type instead of table identity.
    if manager.typeName ~= "placeable" then return end
    local registered = g_placeableSpecializationManager:getSpecializationByName("animalProductDistribution")
    if registered == nil then
        Logging.error("Animal Product Distribution specialization was not registered")
        return
    end
    local specName = registered.name
    for name, entry in pairs(manager.types) do
        if AnimalProductDistribution.prerequisitesPresent(entry.specializations)
            and entry.specializationsByName[specName] == nil then
            manager:addSpecialization(name, specName)
        end
    end
end)

local function text(key)
    return g_i18n:getText(key, modName)
end

local function modeText(mode)
    return g_i18n:getText(({[0] = "ui_production_output_storing",
        [1] = "ui_production_output_selling", [2] = "ui_production_output_distributing"})[mode])
end

local function showProducts(placeable)
    local APD = AnimalProductDistribution
    if not APD.canManage(placeable, nil) then return end
    local products = APD.products(placeable)
    local options = {}
    for _, fillType in ipairs(products) do
        table.insert(options, g_fillTypeManager:getFillTypeTitleByIndex(fillType) .. " — " .. modeText(APD.mode(placeable, fillType)))
    end
    if #options == 0 then return end
    OptionDialog.show(function(index)
        local fillType = products[index]
        if fillType == nil or not APD.canManage(placeable, nil) then return end
        OptionDialog.show(function(choice)
            if choice >= 1 and choice <= 3 then
                APD.requestMode(placeable, fillType, choice - 1)
            end
        end, text("apd_explanation"), placeable:getName() .. " / " .. g_fillTypeManager:getFillTypeTitleByIndex(fillType),
            {modeText(0), modeText(1), modeText(2)}, APD.mode(placeable, fillType) + 1)
    end, text("apd_chooseProduct"), placeable:getName(), options, 1)
end

installHook(InGameMenuAnimalsFrame, "updateMenuButtons", false, function(frame)
    local placeable = frame.selectedHusbandry
    if AnimalProductDistribution.canManage(placeable, nil) and #AnimalProductDistribution.products(placeable) > 0 then
        table.insert(frame.menuButtonInfo, {
            inputAction = InputAction.MENU_EXTRA_1,
            text = text("apd_title"),
            callback = function() showProducts(frame.selectedHusbandry) end
        })
        frame:setMenuButtonInfoDirty()
    end
end)
