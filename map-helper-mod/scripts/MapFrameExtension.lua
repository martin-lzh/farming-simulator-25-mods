-- Map page integration: the Map Helper page of the map overview sidebar (a new state of
-- mapOverviewSelector, next to the filter pages and Active Workers), the Map Helper entry in
-- the map page's button bar that switches to it, the page keys and the global hotkey. The
-- page content lives in MHPage (MapHelperPage.lua).
MHMapFrame = {}
local MF = MHMapFrame
local MF_mt = {__index = MF}

MF.BAR_BUTTON_XML = "gui/MenuBarButton.xml"
MF.INPUT_ACTION = "MENU_EXTRA_1"
-- Frames this Mod added controls to; the in-game menu keeps its frames between missions.
MF.injected = {}

-- Native profiles and elements are loaded the way the bundled Precision Farming
-- extension adds its map page windows (PrecisionFarmingGUI.loadAdditionalGUI).
-- Profiles are global and outlive the mission: load them once per game session.
function MF.loadElements(filename, parent, target, profileName)
    local xmlFile = loadXMLFile("mapHelperGui", MapHelper.MOD_DIRECTORY .. filename)
    if xmlFile == nil or xmlFile == 0 then
        MapHelper.warnOnce("gui_" .. filename, "Could not open %s; the map page controls are not available", filename)
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

    if frame.filterBox ~= nil and MHPage ~= nil then
        ext.page = MHPage.new(frame, ext)
        if not ext.page:load() then
            ext.page = nil
        end
    end
    if ext.page ~= nil then
        MF.injectBarButton(ext)
    end

    -- The selector's onClick was bound to the original function when the map page was
    -- loaded. Call through the frame instead, like Precision Farming does, so that the
    -- hooked InGameMenuMapFrame:onClickMapOverviewSelector runs. Restored on removal.
    local selector = frame.mapOverviewSelector
    if ext.page ~= nil and selector ~= nil then
        ext.selectorCallback = selector.onClickCallback
        selector.onClickCallback = function(_, state)
            frame:onClickMapOverviewSelector(state)
        end
        -- The overview may already be set up when the Mod's frame code runs late.
        if frame.isMapOverviewInitialized then
            MF.addSelectorPage(frame)
        end
    end
end

function MF.getExtension(frame)
    return frame ~= nil and frame.mapHelper or nil
end

-- Controls are removed on mission delete; this also covers any callback that is still
-- reachable after that, for example while the next mission loads without the Mod.
function MF:getIsActive()
    return self.frame ~= nil and self.frame.mapHelper == self and MapHelper.missionActive
        and g_modIsLoaded ~= nil and g_modIsLoaded[MapHelper.MOD_NAME] == true
end

function MF.getActiveExtension(frame)
    local ext = MF.getExtension(frame)
    if ext ~= nil and getmetatable(ext) == MF_mt and ext:getIsActive() then
        return ext
    end
    return nil
end

-- Selector page -------------------------------------------------------------------
-- Appended to InGameMenuMapFrame:setupMapOverview, which rebuilds mapSelectorTexts once per
-- mission when the map page opens. Same steps as Precision Farming's page: one more text
-- and one more dot; the page index is wherever the text ends up.
function MF.addSelectorPage(frame)
    local ext = MF.getActiveExtension(frame)
    if ext == nil or ext.page == nil or frame.mapSelectorTexts == nil then
        return
    end
    local texts = frame.mapSelectorTexts
    local title = MapHelper.text("mh_toggle")
    local index = nil
    for i, text in ipairs(texts) do
        if text == title and i == ext.pageIndex then
            index = i
        end
    end
    if index == nil then
        table.insert(texts, title)
        index = #texts
        frame.mapOverviewSelector:setTexts(texts)
    end
    ext.pageIndex = index
    ext.pageTitle = title
    -- Keep the native per-state tables consistent for the new state, like Precision Farming.
    if frame.dataTables ~= nil then
        frame.dataTables[index] = {}
    end
    if frame.filterStates ~= nil then
        frame.filterStates[index] = {}
    end
    if frame.numSelectedFilters ~= nil then
        frame.numSelectedFilters[index] = 0
    end
    local dotBox = frame.subCategoryDotBox
    if ext.dot == nil and dotBox ~= nil and dotBox.elements[1] ~= nil then
        ext.dot = dotBox.elements[1]:clone(dotBox)
        dotBox:invalidateLayout()
    end
    if ext.dot ~= nil then
        local selector = frame.mapOverviewSelector
        ext.dot.getIsSelected = function()
            return ext.pageIndex ~= nil and selector:getState() == ext.pageIndex
        end
    end
