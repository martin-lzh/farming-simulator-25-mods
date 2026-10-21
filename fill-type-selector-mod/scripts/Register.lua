local modName = g_currentModName

-- Engine class tables survive map changes. Refresh callbacks without stacking hooks.
local function installHook(class, method, prepend, callback)
    local key = "fts_" .. modName .. "_" .. method
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

-- Everything the specialization calls or overwrites. If one is missing, nothing is added.
local function findMissingApi()
    local required = {
        {"Sprayer", Sprayer}, {"FillUnit", FillUnit},
        {"Sprayer.getExternalFill", Sprayer and Sprayer.getExternalFill},
        {"Sprayer.getIsSprayerExternallyFilled", Sprayer and Sprayer.getIsSprayerExternallyFilled},
        {"Sprayer.getIsSprayTypeActive", Sprayer and Sprayer.getIsSprayTypeActive},
        {"Sprayer.setSprayerAITerrainDetailProhibitedRange", Sprayer and Sprayer.setSprayerAITerrainDetailProhibitedRange},
        {"FillUnit.setFillUnitFillTypeToDisplay", FillUnit and FillUnit.setFillUnitFillTypeToDisplay},
        {"FillUnit.getFillUnitSupportedFillTypes", FillUnit and FillUnit.getFillUnitSupportedFillTypes},
        {"SpecializationUtil.registerOverwrittenFunction", SpecializationUtil.registerOverwrittenFunction},
        {"InputAction.TOGGLE_SEEDS", InputAction.TOGGLE_SEEDS},
        {"InputAction.TOGGLE_SEEDS_BACK", InputAction.TOGGLE_SEEDS_BACK},
        {"FillType.UNKNOWN", FillType ~= nil and FillType.UNKNOWN},
        {"g_sprayTypeManager", g_sprayTypeManager},
        {"FTSSelectFillTypeEvent", FTSSelectFillTypeEvent}, {"FillTypeSelector", FillTypeSelector},
    }
    for _, entry in ipairs(required) do
        if not entry[2] then
            return entry[1]
        end
    end
    return nil
end

installHook(TypeManager, "validateTypes", true, function(manager)
    -- Mods receive a proxy manager; compare its type instead of table identity.
    if manager.typeName ~= "vehicle" then return end
    local missing = findMissingApi()
    if missing ~= nil then
        Logging.warning("Fill Type Selector disabled: game function %s not found", missing)
        return
    end
    local registered = g_specializationManager:getSpecializationByName("fillTypeSelector")
    if registered == nil or registered.name ~= FillTypeSelector.SPEC_NAME then
        Logging.error("Fill Type Selector specialization was not registered as %s", FillTypeSelector.SPEC_NAME)
        return
    end
    for name, entry in pairs(manager.types) do
        if FillTypeSelector.prerequisitesPresent(entry.specializations)
            and entry.specializationsByName[registered.name] == nil then
            manager:addSpecialization(name, registered.name)
        end
    end
end)
