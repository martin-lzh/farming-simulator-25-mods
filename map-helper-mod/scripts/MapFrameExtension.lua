-- Map page integration: a Map Helper button under the balance in the top-right
-- corner, an "Add to queue" button next to "Start job" in the job menu, and the
-- actions of the drawer. Every action calls the native InGameMenuMapFrame flow.
MHMapFrame = {}
local MF = MHMapFrame
local MF_mt = {__index = MF}

MF.TOGGLE_XML = "gui/DrawerToggle.xml"
MF.INPUT_ACTION = "MENU_EXTRA_1"
MF.QUEUE_BUTTON_XML = "gui/QueueButton.xml"
-- Frames this Mod added controls to; the in-game menu keeps its frames between missions.
MF.injected = {}

-- Native profiles and elements are loaded the way the bundled Precision Farming
-- extension adds its map page windows (PrecisionFarmingGUI.loadAdditionalGUI).
-- Profiles are global and outlive the mission: load them once per game session.
function MF.loadElements(filename, parent, target, profileName)
    local xmlFile = loadXMLFile("mapHelperGui", MapHelper.MOD_DIRECTORY .. filename)
    if xmlFile == nil or xmlFile == 0 then
        MapHelper.warnOnce("gui_" .. filename, "Could not open %s; the map page button is not available", filename)
        return nil
    end
    if g_gui.profiles == nil or g_gui.profiles[profileName] == nil then
        g_gui:loadProfileSet(xmlFile, "GUI.GuiProfiles", g_gui.presets)
    end
    local count = #parent.elements
    g_gui:loadGuiRec(xmlFile, "GUI", parent, target)
    delete(xmlFile)
    local root = parent.elements[count + 1]
    if root ~= nil then
        root:updateAbsolutePosition()
    end
    return root
end

-- Called after InGameMenuMapFrame:onLoadMapFinished, which runs once per mission on the
-- map frame that g_inGameMenu keeps for the whole game session. A second call for the same
-- mission is ignored; controls left by an earlier copy of the scripts are replaced.
function MF.inject(frame)
    if frame == nil then
        return
    end
    if frame.mapHelper ~= nil then
        if getmetatable(frame.mapHelper) == MF_mt then
            return
        end
        MF.remove(frame)
    end
    local ext = setmetatable({frame = frame}, MF_mt)
    frame.mapHelper = ext
    table.insert(MF.injected, frame)
    -- The header holds the farm balance (shopMoneyBox) in the top-right corner.
    local header = frame.shopMoneyBox ~= nil and frame.shopMoneyBox.parent or nil
    if header ~= nil then
        ext.toggle = MF.loadElements(MF.TOGGLE_XML, header, ext, "mh_toggleContainer")
    else
        MapHelper.warnOnce("noHeader", "Map page header not found; open Map Helper with its key instead")
    end
    if ext.toggle ~= nil then
        ext.toggleText = ext.toggle:getDescendantByName("text")
        if ext.toggleText ~= nil then
            ext.toggleText:setText(MapHelper.text("mh_toggle"))
        end
        MF.placeToggle(ext)
    end
    if frame.createJobContainer ~= nil and MapHelper.features.queue then
        ext.queueButton = MF.loadElements(MF.QUEUE_BUTTON_XML, frame.createJobContainer, ext, "mh_queueContainer")
        if ext.queueButton ~= nil then
            local text = ext.queueButton:getDescendantByName("text")
            if text ~= nil then
                text:setText(MapHelper.text("mh_addToQueue"))
            end
            ext.queueButton:setVisible(false)
        end
    end
end

function MF.getExtension(frame)
    return frame ~= nil and frame.mapHelper or nil
end

MF.TOGGLE_GAP = 10