end

function MF.getIsPageState(frame, state)
    local ext = MF.getActiveExtension(frame)
    return ext ~= nil and ext.page ~= nil and ext.pageIndex ~= nil and state == ext.pageIndex
end

-- Appended to InGameMenuMapFrame:onClickMapOverviewSelector. The native part has already
-- hidden its own containers for an unknown state.
function MF.onSelectorChanged(frame, state)
    local ext = MF.getActiveExtension(frame)
    if ext == nil or ext.page == nil then
        return
    end
    if MF.getIsPageState(frame, state) then
        ext.page:show()
    else
        ext.page:hide()
    end
    MF.setBarButtonDirty(frame)
end

function MF.openPage(frame)
    local ext = MF.getActiveExtension(frame)
    local selector = frame ~= nil and frame.mapOverviewSelector or nil
    if ext == nil or ext.pageIndex == nil or selector == nil or selector:getIsDisabled()
        or frame.mode ~= InGameMenuMapFrame.AI_MODE_OVERVIEW or frame:getIsPicking() then
        return false
    end
    if selector:getState() ~= ext.pageIndex then
        selector:setState(ext.pageIndex, true)
    end
    return true
end

-- Global hotkey: open the in-game menu on the map page, like the native map key
-- (PlayerInputComponent:onInputToggleMap), then select the page like
-- InGameMenu:openFarmlandsScreen selects the farmland state.
function MF.openFromHotkey()
    local menu = g_inGameMenu
    local mission = g_currentMission
    if menu == nil or menu.pageMapOverview == nil or mission == nil or mission.isSynchronizingWithPlayers then
        return false
    end
    local component = MapHelper.inputComponent
    if component ~= nil and component.locked then
        return false
    end
    if g_guidedTourManager ~= nil and g_guidedTourManager:getIsTourRunning() then
        return false
    end
    menu:openMapOverview()
    return MF.openPage(menu.pageMapOverview)
end

-- Button bar -------------------------------------------------------------------------
-- The map page has its own button bar at the bottom of the screen (buttonBox: Back, Next,
-- Previous, the map glyphs and Select). InGameMenu:updateButtonsPanel hides the menu's own
-- buttonsPanel for this page (hasFullScreenMap), so menu button info does not show here;
-- the entry is a button in buttonBox, right after Previous. The box lays out right to left
-- and skips hidden buttons (BoxLayoutElement).
function MF.injectBarButton(ext)
    local frame = ext.frame
    local box = frame.buttonBox
    if box == nil then
        MapHelper.warnOnce("noButtonBox", "Map page button bar not found; open Map Helper with its key or the sidebar instead")
        return
    end
    local button = MF.loadElements(MF.BAR_BUTTON_XML, box, ext, "mh_barButton")
    if button == nil then
        return
    end
    button:setText(MapHelper.text("mh_toggle"))
    local previous = frame.buttonPrev
    if previous ~= nil and previous.parent == box then
        for i, element in ipairs(box.elements) do
            if element == button then
                table.remove(box.elements, i)
                break
            end
        end
        for i, element in ipairs(box.elements) do
            if element == previous then
                table.insert(box.elements, i + 1, button)
                break
            end
        end
    end
    ext.barButton = button
    box:invalidateLayout()
end

-- The entry is shown where it can switch to the page: not on the page itself (its key adds
-- jobs there and the page shows it on Insert as next), not in the native job menu, which
-- locks the selector, and not while another visible button shows the same key, such as
-- Precision Farming's Help on its soil map tab; that one gets the key then.
function MF.getShowsBarButton(ext)
    local frame = ext.frame
    local onPage = ext.page ~= nil and ext.page:getIsShown()
    local inJobMenu = frame.mode == InGameMenuMapFrame.AI_MODE_CREATE
    return ext.page ~= nil and not onPage and not inJobMenu and not MF.getHasOtherKeyButton(frame.elements, ext)
end

function MF.updateBarButton(ext)
    local button = ext.barButton
    if button == nil then
        return
    end
    ext.barButtonDirty = false
    local visible = MF.getShowsBarButton(ext)
    if button.visible ~= visible then
        button:setVisible(visible)
        if button.parent ~= nil then
            button.parent:invalidateLayout()
        end
    end
end

-- Refreshes the entry now and once more on the next frame (MF.update), after other Mods'
-- hooks on the same native function have shown or hidden their own buttons.
function MF.setBarButtonDirty(frame)
    local ext = MF.getActiveExtension(frame)
    if ext ~= nil and ext.barButton ~= nil then
        MF.updateBarButton(ext)
        ext.barButtonDirty = true
    end
