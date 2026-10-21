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
    logged.warnings, logged.infos = {}, {}
    MH.onMissionDeleted(nil)
    g_currentMission = newMission(true)
    g_localPlayer.farmId, g_localPlayer.vehicle = 1, nil
    localConnection.farmId, localConnection.allowed = 1, true
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
local function placeNames(page)
    local result = {}
    for s, cells in ipairs(page.mhPlacesList.cells) do
        table.insert(result, "#" .. page.mhPlacesList.headers[s]:getAttribute("title"):getText())
        for _, cell in ipairs(cells) do
            table.insert(result, cell:getAttribute("name"):getText())
        end
    end
    return table.concat(result, ";")
end

-- Queue model and server ------------------------------------------------------------------
test("feature checks pass against the doubles and both events are registered", function()
    assert(MH.features.queue and MH.features.page and MH.features.hotkey)
    assert(registeredEvents.MHQueueRequestEvent >= 1 and registeredEvents.MHQueueStateEvent >= 1)
    assert(g_messageCenter.subscribers[1].type == MessageType.AI_JOB_STOPPED)
    assert(g_currentMission.updateables[MH] == MH)
end)

test("server permission follows hireAssistant and the vehicle's farm", function()
    local vehicle = mockVehicle(7)
    local job = newJob(vehicle)
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, job, nil, {farmId = 2, allowed = true}))
    assert(not MH.handleRequest(MH.ACTION.ADD, vehicle, newJob(vehicle), nil, {farmId = 1, allowed = false}))
    assert(#MH.getEntries(vehicle) == 0 and #broadcasts == 0)
    vehicle.farmId = FarmManager.SPECTATOR_FARM_ID
    assert(not MH.getCanManage(vehicle, nil))
end)

