-- Contract doubles, not copies of game implementations. Each double keeps only the
-- native behaviour this Mod relies on (see DEVELOPMENT.md for the verified sources).
AccessHandler = {EVERYONE = 0}
FarmManager = {SPECTATOR_FARM_ID = 0}
FillTypeManager = {SEND_NUM_BITS = 10}
MoneyType = {SOLD_PRODUCTS = {id = 1}, PRODUCTION_COSTS = {id = 2}}
XMLValueType = {STRING = "string", FLOAT = "float", INT = "int"}
g_currentModName = "FS25_ProductionOverflow"
g_currentModDirectory = "production-overflow-mod/"
g_modIsLoaded = {[g_currentModName] = true}
g_time = 100000

function table.hasElement(list, value)
    for _, element in pairs(list) do
        if element == value then return true end
    end
    return false
end

g_currentMission = {
    farmId = 1, allowed = true, money = 0, bookings = {},
    getFarmId = function(self, connection)
        if connection ~= nil then return connection.farmId end
        return self.farmId
    end,
    getHasPlayerPermission = function(self, permission, connection, farmId)
        assert(permission == "manageProductions", permission)
        if connection ~= nil then return connection.allowed end
        return self.allowed
    end,
    addMoney = function(self, amount, farmId, moneyType, addChange)
        assert(addChange == true and farmId ~= 0)
        self.money = self.money + amount
        table.insert(self.bookings, {amount = amount, farmId = farmId, moneyType = moneyType})
    end,
    economyManager = {getPricePerLiter = function(_, fillType) return fillType == 9 and 3 or 2 end}
}
g_fillTypeManager = {
    getFillTypeNameByIndex = function(_, i) return "TYPE_" .. i end,
    getFillTypeIndexByName = function(_, name) return name and tonumber(name:match("^TYPE_(%d+)$")) end
}
g_i18n = {getText = function(_, key, env)
    if env ~= nil then
        assert(env == g_currentModName, "Mod text read without the Mod environment")
        return "mod:" .. key
    end
    return key
end}
Logging = {
    warnings = {},
    error = function(message, ...) error(string.format(message, ...)) end,
    warning = function(message, ...) table.insert(Logging.warnings, string.format(message, ...)) end
}

function Class(class, base)
    if base ~= nil then setmetatable(class, {__index = base}) end
    class.superClass = function() return base end
    return {__index = class}
end
Event = {new = function(mt) return setmetatable({}, mt) end}
function InitEventClass() end
g_server = {sent = {}, broadcastEvent = function(self, event, sendLocal, ignoreConnection)
    table.insert(self.sent, event)
end}

-- Streams are plain Lua lists in the tests.
local function push(s, v) table.insert(s, v) end
local function pop(s) return table.remove(s, 1) end
streamWriteUInt8, streamReadUInt8 = push, pop
streamWriteUIntN = function(s, v, bits)
    assert(v >= 0 and v < 2 ^ bits, "value does not fit the stream bits")
    push(s, v)
end
streamReadUIntN = function(s, bits) return pop(s) end
NetworkUtil = {writeNodeObject = push, readNodeObject = pop}

-- Same semantics as GS utils/Utils.lua.
Utils = {
    prependedFunction = function(old, new) return function(...) new(...); old(...) end end,
    appendedFunction = function(old, new) return function(...) old(...); new(...) end end,
    overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end
}

PlaceableProductionPoint = {}
SpecializationUtil = {
    hasSpecialization = function(needle, list)
        for _, value in ipairs(list) do if value == needle then return true end end
        return false
    end,
    registerEventListener = function() end
}
TypeManager = {validateTypes = function() end}
g_placeableSpecializationManager = {getSpecializationByName = function(_, name)
    if name == "productionOverflow" then
        return {name = "FS25_ProductionOverflow.productionOverflow"}
    end
end}

