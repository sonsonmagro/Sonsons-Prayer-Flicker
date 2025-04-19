--- @version 1.1.0

------------------------------------------
--# IMPORTS
------------------------------------------

local API    = require("api")
local Utils  = {}

------------------------------------------
--# TYPE DEFINITIONS
------------------------------------------

--- @class Prayer
--- @field name             string: The name of the prayer (Used for activating ability)
--- @field id               integer: The ID of the buff

--- @class PrayerConfig
--- @field defaultPrayer?   Prayer
--- @field threats          Threat[]

--- @class Threat
--- @field name?            string: Used for debugging and metrics
--- @field type             ThreatType: The type of threat
--- @field prayer           Prayer: The prayer to use against this threat
--- @field range?           integer: The radius to perform the threat check on (default: 60)
--- @field id?              integer: The ID of the of the threat to check for to check for (animation id or projectile id)
--- @field condition?       fun():boolean The condition in the case of 
--- @field bypassCondition? fun(): boolean
--- @field npcId?           integer: The ID of the NPC to check the animation
--- @field priority         integer
--- @field delay            integer
--- @field duration         integer

--- @alias ThreatType
--- | "Projectile"
--- | "Animation"
--- | "Conditional"

--- @class Action
--- @field threat           Threat
--- @field activationData   ActivationData

--- @class ActivationData
--- @field tickAdded        integer
--- @field tickActivated    integer
--- @field tickExpired      integer

--- @class PrayerState
--- @field activePrayer     Prayer
--- @field lastPrayerTick   number
--- @field pendingActions   Threat[]

--- @class PrayerFlicker
--- @field defaultPrayer    Prayer
--- @field threats          Threat[]
--- @field actions          Action[]
--- @field state            PrayerState


------------------------------------------
--# INITIALIZATION
------------------------------------------

local PrayerFlicker = {}
PrayerFlicker.__index = PrayerFlicker

------------------------------------------
--# LIST OF OVERHEADS
------------------------------------------

--- List of curses to choose from
--- @type table<string, Prayer>
PrayerFlicker.CURSES = {
    SOUL_SPLIT         = { name = "Soul Split",         id = 26033 },
    DEFLECT_MELEE      = { name = "Deflect Melee",      id = 26040 },
    DEFLECT_MAGIC      = { name = "Deflect Magic",      id = 26041 },
    DEFLECT_RANGED     = { name = "Deflect Ranged",     id = 26044 },
    DEFLECT_NECROMANCY = { name = "Deflect Necromancy", id = 30745 },
}

--- List of prayers to choose from
--- @type table<string, Prayer>
PrayerFlicker.PRAYERS = {
    ECLIPSED_SOUL           = { name = "Eclipsed Soul",             id = 26033 }, -- FIXME:
    PROTECT_FROM_MELEE      = { name = "Protect from Melee",        id = 25961 },
    PROTECT_FROM_MAGIC      = { name = "Protect from Magic",        id = 25959 },
    PROTECT_FROM_RANGED     = { name = "Protect from Ranged",       id = 26044 }, -- FIXME:
    PROTECT_FROM_SUMMONING  = { name = "Protect from Summoning",    id = 30745 }, -- FIXME:
    PROTECT_FROM_NECROMANCY = { name = "Protect from Necromancy",   id = 30745 }, -- FIXME:
}

-- Singleton instance
local instance      = nil
local debug         = false

