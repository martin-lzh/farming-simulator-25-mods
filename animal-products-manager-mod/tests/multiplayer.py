"""Independent Lua peers using real Mod events over a deterministic ordered transport.

Engine objects, permissions and network delivery are contract doubles. This does
not emulate GIANTS object creation, the native pause lifecycle or inventory sync.
"""
from collections import deque
from math import isclose

from lupa import LuaRuntime


class Peer:
    def __init__(self, root, server=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.outgoing = deque()
        self.lua.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
        for name in ("Distribution", "AnimalProductsManager", "ModeEvent", "ProductDialog", "Register"):
            self.lua.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
        self.lua.globals().serverPeer = server
        self.lua.globals().capturePacket = lambda packet: self.outgoing.append(
            tuple(packet[index] for index in range(1, len(packet) + 1))
        )
        self.lua.execute("""
            APM = AnimalProductsManager
            barn = mockHusbandry()
            barn.isServer, barn.networkId = serverPeer, 42
            objects = {[42] = barn}
            serverConnection = {getIsServer = function() return true end}
            managers = {
                {farmId = 1, allowed = true, getIsServer = function() return false end},
                {farmId = 1, allowed = true, getIsServer = function() return false end}
            }
            g_currentMission.getHasPlayerPermission = function(self, permission, connection, farmId)
                assert(permission == "tradeAnimals" and farmId == 1)
                if connection ~= nil then return connection.allowed end
                return self.allowed
            end
            NetworkUtil.writeNodeObject = function(stream, object)
                streamWriteUInt16(stream, object.networkId)
            end
            NetworkUtil.readNodeObject = function(stream)
                return objects[streamReadUInt16(stream)]
            end
            local function send(event, connection)
                local packet = {}
                event:writeStream(packet, connection)
                capturePacket(packet)
            end
            if serverPeer then
                g_server.broadcastEvent = function(_, event, sendLocal, ignore, object)
                    assert(not sendLocal and ignore == nil and objects[object.networkId] == object)
                    send(event, managers[1])
                end
            else
                g_server = nil
                serverConnection.sendEvent = function(self, event) send(event, self) end
                g_client = {getServerConnection = function() return serverConnection end}
            end
            function receive(packet, manager)
                APMModeEvent.emptyNew():readStream(packet, manager and managers[manager] or serverConnection)
            end
            function request(fillType, mode) APM.requestMode(barn, fillType, mode) end
            function openDialog(placeable)
                local frame = {selectedHusbandry = placeable or barn, setMenuButtonInfoDirty = function() end}
                InGameMenuAnimalsFrame.updateMenuButtons(frame)
                frame.menuButtonInfo[1].callback()
            end
            function snapshot()
                local stream = {}
                APM.onWriteStream(barn, stream, managers[1])
                return stream
            end
            function loadSnapshot(stream) APM.onReadStream(barn, stream, serverConnection) end
            function addFactory()
                factory = mockStorage(0, 500)
                local point = {storage = factory, inputFillTypeIds = {[7] = true},
                    owningPlaceable = {rootNode = 20}, getOwnerFarmId = function() return 1 end}
                g_currentMission.productionChainManager = {
                    getProductionPointsForFarmId = function(_, farmId)
                        assert(farmId == 1)
                        return {point}
                    end
                }
            end
        """)

    def run(self, code):
        return self.lua.execute(code)

    def value(self, expression):
        return self.lua.eval(expression)

    def receive(self, packet, manager=None):
        self.lua.globals().receive(self.lua.table_from(packet), manager)

    def snapshot_to(self, other):
        stream = self.lua.globals().snapshot()
        packet = tuple(stream[index] for index in range(1, len(stream) + 1))
        other.lua.globals().loadSnapshot(other.lua.table_from(packet))


class Session:
    def __init__(self, root):
        self.server = Peer(root, server=True)
        self.clients = [Peer(root), Peer(root)]

    def deliver(self, client):
        peer = self.clients[client]
        while peer.outgoing:
            self.server.receive(peer.outgoing.popleft(), client + 1)

    def broadcast(self):
        while self.server.outgoing:
            packet = self.server.outgoing.popleft()
            for client in self.clients:
                client.receive(packet)
        assert all(not client.outgoing for client in self.clients), "client echoed a server event"

    def modes(self, first, second=0):
        for peer in [self.server, *self.clients]:
            assert peer.value("APM.mode(barn, 7)") == first
            assert peer.value("APM.mode(barn, 8)") == second


def run_multiplayer(root):
    count = 0

    def passed(name):
        nonlocal count
        count += 1
        print(f"PASS multiplayer: {name}")

    for order in ((0, 1), (1, 0)):
        session = Session(root)
        a, b = session.clients
        a.run("request(7, 1)")
        b.run("request(7, 2)")
        session.modes(0)  # No optimistic client update before authoritative reply.
        for client in order:
            session.deliver(client)
        session.broadcast()
        session.modes(order[-1] + 1)
        passed(f"two managers, same product, server arrival order {order}")

    session = Session(root)
    a, b = session.clients
    for peer in (a, b):
        peer.run("openDialog()")
    a.run("g_gui.dialog.rows[1].option:setState(2); g_gui.dialog:onClickOk()")
    session.deliver(0)
    session.broadcast()
    assert b.value("g_gui.dialog.rows[1].option:getState()") == 1  # Open draft is not refreshed.
    b.run("g_gui.dialog.rows[2].option:setState(3); g_gui.dialog:onClickOk()")
    assert len(b.outgoing) == 1, "unchanged draft overwrote another manager's row"
    session.deliver(1)
    session.broadcast()
    session.modes(1, 2)
    b.run("openDialog()")
    assert b.value("g_gui.dialog.rows[1].option:getState()") == 2
    assert b.value("g_gui.dialog.rows[2].option:getState()") == 3
    passed("different product drafts coexist; reopening shows authoritative modes")

    session = Session(root)
    for client in session.clients:
        client.run("openDialog()")
    session.clients[0].run("g_gui.dialog.rows[1].option:setState(2); g_gui.dialog:onClickOk()")
    session.deliver(0)
    session.broadcast()
    session.clients[1].run("g_gui.dialog.rows[1].option:setState(3); g_gui.dialog:onClickOk()")
    session.deliver(1)
    session.broadcast()
    session.modes(2)
    passed("conflicting open drafts use the last accepted edit")

    for host_last in (False, True):
        session = Session(root)
        session.clients[0].run("request(7, 1)")
        if host_last:
            session.deliver(0)
        session.server.run("request(7, 2)")
        if not host_last:
            session.deliver(0)
        session.broadcast()
        session.modes(2 if host_last else 1)
    passed("host and remote edits converge in either server execution order")

    for change in ("managers[1].allowed = false", "managers[1].farmId = 2",
                   "APM.onDelete(barn)", "objects[42] = nil"):
        session = Session(root)
        session.clients[0].run("request(7, 1)")
        session.server.run(change)
        session.deliver(0)
        assert not session.server.outgoing
        session.modes(0)
    passed("server rejects pending requests after permission, farm or object changes")

    for mode, expected_money, expected_factory in ((1, 180, 0), (2, -0.35, 100)):
        session = Session(root)
        for peer in [session.server, *session.clients]:
            peer.run("addFactory()")
        # A dedicated server has no local farm manager, but remote managers still work.
        session.server.run("g_currentMission.farmId = 0")
        for index, peer in enumerate(session.clients):
            peer.run(f"request(7, {mode})")
            session.deliver(index)
        session.broadcast()
        session.modes(mode)
        for _ in range(2):
            for peer in [session.server, *session.clients]:
                peer.run("APM.onHourChanged(barn)")
        assert isclose(session.server.value("g_currentMission.money"), expected_money)
        assert isclose(session.server.value("factory.amount"), expected_factory)
        assert session.server.value("barn.spec_husbandryPallets.pendingLiters[7]") == 0
        for client in session.clients:
            assert client.value("g_currentMission.money") == 0
            assert client.value("factory.amount") == 0
            assert client.value("barn.spec_husbandryPallets.pendingLiters[7]") == 100
        passed(f"mode {mode}: two managers and repeated hours settle server inventory once")

    session = Session(root)
    session.clients[0].run("request(7, 2); request(8, 1)")
    session.deliver(0)
    session.broadcast()
    session.server.run("""
        saved = mockXML()
        APM.saveToXMLFile(barn, saved, 'barn.apm')
        APM.onLoad(barn)
        APM.loadFromXMLFile(barn, saved, 'barn.apm', false)
        APM.onLoadFinished(barn)
        APM.onPostFinalizePlacement(barn)
    """)
    # Native join pauses gameplay: take a stationary snapshot, with no edit/hour
    # injected during sync. This checks Mod serialization, not the engine's pause.
    session.clients = [Peer(root), Peer(root)]
    for client in session.clients:
        session.server.snapshot_to(client)
    session.modes(2, 1)
    session.clients[1].run("request(7, 0)")
    session.deliver(1)
    session.broadcast()
    session.modes(0, 1)
    passed("server mode save/reload, paused join snapshot and post-join edits")
    session = Session(root)
    for peer in [session.server, *session.clients]:
        peer.run("""
            barn.spec_husbandryPallets.activeFillTypes = {8}
            sheepBarn = mockHusbandry()
            sheepBarn.isServer, sheepBarn.networkId = serverPeer, 43
            sheepBarn.spec_husbandryPallets.activeFillTypes = {7}
            objects[43] = sheepBarn
        """)
    session.clients[0].run("""
        openDialog(barn)
        assert(#g_gui.dialog.rows == 1 and g_gui.dialog.rows[1].element.label.text == 'Product 8')
        g_gui.dialog.rows[1].option:setState(2); g_gui.dialog:onClickOk()
    """)
    session.clients[1].run("""
        openDialog(sheepBarn)
        assert(#g_gui.dialog.rows == 1 and g_gui.dialog.rows[1].element.label.text == 'Product 7')
        g_gui.dialog.rows[1].option:setState(3); g_gui.dialog:onClickOk()
    """)
    session.deliver(0)
    session.deliver(1)
    session.broadcast()
    session.modes(0, 1)
    for peer in [session.server, *session.clients]:
        peer.run("""
            assert(APM.mode(sheepBarn, 7) == 2 and APM.mode(sheepBarn, 8) == 0)
            openDialog(barn)
            assert(#g_gui.dialog.rows == 1 and g_gui.dialog.rows[1].element.label.text == 'Product 8')
            g_gui.dialog:onClickBack()
        """)
    passed("goat and sheep products stay local to their barn across manager broadcasts")
    print(f"{count} multiplayer scenarios passed")
