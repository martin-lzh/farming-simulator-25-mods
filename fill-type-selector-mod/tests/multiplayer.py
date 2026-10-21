"""Independent Lua peers using the real Mod event over a deterministic ordered transport.

Engine objects and network delivery are contract doubles. This does not emulate GIANTS object
creation, the native join pause or fill level synchronization.
"""
from collections import deque

from lupa import LuaRuntime


class Peer:
    def __init__(self, root, scripts, server=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.outgoing = deque()
        self.lua.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
        for name in scripts:
            self.lua.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
        self.lua.globals().serverPeer = server
        # Server packets carry their target: None for a broadcast, else the client index.
        self.lua.globals().capturePacket = lambda packet, target=None: self.outgoing.append(
            (target, tuple(packet[index] for index in range(1, len(packet) + 1)))
        )
        self.lua.execute("""
            FTS = FillTypeSelector
            sprayer = mockSprayer({isServer = serverPeer})
            sprayer.networkId = 42
            objects = {[42] = sprayer}
            NetworkUtil.writeNodeObject = function(stream, object) table.insert(stream, object.networkId) end
            NetworkUtil.readNodeObject = function(stream) return objects[table.remove(stream, 1)] end
            local function send(event, connection, target)
                local packet = {}
                event:writeStream(packet, connection)
                capturePacket(packet, target)
            end
            connections = {}
            for index = 1, 2 do
                connections[index] = {farmId = 1, index = index, getIsServer = function() return false end,
                    sendEvent = function(self, event) send(event, self, self.index) end}
            end
            if serverPeer then
                g_server.broadcastEvent = function(_, event, sendLocal, ignore, object)
                    assert(not sendLocal and ignore == nil and objects[object.networkId] == object)
                    send(event, clientConnection)
                end
            else
                g_server = nil
                serverConnection.sendEvent = function(self, event) send(event, self) end
                g_client = {getServerConnection = function() return serverConnection end}
            end
            function receive(packet, fromClient)
                FTSSelectFillTypeEvent.emptyNew():readStream(packet, fromClient and connections[fromClient] or serverConnection)
            end
            function choose(name) FTS.setSelectedFillType(sprayer, FillType[name]) end
            function selected()
                local fillType = FTS.getSelectedFillType(sprayer)
                return fillType and g_fillTypeManager:getFillTypeNameByIndex(fillType) or "none"
            end
            function snapshot()
                local stream = {}
                sprayer:raise("onWriteStream", stream, clientConnection)
                return stream
            end
            function loadSnapshot(stream) sprayer:raise("onReadStream", stream, serverConnection) end
        """)

    def run(self, code):
        return self.lua.execute(code)

    def value(self, expression):
        return self.lua.eval(expression)

    def receive(self, packet, from_client=None):
        self.lua.globals().receive(self.lua.table_from(packet), from_client)

    def snapshot_to(self, other):
        stream = self.lua.globals().snapshot()
        packet = tuple(stream[index] for index in range(1, len(stream) + 1))
        other.lua.globals().loadSnapshot(other.lua.table_from(packet))


class Session:
    def __init__(self, root, scripts):
        self.root, self.scripts = root, scripts
        self.server = Peer(root, scripts, server=True)
        self.clients = [Peer(root, scripts), Peer(root, scripts)]

    def deliver(self, client):
        peer = self.clients[client]
        while peer.outgoing:
            self.server.receive(peer.outgoing.popleft()[1], from_client=client + 1)

    def broadcast(self):
        while self.server.outgoing:
            target, packet = self.server.outgoing.popleft()
            for index, client in enumerate(self.clients):
                if target is None or target == index + 1:
                    client.receive(packet)
        assert all(not client.outgoing for client in self.clients), "client echoed a server event"

    def selections(self):
        return [peer.value("selected()") for peer in (self.server, *self.clients)]


def run_multiplayer(root, scripts):
    count = 0

    def passed(name):
        nonlocal count
        count += 1
        print(f"PASS multiplayer: {name}")

    session = Session(root, scripts)
    session.clients[0].run("choose('LIME')")
    assert session.selections() == ["none", "LIME", "none"]
    session.deliver(0)
    session.broadcast()
    assert session.selections() == ["LIME"] * 3
    assert all(peer.value("sprayer.fillUnits[1].fillTypeToDisplay") == peer.value("FillType.LIME")
               for peer in (session.server, *session.clients))
    passed("client choice reaches the server and every client")

    for order in ((0, 1), (1, 0)):
        session = Session(root, scripts)
        session.clients[0].run("choose('LIME')")
        session.clients[1].run("choose('FERTILIZER')")
        for client in order:
            session.deliver(client)
        session.broadcast()
        last = ("LIME", "FERTILIZER")[order[-1]]
        assert session.selections() == [last] * 3, session.selections()
        passed(f"simultaneous choices converge on the server order {order}")

    session = Session(root, scripts)
    session.server.run("choose('LIME')")
    session.broadcast()
    assert session.selections() == ["LIME"] * 3
    passed("host choice reaches every client")

    session = Session(root, scripts)
    session.server.receive((99, session.server.value("FillType.LIME")), from_client=1)
    assert not session.server.outgoing and session.selections() == ["none"] * 3
    session.server.receive((42, session.server.value("FillType.HERBICIDE")), from_client=1)
    assert [target for target, _ in session.server.outgoing] == [1]
    session.broadcast()
    assert session.selections() == ["none"] * 3
    passed("server rejects fill types the sprayer cannot take and unknown vehicles")

    session = Session(root, scripts)
    session.server.run("choose('FERTILIZER')")
    session.broadcast()
    session.server.run("connections[2].farmId = 2")
    session.clients[1].run("choose('LIME')")
    assert session.selections() == ["FERTILIZER", "FERTILIZER", "LIME"]
    session.deliver(1)
    assert [target for target, _ in session.server.outgoing] == [2], "only the sender is corrected"
    session.broadcast()
    assert session.selections() == ["FERTILIZER"] * 3
    session.server.run("sprayer:addFill(100, 'FERTILIZER')")
    session.clients[0].run("FTS.setSelectedFillType(sprayer, FillType.LIME)")
    session.deliver(0)
    session.broadcast()
    assert session.selections() == ["FERTILIZER"] * 3
    passed("another farm's or a locked request is refused and the sender reverts")

    session = Session(root, scripts)
    session.clients[1].run("choose('LIME')")
    session.deliver(1)
    session.broadcast()
    session.server.run("""
        saved = mockXML()
        FTS.saveToXMLFile(sprayer, saved, 'vehicles.vehicle(0).' .. FTS.SPEC_NAME)
        sprayer = mockSprayer({savegame = {xmlFile = saved, key = 'vehicles.vehicle(0)'}})
        sprayer.networkId = 42
        objects[42] = sprayer
    """)
    session.clients = [Peer(root, scripts), Peer(root, scripts)]
    for client in session.clients:
        session.server.snapshot_to(client)
    assert session.selections() == ["LIME"] * 3
    session.clients[0].run("choose('FERTILIZER')")
    session.deliver(0)
    session.broadcast()
    assert session.selections() == ["FERTILIZER"] * 3
    passed("server save/reload, join snapshot and later edits")

    session = Session(root, scripts)
    session.clients[0].run("choose('LIME')")
    session.deliver(0)
    session.broadcast()
    for peer in (session.server, *session.clients):
        peer.run("""
            sprayer.aiActive, sprayer.fieldWorkActive = true, true
            assert(sprayer:getIsSprayerExternallyFilled())
            boughtType = sprayer:getExternalFill(FillType.UNKNOWN, 1000)
        """)
        assert peer.value("boughtType == FillType.LIME")
    assert session.server.value("g_currentMission.money") == -3
    assert all(client.value("g_currentMission.money") == 0 for client in session.clients)
    assert session.server.value("#sprayer.aiRanges") == 1
    assert all(client.value("#sprayer.aiRanges") == 0 for client in session.clients)
    passed("every peer sprays lime, only the server pays and sets AI requirements")
    print(f"{count} multiplayer scenarios passed")