test("queue holds at most the limit and server-side validation still applies", function()
    local vehicle = mockVehicle(7)
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

test("insert as next, move, edit and remove work by entry id", function()
    local vehicle = mockVehicle(7)
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

test("start queue starts the head through the native AI system", function()
    local vehicle = mockVehicle(7)
    local first, second = newJob(vehicle, 1, 1), newJob(vehicle, 2, 2)
    MH.requestAdd(vehicle, first)
    MH.requestAdd(vehicle, second)
    MH.requestStart(vehicle)
    local started = g_currentMission.aiSystem.started
    assert(#started == 1 and started[1] == first and first.startedFarmId == 1 and vehicle:getIsAIActive())
    local queue = MH.queues[vehicle]
    assert(queue.running and queue.runningJob == first and #queue.entries == 1)
end)

test("queue advances only after a successful finish", function()
    local vehicle = mockVehicle(7)
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
        MH.queues = {}
        local vehicle = mockVehicle(7)
        local first, second = newJob(vehicle, 1, 1), newJob(vehicle, 2, 2)
        MH.requestAdd(vehicle, first)
        MH.requestAdd(vehicle, second)
        MH.requestStart(vehicle)
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
    local vehicle = mockVehicle(7)
    MH.requestAdd(vehicle, newJob(vehicle))
    local manual = newJob(vehicle)
    g_currentMission.aiSystem:startJob(manual, 1)
    g_currentMission.aiSystem:stopJob(manual, AIMessageSuccessFinishedJob.new())
    update(MH.ADVANCE_DELAY)
    assert(#g_currentMission.aiSystem.started == 1 and #MH.getEntries(vehicle) == 1)
    assert(MH.queues[vehicle].pause == MH.PAUSE.NONE and #g_currentMission.notifications == 0)
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
    send(MHQueueRequestEvent.new(MH.ACTION.START, vehicle))
    assert(#MH.getEntries(vehicle) == 0 and #g_currentMission.aiSystem.started == 1)
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

test("queued field work uses the vehicle's worker settings when it starts", function()
    local vehicle = mockVehicle(7)
    vehicle.aiSettings = "A"
    local job = newJob(vehicle, 5, 5, AIJobType.FIELDWORK)
    local stream = {}
    MHQueueRequestEvent.new(MH.ACTION.ADD, vehicle, job):writeStream(stream, {})
    local client = {farmId = 1, allowed = true, getIsServer = function() return false end}
    MHQueueRequestEvent.emptyNew():readStream(stream, client)
    local queued = MH.getEntries(vehicle)[1].job
    assert(queued.pendingData == nil and queued.pendingVehicle == nil, "the requester's copy is dropped")
    vehicle.aiSettings = "B"
    MH.requestStart(vehicle)
    assert(g_currentMission.aiSystem.started[1] == queued and vehicle.aiSettings == "B")
end)

test("quitting with queued jobs completes the mission teardown and never deletes a job", function()
    -- Regression: AIJob:delete raised in the FSBaseMission:delete hook and players could not
    -- leave the save. The double raises like the game, so any remaining call fails here.
    local vehicle = seat(mockVehicle(7))
    for i = 1, 3 do MH.requestAdd(vehicle, newJob(vehicle, i, i)) end
    local other = mockVehicle(8)
    MH.handleRequest(MH.ACTION.ADD, other, newJob(other), nil, localConnection)
    MH.requestStart(vehicle)
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
    assert(page.mhAddButton.disabled and page.mhMineButton.disabled and page.mhPlacesList:getItemCount() == 0)
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

test("selecting another own vehicle on the map switches the page; My vehicle switches back", function()
    local mine = seat(mockVehicle(7))
    local other = mockVehicle(8)
    local foreign = mockVehicle(9, 2)
    local frame, page = openPage()
    frame:setMapSelectionItem(other.hotspot)
    assert(page.vehicle == other and frame.currentJobVehicle == other and page.mhVehicleTitle.text == "Tractor 8")
    assert(not page.mhMineButton.disabled)
    frame:setMapSelectionItem(foreign.hotspot)
    assert(page.vehicle == other, "other farms' vehicles are only selected, not planned for")
    frame:setMapSelectionItem(nil)
    assert(page.vehicle == other and g_currentMission.mapHotspots[frame.aiTargetMapHotspot], "the form marker stays")
    page.mhMineButton.onClickCallback(page)
    assert(page.vehicle == mine and page.mhMineButton.disabled and frame.ingameMap.pannedTo == mine.hotspot)
end)

test("places list contracts, own fields, job types and stations", function()
    local vehicle = seat(mockVehicle(7))
    vehicle.canFieldWork, vehicle.canDeliver = true, true
    local field3 = mockField(3, 300, 300, 2.5, 1)
    mockField(1, 100, 100, 1.25, 1)
    mockField(2, 200, 200, 4, 2)
    mockContract(field3, 1, "Plowing", 0.42)
    mockContract(mockField(5, 500, 500, 1, 0), 2, "Other farm", 0.1)
    mockContract(mockField(6, 600, 600, 1, 0), 1, "Not accepted", 0, "created")
    g_currentMission.stations.loading = {mockStation(600, "Silo", 50, 60)}
    g_currentMission.stations.unloading = {mockStation(601, "Mill", 70, 80), mockStation(602, "Bakery", 90, 95)}
    local _, page = openPage()
    assert(placeNames(page) == "#ui_contracts;Plowing;#ui_fields;Field No. 1;Field No. 3;#mh_placesJobs;Go to;Field work;Deliver;Load and deliver;#ui_stations;Silo;Bakery;Mill",
        placeNames(page))
    assert(page.mhPlacesList.cells[1][1]:getAttribute("info"):getText() == "42 %")
    assert(page.mhPlacesList.cells[2][1]:getAttribute("info"):getText() == "1.25 ha")
    assert(page.mhPlacesList.cells[1][1]:getAttribute("icon").imageSlice == "gui.ingameMap_contracts")
    assert(page.mhPlacesList.cells[4][1]:getAttribute("icon").imageSlice == "gui.ingameMap_loadingStation")
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
    -- Field: field work at the field.
    page.mhPlacesList:click(1, 1)
    assert(frame.ingameMap.centered[1] == 300 and frame.ingameMap.centered[2] == 310)
    local job = frame.currentJob
    assert(job.jobTypeIndex == AIJobType.FIELDWORK and job.positionAngleParameter.x == 300 and job.positionAngleParameter.z == 310)
    assert(frame.jobTypeElement.state == 2 and frame.lastValid)
    -- Loading station: load and deliver with that station.
    page.mhPlacesList:click(3, 2)
    job = frame.currentJob
    assert(job.jobTypeIndex == AIJobType.LOAD_AND_DELIVER and job.loadingStationParameter:getLoadingStation() == silo)
    assert(job.changedParameter == job.loadingStationParameter and frame.ingameMap.centered[1] == 50)
    -- Unloading station keeps the current delivery type and sets its unloading station.
    page.mhPlacesList:click(3, 3)
    assert(frame.currentJob == job and job.unloadingStationParameter:getUnloadingStation() == mill)
    -- A job type just selects that type.
    page.mhPlacesList:click(2, 1)
    assert(frame.currentJob.jobTypeIndex == AIJobType.GOTO)
    -- Without field work, a field prefills Go to.
    vehicle.canFieldWork = false
    page:setVehicle(vehicle, false)
    page.mhPlacesList:click(1, 1)
    assert(frame.currentJob.jobTypeIndex == AIJobType.GOTO and frame.currentJob.positionAngleParameter.x == 300)
end)

test("Add to queue and Insert as next send the native form's job and start a fresh form", function()
    local vehicle = seat(mockVehicle(7))
    local frame, page = openPage()
    frame.currentJob.positionAngleParameter:setPosition(5, 6)
    local first = frame.currentJob
    -- Z (MENU_MAP_ACTION_1) adds: the native handler does nothing on the page.
    g_inputBinding:trigger(InputAction.MENU_MAP_ACTION_1)
    assert(isQueued(vehicle, first) and frame.nativeStartPressed == nil)
    assert(frame.currentJob ~= first and frame.currentJob.jobTypeIndex == AIJobType.GOTO and (first.resetCount or 0) == 0)
    frame.currentJob.positionAngleParameter:setPosition(7, 8)
    -- X (MENU_EXTRA_1) inserts as next.
    g_inputBinding:trigger(InputAction.MENU_EXTRA_1)
    assert(MH.getEntries(vehicle)[1].job.positionAngleParameter.x == 7)
    assert(table.concat(rowTexts(page), ";") == "1|Go to|7, 8;2|Go to|5, 6", table.concat(rowTexts(page), ";"))
    assert(page.mhVehicleInfo.text == "Waiting: 2" and not page.mhStartStopButton.disabled)
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
    for i = 1, 3 do MH.requestAdd(vehicle, newJob(vehicle, i, i)) end
    local frame, page = openPage()
    assert(#rowTexts(page) == 3 and page.mhUpButton.disabled and not page.mhDownButton.disabled, "first row selected")
    page.mhQueueList:click(1, 3)
    assert(page.mhDownButton.disabled and not page.mhUpButton.disabled)
    page.mhUpButton.onClickCallback(page)
    assert(table.concat(rowTexts(page), ";") == "1|Go to|1, 1;2|Go to|3, 3;3|Go to|2, 2")
    assert(page.selectedRow == 2, "the selection follows the moved entry")
    page.mhDownButton.onClickCallback(page)
    assert(rowTexts(page)[3] == "3|Go to|3, 3")
    -- Edit loads the entry into the native form; Save replaces it in place.
    page.mhQueueList:click(1, 2)
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
    page.mhQueueList:click(1, 1)
    page:onClickEdit()
    g_inputBinding:trigger(InputAction.MENU_EXTRA_1)
    assert(page.editingId == nil and #MH.getEntries(vehicle) == 3 and MH.getEntries(vehicle)[1].job.positionAngleParameter.x == 1)
    -- An entry that starts while it is edited ends the edit.
    page:onClickEdit()
    MH.requestStart(vehicle)
    assert(page.editingId == nil)
    page.mhQueueList:click(1, 2)
    page.mhRemoveButton.onClickCallback(page)
    assert(#MH.getEntries(vehicle) == 1)
    page.mhClearButton.onClickCallback(page)
    assert(#MH.getEntries(vehicle) == 0)
end)

test("the running job shows its progress and disappears when it is done", function()
    local vehicle = seat(mockVehicle(7))
    vehicle.canFieldWork = true
    local field = mockField(3, 400, 200, 2, 1)
    mockContract(field, 1, "Sowing", 0.25)
    MH.requestAdd(vehicle, newJob(vehicle, 400, 200, AIJobType.FIELDWORK))
    MH.requestAdd(vehicle, newJob(vehicle, 1, 2))
    local frame, page = openPage()
    page.mhStartStopButton.onClickCallback(page)
    local rows = rowTexts(page)
    assert(#rows == 2 and rows[1] == "|Field work - task 1|ui_distance: 300 m  ·  contract_progress: 25 %", rows[1])
    assert(rows[2] == "1|Go to|1, 2" and page.mhStartStopText.text == "button_cancelJob")
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
    local current = newJob(vehicle)
    g_currentMission.aiSystem:startJob(current, 1)
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
    g_currentMission.aiSystem:startJob(newJob(vehicle), 1)
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
    assert(#MH.getEntries(vehicle) == 0)
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
    MH.requestAdd(vehicle, newJob(vehicle))
    local frame, page = openPage()
    assert(not page.mhAddButton.disabled and not page.mhStartStopButton.disabled)
    g_currentMission.paused = true
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(page.mhAddButton.disabled and page.mhStartStopButton.disabled)
    g_currentMission.paused = false
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(not page.mhAddButton.disabled and not page.mhStartStopButton.disabled)
    g_currentMission.allowed = false
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(page.mhAddButton.disabled and page.mhClearButton.disabled and page.mhEditButton.disabled)
    g_currentMission.allowed = true
    InGameMenuMapFrame.update(frame, MHPage.REFRESH_INTERVAL)
    assert(not page.mhClearButton.disabled)
end)

test("vehicles that never take a worker are recognised up front", function()
    local reel = mockVehicle(7)
    assert(MH.getSupportsAI(reel))
    reel.spec_aiJobVehicle.supportsAIJobs = false
    assert(not MH.getSupportsAI(reel), "e.g. the Emergency pack's hose reel")
end)

print(string.format("%d behavioral tests passed", passed))
