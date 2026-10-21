local modName = g_currentModName
local MH = MapHelper

-- Engine class tables survive map changes. Refresh callbacks without stacking hooks.
local function installHook(class, method, prepend, callback)
    local key = "mh_" .. modName .. "_" .. method
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
    {AIParameterType, "AIParameterType", {"POSITION", "POSITION_ANGLE", "LOADING_STATION", "UNLOADING_STATION"}}
})
MH.features.queue = queueMissing == nil
if queueMissing ~= nil then
    MH.warnOnce("queue", "%s not found in this game version; the command queue is disabled", queueMissing)
end

local drawerMissing = findMissing({
    {InGameMenuMapFrame, "InGameMenuMapFrame", {"onLoadMapFinished", "registerInput", "setJobMenuVisible", "setAIVehicle",
        "setMapSelectionItem", "onStartGoToJob", "onStartCancelJob", "getCanStartJob", "getIsPicking", "onClickBack",
        "updateWarnings", "AI_MODE_OVERVIEW", "AI_MODE_CREATE"}},
    {IngameMapElement, "IngameMapElement", {"panToHotspot", "setCenterToWorldPosition"}},
    {g_gui, "g_gui", {"loadGui", "loadGuiRec", "loadProfileSet", "showDialog", "getIsDialogVisible"}},
    {MessageDialog, "MessageDialog", {"new"}},
    {InfoDialog, "InfoDialog", {"show"}},
    {AIMessageSuccessStoppedByUser, "AIMessageSuccessStoppedByUser", {"new"}},
    {InputAction, "InputAction", {"MH_TOGGLE_DRAWER", "MH_ADD_TO_QUEUE"}}
})
MH.features.drawer = drawerMissing == nil
if drawerMissing ~= nil then
    MH.warnOnce("drawer", "%s not found in this game version; the map page drawer is disabled", drawerMissing)
end

installHook(FSBaseMission, "onStartMission", false, function(mission)
    MH.onMissionStarted(mission)
end)

installHook(FSBaseMission, "delete", true, function(mission)
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

if MH.features.drawer then
    installHook(InGameMenuMapFrame, "onLoadMapFinished", false, function(frame)
        if MapHelper.features.drawer then
            MHMapFrame.inject(frame)
        end
    end)
    installHook(InGameMenuMapFrame, "registerInput", false, function(frame)
        if MapHelper.features.drawer then
            MHMapFrame.registerInput(frame)
        end
    end)
    installHook(InGameMenuMapFrame, "setJobMenuVisible", false, function(frame, isVisible)
        if MapHelper.features.drawer then
            MHMapFrame.updateQueueButton(frame, isVisible)
        end
    end)
end
