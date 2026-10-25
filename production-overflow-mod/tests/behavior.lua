local PO = ProductionOverflow
local passed = 0
local function test(name, body)
    g_currentMission.money, g_currentMission.bookings = 0, {}
    g_currentMission.allowed, g_currentMission.farmId = true, 1
    g_server.sent, g_nativeModeEvents = {}, {}
    body()
    passed = passed + 1
    print("PASS " .. name)
end
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local function raises(func, ...)
    local ok = pcall(func, ...)
    assert(not ok, "expected the error to reach the caller")
end
local function set(point, fillType, mode)
    assert(PO.applyMode(point, fillType, mode), "mode refused")
end
-- A factory and a downstream production point of the same farm that accepts output 7 and 9.
local function chain(targetCapacity)
    local factory = mockPoint()
    local target = mockPoint({inputs = {[7] = true, [9] = true}, capacity = targetCapacity or 1000})
    local manager = setmetatable({isServer = true, productionPoints = {factory, target}}, {__index = ProductionChainManager})
    return factory, target, manager
end
-- The same chain with no space downstream for output 7 and 9.
local function blocked()
    local factory, target, manager = chain()
    target.storage:setFillLevel(1000, 7)
    target.storage:setFillLevel(1000, 9)
    return factory, target, manager
end
local function hour(manager)
    for _, point in ipairs(manager.productionPoints) do point:directlySellOutputs() end
    manager:distributeGoods()
end
local function serverConnection() return {getIsServer = function() return true end} end
local function clientConnection(farmId, allowed)
    return {farmId = farmId or 1, allowed = allowed ~= false, getIsServer = function() return false end}
end

