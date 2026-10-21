-- The Map Helper drawer. A small dialog without backdrop that drops down from the
-- Map Helper button, so the map stays visible. Built like the template's
-- product dialog: native MessageDialog, BoxLayout, ScrollingLayout and Buttons.
MHDrawerDialog = {}
local MHDrawerDialog_mt = Class(MHDrawerDialog, MessageDialog)
MHDrawerDialog.NAME = g_currentModName .. "_MapHelperDrawer"
MHDrawerDialog.XML = g_currentModDirectory .. "gui/DrawerDialog.xml"
MHDrawerDialog.REFRESH_INTERVAL = 250

function MHDrawerDialog.new()
    local self = MessageDialog.new(nil, MHDrawerDialog_mt)
    self.rows = {}
    self.signature = nil
    self.refreshTimer = 0
    return self
end

-- GUI controllers survive map changes; only the current frame reference changes.
function MHDrawerDialog.getInstance()
    local gui = g_gui.guis[MHDrawerDialog.NAME]
    if gui == nil then
        local previousGui = FocusManager.currentGui
        gui = g_gui:loadGui(MHDrawerDialog.XML, MHDrawerDialog.NAME, MHDrawerDialog.new())
        if previousGui ~= nil then
            FocusManager:setGui(previousGui)
        end
    end
    return gui ~= nil and gui.target or nil
end

-- Mission teardown: close the drawer and unload it like InGameMenu.createFromExistingGui
-- unloads a GUI (delete the root element, then the controller), so no later mission keeps
-- a controller that points at this mission's frame.
function MHDrawerDialog.release()
    local gui = g_gui.guis[MHDrawerDialog.NAME]
    if gui == nil then
        return
    end
    if gui.target.isOpen then
        g_gui:closeDialogByName(MHDrawerDialog.NAME)
    end
    gui.target.frame = nil
    gui:delete()
    gui.target:delete()
    g_gui.guis[MHDrawerDialog.NAME] = nil
    -- Gui:loadGui also registered the controller by name and by class (Gui:addScreen).
    local class = gui.target.class ~= nil and gui.target:class() or nil
    if g_gui.nameScreenTypes ~= nil then
        g_gui.nameScreenTypes[MHDrawerDialog.NAME] = nil
    end
    if class ~= nil and g_gui.screens ~= nil and g_gui.screens[class] == gui then
        g_gui.screens[class] = nil
        if g_gui.screenControllers ~= nil then
            g_gui.screenControllers[class] = nil
        end
    end
end

function MHDrawerDialog.show(frame)
    local self = MHDrawerDialog.getInstance()
    if self == nil or self.isOpen then
        return false
    end
    self.frame = frame
    g_gui:showDialog(MHDrawerDialog.NAME)
    return true
end

function MHDrawerDialog:onCreate()
    MHDrawerDialog:superClass().onCreate(self)
    -- An information dialog: query sound instead of the warning sound.
    self:setDialogType(DialogElement.TYPE_INFO)
end

function MHDrawerDialog:onGuiSetupFinished()
    MHDrawerDialog:superClass().onGuiSetupFinished(self)
    self.rowTemplate:unlinkElement()
    FocusManager:removeElement(self.rowTemplate)
    self.actionButtons = {self.centerButton, self.createButton, self.startStopButton, self.goToButton, self.clearButton}
end

-- Drawer layout from top to bottom, in pixels. The drawer is only as tall as what it shows.
MHDrawerDialog.LAYOUT = {padding = 16, title = 34, gap = 12, action = 37, section = 28, row = 34,
    maxRows = 6, empty = 40, buttons = 58, toggleGap = 8}
MHDrawerDialog.SLIDE_TIME = 160

