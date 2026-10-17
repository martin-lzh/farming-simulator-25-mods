AnimalProductDistribution = {}
local APD = AnimalProductDistribution

function APD.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PlaceableHusbandryMilk, specializations)
        or SpecializationUtil.hasSpecialization(PlaceableHusbandryPallets, specializations)
end

function APD.registerEventListeners(placeableType)
    for _, name in ipairs({"onLoad", "onDelete", "onReadStream", "onWriteStream", "onOwnerChanged", "onLoadFinished", "onPostFinalizePlacement", "onHourChanged"}) do
        SpecializationUtil.registerEventListener(placeableType, name, APD)
    end
end

function APD:onOwnerChanged()
    if self.apdState ~= nil then
        local owner = self:getOwnerFarmId()
        local changed = self.apdState.ready and self.apdState.ownerFarmId ~= owner
        self.apdState.ownerFarmId = owner
        if changed then
            self.apdState.modes = {}
            if self.isServer and self.updatePallets ~= nil then
                self:updatePallets()
            end
        end
    end
end

function APD:onLoadFinished()
    self.apdState.ownerFarmId = self:getOwnerFarmId()
end

function APD:onPostFinalizePlacement()
    self.apdState.ownerFarmId = self:getOwnerFarmId()
    self.apdState.ready = true
end

function APD:onHourChanged()
    APD.processHour(self)
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
    schema:register(XMLValueType.FLOAT, key .. ".product(?)#refundLiters", "Product awaiting return after a rejected transfer", 0)
end

function APD:onLoad()
    self.apdState = {modes = {}, refunds = {}, deleted = false, ready = false, processing = false, palletDepth = 0}
end

function APD:onDelete()
    if self.apdState ~= nil then
        self.apdState.deleted = true
    end
end

-- UI rows follow the native animal-dependent list. Keep the full supported list
-- for inventory, saved settings and streams, including products no longer active.
function APD.products(placeable, activeOnly)
    local products, seen = {}, {}
    local function collect(spec)
        if spec == nil then return end
        local active
        if activeOnly and spec.activeFillTypes ~= nil then
            active = {}
            for _, fillType in ipairs(spec.activeFillTypes) do active[fillType] = true end
        end
        for _, fillType in ipairs(spec.fillTypes or {}) do
            if not seen[fillType] and (active == nil or active[fillType]) then
                table.insert(products, fillType)
                seen[fillType] = true
            end
        end
    end
    local milk = placeable.spec_husbandryMilk
    if milk ~= nil and milk.hasMilkProduction then
        collect(milk)
    end
    collect(placeable.spec_husbandryPallets)
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
    -- Remove only this specialization's subtree, including every repeated product.
    xmlFile:removeProperty(key)
    local index = 0
    for _, fillType in ipairs(APD.products(self)) do
        local mode = APD.mode(self, fillType)
        local refund = self.apdState.refunds[fillType] or 0
        if mode ~= APDDistribution.KEEP or refund > 0 then
            local entry = string.format("%s.product(%d)", key, index)
            xmlFile:setValue(entry .. "#fillType", g_fillTypeManager:getFillTypeNameByIndex(fillType))
            xmlFile:setValue(entry .. "#mode", mode)
            xmlFile:setValue(entry .. "#refundLiters", refund)
            index = index + 1
        end
    end
end

function APD:loadFromXMLFile(xmlFile, key, reset)
    self.apdState.modes = {}
    self.apdState.refunds = {}
    if reset then
        return
    end
    for _, entry in xmlFile:iterator(key .. ".product") do
        local fillType = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getValue(entry .. "#fillType"))
        local mode = xmlFile:getValue(entry .. "#mode", APDDistribution.KEEP)
        if APD.supports(self, fillType) and APDDistribution.isMode(mode) then
            self.apdState.modes[fillType] = mode
            local refund = xmlFile:getValue(entry .. "#refundLiters", 0)
            if APDDistribution.isFinite(refund) and refund > 0 then
                self.apdState.refunds[fillType] = refund
            end
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
    self.apdState.ownerFarmId = self:getOwnerFarmId()