-- ProductionPoint double: output modes, production with the NO_OUTPUT_SPACE rule,
-- the pallet loop that skips DIRECT_SELL and AUTO_DELIVER outputs, and the spawn callback.
ProductionPoint = {
    DIRECT_SELL_PRICE_FACTOR = 0.9, DIRECT_DELIVERY_PRICE = 0.000035, NO_PALLET_SPACE_COOLDOWN = 15000,
    OUTPUT_MODE = {KEEP = 0, DIRECT_SELL = 1, AUTO_DELIVER = 2}, OUTPUT_MODE_NUM_BITS = 2
}
g_nativeModeEvents = {}
function ProductionPoint:getOutputDistributionMode(fillType)
    if self.outputFillTypeIdsDirectSell[fillType] ~= nil then return ProductionPoint.OUTPUT_MODE.DIRECT_SELL end
    if self.outputFillTypeIdsAutoDeliver[fillType] ~= nil then return ProductionPoint.OUTPUT_MODE.AUTO_DELIVER end
    return ProductionPoint.OUTPUT_MODE.KEEP
end
function ProductionPoint:setOutputDistributionMode(fillType, mode, noEventSend)
    if self.outputFillTypeIds[fillType] == nil then return end
    mode = tonumber(mode)
    self.outputFillTypeIdsDirectSell[fillType] = nil
    self.outputFillTypeIdsAutoDeliver[fillType] = nil
    if mode == ProductionPoint.OUTPUT_MODE.DIRECT_SELL then
        self.outputFillTypeIdsDirectSell[fillType] = true
    elseif mode == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER then
        self.outputFillTypeIdsAutoDeliver[fillType] = true
    elseif mode ~= ProductionPoint.OUTPUT_MODE.KEEP then
        error("Undefined mode " .. tostring(mode))
    end
    if not noEventSend then
        table.insert(g_nativeModeEvents, {point = self, fillType = fillType, mode = mode})
    end
end
function ProductionPoint:toggleOutputDistributionMode(fillType)
    if self.outputFillTypeIds[fillType] ~= nil then
        local current = self:getOutputDistributionMode(fillType)
        if table.hasElement(ProductionPoint.OUTPUT_MODE, current + 1) then
            self:setOutputDistributionMode(fillType, current + 1)
            return
        end
        self:setOutputDistributionMode(fillType, 0)
    end
end
function ProductionPoint:getOwnerFarmId() return self.ownerFarmId end
function ProductionPoint:setOwnerFarmId(farmId)
    self.ownerFarmId = farmId
    self.isOwned = farmId ~= AccessHandler.EVERYONE
end
function ProductionPoint:updateProduction()
    self.updates = (self.updates or 0) + 1
    if self.failInUpdate then error("native update failed") end
    local enoughSpace = true
    for fillType, liters in pairs(self.produce or {}) do
        if self.storage:getFreeCapacity(fillType) < liters then enoughSpace = false end
    end
    if enoughSpace and self.isOwned then
        for fillType, liters in pairs(self.produce or {}) do
            self.storage:setFillLevel(self.storage:getFillLevel(fillType) + liters, fillType)
        end
    end
    if self.isServer and self.isOwned and g_time > self.palletSpawnCooldown and not self.waitingForPalletToSpawn then
        for _, fillType in ipairs(self.outputFillTypeIdsArray) do
            local pallet = self.outputFillTypeIdsToPallets[fillType]
            if pallet ~= nil and self.outputFillTypeIdsDirectSell[fillType] == nil
                and self.outputFillTypeIdsAutoDeliver[fillType] == nil
                and self.storage:getFillLevel(fillType) >= pallet.capacity then
                self.waitingForPalletToSpawn = true
                self.palletSpawner:spawnPallet(self:getOwnerFarmId(), fillType, self.palletSpawnRequestCallback, self)
                break
            end
        end
    end
end
function ProductionPoint:palletSpawnRequestCallback(pallet, status, fillType)
    self.waitingForPalletToSpawn = false
    if pallet == nil then
        self.palletSpawnCooldown = g_time + ProductionPoint.NO_PALLET_SPACE_COOLDOWN
        return
    end
    local delta = math.min(pallet.capacity - pallet.fill, self.storage:getFillLevel(fillType))
    if delta > 0 then
        pallet.fill = pallet.fill + delta
        self.storage:setFillLevel(self.storage:getFillLevel(fillType) - delta, fillType)
    end