-- Places each part below the previous one and fits the drawer height to them.
function MHDrawerDialog:layout(state)
    local L = MHDrawerDialog.LAYOUT
    local px = g_pixelSizeScaledY
    local onFoot = state.vehicle == nil
    local y = L.padding
    self.titleText:setPosition(nil, -y * px)
    y = y + L.title
    if (state.status or "") ~= "" then
        self.statusText:setPosition(nil, -y * px)
        y = y + math.ceil(self.statusText:getTextHeight() / px) + L.gap
    end
    local numActions = 0
    for _, button in ipairs(self.actionButtons) do
        if button:getIsVisible() then
            numActions = numActions + 1
        end
    end
    self.actionBox:setPosition(nil, -y * px)
    self.actionBox:setSize(nil, numActions * L.action * px)
    y = y + numActions * L.action
    if not onFoot then
        y = y + L.gap
        self.queueTitle:setPosition(nil, -y * px)
        y = y + L.section
        local numRows = math.min(#state.entries, L.maxRows)
        self.queueRows:setPosition(nil, -y * px)
        self.queueRows:setSize(nil, math.max(numRows, 1) * L.row * px)
        self.queueEmptyText:setPosition(nil, -y * px)
        y = y + (numRows > 0 and numRows * L.row or L.empty)
    end
    self.drawerPanel:setSize(nil, (y + L.buttons) * px)
    self:place()
end

-- Opens on the right, under the Map Helper button and aligned with its right edge; while
-- sliding in, the drawer is shifted right by the remaining slide distance.
function MHDrawerDialog:place()
    local ext = self.frame ~= nil and self.frame.mapHelper or nil
    local toggle = ext ~= nil and ext.toggle or nil
    local panel = self.drawerPanel
    if toggle == nil or toggle.absSize == nil or panel.absSize == nil then
        return
    end
    local progress = 1 - (1 - math.min(self.slideTime / MHDrawerDialog.SLIDE_TIME, 1)) ^ 3
    local right = toggle.absPosition[1] + toggle.absSize[1] + (1 - progress) * panel.absSize[1]
    local top = toggle.absPosition[2] - MHDrawerDialog.LAYOUT.toggleGap * g_pixelSizeScaledY
    local dx = right - (panel.absPosition[1] + panel.absSize[1])
    local dy = top - (panel.absPosition[2] + panel.absSize[2])
    panel:setPosition(panel.position[1] + dx, panel.position[2] + dy)
end

function MHDrawerDialog:onOpen()
    MHDrawerDialog:superClass().onOpen(self)
    self.inputDelay = self.time + 250
    self.signature = nil
    self.refreshTimer = 0
    self.slideTime = 0
    self.centerButton:setText(MapHelper.text("mh_centerOnMe"))
    self.clearButton:setText(MapHelper.text("mh_clearQueue"))
    self.queueTitle:setText(MapHelper.text("mh_queueTitle"))
    self.queueEmptyText:setText(MapHelper.text("mh_queueEmpty"))
    MapHelper.addListener(MHDrawerDialog.onQueueChanged, self)
    self:refresh(true)
end

function MHDrawerDialog:onClose()
    MapHelper.removeListener(self)
    self:deleteRows()
    self.frame = nil
    MHDrawerDialog:superClass().onClose(self)
end

function MHDrawerDialog:onQueueChanged()
    if self.isOpen then
        self:refresh(false)
    end
end

function MHDrawerDialog:update(dt)
    MHDrawerDialog:superClass().update(self, dt)
    if self.isOpen and self.slideTime < MHDrawerDialog.SLIDE_TIME then
        self.slideTime = self.slideTime + dt
        self:place()
    end
    if self.isOpen then
        self.refreshTimer = self.refreshTimer + dt
        if self.refreshTimer >= MHDrawerDialog.REFRESH_INTERVAL then
            self.refreshTimer = 0
            self:refresh(false)
        end
    end
end

function MHDrawerDialog:deleteRows()
    for _, row in ipairs(self.rows) do
        row.element:delete()
    end
    self.rows = {}
end

function MHDrawerDialog.getSignature(state)
    local parts = {state.title or "", state.status or "", state.startStop or "", tostring(state.planning),
        tostring(state.canCreate), tostring(state.canGoTo), tostring(state.canStartStop),
        tostring(state.canClear), tostring(state.canRemove)}
    for _, entry in ipairs(state.entries) do
        table.insert(parts, entry.id .. "=" .. entry.label)
    end
    return table.concat(parts, "|")
end

-- Rebuild only when something changed, so focus stays where the player left it.
function MHDrawerDialog:refresh(force)
    if self.frame == nil then
        return
    end
    local state = MHMapFrame.getDrawerState(self.frame)
    local signature = MHDrawerDialog.getSignature(state)
    if not force and signature == self.signature then
        return
    end
    self.signature = signature
    self.state = state
    self.titleText:setText(state.title or "")
    self.statusText:setText(state.status or "")
    local startStopText = g_i18n:getText("button_startJob")
    if state.startStop == "cancel" then
        startStopText = g_i18n:getText("button_cancelJob")
    elseif state.startStop == "queue" then
        startStopText = MapHelper.text("mh_startQueue")
    end
    self.startStopButton:setText(startStopText)
    -- While the vehicle works, the job menu adds to the queue instead of starting.
    self.createButton:setText(state.planning and MapHelper.text("mh_addToQueue") or g_i18n:getText("button_createJob"))
    local onFoot = state.vehicle == nil
    self.createButton:setVisible(not onFoot)
    self.startStopButton:setVisible(not onFoot)
    self.goToButton:setVisible(not onFoot)
    self.clearButton:setVisible(not onFoot)
    self.createButton:setDisabled(not state.canCreate)
    self.startStopButton:setDisabled(not state.canStartStop)
    self.goToButton:setDisabled(not state.canGoTo)
    self.clearButton:setDisabled(not state.canClear)
    self.actionBox:invalidateLayout()

    local focused = FocusManager:getFocusedElement()
    local focusedEntryId = nil
    for _, row in ipairs(self.rows) do
        if row.button == focused then
            focusedEntryId = row.id
        end
    end
    self:deleteRows()
    self.queueTitle:setVisible(not onFoot)
    self.queueEmptyText:setVisible(not onFoot and #state.entries == 0)
    self.queueRows:setVisible(not onFoot)
    self:layout(state)
    for index, entry in ipairs(state.entries) do
        local element = self.rowTemplate:clone(self.queueRows)
        -- Clones keep the template width; the clipping viewport may be narrower.
        element:setSize(self.queueRows.absSize[1], nil)
        element:getDescendantByName("label"):setText(string.format("%d. %s", index, entry.label))
        local button = element:getDescendantByName("remove")
        local entryId = entry.id
        button.onClickCallback = function()
            self:onClickRemove(entryId)
        end
        button:setDisabled(not state.canRemove)
        table.insert(self.rows, {element = element, button = button, id = entryId})
    end
    self.queueRows:invalidateLayout()
    self:linkFocus(focused, focusedEntryId)
end

function MHDrawerDialog:linkFocus(previous, previousEntryId)
    local order = {}
    for _, button in ipairs(self.actionButtons) do
        if button:getIsVisible() and not button:getIsDisabled() then
            table.insert(order, button)
        end
    end
    local target = nil
    for _, row in ipairs(self.rows) do
        if not row.button:getIsDisabled() then
            table.insert(order, row.button)
            if row.id == previousEntryId then
                target = row.button
            end
        end
    end
    for index, element in ipairs(order) do
        FocusManager:linkElements(element, FocusManager.TOP, order[index - 1] or order[#order])
        FocusManager:linkElements(element, FocusManager.BOTTOM, order[index + 1] or order[1])
        if element == previous then
            target = target or element
        end
    end
    target = target or order[1]
    if target ~= nil then
        FocusManager:setFocus(target)
    end
end

function MHDrawerDialog:getCanAct()
    return self.isOpen and self.frame ~= nil and self.inputDelay < self.time
end

-- Actions that need the map close the drawer first, like the template dialog.
function MHDrawerDialog:closeAndRun(action)
    local frame = self.frame
    self:close()
    if frame ~= nil then
        action(frame)
    end
end

function MHDrawerDialog:onClickCenter()
    if self:getCanAct() then
        self:closeAndRun(MHMapFrame.centerOnMe)
    end
    return false
end

function MHDrawerDialog:onClickCreate()
    if self:getCanAct() and self.state ~= nil and self.state.canCreate then
        self:closeAndRun(MHMapFrame.createJob)
    end
    return false
end

function MHDrawerDialog:onClickGoTo()
    if self:getCanAct() and self.state ~= nil and self.state.canGoTo then
        self:closeAndRun(MHMapFrame.goTo)
    end
    return false
end

function MHDrawerDialog:onClickStartStop()
    if not self:getCanAct() or self.state == nil or not self.state.canStartStop then
        return false
    end
    if self.state.startStop == "start" then
        -- Starting the job that is open in the job menu happens on the map page.
        self:closeAndRun(MHMapFrame.startStop)
    else
        MHMapFrame.startStop(self.frame)
        self:refresh(true)
    end
    return false
end

function MHDrawerDialog:onClickClear()
    if self:getCanAct() then
        MHMapFrame.clearQueue(self.frame)
    end
    return false
end

function MHDrawerDialog:onClickRemove(entryId)
    if self:getCanAct() then
        MHMapFrame.removeEntry(self.frame, entryId)
    end
    return false
end

function MHDrawerDialog:onClickBack()
    if not self.isOpen or self.inputDelay >= self.time then
        return true
    end
    self:close()
    return false
end

function MHDrawerDialog:delete()
    if self.rowTemplate ~= nil then
        self.rowTemplate:delete()
    end
    MHDrawerDialog:superClass().delete(self)
end