-- Right-aligns the button with the balance box (shopMoneyBoxBg) and puts it below the box
-- and the AI status line (statusMessage), so it never covers either. Works on absolute
-- positions: GuiElement:setPosition shifts absPosition by the same amount.
function MF.placeToggle(ext)
    local frame = ext.frame
    local toggle = ext.toggle
    local balance = frame ~= nil and frame.shopMoneyBoxBg or nil
    if toggle == nil or balance == nil or balance.absPosition == nil or balance.absSize == nil then
        return
    end
    local right = balance.absPosition[1] + balance.absSize[1]
    local top = balance.absPosition[2]
    local status = frame.statusMessage
    if status ~= nil and status.absPosition ~= nil then
        top = math.min(top, status.absPosition[2])
    end
    top = top - MF.TOGGLE_GAP * g_pixelSizeScaledY
    local dx = right - (toggle.absPosition[1] + toggle.absSize[1])
    local dy = top - (toggle.absPosition[2] + toggle.absSize[2])
    toggle:setPosition(toggle.position[1] + dx, toggle.position[2] + dy)
end

-- Removes the button, the job menu button and the key events from one frame.
function MF.remove(frame)
    local ext = frame.mapHelper
    frame.mapHelper = nil
    if ext == nil then
        return
    end
    if g_inputBinding ~= nil then
        g_inputBinding:removeActionEventsByTarget(ext)
    end
    for _, key in ipairs({"toggle", "queueButton"}) do
        if ext[key] ~= nil then
            ext[key]:delete()
            ext[key] = nil
        end
    end
    ext.frame = nil
end

-- Mission teardown: nothing of this Mod stays on the shared map frame.
function MF.removeAll()
    for _, frame in ipairs(MF.injected) do
        MF.remove(frame)
    end
    MF.injected = {}
end

-- Controls are removed on mission delete; this also covers any callback that is still
-- reachable after that, for example while the next mission loads without the Mod.
function MF:getIsActive()
    return self.frame ~= nil and self.frame.mapHelper == self and MapHelper.missionActive
        and g_modIsLoaded ~= nil and g_modIsLoaded[MapHelper.MOD_NAME] == true
end

-- Appended to InGameMenuMapFrame:registerInput, which runs inside the map page's own
-- input context (MENU_MAP_OVERVIEW) every time the page opens.
function MF.registerInput(frame)
    local ext = MF.getExtension(frame)
    if ext == nil or g_inputBinding == nil then
        return
    end
    -- The page layout can change between visits (resolution, UI scale).
    MF.placeToggle(ext)
    g_inputBinding:removeActionEventsByTarget(ext)
    -- One key for both buttons: the native menu action MENU_EXTRA_1, which the PC map page
    -- does not use. Its button glyph shows a single key, unlike a key combination, and it
    -- has a controller default. Only one of the two buttons is visible at a time.
    local action = InputAction[MF.INPUT_ACTION]
    if action ~= nil then
        local _, eventId = g_inputBinding:registerActionEvent(action, ext, MF.onKeyAction, false, true, false, true)
        if eventId ~= nil and eventId ~= "" then
            g_inputBinding:setActionEventTextVisibility(eventId, false)
        end
    end
end

-- Another visible button on the map page that shows the same key, such as the Help button
-- Precision Farming adds to its soil map tab. ScreenElement.callButtonsWithAction triggers
-- that one, so the key leaves it alone. This Mod's own buttons are not triggerable that way.
function MF.getHasOtherKeyButton(elements, ext)
    for _, element in ipairs(elements or {}) do
        if element ~= ext.toggle and element ~= ext.queueButton then
            if element.inputActionName == MF.INPUT_ACTION and element.getIsVisible ~= nil and element:getIsVisible()
                and not (element.getIsDisabled ~= nil and element:getIsDisabled()) then
                return true
            end
            if MF.getHasOtherKeyButton(element.elements, ext) then
                return true
            end
        end
    end
    return false
end

-- In the job menu the key adds the job to the queue; otherwise it opens the drawer.
function MF:onKeyAction()
    if not self:getIsActive() or MF.getHasOtherKeyButton(self.frame.elements, self) then
        return
    end
    if self.queueButton ~= nil and self.queueButton:getIsVisible() then
        MF.addToQueue(self.frame)
    elseif self.frame.mode == InGameMenuMapFrame.AI_MODE_OVERVIEW then
        MF.openDrawer(self.frame)
    end
