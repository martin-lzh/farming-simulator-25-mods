AnimalProductDistribution = {}
local APD = AnimalProductDistribution

function APD.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PlaceableHusbandryMilk, specializations)
        or SpecializationUtil.hasSpecialization(PlaceableHusbandryPallets, specializations)
end

function APD.registerEventListeners(placeableType)
    for _, name in ipairs({"onLoad", "onDelete", "onReadStream", "onWriteStream", "onOwnerChanged"}) do
        SpecializationUtil.registerEventListener(placeableType, name, APD)
    end
end

function APD:onOwnerChanged()
    if self.apdState ~= nil then
        self.apdState.modes = {}
    end
end

function APD.registerOverwrittenFunctions(placeableType)
    if SpecializationUtil.hasSpecialization(PlaceableHusbandryPallets, placeableType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(placeableType, "updatePallets", APD.updatePallets)
        SpecializationUtil.registerOverwrittenFunction(placeableType, "getPalletCallback", APD.getPalletCallback)
    end
end

function APD.registerSavegameXMLPaths(schema, key)
    schema:register(XMLValueType.STRING, key .. ".product(?)#fillType", "Animal output fill type")
    schema:register(XMLValueType.INT, key .. ".product(?)#mode", "0 store, 1 sell, 2 distribute", 0)
end

function APD:onLoad()
    self.apdState = {modes = {}, deleted = false}
    if self.isServer then
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, APD.processHour, self)
    end
end

function APD:onDelete()
    if self.apdState ~= nil then
        self.apdState.deleted = true
    end
    if self.isServer then
        g_messageCenter:unsubscribe(MessageType.HOUR_CHANGED, self, APD.processHour)
    end
end

function APD.products(placeable)
    local products, seen = {}, {}
    local milk = placeable.spec_husbandryMilk
    if milk ~= nil and milk.hasMilkProduction then
        for _, fillType in ipairs(milk.fillTypes or {}) do
            seen[fillType] = true
            table.insert(products, fillType)
        end
    end
    local pallets = placeable.spec_husbandryPallets
    for _, fillType in ipairs(pallets ~= nil and pallets.fillTypes or {}) do
        if not seen[fillType] then
            table.insert(products, fillType)
            seen[fillType] = true
        end
    end
    table.sort(products)
    return products
end

function APD.supports(placeable, fillType)
    if placeable == nil or placeable.apdState == nil or placeable.apdState.deleted then
        return false
    end
    for _, candidate in ipairs(APD.products(placeable)) do
        if candidate == fillType then
            return true
        end
    end
    return false
end

function APD.mode(placeable, fillType)
    return placeable.apdState ~= nil and placeable.apdState.modes[fillType] or APDDistribution.KEEP
end

function APD.canManage(placeable, connection)
    if placeable == nil or placeable.apdState == nil or placeable.apdState.deleted then
        return false
    end
    local farmId = placeable:getOwnerFarmId()
    return farmId ~= FarmManager.SPECTATOR_FARM_ID
        and g_currentMission:getFarmId(connection) == farmId
        and g_currentMission:getHasPlayerPermission("tradeAnimals", connection, farmId)
end

function APD.applyMode(placeable, fillType, mode)
    if not APDDistribution.isMode(mode) or not APD.supports(placeable, fillType) then
        return false
    end
    placeable.apdState.modes[fillType] = mode
    if placeable.isServer and mode == APDDistribution.KEEP and placeable.updatePallets ~= nil then
        placeable:updatePallets()
    end
    return true
end

function APD.requestMode(placeable, fillType, mode)
    if not APD.canManage(placeable, nil) or not APD.supports(placeable, fillType)
        or not APDDistribution.isMode(mode) then
        return
    end
    local event = APDModeEvent.new(placeable, fillType, mode)
    if placeable.isServer then
        if APD.applyMode(placeable, fillType, mode) then
            g_server:broadcastEvent(event, nil, nil, placeable)
        end
    else
        g_client:getServerConnection():sendEvent(event)
    end
end

function APD:saveToXMLFile(xmlFile, key)
    local index = 0
    for _, fillType in ipairs(APD.products(self)) do
        local mode = APD.mode(self, fillType)
        if mode ~= APDDistribution.KEEP then
            local entry = string.format("%s.product(%d)", key, index)
            xmlFile:setValue(entry .. "#fillType", g_fillTypeManager:getFillTypeNameByIndex(fillType))
            xmlFile:setValue(entry .. "#mode", mode)
            index = index + 1
        end
    end
end

function APD:loadFromXMLFile(xmlFile, key, reset)
    if reset then
        return
    end
    for _, entry in xmlFile:iterator(key .. ".product") do
        local fillType = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getValue(entry .. "#fillType"))
        local mode = xmlFile:getValue(entry .. "#mode", APDDistribution.KEEP)
        if APD.supports(self, fillType) and APDDistribution.isMode(mode) then
            self.apdState.modes[fillType] = mode
        end
    end
