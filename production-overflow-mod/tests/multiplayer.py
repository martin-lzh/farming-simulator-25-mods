"""Independent Lua peers using the real Mod event over a deterministic ordered transport.

Engine objects, permissions and network delivery are contract doubles. This does not
emulate GIANTS object creation, the native pause during a join or ghost objects.
"""
from collections import deque
from math import isclose

from lupa import LuaRuntime

SETUP = """
    PO = ProductionOverflow
    factory = mockPoint()
    target = mockPoint({inputs = {[7] = true, [9] = true}, capacity = 600})
    factory.isServer, factory.networkId = serverPeer, 42
    target.isServer, target.networkId = serverPeer, 43
    objects = {[42] = factory, [43] = target}
    manager = setmetatable({isServer = serverPeer, productionPoints = {factory, target}}, {__index = ProductionChainManager})
    serverConnection = {getIsServer = function() return true end}
    managers = {
        {farmId = 1, allowed = true, getIsServer = function() return false end},
        {farmId = 1, allowed = true, getIsServer = function() return false end}
    }
    NetworkUtil.writeNodeObject = function(stream, object) streamWriteUInt8(stream, object.networkId) end
    NetworkUtil.readNodeObject = function(stream) return objects[streamReadUInt8(stream)] end
    local function send(event)
        local packet = {}
        event:writeStream(packet, nil)
        capturePacket("mode", packet)
    end
    if serverPeer then
        g_server.broadcastEvent = function(_, event, sendLocal, ignoreConnection)
            assert(not sendLocal and ignoreConnection == nil, "the server must reach every client")
            send(event)
        end
    else
        g_server = nil
        serverConnection.sendEvent = function(self, event) send(event) end
        g_client = {getServerConnection = function() return serverConnection end}
    end
    function receive(packet, from)
        POModeEvent.emptyNew():readStream(packet, from and managers[from] or serverConnection)
    end
    -- Native ProductionPointOutputModeEvent: set with noEventSend on every receiver.
    function flushNative()
        for _, entry in ipairs(g_nativeModeEvents) do
            capturePacket("native", {entry.point.networkId, entry.fillType, entry.mode})
        end
        g_nativeModeEvents = {}
    end
    function receiveNative(packet)
        objects[packet[1]]:setOutputDistributionMode(packet[2], packet[3], true)
    end
    function toggle(fillType)
        local frame = setmetatable({selectedProductionPoint = factory,
            selectedProduction = {primaryProductFillType = fillType}}, {__index = InGameMenuProductionFrame})
        frame:onButtonToggleOutputMode()
    end
    function request(fillType, mode) return PO.requestMode(factory, fillType, mode) end
    function mode(fillType) return PO.getMode(factory, fillType) end
    function hour()
        for _, point in ipairs(manager.productionPoints) do point:directlySellOutputs() end
        manager:distributeGoods()
    end
    function snapshot()
        local stream = {}
        factory:writeStream(stream, managers[1])
        ProductionOverflowPlaceable.onWriteStream(factory.owningPlaceable, stream, managers[1])
        return stream
    end
    function loadSnapshot(stream)
        factory:readStream(stream, serverConnection)
        ProductionOverflowPlaceable.onReadStream(factory.owningPlaceable, stream, serverConnection)
        assert(#stream == 0, "stream not fully read")
    end
"""