end

-- Button callbacks return nothing, so ButtonElement:sendAction treats the click as used.
function MF:onClickToggle()
    if self:getIsActive() then
        MF.openDrawer(self.frame)
    end
end

function MF:onClickAddToQueue()
    if self:getIsActive() then
        MF.addToQueue(self.frame)
    end
end

function MF.openDrawer(frame)
    if frame == nil or not MapHelper.features.drawer or g_gui:getIsDialogVisible() then
        return false
    end
    return MHDrawerDialog.show(frame)
end

function MF.getControlledVehicle()
    if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil then
        return nil
    end
    return g_localPlayer:getCurrentVehicle()
end

-- The vanilla context buttons are only offered in the overview mode, outside a
-- position pick, while the game runs and no guided tour is active (getCanCreateJob).
function MF.getIsFrameIdle(frame)
    if frame.mode ~= InGameMenuMapFrame.AI_MODE_OVERVIEW or frame:getIsPicking() or g_currentMission.paused then
        return false
    end
    return g_guidedTourManager == nil or not g_guidedTourManager:getIsTourRunning()
end

-- Same check as InGameMenuMapFrame:refreshContextInput and createJob.
function MF.getHasAvailableJob(frame, vehicle, goToOnly)
    local instances = frame.jobTypeInstances or {}
    if goToOnly then
        local job = AIJobType ~= nil and instances[AIJobType.GOTO] or nil
        return job ~= nil and job:getIsAvailableForVehicle(vehicle)
    end
    for _, job in pairs(instances) do
        if job:getIsAvailableForVehicle(vehicle) then
            return true
        end
    end
    return false
end

function MF.getHasAccess(vehicle)
    local accessHandler = g_currentMission.accessHandler
    return accessHandler == nil or accessHandler:canPlayerAccess(vehicle)
end

