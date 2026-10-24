-- The Map Helper page of the map overview sidebar (gui/MapHelperPage.xml), from top to
-- bottom: the vehicle card, places where the vehicle can work, the native job form
-- (InGameMenuMapFrame.createJobContainer, placed into the page), Add to queue / Insert as
-- next, and the command queue with the running job first.
--
-- The page shows one vehicle: the one the player sits in, or an own vehicle selected on
-- the map while the page is open. All job parameters, validation and map picking are the
-- native create-job flow of InGameMenuMapFrame; the page only replaces Start job.
MHPage = {}
local MHPage_mt = {__index = MHPage}
local MH = MapHelper

MHPage.XML = "gui/MapHelperPage.xml"
MHPage.ROOT_PROFILE = "mh_page"
MHPage.FORM_PROFILE = "mh_nativeForm"
MHPage.NATIVE_FORM_PROFILE = "fs25_subCategoryListContainer"
MHPage.REFRESH_INTERVAL = 1000
MHPage.EDIT_XML = "mapHelperEditJob.xml"

MHPage.ICON = {
    CONTRACT = "gui.ingameMap_contracts",
    -- The seedling of the shop's seeding attribute; the farmland icon (a hill with a marker)
    -- reads as a person at list size.
    FIELD = "gui.storeAttribute_seeding",
    LOADING = "gui.ingameMap_loadingStation",
    UNLOADING = "gui.ingameMap_tippingStation"
}

function MHPage.new(frame, ext)
    local self = setmetatable({}, MHPage_mt)
    self.frame = frame
    self.ext = ext
    self.name = frame.name
    self.vehicle = nil
    self.places = {}
    self.filterByVehicle = {}
    self.rows = {}
    self.selectedRow = nil
    self.editingId = nil
    self.shown = false
    -- The page is the target of its lists: SmoothListElement compares target.time with the
    -- last click to raise a double click (SDK gui/elements/SmoothListElement.lua:1546), so the
    -- page keeps a clock like a screen does.
    self.time = 0
    self.refreshTimer = 0
    return self
end

-- Loads the page into the sidebar (filterBox) with this table as the target, like
-- PrecisionFarmingGUI.loadAdditionalGUI: ids become fields of the target, then the new
-- elements finish their setup (lists find their templates, sliders their lists).
function MHPage:load()
    self.root = MHMapFrame.loadElements(MHPage.XML, self.frame.filterBox, self, MHPage.ROOT_PROFILE)
    if self.root == nil then
        return false
    end
    for _, element in ipairs(self.root:getDescendants()) do
        if element.id ~= nil and element.id ~= "" then
            self[element.id] = element
        end
    end
    self.mhPage = self.root
    self.root:onGuiSetupFinished()
    -- Button labels highlight with their button, as the native map buttons do (MF:158-173).
    for _, pair in ipairs({{"mhResumeText", "mhResumeButton"},
        {"mhAddText", "mhAddButton"}, {"mhNextText", "mhNextButton"}, {"mhClearText", "mhClearButton"},
        {"mhEditText", "mhEditButton"}, {"mhRemoveText", "mhRemoveButton"}}) do
        local text, button = self[pair[1]], self[pair[2]]
        if text ~= nil and button ~= nil then
            text.getIsFocused = function()
                return button:getIsFocused()
            end
            text.getIsHighlighted = function()
                return button:getIsHighlighted()
            end
        end
    end
    self.root:setVisible(false)
    MH.addListener(MHPage.onQueueChanged, self)
    return true
end

-- Elements look up ids on their target (SmoothListElement emptyIndicatorId, tool tips).
function MHPage:getDescendantById(id)
    return self.root ~= nil and self.root:getDescendantById(id) or nil
end

function MHPage:getIsActive()
    return self.ext ~= nil and self.ext:getIsActive() and self.root ~= nil
end

function MHPage:getIsShown()
    return self.shown and self:getIsActive()
end

-- Show / hide ------------------------------------------------------------------------
function MHPage:show()
    if not self:getIsActive() then
        return
    end
    local wasShown = self.shown
    self.shown = true
    self.root:setVisible(true)
    local vehicle = self.vehicle
    if not wasShown or not MH.getVehicleExists(vehicle) then
        vehicle = MHMapFrame.getControlledVehicle()
    end
    self:setVehicle(vehicle, true)
end

function MHPage:hide()
    if not self.shown then
        return
    end
    self.shown = false
    self.editingId = nil
    if self.root ~= nil then
        self.root:setVisible(false)
    end
    self:releaseNativeForm()
end

-- Mission teardown, after FSBaseMission:delete: native form back, page removed. Only GUI
-- elements are touched here; nothing calls into the deleted mission.
function MHPage:release()
    MH.removeListener(self)
    self.shown = false
    self.editingId = nil
    self:releaseNativeForm(true)
    if self.root ~= nil then
        self.root:delete()
        self.root = nil
    end
    self.vehicle = nil
    self.filterByVehicle = {}
    self.ext = nil
end

-- Vehicle ------------------------------------------------------------------------------
function MHPage:getIsPlanning(vehicle)
    local queue = MH.queues[vehicle]
    return vehicle:getIsAIActive() or (queue ~= nil and queue.running)
end

-- Shows a vehicle (or nobody). Selects its map hotspot like InGameMenuMapFrame:setAIVehicle,
-- builds the job form for it and fills the lists.
function MHPage:setVehicle(vehicle, pan)
    local frame = self.frame
    self.vehicle = vehicle
    self.editingId = nil
    self.selectedRow = nil
    local hotspot = vehicle ~= nil and vehicle.getMapHotspot ~= nil and vehicle:getMapHotspot() or nil
    if hotspot ~= nil and frame.mode == InGameMenuMapFrame.AI_MODE_OVERVIEW and not frame:getIsPicking() then
        self.selecting = true
        frame:setMapSelectionItem(hotspot)
        self.selecting = false
        if pan then
            frame.ingameMap:panToHotspot(hotspot)
        end
    end
    self:buildForm(nil, nil)
    self:updateFilterOptions()
    self:reloadPlaces()
    self:refresh()
end

-- From the setMapSelectionItem hook: another own vehicle selected on the map.
function MHPage:onMapSelectionChanged(hotspot)
    if self.selecting then
        return
    end
    local vehicle = hotspot ~= nil and hotspot.getVehicle ~= nil and hotspot:getVehicle() or nil
    if vehicle ~= nil and vehicle ~= self.vehicle and MHMapFrame.getCanPlanFor(vehicle) then
        self:setVehicle(vehicle, false)
    else
        -- The native selection removed or moved the target markers; show the form's again.
        self:showFormMarkers()
    end
end

-- Native job form ------------------------------------------------------------------------
-- The native createJobContainer goes into the page's form slot (profile mh_nativeForm) and
-- its Start job button is hidden; Add to queue and Insert as next replace it.
function MHPage:placeNativeForm()
    local frame = self.frame
    local container = frame.createJobContainer
    if not self.formPlaced then
        self.formPlaced = true
        container:applyProfile(MHPage.FORM_PROFILE)
        -- applyProfile keeps the old anchor deltas; setPosition recomputes them.
        container:setPosition(container.position[1], container.position[2])
        if frame.buttonStartJobContainer ~= nil then
            frame.buttonStartJobContainer:setVisible(false)
        end
    end
    container:setVisible(true)
    if frame.createJobEmptyText ~= nil then
        frame.createJobEmptyText:setVisible(false)
    end
    self:fitLayout()
