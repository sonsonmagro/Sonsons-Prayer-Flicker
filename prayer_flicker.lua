---@version 1.0.1
--[[
    File: praye_flicker.lua
    Description: This class is designed for dynamic prayer switching based on various threat types
    Author: Sonson
    
    Changelog:
    - V.1.0.1:
        - Added PrayerFlicker:deactivatePrayer()
        - update() and & _switchPrayer() now return true when prayer is switched
    - V.1.0.0: 
        -Initial release
]]
---@class PrayerFlicker
---@field config PrayerFlickerConfig
---@field state PrayerFlickerState
local PrayerFlicker = {}
PrayerFlicker.__index = PrayerFlicker

--#region luaCATS annotation
---@class Prayer
---@field name string
---@field buffId number

---@class PrayerFlickerConfig
---@field prioritizeProjectiles boolean
---@field defaultPrayer Prayer
---@field prayers Prayer[]
---@field projectiles Projectile[]
---@field npcs PrayerFlickerNPC[]
---@field conditionals Conditional[]

---projectile threat data
---@class Projectile
---@field id projectileId
---@field prayer Prayer
---@field bypassCondition fun(): boolean
---@field priority number
---@field activationDelay number
---@field duration number

---npc animation data
---@class PrayerFlickerNPC
---@field id npcId
---@field animations Animation[]

---animation threat data
---@class Animation
---@field animId animationId
---@field prayer Prayer
---@field activationDelay number
---@field duration number
---@field priority number

---conditional threat data
---@class Conditional
---@field condition fun(): boolean
---@field prayer Prayer
---@field priority number

---@class PrayerFlickerState
---@field activePrayer Prayer
---@field lastPrayerTick number
---@field pendingActions Threat[]

---@class Threat 
---@field type threatType
---@field projId projectileId
---@field animId animationId
---@field npcId npcId
---@field condition fun(): boolean
---@field prayer Prayer
---@field priority number
---@field activateTick gameTick
---@field expireTick gameTick

---@enum threatType
---| "'projectile'"
---| "'animation'"
---| "'conditional'"

---@alias gameTick number
---@alias projectileId number
---@alias npcId number
---@alias animationId number
--#endregion

local API = require("api")

---creates a new PrayerFlicker instance
---@param config PrayerFlickerConfig    
---@return PrayerFlicker
function PrayerFlicker.new(config)
    local self = setmetatable({}, PrayerFlicker)

    self.config = config or {
        defaultPrayer = {
            name = "Soul Split",
            buffId = 26033
        },
        prayers = {
            { name = "Soul Split", buffId = 26033 },
            { name = "Deflect Melee", buffId = 26040 },
            { name = "Deflect Magic", buffId = 26041 },
            { name = "Deflect Ranged", buffId = 26044 },
            { name = "Deflect Necromancy", buffId = 30745 }
        },
        projectiles = {},
        npcs = {},
        conditionals = {}
    }

    self.state = {
        activePrayer = { name = "", buffId = 0 },
        lastPrayerTick = 0,
        pendingActions = {}
    }

    return self
end

---gets the active prayer
---@return Prayer
function PrayerFlicker:_getCurrentPrayer()
    for _, prayer in ipairs(self.config.prayers) do
        if API.Buffbar_GetIDstatus(prayer.buffId, false).found then
            return prayer
        end
    end
    return {}
end

--#region threat checks
---checks if the projectile threat still exists
---@private
---@param projectileId projectileId
---@return boolean
function PrayerFlicker:_projectileExists(projectileId)
    local projectiles = API.GetAllObjArray1({projectileId}, 60, {5})
    return #projectiles > 0
end

---checks if the animation threat still exists
---@private
---@param npcId npcId
---@param animId animationId
---@return boolean
function PrayerFlicker:_animationExists(npcId, animId)
    local npcs = API.GetAllObjArray1({npcId}, 60, {1})
    for _, npc in ipairs(npcs) do
        if npc.Id and npc.Anim == animId then return true end
    end
    return false
end

---checks if the conditional threat still exists
---@private
---@param condFn fun(): boolean
---@return boolean
function PrayerFlicker:_conditionalThreatExists(condFn)
    return condFn()
end
--#endregion

--#region threat scans
---checks for projectile threats and adds them to self.state.pendingActions
---@private
---@param currentTick gameTick
function PrayerFlicker:_scanProjectiles(currentTick)
    for _, proj in ipairs(self.config.projectiles) do
        if not (proj.bypassCondition and proj.bypassCondition()) then
            if self:_projectileExists(proj.id) then
                table.insert(self.state.pendingActions, {
                    type = "projectile",
                    projId = proj.id,
                    prayer = proj.prayer,
                    priority = proj.priority or 0,
                    activateTick = currentTick + (proj.activationDelay or 0),
                    expireTick = currentTick + (proj.activationDelay or 0) + (proj.duration or 1)
                })
            end
        end
    end
end