end

-- Keep native spawner bookkeeping and callbacks, hiding only managed pending stock.
-- Restore on exceptions too; an already requested pallet must not consume routed stock.
function APD.withStoredPalletsHidden(placeable, superFunc, ...)
    if placeable.apdState == nil or not placeable.isServer then
        return superFunc(placeable, ...)
    end
    local pending = placeable.spec_husbandryPallets.pendingLiters
    placeable.apdState.palletDepth = placeable.apdState.palletDepth + 1
    local hidden = {}
    for fillType, amount in pairs(pending) do
        if APD.mode(placeable, fillType) ~= APDDistribution.KEEP then
            hidden[fillType] = amount
            pending[fillType] = 0
        end
    end
    local ok, result = pcall(superFunc, placeable, ...)
    local resume = false
    for fillType, amount in pairs(hidden) do
        pending[fillType] = pending[fillType] + amount
        -- Ownership or mode can change inside a synchronous native callback.
        -- Its nested update saw zero stock; retry after the outer mask is gone.
        if APD.mode(placeable, fillType) == APDDistribution.KEEP and pending[fillType] > 5 then
            resume = true
        end
    end
    placeable.apdState.palletDepth = placeable.apdState.palletDepth - 1
    if not ok then
        error(result)
    end
    if resume and placeable.apdState.palletDepth == 0 then
        placeable:updatePallets()
    end
    return result
end

function APD:updatePallets(superFunc)
    return APD.withStoredPalletsHidden(self, superFunc)
end

function APD:getPalletCallback(superFunc, pallet, result, fillType)
    return APD.withStoredPalletsHidden(self, superFunc, pallet, result, fillType)
end

-- A Storage listener can throw after changing the level. Always observe the result.
function APD.writeLevel(get, set, value)
    local before = get()
    local ok, err = pcall(set, value)
    local after = get()
    if not ok then Logging.warning("Animal Product Distribution storage callback failed: %s", tostring(err)) end
    return after - before
end

function APD.changeMoney(farmId, amount, moneyType)
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then return 0 end
    local before = farm:getBalance()
    -- Farm publishes MONEY_CHANGED synchronously after changing its balance.
    -- Exclude subscriber effects (loans, repayments, even nested settlements)
    -- from this transaction, including when a subscriber throws after writing.
    local center = g_messageCenter
    local publish = center.publish
    local ownPublish = rawget(center, "publish")
    local listenerDelta, publishing = 0, false
    center.publish = function(messageCenter, messageType, ...)
        if messageCenter ~= center or messageType ~= MessageType.MONEY_CHANGED
            or select(1, ...) ~= farmId or publishing then
            return publish(messageCenter, messageType, ...)
        end
        local beforeListeners = farm:getBalance()
        publishing = true
        local ok, err = pcall(publish, messageCenter, messageType, ...)
        publishing = false
        listenerDelta = listenerDelta + farm:getBalance() - beforeListeners
        if not ok then error(err, 0) end
    end
    local ok, err = pcall(g_currentMission.addMoney, g_currentMission, amount, farmId, moneyType, true)
    center.publish = ownPublish
    local delta = farm:getBalance() - before - listenerDelta
    if not ok then Logging.warning("Animal Product Distribution money callback failed: %s", tostring(err)) end
    return delta
end