end

-- The form takes the height its job type needs and the places list the rest. Reference
-- pixels inside the page (MapHelperPage.xml): the places box starts at PLACES_TOP, the form
-- ends at FORM_BOTTOM just above Add to queue. The native form is 40 px per row: the job type
-- selector plus a title and a row per parameter (InGameMenuMapFrame:setActiveJobTypeSelection,
-- decompiled gui/InGameMenuMapFrame.lua:1403-1451). Load and deliver needs the most, 320 px;
-- field work and Go to need 120 px. Both boxes are anchored at their top edge (pivot 0 1), so
-- a new size keeps the top.
MHPage.PAGE_TOP = 145
MHPage.PLACES_TOP = 139
MHPage.FORM_BOTTOM = 597
MHPage.FORM_GAP = 8
MHPage.FORM_MIN = 40
MHPage.FORM_MAX = 320

function MHPage:getFormHeight()
    local frame = self.frame
    local container = frame.createJobContainer
    if container == nil or not self.formPlaced or not container:getIsVisible() or frame.jobTypeElement == nil
        or frame.jobMenuLayout == nil then
        return MHPage.FORM_MAX
    end
    local used = frame.jobTypeElement.absSize[2]
    for _, element in ipairs(frame.jobMenuLayout.elements) do
        if element:getIsVisible() then
            used = used + element.absSize[2]
        end
    end
    return math.max(MHPage.FORM_MIN, math.min(MHPage.FORM_MAX, math.ceil(used / g_pixelSizeScaledY - 0.5)))
end

function MHPage:fitLayout()
    local px = g_pixelSizeScaledY
    local height = self:getFormHeight()
    local formTop = MHPage.FORM_BOTTOM - height
    local container = self.frame.createJobContainer
    if container ~= nil and self.formPlaced then
        container:setSize(nil, height * px)
        container:setPosition(nil, -(MHPage.PAGE_TOP + formTop) * px)
    end
    local placesHeight = formTop - MHPage.FORM_GAP - MHPage.PLACES_TOP
    if self.placesHeight ~= placesHeight then
        self.placesHeight = placesHeight
        self.mhPlacesBox:setSize(nil, placesHeight * px)
        self.mhPlacesList:reloadData()
    end
end

-- Empties the form like InGameMenuMapFrame:setJobMenuVisible(false) does, without its focus
-- and selector side effects. A native create-job flow that is opening the job menu right
-- now (mode AI_MODE_CREATE) keeps its vehicle and job.
function MHPage:clearForm(teardown)
    local frame = self.frame
    if frame.mode == InGameMenuMapFrame.AI_MODE_CREATE then
        return
    end
    local layout = frame.jobMenuLayout
    if layout ~= nil then
        for i = #layout.elements, 1, -1 do
            layout.elements[i]:delete()
        end
        layout:invalidateLayout()
    end
    frame.currentJobElements = {}
    if frame.jobTypeElement ~= nil then
        frame.jobTypeElement:setTexts({})
    end
    frame.currentJob = nil
    frame.currentJobVehicle = nil
    local mission = g_currentMission
    if not teardown and mission ~= nil and mission.removeMapHotspot ~= nil and not frame:getIsPicking() then
        mission:removeMapHotspot(frame.aiTargetMapHotspot)
        mission:removeMapHotspot(frame.aiLoadingMarkerHotspot)
        mission:removeMapHotspot(frame.aiUnloadingMarkerHotspot)
    end
end

function MHPage:releaseNativeForm(teardown)
    if not self.formPlaced then
        return
    end
    self.formPlaced = false
    local frame = self.frame
    local container = frame.createJobContainer
    if not teardown and frame:getIsPicking() then
        frame:executePickingCallback(false)
    end
    self:clearForm(teardown)
    if frame.mode ~= InGameMenuMapFrame.AI_MODE_CREATE then
        container:setVisible(false)
    end
    container:applyProfile(MHPage.NATIVE_FORM_PROFILE)
    container:setPosition(container.position[1], container.position[2])
    if frame.buttonStartJobContainer ~= nil then
        frame.buttonStartJobContainer:setVisible(true)
    end
    if frame.jobMenuLayout ~= nil then
        frame.jobMenuLayout:invalidateLayout()
    end
end

-- Why no form is shown for the current vehicle, or nil when one can be planned.
function MHPage:getNoFormReason(vehicle)
    if vehicle == nil then
        return MH.text("mh_statusOnFoot")
    elseif not MH.getSupportsAI(vehicle) then
        return MH.text("mh_statusNoAI")
    elseif not MHMapFrame.getCanPlanFor(vehicle) then
        return MH.text("mh_statusNoPermission")
    end
    return nil
end

-- Job types the vehicle can do, in job type order, like InGameMenuMapFrame:createJob.
function MHPage:getAvailableJobTypes(vehicle)
    local frame = self.frame
    local result = {}
    local manager = MH.getJobTypeManager()
    if AIJobType == nil or manager == nil or vehicle == nil then
        return result
    end
    local indices = {}
    for _, index in pairs(AIJobType) do
        table.insert(indices, index)
    end
    table.sort(indices)
    MHMapFrame.withPlanning(vehicle, self:getIsPlanning(vehicle), function()
        for _, index in ipairs(indices) do
            local instance = frame.jobTypeInstances ~= nil and frame.jobTypeInstances[index] or nil
            if instance ~= nil and instance:getIsAvailableForVehicle(vehicle) then
                local jobType = manager:getJobTypeByIndex(index)
                table.insert(result, {index = index, title = jobType ~= nil and jobType.title or "?", instance = instance})
            end
        end
    end)
    return result
end