end
function ProductionPoint:directlySellOutputs()
    for fillType in pairs(self.outputFillTypeIdsDirectSell) do
        local amount = self.storage:getFillLevel(fillType)
        if amount > 0 then
            g_currentMission:addMoney(ProductionPoint.DIRECT_SELL_PRICE_FACTOR * amount
                * g_currentMission.economyManager:getPricePerLiter(fillType), self.ownerFarmId, MoneyType.SOLD_PRODUCTS, true)
            self.storage:setFillLevel(0, fillType)
        end
    end
end
-- Native save and join stream only know the DIRECT_SELL and AUTO_DELIVER sets.
local function sortedKeys(set)
    local keys = {}
    for key in pairs(set) do table.insert(keys, key) end
    table.sort(keys)
    return keys
end
function ProductionPoint:saveToXMLFile(xmlFile, key)
    for index, fillType in ipairs(sortedKeys(self.outputFillTypeIdsAutoDeliver)) do
        xmlFile:setValue(string.format("%s.autoDeliverFillType(%d)", key, index - 1), g_fillTypeManager:getFillTypeNameByIndex(fillType))
    end
    for index, fillType in ipairs(sortedKeys(self.outputFillTypeIdsDirectSell)) do
        xmlFile:setValue(string.format("%s.directSellFillType(%d)", key, index - 1), g_fillTypeManager:getFillTypeNameByIndex(fillType))
    end
end
function ProductionPoint:loadFromXMLFile(xmlFile, key)
    for _, set in ipairs({{"directSellFillType", 1}, {"autoDeliverFillType", 2}}) do
        local index = 0
        while xmlFile.values[string.format("%s.%s(%d)", key, set[1], index)] ~= nil do
            local name = xmlFile.values[string.format("%s.%s(%d)", key, set[1], index)]
            self:setOutputDistributionMode(g_fillTypeManager:getFillTypeIndexByName(name), set[2])
            index = index + 1
        end
    end
end
function ProductionPoint:writeStream(streamId, connection)
    for _, set in ipairs({self.outputFillTypeIdsDirectSell, self.outputFillTypeIdsAutoDeliver}) do
        local keys = sortedKeys(set)
        streamWriteUInt8(streamId, #keys)
        for _, fillType in ipairs(keys) do streamWriteUIntN(streamId, fillType, FillTypeManager.SEND_NUM_BITS) end
    end
end
function ProductionPoint:readStream(streamId, connection)
    for _, mode in ipairs({ProductionPoint.OUTPUT_MODE.DIRECT_SELL, ProductionPoint.OUTPUT_MODE.AUTO_DELIVER}) do
        for _ = 1, streamReadUInt8(streamId) do
            self:setOutputDistributionMode(streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS), mode, true)
        end
    end
end

-- Native hourly distribution: same farm, input accepted, split by free capacity, fee by distance.
ProductionChainManager = {}
function ProductionChainManager:distributeGoods()
    if not self.isServer then return end
    for _, source in ipairs(self.productionPoints) do
        for fillType in pairs(source.outputFillTypeIdsAutoDeliver) do
            local amount = source.storage:getFillLevel(fillType)
            if amount > 0 then
                local targets, total = {}, 0
                for _, point in ipairs(self.productionPoints) do
                    if point ~= source and point.ownerFarmId == source.ownerFarmId and point.inputFillTypeIds[fillType] then
                        table.insert(targets, point)
                        total = total + point.storage:getFreeCapacity(fillType)
                    end
                end
                if total > 0 then
                    for _, point in ipairs(targets) do
                        local free = point.storage:getFreeCapacity(fillType)
                        if free > 0 then
                            local transfer = math.min(free, amount * free / total)
                            g_currentMission:addMoney(-transfer * 1000 * ProductionPoint.DIRECT_DELIVERY_PRICE,
                                point.ownerFarmId, MoneyType.PRODUCTION_COSTS, true)
                            point.storage:setFillLevel(point.storage:getFillLevel(fillType) + transfer, fillType)
                            source.storage:setFillLevel(source.storage:getFillLevel(fillType) - transfer, fillType)
                        end
                    end
                end
            end
        end
    end
end

-- Production menu double: the products list shows the native mode text.
InGameMenuProductionFrame = {}
function InGameMenuProductionFrame:getSelectedProduction()
    return self.selectedProduction, self.selectedProductionPoint
