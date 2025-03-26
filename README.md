# Sonson's Prayer Flicker

## Overview
This class is designed for dynamic prayer switching based on various threat types.

## Features
- Automatic prayer switching
- Multiple threat detection types:
  - Projectiles
  - NPC Animations
  - Conditional Threats

## Usage

### Configuration Details

**A. NPCs and animations**
```lua
npcs = {
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
                duration = 3,         -- no. of game ticks to keep prayer active (useful if you have lingering damage i.e. zammy twinshot)
                priority = 10         -- threat priority: bigger numbers get priority
            }
        }
    }
}
```

**B. Projectiles Configuration**
```lua
projectiles = {
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
        duration = 2,                 -- no. of game ticks to keep prayer active (useful if you have lingering damage i.e. zammy twinshot) 
        priority = 5                  -- threat priority: bigger numbers get priority
    }
}
```

**C. Conditionals Configuration**
```lua
conditionals = {
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

### Configuration Tips
- `prayer`: 'name' needs to be an exact match to ability bar & 'buffId' needs to match the buffBar id
- `bypassCondition`: Optional function to skip threat
- `activationDelay`: Helps sync prayer with mechanics (useful if there's a delay between animation and hitsplat)
- `duration`: Controls how long threat is considered active
- `priority`: Determines which prayer gets switched to first

**Example Full Configuration**
```lua
local config = {
    defaultPrayer = { name = "Soul Split", buffId = 26033 },
    prayers = { ... },
    projectiles = { ... },
    npcs = { ... },
    conditionals = { ... }
}
```
---

### Initialization

```lua
local PrayerFlicker = require("Sonsons-Prayer-Flicker")

--create a new instance of PrayerFlicker 
local prayerFlicker = PrayerFlicker.new(config)
```

### Update Method
4. Call `update()` in your main script loop to manage prayer switching:
```lua
--example main loop
while API.Read_LoopyLoop() do
    if atBoss() then
        prayerFlicker:update() --updates your instance and manages your overhead prayers
    end
    API.RandomSleep2(100, 30, 20)
end
```