-- Builds the native form for the shown vehicle: the job type selector and the parameter
-- rows of InGameMenuMapFrame:setActiveJobTypeSelection. jobTypeIndex picks the type
-- (default: the vehicle's last job type, as natively); sourceJob fills in its parameters.
function MHPage:buildForm(jobTypeIndex, sourceJob)
    local frame = self.frame
    local vehicle = self.vehicle
    local reason = self:getNoFormReason(vehicle)
    local types = reason == nil and self:getAvailableJobTypes(vehicle) or {}
    if reason == nil and #types == 0 then
        reason = MH.text("mh_statusNoAI")
    end
    self.jobTypes = types
    if reason ~= nil then
        self:clearForm()
        if self.formPlaced then
            frame.createJobContainer:setVisible(false)
        end
        self.mhFormEmptyText:setText(reason)
        self.mhFormEmptyText:setVisible(true)
        return false
    end
    self.mhFormEmptyText:setVisible(false)

    local lastJob = vehicle.getLastJob ~= nil and vehicle:getLastJob() or nil
    local selected = nil
    local texts = {}
    local indices = {}
    for i, jobType in ipairs(types) do
        table.insert(texts, jobType.title)
        table.insert(indices, jobType.index)
        if jobTypeIndex ~= nil then
            if jobType.index == jobTypeIndex then
                selected = i
            end
        elseif selected == nil or (lastJob ~= nil and lastJob.class == jobType.instance.class) then
            selected = i
        end
    end
    selected = selected or 1
    frame.currentJobTypes = indices
    frame.jobTypeElement:setTexts(texts)
    frame.jobTypeElement:setState(selected)
    frame.currentJobVehicle = vehicle
    frame.currentJob = nil
    self:placeNativeForm()
    MHMapFrame.withPlanning(vehicle, self:getIsPlanning(vehicle), function()
        frame:setActiveJobTypeSelection(indices[selected])
    end)
    if sourceJob ~= nil and frame.currentJob ~= nil then
        MHPage.copyJobParameters(sourceJob, frame.currentJob)
        frame:updateParameterValueTexts()
        frame:validateParameters()
    end
    self:onFormBuilt()
    -- The context box was refreshed while the vehicle read as idle.
    frame:refreshContextInput()
    self:refreshButtons()
    return true
end

-- Job type indices in order, to see whether the available types changed.
function MHPage.getJobTypesSignature(types)
    local parts = {}
    for _, jobType in ipairs(types or {}) do
        table.insert(parts, tostring(jobType.index))
    end
    return table.concat(parts, ",")
end

-- Which job types the vehicle can do changes with its implements: field work needs an AI
-- implement (AIJobFieldWork:getIsAvailableForVehicle asks getCanStartFieldWork, SDK
-- ai/jobs/AIJobFieldWork.lua:166-168). The periodic refresh reads them again; when they
-- changed, the form is rebuilt with its current type (if still offered) and parameters, so
-- the job type selector and the places (field work or Go to) follow the attached implements.
-- Not while a position is being picked on the map.
function MHPage:refreshJobTypes()
    local vehicle = self.vehicle
    if self:getNoFormReason(vehicle) ~= nil or self.frame:getIsPicking() then
        return false
    end
    local types = self:getAvailableJobTypes(vehicle)
    if MHPage.getJobTypesSignature(types) == MHPage.getJobTypesSignature(self.jobTypes) then
        return false
    end
    local job = self.frame.currentJob
    self:buildForm(job ~= nil and MH.getJobTypeIndex(job) or nil, job)
    return true
end

-- Copies the parameters of a queued job into the form's job, the way AIJobVehicle saves
-- and loads lastJob: AIJob:saveToXMLFile/loadFromXMLFile through an XML file that only
-- exists in memory (never saved). The vehicle parameter has no loadFromXMLFile and stays.
-- Parameters that depend on others (fill types on the loading station) are refreshed.
function MHPage.copyJobParameters(source, target)
    local xmlFile = XMLFile.create("mapHelperEditXML", MH.MOD_DIRECTORY .. MHPage.EDIT_XML, "mapHelperJob")
    if xmlFile == nil then
        return false
    end
    source:saveToXMLFile(xmlFile, "mapHelperJob", {})
    target:loadFromXMLFile(xmlFile, "mapHelperJob")
    xmlFile:delete()
    if target.getNamedParameters ~= nil and target.onParameterValueChanged ~= nil then
        for _, item in ipairs(target:getNamedParameters()) do
            target:onParameterValueChanged(item.parameter)
        end
    end
    target:setValues()
    return true
end

-- From the setActiveJobTypeSelection hook as well: the vehicle row of the form repeats the
-- card, so the vehicle group (title and vehicle row) is hidden on the page.
function MHPage:onFormBuilt()
    local frame = self.frame
    local job = frame.currentJob
    local layout = frame.jobMenuLayout
    if job == nil or layout == nil then
        return
    end
    local position = 1
    for _, group in ipairs(job:getGroupedParameters()) do
        local parameters = group:getParameters()
        local vehicleOnly = #parameters > 0
        for _, parameter in ipairs(parameters) do
            if parameter:getType() ~= AIParameterType.TEXT then
                vehicleOnly = false
            end
        end
        for i = position, position + #parameters do
            local element = layout.elements[i]
            if element ~= nil and vehicleOnly then
                element:setVisible(false)
            end
        end
        position = position + #parameters + 1
    end
    layout:invalidateLayout()
    self:fitLayout()
    self:refreshButtons()
end

-- Target markers of the form (position, stations), as InGameMenuMapFrame:
-- updateParameterValueTexts adds them, without panning the map.
function MHPage:showFormMarkers()
    local frame = self.frame
    local job = frame.currentJob
    local mission = g_currentMission
    if job == nil or not self.formPlaced or frame:getIsPicking() or job.getNamedParameters == nil then
        return
    end
    for _, item in ipairs(job:getNamedParameters()) do
        local parameter = item.parameter
        local parameterType = parameter:getType()
        if parameterType == AIParameterType.POSITION or parameterType == AIParameterType.POSITION_ANGLE then
            local x, z = parameter:getPosition()
            if x ~= nil and z ~= nil then
                frame.aiTargetMapHotspot:setWorldPosition(x, z)
                if parameterType == AIParameterType.POSITION_ANGLE and parameter:getAngle() ~= nil then
                    frame.aiTargetMapHotspot:setWorldRotation(parameter:getAngle() + math.pi)
                end
                mission:addMapHotspot(frame.aiTargetMapHotspot)
            end
        elseif parameterType == AIParameterType.LOADING_STATION or parameterType == AIParameterType.UNLOADING_STATION then
            -- Each parameter type has only its own getter; an unset station is nil.
            local station, marker
            if parameterType == AIParameterType.LOADING_STATION then
                station, marker = parameter:getLoadingStation(), frame.aiLoadingMarkerHotspot
            else
                station, marker = parameter:getUnloadingStation(), frame.aiUnloadingMarkerHotspot
            end
            local x, z = MHPage.getStationPosition(station)
            if x ~= nil and z ~= nil then
                marker:setWorldPosition(x, z)
                mission:addMapHotspot(marker)
            end
        end
    end
end

-- Map position of a station, from its placeable's first hotspot like the native markers.
function MHPage.getStationPosition(station)
    local placeable = station ~= nil and station.owningPlaceable or nil
    if placeable ~= nil and placeable.getHotspot ~= nil then
        local hotspot = placeable:getHotspot(1)
        if hotspot ~= nil then
            return hotspot:getWorldPosition()
        end
    end
    return nil, nil
end

-- Adding and editing ------------------------------------------------------------------
-- Validates the form's job like InGameMenuMapFrame:startJob; shows the native warning.
function MHPage:getValidFormJob()
    local frame = self.frame
    local job = frame.currentJob
    if not self:getIsShown() or job == nil or not self.formPlaced or frame:getIsPicking()
        or g_currentMission.paused or not MHMapFrame.getCanPlanFor(self.vehicle) then
        return nil
    end
    job:setValues()
    local valid, errorMessage = job:validate(g_localPlayer.farmId)
    if not valid then
        InfoDialog.show(tostring(errorMessage), nil, nil, DialogElement.TYPE_WARNING)
        frame:updateWarnings()
        return nil
    end
    return job
end

-- Sends the form's job and starts a fresh form of the same type: the queue owns the sent
-- job now (on the host the request passes it by reference).
function MHPage:submit(insertNext)
    local job = self:getValidFormJob()
    if job == nil then
        return false
    end
    local vehicle = self.vehicle
    local typeIndex = MH.getJobTypeIndex(job)
    if self.editingId ~= nil then
        MH.requestEdit(vehicle, self.editingId, job)
        self.editingId = nil
    else
        if #MH.getEntries(vehicle) >= MH.MAX_ENTRIES then
            InfoDialog.show(string.format(MH.text("mh_queueFull"), MH.MAX_ENTRIES), nil, nil, DialogElement.TYPE_WARNING)
            return false
        end
        MH.requestAdd(vehicle, job, insertNext)
    end
    self.frame.currentJob = nil
    self:buildForm(typeIndex, nil)
    self:refresh()
    return true
end

function MHPage:onClickAdd()
    if self:getIsShown() then
        self:submit(false)
    end
end

-- Insert as next; while editing the same key cancels the edit.
function MHPage:onClickInsertNext()
    if not self:getIsShown() then
        return
    end
    if self.editingId ~= nil then
        self.editingId = nil
        self:buildForm(nil, nil)
        self:refresh()
    else
        self:submit(true)
    end
end

-- Places ------------------------------------------------------------------------------
-- The places list shows one category at a time, chosen with the filter selector above it:
-- fields that need the combination's work, all own fields with their state, the farm's
-- contracts, or the stations the vehicle's delivery jobs accept.
MHPage.FILTER = {NEEDS = "needs", FIELDS = "fields", CONTRACTS = "contracts", STATIONS = "stations"}
MHPage.FILTER_EMPTY = {needs = "mh_emptyNeeds", fields = "mh_emptyFields", contracts = "mh_emptyContracts",
    stations = "mh_emptyStations"}
MHPage.PLACES_INTERVAL = 10000

function MHPage:getFilterTitle(key)
    if key == MHPage.FILTER.NEEDS then
        return MH.text("mh_filterNeeds")
    elseif key == MHPage.FILTER.FIELDS then
        return MH.text("mh_filterFields")
    elseif key == MHPage.FILTER.CONTRACTS then
        return g_i18n:getText("ui_contracts")
    end
    return g_i18n:getText("ui_stations")
end

function MHPage:getAvailableTypes()
    local available = {}
    for _, jobType in ipairs(self.jobTypes or {}) do
        available[jobType.index] = true
    end
    return available
end

-- Options for the shown vehicle and the remembered or default choice: the needs filter when
-- the combination does field work the page can recognise, otherwise all own fields. With
-- keepCurrent (the periodic refresh, when implements may have changed) the shown choice stays
-- while it is still offered.
function MHPage:updateFilterOptions(keepCurrent)
    local vehicle = self.vehicle
    local options = {}
    self.works, self.workList = {}, {}
    if self:getNoFormReason(vehicle) == nil then
        self.works, self.workList = MHFieldNeeds.getWorks(vehicle)
        local available = self:getAvailableTypes()
        if #self.workList > 0 and MH.features.fieldNeeds then
            table.insert(options, MHPage.FILTER.NEEDS)
        end
        table.insert(options, MHPage.FILTER.FIELDS)
        table.insert(options, MHPage.FILTER.CONTRACTS)
        if available[AIJobType.LOAD_AND_DELIVER] or available[AIJobType.DELIVER] then
            table.insert(options, MHPage.FILTER.STATIONS)
        end
    end
    self.filterOptions = options
    local wanted = vehicle ~= nil and self.filterByVehicle[vehicle] or nil
    if keepCurrent and self.filterKey ~= nil then
        wanted = self.filterKey
    end
    local selected = nil
    local texts = {}
    for i, key in ipairs(options) do
        table.insert(texts, self:getFilterTitle(key))
        if key == wanted then
            selected = i
        end
    end
    selected = selected or 1
    self.filterKey = options[selected]
    self.mhFilterSelector:setTexts(texts)
    self.mhFilterSelector:setState(selected)
    self.mhFilterSelector:setDisabled(#options == 0)
end

-- MultiTextOption callback (state, element): remember the choice for this vehicle.
function MHPage:onClickFilter(state)
    local key = self.filterOptions ~= nil and self.filterOptions[state] or nil
    if key == nil or not self:getIsShown() then
        return
    end
    self.filterKey = key
    if self.vehicle ~= nil then
        self.filterByVehicle[self.vehicle] = key
    end
    self:reloadPlaces()
end

function MHPage:reloadPlaces()
    local places = {}
    local vehicle = self.vehicle
    local key = self.filterKey
    self.placesTimer = 0
    if key ~= nil and self:getNoFormReason(vehicle) == nil then
        local farmId = vehicle:getOwnerFarmId()
        local available = self:getAvailableTypes()
        local fieldJob = AIJobType.FIELDWORK ~= nil and available[AIJobType.FIELDWORK] and AIJobType.FIELDWORK
            or (AIJobType.GOTO ~= nil and available[AIJobType.GOTO] and AIJobType.GOTO or nil)
        if key == MHPage.FILTER.NEEDS then
            -- Accepted contracts this combination can do come first (they have a deadline),
            -- then own fields that need the work. Contract fields belong to someone else.
            places = self:getContractPlaces(farmId, fieldJob, true)
            for _, item in ipairs(self:getFieldPlaces(farmId, fieldJob, true)) do
                table.insert(places, item)
            end
        elseif key == MHPage.FILTER.FIELDS then
            places = self:getFieldPlaces(farmId, fieldJob, false)
        elseif key == MHPage.FILTER.CONTRACTS then
            places = self:getContractPlaces(farmId, fieldJob)
        else
            places = self:getStationPlaces(vehicle, available)
        end
        if key ~= MHPage.FILTER.STATIONS then
            -- Places a worker already has are marked; in the work lists they go to the end.
            places = MHPage.markClaims(places, self:getClaims(farmId), key ~= MHPage.FILTER.FIELDS)
        end
    end
    self.places = places
    self.mhPlacesList:reloadData()
    local empty = #places == 0 and key ~= nil
    self.mhPlacesEmpty:setVisible(empty)
    if empty then
        self.mhPlacesEmpty:setText(MH.text(MHPage.FILTER_EMPTY[key]))
    end
end

-- Texts of the works a field needs, the first two.
function MHPage.getNeedsText(needs)
    local texts = {}
    for i = 1, math.min(#needs, 2) do
        table.insert(texts, MHFieldNeeds.getWorkText(needs[i]))
    end
    return table.concat(texts, ", ")
end

-- The point the game keeps a field's state at: Field:updateState reads FieldState at the
-- field's own position (decompiled field/Field.lua:94-96, 194-199), which is also the target
-- inside the field for a job. The name sign (getIndicatorPosition) is only where the number
-- is drawn and often lies on a headland or an edge strip that was never worked.
function MHPage.getFieldPoint(field)
    if field ~= nil and field.getCenterOfFieldWorldPosition ~= nil then
        return field:getCenterOfFieldWorldPosition()
    end
    return nil, nil
end

-- Fields on farmland the farm owns, by number (as InGameMenuMobileMapFrame:updateFields), each
-- read at its field point. Merged fields are grouped first, so a group keeps all its fields'
-- farmlands for the worker marks; onlyNeeded then keeps the groups where any field needs the
-- combination's work and points the row at the first such field.
function MHPage:getFieldPlaces(farmId, jobTypeIndex, onlyNeeded)
    local items = {}
    if g_fieldManager == nil or g_farmlandManager == nil then
        return items
    end
    local fields = {}
    for _, field in pairs(g_fieldManager:getFields()) do
        if field.farmland ~= nil and g_farmlandManager:getFarmlandOwner(field.farmland.id) == farmId and field:getId() ~= nil then
            table.insert(fields, field)
        end
    end
    table.sort(fields, function(a, b)
        return a:getId() < b:getId()
    end)
    for _, field in ipairs(fields) do
        local x, z = MHPage.getFieldPoint(field)
        table.insert(items, {ids = {field:getId()}, area = field:getAreaHa(), icon = MHPage.ICON.FIELD, x = x, z = z,
            jobTypeIndex = jobTypeIndex, farmlands = {field.farmland.id}, bounds = MHFieldNeeds.getFieldBounds(field),
            state = MHFieldNeeds.readState(x, z)})
    end
    local places = {}
    for _, item in ipairs(MHPage.mergeFieldItems(items)) do
        local ids = {}
        for _, id in ipairs(item.ids) do
            table.insert(ids, tostring(id))
        end
        item.name = string.format("%s %s", g_i18n:getText("ui_fieldNo"), table.concat(ids, " + "))
        if onlyNeeded then
            for _, member in ipairs(item.members) do
                local needs = MHFieldNeeds.getNeeds(member.state, self.works, self.workList)
                if #needs > 0 then
                    item.x, item.z = member.x, member.z
                    item.info = MHPage.getNeedsText(needs)
                    break
                end
            end
        else
            local stateText = MHFieldNeeds.getStateText(item.state)
            item.info = stateText ~= "" and stateText or g_i18n:formatArea(item.area, 2)
        end
        if item.info ~= nil then
            item.members, item.state, item.bounds = nil, nil, nil
            table.insert(places, item)
        end
    end
    return places
end

-- Merged fields become one row "Field No. 3 + 4 + 5" at the first field's point, with the
-- first field's state, the total area and every field as a member. Fields are joined when the
-- ground between their points is field ground (MHFieldNeeds.getIsGroundConnected), also through
-- a third one.
function MHPage.mergeFieldItems(items)
    local groupOf = {}
    for i = 1, #items do
        groupOf[i] = i
    end
    local function find(i)
        while groupOf[i] ~= i do
            i = groupOf[i]
        end
        return i
    end
    for i = 1, #items do
        for j = i + 1, #items do
            if find(i) ~= find(j) and MHFieldNeeds.getIsGroundConnected(items[i].x, items[i].z, items[j].x, items[j].z,
                items[i].bounds, items[j].bounds) then
                groupOf[find(j)] = find(i)
            end
        end
    end
    local merged, byRoot = {}, {}
    for i, item in ipairs(items) do
        local root = find(i)
        local group = byRoot[root]
        if group == nil then
            byRoot[root] = item
            item.members = {item}
            table.insert(merged, item)
        else
            table.insert(group.ids, item.ids[1])
            table.insert(group.farmlands, item.farmlands[1])
            table.insert(group.members, item)
            group.area = (group.area or 0) + (item.area or 0)
        end
    end
    return merged
end

-- Contracts of the farm that are in progress and belong to a field (MissionManager:
-- getMissionsByFarmId, AbstractMission:getIsInProgress, AbstractFieldMission). Contracts
-- whose field needs the combination's work come first and name that work.
-- Farmlands whose field already has a worker: field work of the farm that runs now
-- (AISystem:getActiveJobs, SDK ai/AISystem.lua:541) or waits in a Map Helper queue. The job's
-- start position (AIParameterPosition:getPosition, SDK ai/parameters/AIParameterPosition.lua:71)
-- names the field; its farmland comes from FarmlandManager:getFarmlandIdAtWorldPosition (SDK
-- economy/FarmlandManager.lua:421). A running job wins over a queued one.
MHPage.CLAIM = {WORKING = "working", QUEUED = "queued"}
MHPage.CLAIM_TEXT = {working = "mh_claimWorking", queued = "mh_claimQueued"}

function MHPage:getClaims(farmId)
    local claims = {}
    local function claim(job, kind)
        if job == nil or AIJobType.FIELDWORK == nil or MH.getJobTypeIndex(job) ~= AIJobType.FIELDWORK then
            return
        end
        local parameter = job.positionAngleParameter
        if parameter == nil or parameter.getPosition == nil or g_farmlandManager == nil then
            return
        end
        local x, z = parameter:getPosition()
        local farmlandId = x ~= nil and g_farmlandManager:getFarmlandIdAtWorldPosition(x, z) or nil
        if farmlandId ~= nil and farmlandId ~= 0 and claims[farmlandId] ~= MHPage.CLAIM.WORKING then
            claims[farmlandId] = kind
        end
    end
    local aiSystem = g_currentMission ~= nil and g_currentMission.aiSystem or nil
    if aiSystem ~= nil and aiSystem.getActiveJobs ~= nil then
        for _, job in ipairs(aiSystem:getActiveJobs() or {}) do
            if job.startedFarmId == nil or job.startedFarmId == farmId then
                claim(job, MHPage.CLAIM.WORKING)
            end
        end
    end
    for _, queue in pairs(MH.queues) do
        if queue.farmId == farmId then
            for _, entry in ipairs(queue.entries) do
                claim(entry.job, MHPage.CLAIM.QUEUED)
            end
        end
    end
    return claims
end

-- A claimed place shows the claim instead of the work (plus a contract's progress), so the
-- 150 px info column (mh_placeItemInfo, textLayoutMode resize) keeps a readable size. With
-- sendToEnd, claimed places move behind the others (keeping their order).
function MHPage.markClaims(places, claims, sendToEnd)
    local free, claimed = {}, {}
    for _, place in ipairs(places) do
        local kind = nil
        for _, farmlandId in ipairs(place.farmlands or {}) do
            local found = claims[farmlandId]
            if found == MHPage.CLAIM.WORKING or (found ~= nil and kind == nil) then
                kind = found
            end
        end
        place.claim = kind
        if kind ~= nil then
            local text = MH.text(MHPage.CLAIM_TEXT[kind])
            place.info = place.percent ~= nil and string.format("%s · %s", text, place.percent) or text
            table.insert(sendToEnd and claimed or free, place)
        else
            table.insert(free, place)
        end
    end
    for _, place in ipairs(claimed) do
        table.insert(free, place)
    end
    return free
end

-- The work a contract asks for, by mission type (MissionManager:registerMissionType names,
-- decompiled missions/field/*Mission.lua NAME). Baling, wrapping and tedding contracts have
-- no work the page recognises.
MHPage.CONTRACT_WORK = {
    PLOWMISSION = "PLOW", CULTIVATEMISSION = "CULTIVATE", SOWMISSION = "SOW", FERTILIZEMISSION = "FERTILIZE",
    HERBICIDEMISSION = "HERBICIDE", WEEDMISSION = "WEED", HOEMISSION = "WEED", HARVESTMISSION = "HARVEST",
    MOWMISSION = "MOW", STONEPICKMISSION = "STONES"
}

-- The contract's work when this combination can do it: the work by contract type, a weeder
-- for weeding and a hoe for hoeing, and for harvesting and mowing the contract's crop.
function MHPage:getContractWork(mission)
    local typeName = mission.type ~= nil and mission.type.name or nil
    local work = typeName ~= nil and MHPage.CONTRACT_WORK[string.upper(typeName)] or nil
    local data = work ~= nil and self.works ~= nil and self.works[work] or nil
    if data == nil then
        return nil
    end
    local upper = string.upper(typeName)
    if (upper == "HOEMISSION" and data.hoe ~= true) or (upper == "WEEDMISSION" and data.weeder ~= true) then
        return nil
    end
    if (work == "HARVEST" or work == "MOW" or work == "SOW") and mission.fruitTypeIndex ~= nil and data.fruits ~= nil
        and data.fruits[mission.fruitTypeIndex] == nil then
        return nil
    end
    return work
end

function MHPage:getContractPlaces(farmId, jobTypeIndex, onlyNeeded)
    local workable, other = {}, {}
    if g_missionManager == nil then
        return workable
    end
    for _, mission in ipairs(g_missionManager:getMissionsByFarmId(farmId)) do
        if mission.farmId == farmId and mission:getIsInProgress() and mission.getField ~= nil and mission:getField() ~= nil then
            local field = mission:getField()
            local x, z = MHPage.getFieldPoint(field)
            if x == nil then
                x, z = mission:getWorldPosition()
            end
            local name = mission:getTitle()
            if field.getId ~= nil and field:getId() ~= nil then
                name = string.format("%s - %s %s", name, g_i18n:getText("ui_fieldNo"), tostring(field:getId()))
            end
            local work = self:getContractWork(mission)
            local percent = MHPage.formatPercent(mission.completion)
            local item = {name = name, icon = MHPage.ICON.CONTRACT, x = x, z = z, jobTypeIndex = jobTypeIndex,
                farmlands = {field.farmland ~= nil and field.farmland.id or nil}, percent = percent}
            if work ~= nil then
                item.info = string.format("%s - %s", MHFieldNeeds.getWorkText(work), percent)
                table.insert(workable, item)
            elseif not onlyNeeded then
                item.info = percent
                table.insert(other, item)
            end
        end
    end
    for _, item in ipairs(other) do
        table.insert(workable, item)
    end
    return workable
end

-- The stations the vehicle's Load and deliver / Deliver jobs accept: a scratch job of each
-- type gets the vehicle's state (applyCurrentState) and lists its valid stations.
function MHPage:getStationPlaces(vehicle, available)
    local items = {}
    local manager = MH.getJobTypeManager()
    local farmId = g_localPlayer ~= nil and g_localPlayer.farmId or vehicle:getOwnerFarmId()
    local seen = {}
    local function addStations(typeIndex, parameterName, ids, icon, loading)
        if typeIndex == nil or not available[typeIndex] then
            return
        end
        local job = manager:createJob(typeIndex)
        if job == nil then
            return
        end
        job:applyCurrentState(vehicle, g_currentMission, farmId, false)
        local parameter = job:getNamedParameter(parameterName)
        for _, id in ipairs(parameter ~= nil and parameter[ids] or {}) do
            local station = NetworkUtil.getObject(id)
            if station ~= nil and not seen[station] then
                seen[station] = true
                local x, z = MHPage.getStationPosition(station)
                table.insert(items, {name = station:getName(), info = "", icon = icon, x = x, z = z,
                    station = station, loading = loading})
            end
        end
    end
    addStations(AIJobType.LOAD_AND_DELIVER, "loadingStation", "loadingStationIds", MHPage.ICON.LOADING, true)
    addStations(AIJobType.LOAD_AND_DELIVER, "unloadingStation", "unloadingStationIds", MHPage.ICON.UNLOADING, false)
    addStations(AIJobType.DELIVER, "unloadingStation", "unloadingStationIds", MHPage.ICON.UNLOADING, false)
    table.sort(items, function(a, b)
        if a.loading ~= b.loading then
            return a.loading
        end
        return a.name < b.name
    end)
    return items
end

function MHPage.formatPercent(value)
    return string.format("%d %%", math.floor((value or 0) * 100 + 0.5))
end

-- A place pans the map to it and prefills the form: fields and contracts with field work
-- (or Go to) at the field, stations with the delivery job that accepts them.
function MHPage:onClickPlace(list, section, index)
    local place = self.places ~= nil and self.places[index] or nil
    if place == nil or not self:getIsShown() then
        return
    end
    if place.x ~= nil and place.z ~= nil then
        self.frame.ingameMap:setCenterToWorldPosition(place.x, place.z)
    end
    self:prefill(place)
end

-- SmoothList onDoubleClick (SmoothListElement:notifyDoubleClick, SDK gui/elements/
-- SmoothListElement.lua:1546-1550, 1598-1600): a field or contract with field work is filled in
-- and added to the queue at once, like Add to queue. Stations, Go to (no field work) and an
-- entry being edited keep the single-click behaviour.
function MHPage:onDoubleClickPlace(list, section, index)
    local place = self.places ~= nil and self.places[index] or nil
    if place == nil or not self:getIsShown() or self.editingId ~= nil or place.station ~= nil
        or AIJobType.FIELDWORK == nil or place.jobTypeIndex ~= AIJobType.FIELDWORK then
        return
    end
    self:prefill(place)
    self:submit(false)
end

function MHPage:getFormJobTypeIndex()
    local job = self.frame.currentJob
    return job ~= nil and MH.getJobTypeIndex(job) or nil
end

-- Switches the form to a job type, keeping the form when it already has that type.
function MHPage:selectJobType(typeIndex)
    local frame = self.frame
    if typeIndex == nil or not self.formPlaced then
        return false
    end
    if self:getFormJobTypeIndex() == typeIndex then
        return true
    end
    for i, index in ipairs(frame.currentJobTypes or {}) do
        if index == typeIndex then
            frame.jobTypeElement:setState(i)
            MHMapFrame.withPlanning(self.vehicle, self:getIsPlanning(self.vehicle), function()
                frame:setActiveJobTypeSelection(typeIndex)
            end)
            frame:refreshContextInput()
            return true
        end
    end
    return false
end

function MHPage.getParameterHasStation(parameter, ids, station)
    local id = NetworkUtil.getObjectId(station)
    for _, validId in ipairs(parameter[ids] or {}) do
        if validId == id then
            return true
        end
    end
    return false
end

function MHPage:prefill(place)
    local frame = self.frame
    local available = {}
    for _, jobType in ipairs(self.jobTypes or {}) do
        available[jobType.index] = true
    end
    local typeIndex = place.jobTypeIndex
    if place.station ~= nil then
        local current = self:getFormJobTypeIndex()
        if place.loading then
            typeIndex = AIJobType.LOAD_AND_DELIVER
        elseif current == AIJobType.DELIVER or current == AIJobType.LOAD_AND_DELIVER then
            typeIndex = current
        elseif available[AIJobType.LOAD_AND_DELIVER] then
            typeIndex = AIJobType.LOAD_AND_DELIVER
        else
            typeIndex = AIJobType.DELIVER
        end
    end
    if not self:selectJobType(typeIndex) or frame.currentJob == nil then
        return false
    end
    local job = frame.currentJob
    if place.station ~= nil then
        local name = place.loading and "loadingStation" or "unloadingStation"
        local ids = place.loading and "loadingStationIds" or "unloadingStationIds"
        local parameter = job:getNamedParameter(name)
        if parameter ~= nil and MHPage.getParameterHasStation(parameter, ids, place.station) then
            if place.loading then
                parameter:setLoadingStation(place.station)
            else
                parameter:setUnloadingStation(place.station)
            end
            job:onParameterValueChanged(parameter)
        end
    elseif place.x ~= nil and place.z ~= nil then
        local parameter = job:getNamedParameter("positionAngle") or job:getNamedParameter("position")
        if parameter ~= nil then
            parameter:setPosition(place.x, place.z)
        end
    end
    frame:updateParameterValueTexts()
    frame:validateParameters()
    return true
end

-- Queue rows: the job the worker drives now (from the vehicle, like the native worker
-- list), then the waiting entries. A finished job is gone from the vehicle and the queue
-- has already removed every entry it started, so done jobs disappear by themselves.
function MHPage:buildRows()
    local rows = {}
    local vehicle = self.vehicle
    if MH.getSupportsAI(vehicle) then
        local job = vehicle:getIsAIActive() and vehicle.getJob ~= nil and vehicle:getJob() or nil
        if job ~= nil then
            table.insert(rows, {current = true, title = job:getDescription(), text = MHPage.getProgressText(vehicle, job)})
        end
        for index, entry in ipairs(MH.getEntries(vehicle)) do
            table.insert(rows, {entry = entry, index = index, title = MH.getJobTitle(entry.job),
                text = MH.getJobTargets(entry.job)})
        end
    end
    return rows
end

-- Progress of a running job: the distance left to the drive target of its current task
-- (AITaskDriveTo x/z) and the completion of a contract on its field.
function MHPage.getProgressText(vehicle, job)
    local parts = {}
    local task = job.getTaskByIndex ~= nil and job:getTaskByIndex(job.currentTaskIndex) or nil
    if task ~= nil and task.x ~= nil and task.z ~= nil and vehicle.rootNode ~= nil then
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        local distance = MathUtil.vector2Length(task.x - x, task.z - z)
        table.insert(parts, string.format("%s: %s", g_i18n:getText("ui_distance"), g_i18n:formatDistance(distance, 0)))
    end
    local completion = MHPage.getContractCompletion(job)
    if completion ~= nil then
        table.insert(parts, string.format("%s: %s", g_i18n:getText("contract_progress"), MHPage.formatPercent(completion)))
    end
    if #parts == 0 and job.getHelperName ~= nil then
        table.insert(parts, job:getHelperName())
    end
    return table.concat(parts, "  ·  ")
end

-- Completion of the farm's contract on the field the job targets, if there is one.
function MHPage.getContractCompletion(job)
    local parameter = job.getNamedParameter ~= nil and job:getNamedParameter("positionAngle") or nil
    if parameter == nil or g_farmlandManager == nil or g_missionManager == nil then
        return nil
    end
    local x, z = parameter:getPosition()
    local farmland = x ~= nil and g_farmlandManager:getFarmlandAtWorldPosition(x, z) or nil
    if farmland == nil then
        return nil
    end
    for _, mission in ipairs(g_missionManager:getMissionsByFarmId(job.startedFarmId)) do
        if mission.farmId == job.startedFarmId and mission:getIsInProgress() and mission.getField ~= nil then
            local field = mission:getField()
            if field ~= nil and field.farmland == farmland then
                return mission.completion
            end
        end
    end
    return nil
end

function MHPage:reloadQueue()
    self.rows = self:buildRows()
    -- Keep the selection on the same entry when the queue changes.
    local selectedId = self.selectedEntryId
    local selected = nil
    for i, row in ipairs(self.rows) do
        if row.entry ~= nil and row.entry.id == selectedId then
            selected = i
        end
    end
    if self.editingId ~= nil then
        local editing = false
        for _, row in ipairs(self.rows) do
            editing = editing or (row.entry ~= nil and row.entry.id == self.editingId)
        end
        if not editing then
            -- The entry started or was removed; the form keeps its values as a new job.
            self.editingId = nil
        end
    end
    self.selectedRow = selected
    if selected == nil then
        self.selectedEntryId = nil
    end
    self.mhQueueList:reloadData()
    if selected ~= nil then
        self.mhQueueList:setSelectedItem(1, selected, true)
    end
    self.mhQueueEmpty:setVisible(#self.rows == 0)
end

-- SmoothList data source and delegate ------------------------------------------------------
-- Both lists have one section without a header.
function MHPage:getNumberOfSections(list)
    return 1
end

function MHPage:getTitleForSectionHeader(list, section)
    return nil
end

function MHPage:getNumberOfItemsInSection(list, section)
    if list == self.mhPlacesList then
        return #(self.places or {})
    end
    return #self.rows
end

function MHPage:populateCellForItemInSection(list, section, index, cell)
    if list == self.mhPlacesList then
        local place = self.places[index]
        cell:getAttribute("name"):setText(place.name)
        cell:getAttribute("info"):setText(place.info or "")
        cell:getAttribute("icon"):setImageSlice(nil, place.icon)
        return
    end
    local row = self.rows[index]
    local isCurrent = row.current == true
    cell:getAttribute("badgeIcon"):setVisible(isCurrent)
    cell:getAttribute("index"):setText(isCurrent and "" or tostring(row.index))
    cell:getAttribute("title"):setText(row.title or "")
    cell:getAttribute("text"):setText(row.text or "")
end

function MHPage:onListSelectionChanged(list, section, index)
    if list == self.mhQueueList then
        local row = self.rows[index]
        self.selectedRow = row ~= nil and index or nil
        self.selectedEntryId = row ~= nil and row.entry ~= nil and row.entry.id or nil
        self.selectedCurrent = row ~= nil and row.current == true
        self:refreshButtons()
    end
end

function MHPage:onClickQueueEntry(list, section, index)
    self:onListSelectionChanged(list, section, index)
end

-- Queue actions -----------------------------------------------------------------------------
function MHPage:getSelectedRow()
    return self.selectedRow ~= nil and self.rows[self.selectedRow] or nil
end

function MHPage:getSelectedEntry()
    local row = self:getSelectedRow()
    return row ~= nil and row.entry or nil
end

function MHPage:getCanChangeQueue()
    return self:getIsShown() and MHMapFrame.getCanPlanFor(self.vehicle)
end

function MHPage:moveSelected(up)
    local entry = self:getSelectedEntry()
    if entry ~= nil and self:getCanChangeQueue() then
        MH.requestMove(self.vehicle, entry.id, up)
    end
end

function MHPage:onClickMoveUp()
    self:moveSelected(true)
end

function MHPage:onClickMoveDown()
    self:moveSelected(false)
end

-- Loads the selected entry into the form; Add to queue then reads Save.
function MHPage:onClickEdit()
    local entry = self:getSelectedEntry()
    if entry == nil or not self:getCanChangeQueue() then
        return
    end
    if self:buildForm(MH.getJobTypeIndex(entry.job), entry.job) then
        self.editingId = entry.id
    end
    self:refresh()
end

-- Delete removes a waiting entry. On the running row it reads Cancel job and stops the
-- worker, with the same call as InGameMenuMapFrame:cancelJob; the queue then pauses as for
-- any stop by the player, and Resume continues it.
function MHPage:onClickRemove()
    local row = self:getSelectedRow()
    if row == nil or not self:getCanChangeQueue() then
        return
    end
    if row.current then
        local vehicle = self.vehicle
        if vehicle:getIsAIActive() and not g_currentMission.paused then
            vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
        end
        return
    end
    if row.entry.id == self.editingId then
        self.editingId = nil
    end
    MH.requestRemove(self.vehicle, row.entry.id)
end

function MHPage:onClickClear()
    if self:getCanChangeQueue() and #MH.getEntries(self.vehicle) > 0 then
        self.editingId = nil
        MH.requestClear(self.vehicle)
    end
end

-- Adding a job starts the queue by itself. Resume is for a queue with waiting jobs and no
-- worker: paused after a stop or an error, or loaded from the savegame.
function MHPage:getCanResume()
    local vehicle = self.vehicle
    if vehicle == nil or not MHMapFrame.getCanPlanFor(vehicle) or vehicle:getIsAIActive() then
        return false
    end
    local queue = MH.queues[vehicle]
    return #MH.getEntries(vehicle) > 0 and (queue == nil or not queue.running)
end

function MHPage:onClickResume()
    if self:getIsShown() and self:getCanResume() and not g_currentMission.paused then
        MH.requestStart(self.vehicle)
    end
end

-- Card, buttons and refresh -------------------------------------------------------------------
-- The player's own vehicle when it is not the one shown and can take jobs.
function MHPage:getOtherOwnVehicle()
    local mine = MHMapFrame.getControlledVehicle()
    if mine ~= nil and mine ~= self.vehicle and MHMapFrame.getCanPlanFor(mine) then
        return mine
    end
    return nil
end

-- Clicking the card goes back to the player's own vehicle; on that vehicle it moves the map
-- to it.
function MHPage:onClickVehicleCard()
    if not self:getIsShown() then
        return
    end
    local mine = self:getOtherOwnVehicle()
    if mine ~= nil then
        self:setVehicle(mine, true)
        return
    end
    local vehicle = self.vehicle
    if MH.getVehicleExists(vehicle) and vehicle.getMapHotspot ~= nil then
        local hotspot = vehicle:getMapHotspot()
        if hotspot ~= nil then
            self.frame.ingameMap:panToHotspot(hotspot)
        end
    end
end

function MHPage:refreshCard()
    local vehicle = self.vehicle
    local title, status, info = MH.text("mh_onFoot"), MH.text("mh_statusOnFoot"), ""
    local imageFilename = nil
    if vehicle ~= nil then
        title = vehicle:getName()
        imageFilename = vehicle.getImageFilename ~= nil and vehicle:getImageFilename() or nil
        local reason = self:getNoFormReason(vehicle)
        local queue = MH.queues[vehicle]
        local waiting = #MH.getEntries(vehicle)
        if reason ~= nil then
            status = reason
        elseif queue ~= nil and queue.pause ~= MH.PAUSE.NONE then
            status = string.format(MH.text("mh_statusPaused"), MH.getPauseReason(queue))
        elseif vehicle:getIsAIActive() or (queue ~= nil and queue.running) then
            status = MH.text("mh_statusWorking")
        else
            status = MH.text("mh_statusIdle")
        end
        if waiting > 0 then
            info = string.format(MH.text("mh_statusWaiting"), waiting)
        end
    end
    if self:getOtherOwnVehicle() ~= nil then
        info = info ~= "" and string.format("%s - %s", info, MH.text("mh_backToMine")) or MH.text("mh_backToMine")
    end
    self.mhVehicleTitle:setText(title)
    self.mhVehicleStatus:setText(status)
    self.mhVehicleInfo:setText(info)
    local hasImage = imageFilename ~= nil and imageFilename ~= ""
    self.mhVehicleImage:setVisible(hasImage)
    self.mhVehicleIcon:setVisible(not hasImage)
    if hasImage then
        self.mhVehicleImage:setImageFilename(imageFilename)
        self.mhVehicleImage:setImageUVs(nil, unpack(Overlay.DEFAULT_UVS))
    end
end

function MHPage:refreshButtons()
    if self.root == nil then
        return
    end
    self.buttonSignature = self:getButtonSignature()
    local vehicle = self.vehicle
    local canPlan = vehicle ~= nil and MHMapFrame.getCanPlanFor(vehicle)
    local mission = g_currentMission
    local paused = mission ~= nil and mission.paused
    local entries = MH.getEntries(vehicle)
    local hasForm = canPlan and self.formPlaced and self.frame.currentJob ~= nil

    local editing = self.editingId ~= nil
    self.mhAddText:setText(editing and g_i18n:getText("button_save") or MH.text("mh_addToQueue"))
    self.mhNextText:setText(editing and g_i18n:getText("button_cancel") or MH.text("mh_insertNext"))
    self.mhAddButton:setDisabled(not hasForm or paused)
    self.mhNextButton:setDisabled(not editing and (not hasForm or paused))

    local canResume = self:getCanResume()
    self.mhResumeContainer:setVisible(canResume)
    self.mhResumeButton:setDisabled(not canResume or paused)
    self.mhClearButton:setDisabled(not canPlan or #entries == 0)

    local row = self:getSelectedRow()
    local entry = row ~= nil and row.entry or nil
    local index = entry ~= nil and self:getEntryIndex(entry) or nil
    local isCurrent = row ~= nil and row.current == true
    self.mhUpButton:setDisabled(not canPlan or index == nil or index <= 1)
    self.mhDownButton:setDisabled(not canPlan or index == nil or index >= #entries)
    self.mhEditButton:setDisabled(not canPlan or entry == nil)
    self.mhRemoveText:setText(isCurrent and g_i18n:getText("button_cancelJob") or g_i18n:getText("button_delete"))
    self.mhRemoveButton:setDisabled(not canPlan or row == nil or (isCurrent and paused))
end

function MHPage:getEntryIndex(entry)
    for index, candidate in ipairs(MH.getEntries(self.vehicle)) do
        if candidate == entry then
            return index
        end
    end
    return nil
end

function MHPage:refresh()
    if self.root == nil then
        return
    end
    self:refreshCard()
    self:reloadQueue()
    self:refreshButtons()
end

-- Queue state changed (MapHelper listener, after every server state).
function MHPage:onQueueChanged(vehicle)
    if self:getIsShown() and (vehicle == nil or vehicle == self.vehicle) then
        self:refresh()
    end
end

-- Row layout of the queue list: which rows exist, not their texts.
function MHPage.getRowsSignature(rows)
    local parts = {}
    for _, row in ipairs(rows) do
        table.insert(parts, row.current and "current" or tostring(row.entry.id))
    end
    return table.concat(parts, ",")
end

-- Every second, like the native worker list (InGameMenuMapFrame:update): progress texts
-- change in place; a job that started or finished rebuilds the list. The places list is
-- read again every PLACES_INTERVAL, since field states change slowly.
function MHPage:update(dt)
    self.time = self.time + dt
    self.refreshTimer = self.refreshTimer + dt
    self.placesTimer = (self.placesTimer or 0) + dt
    if self.refreshTimer < MHPage.REFRESH_INTERVAL then
        return
    end
    self.refreshTimer = 0
    if self.vehicle ~= nil and not MH.getVehicleExists(self.vehicle) then
        self:setVehicle(MHMapFrame.getControlledVehicle(), false)
        return
    end
    if self.placesTimer >= MHPage.PLACES_INTERVAL then
        -- Implements may have been attached, detached or refilled in the meantime.
        self:refreshJobTypes()
        self:updateFilterOptions(true)
        self:reloadPlaces()
    end
    local rows = self:buildRows()
    if MHPage.getRowsSignature(rows) ~= MHPage.getRowsSignature(self.rows) then
        self:refresh()
        return
    end
    self.rows = rows
    for index, row in ipairs(rows) do
        local cell = self.mhQueueList:getElementAtSectionIndex(1, index)
        if cell ~= nil then
            cell:getAttribute("title"):setText(row.title or "")
            cell:getAttribute("text"):setText(row.text or "")
        end
    end
    self:refreshCard()
    -- Pause and permissions can change without a queue event; refresh the buttons when
    -- anything they depend on changed.
    local signature = self:getButtonSignature()
    if signature ~= self.buttonSignature then
        self:refreshButtons()
    end
end

-- Everything refreshButtons reads, as a short string.
function MHPage:getButtonSignature()
    local vehicle = self.vehicle
    local mission = g_currentMission
    local canPlan = vehicle ~= nil and MHMapFrame.getCanPlanFor(vehicle)
    local queue = MH.queues[vehicle]
    return table.concat({tostring(canPlan), tostring(mission ~= nil and mission.paused),
        tostring(canPlan and vehicle:getIsAIActive()), tostring(queue ~= nil and queue.running),
        tostring(#MH.getEntries(vehicle)), tostring(self.editingId), tostring(self.selectedEntryId),
        tostring(self.selectedCurrent), tostring(self.formPlaced and self.frame.currentJob ~= nil)}, "|")
end
