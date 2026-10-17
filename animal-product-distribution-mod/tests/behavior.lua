local APD = AnimalProductDistribution
local passed = 0
local function test(name, body)
    body()
    passed = passed + 1
    print("PASS " .. name)
end
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local function target(storage)
    return {
        free = function() return storage:getFreeCapacity() end,
        add = function(amount)
            local before = storage.amount
            storage:setFillLevel(before + amount)
            return storage.amount - before
        end,
        remove = function(amount)
            local before = storage.amount
            storage:setFillLevel(before - amount)
            return before - storage.amount
        end
    }
end

test("default and invalid modes", function()
    local h = mockHusbandry()
    assert(APD.mode(h, 7) == 0)
    assert(not APD.applyMode(h, 7, 3))
    assert(not APD.applyMode(h, 999, 1))
    assert(APD.mode(h, 7) == 0)
end)
test("distribution conserves product and weights capacity", function()
    local h = mockHusbandry()
    local a, b = mockStorage(0, 100), mockStorage(0, 300)
    local charged = 0
    local amount = APDDistribution.distribute(APD.source(h, 7), {target(a), target(b)}, function(_, liters) charged = charged + liters; return liters end)
    near(amount, 100); near(a.amount, 25); near(b.amount, 75)
    near(h.spec_husbandryPallets.pendingLiters[7], 0); near(charged, 100)
end)
test("no receiver retains all stock", function()
    local h = mockHusbandry()
    near(APDDistribution.distribute(APD.source(h, 7), {}, function() error("charged") end), 0)
    near(h.spec_husbandryPallets.pendingLiters[7], 100)
end)
test("full and capacity limited destinations retain overflow", function()
    local h = mockHusbandry()
    local a, b = mockStorage(10, 10), mockStorage(0, 30)
    near(APDDistribution.distribute(APD.source(h, 7), {target(a), target(b)}, function(_, n) return n end), 30)
    near(h.spec_husbandryPallets.pendingLiters[7], 70)
end)
test("partial acceptance refunds unaccepted source", function()
    local h = mockHusbandry()
    local charged = 0
    local t = {free = function() return 100 end, add = function() return 10 end}
    near(APDDistribution.distribute(APD.source(h, 7), {t}, function(_, n) charged = n; return n end), 10)
    near(h.spec_husbandryPallets.pendingLiters[7], 90); near(charged, 10)
end)
test("sale credits once and zero price preserves stock", function()
    local h, money = mockHusbandry(), 0
    local source = APD.source(h, 7)
    APDDistribution.sell(source, 0, function() error("credited") end)
    near(source.available(), 100)
    APDDistribution.sell(source, 1.8, function(value) money = money + value; return value end)
    APDDistribution.sell(source, 1.8, function(value) money = money + value; return value end)
    near(money, 180); near(source.available(), 0)
end)
test("milk adapter handles actual tank amounts", function()
    local h = mockHusbandry()
    h.spec_husbandry = {storage = mockStorage(50, 100)}
    h.spec_husbandryMilk = {hasMilkProduction = true, fillTypes = {4}}
    local source = APD.source(h, 4)
    near(source.take(80), 50); source.put(20); near(source.available(), 20)
    assert(APD.supports(h, 4))
end)
test("spawning hides only managed output and restores it", function()
    local h = mockHusbandry()
    APD.applyMode(h, 7, 2)
    APD.updatePallets(h, function(p)
        assert(p.spec_husbandryPallets.pendingLiters[7] == 0)
        p.spec_husbandryPallets.pendingLiters[8] = 0
    end)
    near(h.spec_husbandryPallets.pendingLiters[7], 100)
    near(h.spec_husbandryPallets.pendingLiters[8], 0)
end)
test("spawner exception restores pending stock", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 1)
    local ok = pcall(APD.updatePallets, h, function() error("spawn failed") end)
    assert(not ok); near(h.spec_husbandryPallets.pendingLiters[7], 100)
end)
test("in-flight callback cannot consume managed output", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 2)
    APD.getPalletCallback(h, function(p, pallet, result, fillType)
        assert(fillType == 7); near(p.spec_husbandryPallets.pendingLiters[7], 0)
        APD.updatePallets(p, function() end)
    end, {}, 0, 7)
    near(h.spec_husbandryPallets.pendingLiters[7], 100)
