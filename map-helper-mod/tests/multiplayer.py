"""Independent Lua peers exchanging the real Mod events over a deterministic ordered transport.

Engine objects, permissions, AI jobs and delivery are contract doubles. This does not
emulate GIANTS object creation, native AI events, ghosting or connection loss.
"""
from collections import deque

from lupa import LuaRuntime
from guixml import install

SCRIPTS = ("MapHelper", "QueueEvents", "FieldNeeds", "MapHelperPage", "MapFrameExtension", "Register")


class Peer:
    def __init__(self, root, server=False, farm=1, allowed=True, dedicated=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.outgoing = deque()
        self.lua.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
        install(self.lua, root)
        for name in SCRIPTS:
            self.lua.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
        g = self.lua.globals()
        g.serverPeer, g.peerFarm, g.peerAllowed, g.dedicated = server, farm, allowed, dedicated
        g.capturePacket = lambda kind, target, packet: self.outgoing.append(
            (kind, target, tuple(packet[index] for index in range(1, len(packet) + 1))))
        self.lua.execute("""
            MH = MapHelper
            g_currentMission = newMission(serverPeer)
            g_currentMission.farmId, g_currentMission.allowed = peerFarm, peerAllowed
            g_localPlayer.farmId = peerFarm
            if dedicated then g_localPlayer = nil end
            tractor = mockVehicle(42, 1, "tractorUnique")
            other = mockVehicle(43, 2, "otherUnique")
            -- Server-side connections of the remote players, indexed like Session.clients.
            connections = {}
            local function kindOf(event)
                local class = getmetatable(event).__index
                if class == MHQueueRequestEvent then return "request" end
                return "state"
            end
            function send(event, connection, target)
                local packet = {}
                event:writeStream(packet, connection)
                capturePacket(kindOf(event), target, packet)
            end
            serverConnection = {getIsServer = function() return true end}
            if serverPeer then
                g_server = {broadcastEvent = function(_, event, sendLocal, ignore, ghost)
                    assert(sendLocal == false and ignore == nil and ghost == event.vehicle)
                    for index, connection in ipairs(connections) do send(event, connection, index) end
                end}
            else
                g_server = nil
                g_client = {getServerConnection = function()
                    return {sendEvent = function(_, event) send(event, serverConnection, 0) end}
                end}
            end
            function addConnection(farmId, allowed)
                local connection = {farmId = farmId, allowed = allowed, getIsServer = function() return false end}
                connection.sendEvent = function(self, event) send(event, self, #connections) end
                table.insert(connections, connection)
                return connection
            end
            function receive(kind, packet, index)
                if kind == "request" then
                    MHQueueRequestEvent.emptyNew():readStream(packet, connections[index])
                else
                    MHQueueStateEvent.emptyNew():readStream(packet, serverConnection)
                end
            end
            FSBaseMission.onStartMission(g_currentMission)
            function newJob(vehicle, x, z)
                local job = g_currentMission.aiJobTypeManager:createJob(AIJobType.GOTO)
                job.vehicleParameter:setVehicle(vehicle)
                job.positionParameter:setPosition(x, z)
                return job
            end
            function add(vehicle, x, z, insertNext)
                return MH.requestAdd(vehicle or tractor, newJob(vehicle or tractor, x, z), insertNext)
            end
            function idAt(index) return MH.getEntries(tractor)[index].id end
            -- A worker the player started himself: added jobs wait behind it.
            function busy()
                local job = newJob(tractor, 0, 0)
                g_currentMission.aiSystem:startJob(job, 1)
                return job
            end
            function startedX(index) return g_currentMission.aiSystem.started[index].positionAngleParameter.x end
            function labels(vehicle)
                local result = {}
                for _, entry in ipairs(MH.getEntries(vehicle or tractor)) do table.insert(result, MH.getJobLabel(entry.job)) end
                return table.concat(result, ";")
            end
            function firstId() return MH.getEntries(tractor)[1].id end
            function finishRunning(message)
                local queue = MH.queues[tractor]
                g_currentMission.aiSystem:stopJob(queue.runningJob, message)
            end
            function tick(ms) MH:update(ms) end
            function notes()
                local result = {}
                for _, note in ipairs(g_currentMission.notifications) do table.insert(result, note.kind .. ":" .. note.text) end
                return table.concat(result, ";")
            end
        """)

    def run(self, code):
        return self.lua.execute(code)

    def value(self, expression):
        return self.lua.eval(expression)


class Session:
    def __init__(self, root, clients=((1, True), (1, False), (2, True)), dedicated=False):
        self.root = root
        self.server = Peer(root, server=True, dedicated=dedicated)
        self.clients = []
        for farm, allowed in clients:
            self.join(farm, allowed, snapshot=False)

    def join(self, farm, allowed, snapshot=True):
        peer = Peer(self.root, farm=farm, allowed=allowed)
        self.clients.append(peer)
        self.server.lua.globals().addConnection(farm, allowed)
        if snapshot:
            index = len(self.clients)
            self.server.run(f"FSBaseMission.sendInitialClientState(g_currentMission, connections[{index}], {{}}, {{}})")
            self.broadcast()
        return peer

    def deliver(self, client):
        peer = self.clients[client]
        while peer.outgoing:
            kind, _, packet = peer.outgoing.popleft()
            assert kind == "request", "clients only send requests"
            self.server.lua.globals().receive(kind, self.server.lua.table_from(packet), client + 1)

    def broadcast(self):
        while self.server.outgoing:
            kind, target, packet = self.server.outgoing.popleft()
            assert kind == "state", "the server only sends state"
            peer = self.clients[target - 1]
            peer.lua.globals().receive(kind, peer.lua.table_from(packet), None)
        assert all(not client.outgoing for client in self.clients), "client echoed a server event"

    def labels(self):
        return [peer.value("labels()") for peer in [self.server, *self.clients]]


def run_multiplayer(root):
    count = 0

    def passed(name):
        nonlocal count
        count += 1
        print(f"PASS multiplayer: {name}")

    session = Session(root)
    a, worker, foreign = session.clients
    a.run("add(nil, 10, 20)")
    assert a.value("labels()") == "", "no optimistic client update"
    session.deliver(0)
    session.broadcast()
    assert session.server.value("#g_currentMission.aiSystem.started") == 1 and session.server.value("startedX(1)") == 10
    assert session.labels() == [""] * 4 and all(peer.value("MH.queues[tractor].running") for peer in session.clients)
    passed("the first job added to an idle vehicle starts at once on the server and every client sees it running")

    a.run("add(nil, 30, 40)")
    session.deliver(0)
    session.broadcast()
    assert session.labels() == ["Go to - 30, 40"] * 4
    worker.run("add(nil, 50, 60)")
    foreign.run("MH.requestClear(tractor)")
    session.deliver(1)
    session.deliver(2)
    assert not session.server.outgoing
    assert session.labels() == ["Go to - 30, 40"] * 4
    passed("manager request is applied by the server and reaches every client; others are refused")

    second = Session(root, clients=((1, True), (1, True)))
    second.server.run("busy(); add(nil, 1, 1); add(nil, 2, 2)")
    second.broadcast()
    entry = second.clients[0].value("firstId()")
    for client in second.clients:
        client.run(f"MH.requestRemove(tractor, {entry})")
    second.deliver(0)
    second.deliver(1)
    assert len(second.server.outgoing) == 2, "the second removal of the same entry is a no-op"
    second.broadcast()
    assert second.labels() == ["Go to - 2, 2"] * 3
    passed("host edits broadcast and concurrent removal of one entry removes it once")

    session.server.run("finishRunning(AIMessageSuccessFinishedJob.new())")
    session.broadcast()
    session.server.run("tick(MH.ADVANCE_DELAY)")
    session.broadcast()
    assert session.server.value("#g_currentMission.aiSystem.started") == 2 and session.server.value("startedX(2)") == 30
    assert session.labels() == [""] * 4 and a.value("MH.queues[tractor].running")
    session.server.run("finishRunning(AIMessageSuccessFinishedJob.new())")
    session.broadcast()
    assert all(peer.value("MH.queues[tractor] == nil") for peer in [session.server, *session.clients])
    assert a.value("notes()") == "ok:Tractor 42 finished" and worker.value("notes()") == "ok:Tractor 42 finished"
    assert foreign.value("notes()") == "", "other farms are not notified"
    passed("server advances the queue after each successful finish and notifies the farm")

    session = Session(root)
    a, worker, foreign = session.clients
    a.run("add(nil, 1, 1); add(nil, 2, 2); add(nil, 3, 3)")
    session.deliver(0)
    session.broadcast()
    session.server.run("finishRunning(AIMessageSuccessStoppedByUser.new()); tick(MH.ADVANCE_DELAY * 2)")
    session.broadcast()
    assert session.server.value("#g_currentMission.aiSystem.started") == 1
    for peer in [session.server, *session.clients]:
        assert peer.value("MH.queues[tractor].pause == MH.PAUSE.STOPPED and not MH.queues[tractor].running")
    assert a.value("notes()") == "info:Tractor 42 paused, 2 waiting" and foreign.value("notes()") == ""
    worker.run("MH.requestStart(tractor)")
    session.deliver(1)
    assert session.server.value("#g_currentMission.aiSystem.started") == 1, "worker without permission"
    a.run("MH.requestStart(tractor)")
    session.deliver(0)
    session.broadcast()
    assert session.server.value("#g_currentMission.aiSystem.started") == 2
    assert a.value("MH.queues[tractor].pause == MH.PAUSE.NONE") and a.value("labels()") == "Go to - 3, 3"
    passed("stop by the player pauses on every peer; only a manager can resume")

    late = session.join(1, True)
    assert late.value("labels()") == "Go to - 3, 3" and late.value("MH.queues[tractor].running")
    assert late.value("notes()") == "", "joining players get the state without a message"
    passed("joining player receives the current queue")

    session = Session(root)
    a = session.clients[0]
    a.run("add(nil, 1, 1); add(nil, 2, 2)")
    session.deliver(0)
    session.broadcast()
    session.server.run("finishRunning(AIMessageErrorOutOfFill.new())")
    session.broadcast()
    assert a.value("MH.queues[tractor].pause == MH.PAUSE.STOPPED")
    a.run("add(nil, 3, 3)")
    session.deliver(0)
    session.broadcast()
    assert session.server.value("#g_currentMission.aiSystem.started") == 2 and session.server.value("startedX(2)") == 2
    assert all(peer.value("MH.queues[tractor].pause == MH.PAUSE.NONE and MH.queues[tractor].running")
               for peer in [session.server, *session.clients])
    assert session.labels() == ["Go to - 3, 3"] * 4
    passed("adding a job to a paused queue resumes it with its first waiting job")

    session = Session(root, clients=((1, True),))
    session.server.run("busy()")
    session.clients[0].run("add(nil, 7, 8); add(other, 9, 9)")
    session.deliver(0)
    session.broadcast()
    assert session.server.value("labels(other)") == "", "farm 1 cannot queue for a farm 2 vehicle"
    session.server.run("FSCareerMissionInfo.saveToXMLFile(g_currentMission.missionInfo)")
    saved = dict(session.server.value("files['savegame1/mapHelper.xml']").items())
    fresh = Session(root, clients=())
    fresh.server.lua.globals().files["savegame1/mapHelper.xml"] = fresh.server.lua.table_from(saved)
    fresh.server.run("MH.onMissionDeleted(nil); FSBaseMission.onStartMission(g_currentMission)")
    assert fresh.server.value("labels()") == "Go to - 7, 8"
    joined = fresh.join(1, True)
    assert joined.value("labels()") == "Go to - 7, 8" and not joined.value("MH.queues[tractor].running")
    joined.run("MH.requestStart(tractor)")
    fresh.deliver(0)
    fresh.broadcast()
    assert fresh.server.value("#g_currentMission.aiSystem.started") == 1 and joined.value("labels()") == ""
    passed("server save, reload, join snapshot and resume after loading")

    session = Session(root, clients=((1, True),), dedicated=True)
    manager = session.clients[0]
    manager.run("add(nil, 4, 4); add(nil, 5, 5)")
    session.deliver(0)
    session.broadcast()
    session.server.run("finishRunning(AIMessageErrorOutOfFill.new())")
    session.broadcast()
    assert session.server.value("notes()") == "", "no local player on a dedicated server"
    assert manager.value("notes()") == "info:Tractor 42 paused, 1 waiting" and manager.value("labels()") == "Go to - 5, 5"
    passed("dedicated server runs remote requests and pauses after an error without a local player")

    session = Session(root)
    a, worker, foreign = session.clients
    session.server.run("busy()")
    a.run("add(nil, 1, 1); add(nil, 2, 2); add(nil, 3, 3, true)")
    session.deliver(0)
    session.broadcast()
    assert session.labels() == ["Go to - 3, 3;Go to - 1, 1;Go to - 2, 2"] * 4, session.labels()
    last = a.value("idAt(3)")
    a.run(f"MH.requestMove(tractor, {last}, true)")
    a.run(f"MH.requestEdit(tractor, {last}, newJob(tractor, 9, 9))")
    session.deliver(0)
    session.broadcast()
    assert session.labels() == ["Go to - 3, 3;Go to - 9, 9;Go to - 1, 1"] * 4, session.labels()
    assert a.value("idAt(2)") == last, "an edited entry keeps its id"
    worker.run(f"MH.requestMove(tractor, {last}, true); MH.requestEdit(tractor, {last}, newJob(tractor, 5, 5))")
    foreign.run(f"MH.requestEdit(tractor, {last}, newJob(tractor, 6, 6))")
    session.deliver(1)
    session.deliver(2)
    assert not session.server.outgoing and session.labels()[0] == "Go to - 3, 3;Go to - 9, 9;Go to - 1, 1"
    first_id = a.value("idAt(1)")
    a.run(f"MH.requestMove(tractor, {first_id}, true)")
    session.deliver(0)
    assert not session.server.outgoing, "moving the first entry up changes nothing"
    session.server.run("finishRunning(AIMessageSuccessFinishedJob.new()); tick(MH.ADVANCE_DELAY)")
    session.broadcast()
    assert session.server.value("startedX(2)") == 3, "the inserted job runs next"
    a.run("MH.requestEdit(tractor, 999, newJob(tractor, 7, 7))")
    session.deliver(0)
    assert not session.server.outgoing, "an entry that is gone can't be edited"
    passed("insert as next, move and edit are applied by the server for managers only")
    print(f"{count} multiplayer scenarios passed")
