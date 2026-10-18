local modName = g_currentModName

-- Engine class tables survive map changes. Refresh callbacks without stacking hooks.
local function installHook(class, method, prepend, callback)
    local key = "apm_" .. modName .. "_" .. method
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
    local registered = g_placeableSpecializationManager:getSpecializationByName("animalProductsManager")
    if registered == nil then
        Logging.error("Animal Products Manager specialization was not registered")
        return
    end
    local specName = registered.name
    for name, entry in pairs(manager.types) do
        if AnimalProductsManager.prerequisitesPresent(entry.specializations)
            and entry.specializationsByName[specName] == nil then
            manager:addSpecialization(name, specName)
        end
    end
end)

local function text(key)
    return g_i18n:getText(key, modName)
end

local function showProducts(placeable)
    local APM = AnimalProductsManager
    if not APM.canManage(placeable, nil) then return end
    local products = APM.products(placeable, true)
    local entries = {}
    for _, fillType in ipairs(products) do
        table.insert(entries, {fillType = fillType, title = g_fillTypeManager:getFillTypeTitleByIndex(fillType),
            mode = APM.mode(placeable, fillType)})
    end
    if #entries == 0 then return end
    local ownerFarmId = placeable:getOwnerFarmId()
    APMProductDialog.show(placeable:getName(), text("apm_explanation"), entries, function(changes)
        if not APM.canManage(placeable, nil) or placeable:getOwnerFarmId() ~= ownerFarmId then return end
        for _, change in ipairs(changes) do
            APM.requestMode(placeable, change.fillType, change.mode)
        end
    end)
end

installHook(InGameMenuAnimalsFrame, "updateMenuButtons", false, function(frame)
    local placeable = frame.selectedHusbandry
    if AnimalProductsManager.canManage(placeable, nil) and #AnimalProductsManager.products(placeable, true) > 0 then
        table.insert(frame.menuButtonInfo, {
            inputAction = InputAction.MENU_EXTRA_1,
            text = text("apm_title"),
            callback = function() showProducts(frame.selectedHusbandry) end
        })
        frame:setMenuButtonInfoDirty()
    end
end)
