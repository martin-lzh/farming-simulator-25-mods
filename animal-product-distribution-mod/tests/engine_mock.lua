-- Contract doubles, not copies of game implementations.
FarmManager = {SPECTATOR_FARM_ID = 0}
FillTypeManager = {SEND_NUM_BITS = 10}
MoneyType = {SOLD_PRODUCTS = 1, PRODUCTION_COSTS = 2}
ProductionPoint = {DIRECT_SELL_PRICE_FACTOR = 0.9, DIRECT_DELIVERY_PRICE = 0.000035}
MessageType = {HOUR_CHANGED = 1, MONEY_CHANGED = 2}
g_currentModName = "FS25_AnimalProductDistribution"
g_currentModDirectory = "animal-product-distribution-mod/"
g_modIsLoaded = {[g_currentModName] = true}
g_messageCenter = {subscribe = function() end, unsubscribe = function() end, publish = function() end}
g_currentMission = {
    farmId = 1, allowed = true, money = 0,
    getFarmId = function(self, connection) return connection and connection.farmId or self.farmId end,
    getHasPlayerPermission = function(self) return self.allowed end,
    addMoney = function(self, value) self.money = self.money + value end,
    economyManager = {getPricePerLiter = function() return 2 end}
}
g_farmManager = {getFarmById = function(_, id)
    if id ~= 1 and id ~= 2 then return nil end
    return {getBalance = function() return g_currentMission.money end}
end}
g_fillTypeManager = {
    getFillTypeNameByIndex = function(_, i) return "TYPE_" .. i end,
    getFillTypeIndexByName = function(_, name) return name and tonumber(name:match("TYPE_(%d+)")) end,
    getFillTypeTitleByIndex = function(_, i) return "Product " .. i end
}
function calcDistanceFrom() return 100 end
function Class(class, base)
    if base ~= nil then setmetatable(class, {__index = base}) end
    class.superClass = function() return base end
    return {__index = class}
end
Event = {new = function(mt) return setmetatable({}, mt) end}
function InitEventClass() end
g_server = {count = 0, broadcastEvent = function(self) self.count = self.count + 1 end}
NetworkUtil = {
    writeNodeObject = function(s, v) table.insert(s, v) end,
    readNodeObject = function(s) return table.remove(s, 1) end
}
function streamWriteUInt16(s, v) table.insert(s, v) end
function streamReadUInt16(s) return table.remove(s, 1) end
streamWriteUIntN, streamReadUIntN = streamWriteUInt16, streamReadUInt16
Utils = {
    prependedFunction = function(old, new) return function(...) new(...); return old(...) end end,
    appendedFunction = function(old, new) return function(...) old(...); return new(...) end end
}
PlaceableHusbandryMilk, PlaceableHusbandryPallets = {}, {}
SpecializationUtil = {hasSpecialization = function(needle, list)
    for _, value in ipairs(list) do if value == needle then return true end end
    return false
end}
TypeManager = {validateTypes = function() end}
-- Deliberately distinct from the real manager to catch proxy identity mistakes.
g_placeableTypeManager = {}
g_placeableSpecializationManager = {getSpecializationByName = function()
    return {name = "FS25_AnimalProductDistribution.animalProductDistribution"}
end}
InGameMenuAnimalsFrame = {updateMenuButtons = function(frame) frame.menuButtonInfo = {} end}
InputAction = {MENU_EXTRA_1 = 123}
g_i18n = {getText = function(_, key) return key end}
MessageDialog = {
    new = function(_, mt) return setmetatable({time = 0}, mt) end,
    onGuiSetupFinished = function() end,
    onOpen = function(self) self.isOpen = true end,
    onClose = function(self) self.isOpen = false end,
    close = function(self) self:onClose(); FocusManager:setGui(g_gui.previousGui) end,
    delete = function() end
}
FocusManager = {TOP = 1, BOTTOM = 2, currentGui = "InGameMenu", removeElement = function() end,
    setGui = function(self, name) self.currentGui = name end,
    linkElements = function() end, setFocus = function(self, element) self.focused = element end}
local function mockText()
    return {setText = function(self, value) self.text = value end}
end
local function mockRow(parent)
    local row = {parent = parent, label = mockText(), option = {
        setTexts = function(self, texts) self.texts = texts end,
        setState = function(self, state) self.state = state end,
        getState = function(self) return self.state end
    }}
    function row:getDescendantByName(name) return name == "mode" and self.option or self.label end
    function row:delete()
        self.deleted = true
        if self.parent ~= nil then
            for i, element in ipairs(self.parent.elements) do
                if element == self then table.remove(self.parent.elements, i); break end
            end
        end
    end
    return row
end
g_gui = {guis = {}, loads = 0, shows = 0}
function g_gui:loadGui(path, name, controller)
    self.loads = self.loads + 1
    FocusManager:setGui(name)
    controller.name, controller.xmlFilename = name, path
    controller.dialogTitleElement, controller.explanationElement = mockText(), mockText()
    controller.productRows = {elements = {}, invalidateLayout = function() end,
        scrollTo = function(self, position) self.scrollPosition = position end}
    controller.rowTemplate = {unlinkElement = function() end, delete = function() end,
        clone = function(_, parent)
            local row = mockRow(parent)
            table.insert(parent.elements, row)
            return row
        end}
    controller:onGuiSetupFinished()
    self.guis[name] = {target = controller}
    return self.guis[name]
end
function g_gui:showDialog(name)
    self.shows = self.shows + 1
    self.previousGui = FocusManager.currentGui
    FocusManager:setGui(name)
    self.dialog = self.guis[name].target
    self.dialog:onOpen()
    self.dialog.time = self.dialog.time + 251
end
Logging = {error = function(message) error(message) end, warning = function() end}

function mockHusbandry()
    local h = {
        isServer = true, farmId = 1,
        spec_husbandryPallets = {fillTypes = {7, 8}, pendingLiters = {[7] = 100, [8] = 40}},
        getOwnerFarmId = function(self) return self.farmId end,
        getName = function() return "Barn" end,
        updatePallets = function() end
    }
    AnimalProductDistribution.onLoad(h)
    AnimalProductDistribution.onLoadFinished(h)
    AnimalProductDistribution.onPostFinalizePlacement(h)
    return h
end
function mockStorage(amount, capacity)
    return {
        amount = amount, capacity = capacity,
        getFillLevel = function(self) return self.amount end,
        getFreeCapacity = function(self) return self.capacity - self.amount end,
        setFillLevel = function(self, value) self.amount = math.max(0, math.min(value, self.capacity)) end
    }
end
function mockXML()
    return {
        values = {},
        removeProperty = function(self, key)
            for path in pairs(self.values) do
                if path:sub(1, #key + 1) == key .. "." or path:sub(1, #key + 1) == key .. "(" then
                    self.values[path] = nil
                end
            end
        end,
        setValue = function(self, key, value) self.values[key] = value end,
        getValue = function(self, key, default) local v = self.values[key]; if v == nil then return default end; return v end,
        iterator = function(self, key)
            local i = -1
            return function()
                i = i + 1
                local entry = key .. "(" .. i .. ")"
                if self.values[entry .. "#fillType"] ~= nil then return i, entry end
            end
        end
    }
end