end

-- Appended to InGameMenuMapFrame:setJobMenuVisible (native job menu opened or closed).
function MF.onJobMenuVisible(frame, isVisible)
    MF.setBarButtonDirty(frame)
end

-- Keys --------------------------------------------------------------------------------
-- Appended to InGameMenuMapFrame:registerInput, which runs inside the map page's own
-- input context (MENU_MAP_OVERVIEW) every time the page opens.
function MF.registerInput(frame)
    local ext = MF.getActiveExtension(frame)
    if ext == nil or g_inputBinding == nil then
        return
    end
    if ext.page ~= nil then
        ext.page.name = frame.name
    end
    g_inputBinding:removeActionEventsByTarget(ext)
    -- MENU_EXTRA_1, which the PC map page does not use: switches to the page, and on the
    -- page inserts the job as the next entry. Its glyph shows a single key and it has a
    -- controller default.
    local action = InputAction[MF.INPUT_ACTION]
    if action ~= nil then
        local _, eventId = g_inputBinding:registerActionEvent(action, ext, MF.onKeyAction, false, true, false, true)
        if eventId ~= nil and eventId ~= "" then
            g_inputBinding:setActionEventTextVisibility(eventId, false)
        end
    end
    MF.setBarButtonDirty(frame)
end

-- Another visible button on the map page that shows the same key, such as the Help button
-- Precision Farming adds to its soil map tab. ScreenElement.callButtonsWithAction triggers
-- that one, so the key leaves it alone. This Mod's own buttons are not triggerable that way.
function MF.getHasOtherKeyButton(elements, ext)
    for _, element in ipairs(elements or {}) do
        if element ~= ext.barButton and (ext.page == nil or element ~= ext.page.root) then
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

function MF:onKeyAction()
    if not self:getIsActive() then
        return
    end
    if self.page ~= nil and self.page:getIsShown() then
        self.page:onClickInsertNext()
    elseif not MF.getHasOtherKeyButton(self.frame.elements, self) then
        MF.openPage(self.frame)
    end
end

-- Appended to InGameMenuMapFrame:onMenuMapAction1 (the native Start job key). On the page
-- the native Start job button is hidden, so the native handler does nothing there.
function MF.onMenuMapAction1(frame)
    local ext = MF.getActiveExtension(frame)
    if ext ~= nil and ext.page ~= nil and ext.page:getIsShown() then
        ext.page:onClickAdd()
    end
end

-- Mouse click on the bar entry; the key goes through MF:onKeyAction. Button callbacks return
-- nothing, so ButtonElement:sendAction treats the click as used.
function MF:onClickBarButton()
    if self:getIsActive() then
        MF.openPage(self.frame)
    end
end

-- Other native hooks ----------------------------------------------------------------
-- Appended to InGameMenuMapFrame:setMapSelectionItem: a vehicle selected on the map while
-- the page is shown becomes the page's vehicle.
function MF.onMapSelectionChanged(frame, hotspot)
    local ext = MF.getActiveExtension(frame)
    if ext ~= nil and ext.page ~= nil and ext.page:getIsShown() then
        ext.page:onMapSelectionChanged(hotspot)
    end
end

-- Appended to InGameMenuMapFrame:setActiveJobTypeSelection (form built or job type changed).
function MF.onJobTypeSelected(frame)
    local ext = MF.getActiveExtension(frame)
    if ext ~= nil and ext.page ~= nil and ext.page:getIsShown() then
        ext.page:onFormBuilt()
    end
end

-- Appended to InGameMenuMapFrame:onFrameClose: give the native form back while the menu is
-- closed; onFrameOpen selects the page again through onClickMapOverviewSelector.
function MF.onFrameClose(frame)
    local ext = MF.getActiveExtension(frame)
    if ext ~= nil and ext.page ~= nil then
        ext.page:hide()
    end
end

-- Appended to InGameMenuMapFrame:update (runs while the map page is open).
function MF.update(frame, dt)
    local ext = MF.getActiveExtension(frame)
    if ext == nil then
        return
    end
    if ext.barButtonDirty then
        MF.updateBarButton(ext)
    end
    if ext.page ~= nil and ext.page:getIsShown() then
        ext.page:update(dt)
    end
end