end
function InGameMenuProductionFrame:populateCellForItemInSection(list, section, index, cell)
    if list == self.productsList then
        local _, point = self:getSelectedProduction()
        local mode = point:getOutputDistributionMode(point.sortedProductions[index].primaryProductFillType)
        local text = "ui_production_output_storing"
        if mode == ProductionPoint.OUTPUT_MODE.DIRECT_SELL then
            text = "ui_production_output_selling"
        elseif mode == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER then
            text = "ui_production_output_distributing"
        end
        cell:getAttribute("activity"):setText(text)
    end
end
function InGameMenuProductionFrame:onButtonToggleOutputMode()
    if g_currentMission:getHasPlayerPermission("manageProductions") then
        local production, point = self:getSelectedProduction()
        point:toggleOutputDistributionMode(production.primaryProductFillType)
    end
end
function InGameMenuProductionFrame:update(dt) end
function InGameMenuProductionFrame:updateProductionLists() self.refreshes = (self.refreshes or 0) + 1 end

function mockStorage(levels, capacity)
    return {
        levels = levels, capacity = capacity,
        getFillLevel = function(self, fillType) return self.levels[fillType] or 0 end,
        getFreeCapacity = function(self, fillType) return self.capacity - (self.levels[fillType] or 0) end,
        setFillLevel = function(self, value, fillType) self.levels[fillType] = math.max(0, math.min(value, self.capacity)) end
    }
end

function mockSpawner()
    return {
        requests = {}, pallets = {}, sync = false,
        spawnPallet = function(self, farmId, fillType, callback, target)
            table.insert(self.requests, {fillType = fillType, callback = callback, target = target})
            if self.sync then self:finish() end
        end,
        -- Completes the oldest request, like the asynchronous native spawner.
        finish = function(self, noSpace)
            local request = table.remove(self.requests, 1)
            if request == nil then return nil end
            local pallet
            if not noSpace then
                pallet = {fillType = request.fillType, fill = 0,
                    capacity = request.target.outputFillTypeIdsToPallets[request.fillType].capacity}
                table.insert(self.pallets, pallet)
            end
            request.callback(request.target, pallet, pallet and 1 or 2, request.fillType)
            return pallet
        end
    }
end

-- A factory with three outputs: 7 (pallets of 100 L), 8 (pallets of 50 L), 9 (liquid, no pallet).
function mockPoint(options)
    options = options or {}
    local point = setmetatable({}, {__index = ProductionPoint})
    point.isServer = options.isServer ~= false
    point.ownerFarmId = options.farmId or 1
    point.isOwned = point.ownerFarmId ~= AccessHandler.EVERYONE
    point.outputFillTypeIds = {[7] = true, [8] = true, [9] = true}
    point.outputFillTypeIdsArray = {7, 8, 9}
    point.outputFillTypeIdsDirectSell, point.outputFillTypeIdsAutoDeliver = {}, {}
    point.outputFillTypeIdsToPallets = {[7] = {capacity = 100}, [8] = {capacity = 50}}
    point.palletSpawner = mockSpawner()
    point.storage = mockStorage({}, options.capacity or 1000)
    point.inputFillTypeIds = options.inputs or {}
    point.palletSpawnCooldown, point.waitingForPalletToSpawn = 0, false
    point.sortedProductions = {{primaryProductFillType = 7}, {primaryProductFillType = 8}, {primaryProductFillType = 9}}
    point.owningPlaceable = {spec_productionPoint = {productionPoint = point}}
    if options.withMod ~= false then
        ProductionOverflowPlaceable.onLoad(point.owningPlaceable)
        if options.placed ~= false then
            ProductionOverflowPlaceable.onPostFinalizePlacement(point.owningPlaceable)
        end
    end
    return point
end

function mockXML()
    return {
        values = {},
        setValue = function(self, key, value) self.values[key] = value end,
        getValue = function(self, key, default)
            local value = self.values[key]
            if value == nil then return default end
            return value
        end,
        iterator = function(self, key)
            local index = -1
            return function()
                index = index + 1
                local entry = key .. "(" .. index .. ")"
                if self.values[entry .. "#fillType"] ~= nil or self.values[entry .. "#mode"] ~= nil then
                    return index, entry
                end
            end
        end
    }
end
