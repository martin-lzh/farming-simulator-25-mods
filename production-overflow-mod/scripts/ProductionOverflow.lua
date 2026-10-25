-- Two extra output modes for production points, on top of the native Distributing mode.
-- The Mod modes keep the output in the native AUTO_DELIVER set, so native distribution,
-- saving and streaming are unchanged; the extra behaviour is a per-output flag here.
ProductionOverflow = {}
local PO = ProductionOverflow

PO.MOD_NAME = g_currentModName

-- Mode numbers as this Mod sees them. 0 to 2 are the native ProductionPoint.OUTPUT_MODE
-- values; 3 and 4 only travel in this Mod's own event and are never given to native code.
PO.KEEP = 0
PO.SELL = 1
PO.DISTRIBUTE = 2
PO.DISTRIBUTE_STORE = 3
PO.DISTRIBUTE_SELL = 4
PO.MODE_NUM_BITS = 3

PO.SAVE_NAMES = {[PO.DISTRIBUTE_STORE] = "storeRest", [PO.DISTRIBUTE_SELL] = "sellRest"}
PO.SAVE_MODES = {storeRest = PO.DISTRIBUTE_STORE, sellRest = PO.DISTRIBUTE_SELL}
PO.TEXTS = {[PO.DISTRIBUTE_STORE] = "po_mode_distribute_store", [PO.DISTRIBUTE_SELL] = "po_mode_distribute_sell"}

-- Set when a mode change arrives, so an open production page shows it at once.
PO.uiDirty = false

function PO.isMode(mode)
    return mode == PO.KEEP or mode == PO.SELL or mode == PO.DISTRIBUTE
        or mode == PO.DISTRIBUTE_STORE or mode == PO.DISTRIBUTE_SELL
end

function PO.isRestMode(mode)
    return mode == PO.DISTRIBUTE_STORE or mode == PO.DISTRIBUTE_SELL
end

-- State exists only on production points owned by a placeable with this Mod's
-- specialization (see ProductionOverflowPlaceable). Others are left to the base game.
function PO.newState()
    -- rest[fillType]: DISTRIBUTE_STORE or DISTRIBUTE_SELL on top of native AUTO_DELIVER.
    -- released[fillType]: liters left after the last hourly distribution that may still
    -- become pallets (DISTRIBUTE_STORE, server only).
    -- exposed[fillType]: outputs taken out of the native AUTO_DELIVER set for the duration
    -- of one native updateProduction call, so its pallet loop may handle them.
    -- ready/ownerFarmId: set once the placeable is placed, to tell owner changes apart.
    return {rest = {}, released = {}, exposed = nil, loaded = nil, deleted = false, ready = false, ownerFarmId = nil}
end

function PO.state(point)
    local state = point ~= nil and point.poState or nil
    if state ~= nil and not state.deleted then
        return state
    end
    return nil
end

function PO.isOutput(point, fillType)
    return fillType ~= nil and point.outputFillTypeIds ~= nil and point.outputFillTypeIds[fillType] ~= nil
end

-- The store-rest mode needs a pallet for the product; liquids without one only get sell-rest.
function PO.canStoreRest(point, fillType)
    return point.palletSpawner ~= nil and point.outputFillTypeIdsToPallets ~= nil
        and point.outputFillTypeIdsToPallets[fillType] ~= nil
end

function PO.canUse(point, fillType, mode)
    if PO.state(point) == nil or not PO.isOutput(point, fillType) or not PO.isMode(mode) then
        return false
    end
    if mode == PO.DISTRIBUTE_STORE then
        return PO.canStoreRest(point, fillType)
    end
    return true
end

-- The mode the player sees: a Mod mode on top of native Distributing, else the native mode.
-- Returns nil for a native mode added by someone else (for example the Pumps n' Hoses
-- AUTO_DISTRIBUTION), whose number may equal one of this Mod's own numbers.
function PO.getMode(point, fillType)
    local native = point:getOutputDistributionMode(fillType)
    if native == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER then
        local state = PO.state(point)
        if state ~= nil and state.rest[fillType] ~= nil then
            return state.rest[fillType]
        end
        return PO.DISTRIBUTE
    elseif native == ProductionPoint.OUTPUT_MODE.KEEP or native == ProductionPoint.OUTPUT_MODE.DIRECT_SELL then
        return native
    end
    return nil
end

-- Toggle order of the base game, with the Mod modes after Distributing. Returns nil for
-- a mode this Mod doesn't know (current is nil), whose cycle is left to the native toggle.
function PO.nextMode(point, fillType, current)
    if current == PO.KEEP then
        return PO.SELL
    elseif current == PO.SELL then
        return PO.DISTRIBUTE
    elseif current == PO.DISTRIBUTE then
        return PO.canStoreRest(point, fillType) and PO.DISTRIBUTE_STORE or PO.DISTRIBUTE_SELL
    elseif current == PO.DISTRIBUTE_STORE then
        return PO.DISTRIBUTE_SELL
    elseif current == PO.DISTRIBUTE_SELL then
        return PO.KEEP
    end
    return nil
