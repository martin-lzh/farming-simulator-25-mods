local MH = MapHelper
local MF = MHMapFrame
local passed = 0
local function test(name, body)
    -- Every test starts a fresh host mission (server with a local player).
    objects, files, broadcasts, infoDialogs = {}, {}, {}, {}
    g_messageCenter.subscribers = {}
    g_inputBinding.events = {}
    g_inputBinding.currentContext, g_inputBinding.registrationContext = "PLAYER", nil
    g_fieldManager.fields, g_farmlandManager.owners, g_missionManager.missions = {}, {}, {}
    workedStrips = {}
    MHFieldNeeds.mergeCache = {}
    logged.warnings, logged.infos = {}, {}
    MH.onMissionDeleted(nil)
    g_currentMission = newMission(true)
    g_localPlayer.farmId, g_localPlayer.vehicle = 1, nil
    localConnection.farmId, localConnection.allowed, localConnection.userId = 1, true, nil
    g_inGameMenu.pageMapOverview = nil
    FSBaseMission.onStartMission(g_currentMission)
    body()
    passed = passed + 1
    print("PASS " .. name)
end
local function newJob(vehicle, x, z, typeIndex)
    local job = g_currentMission.aiJobTypeManager:createJob(typeIndex or AIJobType.GOTO)
    job.vehicleParameter:setVehicle(vehicle)
    if job.positionAngleParameter ~= nil then
        job.positionAngleParameter:setPosition(x or 1, z or 2)
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
local function isQueued(vehicle, job)
    for _, entry in ipairs(MH.getEntries(vehicle)) do
        if entry.job == job then return true end
    end
    return false
end
-- A worker the player started himself: jobs added now wait behind it.
local function startManual(vehicle)
    local job = newJob(vehicle, 0, 0)
    g_currentMission.aiSystem:startJob(job, 1)
    return job
end
-- Waiting entries without a worker: queued behind a job the player started and then stopped.
local function pausedQueue(vehicle, jobs)
    startManual(vehicle)
    for _, job in ipairs(jobs) do MH.requestAdd(vehicle, job) end
    vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
    g_currentMission.notifications = {}
    return MH.queues[vehicle]
end
-- A map page as the in-game menu shows it: loaded, opened, Map Helper page selected.
local function openPage()
    local frame = mockFrame()
    g_inGameMenu.pageMapOverview = frame
    InGameMenuMapFrame.onLoadMapFinished(frame)
    frame:onFrameOpen()
    local ext = frame.mapHelper
    frame.mapOverviewSelector:setState(ext.pageIndex, true)
    return frame, ext.page, ext
end
local function rowTexts(page)
    local result = {}
    for i = 1, page.mhQueueList:getItemCount() do
        local cell = page.mhQueueList:getElementAtSectionIndex(1, i)
        table.insert(result, cell:getAttribute("index"):getText() .. "|" .. cell:getAttribute("title"):getText()
            .. "|" .. cell:getAttribute("text"):getText())
    end
    return result
end
local function placeTexts(page)
    local result = {}
    for _, cell in ipairs(page.mhPlacesList.cells[1] or {}) do
        table.insert(result, cell:getAttribute("name"):getText() .. "|" .. cell:getAttribute("info"):getText())
    end
    return table.concat(result, ";")
end

-- Queue model and server ------------------------------------------------------------------
test("feature checks pass against the doubles and both events are registered", function()
    assert(MH.features.queue and MH.features.page and MH.features.hotkey and MH.features.fieldNeeds)
    assert(registeredEvents.MHQueueRequestEvent >= 1 and registeredEvents.MHQueueStateEvent >= 1)
    assert(g_messageCenter.subscribers[1].type == MessageType.AI_JOB_STOPPED)
    assert(g_currentMission.updateables[MH] == MH)
end)

test("server permission follows hireAssistant and the vehicle's farm", function()
    local vehicle = mockVehicle(7)
    local job = newJob(vehicle)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, job, nil, {farmId = 2, allowed = true}))
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, newJob(vehicle), nil, {farmId = 1, allowed = false}))
    assert(#MH.getEntries(vehicle) == 0 and #broadcasts == 0 and #g_currentMission.aiSystem.started == 0)
    vehicle.farmId = FarmManager.SPECTATOR_FARM_ID
    assert(not MH.getCanManage(vehicle, nil))
end)

test("queue holds at most the limit and server-side validation still applies", function()
    local vehicle = mockVehicle(7)
    startManual(vehicle)
    for i = 1, MH.MAX_ENTRIES do
        assert(MH.handleRequest(MH.ACTION.ADD, vehicle, newJob(vehicle, i, i), nil, localConnection))
    end
    local extra = newJob(vehicle)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, extra, nil, localConnection) and not isQueued(vehicle, extra))
    local other = mockVehicle(8)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, newJob(other), nil, localConnection), "job for another vehicle")
    local invalid = newJob(other)
    invalid.valid = false
    assert(not MH.handleRequest(MH.ACTION.ADD, other, invalid, nil, localConnection) and MH.queues[other] == nil)
    local edit = newJob(vehicle)
    edit.valid = false
    assert(not MH.handleRequest(MH.ACTION.EDIT, vehicle, edit, MH.getEntries(vehicle)[1].id, localConnection))
end)