--- Initiatlizes a new Prayer Flicker instance
--- @param config? PrayerConfig Configuration options
--- @return PrayerFlicker: Initialized PrayerFlicker instance
function PrayerFlicker.new(config)
    if instance then
        Utils:log("Returning existing PrayerFlicker instance", "debug") -- DEBUG
        return instance
    end

    -- Creates a new instance if none exists
    local self = setmetatable({}, PrayerFlicker)
    Utils:log("Initializing Prayer flicker instance", "info")
    -- Default debug values
    

    -- TODO: Assert configurations
    Utils:log("Validating configuration...", "debug") -- DEBUG
    if config then
        Utils:log("Configuration provided", "debug") -- DEBUG
    end

    self.flickInterval      = 1
    self.sameFlickInterval  = 4
    self.defaultPrayer      = config and config.defaultPrayer or {}
    self.threats            = config and config.threats or {}
    self.prayers            = self:_getRequiredPrayers()
    self.pendingActions     = {}

    -- Check if the player has their required prayers on their bars
    self:_checkRequiredPrayers()

    self.state = {
        activePrayer = {},
        activationTick = 0,
    }

    instance = self
    Utils:log("PrayerFlicker initialized successfully", "info") -- DEBUG
    return instance
end

--- Retrieves all required prayers from list of threats
function PrayerFlicker:_getRequiredPrayers()
    Utils:log("Retrieving required prayers from threats", "debug") -- DEBUG
    local requiredPrayers = {}

    if self.defaultPrayer then
        table.insert(requiredPrayers, self.defaultPrayer)
    end

    for _, threat in ipairs(self.threats) do
        local prayer = threat.prayer
        -- Check if prayer already exists
        if #requiredPrayers > 0 then
            for _, requiredPrayer in ipairs(requiredPrayers) do
                if requiredPrayer.name == prayer.name then
                    Utils:log("Prayer already registered: " .. prayer.name, "debug") -- DEBUG
                    goto continue
                end
            end
        end
        Utils:log("Required prayer registered: "..prayer.name, "info")
        table.insert(requiredPrayers, prayer)
        ::continue::
    end
    Utils:log("Total required prayers: " .. #requiredPrayers, "debug") -- DEBUG
    return requiredPrayers
end

--- Checks to see if the listed prayers exist on available ability bars
--- @private
function PrayerFlicker:_checkRequiredPrayers()
    Utils:log("Checking for required prayers on ability bars", "debug") -- DEBUG
    local missingPrayers = {}

    for _, prayer in pairs(self.prayers) do
        Utils:log("Checking ability bar for prayer: " .. prayer.name, "debug") -- DEBUG
        if #API.GetABs_names({ prayer.name }) < 1 then
            Utils:log("Prayer missing: " .. prayer.name, "debug") -- DEBUG
            table.insert(missingPrayers, prayer.name)
        end
    end

    if #missingPrayers >= 1 then
        API.SetDrawLogs(true)
        Utils:log("[PRAYER FLICKER]: Missing prayers!", "warn")
        Utils:log("[PRAYER FLICKER]: Please make sure to add the following prayers to your ability bars.", "warn")
        Utils:log("[PRAYER FLICKER]: " .. table.concat(missingPrayers, ", "), "warn")
        Utils:log("[PRAYER FLICKER]: Terminating your session.", "error")
        -- Terminate session
        API.Write_LoopyLoop(false)
    else
        Utils:log("All required prayers found on ability bars", "info") -- DEBUG
    end
end

------------------------------------------
--# CORE FUNCTIONALITY
------------------------------------------

--- Updates the Prayer Flicker instance
--- @return boolean: Whether an action was triggered this loop
function PrayerFlicker:update()
    Utils:log("Updating PrayerFlicker...", "debug") -- DEBUG
    self:_updateActions()
    return self:_switchPrayer(self:_determinePrayer())
end

--- Disables active prayer
--- @return boolean
function PrayerFlicker:deactivatePrayer()
    Utils:log("Attempting to deactivate prayer", "debug") -- DEBUG
    local currentTick = API.Get_tick()
    local prayer = self:_getActivePrayer()
    if not prayer.name or ((currentTick - self.state.activationTick < 1) and not self.state.activePrayer.name) then 
        Utils:log("Deactivation skipped: No active prayer or cooldown", "debug") -- DEBUG
        return false 
    end

    Utils:log("Deactivating prayer: " .. prayer.name, "info") -- DEBUG
    local success = API.DoAction_Ability(
        prayer.name,
        1,
        API.OFF_ACT_GeneralInterface_route,
        true
    )

    if success then
        self.state.activationTick = API.Get_tick()
        ---@diagnostic disable-next-line
        self.state.activePrayer = {}
        Utils:log("Prayer deactivated: " .. prayer.name, "info") -- DEBUG
    else
        Utils:log("Failed to deactivate prayer: " .. prayer.name, "warn") -- DEBUG
    end

    return success
end

------------------------------------------
--# THREAT MANAGEMENT CORE FUNCTIONS
------------------------------------------

--- Checks to see if threats exists and adds them to self.pendingActions if they do
function PrayerFlicker:_getExistingThreats()
    Utils:log("Scanning for existing threats...", "debug") -- DEBUG
    local foundThreats = {}
    -- Iterate over list of threats
    for _, threat in ipairs(self.threats) do
        Utils:log("Checking threat: " .. (threat.name or "Unnamed"), "debug") -- DEBUG
        if self:_doesThreatExist(threat) then
            if not self:_isThreatInTable(foundThreats, threat) then
                Utils:log("+ Threat detected: "..(threat.name or "Unnamed threat"), "warn")
                table.insert(foundThreats, threat)
            end
        else
            Utils:log("- Threat not active: " .. (threat.name or "Unnamed"), "debug") -- DEBUG
        end
    end
    Utils:log("Total threats found: " .. #foundThreats, "debug") -- DEBUG
    return foundThreats
end

function PrayerFlicker:_updateActions()
    Utils:log("Updating pending actions...", "debug") -- DEBUG
    local currentTick   = API.Get_tick()
    local threats       = self:_getExistingThreats()
    local actions       = self.pendingActions
    local toAdd = {}
    local toRemove = {}

    Utils:log("Current pending actions: " .. #actions, "debug") -- DEBUG

    if #threats > 0 then
        Utils:log("Processing " .. #threats .. " active threats", "debug") -- DEBUG
        -- Check if threats exist, add to threats.pendingActions
        for _, threat in ipairs(threats) do
            if not self:_isThreatInTable(self.pendingActions, threat) then
                Utils:log("+ Adding threat: ".. (threat.name or "Unnamed threat"), "debug") -- DEBUG
                table.insert(toAdd, threat)
            end
        end

        -- Add threats that don't exist in self.pendingActions
        for _, threat in ipairs(toAdd) do
            table.insert(self.pendingActions, {
                threat = threat,
                activationData = {
                    tickExpired = -1,
                    tickAdded = currentTick
                }
            })
            Utils:log("Added threat to pending actions: " .. (threat.name or "Unnamed"), "debug") -- DEBUG
        end
    end

    if #actions > 0 then
        Utils:log("Processing " .. #actions .. " pending actions", "debug") -- DEBUG
        for i, action in ipairs(actions) do
            local threatExists = self:_doesThreatExist(action.threat)
            -- If the threat no longer exists
            if not threatExists then
                local tickExpired = action.activationData.tickExpired
                -- If no expiration tick set
                if tickExpired == -1 then
                    action.activationData.tickExpired = currentTick + action.threat.duration
                    Utils:log("Set expiration tick for threat: " .. (action.threat.name or "Unnamed"), "debug") -- DEBUG
                    goto continue
                end
                -- If expiration tick passed
                if tickExpired >= currentTick then
                    Utils:log("Threat expired: "..(action.threat.name or "Unnamed threat"), "debug") -- DEBUG
                    table.insert(toRemove, {index = i, action = action})
                    goto continue
                end
            else
                -- Threat still exists, make sure no expiration date
                action.activationData.tickExpired = -1
                Utils:log("Threat still active: " .. (action.threat.name or "Unnamed"), "debug") -- DEBUG
            end
            ::continue::
        end
    end

    -- Remove expired actions
    table.sort(actions, function(a, b)
        return a.index < b.index
    end)
    for _, record in ipairs(toRemove) do
        Utils:log("Removing expired action: " .. (record.action.threat.name or "Unnamed"), "debug") -- DEBUG
        table.remove(self.pendingActions, record.index)
    end 

    Utils:log("Pending actions after update: " .. #self.pendingActions, "debug") -- DEBUG
end

------------------------------------------
--# THREAT MANAGEMENT HELPER FUNCTIONS
------------------------------------------

--- Checks if the threat exists
--- @param threat Threat: The threat in question
--- @return boolean: Whether the threat exists
function PrayerFlicker:_doesThreatExist(threat)
    --- @type ThreatType
    local threatType = threat.type
    local threatExists = false
    Utils:log(string.format("Checking for threat [%s]: %s", threat.type, threat.name or "Unnamed threat"), "debug")

    -- Projectile threat checks
    if threatType == "Projectile" then
        Utils:log(string.format("Checking projectile ID %d (range %d)", threat.id, threat.range or 60), "debug") -- DEBUG
        threatExists = self:_projectileExists(threat.id, threat.range)
        goto continue
    end

    -- Animation threat checks
    if threatType == "Animation" then
        Utils:log(string.format("Checking NPC %d animation %d (range %d)", threat.npcId, threat.id, threat.range or 60), "debug") -- DEBUG
        threatExists = self:_animationExists(threat.npcId, threat.id, threat.range)
        goto continue
    end

    -- Conditional threat checks
    if threatType == "Conditional" then
        Utils:log("Checking conditional threat", "debug") -- DEBUG
        threatExists = self:_conditionalThreatExists(threat.condition)
        goto continue
    end
    ::continue::
    if threat.bypassCondition and threat.bypassCondition() then
        Utils:log("Threat bypassed by condition", "debug") -- DEBUG
        return false
    end
    Utils:log("Threat exists: " .. tostring(threatExists), "debug") -- DEBUG
    return threatExists
end

--- Checks if the specified projectile threat(s) exist
--- @param id integer | integer[]
--- @param range? integer
--- @return boolean
--- @private
function PrayerFlicker:_projectileExists(id, range)
    Utils:log(string.format("Scanning for projectiles (ID: %s, range: %d)", tostring(id), range or 60), "debug") -- DEBUG
    local found = #Utils:findAll(id, 5, range or 60) > 0
    Utils:log(string.format("Projectiles found: %s", tostring(found)), "debug") -- DEBUG
    return found
end

--- Checks if the specified animation threat(s) exist
--- @param npcId integer
--- @param animId integer | integer[]
--- @param range? integer
--- @return boolean
--- @private
function PrayerFlicker:_animationExists(npcId, animId, range)
    Utils:log(string.format("Scanning NPC %d for animation %d (range %d)", npcId, animId, range or 60), "debug") -- DEBUG
    local npcs = Utils:findAll(npcId, 1, range or 60)
    if #npcs > 0 then
        for _, npc in ipairs(npcs) do
            if npc.Id and npc.Anim == animId then 
                Utils:log("Animation found on NPC", "debug") -- DEBUG
                return true 
            end
        end
    end
    Utils:log("Animation not found", "debug") -- DEBUG
    return false
end

--- Checks if the conditional threat exists
--- @param condition fun(): boolean
--- @return boolean
--- @private
function PrayerFlicker:_conditionalThreatExists(condition)
    Utils:log("Evaluating conditional threat", "debug") -- DEBUG
    local result = condition and condition()
    Utils:log("Condition result: " .. tostring(result), "debug") -- DEBUG
    return result
end

--- Checks if a threat with the same properties exists in the specified table
--- @param tableToCheck table The table to check (either pendingActions or another table)
--- @param threat Threat The threat to look for
--- @return boolean: True if threat already exists, false otherwise
--- @private
function PrayerFlicker:_isThreatInTable(tableToCheck, threat)
    Utils:log(string.format("Checking if threat exists in table: %s", threat.name or "Unnamed"), "debug") -- DEBUG
    -- Handle pendingActions special case
    local items = tableToCheck
    if tableToCheck == self.pendingActions then
        -- Process pendingActions differently since threats are nested in action.threat
        for _, action in ipairs(tableToCheck) do
            if self:_threatsMatch(action.threat, threat) then
                Utils:log("Threat already in pending actions", "debug") -- DEBUG
                return true
            end
        end
    else
        -- Standard table processing
        for _, existingThreat in ipairs(tableToCheck) do
            if self:_threatsMatch(existingThreat, threat) then
                Utils:log("Threat already exists in table", "debug") -- DEBUG
                return true
            end
        end
    end
    Utils:log("Threat not found in table", "debug") -- DEBUG
    return false
end

--- Helper function to compare two threats
--- @param threatA Threat First threat to compare
--- @param threatB Threat Second threat to compare
--- @return boolean: True if threats match
--- @private
function PrayerFlicker:_threatsMatch(threatA, threatB)
    Utils:log(string.format("Comparing threats: %s vs %s", threatA.name or "A", threatB.name or "B"), "debug") -- DEBUG
    -- Simple check if names exist and match
    if threatA.name and threatB.name then
        if threatA.name == threatB.name then
            Utils:log("Threat names match", "debug") -- DEBUG
            return true
        end
    end

    -- More detailed comparison based on type
    if threatA.type == threatB.type then
        if threatA.type == "Projectile" then
            local match = threatA.id == threatB.id
            Utils:log(string.format("Projectile ID match: %s", tostring(match)), "debug") -- DEBUG
            return match
        elseif threatA.type == "Animation" then
            local match = (threatA.npcId == threatB.npcId) and (threatA.id == threatB.id)
            Utils:log(string.format("Animation NPC/ID match: %s", tostring(match)), "debug") -- DEBUG
            return match
        elseif threatA.type == "Conditional" then
            local match = tostring(threatA.condition) == tostring(threatB.condition)
            Utils:log(string.format("Conditional function match: %s", tostring(match)), "debug") -- DEBUG
            return match
        end
    end

    Utils:log("Threats do not match", "debug") -- DEBUG
    return false
end

------------------------------------------
--# OVERHEAD MANAGEMENT CORE FUNCTIONS
------------------------------------------

--- Determines the prayer to use based on threat priorities
--- @return Prayer: The prayer with the highest threat priority
--- @private
function PrayerFlicker:_determinePrayer()
    Utils:log("Determining prayer based on threats...", "debug") -- DEBUG
    local currentTick   = API.Get_tick()
    local actions       = self.pendingActions

    -- Sort threats by priority (highest first)
    table.sort(actions, function(a, b)
        return (a.threat.priority or 0) > (b.threat.priority or 0)
    end)

    if #actions > 0 then
        Utils:log("Evaluating " .. #actions .. " actions", "debug") -- DEBUG
        for _, action in ipairs(actions) do
            if currentTick - action.activationData.tickAdded >= action.threat.delay then
                Utils:log("Selected prayer: " .. action.threat.prayer.name, "debug") -- DEBUG
                return action.threat.prayer
            end
        end
    end

    Utils:log("No active threats, using default prayer", "debug") -- DEBUG
    return self.defaultPrayer
end

--- Switches your prayers depending on highest threat and last triggered
--- @param prayer Prayer
--- @return boolean
--- @private
function PrayerFlicker:_switchPrayer(prayer)
    Utils:log("Attempting to switch prayer...", "debug") -- DEBUG
    if not prayer then 
        Utils:log("No prayer provided", "debug") -- DEBUG
        return false 
    end
    if not self:_shouldToggle(prayer) then 
        Utils:log("Prayer toggle not required", "debug") -- DEBUG
        return false 
    end

    Utils:log("Flicking to prayer: " .. prayer.name, "info") -- DEBUG
    local success = API.DoAction_Ability(prayer.name, 1, API.OFF_ACT_GeneralInterface_route, true)

    if success then
        self.state.activePrayer = prayer
        self.state.activationTick = API.Get_tick()
        Utils:log("Prayer switched successfully to " .. prayer.name, "info") -- DEBUG
    else
        Utils:log("Failed to switch to prayer: " .. prayer.name, "warn") -- DEBUG
    end

    return success
end

------------------------------------------
--# OVERHEAD MANAGEMENT HELPER FUNCTIONS
------------------------------------------

--- Returns the active overhead used by the player
--- @return Prayer
function PrayerFlicker:_getActivePrayer()
    Utils:log("Checking active prayer...", "debug") -- DEBUG
    -- Loops through required prayers
    for _, prayer in ipairs(self.prayers) do
        if API.Buffbar_GetIDstatus(prayer.id, false).found then
            Utils:log("Active prayer found: " .. prayer.name, "debug") -- DEBUG
            return prayer
        end
    end
    Utils:log("No active prayer detected", "debug") -- DEBUG
    return {}
end

--- Checks if prayer can be toggled (to avoid misfires)
--- @param prayer Prayer: The prayer to activate
--- @return boolean: Whether the prayer should be toggled
function PrayerFlicker:_shouldToggle(prayer)
    local currentTick = API.Get_tick()
    local flickInterval = (prayer.name == self.state.activePrayer.name) and self.sameFlickInterval or self.sameFlickInterval

    Utils:log(string.format("Checking toggle conditions: CurrentTick=%d, LastActivation=%d, Interval=%d", 
        currentTick, self.state.activationTick, flickInterval), "debug") -- DEBUG

    if currentTick - self.state.activationTick > flickInterval then
        local activePrayer = self:_getActivePrayer()
        local shouldToggle = prayer.name ~= (activePrayer and activePrayer.name or "")
        Utils:log("Should toggle: " .. tostring(shouldToggle), "debug") -- DEBUG
        return shouldToggle
    end

    Utils:log("Toggle blocked by cooldown", "debug") -- DEBUG
    return false
end

------------------------------------------
--# METRICS
------------------------------------------

--- Can be used with API.DrawTable(PrayerFlicker:tracking()) to check metrics
--- @return table
function PrayerFlicker:tracking()
    local actions = self.pendingActions
    local metrics = {
        { "Prayer Flicker:", "" },
        { "- Active",        self:_getActivePrayer() and self:_getActivePrayer().name or "None" },
        { "- Last Used",     self.state.activePrayer and self.state.activePrayer.name or "None" },
        { "- Required",      self:_determinePrayer().name },
    }

    if #actions > 0 then
        local formattedPendingActions = {}
        for i, action in ipairs(actions) do
            table.insert(formattedPendingActions, {
                string.format("-- [%d] %s", i, action.threat.prayer.name),
                string.format("[%d] Type: %s", action.threat.priority or -1, action.threat.type or "UNKNOWN")
            })  
        end

        Utils:multiTableConcat(
            metrics,
            {
                { "- Pending Actions:", #actions .. " actions pending" },
            },
            formattedPendingActions
        )
    end
    return metrics
end

------------------------------------------
--# BORROWED HELPER FUNCTIONS
------------------------------------------

---Concatenates multiple tables into the first one
---@param t1 table
---@param ... table
function Utils:multiTableConcat(t1, ...)
    local args = { ... }
    for _, t2 in ipairs(args) do
        for i = 1, #t2 do t1[#t1 + 1] = t2[i] end
    end
end

---@param message string
---@param logType? "warn"|"error"|"debug"|"info"|"lua"
function Utils:log(message, logType)
    if not debug then return end

    ---@type table<string, fun(message: string)>
    local debugLogTypes = {
        warn = API.logWarn,
        error = API.logError,
        debug = API.logDebug,
        info = API.logInfo,
        lua = print
    }

    logType = logType or "debug"
    local logFunction = debugLogTypes[logType] or debugLogTypes.debug
    logFunction(message)
end

---Returns all AllObjects
---@param objID number | table
---@param distance number
---@param objType number
---@return AllObject[]
function Utils:findAll(objID, objType, distance)
    local id = type(objID) == "table" and objID or { objID }
    local allObjects = API.GetAllObjArray1(id, distance or 25, { objType })
    return allObjects or nil
end

return PrayerFlicker