end

function APD:onWriteStream(streamId, connection)
    local products = APD.products(self)
    streamWriteUInt16(streamId, #products)
    for _, fillType in ipairs(products) do
        streamWriteUIntN(streamId, fillType, FillTypeManager.SEND_NUM_BITS)
        streamWriteUIntN(streamId, APD.mode(self, fillType), 2)
    end
end

function APD:onReadStream(streamId, connection)
    local count = streamReadUInt16(streamId)
    for _ = 1, count do
        local fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        local mode = streamReadUIntN(streamId, 2)
        if APD.supports(self, fillType) and APDDistribution.isMode(mode) then
            self.apdState.modes[fillType] = mode
        end
    end
end

-- Keep native spawner bookkeeping and callbacks, hiding only managed pending stock.
-- Restore on exceptions too; an already requested pallet must not consume routed stock.
function APD.withStoredPalletsHidden(placeable, superFunc, ...)
    if placeable.apdState == nil or not placeable.isServer then
        return superFunc(placeable, ...)
    end
    local pending = placeable.spec_husbandryPallets.pendingLiters
    local hidden = {}
    for fillType, amount in pairs(pending) do
        if APD.mode(placeable, fillType) ~= APDDistribution.KEEP then
            hidden[fillType] = amount
            pending[fillType] = 0
        end
    end
    local ok, result = pcall(superFunc, placeable, ...)
    for fillType, amount in pairs(hidden) do
        pending[fillType] = pending[fillType] + amount
    end
    if not ok then
        error(result)
    end
    return result
end

function APD:updatePallets(superFunc)
    return APD.withStoredPalletsHidden(self, superFunc)
end

function APD:getPalletCallback(superFunc, pallet, result, fillType)
    return APD.withStoredPalletsHidden(self, superFunc, pallet, result, fillType)
end

-- Source operations always measure real deltas so clamping cannot create product.
function APD.source(placeable, fillType)
    local pallets = placeable.spec_husbandryPallets
    local get, set
    if pallets ~= nil and pallets.pendingLiters[fillType] ~= nil then
        get = function() return pallets.pendingLiters[fillType] end
        set = function(value) pallets.pendingLiters[fillType] = value end
    else
        local storage = placeable.spec_husbandry ~= nil and placeable.spec_husbandry.storage
        if storage == nil then
            return nil
        end
        get = function() return storage:getFillLevel(fillType) end
        set = function(value) storage:setFillLevel(value, fillType) end
    end
    return {
        available = get,
        take = function(amount)
            local before = get()
            set(math.max(before - math.max(amount, 0), 0))
            return math.max(before - get(), 0)
        end,
        put = function(amount)
            if amount > 0 then set(get() + amount) end
        end
    }
end

function APD.targets(placeable, fillType)
    local result = {}
    local manager = g_currentMission.productionChainManager
    local farmId = placeable:getOwnerFarmId()
    if manager == nil then return result end
    for _, point in ipairs(manager:getProductionPointsForFarmId(farmId)) do
        if point:getOwnerFarmId() == farmId and point.owningPlaceable ~= placeable
            and point.storage ~= nil and point.inputFillTypeIds[fillType] then
            local storage = point.storage
            local target = {point = point}
            target.free = function() return storage:getFreeCapacity(fillType, true) end
            target.add = function(amount)
                local before = storage:getFillLevel(fillType)
                storage:setFillLevel(before + math.min(amount, target.free()), fillType)
                return math.max(storage:getFillLevel(fillType) - before, 0)
            end
            table.insert(result, target)
        end
    end
    return result
end

function APD:processHour()
    if not self.isServer or self.apdState.deleted or self:getOwnerFarmId() == FarmManager.SPECTATOR_FARM_ID then
        return
    end
    local mission = g_currentMission
    local farmId = self:getOwnerFarmId()
    for _, fillType in ipairs(APD.products(self)) do
        local mode = APD.mode(self, fillType)
        if mode ~= APDDistribution.KEEP then
            local source = APD.source(self, fillType)
            if source ~= nil then
                if mode == APDDistribution.SELL then
                    APDDistribution.sell(source,
                        mission.economyManager:getPricePerLiter(fillType) * ProductionPoint.DIRECT_SELL_PRICE_FACTOR,
                        function(revenue) mission:addMoney(revenue, farmId, MoneyType.SOLD_PRODUCTS, true) end)
                elseif mode == APDDistribution.DISTRIBUTE then
                    APDDistribution.distribute(source, APD.targets(self, fillType), function(target, amount)
                        local distance = calcDistanceFrom(self.rootNode, target.point.owningPlaceable.rootNode)
                        mission:addMoney(-amount * distance * ProductionPoint.DIRECT_DELIVERY_PRICE,
                            farmId, MoneyType.PRODUCTION_COSTS, true)
                    end)
                end
            end
        end
    end
end