end)
test("store mode resumes native spawning", function()
    local h = mockHusbandry(); local calls = 0
    h.updatePallets = function() calls = calls + 1 end
    APD.applyMode(h, 7, 1); assert(calls == 0)
    APD.applyMode(h, 7, 0); assert(calls == 1)
end)
test("save and reload uses fill type names", function()
    local h, xml = mockHusbandry(), mockXML()
    APD.applyMode(h, 7, 2)
    APD.saveToXMLFile(h, xml, "barn.apd")
    assert(xml.values["barn.apd.product(0)#fillType"] == "TYPE_7")
    local loaded = mockHusbandry()
    APD.loadFromXMLFile(loaded, xml, "barn.apd", false)
    assert(APD.mode(loaded, 7) == 2 and APD.mode(loaded, 8) == 0)
    local reset = mockHusbandry(); APD.loadFromXMLFile(reset, xml, "barn.apd", true)
    assert(APD.mode(reset, 7) == 0)
end)
test("invalid save values fall back to storing", function()
    local h, xml = mockHusbandry(), mockXML()
    xml:setValue("barn.product(0)#fillType", "TYPE_7"); xml:setValue("barn.product(0)#mode", 999)
    xml:setValue("barn.product(1)#fillType", "UNKNOWN"); xml:setValue("barn.product(1)#mode", 1)
    APD.loadFromXMLFile(h, xml, "barn", false)
    assert(APD.mode(h, 7) == 0)
end)
test("join stream restores individual product modes", function()
    local h, c, stream = mockHusbandry(), mockHusbandry(), {}
    c.isServer = false; APD.applyMode(h, 7, 1); APD.applyMode(h, 8, 2)
    APD.onWriteStream(h, stream, {}); APD.onReadStream(c, stream, {})
    assert(APD.mode(c, 7) == 1 and APD.mode(c, 8) == 2 and #stream == 0)
end)
test("server rejects cross-farm requests and bad modes", function()
    local h = mockHusbandry()
    local connection = {farmId = 2, getIsServer = function() return false end}
    APDModeEvent.new(h, 7, 1):run(connection); assert(APD.mode(h, 7) == 0)
    connection.farmId = 1
    APDModeEvent.new(h, 7, 3):run(connection); assert(APD.mode(h, 7) == 0)
    g_currentMission.allowed = false
    APDModeEvent.new(h, 7, 1):run(connection); assert(APD.mode(h, 7) == 0)
    g_currentMission.allowed = true
    local before = g_server.count
    APDModeEvent.new(h, 7, 1):run(connection)
    assert(APD.mode(h, 7) == 1 and g_server.count == before + 1)
end)
test("event serialization and authoritative client application", function()
    local h, stream = mockHusbandry(), {}
    h.isServer = false
    APDModeEvent.new(h, 7, 2):writeStream(stream, {})
    APDModeEvent.emptyNew():readStream(stream, {getIsServer = function() return true end})
    assert(APD.mode(h, 7) == 2 and #stream == 0)
end)
test("deleted and unowned husbandries cannot be managed", function()
    local h = mockHusbandry(); h.farmId = 0; assert(not APD.canManage(h))
    h.farmId = 1; APD.onDelete(h); assert(not APD.canManage(h))
    assert(not APD.applyMode(h, 7, 1))
end)
test("ownership changes reset modes", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 2); h.farmId = 2; APD.onOwnerChanged(h)
    assert(APD.mode(h, 7) == 0)
end)
test("only same-farm accepting production points receive goods", function()
    local h = mockHusbandry()
    local function point(farm, accepts)
        return {getOwnerFarmId = function() return farm end, storage = mockStorage(0, 500),
            inputFillTypeIds = {[7] = accepts}, owningPlaceable = {rootNode = 20}}
    end
    local good, foreign, wrong = point(1, true), point(2, true), point(1, false)
    g_currentMission.productionChainManager = {getProductionPointsForFarmId = function() return {good, foreign, wrong} end}
    assert(#APD.targets(h, 7) == 1)
    APD.applyMode(h, 7, 2); g_currentMission.money = 0
    APD.processHour(h)
    near(good.storage.amount, 100); near(foreign.storage.amount, 0); near(wrong.storage.amount, 0)
    near(g_currentMission.money, -100 * 100 * 0.000035)
end)
test("clients never process balances", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 1); h.isServer = false
    g_currentMission.money = 0; APD.processHour(h)
    near(g_currentMission.money, 0); near(h.spec_husbandryPallets.pendingLiters[7], 100)
end)
test("hourly sale preserves other output and uses native factor", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 1)
    g_currentMission.money = 0; APD.processHour(h); APD.processHour(h)
    near(g_currentMission.money, 180); near(h.spec_husbandryPallets.pendingLiters[8], 40)
end)
test("specialization registration works with a proxy and is idempotent", function()
    local entry = {specializations = {PlaceableHusbandryMilk}, specializationsByName = {}}
    local calls = 0
    local manager = {typeName = "placeable", types = {barn = entry}, addSpecialization = function(_, _, name)
        entry.specializationsByName[name] = true; calls = calls + 1
    end}
    TypeManager.validateTypes(manager); TypeManager.validateTypes(manager); assert(calls == 1)
    manager.typeName = "vehicle"; TypeManager.validateTypes(manager); assert(calls == 1)
end)
test("animal menu opens product and mode dialogs, cancel is harmless", function()
    local h = mockHusbandry()
    local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); assert(#frame.menuButtonInfo == 1)
    frame.menuButtonInfo[1].callback(); assert(#OptionDialog.options == 2)
    OptionDialog.callback(0); assert(APD.mode(h, 7) == 0)
    frame.menuButtonInfo[1].callback(); OptionDialog.callback(1)
    assert(#OptionDialog.options == 3)
    OptionDialog.callback(3); assert(APD.mode(h, 7) == 2)
end)
test("disabled mod leaves native animal menu alone", function()
    g_modIsLoaded[g_currentModName] = false
    local frame = {selectedHusbandry = mockHusbandry(), setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame)
    assert(#frame.menuButtonInfo == 0)
    g_modIsLoaded[g_currentModName] = true
end)
test("load restores modes before owner assignment without resetting them", function()
    local saved, xml = mockHusbandry(), mockXML()
    APD.applyMode(saved, 7, 2); APD.saveToXMLFile(saved, xml, "barn")
    local loaded = mockHusbandry(); APD.onLoad(loaded)
    APD.loadFromXMLFile(loaded, xml, "barn", false)
    loaded.farmId = 2; APD.onOwnerChanged(loaded)
    APD.onLoadFinished(loaded); APD.onPostFinalizePlacement(loaded)
    assert(APD.mode(loaded, 7) == 2)
    APD.onOwnerChanged(loaded); assert(APD.mode(loaded, 7) == 2)
    loaded.farmId = 1; APD.onOwnerChanged(loaded); assert(APD.mode(loaded, 7) == 0)
end)
test("unfinished and missing-farm husbandries never settle", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 1)
    g_currentMission.money = 0; h.apdState.ready = false; APD.processHour(h)
    h.apdState.ready = true; h.farmId = 99; APD.processHour(h)
    near(g_currentMission.money, 0); near(APD.source(h, 7).available(), 100)
end)
test("reusing save XML cannot resurrect stale product modes", function()
    local h, xml = mockHusbandry(), mockXML()
    APD.applyMode(h, 7, 2); APD.applyMode(h, 8, 1); APD.saveToXMLFile(h, xml, "barn")
    APD.applyMode(h, 7, 0); APD.applyMode(h, 8, 0); APD.saveToXMLFile(h, xml, "barn")
    APD.loadFromXMLFile(h, xml, "barn", false)
    assert(APD.mode(h, 7) == 0 and APD.mode(h, 8) == 0)
end)
test("credit failure before mutation refunds inventory", function()
    local h, original = mockHusbandry(), g_currentMission.addMoney
    APD.applyMode(h, 7, 1); g_currentMission.money = 0
    g_currentMission.addMoney = function() error("rejected before credit") end
    APD.processHour(h); near(APD.source(h, 7).available(), 100); near(g_currentMission.money, 0)
    g_currentMission.addMoney = original
    APD.processHour(h); near(APD.source(h, 7).available(), 0); near(g_currentMission.money, 180)
end)
test("credit exception after mutation never refunds paid product", function()
    local h, original = mockHusbandry(), g_currentMission.addMoney
    APD.applyMode(h, 7, 1); g_currentMission.money = 0
    g_currentMission.addMoney = function(self, amount) self.money = self.money + amount; error("HUD error") end
    APD.processHour(h); APD.processHour(h)
    near(APD.source(h, 7).available(), 0); near(g_currentMission.money, 180)
    g_currentMission.addMoney = original
end)
test("silent no-op and partial credit preserve unpaid product", function()
    local h, original = mockHusbandry(), g_currentMission.addMoney
    APD.applyMode(h, 7, 1); g_currentMission.money = 0
    g_currentMission.addMoney = function() end
    APD.processHour(h); near(APD.source(h, 7).available(), 100)
    g_currentMission.addMoney = function(self, amount) self.money = self.money + amount / 2 end
    APD.processHour(h); near(APD.source(h, 7).available(), 50); near(g_currentMission.money, 90)
    g_currentMission.addMoney = original
end)
test("reentrant money notification cannot settle another output twice", function()
    local h, original = mockHusbandry(), g_currentMission.addMoney
    APD.applyMode(h, 7, 1); APD.applyMode(h, 8, 1); g_currentMission.money = 0
    g_currentMission.addMoney = function(self, amount)
        self.money = self.money + amount; APD.processHour(h)
    end
    APD.processHour(h); near(g_currentMission.money, 252)
    near(APD.source(h, 7).available(), 0); near(APD.source(h, 8).available(), 0)
    assert(not h.apdState.processing)
    g_currentMission.addMoney = original
end)
local function receiver(storage)
    return {getOwnerFarmId = function() return 1 end, ownerFarmId = 1,
        storage = storage, inputFillTypeIds = {[7] = true}, owningPlaceable = {rootNode = 20}}
end
local function receiverList(points)
    g_currentMission.productionChainManager = {getProductionPointsForFarmId = function() return points end}
end
test("destination failures before and after mutation conserve product", function()
    for _, accepted in ipairs({0, 20}) do
        local h, storage = mockHusbandry(), mockStorage(0, 500)
        APD.applyMode(h, 7, 2); g_currentMission.money = 0
        storage.setFillLevel = function(self) self.amount = self.amount + accepted; error("listener error") end
        receiverList({receiver(storage)}); APD.processHour(h)
        near(APD.source(h, 7).available() + storage.amount, 100)
        near(storage.amount, accepted); near(g_currentMission.money, -accepted * 100 * 0.000035)
    end
end)
test("unpaid delivery restores goods and paid callback errors do not duplicate fees", function()
    local original = g_currentMission.addMoney
    for _, paid in ipairs({false, true}) do
        local h, storage = mockHusbandry(), mockStorage(0, 500)
        APD.applyMode(h, 7, 2); g_currentMission.money = 0; receiverList({receiver(storage)})
        g_currentMission.addMoney = function(self, amount)
            if paid then self.money = self.money + amount end
            error("money callback error")
        end
        APD.processHour(h)
        near(APD.source(h, 7).available() + storage.amount, 100)
        near(storage.amount, paid and 100 or 0)
        near(g_currentMission.money, paid and -0.35 or 0)
    end
    g_currentMission.addMoney = original
end)
test("duplicate receiver entries do not bias capacity shares", function()
    local h, a, b = mockHusbandry(), mockStorage(0, 100), mockStorage(0, 100)
    local pa, pb = receiver(a), receiver(b)
    receiverList({pa, pa, pb}); APD.applyMode(h, 7, 2); APD.processHour(h)
    near(a.amount, 50); near(b.amount, 50)
    h.spec_husbandry = {storage = a}; assert(#APD.targets(h, 7) == 1)
end)
test("failed refund is saved separately and recovered exactly once", function()
    local h = mockHusbandry()
    local storage, xml = mockStorage(100, 100), mockXML()
    h.spec_husbandry = {storage = storage}
    h.spec_husbandryMilk = {hasMilkProduction = true, fillTypes = {4}}
    local set = storage.setFillLevel
    storage.setFillLevel = function(self, value)
        if value > self.amount then error("cannot return to tank") end
        set(self, value)
    end
    local source = APD.source(h, 4)
    APDDistribution.sell(source, 2, function() return 0 end)
    near(storage.amount, 0); near(source.available(), 100); near(h.apdState.refunds[4], 100)
    APD.saveToXMLFile(h, xml, "barn")
    local loaded = mockHusbandry()
    loaded.spec_husbandry = {storage = mockStorage(storage.amount, 100)}
    loaded.spec_husbandryMilk = h.spec_husbandryMilk
    APD.loadFromXMLFile(loaded, xml, "barn", false)
    APD.processHour(loaded); APD.processHour(loaded)
    near(loaded.spec_husbandry.storage.amount, 100); near(loaded.apdState.refunds[4], 0)
    near(APD.source(loaded, 4).available(), 100)
end)
test("settlement cannot run while native pallet stock is temporarily hidden", function()
    local h = mockHusbandry(); APD.applyMode(h, 7, 1); APD.applyMode(h, 8, 1)
    g_currentMission.money = 0
    APD.updatePallets(h, function() APD.processHour(h) end)
    near(APD.source(h, 7).available(), 100); near(g_currentMission.money, 0)
    assert(h.apdState.palletDepth == 0)
end)
test("nonfinite prices cannot corrupt balances or stock", function()
    local source = APD.source(mockHusbandry(), 7)
    for _, price in ipairs({math.huge, -math.huge, 0/0}) do
        near(APDDistribution.sell(source, price, function() error("must not credit") end), 0)
        near(source.available(), 100)
    end
end)
print(string.format("%d behavioral tests passed", passed))
