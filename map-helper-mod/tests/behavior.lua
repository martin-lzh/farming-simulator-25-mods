local MH = MapHelper
local MF = MHMapFrame
local passed = 0
local function test(name, body)
    -- Every test starts a fresh host mission (server with a local player).
    objects, files, broadcasts, infoDialogs = {}, {}, {}, {}
    g_messageCenter.subscribers = {}
    g_inputBinding.events = {}
    g_gui.openDialog = nil
    logged.warnings, logged.infos = {}, {}
    g_currentMission = newMission(true)
    g_localPlayer.farmId, g_localPlayer.vehicle = 1, nil
    localConnection.farmId, localConnection.allowed = 1, true
    MH.onMissionDeleted(nil)
    FSBaseMission.onStartMission(g_currentMission)
    body()
    passed = passed + 1
    print("PASS " .. name)
end
local function newJob(vehicle, x, z, typeIndex)
    local job = g_currentMission.aiJobTypeManager:createJob(typeIndex or AIJobType.GOTO)
    job.vehicleParameter:setVehicle(vehicle)
    if job.positionParameter ~= nil then
        job.positionParameter:setPosition(x or 1, z or 2)
    end
    return job
end
local function update(ms)
    for updateable in pairs(g_currentMission.updateables) do
        updateable:update(ms)
    end
end
local function seat(vehicle)
    g_localPlayer.vehicle = vehicle
    return vehicle
end
local function frameWithJobMenu(vehicle)
    local frame = mockFrame()
    InGameMenuMapFrame.onLoadMapFinished(frame)
    frame:setAIVehicle(vehicle)
    return frame
end

test("feature checks pass against the doubles and both events are registered", function()
    assert(MH.features.queue and MH.features.drawer)
    assert(registeredEvents.MHQueueRequestEvent >= 1 and registeredEvents.MHQueueStateEvent >= 1)
    assert(g_messageCenter.subscribers[1].type == MessageType.AI_JOB_STOPPED)
    assert(g_currentMission.updateables[MH] == MH)
end)

test("drawer on foot only offers center on me", function()
    local frame = mockFrame()
    local state = MF.getDrawerState(frame)
    assert(state.onFoot and state.title == "mh_onFoot" and state.status == "mh_statusOnFoot")
    assert(state.canCenter and not state.canCreate and not state.canGoTo and not state.canStartStop and not state.canClear)
    MF.centerOnMe(frame)
    assert(frame.ingameMap.centered[1] == 11 and frame.ingameMap.centered[2] == 22)
end)

test("drawer in an idle vehicle offers the native job actions", function()
    local vehicle = seat(mockVehicle(7))
    local frame = mockFrame()
    local state = MF.getDrawerState(frame)
    assert(state.title == "Tractor 7" and state.status == "mh_statusIdle")
    assert(state.canCreate and state.canGoTo and not state.canStartStop and not state.canClear)
    MF.centerOnMe(frame)
    assert(frame.ingameMap.pannedTo == vehicle.hotspot and frame.selected == vehicle.hotspot)
    assert(MF.goTo(frame) and frame.goToStarted == 1 and frame.selected == vehicle.hotspot)
    assert(MF.createJob(frame) and frame.mode == InGameMenuMapFrame.AI_MODE_CREATE and frame.currentJobVehicle == vehicle)
end)

test("drawer keeps planning actions off while picking, paused or for vehicles without workers", function()
    local vehicle = seat(mockVehicle(7))
    local frame = mockFrame()
    frame.picking = true
    assert(not MF.getDrawerState(frame).canCreate)
    frame.picking = false
    g_currentMission.paused = true
    assert(not MF.getDrawerState(frame).canGoTo)
    g_currentMission.paused = false
    vehicle.spec_aiJobVehicle = nil
    local state = MF.getDrawerState(frame)
    assert(state.status == "mh_statusNoAI" and not state.canCreate)
    assert(not MF.createJob(frame))
end)

