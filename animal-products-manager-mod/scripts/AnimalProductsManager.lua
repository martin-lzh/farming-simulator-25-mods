AnimalProductsManager = {}
local APM = AnimalProductsManager

function APM.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PlaceableHusbandryMilk, specializations)
        or SpecializationUtil.hasSpecialization(PlaceableHusbandryPallets, specializations)
end

function APM.registerEventListeners(placeableType)
    for _, name in ipairs({"onLoad", "onDelete", "onReadStream", "onWriteStream", "onOwnerChanged", "onLoadFinished", "onPostFinalizePlacement", "onHourChanged"}) do
        SpecializationUtil.registerEventListener(placeableType, name, APM)
    end
end

function APM:onOwnerChanged()
    if self.apmState ~= nil then
        local owner = self:getOwnerFarmId()
        local changed = self.apmState.ready and self.apmState.ownerFarmId ~= owner
        self.apmState.ownerFarmId = owner
        if changed then
            self.apmState.modes = {}
            self.apmState.released = {}
            if self.isServer and self.updatePallets ~= nil then
                self:updatePallets()
            end
        end
    end
end

function APM:onLoadFinished()
    self.apmState.ownerFarmId = self:getOwnerFarmId()
end

function APM:onPostFinalizePlacement()
    self.apmState.ownerFarmId = self:getOwnerFarmId()
    self.apmState.ready = true
end

function APM:onHourChanged()
    APM.processHour(self)
end

function APM.registerOverwrittenFunctions(placeableType)
    if SpecializationUtil.hasSpecialization(PlaceableHusbandryPallets, placeableType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(placeableType, "updatePallets", APM.updatePallets)
        SpecializationUtil.registerOverwrittenFunction(placeableType, "getPalletCallback", APM.getPalletCallback)
    end
end

function APM.registerSavegameXMLPaths(schema, key)
    schema:register(XMLValueType.STRING, key .. ".product(?)#fillType", "Animal output fill type")
    schema:register(XMLValueType.INT, key .. ".product(?)#mode", "0 store, 1 sell, 2 distribute and store the rest, 3 distribute and sell the rest", 0)
    schema:register(XMLValueType.FLOAT, key .. ".product(?)#refundLiters", "Product awaiting return after a rejected transfer", 0)
    schema:register(XMLValueType.FLOAT, key .. ".product(?)#releasedLiters", "Pallet output left after the last hourly distribution, still to become pallets", 0)
end

function APM:onLoad()
    -- released: pallet output left over after an hourly distribution in mode 2,
    -- which the native spawner may turn into pallets. Server only.
    self.apmState = {modes = {}, refunds = {}, hidden = {}, released = {}, deleted = false, ready = false,
        processing = false, palletDepth = 0}
end

function APM:onDelete()
    if self.apmState ~= nil then
        self.apmState.deleted = true
    end
end

-- UI rows follow the native animal-dependent list. Keep the full supported list
-- for inventory, saved settings and streams, including products no longer active.
function APM.products(placeable, activeOnly)
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

function APM.supports(placeable, fillType)
    if placeable == nil or placeable.apmState == nil or placeable.apmState.deleted then
        return false
    end
    for _, candidate in ipairs(APM.products(placeable)) do
        if candidate == fillType then
            return true
        end
    end
    return false
end

function APM.mode(placeable, fillType)
    return placeable.apmState ~= nil and placeable.apmState.modes[fillType] or APMDistribution.KEEP
end

function APM.canManage(placeable, connection)
    if placeable == nil or placeable.apmState == nil or placeable.apmState.deleted then
        return false
    end
    local farmId = placeable:getOwnerFarmId()
    return farmId ~= FarmManager.SPECTATOR_FARM_ID
        and g_currentMission:getFarmId(connection) == farmId
        and g_currentMission:getHasPlayerPermission("tradeAnimals", connection, farmId)
end

function APM.applyMode(placeable, fillType, mode)
    if not APMDistribution.isMode(mode) or not APM.supports(placeable, fillType) then
        return false
    end
    -- Released output belongs to one hourly result of mode 2. Any other mode
    -- handles all pending output itself; a new mode 2 waits for its own hour.
    if APM.mode(placeable, fillType) ~= mode then
        placeable.apmState.released[fillType] = nil
    end
    placeable.apmState.modes[fillType] = mode
    if placeable.isServer and mode == APMDistribution.KEEP and placeable.updatePallets ~= nil then
        placeable:updatePallets()
    end
    return true
end

function APM.requestMode(placeable, fillType, mode)
    if not APM.canManage(placeable, nil) or not APM.supports(placeable, fillType)
        or not APMDistribution.isMode(mode) then
        return
    end
    local event = APMModeEvent.new(placeable, fillType, mode)
    if placeable.isServer then
        if APM.applyMode(placeable, fillType, mode) then
            g_server:broadcastEvent(event, nil, nil, placeable)
        end
    else
        g_client:getServerConnection():sendEvent(event)
    end
end

function APM:saveToXMLFile(xmlFile, key)
    -- Native pending stock may already be saved; keep masked stock in the refund buffer.
    APM.recoverAbortedCalls(self, true)
    -- Remove only this specialization's subtree, including every repeated product.
    xmlFile:removeProperty(key)
    local index = 0
    for _, fillType in ipairs(APM.products(self)) do
        local mode = APM.mode(self, fillType)
        local refund = self.apmState.refunds[fillType] or 0
        if mode ~= APMDistribution.KEEP or refund > 0 then
            local entry = string.format("%s.product(%d)", key, index)
            xmlFile:setValue(entry .. "#fillType", g_fillTypeManager:getFillTypeNameByIndex(fillType))
            xmlFile:setValue(entry .. "#mode", mode)
            xmlFile:setValue(entry .. "#refundLiters", refund)
            local released = APM.released(self, fillType)
            if released > 0 then
                xmlFile:setValue(entry .. "#releasedLiters", released)
            end
            index = index + 1
        end
    end
end

function APM:loadFromXMLFile(xmlFile, key, reset)
    self.apmState.modes = {}
    self.apmState.refunds = {}
    self.apmState.released = {}
    if reset then
        return
    end
    for _, entry in xmlFile:iterator(key .. ".product") do
        local fillType = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getValue(entry .. "#fillType"))
        local mode = xmlFile:getValue(entry .. "#mode", APMDistribution.KEEP)
        if APM.supports(self, fillType) and APMDistribution.isMode(mode) then
            self.apmState.modes[fillType] = mode
            local refund = xmlFile:getValue(entry .. "#refundLiters", 0)
            if APMDistribution.isFinite(refund) and refund > 0 then
                self.apmState.refunds[fillType] = refund
            end
            -- Native pending liters are saved separately and still contain this
            -- amount; it only limits what may become pallets.
            local released = xmlFile:getValue(entry .. "#releasedLiters", 0)
            if mode == APMDistribution.DISTRIBUTE_STORE and APMDistribution.isFinite(released) and released > 0 then
                self.apmState.released[fillType] = released
            end
        end
    end