class Peer:
    def __init__(self, root, scripts, server=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.outgoing = deque()
        self.lua.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
        for name in scripts:
            self.lua.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
        self.lua.globals().serverPeer = server
        self.lua.globals().capturePacket = lambda kind, packet: self.outgoing.append(
            (kind, tuple(packet[index] for index in range(1, len(packet) + 1)))
        )
        self.lua.execute(SETUP)

    def run(self, code):
        self.lua.execute(code)
        self.lua.execute("flushNative()")

    def value(self, expression):
        return self.lua.eval(expression)

    def receive(self, kind, packet, sender=None):
        table = self.lua.table_from(packet)
        if kind == "mode":
            self.lua.globals().receive(table, sender)
        else:
            self.lua.globals().receiveNative(table)


class Session:
    def __init__(self, root, scripts):
        self.root, self.scripts = root, scripts
        self.server = Peer(root, scripts, server=True)
        self.clients = [Peer(root, scripts), Peer(root, scripts)]

    def peers(self):
        return [self.server, *self.clients]

    def deliver(self, client):
        peer = self.clients[client]
        while peer.outgoing:
            kind, packet = peer.outgoing.popleft()
            assert kind == "mode", "clients only send Mod requests"
            self.server.receive(kind, packet, client + 1)

    def broadcast(self):
        while self.server.outgoing:
            kind, packet = self.server.outgoing.popleft()
            for client in self.clients:
                client.receive(kind, packet)
        assert all(not client.outgoing for client in self.clients), "client echoed a server event"

    def modes(self, expected, fill_type=7):
        for peer in self.peers():
            actual = peer.value(f"mode({fill_type})")
            assert actual == expected, f"expected mode {expected}, got {actual}"


def run_multiplayer(root, scripts):
    count = 0

    def passed(name):
        nonlocal count
        count += 1
        print(f"PASS multiplayer: {name}")

    session = Session(root, scripts)
    a = session.clients[0]
    for expected in (1, 2, 3, 4, 0):
        a.run("toggle(7)")
        session.modes(expected - 1 if expected else 4)  # No client changes before the server's answer.
        session.deliver(0)
        session.broadcast()
        session.modes(expected)
    for expected in (1, 2, 4, 0):
        a.run("toggle(9)")
        session.deliver(0)
        session.broadcast()
        session.modes(expected, 9)
    passed("a client walks through all modes; liquids skip store-rest")

    for order in ((0, 1), (1, 0)):
        session = Session(root, scripts)
        a, b = session.clients
        a.run("request(7, 3)")
        b.run("request(7, 4)")
        session.modes(0)
        for client in order:
            session.deliver(client)
        session.broadcast()
        session.modes(3 if order[-1] == 0 else 4)
        passed(f"two managers, same product, server arrival order {order}")

    for host_last in (False, True):
        session = Session(root, scripts)
        session.clients[0].run("request(7, 4)")
        if host_last:
            session.deliver(0)
        session.server.run("request(7, 3)")
        if not host_last:
            session.deliver(0)
        session.broadcast()
        session.modes(3 if host_last else 4)
    passed("host and remote edits converge in either server execution order")

    for change in ("managers[1].allowed = false", "managers[1].farmId = 2",
                   "ProductionOverflowPlaceable.onDelete(factory.owningPlaceable)", "objects[42] = nil"):
        session = Session(root, scripts)
        session.clients[0].run("request(7, 4)")
        session.server.run(change)
        session.deliver(0)
        assert not session.server.outgoing, change
        session.broadcast()
        assert session.clients[0].value("mode(7)") == 0
    passed("server rejects requests after permission, farm or object changes")

    session = Session(root, scripts)
    session.server.run("g_currentMission.farmId = 0")  # A dedicated server has no local farm.
    session.clients[0].run("request(7, 3)")
    session.deliver(0)
    session.broadcast()
    session.modes(3)
    session.server.run("factory:setOutputDistributionMode(7, 0)")
    session.broadcast()
    session.modes(0)
    passed("a native mode change ends the Mod mode on every machine")

    # Sell-rest: 200 L fit downstream (fee 7), 300 L are sold at 2 x 0.9.
    # Store-rest: the same 300 L become three pallets of 100 L on the server only.
    for wanted, expected_money, expected_pallets in ((4, -7 + 540, 0), (3, -7, 3)):
        session = Session(root, scripts)
        for peer in session.peers():
            peer.run("target.storage:setFillLevel(400, 7); factory.storage:setFillLevel(500, 7)")
        session.clients[1].run(f"request(7, {wanted})")
        session.deliver(1)
        session.broadcast()
        for _ in range(2):
            for peer in session.peers():
                peer.run("hour()")
        for _ in range(4):
            for peer in session.peers():
                peer.run("factory:updateProduction(); factory.palletSpawner:finish()")
        assert isclose(session.server.value("g_currentMission.money"), expected_money)
        assert session.server.value("#factory.palletSpawner.pallets") == expected_pallets
        assert isclose(session.server.value("factory.storage:getFillLevel(7)"), 0)
        assert isclose(session.server.value("target.storage:getFillLevel(7)"), 600)
        for client in session.clients:
            assert client.value("g_currentMission.money") == 0
            assert client.value("#factory.palletSpawner.pallets") == 0
            assert client.value("factory.storage:getFillLevel(7)") == 500
        passed(f"mode {wanted}: repeated hours settle once, on the server only")

    session = Session(root, scripts)
    session.clients[0].run("request(7, 3); request(8, 1); request(9, 4)")
    session.deliver(0)
    session.broadcast()
    session.server.run("""
        factory.storage:setFillLevel(170, 7)
        target.storage:setFillLevel(600, 7)
        hour()
        saved = mockXML()
        factory:saveToXMLFile(saved, 'pp')
        ProductionOverflowPlaceable.saveToXMLFile(factory.owningPlaceable, saved, 'pp.po')
        local reloaded = mockPoint({farmId = 0, placed = false})
        reloaded.isServer, reloaded.networkId = true, 42
        reloaded.storage:setFillLevel(170, 7)
        reloaded:loadFromXMLFile(saved, 'pp')
        ProductionOverflowPlaceable.loadFromXMLFile(reloaded.owningPlaceable, saved, 'pp.po', false)
        ProductionOverflowPlaceable.onLoadFinished(reloaded.owningPlaceable)
        reloaded:setOwnerFarmId(1)
        ProductionOverflowPlaceable.onPostFinalizePlacement(reloaded.owningPlaceable)
        factory, objects[42], manager.productionPoints[1] = reloaded, reloaded, reloaded
        g_nativeModeEvents = {}
        assert(factory.poState.released[7] == 170)
    """)
    session.clients = [Peer(root, scripts), Peer(root, scripts)]
    for client in session.clients:
        stream = session.server.value("snapshot()")
        packet = tuple(stream[index] for index in range(1, len(stream) + 1))
        client.lua.globals().loadSnapshot(client.lua.table_from(packet))
    session.modes(3, 7)
    session.modes(1, 8)
    session.modes(4, 9)
    for client in session.clients:
        assert client.value("factory.poState.released[7]") is None
    session.clients[1].run("toggle(7)")
    session.deliver(1)
    session.broadcast()
    session.modes(4, 7)
    assert session.server.value("factory.poState.released[7]") is None
    passed("save and reload on the server, join snapshot and edits after the join")
    print(f"{count} multiplayer scenarios passed")