-- Teardown ------------------------------------------------------------------------------
-- Removes the page, the button bar entry, the extra selector state and the key events from
-- one frame and gives the native job form back.
function MF.remove(frame)
    local ext = frame.mapHelper
    frame.mapHelper = nil
    if ext == nil then
        return
    end
    if g_inputBinding ~= nil then
        g_inputBinding:removeActionEventsByTarget(ext)
    end
    if ext.page ~= nil and ext.page.release ~= nil then
        ext.page:release()
    end
    local selector = frame.mapOverviewSelector
    if ext.selectorCallback ~= nil and selector ~= nil then
        selector.onClickCallback = ext.selectorCallback
    end
    if ext.pageIndex ~= nil and selector ~= nil then
        -- Before the text goes: MultiTextOption:setTexts clamps the state to the new count.
        local onPage = selector.getState ~= nil and selector:getState() == ext.pageIndex
        local texts = frame.mapSelectorTexts
        if texts ~= nil and texts[ext.pageIndex] == ext.pageTitle then
            table.remove(texts, ext.pageIndex)
            selector:setTexts(texts)
        end
        if frame.dataTables ~= nil then
            frame.dataTables[ext.pageIndex] = nil
        end
        if frame.filterStates ~= nil then
            frame.filterStates[ext.pageIndex] = nil
        end
        if frame.numSelectedFilters ~= nil then
            frame.numSelectedFilters[ext.pageIndex] = nil
        end
        if onPage then
            selector:setState(1)
        end
    end
    if ext.dot ~= nil then
        local dotBox = ext.dot.parent
        ext.dot:delete()
        if dotBox ~= nil then
            dotBox:invalidateLayout()
        end
        ext.dot = nil
    end
    if ext.barButton ~= nil then
        local box = ext.barButton.parent
        ext.barButton:delete()
        ext.barButton = nil
        if box ~= nil then
            box:invalidateLayout()
        end
    end
    ext.page = nil
    ext.frame = nil
end

-- Mission teardown: nothing of this Mod stays on the shared map frame.
function MF.removeAll()
    for _, frame in ipairs(MF.injected) do
        MF.remove(frame)
    end
    MF.injected = {}
    MF.restorePlanning()
end

-- Shared helpers ------------------------------------------------------------------------
function MF.getControlledVehicle()
    if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil then
        return nil
    end
    return g_localPlayer:getCurrentVehicle()
end

function MF.getHasAccess(vehicle)
    local accessHandler = g_currentMission.accessHandler
    return accessHandler == nil or accessHandler:canPlayerAccess(vehicle)
end

-- Vehicles the local player may plan for: AI-capable, accessible, own farm, hireAssistant.
function MF.getCanPlanFor(vehicle)
    local MH = MapHelper
    return MH.features.queue and MH.getSupportsAI(vehicle) and MF.getHasAccess(vehicle) and MH.getCanManage(vehicle, nil)
end

-- The native job types only offer themselves for a vehicle without a worker
-- (AIJobVehicle:getCanStartAIVehicle checks getIsAIActive). To plan entries for a vehicle
-- that is working, the job form is built while the vehicle reads as idle: an instance field
-- shadows the vehicle's function for the duration of the call. Scripts catch no errors
-- (ModHub TestRunner), so if the call raises, MapHelper:update removes the shadow on the
-- next frame through MF.restorePlanning.
function MF.returnFalse()
    return false
end

-- Field work also asks AIFieldWorker:getCanStartFieldWork, which is false while the field
-- worker runs (spec.isActive, decompiled vehicles/specializations/AIFieldWorker.lua:320-327).
-- Without its shadow, jobs planned while the vehicle worked a field fell back to Go to and
-- only drove there (maintainer's report, 2026-10-25). The shadow answers like an idle worker.
function MF.getCanStartFieldWorkIdle(vehicle)
    local spec = vehicle.spec_aiFieldWorker
    return spec ~= nil and spec.aiImplementList ~= nil and #spec.aiImplementList > 0
end

function MF.withPlanning(vehicle, planning, func)
    if not planning then
        return func()
    end
    MF.restorePlanning()
    MF.planningShadow = {vehicle = vehicle, previous = rawget(vehicle, "getIsAIActive"),
        previousCanStart = rawget(vehicle, "getCanStartFieldWork"), shadowsCanStart = vehicle.spec_aiFieldWorker ~= nil}
    vehicle.getIsAIActive = MF.returnFalse
    if MF.planningShadow.shadowsCanStart then
        vehicle.getCanStartFieldWork = MF.getCanStartFieldWorkIdle
    end
    local result = func()
    MF.restorePlanning()
    return result
end

function MF.restorePlanning()
    local shadow = MF.planningShadow
    if shadow ~= nil then
        MF.planningShadow = nil
        shadow.vehicle.getIsAIActive = shadow.previous
        if shadow.shadowsCanStart then
            shadow.vehicle.getCanStartFieldWork = shadow.previousCanStart
        end
    end
end