-- Everything the drawer shows, computed from the native vehicle and frame state.
function MF.getDrawerState(frame)
    local MH = MapHelper
    local mission = g_currentMission
    local vehicle = MF.getControlledVehicle()
    local state = {vehicle = vehicle, entries = {}, canCenter = true, startStop = "start"}
    if vehicle == nil then
        state.onFoot = true
        state.title = MH.text("mh_onFoot")
        state.status = MH.text("mh_statusOnFoot")
        return state
    end
    state.title = vehicle:getName()
    if not MH.getSupportsAI(vehicle) then
        state.status = MH.text("mh_statusNoAI")
        return state
    end
    local queue = MH.queues[vehicle]
    for _, entry in ipairs(MH.getEntries(vehicle)) do
        table.insert(state.entries, {id = entry.id, label = MH.getJobLabel(entry.job)})
    end
    local permitted = MF.getHasAccess(vehicle) and MH.getCanManage(vehicle, nil)
    local aiActive = vehicle:getIsAIActive()
    local idle = MF.getIsFrameIdle(frame)
    local running = queue ~= nil and queue.running
    state.permitted = permitted
    if not permitted then
        state.status = MH.text("mh_statusNoPermission")
    elseif queue ~= nil and queue.pause ~= MH.PAUSE.NONE then
        state.status = string.format(MH.text("mh_statusPaused"), MH.getPauseReason(queue))
    elseif aiActive or running then
        state.status = MH.text("mh_statusWorking")
    else
        state.status = MH.text("mh_statusIdle")
    end
    if #state.entries > 0 then
        state.status = state.status .. "\n" .. string.format(MH.text("mh_statusWaiting"), #state.entries)
    end
    -- While the vehicle works, Create job plans the next entries like a to-do list.
    state.planning = (aiActive or running) and MH.features.queue
    state.canCreate = permitted and idle and MF.withPlanning(vehicle, state.planning, function()
        return MF.getHasAvailableJob(frame, vehicle, false)
    end)
    state.canGoTo = permitted and idle and not state.planning and MF.getHasAvailableJob(frame, vehicle, true)
    if aiActive then
        state.startStop = "cancel"
        state.canStartStop = permitted and not mission.paused
    elseif #state.entries > 0 and MH.features.queue then
        state.startStop = "queue"
        state.canStartStop = permitted and not running and not mission.paused
    elseif frame.mode == InGameMenuMapFrame.AI_MODE_CREATE and frame.currentJobVehicle == vehicle then
        state.startStop = "start"
        state.canStartStop = frame:getCanStartJob() and not mission.paused
    end
    state.canClear = permitted and #state.entries > 0 and MH.features.queue
    state.canRemove = state.canClear
    return state
end

-- Drawer actions ---------------------------------------------------------------
function MF.centerOnMe(frame)
    local vehicle = MF.getControlledVehicle()
    local hotspot = vehicle ~= nil and vehicle.getMapHotspot ~= nil and vehicle:getMapHotspot() or nil
    if hotspot ~= nil then
        if MF.getIsFrameIdle(frame) then
            frame:setMapSelectionItem(hotspot)
        end
        frame.ingameMap:panToHotspot(hotspot)
        return true
    elseif g_localPlayer ~= nil then
        -- InGameMenuMapFrame:onFrameOpen centers the map on the player the same way.
        local x, _, z = g_localPlayer:getPosition()
        frame.ingameMap:setCenterToWorldPosition(x, z)
        return true
    end
    return false
end

-- The native job types only offer themselves for a vehicle without a worker
-- (AIJobVehicle:getCanStartAIVehicle checks getIsAIActive). To plan entries for a vehicle
-- that is working, the job menu is built while the vehicle reads as idle: an instance field
-- shadows the vehicle's function for the duration of the call. Scripts catch no errors
-- (ModHub TestRunner), so if the call raises, MapHelper:update removes the shadow on the
-- next frame through MF.restorePlanning.
function MF.returnFalse()
    return false
end

function MF.withPlanning(vehicle, planning, func)
    if not planning then
        return func()
    end
    MF.restorePlanning()
    MF.planningShadow = {vehicle = vehicle, previous = rawget(vehicle, "getIsAIActive")}
    vehicle.getIsAIActive = MF.returnFalse
    local result = func()
    MF.restorePlanning()
    return result
end

function MF.restorePlanning()
    local shadow = MF.planningShadow
    if shadow ~= nil then
        MF.planningShadow = nil
        shadow.vehicle.getIsAIActive = shadow.previous
    end
end

function MF.createJob(frame)
    local state = MF.getDrawerState(frame)
    if not state.canCreate then
        return false
    end
    local vehicle = state.vehicle
    if not state.planning then
        -- Selects the hotspot, pans to it and opens the job menu after getCanCreateJob.
        frame:setAIVehicle(vehicle)
        return true
    end
    -- Same steps as InGameMenuMapFrame:setAIVehicle, minus the getCanCreateJob check that
    -- refuses a working vehicle; the job menu then only offers Add to queue.
    local hotspot = vehicle:getMapHotspot()
    frame:setMapSelectionItem(hotspot)
    frame.ingameMap:panToHotspot(hotspot)
    local ext = MF.getExtension(frame)
    if ext ~= nil then
        ext.planningVehicle = vehicle
    end
    MF.withPlanning(vehicle, true, function()
        frame:createJob()
    end)
    if frame.createJobEmptyText ~= nil then
        frame.createJobEmptyText:setVisible(false)
    end
    return frame.mode == InGameMenuMapFrame.AI_MODE_CREATE
end

function MF.goTo(frame)
    local state = MF.getDrawerState(frame)
    if not state.canGoTo then
        return false
    end
    local hotspot = state.vehicle:getMapHotspot()
    frame:setMapSelectionItem(hotspot)
    frame.ingameMap:panToHotspot(hotspot)
    -- Starts the native position and direction pick, then InGameMenuMapFrame:startGoToJob.
    frame:onStartGoToJob()
    return true
end

function MF.startStop(frame)
    local state = MF.getDrawerState(frame)
    if not state.canStartStop then
        return false
    end
    if state.startStop == "cancel" then
        -- Same call as InGameMenuMapFrame:cancelJob.
        state.vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
    elseif state.startStop == "queue" then
        MapHelper.requestStart(state.vehicle)
    else
        frame:onStartCancelJob()
    end
    return true
end

function MF.removeEntry(frame, entryId)
    local state = MF.getDrawerState(frame)
    if not state.canRemove then
        return false
    end
    return MapHelper.requestRemove(state.vehicle, entryId)
end

function MF.clearQueue(frame)
    local state = MF.getDrawerState(frame)
    if not state.canClear then
        return false
    end
    return MapHelper.requestClear(state.vehicle)
end

-- Job menu ----------------------------------------------------------------------
-- Queues are planned for the vehicle the player is sitting in, the one the drawer shows.
function MF.getCanQueueFor(frame, vehicle)
    return MapHelper.features.queue and vehicle ~= nil and vehicle == MF.getControlledVehicle()
        and MapHelper.getCanManage(vehicle, nil)
end

-- Appended to InGameMenuMapFrame:setJobMenuVisible. InGameMenuMapFrame:createJob sets the
-- mode and currentJobVehicle before it shows the menu, and creates currentJob afterwards.
function MF.updateQueueButton(frame, isVisible)
    local ext = MF.getExtension(frame)
    if ext == nil or ext.queueButton == nil then
        return
    end
    local inJobMenu = isVisible and frame.mode == InGameMenuMapFrame.AI_MODE_CREATE
    local visible = inJobMenu and MF.getCanQueueFor(frame, frame.currentJobVehicle)
    ext.queueButton:setVisible(visible and true or false)
    -- The header button shares the key with Add to queue, so it steps aside in the job menu.
    if ext.toggle ~= nil then
        ext.toggle:setVisible(not inJobMenu)
    end
    -- Planning for a working vehicle: the native Start job would be refused, so only
    -- Add to queue is offered. Leaving the job menu shows Start job again.
    local planning = inJobMenu and ext.planningVehicle ~= nil and ext.planningVehicle == frame.currentJobVehicle
    if not inJobMenu then
        ext.planningVehicle = nil
    end
    if frame.buttonStartJobContainer ~= nil then
        frame.buttonStartJobContainer:setVisible(not planning)
    end
end

-- Instead of InGameMenuMapFrame:startJob: validate like startJob, send the job to the
-- server queue and leave the job menu like the native Back button does.
function MF.addToQueue(frame)
    local MH = MapHelper
    if frame == nil or frame.mode ~= InGameMenuMapFrame.AI_MODE_CREATE or frame:getIsPicking()
        or frame.currentJob == nil or g_currentMission.paused or not frame:getCanStartJob() then
        return false
    end
    local vehicle = frame.currentJobVehicle
    if not MF.getCanQueueFor(frame, vehicle) then
        return false
    end
    local job = frame.currentJob
    job:setValues()
    local valid, errorMessage = job:validate(g_localPlayer.farmId)
    if not valid then
        InfoDialog.show(tostring(errorMessage), nil, nil, DialogElement.TYPE_WARNING)
        frame:updateWarnings()
        return false
    end
    if #MH.getEntries(vehicle) >= MH.MAX_ENTRIES then
        InfoDialog.show(string.format(MH.text("mh_queueFull"), MH.MAX_ENTRIES), nil, nil, DialogElement.TYPE_WARNING)
        return false
    end
    MH.requestAdd(vehicle, job)
    -- Leave the job menu the way a successful InGameMenuMapFrame:startJob does. Not
    -- onClickBack: it calls resetTasks on currentJob, which the queue owns now (on the
    -- host the request event passed it by reference).
    frame.mode = InGameMenuMapFrame.AI_MODE_OVERVIEW
    frame.currentJob = nil
    frame:setJobMenuVisible(false)
    frame:refreshContextInput()
    -- Show the queue with the new entry, like ticking off a to-do list.
    MF.openDrawer(frame)
    return true
end
