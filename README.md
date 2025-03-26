# Sonson's Prayer Flicker

## Overview
This class is designed for dynamic prayer switching based on various threat types.

## Features
- Automatic prayer switching based on multiple threat detection methods
- Dynamic threat prioritization
- Configurable prayer management for:
  - NPC Animations
  - Projectile Threats
  - Conditional Game States
- Customizable threat detection and prayer switching
- Minimal performance overhead
- Easy to configure for different boss fights and combat scenarios

## Changelog
### v1.0.0 - Initial Release
- Initial release of Sonson's Prayer Flicker
- Core prayer switching mechanics implemented
- Support for NPC, Projectile, and Conditional threat detection
- Configurable priority-based prayer management

## TODO
- Method to disable prayers
---
## Usage

### Save File
Make sure to save `prayer_flicker` in your `Lua_Scripts` folder.

### Import the Class
```lua
local PrayerFlicker = require("prayer_flicker")
```

### Configuration Details

#### A. Available Prayers
Define the prayers you'll use:
```lua
local prayers = {
    { name = "Soul Split", buffId = 26033 },
    { name = "Deflect Melee", buffId = 26040 },
    { name = "Deflect Magic", buffId = 26041 },
    { name = "Deflect Ranged", buffId = 26044 },
    { name = "Deflect Necromancy", buffId = 30745 }
}
```

#### B. NPCs and Animations
```lua
local npcs = {
    {
        id = 123,  -- npc id
        animations = {
            {
                animId = 456,         -- animation id
                prayer = {            -- prayer to switch to
                    name = "Deflect Magic", 
                    buffId = 26041
                },
                activationDelay = 1,  -- delay before prayer switch (in game ticks)
                duration = 3,         -- no. of game ticks to keep prayer active
                priority = 10         -- threat priority: bigger numbers get priority
            }
        }
    }
}
```

#### C. Projectiles Configuration
```lua
local projectiles = {
    {
        id = 789,                     -- projectile id
        prayer = {
            name = "Deflect Ranged", 
            buffId = 26044
        },
        bypassCondition = function()  -- optional: condition to ignore this projectile
            return isDivertActive() or isResonanceActive()
        end,
        activationDelay = 0,          -- delay before prayer switch (in game ticks)
        duration = 2,                 -- no. of game ticks to keep prayer active
        priority = 5                  -- threat priority: bigger numbers get priority
    }
}
```

#### D. Conditionals Configuration
```lua
local conditionals = {
    {
        condition = function()         -- custom condition function
            return isNearChaosTrap()
        end,
        prayer = {
            name = "Soul Split", 
            buffId = 26033
        },
        priority = 15                  -- threat priority: bigger numbers get priority
    }
}
```

### Create PrayerFlicker Instance
```lua
local config = {
    defaultPrayer = { name = "Soul Split", buffId = 26033 },
    prayers = prayers,
    projectiles = projectiles,
    npcs = npcs,
    conditionals = conditionals
}

local prayerFlicker = PrayerFlicker.new(config)
```

### Update in Main Loop
```lua
while API.Read_LoopyLoop() do
    if atBoss() then
        prayerFlicker:update() -- manages overhead prayers
    else
        prayerFlicker:deactivatePrayer()
    end

    API.RandomSleep2(100, 30, 20)
end
```

## Configuration Tips
- `prayer`: `name` must match ability bar & `buffId` must match buffBar id
- `bypassCondition`: Optional function to skip threat
- `activationDelay`: Syncs prayer with game mechanics
- `duration`: Controls threat active time
- `priority`: Determines prayer switching order
- It's okay to set `conditionals = {}` if you don't have any, same applies to `npcs` and `projectiles`
