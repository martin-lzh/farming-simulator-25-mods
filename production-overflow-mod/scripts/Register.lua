local modName = g_currentModName
local SPEC_NAME = modName .. ".productionOverflow"

-- Everything this Mod calls, overwrites or reads in the game. If one is missing, the Mod
-- installs nothing and the production points work as in the base game.
local function findMissingApi()
    local function field(table, name)
        return table ~= nil and table[name] or nil
    end
    local outputMode = field(ProductionPoint, "OUTPUT_MODE")
    local required = {
        {"ProductionPoint", ProductionPoint},
        {"ProductionPoint.OUTPUT_MODE.KEEP", field(outputMode, "KEEP") == 0},
        {"ProductionPoint.OUTPUT_MODE.DIRECT_SELL", field(outputMode, "DIRECT_SELL") == 1},
        {"ProductionPoint.OUTPUT_MODE.AUTO_DELIVER", field(outputMode, "AUTO_DELIVER") == 2},
        {"ProductionPoint.DIRECT_SELL_PRICE_FACTOR", field(ProductionPoint, "DIRECT_SELL_PRICE_FACTOR")},
        {"ProductionPoint.getOutputDistributionMode", field(ProductionPoint, "getOutputDistributionMode")},
        {"ProductionPoint.setOutputDistributionMode", field(ProductionPoint, "setOutputDistributionMode")},
        {"ProductionPoint.toggleOutputDistributionMode", field(ProductionPoint, "toggleOutputDistributionMode")},
        {"ProductionPoint.updateProduction", field(ProductionPoint, "updateProduction")},
        {"ProductionPoint.palletSpawnRequestCallback", field(ProductionPoint, "palletSpawnRequestCallback")},
        {"ProductionPoint.setOwnerFarmId", field(ProductionPoint, "setOwnerFarmId")},
        {"ProductionPoint.saveToXMLFile", field(ProductionPoint, "saveToXMLFile")},
        {"ProductionPoint.writeStream", field(ProductionPoint, "writeStream")},
        {"ProductionChainManager.distributeGoods", field(ProductionChainManager, "distributeGoods")},
        {"InGameMenuProductionFrame.populateCellForItemInSection", field(InGameMenuProductionFrame, "populateCellForItemInSection")},
        {"InGameMenuProductionFrame.update", field(InGameMenuProductionFrame, "update")},
        {"InGameMenuProductionFrame.updateProductionLists", field(InGameMenuProductionFrame, "updateProductionLists")},
        {"PlaceableProductionPoint", PlaceableProductionPoint},
        {"AccessHandler.EVERYONE", field(AccessHandler, "EVERYONE") ~= nil},
        {"ProductionOverflow", ProductionOverflow}, {"POModeEvent", POModeEvent},
    }
    for _, entry in ipairs(required) do
        if not entry[2] then
            return entry[1]
        end
    end
    return nil
end

-- Engine class tables survive map changes. Refresh callbacks without stacking hooks;
-- when the Mod is not active in the loaded game, every hook passes straight through.
local function hookKey(method)
    return "po_" .. modName .. "_" .. method
end

local function installHook(class, method, prepend, callback)
    local key = hookKey(method .. (prepend and "_pre" or "_post"))
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

local function installOverwrite(class, method, callback)
    local key = hookKey(method)
    if class[key] == nil then
        class[method] = Utils.overwrittenFunction(class[method], function(self, superFunc, ...)
            if g_modIsLoaded[modName] then
                return class[key](self, superFunc, ...)
            end
            return superFunc(self, ...)
        end)
    end
    class[key] = callback
end

local missing = findMissingApi()
if missing ~= nil then
    Logging.warning("Production Overflow disabled: game function %s not found", missing)
    return
end

local PO = ProductionOverflow
installOverwrite(ProductionPoint, "setOutputDistributionMode", PO.setOutputDistributionMode)
installOverwrite(ProductionPoint, "toggleOutputDistributionMode", PO.toggleOutputDistributionMode)
installOverwrite(ProductionPoint, "updateProduction", PO.updateProduction)
installOverwrite(ProductionPoint, "palletSpawnRequestCallback", PO.palletSpawnRequestCallback)
installHook(ProductionPoint, "setOwnerFarmId", false, PO.onOwnerChanged)
installHook(ProductionPoint, "saveToXMLFile", true, PO.restoreExposed)
installHook(ProductionPoint, "writeStream", true, PO.restoreExposed)
installHook(ProductionChainManager, "distributeGoods", true, PO.restoreAll)
installHook(ProductionChainManager, "distributeGoods", false, PO.afterDistribution)
installHook(InGameMenuProductionFrame, "populateCellForItemInSection", false, PO.populateCellForItemInSection)
installHook(InGameMenuProductionFrame, "update", false, PO.updateFrame)

installHook(TypeManager, "validateTypes", true, function(manager)
    -- Mods receive a proxy manager; compare its type instead of table identity.
    if manager.typeName ~= "placeable" then return end
    local registered = g_placeableSpecializationManager:getSpecializationByName("productionOverflow")
    if registered == nil or registered.name ~= SPEC_NAME or ProductionOverflowPlaceable == nil then
        Logging.error("Production Overflow specialization was not registered as %s", SPEC_NAME)
        return
    end
    for name, entry in pairs(manager.types) do
        if ProductionOverflowPlaceable.prerequisitesPresent(entry.specializations)
            and entry.specializationsByName[registered.name] == nil then
            manager:addSpecialization(name, registered.name)
        end
    end
end)