test("toggle cycles the native modes, then the two Mod modes", function()
    local point = mockPoint()
    local seen = {}
    for _ = 1, 6 do
        point:toggleOutputDistributionMode(7)
        table.insert(seen, PO.getMode(point, 7))
    end
    assert(table.concat(seen, ",") == "1,2,3,4,0,1", table.concat(seen, ","))
    -- The Mod modes stay native Distributing underneath.
    set(point, 7, PO.DISTRIBUTE_SELL)
    assert(point:getOutputDistributionMode(7) == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER)
    assert(point.outputFillTypeIdsAutoDeliver[7] and point.outputFillTypeIdsDirectSell[7] == nil)
end)
test("outputs without a pallet skip store-rest", function()
    local point = mockPoint()
    local seen = {}
    for _ = 1, 4 do
        point:toggleOutputDistributionMode(9)
        table.insert(seen, PO.getMode(point, 9))
    end
    assert(table.concat(seen, ",") == "1,2,4,0", table.concat(seen, ","))
    assert(not PO.applyMode(point, 9, PO.DISTRIBUTE_STORE))
    point.palletSpawner = nil
    assert(not PO.applyMode(point, 7, PO.DISTRIBUTE_STORE) and PO.applyMode(point, 7, PO.DISTRIBUTE_SELL))
end)
test("invalid modes and fill types are refused", function()
    local point = mockPoint()
    for _, mode in ipairs({-1, 5, 7, 2.5}) do assert(not PO.applyMode(point, 7, mode)) end
    assert(not PO.applyMode(point, 3, PO.SELL) and not PO.applyMode(point, nil, PO.SELL))
    assert(PO.getMode(point, 7) == PO.KEEP)
end)
test("production points without the Mod keep the native toggle", function()
    local point = mockPoint({withMod = false})
    for _ = 1, 3 do point:toggleOutputDistributionMode(7) end
    assert(point:getOutputDistributionMode(7) == 0 and #g_nativeModeEvents == 3)
    assert(not PO.applyMode(point, 7, PO.DISTRIBUTE_SELL))
    -- Deleted placeables behave the same.
    local deleted = mockPoint()
    ProductionOverflowPlaceable.onDelete(deleted.owningPlaceable)
    deleted:toggleOutputDistributionMode(7)
    assert(deleted:getOutputDistributionMode(7) == 1)
end)
test("a mode this Mod doesn't know keeps its own toggle", function()
    local point = mockPoint()
    ProductionPoint.OUTPUT_MODE.OTHER = 3
    point.getOutputDistributionMode = function() return 3 end
    -- Its number equals store-rest; it must not be shown, saved or toggled as store-rest.
    assert(PO.getMode(point, 7) == nil and #PO.restEntries(point) == 0)
    point:toggleOutputDistributionMode(7)
    ProductionPoint.OUTPUT_MODE.OTHER = nil
    point.getOutputDistributionMode = nil
    assert(#g_nativeModeEvents == 1 and g_nativeModeEvents[1].mode == 0)
end)
test("any native mode change ends a Mod mode", function()
    local point = mockPoint()
    set(point, 7, PO.DISTRIBUTE_STORE)
    point.poState.released[7] = 100
    point:setOutputDistributionMode(7, ProductionPoint.OUTPUT_MODE.AUTO_DELIVER, true)
    assert(PO.getMode(point, 7) == PO.DISTRIBUTE and point.poState.released[7] == nil)
    set(point, 8, PO.DISTRIBUTE_SELL)
    point:setOutputDistributionMode(8, ProductionPoint.OUTPUT_MODE.KEEP)
    assert(PO.getMode(point, 8) == PO.KEEP and point.poState.rest[8] == nil)
end)
test("sell-rest distributes first, then sells the rest at the Selling price", function()
    local factory, target, manager = chain(600)
    target.storage:setFillLevel(400, 7)
    factory.storage:setFillLevel(500, 7)
    set(factory, 7, PO.DISTRIBUTE_SELL)
    hour(manager)
    near(target.storage:getFillLevel(7), 600)
    near(factory.storage:getFillLevel(7), 0)
    local fee = -200 * 1000 * ProductionPoint.DIRECT_DELIVERY_PRICE
    near(g_currentMission.money, fee + 300 * 2 * 0.9)
    local sale = g_currentMission.bookings[#g_currentMission.bookings]
    assert(sale.moneyType == MoneyType.SOLD_PRODUCTS and sale.farmId == 1)
    near(sale.amount, 540)
end)
test("sell-rest sells everything when nothing accepts the product", function()
    local factory, _, manager = chain()
    factory.storage:setFillLevel(250, 8)
    set(factory, 8, PO.DISTRIBUTE_SELL)
    hour(manager)
    near(factory.storage:getFillLevel(8), 0); near(g_currentMission.money, 250 * 2 * 0.9)
    hour(manager)
    assert(#g_currentMission.bookings == 1, "an empty storage is not sold again")
end)
test("plain Distributing is unchanged", function()
    local factory, target, manager = chain(600)
    target.storage:setFillLevel(400, 7)
    factory.storage:setFillLevel(500, 7)
    set(factory, 7, PO.DISTRIBUTE)
    hour(manager)
    near(factory.storage:getFillLevel(7), 300); near(target.storage:getFillLevel(7), 600)
    factory:updateProduction()
    assert(#factory.palletSpawner.requests == 0, "native Distributing never makes pallets")
end)
test("store-rest makes full pallets of the rest only", function()
    local factory, target, manager = chain(600)
    target.storage:setFillLevel(530, 7)
    factory.storage:setFillLevel(320, 7)
    set(factory, 7, PO.DISTRIBUTE_STORE)
    factory:updateProduction()
    assert(#factory.palletSpawner.requests == 0, "nothing before the first hour")
    hour(manager)
    near(factory.storage:getFillLevel(7), 250); near(factory.poState.released[7], 250)
    for _ = 1, 4 do
        factory:updateProduction()
        factory.palletSpawner:finish()
    end
    assert(#factory.palletSpawner.pallets == 2, "two full pallets of 100 L")
    near(factory.storage:getFillLevel(7), 50); near(factory.poState.released[7], 50)
    assert(factory.outputFillTypeIdsAutoDeliver[7], "the output is back in the Distributing set")
    assert(PO.getMode(factory, 7) == PO.DISTRIBUTE_STORE)
end)
test("output made after the hour waits for the next distribution", function()
    local factory, target, manager = chain(600)
    target.storage:setFillLevel(600, 7)
    factory.storage:setFillLevel(150, 7)
    set(factory, 7, PO.DISTRIBUTE_STORE)
    hour(manager)
    near(factory.poState.released[7], 150)
    factory.produce = {[7] = 100}
    factory:updateProduction() -- 250 L in storage, 150 L released: one pallet
    factory.palletSpawner:finish()
    factory:updateProduction() -- 250 L, 50 L released: no pallet
    factory.produce = nil
    assert(#factory.palletSpawner.pallets == 1 and #factory.palletSpawner.requests == 0)
    near(factory.storage:getFillLevel(7), 250); near(factory.poState.released[7], 50)
    -- Next hour: space downstream again, so the new output is delivered first.
    target.storage:setFillLevel(400, 7)
    hour(manager)
    near(target.storage:getFillLevel(7), 600); near(factory.storage:getFillLevel(7), 50)
    near(factory.poState.released[7], 50)
end)
test("a pallet that takes stock produced later never counts twice", function()
    local factory, _, manager = blocked()
    factory.storage:setFillLevel(120, 7)
    set(factory, 7, PO.DISTRIBUTE_STORE)
    hour(manager)
    factory:updateProduction()
    factory.storage:setFillLevel(400, 7) -- the pallet arrives frames later
    factory.palletSpawner:finish()
    near(factory.storage:getFillLevel(7), 300); near(factory.poState.released[7], 20)
    factory:updateProduction()
    assert(#factory.palletSpawner.requests == 0)
end)
test("a pallet without space keeps the released stock for a retry", function()
    local factory, _, manager = blocked()
    factory.storage:setFillLevel(100, 7)
    set(factory, 7, PO.DISTRIBUTE_STORE)
    hour(manager)
    factory:updateProduction()
    factory.palletSpawner:finish(true)
    near(factory.poState.released[7], 100)
    factory:updateProduction()
    assert(#factory.palletSpawner.requests == 0, "native cooldown applies")
    g_time = g_time + 20000
    factory:updateProduction()
    factory.palletSpawner:finish()
    assert(factory.poState.released[7] == nil and factory.storage:getFillLevel(7) == 0)
end)
test("pallets for Storing outputs keep working beside store-rest", function()
    local factory, _, manager = blocked()
    factory.storage:setFillLevel(100, 7)
    factory.storage:setFillLevel(60, 8)
    set(factory, 7, PO.DISTRIBUTE_STORE)
    hour(manager)
    factory:updateProduction(); factory.palletSpawner:finish()
    factory:updateProduction(); factory.palletSpawner:finish()
    assert(#factory.palletSpawner.pallets == 2)
    assert(factory.palletSpawner.pallets[1].fillType == 7 and factory.palletSpawner.pallets[2].fillType == 8)
    near(factory.storage:getFillLevel(8), 10)
end)
test("stock removed by other means lowers the released amount", function()
    local factory, _, manager = blocked()
    factory.storage:setFillLevel(180, 7)
    set(factory, 7, PO.DISTRIBUTE_STORE)
    hour(manager)
    factory.storage:setFillLevel(90, 7) -- taken at a loading station
    factory:updateProduction()
    assert(#factory.palletSpawner.requests == 0); near(factory.poState.released[7], 90)
end)
test("mode and owner changes drop released stock", function()
    for _, change in ipairs({"sell", "distribute", "keep", "owner", "same"}) do
        local factory, _, manager = blocked()
        factory.storage:setFillLevel(200, 7)
        set(factory, 7, PO.DISTRIBUTE_STORE)
        hour(manager)
        if change == "sell" then set(factory, 7, PO.DISTRIBUTE_SELL)
        elseif change == "distribute" then set(factory, 7, PO.DISTRIBUTE)
        elseif change == "keep" then set(factory, 7, PO.KEEP)
        elseif change == "owner" then factory:setOwnerFarmId(2)
        else set(factory, 7, PO.DISTRIBUTE_STORE) end
        if change == "same" then
            near(factory.poState.released[7], 200)
        else
            assert(factory.poState.released[7] == nil, change)
            if change == "owner" then
                assert(PO.getMode(factory, 7) == PO.DISTRIBUTE_STORE, "the mode stays, like native modes")
            end
        end
    end
end)
test("a failing native update restores the Distributing set", function()
    local factory, _, manager = blocked()
    factory.storage:setFillLevel(200, 7)
    set(factory, 7, PO.DISTRIBUTE_STORE)
    hour(manager)
    factory.failInUpdate = true
    raises(factory.updateProduction, factory)
    assert(factory.outputFillTypeIdsAutoDeliver[7] == nil and factory.poState.exposed[7])
    -- Saving restores it before the native save writes the sets.
    local xml = mockXML()
    factory:saveToXMLFile(xml, "pp")
    assert(xml.values["pp.autoDeliverFillType(0)"] == "TYPE_7" and factory.poState.exposed == nil)
    raises(factory.updateProduction, factory)
    factory:writeStream({}, {})
    assert(factory.outputFillTypeIdsAutoDeliver[7])
    raises(factory.updateProduction, factory)
    factory.failInUpdate = false
    hour(manager)
    assert(factory.outputFillTypeIdsAutoDeliver[7] and factory.poState.exposed == nil)
    raises(function() factory.failInUpdate = true; factory:updateProduction() end)
    factory.failInUpdate = false
    factory:setOutputDistributionMode(7, ProductionPoint.OUTPUT_MODE.KEEP, true)
    assert(factory.outputFillTypeIdsAutoDeliver[7] == nil and PO.getMode(factory, 7) == PO.KEEP)
    factory:updateProduction()
    assert(factory.outputFillTypeIdsAutoDeliver[7] == nil, "a native change after a failure is kept")
end)
test("clients and unowned points never sell or make pallets", function()
    local factory, _, manager = chain()
    factory.storage:setFillLevel(300, 8)
    set(factory, 8, PO.DISTRIBUTE_SELL)
    manager.isServer = false
    hour(manager)
    near(factory.storage:getFillLevel(8), 300); assert(#g_currentMission.bookings == 0)
    manager.isServer = true
    factory:setOwnerFarmId(AccessHandler.EVERYONE)
    hour(manager)
    near(factory.storage:getFillLevel(8), 300)
    local client = mockPoint({isServer = false})
    client.storage:setFillLevel(300, 7)
    set(client, 7, PO.DISTRIBUTE_STORE)
    client.poState.released[7] = 300
    client:updateProduction()
    assert(#client.palletSpawner.requests == 0)
end)
test("save writes the Mod modes; the native save keeps Distributing", function()
    local factory, _, manager = blocked()
    factory.storage:setFillLevel(170, 7)
    set(factory, 7, PO.DISTRIBUTE_STORE)
    set(factory, 8, PO.SELL)
    set(factory, 9, PO.DISTRIBUTE_SELL)
    hour(manager)
    local xml = mockXML()
    factory:saveToXMLFile(xml, "pp")
    ProductionOverflowPlaceable.saveToXMLFile(factory.owningPlaceable, xml, "pp.po")
    assert(xml.values["pp.autoDeliverFillType(0)"] == "TYPE_7" and xml.values["pp.autoDeliverFillType(1)"] == "TYPE_9")
    assert(xml.values["pp.directSellFillType(0)"] == "TYPE_8")
    assert(xml.values["pp.po.output(0)#fillType"] == "TYPE_7" and xml.values["pp.po.output(0)#mode"] == "storeRest")
    near(xml.values["pp.po.output(0)#releasedLiters"], 170)
    assert(xml.values["pp.po.output(1)#fillType"] == "TYPE_9" and xml.values["pp.po.output(1)#mode"] == "sellRest")
    assert(xml.values["pp.po.output(1)#releasedLiters"] == nil and xml.values["pp.po.output(2)#fillType"] == nil)
    -- Load in either order relative to the native data; the Mod modes apply when loading finishes.
    for _, nativeFirst in ipairs({true, false}) do
        -- Game order: onLoad, loadFromXMLFile, onLoadFinished, then placement sets the owner.
        local loaded = mockPoint({farmId = AccessHandler.EVERYONE, placed = false})
        loaded.storage:setFillLevel(120, 7)
        if nativeFirst then loaded:loadFromXMLFile(xml, "pp") end
        ProductionOverflowPlaceable.loadFromXMLFile(loaded.owningPlaceable, xml, "pp.po", false)
        if not nativeFirst then loaded:loadFromXMLFile(xml, "pp") end
        ProductionOverflowPlaceable.onLoadFinished(loaded.owningPlaceable)
        loaded:setOwnerFarmId(1)
        ProductionOverflowPlaceable.onPostFinalizePlacement(loaded.owningPlaceable)
        assert(PO.getMode(loaded, 7) == PO.DISTRIBUTE_STORE and PO.getMode(loaded, 8) == PO.SELL)
        assert(PO.getMode(loaded, 9) == PO.DISTRIBUTE_SELL)
        near(PO.released(loaded, 7), 120) -- never more than the storage holds
    end
    -- Without the Mod the same save is plain Distributing.
    local native = mockPoint({withMod = false})
    native:loadFromXMLFile(xml, "pp")
    assert(native:getOutputDistributionMode(7) == 2 and native:getOutputDistributionMode(9) == 2)
end)
test("invalid or outdated saved entries are ignored", function()
    local xml = mockXML()
    xml:setValue("pp.po.output(0)#fillType", "TYPE_9"); xml:setValue("pp.po.output(0)#mode", "storeRest")
    xml:setValue("pp.po.output(1)#fillType", "TYPE_8"); xml:setValue("pp.po.output(1)#mode", "sellRest")
    xml:setValue("pp.po.output(2)#fillType", "TYPE_7"); xml:setValue("pp.po.output(2)#mode", "other")
    xml:setValue("pp.po.output(3)#fillType", "UNKNOWN_NAME"); xml:setValue("pp.po.output(3)#mode", "sellRest")
    xml:setValue("pp.po.output(4)#fillType", "TYPE_7"); xml:setValue("pp.po.output(4)#mode", "sellRest")
    xml:setValue("pp.po.output(4)#releasedLiters", 90)
    local loaded = mockPoint()
    for _, fillType in ipairs({7, 9}) do loaded:setOutputDistributionMode(fillType, 2, true) end
    loaded:setOutputDistributionMode(8, 1, true) -- the native save says Selling: it wins
    ProductionOverflowPlaceable.loadFromXMLFile(loaded.owningPlaceable, xml, "pp.po", false)
    ProductionOverflowPlaceable.onLoadFinished(loaded.owningPlaceable)
    assert(PO.getMode(loaded, 9) == PO.DISTRIBUTE and PO.getMode(loaded, 8) == PO.SELL)
    assert(PO.getMode(loaded, 7) == PO.DISTRIBUTE_SELL and loaded.poState.released[7] == nil)
    local reset = mockPoint()
    reset:setOutputDistributionMode(7, 2, true)
    ProductionOverflowPlaceable.loadFromXMLFile(reset.owningPlaceable, xml, "pp.po", true)
    ProductionOverflowPlaceable.onLoadFinished(reset.owningPlaceable)
    assert(PO.getMode(reset, 7) == PO.DISTRIBUTE)
end)
test("joining clients receive the Mod modes after the native stream", function()
    local server, client, stream = mockPoint(), mockPoint({isServer = false}), {}
    set(server, 7, PO.DISTRIBUTE_STORE); set(server, 8, PO.SELL); set(server, 9, PO.DISTRIBUTE_SELL)
    server.poState.released[7] = 40
    server:writeStream(stream, {})
    ProductionOverflowPlaceable.onWriteStream(server.owningPlaceable, stream, {})
    client:readStream(stream, {})
    ProductionOverflowPlaceable.onReadStream(client.owningPlaceable, stream, {})
    assert(#stream == 0)
    assert(PO.getMode(client, 7) == PO.DISTRIBUTE_STORE and PO.getMode(client, 8) == PO.SELL)
    assert(PO.getMode(client, 9) == PO.DISTRIBUTE_SELL and client.poState.released[7] == nil)
    -- Placeables whose production point failed to load still keep the stream aligned.
    local broken, other = {spec_productionPoint = {}}, {}
    ProductionOverflowPlaceable.onLoad(broken)
    ProductionOverflowPlaceable.onWriteStream(broken, other, {})
    ProductionOverflowPlaceable.onReadStream(broken, other, {})
    assert(#other == 0)
end)
test("the mode event travels with three bits and the server checks the sender", function()
    local packet = {}
    local client = mockPoint({isServer = false})
    POModeEvent.new(client, 7, PO.DISTRIBUTE_SELL):writeStream(packet, {})
    POModeEvent.emptyNew():readStream(packet, serverConnection())
    assert(PO.getMode(client, 7) == PO.DISTRIBUTE_SELL and #packet == 0)
    local server = mockPoint()
    POModeEvent.new(server, 7, PO.DISTRIBUTE_STORE):run(clientConnection(1, true))
    assert(PO.getMode(server, 7) == PO.DISTRIBUTE_STORE and #g_server.sent == 1)
    for _, connection in ipairs({clientConnection(2, true), clientConnection(1, false)}) do
        POModeEvent.new(server, 7, PO.KEEP):run(connection)
    end
    POModeEvent.new(server, 9, PO.DISTRIBUTE_STORE):run(clientConnection(1, true))
    assert(PO.getMode(server, 7) == PO.DISTRIBUTE_STORE and PO.getMode(server, 9) == PO.KEEP)
    assert(#g_server.sent == 1, "rejected requests are not sent on")
    server:setOwnerFarmId(AccessHandler.EVERYONE)
    POModeEvent.new(server, 7, PO.KEEP):run(clientConnection(0, true))
    assert(PO.getMode(server, 7) == PO.DISTRIBUTE_STORE)
    POModeEvent.new(nil, 7, PO.KEEP):run(clientConnection(1, true))
end)
test("toggling on a client asks the server and changes nothing locally", function()
    local client = mockPoint({isServer = false})
    local sent = {}
    g_client = {getServerConnection = function() return {sendEvent = function(_, event) table.insert(sent, event) end} end}
    client:toggleOutputDistributionMode(7)
    assert(#sent == 1 and sent[1].mode == PO.SELL and PO.getMode(client, 7) == PO.KEEP)
    assert(#g_nativeModeEvents == 0)
    g_currentMission.allowed = false
    client:toggleOutputDistributionMode(7)
    assert(#sent == 1, "no request without the permission")
    g_client = nil
end)
test("the production menu shows the Mod mode names", function()
    local point = mockPoint()
    set(point, 7, PO.DISTRIBUTE_STORE); set(point, 8, PO.DISTRIBUTE_SELL); set(point, 9, PO.SELL)
    local frame = setmetatable({productsList = {}, selectedProductionPoint = point}, {__index = InGameMenuProductionFrame})
    local function text(index, list)
        local activity = {setText = function(self, value) self.text = value end}
        local cell = {getAttribute = function(_, name) assert(name == "activity"); return activity end}
        frame:populateCellForItemInSection(list or frame.productsList, 1, index, cell)
        return activity.text
    end
    assert(text(1) == "mod:po_mode_distribute_store" and text(2) == "mod:po_mode_distribute_sell")
    assert(text(3) == "ui_production_output_selling")
    assert(text(1, {}) == nil, "other lists are left alone")
    set(point, 7, PO.DISTRIBUTE)
    assert(text(1) == "ui_production_output_distributing")
    point.sortedProductions[1].primaryProductFillType = 3
    frame.populateCellForItemInSection = function(...)
        -- Native code shows Storing for a non-output; the Mod must not touch it.
        local f, list, section, index, cell = ...
        cell:getAttribute("activity"):setText("native")
        PO.populateCellForItemInSection(...)
    end
    assert(text(1) == "native")
end)
test("an open production page refreshes when a mode changes", function()
    local point = mockPoint()
    local frame = setmetatable({}, {__index = InGameMenuProductionFrame})
    PO.uiDirty = false
    frame:update(16)
    assert(frame.refreshes == nil)
    set(point, 7, PO.DISTRIBUTE_SELL)
    frame:update(16)
    assert(frame.refreshes == nil, "a page that never opened is not refreshed")
    frame.chainManager = {}
    frame:update(16)
    frame:update(16)
    assert(frame.refreshes == 1)
end)
test("the menu button walks through all five modes on the host", function()
    local point = mockPoint()
    local frame = setmetatable({selectedProductionPoint = point, selectedProduction = point.sortedProductions[2]},
        {__index = InGameMenuProductionFrame})
    local seen = {}
    for _ = 1, 5 do
        frame:onButtonToggleOutputMode()
        table.insert(seen, PO.getMode(point, 8))
    end
    assert(table.concat(seen, ",") == "1,2,3,4,0")
    assert(#g_server.sent == 5 and #g_nativeModeEvents == 0)
end)
test("hooks pass through when the Mod is not active in the loaded game", function()
    local point = mockPoint()
    g_modIsLoaded[g_currentModName] = false
    for _ = 1, 3 do point:toggleOutputDistributionMode(7) end
    assert(point:getOutputDistributionMode(7) == 0 and #g_nativeModeEvents == 3)
    g_modIsLoaded[g_currentModName] = true
end)
test("loading the scripts again does not stack hooks", function()
    local point = mockPoint()
    local calls = 0
    local original = PO.toggleOutputDistributionMode
    PO.toggleOutputDistributionMode = function(...) calls = calls + 1; return original(...) end
    ProductionPoint["po_" .. g_currentModName .. "_toggleOutputDistributionMode"] = PO.toggleOutputDistributionMode
    point:toggleOutputDistributionMode(7)
    PO.toggleOutputDistributionMode = original
    ProductionPoint["po_" .. g_currentModName .. "_toggleOutputDistributionMode"] = original
    assert(calls == 1 and PO.getMode(point, 7) == PO.SELL)
end)
test("the specialization is added once to production point placeables", function()
    local manager = {typeName = "placeable", types = {
        factory = {specializations = {PlaceableProductionPoint}, specializationsByName = {}},
        silo = {specializations = {}, specializationsByName = {}}
    }}
    manager.addSpecialization = function(self, name, spec)
        assert(spec == "FS25_ProductionOverflow.productionOverflow")
        self.types[name].specializationsByName[spec] = true
        self.added = (self.added or 0) + 1
    end
    TypeManager.validateTypes(manager)
    TypeManager.validateTypes(manager)
    assert(manager.added == 1 and manager.types.silo.specializationsByName[next(manager.types.factory.specializationsByName)] == nil)
    TypeManager.validateTypes({typeName = "vehicle", types = {}})
end)
test("a missing game function disables the Mod without hooks", function()
    local saved = ProductionChainManager.distributeGoods
    local before = ProductionPoint.updateProduction
    ProductionChainManager.distributeGoods = nil
    Logging.warnings = {}
    local chunk = assert(load(MOD_REGISTER_SOURCE))
    chunk()
    ProductionChainManager.distributeGoods = saved
    assert(#Logging.warnings == 1 and Logging.warnings[1]:find("ProductionChainManager.distributeGoods", 1, true))
    assert(ProductionPoint.updateProduction == before)
end)

print(string.format("%d behavioral tests passed", passed))