end

function APM:onWriteStream(streamId, connection)
    local products = APM.products(self)
    streamWriteUInt16(streamId, #products)
    for _, fillType in ipairs(products) do
        streamWriteUIntN(streamId, fillType, FillTypeManager.SEND_NUM_BITS)
        streamWriteUIntN(streamId, APM.mode(self, fillType), 2)
    end
end

function APM:onReadStream(streamId, connection)
    local count = streamReadUInt16(streamId)
    for _ = 1, count do
        local fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        local mode = streamReadUIntN(streamId, 2)
        if APM.supports(self, fillType) and APMDistribution.isMode(mode) then
            self.apmState.modes[fillType] = mode
        end
    end
    self.apmState.ownerFarmId = self:getOwnerFarmId()
end

-- Errors raised by game or Mod code are not caught here, so they reach the log.
-- An error unwinds past our cleanup; the next call in a later frame finishes it.
function APM.recoverAbortedCalls(placeable, intoBuffer)
    local state = placeable.apmState
    if state.processing and state.processing ~= g_updateLoopIndex then
        state.processing = false
    end
    if state.palletDepth > 0 and state.palletFrame ~= g_updateLoopIndex then
        local pallets = placeable.spec_husbandryPallets
        -- Pending stock still holds only the visible part; what is left of it
        -- is what is left released.
        APM.clampReleased(placeable)
        for fillType, amount in pairs(state.hidden) do
            if intoBuffer or pallets == nil then
                state.refunds[fillType] = (state.refunds[fillType] or 0) + amount
            else
                pallets.pendingLiters[fillType] = (pallets.pendingLiters[fillType] or 0) + amount
            end
        end
        state.hidden = {}
        state.palletDepth = 0
    end
end

-- Released liters still waiting in native pending stock, never more than it holds.
function APM.released(placeable, fillType)
    local pallets = placeable.spec_husbandryPallets
    local released = placeable.apmState.released[fillType] or 0
    if pallets == nil or released <= 0 then return 0 end
    return math.max(math.min(released, pallets.pendingLiters[fillType] or 0), 0)
end

-- The native spawner only takes from visible pending stock, and in mode 2 only
-- released liters are visible. Whatever it consumed is no longer released.
function APM.clampReleased(placeable)
    local state = placeable.apmState
    for fillType in pairs(state.released) do
        local released = APM.released(placeable, fillType)
        state.released[fillType] = released > 0 and released or nil
    end
end

-- Keep native spawner bookkeeping and callbacks, hiding only managed pending stock.
-- Mode 2 leaves its released liters visible; output produced after the hourly
-- distribution stays hidden until the next one.
-- Hidden stock is recorded in the state, so an error in the spawner cannot lose it.
function APM.withStoredPalletsHidden(placeable, superFunc, ...)
    if placeable.apmState == nil or not placeable.isServer then
        return superFunc(placeable, ...)
    end
    local state = placeable.apmState
    APM.recoverAbortedCalls(placeable, false)
    local pending = placeable.spec_husbandryPallets.pendingLiters
    state.palletDepth = state.palletDepth + 1
    state.palletFrame = g_updateLoopIndex
    local hidden = {}
    for fillType, amount in pairs(pending) do
        local mode = APM.mode(placeable, fillType)
        if mode ~= APMDistribution.KEEP and amount ~= 0 then
            local visible = 0
            if mode == APMDistribution.DISTRIBUTE_STORE then
                visible = APM.released(placeable, fillType)
            end
            if amount ~= visible then
                hidden[fillType] = amount - visible
                state.hidden[fillType] = (state.hidden[fillType] or 0) + amount - visible
                pending[fillType] = visible
            end
        end
    end
    local result = superFunc(placeable, ...)
    APM.clampReleased(placeable)
    local resume = false
    for fillType, amount in pairs(hidden) do
        pending[fillType] = pending[fillType] + amount
        state.hidden[fillType] = state.hidden[fillType] - amount
        if state.hidden[fillType] <= 0 then state.hidden[fillType] = nil end
        -- Ownership or mode can change inside a synchronous native callback.
        -- Its nested update saw zero stock; retry after the outer mask is gone.
        if APM.mode(placeable, fillType) == APMDistribution.KEEP and pending[fillType] > 5 then
            resume = true
        end
    end
    state.palletDepth = state.palletDepth - 1
    if resume and state.palletDepth == 0 then
        placeable:updatePallets()
    end
    return result
end

function APM:updatePallets(superFunc)
    return APM.withStoredPalletsHidden(self, superFunc)
end

function APM:getPalletCallback(superFunc, pallet, result, fillType)
    return APM.withStoredPalletsHidden(self, superFunc, pallet, result, fillType)
end

function APM.writeLevel(get, set, value)
    local before = get()
    set(value)
    return get() - before
end

function APM.releaseMoneyHook()
    local hook = APM.moneyHook
    if hook ~= nil then
        APM.moneyHook = nil
        if rawget(hook.center, "publish") == hook.publish then
            hook.center.publish = hook.own
        end
    end
end

-- Farm:changeBalance changes the balance, then publishes MONEY_CHANGED.
-- Book the change at that moment, before subscribers run: their own effects
-- (loans, repayments, nested settlements) and their errors stay out of this
-- transaction. The hook removes itself before calling them.
function APM.changeMoney(farmId, amount, moneyType, onBooked)
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then return 0 end
    APM.releaseMoneyHook()
    local center = g_messageCenter
    local publish = center.publish
    local before = farm:getBalance()
    local booked
    local function book()
        if booked == nil then
            booked = farm:getBalance() - before
            if onBooked ~= nil then onBooked(booked) end
        end
    end
    local hook = {center = center, own = rawget(center, "publish"), frame = g_updateLoopIndex}
    hook.publish = function(messageCenter, messageType, ...)
        if APM.moneyHook == hook then
            if hook.frame ~= g_updateLoopIndex then
                APM.releaseMoneyHook()
            elseif messageCenter == center and messageType == MessageType.MONEY_CHANGED and select(1, ...) == farmId then
                APM.releaseMoneyHook()
                book()
            end
        end
        return publish(messageCenter, messageType, ...)
    end
    center.publish = hook.publish
    APM.moneyHook = hook
    g_currentMission:addMoney(amount, farmId, moneyType, true)
    -- Small changes are not published; nothing else ran between the change and here.
    APM.releaseMoneyHook()
    book()
    return booked
end

-- The refund buffer holds this barn's product outside native stock: taken
-- liters stay in it until they are sold or delivered, and liters a storage
-- refuses to take back wait in it, saved with the game, until they fit.
function APM.source(placeable, fillType)
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
    local refunds = placeable.apmState.refunds
    local function held() return refunds[fillType] or 0 end
    local function moveBack(amount, warn)
        amount = math.min(math.max(amount, 0), held())
        if amount <= 0 then return end
        -- Count the liters as returned first; the tank changes before its listeners run.
        refunds[fillType] = held() - amount
        local retained = math.max(amount - math.max(APM.writeLevel(get, set, get() + amount), 0), 0)
        refunds[fillType] = held() + retained
        if warn and retained > 0.000001 then
            Logging.warning("Animal Products Manager retained %.3f liters of %s for recovery; keep the mod enabled until restored",
                retained, g_fillTypeManager:getFillTypeNameByIndex(fillType))
        end
    end
    return {
        available = function() return get() + held() end,
        take = function(amount)
            amount = math.max(amount, 0)
            local buffered = held()
            local level = get()
            local target = math.max(level - math.max(amount - buffered, 0), 0)
            if target < level then
                -- Count the liters as taken first; the tank changes before its listeners run.
                refunds[fillType] = buffered + level - target
                refunds[fillType] = buffered + math.max(-APM.writeLevel(get, set, target), 0)
            end
            return math.min(held(), amount)
        end,
        release = function(amount) refunds[fillType] = math.max(held() - math.max(amount, 0), 0) end,
        hold = function(amount) refunds[fillType] = held() + math.max(amount, 0) end,
        put = function(amount) moveBack(amount, true) end,
        restore = function() moveBack(held(), false) end
    }
end

function APM.targets(placeable, fillType)
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
                return math.max(APM.writeLevel(get, set, get() + math.min(amount, target.free())), 0)
            end
            target.remove = function(amount)
                local get = function() return storage:getFillLevel(fillType) end
                local set = function(value) storage:setFillLevel(value, fillType) end
                return math.max(-APM.writeLevel(get, set, math.max(get() - amount, 0)), 0)
            end
            table.insert(result, target)
        end
    end
    return result
end

function APM:processHour()
    local state = self.apmState
    if not self.isServer or state == nil or state.deleted or not state.ready then
        return
    end
    APM.recoverAbortedCalls(self, false)
    if state.processing or state.palletDepth > 0 or self:getOwnerFarmId() == FarmManager.SPECTATOR_FARM_ID
        or g_farmManager:getFarmById(self:getOwnerFarmId()) == nil then
        return
    end
    state.processing = g_updateLoopIndex
    local spawn = APM.processOutputs(self)
    state.processing = false
    -- Released output becomes pallets the native way, after the settlement.
    if spawn and self.updatePallets ~= nil then
        self:updatePallets()
    end
end

-- Returns true when released pallet output is waiting for the native spawner.
function APM:processOutputs()
    local mission = g_currentMission
    local farmId = self:getOwnerFarmId()
    local state = self.apmState
    local spawn = false
    local function sell(source, fillType)
        APMDistribution.sell(source,
            mission.economyManager:getPricePerLiter(fillType) * ProductionPoint.DIRECT_SELL_PRICE_FACTOR,
            function(revenue, onPaid) APM.changeMoney(farmId, revenue, MoneyType.SOLD_PRODUCTS, onPaid) end)
    end
    local function distribute(source, fillType)
        APMDistribution.distribute(source, APM.targets(self, fillType), function(target, amount)
            local distance = calcDistanceFrom(self.rootNode, target.point.owningPlaceable.rootNode)
            local rate = distance * ProductionPoint.DIRECT_DELIVERY_PRICE
            if rate <= 0 then return amount end
            local paid = -APM.changeMoney(farmId, -amount * rate, MoneyType.PRODUCTION_COSTS)
            return paid / rate
        end)
    end
    for _, fillType in ipairs(APM.products(self)) do
        local mode = APM.mode(self, fillType)
        local source = APM.source(self, fillType)
        if source ~= nil then
            if mode == APMDistribution.KEEP then
                if (state.refunds[fillType] or 0) > 0 then source.restore() end
            elseif mode == APMDistribution.SELL then
                sell(source, fillType)
            elseif mode == APMDistribution.DISTRIBUTE_SELL then
                distribute(source, fillType)
                sell(source, fillType)
            elseif mode == APMDistribution.DISTRIBUTE_STORE then
                distribute(source, fillType)
                -- Store the rest natively: liquids stay in the tank, and the pallet
                -- output left now (not what is produced later) may become pallets.
                source.restore()
                local pallets = self.spec_husbandryPallets
                local pending = pallets ~= nil and pallets.pendingLiters[fillType]
                if pending then
                    state.released[fillType] = pending > 0 and pending or nil
                    spawn = spawn or pending > 5
                end
            end
        end
    end
    return spawn
end
