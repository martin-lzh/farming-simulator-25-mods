local modName = g_currentModName
local MH = MapHelper

-- Engine class tables survive map changes. Refresh callbacks without stacking hooks.
local function installHook(class, method, prepend, callback)
    local key = "mh_" .. modName .. "_" .. method .. (prepend and "_before" or "")
    if class[key] == nil then
        local dispatch = function(...)
            if g_modIsLoaded[modName] then
                return class[key](...)
            end
        end
        local wrap = prepend and Utils.prependedFunction or Utils.appendedFunction
        class[method] = wrap(class[method], dispatch)
    end
    class[key] = callback
end

local function getMissing(class, className, names)
    if class == nil then
        return className
    end
    for _, name in ipairs(names) do
        if class[name] == nil then
            return className .. "." .. name
        end
    end
    return nil
end

-- Check every game function the Mod relies on. A missing one disables only the
-- feature that needs it, logs once, and leaves the map page untouched.
local function findMissing(checks)
    for _, check in ipairs(checks) do
        local missing = getMissing(check[1], check[2], check[3])
        if missing ~= nil then
            return missing
        end
    end
    return nil
end

local queueMissing = findMissing({
    {FSBaseMission, "FSBaseMission", {"onStartMission", "delete", "sendInitialClientState", "addUpdateable", "removeUpdateable"}},
    {FSCareerMissionInfo, "FSCareerMissionInfo", {"saveToXMLFile"}},
    {AISystem, "AISystem", {"startJob", "stopJob", "stopJobInternal"}},
    {AIJob, "AIJob", {"writeStream", "readStream", "saveToXMLFile", "loadFromXMLFile", "getIsStartable", "validate", "setValues"}},
    {AIJobTypeManager, "AIJobTypeManager", {"createJob", "getJobTypeIndex", "getJobTypeByIndex", "getJobTypeIndexByName"}},
    {AIMessageSuccessFinishedJob, "AIMessageSuccessFinishedJob", {"new"}},
    {MessageType, "MessageType", {"AI_JOB_STOPPED"}},
    {XMLFile, "XMLFile", {"create", "loadIfExists"}},
    {AIParameterType, "AIParameterType", {"POSITION", "POSITION_ANGLE", "LOADING_STATION", "UNLOADING_STATION", "TEXT"}}
})
MH.features.queue = queueMissing == nil
if queueMissing ~= nil then
    MH.warnOnce("queue", "%s not found in this game version; the command queue is disabled", queueMissing)
end

local pageMissing = findMissing({
    {InGameMenuMapFrame, "InGameMenuMapFrame", {"onLoadMapFinished", "setupMapOverview", "onClickMapOverviewSelector",
        "registerInput", "setJobMenuVisible", "setMapSelectionItem", "setActiveJobTypeSelection", "updateParameterValueTexts",
        "validateParameters", "updateWarnings", "refreshContextInput", "executePickingCallback", "getIsPicking",
        "onMenuMapAction1", "onFrameClose", "update", "AI_MODE_OVERVIEW", "AI_MODE_CREATE"}},
    {IngameMapElement, "IngameMapElement", {"panToHotspot", "setCenterToWorldPosition"}},
    {g_gui, "g_gui", {"loadGuiRec", "loadProfileSet"}},
    {InfoDialog, "InfoDialog", {"show"}},
    {AIMessageSuccessStoppedByUser, "AIMessageSuccessStoppedByUser", {"new"}},
    {InputAction, "InputAction", {"MENU_EXTRA_1"}}
})
MH.features.page = pageMissing == nil and MH.features.queue
if pageMissing ~= nil then
    MH.warnOnce("page", "%s not found in this game version; the Map Helper page is disabled", pageMissing)
end

-- Field states for the "fields needing this work" filter and the field hints. Without them
-- the page still lists fields, contracts and stations.
local fieldNeedsMissing = findMissing({
    {FieldState, "FieldState", {"new", "update"}},
    {FieldGroundType, "FieldGroundType", {"NONE", "PLOWED", "CULTIVATED", "SEEDBED"}},
    {FruitType, "FruitType", {"UNKNOWN"}},
    {FieldDensityMap, "FieldDensityMap", {"SPRAY_LEVEL"}},
    {g_fruitTypeManager, "g_fruitTypeManager", {"getFruitTypeByIndex"}}
})
MH.features.fieldNeeds = fieldNeedsMissing == nil
if fieldNeedsMissing ~= nil and MH.features.page then
    MH.warnOnce("fieldNeeds", "%s not found in this game version; field needs are not shown", fieldNeedsMissing)
end

local hotkeyMissing = findMissing({
    {PlayerInputComponent, "PlayerInputComponent", {"registerGlobalPlayerActionEvents"}},
    {InGameMenu, "InGameMenu", {"openMapOverview"}},
    {InputAction, "InputAction", {MH.HOTKEY_ACTION}}
})
MH.features.hotkey = hotkeyMissing == nil and MH.features.page
if hotkeyMissing ~= nil and MH.features.page then
    MH.warnOnce("hotkey", "%s not found in this game version; the Map Helper hotkey is disabled", hotkeyMissing)
end

installHook(FSBaseMission, "onStartMission", false, function(mission)
    MH.onMissionStarted(mission)
end)

-- FSBaseMission:delete: before the game's teardown only a flag is set (MH.onMissionDeleting),
-- so nothing of this Mod can stop it; everything else runs after it.
installHook(FSBaseMission, "delete", true, function()
    MH.onMissionDeleting()
end)
installHook(FSBaseMission, "delete", false, function(mission)
    MH.onMissionDeleted(mission)
end)

if MH.features.queue then
    installHook(FSBaseMission, "sendInitialClientState", false, function(_, connection)
        if MapHelper.features.queue then
            MapHelper.sendInitialState(connection)
        end
    end)
    installHook(FSCareerMissionInfo, "saveToXMLFile", false, function(missionInfo)
        MapHelper.onSavegameSaved(missionInfo)
    end)
end

if MH.features.page then
    local frameHooks = {
        onLoadMapFinished = function(frame) MHMapFrame.inject(frame) end,
        setupMapOverview = function(frame) MHMapFrame.addSelectorPage(frame) end,
        onClickMapOverviewSelector = function(frame, state) MHMapFrame.onSelectorChanged(frame, state) end,
        registerInput = function(frame) MHMapFrame.registerInput(frame) end,
        setJobMenuVisible = function(frame, isVisible) MHMapFrame.onJobMenuVisible(frame, isVisible) end,
        setMapSelectionItem = function(frame, hotspot) MHMapFrame.onMapSelectionChanged(frame, hotspot) end,
        setActiveJobTypeSelection = function(frame) MHMapFrame.onJobTypeSelected(frame) end,
        onMenuMapAction1 = function(frame) MHMapFrame.onMenuMapAction1(frame) end,
        onFrameClose = function(frame) MHMapFrame.onFrameClose(frame) end,
        update = function(frame, dt) MHMapFrame.update(frame, dt) end
    }
    for method, callback in pairs(frameHooks) do
        installHook(InGameMenuMapFrame, method, false, function(...)
            if MapHelper.features.page then
                callback(...)
            end
        end)
    end
end

-- The hotkey is registered together with the game's own global actions (menu, map, shop),
-- which PlayerInputComponent registers on foot (PLAYER) and Enterable in every vehicle
-- (VEHICLE). Same context handling as the game's function.
if MH.features.hotkey then
    installHook(PlayerInputComponent, "registerGlobalPlayerActionEvents", false, function(component, context)
        if MapHelper.features.hotkey then
            MapHelper.registerHotkey(component, context)
        end
    end)
end