end

-- Applies a mode on this machine only. Native parts are set without the native event:
-- the caller distributes the change with this Mod's own event.
function PO.applyMode(point, fillType, mode)
    if not PO.canUse(point, fillType, mode) then
        return false
    end
    local state = point.poState
    if PO.isRestMode(mode) then
        if point:getOutputDistributionMode(fillType) ~= ProductionPoint.OUTPUT_MODE.AUTO_DELIVER then
            point:setOutputDistributionMode(fillType, ProductionPoint.OUTPUT_MODE.AUTO_DELIVER, true)
        end
        if state.rest[fillType] ~= mode then
            -- Released output belongs to one hourly result of store-rest. A new
            -- store-rest waits for its own hour.
            state.released[fillType] = nil
        end
        state.rest[fillType] = mode
    else
        -- The native setter hook clears the Mod flag and released output.
        point:setOutputDistributionMode(fillType, mode, true)
    end
    PO.uiDirty = true
    return true
end

function PO.canManage(point, connection)
    if PO.state(point) == nil then
        return false
    end
    local farmId = point:getOwnerFarmId()
    return farmId ~= nil and farmId ~= AccessHandler.EVERYONE
        and g_currentMission:getFarmId(connection) == farmId
        and g_currentMission:getHasPlayerPermission("manageProductions", connection, farmId)
end

-- Every change made through the toggle goes through the server, which applies it and
-- sends it to all clients in one order.
function PO.requestMode(point, fillType, mode)
    if not PO.canUse(point, fillType, mode) or not PO.canManage(point, nil) then
        return false
    end
    local event = POModeEvent.new(point, fillType, mode)
    if point.isServer then
        if PO.applyMode(point, fillType, mode) then
            g_server:broadcastEvent(event)
        end
    else
        g_client:getServerConnection():sendEvent(event)
    end
    return true
end

-- Native helpers below are installed by Register.lua on the ProductionPoint class.

function PO.toggleOutputDistributionMode(point, superFunc, fillType)
    if PO.state(point) == nil or not PO.isOutput(point, fillType) then
        return superFunc(point, fillType)
    end
    local nextMode = PO.nextMode(point, fillType, PO.getMode(point, fillType))
    if nextMode == nil then
        return superFunc(point, fillType)
    end
    PO.requestMode(point, fillType, nextMode)
end

-- Any native mode change (native event, console command, loading, other Mods) ends a Mod mode.
function PO.setOutputDistributionMode(point, superFunc, fillType, mode, noEventSend)
    local state = PO.state(point)
    if state ~= nil then
        PO.restoreExposed(point)
        state.rest[fillType] = nil
        state.released[fillType] = nil
    end
    return superFunc(point, fillType, mode, noEventSend)
end

function PO.restoreExposed(point)
    local state = point.poState
    if state == nil or state.exposed == nil then
        return
    end
    for fillType in pairs(state.exposed) do
        if state.rest[fillType] ~= nil then
            point.outputFillTypeIdsAutoDeliver[fillType] = true
        end
    end
    state.exposed = nil
end

-- Released liters still in storage, never more than it holds.
function PO.released(point, fillType)
    local state = point.poState
    local released = state ~= nil and state.released[fillType] or nil
    if released == nil or released <= 0 or state.rest[fillType] ~= PO.DISTRIBUTE_STORE then
        return 0
    end
    return math.max(math.min(released, point.storage:getFillLevel(fillType)), 0)
end

function PO.clampReleased(point)
    local state = point.poState
    for fillType in pairs(state.released) do
        local released = PO.released(point, fillType)
        state.released[fillType] = released > 0 and released or nil
    end
end

-- The native pallet loop in updateProduction skips outputs in the AUTO_DELIVER set. For
-- store-rest outputs it may run while at least one full pallet of released output is
-- waiting: those outputs leave the set for the duration of this call only. Output made
-- after the hour is not released, so it waits for the next distribution.
function PO.updateProduction(point, superFunc)
    local state = PO.state(point)
    if state == nil or not point.isServer then
        return superFunc(point)
    end
    PO.restoreExposed(point)
    PO.clampReleased(point)
    local exposed
    if point.isOwned and point.palletSpawner ~= nil and not point.waitingForPalletToSpawn
        and g_time > point.palletSpawnCooldown then
        for fillType, released in pairs(state.released) do
            local pallet = point.outputFillTypeIdsToPallets[fillType]
            if pallet ~= nil and state.rest[fillType] == PO.DISTRIBUTE_STORE
                and point.outputFillTypeIdsAutoDeliver[fillType] and released >= pallet.capacity then
                exposed = exposed or {}
                exposed[fillType] = true
            end
        end
    end
    if exposed ~= nil then
        -- Recorded first: if the native call raises an error, the next call restores the set.
        state.exposed = exposed
        for fillType in pairs(exposed) do
            point.outputFillTypeIdsAutoDeliver[fillType] = nil
        end
    end
    superFunc(point)
    PO.restoreExposed(point)