-- Refunds normally go straight back to native stock. If a third-party storage
-- refuses that write, retain the remainder in a separately persisted recovery buffer.
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
    local refunds = placeable.apdState.refunds
    return {
        available = function() return get() + (refunds[fillType] or 0) end,
        take = function(amount)
            local held = math.min(refunds[fillType] or 0, math.max(amount, 0))
            refunds[fillType] = (refunds[fillType] or 0) - held
            local before = get()
            local delta = APD.writeLevel(get, set, math.max(before - math.max(amount - held, 0), 0))
            return held + math.max(-delta, 0)
        end,
        put = function(amount)
            if amount > 0 then
                local restored = math.max(APD.writeLevel(get, set, get() + amount), 0)
                local retained = math.max(amount - restored, 0)
                refunds[fillType] = (refunds[fillType] or 0) + retained
                if retained > 0.000001 then
                    Logging.warning("Animal Product Distribution retained %.3f liters of %s for recovery; keep the mod enabled until restored",
                        retained, g_fillTypeManager:getFillTypeNameByIndex(fillType))
                end
            end
        end,
        restore = function()
            local held = refunds[fillType] or 0
            if held > 0 then
                local restored = math.max(APD.writeLevel(get, set, get() + held), 0)
                refunds[fillType] = math.max(held - restored, 0)
            end
        end
    }
end

function APD.targets(placeable, fillType)
    local result, seen = {}, {}
    local manager = g_currentMission.productionChainManager
    local farmId = placeable:getOwnerFarmId()
    if manager == nil then return result end
    for _, point in ipairs(manager:getProductionPointsForFarmId(farmId)) do
        if point:getOwnerFarmId() == farmId and point.owningPlaceable ~= placeable
            and point.owningPlaceable ~= nil and point.storage ~= nil and point.inputFillTypeIds[fillType]
            and not seen[point.storage] and (placeable.spec_husbandry == nil or point.storage ~= placeable.spec_husbandry.storage) then
            local storage = point.storage
            seen[storage] = true
            local target = {point = point}
            target.free = function() return storage:getFreeCapacity(fillType, true) end
            target.add = function(amount)
                local get = function() return storage:getFillLevel(fillType) end
                local set = function(value) storage:setFillLevel(value, fillType) end
                return math.max(APD.writeLevel(get, set, get() + math.min(amount, target.free())), 0)
            end
            target.remove = function(amount)
                local get = function() return storage:getFillLevel(fillType) end
                local set = function(value) storage:setFillLevel(value, fillType) end
                return math.max(-APD.writeLevel(get, set, math.max(get() - amount, 0)), 0)
            end
            table.insert(result, target)
        end
    end
    return result
end

function APD:processHour()
    local state = self.apdState
    if not self.isServer or state == nil or state.deleted or not state.ready
        or state.processing or state.palletDepth > 0 or self:getOwnerFarmId() == FarmManager.SPECTATOR_FARM_ID
        or g_farmManager:getFarmById(self:getOwnerFarmId()) == nil then
        return
    end
    state.processing = true
    local ok, err = pcall(APD.processOutputs, self)
    state.processing = false
    if not ok then Logging.warning("Animal Product Distribution settlement failed: %s", tostring(err)) end
end

function APD:processOutputs()
    local mission = g_currentMission
    local farmId = self:getOwnerFarmId()
    for _, fillType in ipairs(APD.products(self)) do
        local mode = APD.mode(self, fillType)
        if mode == APDDistribution.KEEP and (self.apdState.refunds[fillType] or 0) > 0 then
            local source = APD.source(self, fillType)
            if source ~= nil then source.restore() end
        end
        if mode ~= APDDistribution.KEEP then
            local source = APD.source(self, fillType)
            if source ~= nil then
                if mode == APDDistribution.SELL then
                    APDDistribution.sell(source,
                        mission.economyManager:getPricePerLiter(fillType) * ProductionPoint.DIRECT_SELL_PRICE_FACTOR,
                        function(revenue) return APD.changeMoney(farmId, revenue, MoneyType.SOLD_PRODUCTS) end)
                elseif mode == APDDistribution.DISTRIBUTE then
                    APDDistribution.distribute(source, APD.targets(self, fillType), function(target, amount)
                        local distance = calcDistanceFrom(self.rootNode, target.point.owningPlaceable.rootNode)
                        local rate = distance * ProductionPoint.DIRECT_DELIVERY_PRICE
                        if rate <= 0 then return amount end
                        local paid = -APD.changeMoney(farmId, -amount * rate, MoneyType.PRODUCTION_COSTS)
                        return paid / rate
                    end)
                end
            end
        end
    end
end
