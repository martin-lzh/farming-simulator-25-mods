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
test("animal menu edits all products in one dialog and cancel discards drafts", function()
    local h = mockHusbandry()
    local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); assert(#frame.menuButtonInfo == 1)
    local shows = g_gui.shows
    frame.menuButtonInfo[1].callback()
    local dialog = g_gui.dialog
    assert(g_gui.shows == shows + 1 and #dialog.rows == 2)
    assert(g_gui.previousGui == "InGameMenu", "lazy GUI loading lost parent focus")
    dialog.rows[1].option:setState(3); dialog.rows[2].option:setState(2)
    assert(APD.mode(h, 7) == 0 and APD.mode(h, 8) == 0)
    dialog:onClickBack()
    assert(FocusManager.currentGui == "InGameMenu")
    assert(APD.mode(h, 7) == 0 and APD.mode(h, 8) == 0)
    frame.menuButtonInfo[1].callback()
    assert(dialog.rows[1].option:getState() == 1)
    dialog.rows[1].option:setState(3); dialog.rows[2].option:setState(2)
    dialog:onClickOk()
    assert(g_gui.shows == shows + 2)
    assert(APD.mode(h, 7) == 2 and APD.mode(h, 8) == 1)
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
-- A synchronous notification may make a separate balance change after the
-- engine books this transaction, then throw. These are distinct ledger entries.
local function moneyScenario(body)
    local add, publish, balance = g_currentMission.addMoney, g_messageCenter.publish, g_currentMission.money
    local ledger = {sales = 0, fees = 0, notifications = 0}
    g_currentMission.money = 6000
    g_currentMission.addMoney = function(self, amount, farmId)
        self.money = self.money + amount
        if amount > 0 then ledger.sales = ledger.sales + amount else ledger.fees = ledger.fees - amount end
        g_messageCenter:publish(MessageType.MONEY_CHANGED, farmId, self.money)
    end
    local notify = function(_, messageType, farmId)
        if messageType == MessageType.MONEY_CHANGED then
            ledger.notifications = ledger.notifications + 1
            if ledger.listener ~= nil then ledger.listener(farmId) end
        end
    end
    g_messageCenter.publish = notify
    body(ledger)
    assert(g_messageCenter.publish == notify, "money observer leaked beyond settlement")
    g_currentMission.addMoney, g_messageCenter.publish, g_currentMission.money = add, publish, balance
end

test("sale ignores synchronous loan and repayment even when notification throws", function()
    for _, change in ipairs({-5000, 5000}) do
        for _, fails in ipairs({false, true}) do
            moneyScenario(function(ledger)
                local h = mockHusbandry(); APD.applyMode(h, 7, 1)
                ledger.listener = function()
                    g_currentMission.money = g_currentMission.money + change
                    if fails then error("subscriber failed after separate transaction") end
                end
                APD.processHour(h); APD.processHour(h)
                near(ledger.sales, 180); near(APD.source(h, 7).available(), 0)
                near(g_currentMission.money, 6000 + 180 + change)
                assert(ledger.notifications == 1 and not h.apdState.processing)
            end)
        end
    end
end)
test("delivery keeps paid goods when a balance subscriber borrows or repays", function()
    for _, change in ipairs({-5000, 5000}) do
        for _, fails in ipairs({false, true}) do
            moneyScenario(function(ledger)
                local h, storage = mockHusbandry(), mockStorage(0, 2000)
                h.spec_husbandryPallets.pendingLiters[7] = 1000
                APD.applyMode(h, 7, 2); receiverList({receiver(storage)})
                ledger.listener = function()
                    g_currentMission.money = g_currentMission.money + change
                    if fails then error("subscriber failed after separate transaction") end
                end
                APD.processHour(h); APD.processHour(h)
                near(ledger.fees, 3.5); near(storage.amount, 1000)
                near(APD.source(h, 7).available(), 0); near(g_currentMission.money, 6000 - 3.5 + change)
            end)
        end
    end
end)
test("nested notifications and another husbandry settlement are counted once", function()
    moneyScenario(function(ledger)
        local a, b = mockHusbandry(), mockHusbandry()
        APD.applyMode(a, 7, 1); APD.applyMode(b, 7, 1)
        local entered = false
        ledger.listener = function(farmId)
            if entered then return end
            entered = true
            g_currentMission.money = g_currentMission.money - 5000
            g_messageCenter:publish(MessageType.MONEY_CHANGED, farmId, g_currentMission.money)
            APD.processHour(b)
        end
        APD.processHour(a); APD.processHour(a); APD.processHour(b)
        near(ledger.sales, 360); near(g_currentMission.money, 6000 + 360 - 5000)
        near(APD.source(a, 7).available(), 0); near(APD.source(b, 7).available(), 0)
    end)
end)
test("subscriber side effects do not turn a rejected credit into a sale", function()
    moneyScenario(function(ledger)
        local h = mockHusbandry(); APD.applyMode(h, 7, 1)
        local add = g_currentMission.addMoney
        ledger.listener = function() g_currentMission.money = g_currentMission.money + 5000 end
        g_currentMission.addMoney = function(_, _, farmId)
            g_messageCenter:publish(MessageType.MONEY_CHANGED, farmId, g_currentMission.money)
            error("rejected before sale credit")
        end
        APD.processHour(h)
        near(APD.source(h, 7).available(), 100); near(ledger.sales, 0)
        g_currentMission.addMoney = add
    end)
end)
test("nested other-farm settlement and unrelated events remain isolated", function()
    local add, publish, getFarm = g_currentMission.addMoney, g_messageCenter.publish, g_farmManager.getFarmById
    local balances, farms = {[1] = 6000, [2] = 3000}, {}
    for id = 1, 2 do
        local farmId = id
        farms[id] = {getBalance = function() return balances[farmId] end}
    end
    g_farmManager.getFarmById = function(_, id) return farms[id] end
    local nested, custom = 0, 0
    local notify = function(_, messageType, ...)
        local farmId = select(1, ...)
        if messageType == MessageType.MONEY_CHANGED then
            if farmId == 1 then
                nested = APD.changeMoney(2, 90, MoneyType.SOLD_PRODUCTS)
            else
                balances[2] = balances[2] - 1000
            end
        else
            assert(messageType == "CUSTOM" and select("#", ...) == 3)
            local a, b, c = ...
            assert(a == 1 and b == nil and c == "tail")
            custom = custom + 1
            return "first", "second"
        end
    end
    g_messageCenter.publish = notify
    g_currentMission.addMoney = function(_, amount, farmId)
        balances[farmId] = balances[farmId] + amount
        local a, b = g_messageCenter:publish("CUSTOM", 1, nil, "tail")
        assert(a == "first" and b == "second")
        g_messageCenter:publish(MessageType.MONEY_CHANGED, farmId, balances[farmId])
    end
    near(APD.changeMoney(1, 180, MoneyType.SOLD_PRODUCTS), 180)
    near(nested, 90); near(balances[1], 6180); near(balances[2], 2090)
    assert(custom == 2 and g_messageCenter.publish == notify)
    g_currentMission.addMoney, g_messageCenter.publish, g_farmManager.getFarmById = add, publish, getFarm
end)
test("ownership reset restarts pending pallets once on the ready server", function()
    for _, server in ipairs({false, true}) do
        local h, calls = mockHusbandry(), 0
        h.isServer = server; APD.applyMode(h, 7, 2)
        h.updatePallets = function(self)
            calls = calls + 1
            assert(APD.mode(self, 7) == 0 and self.apdState.ownerFarmId == 2)
            APD.onOwnerChanged(self) -- Same-owner notification must not recurse.
        end
        h.farmId = 2; APD.onOwnerChanged(h); APD.onOwnerChanged(h)
        assert(calls == (server and 1 or 0)); near(APD.source(h, 7).available(), 100)
    end
end)
test("loading owner assignment preserves modes without spawning pallets", function()
    local h = mockHusbandry(); APD.onLoad(h); APD.applyMode(h, 7, 2)
    h.updatePallets = function() error("must not spawn during load") end
    h.farmId = 2; APD.onOwnerChanged(h)
    assert(APD.mode(h, 7) == 2)
    APD.onLoadFinished(h); APD.onPostFinalizePlacement(h); APD.onOwnerChanged(h)
end)
test("callback mode or owner changes resume stock after all pallet masks unwind", function()
    for _, ownerChange in ipairs({false, true}) do
        for _, nested in ipairs({false, true}) do
            local h, spawned = mockHusbandry(), {[7] = 0, [8] = 0}
            h.spec_husbandryPallets.pendingLiters[7] = 3000
            APD.applyMode(h, 7, 2); APD.applyMode(h, 8, 2)
            h.updatePallets = function(self)
                APD.updatePallets(self, function(p)
                    for fillType, amount in pairs(p.spec_husbandryPallets.pendingLiters) do
                        if amount > 5 then
                            spawned[fillType] = spawned[fillType] + amount
                            p.spec_husbandryPallets.pendingLiters[fillType] = 0
                        end
                    end
                end)
            end
            local callback = function(p)
                assert(p.spec_husbandryPallets.pendingLiters[7] == 0)
                if ownerChange then p.farmId = 2; APD.onOwnerChanged(p)
                else APD.applyMode(p, 7, APDDistribution.KEEP) end
                near(spawned[7], 0) -- Stock is still masked until the callback returns.
            end
            if nested then
                APD.updatePallets(h, function(p) APD.getPalletCallback(p, callback, {}, 0, 7) end)
            else
                APD.getPalletCallback(h, callback, {}, 0, 7)
            end
            near(spawned[7], 3000) -- Resumed without waiting for another hour/update.
            h:updatePallets() -- No duplicate recovery on a later update.
            near(spawned[7], 3000); near(APD.source(h, 7).available(), 0)
            near(spawned[8], ownerChange and 40 or 0)
            near(APD.source(h, 8).available(), ownerChange and 0 or 40)
            assert(h.apdState.palletDepth == 0)
        end
    end
end)
test("money observer restores inherited publisher without freezing its class", function()
    local originalCenter, add, balance = g_messageCenter, g_currentMission.addMoney, g_currentMission.money
    for _, fails in ipairs({false, true}) do
        local class = {publish = function() if fails then error("listener failure") end end}
        g_messageCenter = setmetatable({}, {__index = class})
        g_currentMission.addMoney = function(self, amount, farmId)
            self.money = self.money + amount
            g_messageCenter:publish(MessageType.MONEY_CHANGED, farmId, self.money)
        end
        near(APD.changeMoney(1, 180, MoneyType.SOLD_PRODUCTS), 180)
        assert(rawget(g_messageCenter, "publish") == nil)
        class.publish = function() return "replacement" end
        assert(g_messageCenter:publish("CUSTOM") == "replacement")
    end
    g_messageCenter, g_currentMission.addMoney, g_currentMission.money = originalCenter, add, balance
end)
test("each product row uses native production mode translations", function()
    local getText = g_i18n.getText
    g_i18n.getText = function(_, key, customMod)
        if key:find("ui_production_output_", 1, true) then
            assert(customMod == nil, "native key resolved in mod namespace")
            return "native:" .. key
        end
        assert(key ~= "apd_store" and key ~= "apd_sell" and key ~= "apd_distribute")
        return key
    end
    local frame = {selectedHusbandry = mockHusbandry(), setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
    for _, row in ipairs(g_gui.dialog.rows) do
        for i, suffix in ipairs({"storing", "selling", "distributing"}) do
            assert(row.option.texts[i] == "native:ui_production_output_" .. suffix)
        end
    end
    g_gui.dialog:onClickBack()
    g_i18n.getText = getText
end)

test("dialog confirms only edited rows and cannot submit twice", function()
    local h = mockHusbandry()
    local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
    local dialog, count = g_gui.dialog, g_server.count
    -- A different player changes an untouched row while this window is open.
    APD.applyMode(h, 8, 1)
    dialog.rows[1].option:setState(3)
    dialog:onClickOk(); dialog:onClickOk()
    assert(APD.mode(h, 7) == 2 and APD.mode(h, 8) == 1)
    assert(g_server.count == count + 1)
    frame.menuButtonInfo[1].callback()
    assert(dialog.rows[1].option:getState() == 3 and dialog.rows[2].option:getState() == 2)
    dialog:onClickOk()
    assert(g_server.count == count + 1)
end)

test("dialog rechecks permission deletion and original ownership at confirmation", function()
    for _, change in ipairs({"permission", "delete", "owner"}) do
        local h = mockHusbandry()
        local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
        InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
        local dialog, count = g_gui.dialog, g_server.count
        dialog.rows[1].option:setState(3)
        if change == "permission" then g_currentMission.allowed = false end
        if change == "delete" then h.apdState.deleted = true end
        if change == "owner" then h.farmId = 2; g_currentMission.farmId = 2 end
        dialog:onClickOk()
        assert(APD.mode(h, 7) == 0 and g_server.count == count)
        g_currentMission.allowed, g_currentMission.farmId = true, 1
    end
end)

test("dialog reuse refreshes rows without retaining previous husbandry", function()
    local first, second = mockHusbandry(), mockHusbandry()
    second.spec_husbandryPallets.fillTypes = {8}
    APD.applyMode(second, 8, 1)
    local frame = {selectedHusbandry = first, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
    local dialog, loads = g_gui.dialog, g_gui.loads
    local oldRow = dialog.rows[1].element
    dialog:onClickBack()
    assert(oldRow.deleted and #dialog.productRows.elements == 0)
    assert(dialog.entries == nil and dialog.confirmCallback == nil)
    frame.selectedHusbandry = second; frame.menuButtonInfo[1].callback()
    assert(g_gui.loads == loads and #dialog.rows == 1)
    assert(dialog.rows[1].element.label.text == "Product 8")
    assert(dialog.rows[1].option:getState() == 2)
    dialog.rows[1].option:setState(3); dialog:onClickOk()
    assert(APD.mode(second, 8) == 2 and APD.mode(first, 8) == 0)
end)

test("dialog batches client requests without locally changing modes", function()
    local h, sent, previousClient = mockHusbandry(), {}, g_client
    h.isServer = false
    g_client = {getServerConnection = function() return {sendEvent = function(_, event)
        table.insert(sent, event)
    end} end}
    local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
    g_gui.dialog.rows[1].option:setState(2); g_gui.dialog.rows[2].option:setState(3)
    g_gui.dialog:onClickOk()
    assert(#sent == 2 and sent[1].mode == 1 and sent[2].mode == 2)
    assert(APD.mode(h, 7) == 0 and APD.mode(h, 8) == 0)
    g_client = previousClient
end)

test("dialog ignores opening key repeat and supports more than four products", function()
    local h = mockHusbandry()
    h.spec_husbandryPallets.fillTypes = {7, 8, 9, 10, 11, 12}
    local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
    local dialog = g_gui.dialog
    assert(#dialog.rows == 6 and FocusManager.focused == dialog.rows[1].option)
    dialog.time = dialog.inputDelay
    dialog.rows[6].option:setState(3)
    assert(dialog:onClickOk() and dialog:onClickBack() and dialog.isOpen)
    dialog.time = dialog.inputDelay + 1
    dialog:onClickOk()
    assert(APD.mode(h, 12) == 2)
end)
test("product rows fit the clipping viewport and height follows visible products", function()
    local heights = {}
    for _, count in ipairs({1, 2, 4, 6, 1}) do
        local h = mockHusbandry()
        h.spec_husbandryPallets.fillTypes = {}
        for i = 1, count do table.insert(h.spec_husbandryPallets.fillTypes, i + 6) end
        local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
        InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
        local dialog = g_gui.dialog
        assert(#dialog.rows == count)
        for _, row in ipairs(dialog.rows) do
            assert(row.element.size[1] <= dialog.productRows.absSize[1], "right arrow clipped by viewport")
        end
        local visibleHeight = dialog.productRows.size[2]
        near(visibleHeight, math.min(count, 4) * dialog.rows[1].element.size[2])
        if heights[count] ~= nil then near(dialog.dialogElement.size[2], heights[count]) end
        heights[count] = dialog.dialogElement.size[2]
        dialog:onClickBack()
    end
    assert(heights[1] < heights[2] and heights[2] < heights[4])
    near(heights[4], heights[6])
    local dialog = g_gui.dialog
    dialog.explanationElement.measuredHeight = 72 / 1080
    local h = mockHusbandry(); h.spec_husbandryPallets.fillTypes = {7}
    local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
    assert(dialog.dialogElement.size[2] > heights[1], "wrapped explanation overlaps products")
    near(dialog.productRows.size[2], dialog.rows[1].element.size[2])
    dialog:onClickBack(); dialog.explanationElement.measuredHeight = nil
end)
test("goat and sheep barns show only their own native active products", function()
    local goats, sheep = mockHusbandry(), mockHusbandry()
    goats.spec_husbandryPallets.activeFillTypes = {8}
    sheep.spec_husbandryPallets.activeFillTypes = {7}
    local frame = {selectedHusbandry = goats, setMenuButtonInfoDirty = function() end}
    for _, selection in ipairs({{goats, 8}, {sheep, 7}, {goats, 8}}) do
        frame.selectedHusbandry = selection[1]
        InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
        assert(#g_gui.dialog.rows == 1)
        assert(g_gui.dialog.rows[1].element.label.text == "Product " .. selection[2])
        g_gui.dialog.rows[1].option:setState(3); g_gui.dialog:onClickOk()
    end
    assert(APD.mode(goats, 7) == 0 and APD.mode(goats, 8) == 2)
    assert(APD.mode(sheep, 7) == 2 and APD.mode(sheep, 8) == 0)
end)

test("mixed herds show both products and animal changes refresh reopened rows", function()
    local h = mockHusbandry()
    h.spec_husbandryPallets.activeFillTypes = {8, 7}
    local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame); frame.menuButtonInfo[1].callback()
    assert(#g_gui.dialog.rows == 2)
    g_gui.dialog:onClickBack()
    h.spec_husbandryPallets.activeFillTypes = {8}
    frame.menuButtonInfo[1].callback()
    assert(#g_gui.dialog.rows == 1 and g_gui.dialog.rows[1].element.label.text == "Product 8")
    g_gui.dialog:onClickBack()
end)

test("native milk activity selects subtype output even at zero production", function()
    local h = mockHusbandry()
    h.spec_husbandryPallets.activeFillTypes = {}
    h.spec_husbandryMilk = {hasMilkProduction = true, fillTypes = {4, 5},
        activeFillTypes = {5}, litersPerHour = {[4] = 0, [5] = 0}}
    local products = APD.products(h, true)
    assert(#products == 1 and products[1] == 5)
    h.spec_husbandryMilk.hasMilkProduction = false
    assert(#APD.products(h, true) == 0)
end)

test("empty native activity hides the entry without falling back to all products", function()
    local h = mockHusbandry()
    h.spec_husbandryPallets.activeFillTypes = {}
    local frame = {selectedHusbandry = h, setMenuButtonInfoDirty = function() end}
    InGameMenuAnimalsFrame.updateMenuButtons(frame)
    assert(#frame.menuButtonInfo == 0 and #APD.products(h, true) == 0)
    assert(#APD.products(h) == 2)
end)

test("missing activity metadata falls back to supported products and lists deduplicate", function()
    local h = mockHusbandry()
    assert(#APD.products(h, true) == 2)
    h.spec_husbandryPallets.activeFillTypes = {8, 8, 999}
    h.spec_husbandryMilk = {hasMilkProduction = true, fillTypes = {8, 8}, activeFillTypes = {8}}
    local products = APD.products(h, true)
    assert(#products == 1 and products[1] == 8)
end)

test("hiding inactive outputs preserves modes refunds and the complete join stream", function()
    local h, xml = mockHusbandry(), mockXML()
    h.spec_husbandryPallets.activeFillTypes = {8}
    APD.applyMode(h, 7, 2); APD.applyMode(h, 8, 1)
    h.apdState.refunds[7] = 12
    APD.saveToXMLFile(h, xml, "barn")
    local loaded = mockHusbandry()
    loaded.spec_husbandryPallets.activeFillTypes = {}
    APD.loadFromXMLFile(loaded, xml, "barn", false)
    assert(APD.mode(loaded, 7) == 2 and APD.mode(loaded, 8) == 1)
    near(loaded.apdState.refunds[7], 12)
    local stream, client = {}, mockHusbandry()
    client.isServer = false
    client.spec_husbandryPallets.activeFillTypes = {}
    APD.onWriteStream(loaded, stream); APD.onReadStream(client, stream)
    assert(APD.mode(client, 7) == 2 and APD.mode(client, 8) == 1)
    client.spec_husbandryPallets.activeFillTypes = {7}
    assert(APD.products(client, true)[1] == 7 and APD.mode(client, 7) == 2)
end)

test("inactive leftover inventory still settles once using its saved mode", function()
    local h = mockHusbandry()
    h.spec_husbandryPallets.activeFillTypes = {8}
    APD.applyMode(h, 7, 1)
    g_currentMission.money = 0
    APD.processHour(h); APD.processHour(h)
    near(g_currentMission.money, 180)
    near(h.spec_husbandryPallets.pendingLiters[7], 0)
    near(h.spec_husbandryPallets.pendingLiters[8], 40)
    assert(APD.products(h, true)[1] == 8)
end)
print(string.format("%d behavioral tests passed", passed))