---checks for npcs and animations and adds them to self.state.pendingActions
---@private
---@param currentTick gameTick
function PrayerFlicker:_scanAnimations(currentTick)
    for _, npc in ipairs(self.config.npcs) do
        local npcs = API.GetAllObjArray1({npc.id}, 60, {1})

        for _, npcObj in ipairs(npcs) do
            if npcObj.Id then
                for _, anim in ipairs(npc.animations) do
                    if npcObj.Anim == anim.animId then
                        table.insert(self.state.pendingActions, {
                            type = "animation",
                            npcId = npc.id,
                            animId = anim.animId,
                            prayer = anim.prayer,
                            priority = anim.priority or 0,
                            activateTick = currentTick + (anim.activationDelay or 0),
                            expireTick = currentTick + (anim.activationDelay or 0) + (anim.duration or 1)
                        })
                    end
                end
            end
        end
    end
end

---checks for conditional threats and adds them to self.state.pendingActions
---@private
---@param currentTick gameTick
function PrayerFlicker:_scanConditionals(currentTick)
    for _, cond in ipairs(self.config.conditionals) do
        if cond.condition() then
            table.insert(self.state.pendingActions, {
                type = "conditional",
                condition = cond.condition,
                prayer = cond.prayer,
                priority = cond.priority,
                activateTick = currentTick,
                expireTick = currentTick + 1
            })
        end
    end
end
--#endregion

---cleans up self.state.pendingActions, keeping only active threats
---@private
---@param currentTick gameTick
function PrayerFlicker:_cleanupPendingActions(currentTick)
    for i = #self.state.pendingActions, 1, -1 do
        local action = self.state.pendingActions[i]

        -- only remove if expired
        if action.expireTick <= currentTick then
            table.remove(self.state.pendingActions, i)

        -- remove if threat no longer exists and not active
        elseif action.activateTick > currentTick then
            if action.type == "projectile" and not self:_projectileExists(action.projId) then
                table.remove(self.state.pendingActions, i)
            elseif action.type == "animation" and not self:_animationExists(action.npcId, action.animId) then
                table.remove(self.state.pendingActions, i)
            elseif action.type == "condition" and not self:_conditionalThreatExists(action.condition) then
                table.remove(self.state.pendingActions, i)
            end
        end
    end
end

---determines the prayer to use based on threat priorities
---@private
---@param currentTick gameTick
---@return Prayer
function PrayerFlicker:_determineActivePrayer(currentTick)
    -- sort threats by priority (highest first)
    table.sort(self.state.pendingActions, function(a, b) 
        return (a.priority or 0) > (b.priority or 0)
    end)

    for _, action in ipairs(self.state.pendingActions) do
        if action.activateTick <= currentTick and action.expireTick > currentTick then
            return action.prayer
        end
    end

    return self.config.defaultPrayer
end

---@private
---@param prayer Prayer
---@return boolean
function PrayerFlicker:_switchPrayer(prayer)
    if not prayer then return false end
    local currentPrayer = self:_getCurrentPrayer()

    -- check if prayer in use
    if (self.state.activePrayer.buffId == prayer.buffId and self.state.lastPrayerTick + 4 > API.Get_tick()) or (currentPrayer.buffId == prayer.buffId) then
        return false
    end

    -- flick prayer
    local success = API.DoAction_Ability(
        prayer.name,
        1,
        API.OFF_ACT_GeneralInterface_route,
        true
    )

    if success then
        self.state.lastPrayerTick = API.Get_tick()
        self.state.activePrayer = prayer
    end

    return success
end

---disables active prayer or selected prayer
---@param prayer Prayer optional if you want to turn off a specific prayer
---@return boolean
function PrayerFlicker:deactivatePrayer(prayer)
    prayer = prayer or self:_getCurrentPrayer()
    if not prayer then return false end

    local success = API.DoAction_Ability(
        prayer.name,
        1,
        API.OFF_ACT_GeneralInterface_route,
        true
    )

    if success then
        self.state.lastPrayerTick = API.Get_tick()
        ---@diagnostic disable-next-line
        self.state.activePrayer = {}
    end

    return success
end

---updates PrayerFlicker instance
---@return boolean
function PrayerFlicker:update()
    local currentTick = API.Get_tick()
    local requiredPrayer = self:_determineActivePrayer(currentTick)

    self:_scanProjectiles(currentTick)
    self:_scanAnimations(currentTick)
    self:_cleanupPendingActions(currentTick)

    return self:_switchPrayer(requiredPrayer)
end

---can use with API.DrawTable(PrayerFlicker:tracking()) to check metrics
---@return table
function PrayerFlicker:tracking()
    local metrics = {
        {"Prayer Flicker:", ""},
        {"- Prayers:"},
        {"-- Active", self:_getCurrentPrayer() and self:_getCurrentPrayer().name or "None"},
        {"-- Last Used", self.state.activePrayer.name or "None"},
        {"-- Required", self:_determineActivePrayer(API.Get_tick()).name},
    }
    return metrics
end

return PrayerFlicker
