# Sonson's Prayer Flicker

## Overview
Flick your overhead prayers **automatically** based on real‑time projectile, animation, or custom conditions.
The module lets you describe every “threat” once, rank it by priority, and the class will handle the rest— from precise activation delays to safely de‑activating your prayer when the danger is gone.

## Features
- Single `threats` list – handles projectiles, animations & custom conditions

- Built‑in prayer enums – quick access to all overheads

- Priority system – higher number wins overlapping threats

- Per‑threat `delay` & `duration` – tick‑perfect timing

- `bypassCondition` hook – skip a threat when safe

- Debug table – `tracking()` for on‑screen status

## Installation

### Save File
Make sure to save `prayer_flicker` in your `Lua_Scripts` folder.

### Import the Class
```lua
local PrayerFlicker = require("prayer_flicker")
```

### Configuration Details

#### Build your configuration with all types of threats
```lua
local PRAYER_CONFIG = {
    defaultPrayer = PrayerFlicker.CURSES.SOUL_SPLIT,
    threats = {
        {
            name = "Standing on fire",
            type = "Conditional",
            priority = 10,
            prayer = PrayerFlicker.CURSES.DEFLECT_MAGIC,
            condition = function() return playerOnFire() end,
            duration = 1,
            delay = 0,
        },
        {
            name = "Ranged attacks",
            type = "Projectile",
            priority = 20,
            id = { 123, 456, 789 } -- multiple ids supported now
            prayer = PrayerFlicker.CURSES.DEFLECT_RANGED,
            duration = 2,
            delay = 1,
        },
        {
            name = "Boss magic attacks",
            type = "Animation",
            priority = 30,
            npcId = 12345
            id = { 111, 222, 333 } -- multiple animation ids supported now
            prayer = PrayerFlicker.CURSES.DEFLECT_MAGIC,
            duration = 0,
            delay = 2,
        },
    }
}
```

## Configuration Reference

|Field | Type | Description|
|--|--|--|
|`defaultPrayer` |  `Prayer` | Overhead to fall back on when no threats are active.|
|`threats` | `Threat[]` | List of every projectile / animation / conditional threat.|

### `Threat`

|Key | Type | Required | Notes|
|--|--|--|--|
|`name` | `string` | ✔ | Useful for debugging.|
|`type` | `"Projectile"` or `"Animation"` or `"Conditional"` | ✔ | Determines which fields below are relevant.|
|`prayer` | `Prayer` | ✔ | Prayer to activate for this threat.|
|`priority` | `integer` | ✔ | Higher number wins when threats overlap.|
|`delay` | `integer` | ✔ | Ticks to wait after detection before flicking.|
|`duration` | `integer` | ✔ | How long the threat stays active after the flick.|
|`id` | `integer` | ◐ | Projectile ID or animation ID, depending on type.|
|`npcId` | `integer` | ◐ | Animation threats only – NPC whose animation is checked.|
|`condition` | `function(): boolean` | ◐ | Conditional threats only – returns true when danger exists.|
|`range` | `integer` | ✖ | Radius to search for the projectile/animation (default 60).|
|`bypassCondition` | `function(): boolean` | ✖ | Return true to skip this threat on that tick (useful for Resonance, Reflect, etc.).|

### Create PrayerFlicker Instance
```lua
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