test("the first job added to an idle vehicle starts right away; later ones wait", function()
    local vehicle = mockVehicle(7)
    local first, second, third = newJob(vehicle, 1, 1), newJob(vehicle, 2, 2), newJob(vehicle, 3, 3)
    MH.requestAdd(vehicle, first)
    local started = g_currentMission.aiSystem.started
    assert(#started == 1 and started[1] == first and vehicle:getIsAIActive())
    local queue = MH.queues[vehicle]
    assert(queue.running and queue.runningJob == first and #queue.entries == 0 and queue.pause == MH.PAUSE.NONE)
    MH.requestAdd(vehicle, second)
    MH.requestAdd(vehicle, third, true)
    assert(#started == 1 and queue.entries[1].job == third and queue.entries[2].job == second)
    -- Between two queued jobs the queue keeps running: an added job just waits.
    g_currentMission.aiSystem:stopJob(first, AIMessageSuccessFinishedJob.new())
    MH.requestAdd(vehicle, newJob(vehicle, 4, 4))
    assert(#started == 1 and #queue.entries == 3)
    update(MH.ADVANCE_DELAY)
    assert(started[2] == third)
    -- Insert as next on an idle vehicle starts the job as well.
    local other = mockVehicle(8)
    local nextJob = newJob(other, 5, 5)
    MH.requestAdd(other, nextJob, true)
    assert(started[3] == nextJob)
end)

test("adding to a paused queue resumes it; Resume continues it without adding", function()
    local vehicle = mockVehicle(7)
    local a, b = newJob(vehicle, 1, 1), newJob(vehicle, 2, 2)
    local queue = pausedQueue(vehicle, {a, b})
    assert(queue.pause == MH.PAUSE.STOPPED and #queue.entries == 2 and not vehicle:getIsAIActive())
    MH.requestAdd(vehicle, newJob(vehicle, 3, 3))
    local started = g_currentMission.aiSystem.started
    assert(started[#started] == a, "resumes with the first waiting job, not the added one")
    assert(queue.pause == MH.PAUSE.NONE and queue.running and #queue.entries == 2)
    vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
    assert(queue.pause == MH.PAUSE.STOPPED)
    MH.requestStart(vehicle)
    assert(started[#started] == b and queue.running)
    assert(not MH.handleRequest(MH.ACTION.START, vehicle, nil, nil, localConnection), "a worker is driving")
end)

test("insert as next, move, edit and remove work by entry id", function()
    local vehicle = mockVehicle(7)
    startManual(vehicle)
    local jobs = {newJob(vehicle, 1, 1), newJob(vehicle, 2, 2), newJob(vehicle, 3, 3)}
    MH.requestAdd(vehicle, jobs[1])
    MH.requestAdd(vehicle, jobs[2])
    MH.requestAdd(vehicle, jobs[3], true)
    local entries = MH.getEntries(vehicle)
    assert(entries[1].job == jobs[3] and entries[2].job == jobs[1] and entries[3].job == jobs[2], "inserted as next")
    local id = entries[3].id
    assert(MH.requestMove(vehicle, id, true) and MH.getEntries(vehicle)[2].id == id)
    assert(not MH.handleRequest(MH.ACTION.MOVE, vehicle, nil, MH.getEntries(vehicle)[1].id, localConnection, true), "first stays first")
    assert(not MH.handleRequest(MH.ACTION.MOVE, vehicle, nil, MH.getEntries(vehicle)[3].id, localConnection, false), "last stays last")
    local replacement = newJob(vehicle, 9, 9)
    MH.requestEdit(vehicle, id, replacement)
    entries = MH.getEntries(vehicle)
    assert(entries[2].id == id and entries[2].job == replacement and replacement.setValuesCount >= 1 and not isQueued(vehicle, jobs[2]))
    assert(not MH.handleRequest(MH.ACTION.EDIT, vehicle, newJob(vehicle), 999, localConnection), "unknown entry")
    assert(MH.requestRemove(vehicle, id))
    assert(#MH.getEntries(vehicle) == 2 and not isQueued(vehicle, replacement))
    assert(not MH.handleRequest(MH.ACTION.REMOVE, vehicle, nil, id, localConnection), "already removed")
    MH.requestClear(vehicle)
    assert(MH.queues[vehicle] == nil)
end)

test("queue advances only after a successful finish", function()
    local vehicle = mockVehicle(7)
    local jobs = {newJob(vehicle, 1, 1), newJob(vehicle, 2, 2), newJob(vehicle, 3, 3)}
    for _, job in ipairs(jobs) do MH.requestAdd(vehicle, job) end
    assert(g_currentMission.aiSystem.started[1] == jobs[1])
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
        MH.queues = {}
        local vehicle = mockVehicle(7)
        local first, second = newJob(vehicle, 1, 1), newJob(vehicle, 2, 2)
        MH.requestAdd(vehicle, first)
        MH.requestAdd(vehicle, second)
        if reason == "player" then
            vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
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
        MH.requestStart(vehicle)
        assert(started[#started] == second and queue.pause == MH.PAUSE.NONE)
    end
end)

test("a job that cannot start keeps its place and shows the native reason", function()
    local vehicle = mockVehicle(7)
    g_currentMission.aiSystem.limitReached = true
    MH.requestAdd(vehicle, newJob(vehicle, 1, 1))
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
    local seatConnection = {farmId = 1, userId = 1}
    localConnection.userId = 1
    vehicle.spec_enterable = {isControlled = true, controllerUserId = 1}
    vehicle.ownerConnection = seatConnection
    local job = newJob(vehicle)
    MH.requestAdd(vehicle, job)
    assert(job.startConnection == seatConnection and g_currentMission.aiSystem.started[1] == job)
end)

test("a vehicle another player sits in is not started for someone else", function()
    local vehicle = mockVehicle(7)
    local driver = {farmId = 1, userId = 2}
    localConnection.userId = 1
    vehicle.spec_enterable = {isControlled = true, controllerUserId = 2}
    vehicle.ownerConnection = driver
    local job = newJob(vehicle)
    MH.requestAdd(vehicle, job)
    local queue = MH.queues[vehicle]
    -- Refused with the game's own "in use" reason; the job waits.
    assert(#g_currentMission.aiSystem.started == 0 and job.startConnection == localConnection)
    assert(queue.pause == MH.PAUSE.START_FAILED and queue.startState == 5 and MH.getPauseReason(queue) == "GoTo start error 5")
    assert(queue.entries[1].job == job)
    MH.requestStart(vehicle)
    assert(#g_currentMission.aiSystem.started == 0, "Resume is refused the same way")
    -- The driver gets out: Resume starts it.
    vehicle.spec_enterable.isControlled = false
    MH.requestStart(vehicle)
    assert(g_currentMission.aiSystem.started[1] == job and queue.pause == MH.PAUSE.NONE)
    -- A queue that advances on its own keeps going for a driver who got in meanwhile.
    MH.requestAdd(vehicle, newJob(vehicle, 5, 5))
    vehicle.spec_enterable.isControlled = true
    g_currentMission.aiSystem:stopJob(job, AIMessageSuccessFinishedJob.new())
    update(MH.ADVANCE_DELAY)
    assert(#g_currentMission.aiSystem.started == 2 and g_currentMission.aiSystem.started[2].startConnection == driver)
end)

test("jobs the queue did not start are ignored", function()
    local vehicle = mockVehicle(7)
    local queue = pausedQueue(vehicle, {newJob(vehicle)})
    local manual = newJob(vehicle)
    g_currentMission.aiSystem:startJob(manual, 1)
    g_currentMission.aiSystem:stopJob(manual, AIMessageSuccessFinishedJob.new())
    update(MH.ADVANCE_DELAY)
    assert(#g_currentMission.aiSystem.started == 2 and #MH.getEntries(vehicle) == 1)
    assert(queue.pause == MH.PAUSE.STOPPED and #g_currentMission.notifications == 0)
end)

test("deleted vehicles and owner changes drop the queue", function()
    local vehicle = mockVehicle(7)
    MH.requestAdd(vehicle, newJob(vehicle))
    vehicle.isDeleted = true
    update(16)
    assert(MH.queues[vehicle] == nil)
    local other = mockVehicle(8)
    MH.handleRequest(MH.ACTION.ADD, other, newJob(other), nil, localConnection)
    local count = #broadcasts
    other.farmId = 2
    update(16)
    assert(MH.queues[other] == nil and #broadcasts == count + 1 and #broadcasts[#broadcasts].queue.entries == 0)
end)

test("request and state events serialize every action with the native job stream", function()
    local vehicle = mockVehicle(7)
    startManual(vehicle)
    local client = {farmId = 1, allowed = true, getIsServer = function() return false end}
    local function send(event)
        local stream = {}
        event:writeStream(stream, {})
        MHQueueRequestEvent.emptyNew():readStream(stream, client)
        assert(#stream == 0, "every value read back")
    end
    send(MHQueueRequestEvent.new(MH.ACTION.ADD, vehicle, newJob(vehicle, 5, 6), nil, false))
    send(MHQueueRequestEvent.new(MH.ACTION.ADD, vehicle, newJob(vehicle, 7, 8), nil, true))
    local entries = MH.getEntries(vehicle)
    assert(entries[1].job.positionAngleParameter.x == 7 and entries[2].job.positionAngleParameter.x == 5)
    send(MHQueueRequestEvent.new(MH.ACTION.MOVE, vehicle, nil, entries[2].id, true))
    assert(MH.getEntries(vehicle)[1].job.positionAngleParameter.x == 5)
    local editedId = MH.getEntries(vehicle)[2].id
    send(MHQueueRequestEvent.new(MH.ACTION.EDIT, vehicle, newJob(vehicle, 1, 1, AIJobType.FIELDWORK), editedId))
    assert(MH.getEntries(vehicle)[2].job.jobTypeIndex == AIJobType.FIELDWORK and MH.getEntries(vehicle)[2].id == editedId)
    send(MHQueueRequestEvent.new(MH.ACTION.REMOVE, vehicle, nil, editedId))
    vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
    send(MHQueueRequestEvent.new(MH.ACTION.START, vehicle))
    assert(#MH.getEntries(vehicle) == 0 and #g_currentMission.aiSystem.started == 2)
    -- Server state reaches a client copy.
    MH.requestAdd(vehicle, newJob(vehicle, 3, 4))
    local stateEvent = broadcasts[#broadcasts]
    local stream = {}
    stateEvent:writeStream(stream, client)
    local server = {getIsServer = function() return true end}
    g_currentMission = newMission(false)
    MH.queues = {}
    MHQueueStateEvent.emptyNew():readStream(stream, server)
    local copy = MH.getEntries(vehicle)
    assert(#copy == 1 and copy[1].job.positionAngleParameter.z == 4 and MH.queues[vehicle].running)
    assert(MH.getJobLabel(copy[1].job) == "Go to - 3, 4")
    -- A client ignores requests and the server ignores state events.
    local ignored = newJob(vehicle)
    MHQueueRequestEvent.new(MH.ACTION.ADD, vehicle, ignored):run(server)
    assert(not isQueued(vehicle, ignored) and #MH.getEntries(vehicle) == 1)
end)

test("save and load round trip restores queues and drops what no longer exists", function()
    local vehicle = mockVehicle(7, 1, "vehicleA")
    local gone = mockVehicle(8, 1, "vehicleB")
    local silo = mockStation(500, "Grain silo", 0, 0)
    startManual(vehicle)
    startManual(gone)
    MH.requestAdd(vehicle, newJob(vehicle, 10, 20))
    local station = newJob(vehicle, nil, nil, AIJobType.LOAD_AND_DELIVER)
    station.loadingStationParameter:setLoadingStation(silo)
    MH.requestAdd(vehicle, station)
    MH.handleRequest(MH.ACTION.ADD, gone, newJob(gone, 3, 4), nil, localConnection)
    FSCareerMissionInfo.saveToXMLFile(g_currentMission.missionInfo)
    local saved = files["savegame1/mapHelper.xml"]
    assert(saved ~= nil and saved["mapHelper.queue(0)#vehicleUniqueId"] == "vehicleA")
    assert(saved["mapHelper.queue(0).job(1)#type"] == "LOAD_AND_DELIVER")
    saved["mapHelper.queue(0).job(2)#type"] = "REMOVED_MOD_JOB"
    saved["mapHelper.queue(0).job(2).parameter(0)#name"] = "vehicle"
    -- New session: vehicle B was sold, vehicle A got a new network id.
    FSBaseMission.delete(g_currentMission)
    objects = {}
    mockStation(500, "Grain silo", 0, 0)
    local reloaded = mockVehicle(42, 1, "vehicleA")
    g_currentMission = newMission(true)
    FSBaseMission.onStartMission(g_currentMission)
    local entries = MH.getEntries(reloaded)
    assert(#entries == 2 and entries[1].job.vehicleParameter:getVehicle() == reloaded)
    assert(entries[1].job.positionAngleParameter.x == 10 and entries[1].job.setValuesCount == 1)
    assert(MH.getJobLabel(entries[2].job) == "Load and deliver - Grain silo")
    assert(logged.infos[1]:find("Dropped 2"), logged.infos[1])
    local queue = MH.queues[reloaded]
    assert(not queue.running and queue.pause == MH.PAUSE.NONE, "a loaded queue waits for Resume")
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

test("queued field work uses the vehicle's worker settings when it starts", function()
    local vehicle = mockVehicle(7)
    local manual = startManual(vehicle)
    vehicle.aiSettings = "A"
    local job = newJob(vehicle, 5, 5, AIJobType.FIELDWORK)
    local stream = {}
    MHQueueRequestEvent.new(MH.ACTION.ADD, vehicle, job):writeStream(stream, {})
    local client = {farmId = 1, allowed = true, getIsServer = function() return false end}
    MHQueueRequestEvent.emptyNew():readStream(stream, client)
    local queued = MH.getEntries(vehicle)[1].job
    assert(queued.pendingData == nil and queued.pendingVehicle == nil, "the requester's copy is dropped")
    vehicle.aiSettings = "B"
    g_currentMission.aiSystem:stopJob(manual, AIMessageSuccessFinishedJob.new())
    update(MH.ADVANCE_DELAY)
    assert(g_currentMission.aiSystem.started[2] == queued and vehicle.aiSettings == "B")
end)

test("quitting with queued jobs completes the mission teardown and never deletes a job", function()
    -- Regression: AIJob:delete raised in the FSBaseMission:delete hook and players could not
    -- leave the save. The double raises like the game, so any remaining call fails here.
    local vehicle = seat(mockVehicle(7))
    for i = 1, 3 do MH.requestAdd(vehicle, newJob(vehicle, i, i)) end
    local other = mockVehicle(8)
    MH.handleRequest(MH.ACTION.ADD, other, newJob(other), nil, localConnection)
    MH.requestRemove(vehicle, MH.getEntries(vehicle)[1].id)
    MH.requestEdit(vehicle, MH.getEntries(vehicle)[1].id, newJob(vehicle, 9, 9))
    local frame, page = openPage()
    assert(page:getIsShown())
    local mission = g_currentMission
    local broadcastCount = #broadcasts
    assert(vehicle:getIsAIActive(), "a running job is stopped by the AI system's deletion")
    FSBaseMission.delete(mission)
    assert(mission.deleted, "the game's own teardown ran")
    assert(not vehicle:getIsAIActive() and #mission.notifications == 0 and #broadcasts == broadcastCount,
        "nothing reacts to jobs stopped during the teardown")
    assert(not MH.missionActive and next(MH.queues) == nil and frame.mapHelper == nil)
    assert(next(mission.updateables) == nil and #g_messageCenter.subscribers == 0)
end)

-- Map page --------------------------------------------------------------------------------
test("the page is a new state of the overview selector and replaces the native containers", function()
    seat(mockVehicle(7))
    local frame, page, ext = openPage()
    assert(ext.pageIndex == 8 and frame.mapSelectorTexts[8] == "mh_toggle" and #frame.subCategoryDotBox.elements == 8)
    assert(ext.dot.getIsSelected())
    assert(page.root.visible and page.root.parent == frame.filterBox)
    assert(not frame.filterListContainer.visible and not frame.workerListContainer.visible and not frame.createJobEmptyText.visible)
    -- The native job form sits in the page's form slot, without Start job.
    assert(frame.createJobContainer.visible and frame.createJobContainer.profile == "mh_nativeForm")
    assert(frame.createJobContainer.anchorDeltasUpdated >= 1 and not frame.buttonStartJobContainer.visible)
    assert(frame.mode == InGameMenuMapFrame.AI_MODE_OVERVIEW and frame.currentJob ~= nil)
    assert(not ext.toggle.visible, "the header button steps aside on the page")
    -- Other pages get their containers back; the native form returns to its own place.
    frame.mapOverviewSelector:setState(InGameMenuMapFrame.AI_WORKER_LIST, true)
    assert(not page.root.visible and frame.workerListContainer.visible and ext.toggle.visible)
    assert(not frame.createJobContainer.visible and frame.createJobContainer.profile == "fs25_subCategoryListContainer")
    assert(frame.buttonStartJobContainer.visible and frame.currentJob == nil and #frame.jobMenuLayout.elements == 0)
    assert(not ext.dot.getIsSelected())
    -- The native Create job from the context box still opens state 6 with the native form.
    frame.mapOverviewSelector:setState(ext.pageIndex, true)
    frame:setMapSelectionItem(g_localPlayer.vehicle.hotspot)
    frame:createJob()
    assert(frame.mapOverviewSelector:getState() == InGameMenuMapFrame.AI_CREATE_JOB and not page.root.visible)
    assert(frame.createJobContainer.visible and frame.createJobContainer.profile == "fs25_subCategoryListContainer")
    assert(frame.buttonStartJobContainer.visible and frame.currentJob ~= nil and frame.currentJobVehicle == g_localPlayer.vehicle)
    assert(not ext.toggle.visible, "hidden in the native job menu")
end)

test("the page shows the vehicle the player sits in and explains when nothing can be planned", function()
    local frame, page = openPage()
    assert(page.mhVehicleTitle.text == "mh_onFoot" and page.mhVehicleStatus.text == "mh_statusOnFoot")
    assert(page.mhFormEmptyText.visible and frame.currentJob == nil and not frame.createJobContainer.visible)
    assert(page.mhAddButton.disabled and page.mhPlacesList:getItemCount() == 0)
    assert(page.mhFilterSelector.disabled and #page.mhFilterSelector.texts == 0 and not page.mhPlacesEmpty.visible)
    local vehicle = seat(mockVehicle(7))
    frame.mapOverviewSelector:setState(1, true)
    frame.mapOverviewSelector:setState(frame.mapHelper.pageIndex, true)
    assert(page.vehicle == vehicle and page.mhVehicleTitle.text == "Tractor 7" and page.mhVehicleStatus.text == "mh_statusIdle")
    assert(page.mhVehicleImage.visible and page.mhVehicleImage.imageFilename == "store/tractor7.dds")
    assert(not page.mhFormEmptyText.visible and frame.createJobContainer.visible and not page.mhAddButton.disabled)
    assert(frame.selected == vehicle.hotspot and frame.ingameMap.pannedTo == vehicle.hotspot)
    g_currentMission.allowed = false
    page:setVehicle(vehicle, false)
    assert(page.mhVehicleStatus.text == "mh_statusNoPermission" and page.mhFormEmptyText.visible and page.mhAddButton.disabled)
    vehicle.spec_aiJobVehicle = nil
    page:setVehicle(vehicle, false)
    assert(page.mhVehicleStatus.text == "mh_statusNoAI")
end)

test("the native form hides its vehicle row and keeps the native job type list", function()
    local vehicle = seat(mockVehicle(7))
    vehicle.canFieldWork = true
    local frame, page = openPage()
    assert(#frame.currentJobTypes == 2 and frame.jobTypeElement.texts[2] == "Field work")
    local layout = frame.jobMenuLayout.elements
    -- Group 1 is the vehicle (title + vehicle row), group 2 the target position.
    assert(not layout[1].visible and not layout[2].visible and layout[3].visible and layout[4].visible)
    -- Changing the job type in the native selector keeps the vehicle rows hidden.
    frame.jobTypeElement:setState(2)
    frame:onJobTypeChanged(2)
    assert(frame.currentJob.jobTypeIndex == AIJobType.FIELDWORK and not frame.jobMenuLayout.elements[2].visible)
end)

test("selecting another own vehicle on the map switches the page; the card switches back", function()
    local mine = seat(mockVehicle(7))
    local other = mockVehicle(8)
    local foreign = mockVehicle(9, 2)
    local frame, page = openPage()
    assert(page.mhVehicleInfo.text == "", "no hint on the own vehicle")
    frame:setMapSelectionItem(other.hotspot)
    assert(page.vehicle == other and frame.currentJobVehicle == other and page.mhVehicleTitle.text == "Tractor 8")
    assert(page.mhVehicleInfo.text == "mh_backToMine")
    frame:setMapSelectionItem(foreign.hotspot)
    assert(page.vehicle == other, "other farms' vehicles are only selected, not planned for")
    frame:setMapSelectionItem(nil)
    assert(page.vehicle == other and g_currentMission.mapHotspots[frame.aiTargetMapHotspot], "the form marker stays")
    page.mhVehicleCardButton.onClickCallback(page)
    assert(page.vehicle == mine and frame.ingameMap.pannedTo == mine.hotspot and page.mhVehicleInfo.text == "")
    -- On the own vehicle the card moves the map to it.
    frame.ingameMap.pannedTo = nil
    page.mhVehicleCardButton.onClickCallback(page)
    assert(page.vehicle == mine and frame.ingameMap.pannedTo == mine.hotspot)
end)

test("the place filter offers what the vehicle can use and remembers the choice per vehicle", function()
    local tractor = seat(mockVehicle(7))
    local truck = mockVehicle(8)
    truck.canDeliver = true
    local frame, page = openPage()
    local selector = page.mhFilterSelector
    -- Nothing recognised (no implement): all own fields first, no stations without a delivery job.
    assert(table.concat(selector.texts, ";") == "mh_filterFields;ui_contracts" and page.filterKey == "fields")
    attachImplement(tractor, {spec_plow = {}})
    page:setVehicle(tractor, false)
    assert(table.concat(selector.texts, ";") == "mh_filterNeeds;mh_filterFields;ui_contracts")
    assert(page.filterKey == "needs" and selector.state == 1 and not selector.disabled)
    selector:setState(3, true)
    assert(page.filterKey == "contracts")
    frame:setMapSelectionItem(truck.hotspot)
    assert(table.concat(selector.texts, ";") == "mh_filterFields;ui_contracts;ui_stations" and page.filterKey == "fields")
    selector:setState(3, true)
    -- Back on the tractor (card), then the truck again: each keeps its own choice.
    page.mhVehicleCardButton.onClickCallback(page)
    assert(page.vehicle == tractor and page.filterKey == "contracts" and selector.state == 3)
    frame:setMapSelectionItem(truck.hotspot)
    assert(page.filterKey == "stations" and selector.state == 3)
end)

test("field needs follow what each implement can do", function()
    local FN = MHFieldNeeds
    local W = FN.WORK
    local function state(values)
        local result = {groundType = FieldGroundType.STUBBLE_TILLAGE, fruitTypeIndex = 0, growthState = 0, sprayLevel = 0,
            limeLevel = 1, plowLevel = 1, rollerLevel = 0, weedState = 0, stoneLevel = 0, sprayType = FieldSprayType.NONE}
        for key, value in pairs(values) do result[key] = value end
        result.fruit = g_fruitTypeManager:getFruitTypeByIndex(result.fruitTypeIndex)
        return result
    end
    local function works(specs, fill)
        local vehicle = mockVehicle(90 + #g_currentMission.notifications + math.random(1000))
        local implement = attachImplement(vehicle, specs)
        implement.fillTypes[1] = fill
        local map, list = FN.getWorks(vehicle)
        return table.concat(list, ","), map, vehicle, implement
    end
    assert(works({spec_plow = {}}) == "PLOW")
    assert(works({spec_cultivator = {}}) == "CULTIVATE")
    assert(works({spec_sowingMachine = {}, spec_sprayer = {}}) == "SOW", "a fertilizing seeder sows")
    assert(works({spec_sprayer = {}}, "LIME") == "LIME" and works({spec_sprayer = {}}, "HERBICIDE") == "HERBICIDE")
    assert(works({spec_sprayer = {}}, "LIQUIDFERTILIZER") == "FERTILIZE" and works({spec_sprayer = {}}) == "FERTILIZE")
    assert(works({spec_sprayer = {hasWorkAreas = false}}, "HERBICIDE") == "", "a tank without work areas sprays nothing")
    assert(works({spec_roller = {isSoilRoller = false, isGrassRoller = true}}) == "", "a grass roller has no soil need")
    assert(works({spec_roller = {isSoilRoller = true}}) == "ROLL")

    local stubble, plowed = state({}), state({groundType = FieldGroundType.PLOWED})
    local cultivated = state({groundType = FieldGroundType.CULTIVATED})
    local growing = state({groundType = FieldGroundType.SOWN, fruitTypeIndex = FRUIT.WHEAT, growthState = 2})
    local ripe = state({groundType = FieldGroundType.SOWN, fruitTypeIndex = FRUIT.WHEAT, growthState = 4})
    local harvested = state({groundType = FieldGroundType.HARVEST_READY, fruitTypeIndex = FRUIT.WHEAT, growthState = 6})
    -- Soil work only where no crop would be destroyed.
    assert(FN.getNeedsWork(stubble, W.PLOW) and not FN.getNeedsWork(plowed, W.PLOW) and not FN.getNeedsWork(growing, W.PLOW))
    assert(FN.getNeedsWork(state({groundType = FieldGroundType.CULTIVATED, plowLevel = 0}), W.PLOW), "plowing required")
    assert(FN.getNeedsWork(stubble, W.CULTIVATE) and FN.getNeedsWork(plowed, W.CULTIVATE))
    assert(not FN.getNeedsWork(state({groundType = FieldGroundType.SEEDBED}), W.CULTIVATE))
    -- Sowing: prepared ground; a direct seeder or a seeder with a cultivator also on harvested ground.
    local _, plain = works({spec_sowingMachine = {}})
    local _, direct = works({spec_sowingMachine = {useDirectPlanting = true}})
    local seederVehicle = mockVehicle(80)
    attachImplement(seederVehicle, {spec_sowingMachine = {}})
    attachImplement(seederVehicle, {spec_cultivator = {}})
    local combined = FN.getWorks(seederVehicle)
    assert(FN.getNeedsWork(cultivated, W.SOW, plain.SOW) and not FN.getNeedsWork(growing, W.SOW, direct.SOW))
    assert(not FN.getNeedsWork(harvested, W.SOW, plain.SOW), "a normal seeder needs worked soil")
    assert(FN.getNeedsWork(harvested, W.SOW, direct.SOW) and FN.getNeedsWork(harvested, W.SOW, combined.SOW))
    -- Field info box conditions; soil rolling only before the second growth state.
    assert(FN.getNeedsWork(state({rollerLevel = 1}), W.ROLL) and not FN.getNeedsWork(stubble, W.ROLL))
    assert(not FN.getNeedsWork(state({rollerLevel = 1, fruitTypeIndex = FRUIT.WHEAT, growthState = 2}), W.ROLL))
    local _, limeWorks = works({spec_sprayer = {}}, "LIME")
    assert(FN.getNeedsWork(state({limeLevel = 0}), W.LIME, limeWorks.LIME) and not FN.getNeedsWork(stubble, W.LIME))
    assert(not FN.getNeedsWork(state({limeLevel = 0, sprayType = FieldSprayType.LIME}), W.LIME, limeWorks.LIME),
        "lime just spread")
    local _, liquid = works({spec_sprayer = {}}, "LIQUIDFERTILIZER")
    assert(FN.getNeedsWork(state({sprayLevel = 1}), W.FERTILIZE, liquid.FERTILIZE))
    assert(not FN.getNeedsWork(state({sprayLevel = 2}), W.FERTILIZE, liquid.FERTILIZE))
    -- Fertilized once (the maintainer's case): the field carries the FERTILIZER marker until the
    -- game clears it, so it needs no fertilizer again, solid or liquid.
    assert(not FN.getNeedsWork(state({sprayLevel = 1, sprayType = FieldSprayType.FERTILIZER}), W.FERTILIZE, liquid.FERTILIZE),
        "the same fertilizer was just spread")
    local _, solid = works({spec_sprayer = {}}, "FERTILIZER")
    assert(not FN.getNeedsWork(state({sprayLevel = 1, sprayType = FieldSprayType.FERTILIZER}), W.FERTILIZE, solid.FERTILIZE))
    assert(FN.getNeedsWork(state({sprayLevel = 1, sprayType = FieldSprayType.MANURE}), W.FERTILIZE, liquid.FERTILIZE),
        "manure leaves another marker")
    assert(not FN.getNeedsWork(ripe, W.FERTILIZE), "no fertilizer on a ripe crop")
    -- Weeds: herbicide on growing crops; weeder and hoe by their own replacement tables and crop states.
    local function weedy(weedState, growthState)
        return state({groundType = FieldGroundType.SOWN, fruitTypeIndex = FRUIT.WHEAT, growthState = growthState or 1,
            weedState = weedState})
    end
    local _, weeder = works({spec_weeder = {isHoeWeeder = false}})
    local _, hoe = works({spec_weeder = {isHoeWeeder = true}})
    assert(FN.getNeedsWork(weedy(2, 2), W.HERBICIDE) and not FN.getNeedsWork(growing, W.HERBICIDE))
    assert(FN.getNeedsWork(weedy(1), W.WEED, weeder.WEED) and not FN.getNeedsWork(weedy(2), W.WEED, weeder.WEED),
        "the weeder only takes small weeds")
    assert(FN.getNeedsWork(weedy(2), W.WEED, hoe.WEED) and not FN.getNeedsWork(weedy(3), W.WEED, hoe.WEED))
    assert(not FN.getNeedsWork(weedy(1, 3), W.WEED, weeder.WEED), "too late in the crop for the weeder")
    -- Crops: mulching stubble, the topper's own crops, mower and header ranges.
    assert(FN.getNeedsWork(state({fruitTypeIndex = FRUIT.WHEAT, growthState = 6}), W.MULCH) and not FN.getNeedsWork(growing, W.MULCH))
    assert(not FN.getNeedsWork(state({fruitTypeIndex = FRUIT.GRASS, growthState = 4}), W.MULCH), "grass has no mulched state")
    local _, topper = works({spec_fruitPreparer = {fruitTypes = {FRUIT.POTATO}}})
    local _, otherTopper = works({spec_fruitPreparer = {fruitTypes = {FRUIT.WHEAT}}})
    local foliage = state({fruitTypeIndex = FRUIT.POTATO, growthState = 4})
    assert(FN.getNeedsWork(foliage, W.PREPARE, topper.PREPARE) and not FN.getNeedsWork(foliage, W.PREPARE, otherTopper.PREPARE))
    local _, grain = works({spec_cutter = {fruitTypeIndices = {FRUIT.WHEAT, FRUIT.MAIZE}}})
    local _, forage = works({spec_cutter = {fruitTypeIndices = {FRUIT.MAIZE}, allowsForageGrowthState = true}})
    local maizeForage = state({fruitTypeIndex = FRUIT.MAIZE, growthState = 3})
    local maizeRipe = state({fruitTypeIndex = FRUIT.MAIZE, growthState = 4})
    assert(FN.getNeedsWork(ripe, W.HARVEST, grain.HARVEST) and not FN.getNeedsWork(growing, W.HARVEST, grain.HARVEST))
    assert(not FN.getNeedsWork(maizeForage, W.HARVEST, grain.HARVEST), "a grain header waits for ripe maize")
    assert(FN.getNeedsWork(maizeForage, W.HARVEST, forage.HARVEST) and FN.getNeedsWork(maizeRipe, W.HARVEST, forage.HARVEST))
    local grass = state({groundType = FieldGroundType.GRASS, fruitTypeIndex = FRUIT.GRASS, growthState = 3})
    assert(not FN.getNeedsWork(grass, W.HARVEST, grain.HARVEST), "the header does not cut grass")
    -- The game's MOWER converter: grass -> grass windrow, grain -> straw (maps_fruitTypes.xml:59-67).
    local _, mower = works({spec_mower = {fruitTypeConverters = {
        [FRUIT.GRASS] = {fillTypeIndex = FillType.GRASS_WINDROW, conversionFactor = 1},
        [FRUIT.WHEAT] = {fillTypeIndex = FillType.STRAW, conversionFactor = 1}}}})
    assert(FN.getNeedsWork(grass, W.MOW, mower.MOW))
    assert(not FN.getNeedsWork(ripe, W.MOW, mower.MOW), "ripe wheat is harvested, not mowed for straw")
    assert(FN.getNeedsWork(state({stoneLevel = 2}), W.STONES) and not FN.getNeedsWork(stubble, W.STONES))
    -- "My fields" keeps the map's order: forage maize is growing, not ready to harvest.
    assert(FN.getStateText(maizeForage) == "ui_growthMapGrowing" and FN.getStateText(maizeRipe) == "ui_growthMapReadyToHarvest")
    -- Switched-off game settings switch the needs off.
    g_currentMission.missionInfo.limeRequired, g_currentMission.missionInfo.weedsEnabled = false, false
    assert(not FN.getNeedsWork(state({limeLevel = 0}), W.LIME) and not FN.getNeedsWork(weedy(2, 2), W.HERBICIDE))
    assert(#FN.getNeeds(nil, {}, {"PLOW"}) == 0, "a point outside every field has no need")
end)

test("a sprayer sprays what its tank, a front tank or the fill type choice supplies", function()
    local FN = MHFieldNeeds
    local function sprayer()
        local vehicle = mockVehicle(60)
        local implement = attachImplement(vehicle, {spec_sprayer = {supportedSprayTypes = {"FERTILIZER", "HERBICIDE"},
            fillTypeSources = {FERTILIZER = {}, HERBICIDE = {}}}})
        return vehicle, implement
    end
    local vehicle, implement = sprayer()
    local frontTank = attachImplement(vehicle, {})
    frontTank.fillTypes[2] = "HERBICIDE"
    implement.spec_sprayer.fillTypeSources.HERBICIDE = {{vehicle = frontTank, fillUnitIndex = 2}}
    local _, list = FN.getWorks(vehicle)
    assert(table.concat(list, ",") == "HERBICIDE", "the empty tank is supplied with herbicide from the front tank")
    implement.fillTypes[1] = "FERTILIZER"
    _, list = FN.getWorks(vehicle)
    assert(table.concat(list, ",") == "FERTILIZE", "the own tank comes first")
    -- Empty everywhere: the Fill Type Selector Mod's choice, when that Mod is there.
    vehicle, implement = sprayer()
    _, list = FN.getWorks(vehicle)
    assert(table.concat(list, ",") == "FERTILIZE")
    implement[FN.FILL_TYPE_SELECTOR_SPEC] = {selectedFillType = "LIME"}
    _, list = FN.getWorks(vehicle)
    assert(table.concat(list, ",") == "LIME")
end)

test("the lists: fields needing the work, my fields with their state, contracts and stations", function()
    local tractor = seat(mockVehicle(7))
    tractor.canFieldWork, tractor.canDeliver = true, true
    attachImplement(tractor, {spec_plow = {}})
    local field1 = mockField(1, 100, 100, 1.25, 1, {groundType = FieldGroundType.PLOWED})
    mockField(3, 300, 300, 3, 1, {groundType = FieldGroundType.SOWN, fruitTypeIndex = FRUIT.WHEAT, growthState = 4})
    mockField(2, 200, 200, 2, 1, {limeLevel = 0})
    mockField(4, 400, 400, 1, 2)
    mockContract(mockField(5, 500, 500, 1, 0, {groundType = FieldGroundType.SOWN, fruitTypeIndex = FRUIT.WHEAT, growthState = 2}),
        1, "Sowing", 0.1, nil, "sowMission")
    -- A ploughing contract on a field the farm doesn't own (the maintainer's case).
    mockContract(mockField(6, 600, 600, 1, 0, {groundType = FieldGroundType.CULTIVATED}), 1, "Plowing", 0.42, nil, "plowMission")
    mockContract(mockField(7, 700, 700, 1, 0), 2, "Other farm", 0.5)
    mockContract(mockField(8, 800, 800, 1, 0), 1, "Not accepted", 0, "created")
    g_currentMission.stations.loading = {mockStation(600, "Silo", 50, 60)}
    g_currentMission.stations.unloading = {mockStation(601, "Mill", 70, 80)}
    local frame, page = openPage()
    local selector = page.mhFilterSelector
    -- The contract comes first, by its type even though the field state alone wouldn't need it.
    assert(placeTexts(page) == "Plowing - Field No. 6|contract_field_plow_title - 42 %;Field No. 2|contract_field_plow_title",
        placeTexts(page))
    assert(page.mhPlacesList.cells[1][1]:getAttribute("icon").imageSlice == "gui.ingameMap_contracts")
    assert(page.mhPlacesList.cells[1][2]:getAttribute("icon").imageSlice == "gui.storeAttribute_seeding")
    assert(not page.mhPlacesEmpty.visible)
    selector:setState(2, true)
    assert(placeTexts(page) == "Field No. 1|ui_growthMapPlowed;Field No. 2|ui_growthMapNeedsLime;Field No. 3|ui_growthMapReadyToHarvest",
        placeTexts(page))
    selector:setState(3, true)
    assert(placeTexts(page) == "Plowing - Field No. 6|contract_field_plow_title - 42 %;Sowing - Field No. 5|10 %", placeTexts(page))
    assert(page.mhPlacesList.cells[1][1]:getAttribute("icon").imageSlice == "gui.ingameMap_contracts")
    selector:setState(4, true)
    assert(placeTexts(page) == "Silo|;Mill|")
    assert(page.mhPlacesList.cells[1][1]:getAttribute("icon").imageSlice == "gui.ingameMap_loadingStation")
    -- The field states are read again every few seconds while the page is open.
    selector:setState(1, true)
    field1.state.groundType = FieldGroundType.STUBBLE_TILLAGE
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    local contractRow = "Plowing - Field No. 6|contract_field_plow_title - 42 %;"
    assert(placeTexts(page) == contractRow .. "Field No. 2|contract_field_plow_title")
    InGameMenuMapFrame.update(frame, MHPage.PLACES_INTERVAL)
    assert(placeTexts(page) == contractRow .. "Field No. 1|contract_field_plow_title;Field No. 2|contract_field_plow_title",
        placeTexts(page))
end)

test("implements attached while the page is open update the filter and keep the choice", function()
    local tractor = seat(mockVehicle(7))
    mockField(1, 100, 100, 1, 1)
    local frame, page = openPage()
    local selector = page.mhFilterSelector
    assert(page.filterKey == "fields" and table.concat(selector.texts, ";") == "mh_filterFields;ui_contracts")
    selector:setState(2, true)
    attachImplement(tractor, {spec_plow = {}})
    InGameMenuMapFrame.update(frame, MHPage.PLACES_INTERVAL)
    assert(table.concat(selector.texts, ";") == "mh_filterNeeds;mh_filterFields;ui_contracts")
    assert(page.filterKey == "contracts" and selector.state == 3, "the shown choice stays")
    selector:setState(1, true)
    assert(placeTexts(page) == "Field No. 1|contract_field_plow_title")
    -- Detached again: the needs choice is gone, the page falls back to the first option.
    table.remove(tractor.childVehicles)
    InGameMenuMapFrame.update(frame, MHPage.PLACES_INTERVAL)
    assert(table.concat(selector.texts, ";") == "mh_filterFields;ui_contracts" and page.filterKey == "fields")
end)

test("each filter explains an empty list", function()
    local tractor = seat(mockVehicle(7))
    attachImplement(tractor, {spec_plow = {}})
    local _, page = openPage()
    local selector = page.mhFilterSelector
    assert(page.mhPlacesEmpty.visible and page.mhPlacesEmpty.text == "mh_emptyNeeds")
    selector:setState(2, true)
    assert(page.mhPlacesEmpty.visible and page.mhPlacesEmpty.text == "mh_emptyFields")
    selector:setState(3, true)
    assert(page.mhPlacesEmpty.visible and page.mhPlacesEmpty.text == "mh_emptyContracts")
    mockField(1, 100, 100, 1, 1, {groundType = FieldGroundType.PLOWED})
    selector:setState(1, true)
    assert(page.mhPlacesEmpty.text == "mh_emptyNeeds", "a field that needs nothing is not listed")
    selector:setState(2, true)
    assert(not page.mhPlacesEmpty.visible and page.mhPlacesList:getItemCount() == 1)
    tractor.canDeliver = true
    page:setVehicle(tractor, false)
    selector:setState(4, true)
    assert(page.mhPlacesEmpty.visible and page.mhPlacesEmpty.text == "mh_emptyStations")
end)

test("a place moves the map there and prefills the native form", function()
    local vehicle = seat(mockVehicle(7))
    vehicle.canFieldWork, vehicle.canDeliver = true, true
    mockField(3, 300, 310, 2.5, 1)
    local silo = mockStation(600, "Silo", 50, 60)
    local mill = mockStation(601, "Mill", 70, 80)
    g_currentMission.stations.loading = {mockStation(599, "Depot", 0, 0), silo}
    g_currentMission.stations.unloading = {mill}
    local frame, page = openPage()
    assert(page.filterKey == "fields")
    -- Field: field work at the field.
    page.mhPlacesList:click(1, 1)
    assert(frame.ingameMap.centered[1] == 300 and frame.ingameMap.centered[2] == 310)
    local job = frame.currentJob
    assert(job.jobTypeIndex == AIJobType.FIELDWORK and job.positionAngleParameter.x == 300 and job.positionAngleParameter.z == 310)
    assert(frame.jobTypeElement.state == 2 and frame.lastValid)
    -- Loading station: load and deliver with that station.
    page.mhFilterSelector:setState(3, true)
    assert(placeTexts(page) == "Depot|;Silo|;Mill|")
    page.mhPlacesList:click(1, 2)
    job = frame.currentJob
    assert(job.jobTypeIndex == AIJobType.LOAD_AND_DELIVER and job.loadingStationParameter:getLoadingStation() == silo)
    assert(job.changedParameter == job.loadingStationParameter and frame.ingameMap.centered[1] == 50)
    -- Unloading station keeps the current delivery type and sets its unloading station.
    page.mhPlacesList:click(1, 3)
    assert(frame.currentJob == job and job.unloadingStationParameter:getUnloadingStation() == mill)
    -- Without field work, a field prefills Go to.
    vehicle.canFieldWork = false
    page:setVehicle(vehicle, false)
    page.mhFilterSelector:setState(1, true)
    page.mhPlacesList:click(1, 1)
    assert(frame.currentJob.jobTypeIndex == AIJobType.GOTO and frame.currentJob.positionAngleParameter.x == 300)
end)

test("Add to queue starts the first job at once; Insert as next puts a job in front", function()
    local vehicle = seat(mockVehicle(7))
    local frame, page = openPage()
    frame.currentJob.positionAngleParameter:setPosition(5, 6)
    local first = frame.currentJob
    -- Z (MENU_MAP_ACTION_1) adds: the native handler does nothing on the page.
    g_inputBinding:trigger(InputAction.MENU_MAP_ACTION_1)
    assert(g_currentMission.aiSystem.started[1] == first and vehicle:getIsAIActive() and frame.nativeStartPressed == nil)
    assert(frame.currentJob ~= first and frame.currentJob.jobTypeIndex == AIJobType.GOTO and (first.resetCount or 0) == 0)
    assert(#rowTexts(page) == 1 and rowTexts(page)[1]:sub(1, 13) == "|Go to - task", rowTexts(page)[1])
    frame.currentJob.positionAngleParameter:setPosition(9, 9)
    page:onClickAdd()
    frame.currentJob.positionAngleParameter:setPosition(7, 8)
    -- X (MENU_EXTRA_1) inserts as next.
    g_inputBinding:trigger(InputAction.MENU_EXTRA_1)
    local rows = rowTexts(page)
    assert(#rows == 3 and rows[2] == "1|Go to|7, 8" and rows[3] == "2|Go to|9, 9", table.concat(rows, ";"))
    assert(page.mhVehicleInfo.text == "Waiting: 2" and not page.mhResumeContainer.visible, "running: nothing to resume")
    -- An invalid form stays with the native warning.
    frame.currentJob.valid = false
    page.mhAddButton.onClickCallback(page)
    assert(infoDialogs[1] == "invalid target" and frame.warningsUpdated and #MH.getEntries(vehicle) == 2)
    frame.currentJob.valid = true
    for i = 3, MH.MAX_ENTRIES do MH.requestAdd(vehicle, newJob(vehicle, i, i)) end
    page:onClickAdd()
    assert(infoDialogs[2] == "Full at 10")
end)

test("entries can be moved, edited and removed from the queue list", function()
    local vehicle = seat(mockVehicle(7))
    vehicle.canFieldWork = true
    local manual = startManual(vehicle)
    for i = 1, 3 do MH.requestAdd(vehicle, newJob(vehicle, i, i)) end
    local frame, page = openPage()
    -- Row 1 is the running job: no arrows or edit, Delete reads Cancel job.
    assert(#rowTexts(page) == 4 and page.selectedCurrent and page.mhUpButton.disabled and page.mhEditButton.disabled)
    assert(page.mhRemoveText.text == "button_cancelJob" and not page.mhRemoveButton.disabled)
    page.mhQueueList:click(1, 4)
    assert(page.mhDownButton.disabled and not page.mhUpButton.disabled and page.mhRemoveText.text == "button_delete")
    page.mhUpButton.onClickCallback(page)
    local rows = rowTexts(page)
    assert(rows[2] == "1|Go to|1, 1" and rows[3] == "2|Go to|3, 3" and rows[4] == "3|Go to|2, 2", table.concat(rows, ";"))
    assert(page.selectedRow == 3, "the selection follows the moved entry")
    page.mhDownButton.onClickCallback(page)
    assert(rowTexts(page)[4] == "3|Go to|3, 3")
    -- Edit loads the entry into the native form; Save replaces it in place.
    page.mhQueueList:click(1, 3)
    local id = MH.getEntries(vehicle)[2].id
    page.mhEditButton.onClickCallback(page)
    assert(page.editingId == id and frame.currentJob.positionAngleParameter.x == 2 and page.mhAddText.text == "button_save")
    assert(page.mhNextText.text == "button_cancel")
    frame.jobTypeElement:setState(2)
    frame:onJobTypeChanged(2)
    frame.currentJob.positionAngleParameter:setPosition(42, 43)
    page:onClickAdd()
    local entries = MH.getEntries(vehicle)
    assert(#entries == 3 and entries[2].id == id and entries[2].job.jobTypeIndex == AIJobType.FIELDWORK)
    assert(entries[2].job.positionAngleParameter.x == 42 and page.editingId == nil and page.mhAddText.text == "mh_addToQueue")
    -- X cancels an edit without sending anything.
    page.mhQueueList:click(1, 2)
    page:onClickEdit()
    g_inputBinding:trigger(InputAction.MENU_EXTRA_1)
    assert(page.editingId == nil and #MH.getEntries(vehicle) == 3 and MH.getEntries(vehicle)[1].job.positionAngleParameter.x == 1)
    -- An entry that starts while it is edited ends the edit.
    page:onClickEdit()
    g_currentMission.aiSystem:stopJob(manual, AIMessageSuccessFinishedJob.new())
    update(MH.ADVANCE_DELAY)
    assert(page.editingId == nil and #MH.getEntries(vehicle) == 2)
    page.mhQueueList:click(1, 3)
    page.mhRemoveButton.onClickCallback(page)
    assert(#MH.getEntries(vehicle) == 1)
    page.mhClearButton.onClickCallback(page)
    assert(#MH.getEntries(vehicle) == 0)
end)

test("Cancel job on the running row pauses the queue; Resume continues it", function()
    local vehicle = seat(mockVehicle(7))
    local a, b = newJob(vehicle, 1, 1), newJob(vehicle, 2, 2)
    MH.requestAdd(vehicle, a)
    MH.requestAdd(vehicle, b)
    local _, page = openPage()
    assert(page.selectedCurrent and page.mhRemoveText.text == "button_cancelJob" and not page.mhResumeContainer.visible)
    page.mhRemoveButton.onClickCallback(page)
    local queue = MH.queues[vehicle]
    assert(not vehicle:getIsAIActive() and queue.pause == MH.PAUSE.STOPPED and #queue.entries == 1)
    assert(page.mhVehicleStatus.text == "Paused: mh_reasonStopped")
    assert(page.mhResumeContainer.visible and not page.mhResumeButton.disabled and page.mhRemoveText.text == "button_delete")
    page.mhResumeButton.onClickCallback(page)
    local started = g_currentMission.aiSystem.started
    assert(started[#started] == b and queue.running and not page.mhResumeContainer.visible)
end)

test("the running job shows its progress and disappears when it is done", function()
    local vehicle = seat(mockVehicle(7))
    vehicle.canFieldWork = true
    local field = mockField(3, 400, 200, 2, 1)
    mockContract(field, 1, "Sowing", 0.25)
    MH.requestAdd(vehicle, newJob(vehicle, 400, 200, AIJobType.FIELDWORK))
    MH.requestAdd(vehicle, newJob(vehicle, 1, 2))
    local frame, page = openPage()
    local rows = rowTexts(page)
    assert(#rows == 2 and rows[1] == "|Field work - task 1|ui_distance: 300 m  ·  contract_progress: 25 %", rows[1])
    assert(rows[2] == "1|Go to|1, 2" and page.mhRemoveText.text == "button_cancelJob")
    assert(page.mhVehicleStatus.text == "mh_statusWorking")
    local cell = page.mhQueueList:getElementAtSectionIndex(1, 1)
    assert(cell:getAttribute("badgeIcon").visible and not page.mhQueueList:getElementAtSectionIndex(1, 2):getAttribute("badgeIcon").visible)
    -- Progress refreshes in place every second.
    vehicle.x = 350
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(page.mhQueueList:getElementAtSectionIndex(1, 1) == cell and cell:getAttribute("text"):getText():find("50 m", 1, true))
    -- Done: the row goes, the next entry starts and becomes the running row.
    g_currentMission.aiSystem:stopJob(vehicle:getJob(), AIMessageSuccessFinishedJob.new())
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(#rowTexts(page) == 1 and rowTexts(page)[1] == "1|Go to|1, 2")
    update(MH.ADVANCE_DELAY)
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(#rowTexts(page) == 1 and rowTexts(page)[1]:sub(1, 7) == "|Go to ", rowTexts(page)[1])
    g_currentMission.aiSystem:stopJob(vehicle:getJob(), AIMessageSuccessFinishedJob.new())
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(#rowTexts(page) == 0 and page.mhQueueEmpty.visible)
end)

test("jobs can be planned while the vehicle works and run after the current job", function()
    local vehicle = seat(mockVehicle(7))
    local current = startManual(vehicle)
    local frame, page = openPage()
    assert(frame.currentJob ~= nil and frame.currentJob.builtWhileAIActive == false, "built while the vehicle reads idle")
    assert(rawget(vehicle, "getIsAIActive") ~= nil and vehicle:getIsAIActive(), "the vehicle's own function is back")
    assert(frame.contextRefreshed >= 1)
    page:onClickAdd()
    local queue = MH.queues[vehicle]
    assert(#queue.entries == 1 and queue.running and queue.runningJob == current)
    g_currentMission.aiSystem:stopJob(current, AIMessageSuccessFinishedJob.new())
    update(MH.ADVANCE_DELAY)
    assert(#g_currentMission.aiSystem.started == 2 and vehicle:getIsAIActive())
end)

test("an error while planning is cleaned up on the next frame", function()
    local vehicle = seat(mockVehicle(7))
    startManual(vehicle)
    local _, page = openPage()
    page.frame.setActiveJobTypeSelection = function() error("broken menu") end
    -- The error reaches the game log like any other; nothing in the Mod catches it.
    assert(not pcall(page.buildForm, page, nil, nil))
    assert(not vehicle:getIsAIActive(), "the shadow is still there until the next frame")
    update(16)
    assert(rawget(vehicle, "getIsAIActive") ~= nil and vehicle:getIsAIActive())
end)

test("clients only send requests and wait for the server", function()
    local vehicle = seat(mockVehicle(7))
    local frame, page = openPage()
    g_currentMission = newMission(false)
    local sent = {}
    local previousClient, previousServer = g_client, g_server
    g_server = nil
    g_client = {getServerConnection = function() return {sendEvent = function(_, event) table.insert(sent, event) end} end}
    page:onClickAdd()
    page:onClickInsertNext()
    assert(#sent == 2 and sent[1].action == MH.ACTION.ADD and not sent[1].flag and sent[2].flag)
    assert(#MH.getEntries(vehicle) == 0 and #g_currentMission.aiSystem.started == 0)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, newJob(vehicle), nil, localConnection), "clients never apply")
    g_client, g_server = previousClient, previousServer
end)

-- Keys ---------------------------------------------------------------------------------------
test("X on the map opens the page and gives way to Precision Farming's help button", function()
    seat(mockVehicle(7))
    local frame = mockFrame()
    g_inGameMenu.pageMapOverview = frame
    InGameMenuMapFrame.onLoadMapFinished(frame)
    frame:onFrameOpen()
    local ext = frame.mapHelper
    assert(ext.toggle.visible and frame.mapOverviewSelector:getState() == 1)
    local help = mockElement("pfHelpButton")
    help.inputActionName = "MENU_EXTRA_1"
    frame.filterListContainer:addElement(help)
    g_inputBinding:trigger(InputAction.MENU_EXTRA_1)
    assert(frame.mapOverviewSelector:getState() == 1, "the soil map help button gets the key")
    help:setVisible(false)
    g_inputBinding:trigger(InputAction.MENU_EXTRA_1)
    assert(frame.mapOverviewSelector:getState() == ext.pageIndex and ext.page:getIsShown())
    frame.mapOverviewSelector:setState(1, true)
    ext.toggle:getDescendantByName("button").onClickCallback(ext)
    assert(ext.page:getIsShown())
end)

test("the global hotkey opens the map on the Map Helper page, on foot and in vehicles", function()
    local frame = mockFrame()
    g_inGameMenu.pageMapOverview = frame
    InGameMenuMapFrame.onLoadMapFinished(frame)
    local component = {player = {isOwner = true}}
    PlayerInputComponent.registerGlobalPlayerActionEvents(component)
    PlayerInputComponent.registerGlobalPlayerActionEvents(component)
    g_inputBinding:beginActionEventsModification("VEHICLE")
    PlayerInputComponent.registerGlobalPlayerActionEvents(component, "VEHICLE")
    g_inputBinding:endActionEventsModification()
    local contexts = {}
    for _, event in ipairs(g_inputBinding.events) do
        if event.action == InputAction.MH_OPEN_MAP_HELPER then
            table.insert(contexts, event.context)
            assert(event.textVisible and event.priority == GS_PRIO_VERY_LOW)
        end
    end
    assert(table.concat(contexts, ",") == "PLAYER,VEHICLE", table.concat(contexts, ","))
    g_inputBinding:trigger(InputAction.MH_OPEN_MAP_HELPER, "PLAYER")
    assert(g_inGameMenu.opened == 1 and frame.mapOverviewSelector:getState() == frame.mapHelper.pageIndex)
    assert(frame.mapHelper.page:getIsShown())
    -- Locked input (for example during a cutscene) or a guided tour: nothing opens.
    component.locked = true
    g_inputBinding:trigger(InputAction.MH_OPEN_MAP_HELPER, "PLAYER")
    assert(g_inGameMenu.opened == 1)
end)

-- Lifecycle -----------------------------------------------------------------------------------
test("map page hooks are idempotent across repeated registration and loads", function()
    local frame = mockFrame()
    InGameMenuMapFrame.onLoadMapFinished(frame)
    InGameMenuMapFrame.onLoadMapFinished(frame)
    local header = frame.shopMoneyBox.parent
    assert(#header.elements == 2, "balance plus one Map Helper button")
    assert(#frame.filterBox.elements == 7, "the native sidebar elements plus one page")
    assert(frame.mapHelper.toggle:getDescendantByName("text").text == "mh_toggle")
    local toggle, balance = frame.mapHelper.toggle, frame.shopMoneyBoxBg
    assert(math.abs(toggle.absPosition[1] + toggle.absSize[1] - (balance.absPosition[1] + balance.absSize[1])) < 1e-9)
    assert(toggle.absPosition[2] + toggle.absSize[2] < math.min(balance.absPosition[2], frame.statusMessage.absPosition[2]))
    frame:onFrameOpen()
    frame:setupMapOverview()
    assert(#frame.mapSelectorTexts == 8 and #frame.subCategoryDotBox.elements == 8, "one page and one dot per mission")
    local profileLoads = g_gui.profileLoads
    local second = mockFrame()
    InGameMenuMapFrame.onLoadMapFinished(second)
    assert(#second.filterBox.elements == 7 and g_gui.profileLoads == profileLoads, "profiles load once per game session")
    InGameMenuMapFrame.registerInput(frame)
    InGameMenuMapFrame.registerInput(frame)
    local count = 0
    for _, event in ipairs(g_inputBinding.events) do
        if event.target == frame.mapHelper then count = count + 1 end
    end
    assert(count == 1)
    local starts = 0
    local original = MH.onMissionStarted
    MH.onMissionStarted = function() starts = starts + 1 end
    FSBaseMission.onStartMission(g_currentMission)
    MH.onMissionStarted = original
    assert(starts == 1, "one dispatch per call after re-registration")
end)

test("leaving the save restores the native map page; the next save with the Mod gets a fresh page", function()
    seat(mockVehicle(7))
    local frame, page, ext = openPage()
    local header = frame.shopMoneyBox.parent
    local oldToggle = ext.toggle:getDescendantByName("button")
    MH.requestAdd(g_localPlayer.vehicle, newJob(g_localPlayer.vehicle))
    FSBaseMission.delete(g_currentMission)
    assert(frame.mapHelper == nil and #header.elements == 1 and #frame.filterBox.elements == 6 and page.root == nil)
    assert(frame.createJobContainer.profile == "fs25_subCategoryListContainer" and not frame.createJobContainer.visible)
    assert(frame.buttonStartJobContainer.visible and frame.createJobContainer.parent == frame.filterBox)
    assert(#frame.mapSelectorTexts == 7 and #frame.subCategoryDotBox.elements == 7 and frame.mapOverviewSelector:getState() == 1)
    assert(frame.dataTables[8] == nil and frame.numSelectedFilters[8] == nil)
    assert(#g_inputBinding.events == 1, "only the native Start job key of the map page is left")
    assert(#g_messageCenter.subscribers == 0 and not MH.missionActive and #MH.listeners == 0)
    -- The selector calls the native function again, as loaded.
    frame.mapOverviewSelector:setState(InGameMenuMapFrame.AI_WORKER_LIST, true)
    assert(frame.workerListContainer.visible)
    -- Next save without the Mod: hooks stay quiet and left-over callbacks do nothing.
    g_modIsLoaded[g_currentModName] = false
    g_currentMission = newMission(true)
    FSBaseMission.onStartMission(g_currentMission)
    frame:reset()
    InGameMenuMapFrame.onLoadMapFinished(frame)
    frame:onFrameOpen()
    oldToggle.onClickCallback(ext)
    MF.onKeyAction(ext)
    assert(frame.mapHelper == nil and #header.elements == 1 and #frame.mapSelectorTexts == 7)
    assert(#g_messageCenter.subscribers == 0 and next(g_currentMission.updateables) == nil)
    FSBaseMission.delete(g_currentMission)
    -- A save with the Mod again: one fresh set of controls and a working page.
    g_modIsLoaded[g_currentModName] = true
    g_currentMission = newMission(true)
    FSBaseMission.onStartMission(g_currentMission)
    frame:reset()
    InGameMenuMapFrame.onLoadMapFinished(frame)
    frame:onFrameOpen()
    assert(frame.mapHelper ~= nil and frame.mapHelper ~= ext and #header.elements == 2 and #frame.filterBox.elements == 7)
    assert(#frame.mapSelectorTexts == 8 and #frame.subCategoryDotBox.elements == 8)
    oldToggle.onClickCallback(ext)
    assert(frame.mapOverviewSelector:getState() == 1, "controls of the previous save stay inert")
    frame.mapHelper.toggle:getDescendantByName("button").onClickCallback(frame.mapHelper)
    assert(frame.mapHelper.page:getIsShown())
    -- Controls left by an earlier copy of the scripts are replaced, not duplicated.
    MF.remove(frame)
    local stale = {toggle = mockElement("staleToggle")}
    header:addElement(stale.toggle)
    frame.mapHelper = stale
    InGameMenuMapFrame.onLoadMapFinished(frame)
    assert(stale.toggle == nil and #header.elements == 2 and frame.mapHelper ~= stale)
end)

test("closing the menu gives the native form back and reopening shows the page again", function()
    local vehicle = seat(mockVehicle(7))
    local frame, page = openPage()
    frame:onFrameClose()
    assert(not page:getIsShown() and frame.createJobContainer.profile == "fs25_subCategoryListContainer")
    frame:onFrameOpen()
    assert(page:getIsShown() and page.vehicle == vehicle and frame.createJobContainer.profile == "mh_nativeForm")
    -- A position pick that is still running is cancelled with the page.
    frame:startPickPositionAndRotation(frame.currentJob.positionAngleParameter, function() end)
    frame.mapOverviewSelector:setState(1, true)
    assert(not frame:getIsPicking())
end)

test("a delivery form without stations keeps working when the selection changes", function()
    local vehicle = seat(mockVehicle(7))
    vehicle.canDeliver = true
    local frame, page = openPage()
    assert(page:selectJobType(AIJobType.LOAD_AND_DELIVER) and frame.currentJob.loadingStationParameter:getLoadingStation() == nil)
    frame:setMapSelectionItem(nil)
    assert(not g_currentMission.mapHotspots[frame.aiLoadingMarkerHotspot] and not g_currentMission.mapHotspots[frame.aiUnloadingMarkerHotspot])
    frame.mapOverviewSelector:setState(1, true)
    assert(not page:getIsShown())
    -- With stations, their markers come back after a selection change.
    g_currentMission.stations.loading = {mockStation(600, "Silo", 50, 60)}
    frame.mapOverviewSelector:setState(frame.mapHelper.pageIndex, true)
    page:selectJobType(AIJobType.LOAD_AND_DELIVER)
    frame:setMapSelectionItem(nil)
    assert(frame.aiLoadingMarkerHotspot.x == 50 and g_currentMission.mapHotspots[frame.aiLoadingMarkerHotspot])
    assert(not g_currentMission.mapHotspots[frame.aiUnloadingMarkerHotspot])
end)

test("buttons follow pause and permission changes on the periodic refresh", function()
    local vehicle = seat(mockVehicle(7))
    pausedQueue(vehicle, {newJob(vehicle)})
    local frame, page = openPage()
    assert(not page.mhAddButton.disabled and page.mhResumeContainer.visible and not page.mhResumeButton.disabled)
    g_currentMission.paused = true
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(page.mhAddButton.disabled and page.mhResumeButton.disabled)
    g_currentMission.paused = false
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(not page.mhAddButton.disabled and not page.mhResumeButton.disabled)
    g_currentMission.allowed = false
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(page.mhAddButton.disabled and page.mhClearButton.disabled and page.mhRemoveButton.disabled)
    assert(not page.mhResumeContainer.visible)
    g_currentMission.allowed = true
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(not page.mhClearButton.disabled and page.mhResumeContainer.visible)
end)

test("vehicles that never take a worker are recognised up front", function()
    local reel = mockVehicle(7)
    assert(MH.getSupportsAI(reel))
    reel.spec_aiJobVehicle.supportsAIJobs = false
    assert(not MH.getSupportsAI(reel), "e.g. the Emergency pack's hose reel")
end)

test("contracts count for the needs list only when the combination does their work", function()
    local tractor = seat(mockVehicle(7))
    tractor.canFieldWork = true
    attachImplement(tractor, {spec_cultivator = {}})
    mockContract(mockField(10, 1000, 1000, 1, 0), 1, "Cultivating", 0.2, nil, "cultivateMission")
    mockContract(mockField(41, 4100, 4100, 1, 0), 1, "Plowing", 0.3, nil, "plowMission")
    mockContract(mockField(36, 3600, 3600, 1, 0), 1, "Baling", 0, nil, "baleMission")
    local _, page = openPage()
    assert(placeTexts(page) == "Cultivating - Field No. 10|contract_field_cultivate_title - 20 %", placeTexts(page))
end)

test("merged fields show as one row", function()
    local tractor = seat(mockVehicle(7))
    tractor.canFieldWork = true
    attachImplement(tractor, {spec_cultivator = {}})
    -- Fields 3, 4 and 5 side by side; the strips between 3-4 and 4-5 were worked into one area
    -- (the maintainer's case). Field 6 next to them keeps its grass strip.
    mockField(3, 300, 900, 2, 1, {groundType = FieldGroundType.PLOWED})
    mockField(4, 400, 900, 1.5, 1, {groundType = FieldGroundType.PLOWED})
    mockField(5, 500, 900, 1, 1, {groundType = FieldGroundType.PLOWED})
    mockField(6, 600, 900, 1, 1, {groundType = FieldGroundType.PLOWED})
    workedStrips = {{330, 880, 470, 920}}
    local frame, page = openPage()
    assert(placeTexts(page) == "Field No. 3 + 4 + 5|contract_field_cultivate_title;Field No. 6|contract_field_cultivate_title",
        placeTexts(page))
    -- My fields: one row with the total area when the state has no text.
    page.mhFilterSelector:setState(2, true)
    assert(placeTexts(page):find("Field No. 3 + 4 + 5|", 1, true) ~= nil, placeTexts(page))
    -- Without the worked strips the fields are separate again (once the cached result expires).
    workedStrips = {}
    g_time = (g_time or 0) + MHFieldNeeds.MERGE_CACHE_TIME
    page.mhFilterSelector:setState(1, true)
    assert(placeTexts(page) == "Field No. 3|contract_field_cultivate_title;Field No. 4|contract_field_cultivate_title;"
        .. "Field No. 5|contract_field_cultivate_title;Field No. 6|contract_field_cultivate_title", placeTexts(page))
end)

test("double-clicking a field queues field work there", function()
    local vehicle = seat(mockVehicle(7))
    vehicle.canFieldWork, vehicle.canDeliver = true, true
    mockField(3, 300, 310, 2.5, 1)
    mockField(4, 400, 410, 1, 1)
    g_currentMission.stations.loading = {mockStation(600, "Silo", 50, 60)}
    local frame, page = openPage()
    page.mhPlacesList:doubleClick(1, 1)
    -- Added and, with nobody driving, started at once (field work at field 3).
    local started = g_currentMission.aiSystem.started
    assert(#started == 1 and started[1].jobTypeIndex == AIJobType.FIELDWORK and started[1].positionAngleParameter.x == 300)
    page.mhPlacesList:doubleClick(1, 2)
    local entries = MH.getEntries(vehicle)
    assert(#entries == 1 and entries[1].job.positionAngleParameter.x == 400, "the second field waits behind the first")
    -- Stations only fill in the form.
    page.mhFilterSelector:setState(3, true)
    page.mhPlacesList:doubleClick(1, 1)
    assert(#MH.getEntries(vehicle) == 1 and frame.currentJob.jobTypeIndex == AIJobType.LOAD_AND_DELIVER)
    -- Without field work a double click only fills in Go to.
    vehicle.canFieldWork = false
    page:setVehicle(vehicle, false)
    page.mhFilterSelector:setState(1, true)
    page.mhPlacesList:doubleClick(1, 1)
    assert(#MH.getEntries(vehicle) == 1 and frame.currentJob.jobTypeIndex == AIJobType.GOTO)
end)

print(string.format("%d behavioral tests passed", passed))
