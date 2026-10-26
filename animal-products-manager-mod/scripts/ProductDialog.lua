APMProductDialog = {}
local APMProductDialog_mt = Class(APMProductDialog, MessageDialog)
local modName = g_currentModName
local dialogName = modName .. "_ProductDestinations"
local dialogFile = g_currentModDirectory .. "gui/ProductDialog.xml"

function APMProductDialog.new()
    local self = MessageDialog.new(nil, APMProductDialog_mt)
    self.rows = {}
    return self
end

function APMProductDialog.show(title, explanation, entries, callback)
    -- GUI controllers survive map changes. Only the current request owns farm data.
    local gui = g_gui.guis[dialogName]
    if gui == nil then
        local previousGui = FocusManager.currentGui
        gui = g_gui:loadGui(dialogFile, dialogName, APMProductDialog.new())
        if previousGui ~= nil then FocusManager:setGui(previousGui) end
    end
    if gui == nil or gui.target.isOpen then return end
    local self = gui.target
    self.dialogTitleElement:setText(title)
    self.explanationElement:setText(explanation)
    self.entries, self.confirmCallback = entries, callback
    g_gui:showDialog(dialogName)
end

function APMProductDialog:onGuiSetupFinished()
    APMProductDialog:superClass().onGuiSetupFinished(self)
    self.dialogChromeHeight = self.dialogElement.size[2] - self.contentContainer.size[2]
    self.rowTemplate:unlinkElement()
    FocusManager:removeElement(self.rowTemplate)
end

function APMProductDialog:onOpen()
    APMProductDialog:superClass().onOpen(self)
    self.inputDelay = self.time + 250
    local visibleRows = math.min(math.max(#self.entries, 1), 4)
    local rowsHeight = visibleRows * self.rowTemplate.size[2]
    local explanationHeight = self.explanationElement:getTextHeight()
    self.productRows:setSize(nil, rowsHeight)
    self.dialogElement:setSize(nil, self.dialogChromeHeight - self.explanationElement.position[2]
        + explanationHeight + 20 * g_pixelSizeScaledY + rowsHeight + self.productRows.position[2])
    local texts = {
        g_i18n:getText("ui_production_output_storing"),
        g_i18n:getText("ui_production_output_selling"),
        g_i18n:getText("apm_mode_distribute_store", modName),
        g_i18n:getText("apm_mode_distribute_sell", modName)
    }
    for _, entry in ipairs(self.entries) do
        local element = self.rowTemplate:clone(self.productRows)
        -- Clones keep the template's original width; the scrolling viewport is narrower.
        element:setSize(self.productRows.absSize[1], nil)
        element:getDescendantByName("productName"):setText(entry.title)
        local option = element:getDescendantByName("mode")
        option:setTexts(texts)
        option:setState(entry.mode + 1)
        table.insert(self.rows, {element = element, option = option,
            fillType = entry.fillType, initialMode = entry.mode})
    end
    self.productRows:invalidateLayout()
    self.productRows:scrollTo(0, true)
    if #self.rows > 0 then
        for index, row in ipairs(self.rows) do
            local previous = self.rows[index - 1] or self.rows[#self.rows]
            local following = self.rows[index + 1] or self.rows[1]
            FocusManager:linkElements(row.option, FocusManager.TOP, previous.option)
            FocusManager:linkElements(row.option, FocusManager.BOTTOM, following.option)
        end
        FocusManager:setFocus(self.rows[1].option)
    end
end

function APMProductDialog:onClickOk()
    if not self.isOpen or self.inputDelay >= self.time then return true end
    local changes = {}
    for _, row in ipairs(self.rows) do
        local mode = row.option:getState() - 1
        if mode ~= row.initialMode then
            table.insert(changes, {fillType = row.fillType, mode = mode})
        end
    end
    local callback = self.confirmCallback
    self:close()
    if callback ~= nil then callback(changes) end
    return false
end

function APMProductDialog:onClickBack()
    if not self.isOpen or self.inputDelay >= self.time then return true end
    self:close()
    return false
end

function APMProductDialog:onClose()
    self.entries, self.confirmCallback = nil, nil
    for _, row in ipairs(self.rows) do row.element:delete() end
    self.rows = {}
    APMProductDialog:superClass().onClose(self)
end

function APMProductDialog:delete()
    if self.rowTemplate ~= nil then self.rowTemplate:delete() end
    APMProductDialog:superClass().delete(self)
end