test("permission gating follows hireAssistant and the vehicle's farm", function()
    local vehicle = seat(mockVehicle(7))
    local frame = mockFrame()
    g_currentMission.allowed = false
    local state = MF.getDrawerState(frame)
    assert(state.status == "mh_statusNoPermission" and not state.canCreate and not state.canStartStop)
    g_currentMission.allowed = true
    vehicle.farmId = 2
    assert(not MF.getDrawerState(frame).canCreate)
    vehicle.farmId = 1
    -- Server side: requests from another farm or without permission are refused.
    local job = newJob(vehicle)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, job, nil, {farmId = 2, allowed = true}))
    assert(job.deleted and #MH.getEntries(vehicle) == 0)
    job = newJob(vehicle)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, job, nil, {farmId = 1, allowed = false}))
    assert(job.deleted and #broadcasts == 0)
    vehicle.farmId = FarmManager.SPECTATOR_FARM_ID
    assert(not MH.getCanManage(vehicle, nil))
end)

test("add to queue validates like Start job and leaves the job menu", function()
    local vehicle = seat(mockVehicle(7))
    local frame = frameWithJobMenu(vehicle)
    local ext = frame.mapHelper
    assert(ext.queueButton.visible, "queue button shown for the controlled vehicle")
    local job = frame.currentJob
    assert(MF.addToQueue(frame))
    local entries = MH.getEntries(vehicle)
    assert(#entries == 1 and entries[1].job == job and job.setValuesCount >= 2)
    assert(frame.mode == InGameMenuMapFrame.AI_MODE_OVERVIEW and frame.currentJob == nil and job.resetCount == 1)
    assert(not ext.queueButton.visible and #broadcasts == 1)
    -- An invalid job stays in the menu with the native warning.
    frame:setAIVehicle(vehicle)
    frame.currentJob.valid = false
    assert(not MF.addToQueue(frame))
    assert(infoDialogs[1] == "invalid target" and frame.warningsUpdated and frame.mode == InGameMenuMapFrame.AI_MODE_CREATE)
    assert(#MH.getEntries(vehicle) == 1)
end)

test("add to queue is only offered for the vehicle the player sits in", function()
    local vehicle = mockVehicle(7)
    seat(mockVehicle(8))
    local frame = frameWithJobMenu(vehicle)
    assert(not frame.mapHelper.queueButton.visible)
    assert(not MF.addToQueue(frame) and #MH.getEntries(vehicle) == 0)
    frame:onClickBack()
    seat(vehicle)
    frame:setAIVehicle(vehicle)
    assert(frame.mapHelper.queueButton.visible)
    frame.mapHelper.queueButton:getDescendantByName("button").onClickCallback(frame.mapHelper)
    assert(#MH.getEntries(vehicle) == 1)
end)

test("queue holds at most the limit and server-side validation still applies", function()
    local vehicle = seat(mockVehicle(7))
    for i = 1, MH.MAX_ENTRIES do
        assert(MH.handleRequest(MH.ACTION.ADD, vehicle, newJob(vehicle, i, i), nil, localConnection))
    end
    local frame = frameWithJobMenu(vehicle)
    assert(not MF.addToQueue(frame) and infoDialogs[1] == "Full at 10")
    local extra = newJob(vehicle)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, extra, nil, localConnection) and extra.deleted)
    local other = mockVehicle(8)
    local foreign = newJob(other)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, foreign, nil, localConnection), "job for another vehicle")
    local invalid = newJob(other)
    invalid.valid = false
    assert(not MH.handleRequest(MH.ACTION.ADD, other, invalid, nil, localConnection) and MH.queues[other] == nil)
end)

test("remove takes out one entry by id and clear empties the queue", function()
    local vehicle = seat(mockVehicle(7))
    local jobs = {newJob(vehicle, 1, 1), newJob(vehicle, 2, 2), newJob(vehicle, 3, 3)}
    for _, job in ipairs(jobs) do MH.requestAdd(vehicle, job) end
    local entries = MH.getEntries(vehicle)
    local secondId = entries[2].id
    assert(MH.requestRemove(vehicle, secondId))
    entries = MH.getEntries(vehicle)
    assert(#entries == 2 and entries[1].job == jobs[1] and entries[2].job == jobs[3] and jobs[2].deleted)
    assert(not MH.handleRequest(MH.ACTION.REMOVE, vehicle, nil, secondId, localConnection), "already removed")
    MH.requestClear(vehicle)
    assert(MH.queues[vehicle] == nil and jobs[1].deleted and jobs[3].deleted)
end)

test("start queue starts the head through the native AI system", function()
    local vehicle = seat(mockVehicle(7))
    local first, second = newJob(vehicle, 1, 1), newJob(vehicle, 2, 2)
    MH.requestAdd(vehicle, first)
    MH.requestAdd(vehicle, second)
    local frame = mockFrame()
    local state = MF.getDrawerState(frame)
    assert(state.startStop == "queue" and state.canStartStop and state.canCreate)
    assert(MF.startStop(frame))
    local started = g_currentMission.aiSystem.started
    assert(#started == 1 and started[1] == first and first.startedFarmId == 1 and vehicle:getIsAIActive())
    local queue = MH.queues[vehicle]
    assert(queue.running and queue.runningJob == first and #queue.entries == 1)
    state = MF.getDrawerState(frame)
    assert(state.startStop == "cancel" and state.status:find("mh_statusWorking", 1, true) and not state.canCreate)
end)

test("queue advances only after a successful finish", function()
    local vehicle = seat(mockVehicle(7))
    local jobs = {newJob(vehicle, 1, 1), newJob(vehicle, 2, 2), newJob(vehicle, 3, 3)}
    for _, job in ipairs(jobs) do MH.requestAdd(vehicle, job) end
    MH.requestStart(vehicle)
    g_currentMission.aiSystem:stopJob(jobs[1], AIMessageSuccessFinishedJob.new())
    update(MH.ADVANCE_DELAY - 1)
    assert(#g_currentMission.aiSystem.started == 1, "waits for the native job removal")
    update(1)
    assert(#g_currentMission.aiSystem.started == 2 and g_currentMission.aiSystem.started[2] == jobs[2])
    g_currentMission.aiSystem:stopJob(jobs[2], AIMessageSuccessSiloEmpty.new())
    update(MH.ADVANCE_DELAY)
    assert(g_currentMission.aiSystem.started[3] == jobs[3])
    g_currentMission.aiSystem:stopJob(jobs[3], AIMessageSuccessFinishedJob.new())
    assert(MH.queues[vehicle] == nil)
    local note = g_currentMission.notifications[#g_currentMission.notifications]
    assert(note.kind == "ok" and note.text == "Tractor 7 finished")
end)

test("stop by the player, errors and deletion pause the queue", function()
    for _, reason in ipairs({"player", "error", "deleted"}) do
        objects, g_currentMission.notifications = {}, {}
        for vehicle in pairs(MH.queues) do MH.deleteQueue(vehicle) end
        local vehicle = seat(mockVehicle(7))
        local first, second = newJob(vehicle, 1, 1), newJob(vehicle, 2, 2)
        MH.requestAdd(vehicle, first)
        MH.requestAdd(vehicle, second)
        MH.requestStart(vehicle)
        local frame = mockFrame()
        if reason == "player" then
            -- Drawer Cancel job: the same call as InGameMenuMapFrame:cancelJob.
            assert(MF.startStop(frame))
        elseif reason == "error" then
            g_currentMission.aiSystem:stopJob(first, AIMessageErrorOutOfFill.new())
        else
            g_currentMission.aiSystem:stopJob(first, nil)
        end
        update(MH.ADVANCE_DELAY * 2)
        local started = g_currentMission.aiSystem.started
        assert(started[#started] == first, "next job must not start after " .. reason)
        local queue = MH.queues[vehicle]
        assert(not queue.running and queue.pause == MH.PAUSE.STOPPED and #queue.entries == 1)
        local note = g_currentMission.notifications[1]
        assert(note.kind == "info" and note.text == "Tractor 7 paused, 1 waiting")
        local state = MF.getDrawerState(frame)
        assert(state.status:find("Paused: mh_reasonStopped", 1, true) and state.startStop == "queue" and state.canStartStop)
        MH.requestStart(vehicle)
        assert(started[#started] == second and queue.pause == MH.PAUSE.NONE)
    end
end)

test("a job that cannot start keeps its place and shows the native reason", function()
    local vehicle = seat(mockVehicle(7))
    MH.requestAdd(vehicle, newJob(vehicle, 1, 1))
    g_currentMission.aiSystem.limitReached = true
    MH.requestStart(vehicle)
    local queue = MH.queues[vehicle]
    assert(queue.pause == MH.PAUSE.START_FAILED and queue.startState == 1 and #queue.entries == 1)
    assert(MH.getPauseReason(queue) == "GoTo start error 1")
    g_currentMission.aiSystem.limitReached = false
    queue.entries[1].job.valid = false
    MH.requestStart(vehicle)
    assert(queue.pause == MH.PAUSE.INVALID and MH.getPauseReason(queue) == "mh_reasonInvalid")
    assert(#g_currentMission.aiSystem.started == 0)
end)

test("the player's own seat is not reported as in use", function()
    local vehicle = seat(mockVehicle(7))
    local seatConnection = {farmId = 1}
    vehicle.spec_enterable = {isControlled = true}
    vehicle.ownerConnection = seatConnection
    local job = newJob(vehicle)
    MH.requestAdd(vehicle, job)
    MH.requestStart(vehicle)
    assert(job.startConnection == seatConnection)
end)

test("jobs the queue did not start are ignored", function()
    local vehicle = seat(mockVehicle(7))
    MH.requestAdd(vehicle, newJob(vehicle))
    local manual = newJob(vehicle)
    g_currentMission.aiSystem:startJob(manual, 1)
    g_currentMission.aiSystem:stopJob(manual, AIMessageSuccessFinishedJob.new())
    update(MH.ADVANCE_DELAY)
    assert(#g_currentMission.aiSystem.started == 1 and #MH.getEntries(vehicle) == 1)
    assert(MH.queues[vehicle].pause == MH.PAUSE.NONE and #g_currentMission.notifications == 0)
end)

test("deleted vehicles and owner changes drop the queue", function()
    local vehicle = seat(mockVehicle(7))
    local job = newJob(vehicle)
    MH.requestAdd(vehicle, job)
    vehicle.isDeleted = true
    update(16)
    assert(MH.queues[vehicle] == nil and job.deleted)
    local other = mockVehicle(8)
    MH.handleRequest(MH.ACTION.ADD, other, newJob(other), nil, localConnection)
    local count = #broadcasts
    other.farmId = 2
    update(16)
    assert(MH.queues[other] == nil and #broadcasts == count + 1 and #broadcasts[#broadcasts].queue.entries == 0)
end)

test("request and state events serialize jobs with their native stream", function()
    local vehicle = mockVehicle(7)
    local job = newJob(vehicle, 5, 6)
    local request = MHQueueRequestEvent.new(MH.ACTION.ADD, vehicle, job, nil)
    local stream = {}
    request:writeStream(stream, {})
    local client = {farmId = 1, allowed = true, getIsServer = function() return false end}
    MHQueueRequestEvent.emptyNew():readStream(stream, client)
    assert(#stream == 0)
    local entry = MH.getEntries(vehicle)[1]
    assert(entry.job ~= job and entry.job.positionParameter.x == 5 and entry.job.vehicleParameter:getVehicle() == vehicle)
    -- Server state reaches a client copy; an unknown job type is skipped as a whole.
    local stateEvent = broadcasts[#broadcasts]
    stream = {}
    stateEvent:writeStream(stream, client)
    local server = {getIsServer = function() return true end}
    g_currentMission = newMission(false)
    MH.queues = {}
    MHQueueStateEvent.emptyNew():readStream(stream, server)
    local copy = MH.getEntries(vehicle)
    assert(#copy == 1 and copy[1].id == entry.id and copy[1].job.positionParameter.z == 6)
    assert(MH.getJobLabel(copy[1].job) == "Go to - 5, 6")
    -- A client ignores requests and the server ignores state events.
    local ignored = newJob(vehicle)
    MHQueueRequestEvent.new(MH.ACTION.ADD, vehicle, ignored):run(server)
    assert(ignored.deleted and #MH.getEntries(vehicle) == 1)
end)

test("save and load round trip restores queues and drops what no longer exists", function()
    local vehicle = seat(mockVehicle(7, 1, "vehicleA"))
    local gone = mockVehicle(8, 1, "vehicleB")
    MH.requestAdd(vehicle, newJob(vehicle, 10, 20))
    local station = newJob(vehicle, nil, nil, AIJobType.LOADANDDELIVER)
    station.stationParameter.name = "Grain silo"
    MH.requestAdd(vehicle, station)
    MH.handleRequest(MH.ACTION.ADD, gone, newJob(gone, 3, 4), nil, localConnection)
    FSCareerMissionInfo.saveToXMLFile(g_currentMission.missionInfo)
    local saved = files["savegame1/mapHelper.xml"]
    assert(saved ~= nil and saved["mapHelper.queue(0)#vehicleUniqueId"] == "vehicleA")
    assert(saved["mapHelper.queue(0).job(1)#type"] == "LOADANDDELIVER")
    saved["mapHelper.queue(0).job(2)#type"] = "REMOVED_MOD_JOB"
    saved["mapHelper.queue(0).job(2).parameter(0)#name"] = "vehicle"
    -- New session: vehicle B was sold, vehicle A got a new network id.
    MH.onMissionDeleted(g_currentMission)
    objects = {}
    local reloaded = mockVehicle(42, 1, "vehicleA")
    g_currentMission = newMission(true)
    FSBaseMission.onStartMission(g_currentMission)
    local entries = MH.getEntries(reloaded)
    assert(#entries == 2 and entries[1].job.vehicleParameter:getVehicle() == reloaded)
    assert(entries[1].job.positionParameter.x == 10 and entries[1].job.setValuesCount == 1)
    assert(MH.getJobLabel(entries[2].job) == "Load and deliver - Grain silo")
    assert(logged.infos[1]:find("Dropped 2"), logged.infos[1])
    local queue = MH.queues[reloaded]
    assert(not queue.running and queue.pause == MH.PAUSE.NONE)
end)

test("saving with no queues overwrites stale queue data", function()
    files["savegame1/mapHelper.xml"] = {["mapHelper.queue(0)#vehicleUniqueId"] = "old"}
    MH.onSavegameSaved(g_currentMission.missionInfo)
    assert(files["savegame1/mapHelper.xml"]["mapHelper.queue(0)#vehicleUniqueId"] == nil)
    g_currentMission.missionInfo.isValid = false
    files = {}
    MH.onSavegameSaved(g_currentMission.missionInfo)
    assert(files["savegame1/mapHelper.xml"] == nil)
end)

test("joining players receive every queue", function()
    local a, b = mockVehicle(7), mockVehicle(8)
    MH.handleRequest(MH.ACTION.ADD, a, newJob(a), nil, localConnection)
    MH.handleRequest(MH.ACTION.ADD, b, newJob(b), nil, localConnection)
    local sent = {}
    FSBaseMission.sendInitialClientState(g_currentMission, {sendEvent = function(_, event) table.insert(sent, event) end}, {}, {})
    assert(#sent == 2 and sent[1].notify == MH.NOTIFY.NONE)
end)

test("map page hooks are idempotent across repeated registration and loads", function()
    local frame = mockFrame()
    InGameMenuMapFrame.onLoadMapFinished(frame)
    InGameMenuMapFrame.onLoadMapFinished(frame)
    local header = frame.shopMoneyBox.parent
    assert(#header.elements == 2, "balance plus one Map Helper button")
    assert(#frame.createJobContainer.elements == 1)
    assert(frame.mapHelper.toggle:getDescendantByName("text").text == "mh_toggle")
    -- A new frame for the next mission gets its own button; profiles load once.
    local profileLoads = g_gui.profileLoads
    local second = mockFrame()
    InGameMenuMapFrame.onLoadMapFinished(second)
    assert(#second.shopMoneyBox.parent.elements == 2 and g_gui.profileLoads == profileLoads)
    InGameMenuMapFrame.registerInput(frame)
    InGameMenuMapFrame.registerInput(frame)
    assert(#g_inputBinding.events == 2)
    local starts = 0
    local original = MH.onMissionStarted
    MH.onMissionStarted = function() starts = starts + 1 end
    FSBaseMission.onStartMission(g_currentMission)
    MH.onMissionStarted = original
    assert(starts == 1, "one dispatch per call after re-registration")
end)

test("hotkeys open the drawer and add the job being created", function()
    local vehicle = seat(mockVehicle(7))
    local frame = frameWithJobMenu(vehicle)
    InGameMenuMapFrame.registerInput(frame)
    g_inputBinding:trigger(InputAction.MH_ADD_TO_QUEUE)
    assert(#MH.getEntries(vehicle) == 1 and frame.mode == InGameMenuMapFrame.AI_MODE_OVERVIEW)
    g_inputBinding:trigger(InputAction.MH_ADD_TO_QUEUE)
    assert(#MH.getEntries(vehicle) == 1, "nothing to add outside the job menu")
    g_inputBinding:trigger(InputAction.MH_TOGGLE_DRAWER)
    assert(g_gui.openDialog ~= nil and g_gui.openDialog.frame == frame)
    g_gui.openDialog:onClickBack()
    assert(g_gui.openDialog == nil)
    frame.mapHelper.toggle:getDescendantByName("button").onClickCallback(frame.mapHelper)
    assert(g_gui.openDialog ~= nil)
    g_gui.openDialog:onClickBack()
end)

test("drawer dialog lists the queue and sends remove, clear and start requests", function()
    local vehicle = seat(mockVehicle(7))
    MH.requestAdd(vehicle, newJob(vehicle, 1, 2))
    MH.requestAdd(vehicle, newJob(vehicle, 3, 4))
    local frame = mockFrame()
    InGameMenuMapFrame.onLoadMapFinished(frame)
    assert(MF.openDrawer(frame))
    local dialog = g_gui.openDialog
    assert(dialog.dialogType == DialogElement.TYPE_INFO and dialog.drawerPanel.position[2] ~= nil)
    assert(#dialog.rows == 2 and dialog.rows[1].element:getDescendantByName("label").text == "1. Go to - 1, 2")
    assert(dialog.startStopButton.text == "mh_startQueue" and not dialog.startStopButton.disabled)
    assert(not dialog.queueEmptyText.visible and FocusManager.focused == dialog.centerButton)
    dialog.rows[1].button.onClickCallback(dialog, dialog.rows[1].button)
    assert(#MH.getEntries(vehicle) == 1 and #dialog.rows == 1, "listener refreshed the open drawer")
    assert(dialog.rows[1].element:getDescendantByName("label").text == "1. Go to - 3, 4")
    dialog:onClickStartStop()
    assert(#g_currentMission.aiSystem.started == 1 and dialog.isOpen)
    assert(dialog.startStopButton.text == "button_cancelJob" and dialog.createButton.disabled)
    dialog:onClickStartStop()
    assert(not vehicle:getIsAIActive() and MH.queues[vehicle] == nil)
    dialog:update(MHDrawerDialog.REFRESH_INTERVAL)
    assert(dialog.queueEmptyText.visible and #dialog.rows == 0 and dialog.clearButton.disabled)
    dialog:onClickBack()
    assert(#MH.listeners == 0)
end)

test("drawer actions that need the map close it first", function()
    local vehicle = seat(mockVehicle(7))
    local frame = mockFrame()
    InGameMenuMapFrame.onLoadMapFinished(frame)
    MF.openDrawer(frame)
    g_gui.openDialog:onClickCreate()
    assert(g_gui.openDialog == nil and frame.mode == InGameMenuMapFrame.AI_MODE_CREATE)
    frame:onClickBack()
    MF.openDrawer(frame)
    g_gui.openDialog:onClickCenter()
    assert(g_gui.openDialog == nil and frame.ingameMap.pannedTo == vehicle.hotspot)
    MF.openDrawer(frame)
    local dialog = g_gui.openDialog
    dialog.time = dialog.inputDelay
    dialog:onClickGoTo()
    assert(g_gui.openDialog ~= nil and frame.goToStarted == nil, "opening key repeat is ignored")
    dialog.time = dialog.inputDelay + 1
    dialog:onClickGoTo()
    assert(g_gui.openDialog == nil and frame.goToStarted == 1)
    -- On foot the drawer hides the vehicle actions.
    seat(nil)
    MF.openDrawer(frame)
    dialog = g_gui.openDialog
    assert(not dialog.createButton.visible and not dialog.queueRows.visible and dialog.titleText.text == "mh_onFoot")
    dialog:onClickCreate()
    assert(g_gui.openDialog == dialog)
    dialog:onClickBack()
end)

test("start job in the drawer uses the open job menu", function()
    local vehicle = seat(mockVehicle(7))
    local frame = frameWithJobMenu(vehicle)
    local state = MF.getDrawerState(frame)
    assert(state.startStop == "start" and state.canStartStop and not state.canCreate)
    MF.openDrawer(frame)
    g_gui.openDialog:onClickStartStop()
    assert(g_gui.openDialog == nil and frame.startCancel == 1)
end)

test("clients only send requests and wait for the server", function()
    local vehicle = seat(mockVehicle(7))
    g_currentMission = newMission(false)
    local sent = {}
    local previousClient, previousServer = g_client, g_server
    g_server = nil
    g_client = {getServerConnection = function() return {sendEvent = function(_, event) table.insert(sent, event) end} end}
    local frame = frameWithJobMenu(vehicle)
    assert(MF.addToQueue(frame))
    assert(#sent == 1 and sent[1].action == MH.ACTION.ADD and #MH.getEntries(vehicle) == 0)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, newJob(vehicle), nil, localConnection), "clients never apply")
    g_client, g_server = previousClient, previousServer
end)

test("queued field work uses the vehicle's worker settings when it starts", function()
    local vehicle = seat(mockVehicle(7))
    vehicle.aiSettings = "A"
    local job = newJob(vehicle, 5, 5, AIJobType.FIELDWORK)
    local stream = {}
    MHQueueRequestEvent.new(MH.ACTION.ADD, vehicle, job):writeStream(stream, {})
    local client = {farmId = 1, allowed = true, getIsServer = function() return false end}
    MHQueueRequestEvent.emptyNew():readStream(stream, client)
    local queued = MH.getEntries(vehicle)[1].job
    assert(queued.pendingData == nil and queued.pendingVehicle == nil, "the requester's copy is dropped")
    -- The player changes the worker settings after queueing; the state event sends what starts.
    vehicle.aiSettings = "B"
    stream = {}
    broadcasts[#broadcasts]:writeStream(stream, client)
    local copy = MHQueueStateEvent.emptyNew()
    g_currentMission = newMission(false)
    local serverQueues = MH.queues
    MH.queues = {}
    copy:readStream(stream, {getIsServer = function() return true end})
    assert(MH.getEntries(vehicle)[1].job.pendingData == nil)
    g_currentMission = newMission(true)
    MH.queues = serverQueues
    MH.requestStart(vehicle)
    assert(g_currentMission.aiSystem.started[1] == queued and vehicle.aiSettings == "B")
end)

test("map page controls are removed with the mission and come back only when the Mod is active", function()
    -- g_inGameMenu keeps one map frame for the whole game session.
    local frame = mockFrame()
    local header = frame.shopMoneyBox.parent
    seat(mockVehicle(7))
    InGameMenuMapFrame.onLoadMapFinished(frame)
    InGameMenuMapFrame.registerInput(frame)
    local oldExt = frame.mapHelper
    local oldToggle = oldExt.toggle:getDescendantByName("button")
    MF.openDrawer(frame)
    assert(g_gui.openDialog ~= nil and #header.elements == 2 and #g_inputBinding.events == 2)
    -- Leave the save: the open drawer, both buttons and the key events go.
    FSBaseMission.delete(g_currentMission)
    assert(g_gui.openDialog == nil and g_gui.guis[MHDrawerDialog.NAME] == nil and g_gui.nameScreenTypes[MHDrawerDialog.NAME] == nil)
    assert(frame.mapHelper == nil and #header.elements == 1 and #frame.createJobContainer.elements == 0)
    assert(#g_inputBinding.events == 0 and #g_messageCenter.subscribers == 0 and not MH.missionActive)
    -- Next save without the Mod: hooks stay quiet and left-over callbacks do nothing.
    g_modIsLoaded[g_currentModName] = false
    g_currentMission = newMission(true)
    FSBaseMission.onStartMission(g_currentMission)
    InGameMenuMapFrame.onLoadMapFinished(frame)
    InGameMenuMapFrame.registerInput(frame)
    oldToggle.onClickCallback(oldExt)
    MF.onToggleAction(oldExt)
    assert(frame.mapHelper == nil and #header.elements == 1 and #g_inputBinding.events == 0)
    assert(g_gui.openDialog == nil and #g_messageCenter.subscribers == 0 and next(g_currentMission.updateables) == nil)
    FSBaseMission.delete(g_currentMission)
    -- A save with the Mod again: one fresh set of controls and a working drawer.
    g_modIsLoaded[g_currentModName] = true
    g_currentMission = newMission(true)
    FSBaseMission.onStartMission(g_currentMission)
    InGameMenuMapFrame.onLoadMapFinished(frame)
    InGameMenuMapFrame.registerInput(frame)
    assert(frame.mapHelper ~= nil and frame.mapHelper ~= oldExt and #header.elements == 2 and #g_inputBinding.events == 2)
    oldToggle.onClickCallback(oldExt)
    assert(g_gui.openDialog == nil, "controls of the previous save stay inert")
    frame.mapHelper.toggle:getDescendantByName("button").onClickCallback(frame.mapHelper)
    assert(g_gui.openDialog ~= nil and g_gui.openDialog.frame == frame)
    g_gui.openDialog:onClickBack()
    -- Controls left by an earlier copy of the scripts are replaced, not duplicated.
    MF.remove(frame)
    local stale = {toggle = mockElement("staleToggle")}
    header:addElement(stale.toggle)
    frame.mapHelper = stale
    InGameMenuMapFrame.onLoadMapFinished(frame)
    assert(stale.toggle == nil and #header.elements == 2 and frame.mapHelper ~= stale)
end)

print(string.format("%d behavioral tests passed", passed))