end

-- A pallet takes what it can from storage; that much is no longer released.
function PO.palletSpawnRequestCallback(point, superFunc, pallet, status, fillType)
    local state = PO.state(point)
    local before
    if state ~= nil and fillType ~= nil and state.released[fillType] ~= nil then
        before = point.storage:getFillLevel(fillType)
    end
    superFunc(point, pallet, status, fillType)
    if before ~= nil and state.released[fillType] ~= nil then
        local taken = before - point.storage:getFillLevel(fillType)
        if taken > 0 then
            local left = state.released[fillType] - taken
            state.released[fillType] = left > 0 and left or nil
        end
    end
end

-- Native output modes stay with the production point when it changes owner; released
-- output does not carry over. Placing the point (also after loading a save) sets its
-- first owner; only changes after that count.
function PO.onOwnerChanged(point)
    local state = PO.state(point)
    if state ~= nil and state.ready then
        local owner = point:getOwnerFarmId()
        if owner ~= state.ownerFarmId then
            PO.restoreExposed(point)
            state.released = {}
        end
        state.ownerFarmId = owner
    end
end

function PO.onPlaced(point)
    local state = PO.state(point)
    if state ~= nil then
        state.ownerFarmId = point:getOwnerFarmId()
        state.ready = true
    end
end

-- Runs on the server right after the native hourly distribution.
function PO.afterDistribution(manager)
    if not manager.isServer then
        return
    end
    for _, point in ipairs(manager.productionPoints or {}) do
        if PO.state(point) ~= nil and point.isServer and point.isOwned then
            PO.restoreExposed(point)
            PO.settle(point)
        end
    end
end

function PO.restoreAll(manager)
    for _, point in ipairs(manager.productionPoints or {}) do
        if PO.state(point) ~= nil then
            PO.restoreExposed(point)
        end
    end
end

function PO.settle(point)
    local state = point.poState
    local stale = {}
    for fillType, mode in pairs(state.rest) do
        if not point.outputFillTypeIdsAutoDeliver[fillType] then
            table.insert(stale, fillType)
        elseif mode == PO.DISTRIBUTE_SELL then
            state.released[fillType] = nil
            local amount = point.storage:getFillLevel(fillType)
            if amount > 0 then
                -- Same price, money type and order as the native Selling mode
                -- (ProductionPoint:directlySellOutputs).
                local revenue = ProductionPoint.DIRECT_SELL_PRICE_FACTOR * amount
                    * g_currentMission.economyManager:getPricePerLiter(fillType)
                g_currentMission:addMoney(revenue, point:getOwnerFarmId(), MoneyType.SOLD_PRODUCTS, true)
                point.storage:setFillLevel(0, fillType)
            end
        elseif mode == PO.DISTRIBUTE_STORE then
            local amount = point.storage:getFillLevel(fillType)
            state.released[fillType] = amount > 0 and amount or nil
        end
    end
    for _, fillType in ipairs(stale) do
        state.rest[fillType] = nil
        state.released[fillType] = nil
    end
end

-- Outputs with a Mod mode, in the production point's own output order.
function PO.restEntries(point)
    local entries = {}
    local state = PO.state(point)
    if state == nil then
        return entries
    end
    for _, fillType in ipairs(point.outputFillTypeIdsArray or {}) do
        local mode = PO.getMode(point, fillType)
        if PO.isRestMode(mode) then
            table.insert(entries, {fillType = fillType, mode = mode})
        end
    end
    return entries
end

-- Production menu: the product list shows the Mod mode instead of "Distributing".
function PO.populateCellForItemInSection(frame, list, section, index, cell)
    if list ~= frame.productsList then
        return
    end
    local _, point = frame:getSelectedProduction()
    if PO.state(point) == nil or point.sortedProductions == nil then
        return
    end
    local production = point.sortedProductions[index]
    if production == nil or not PO.isOutput(point, production.primaryProductFillType) then
        return
    end
    local key = PO.TEXTS[PO.getMode(point, production.primaryProductFillType)]
    if key ~= nil then
        cell:getAttribute("activity"):setText(g_i18n:getText(key, PO.MOD_NAME))
    end
end

-- The native page refreshes itself every 5 s; chainManager is set when it first opens.
function PO.updateFrame(frame, dt)
    if PO.uiDirty and frame.chainManager ~= nil then
        PO.uiDirty = false
        frame:updateProductionLists()
    end
end
