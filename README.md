
# Schema — Roblox Networking Library

![Static Badge](https://img.shields.io/badge/build-v2.0.0--beta-black)
![Static Badge](https://img.shields.io/badge/stability-stable-green)

A type-safe networking library for Roblox. Clean API for defining channels, validating payloads, and handling client-server communication across reliable, unreliable, and invoke modes.

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [Type System](#type-system)
- [API Reference](#api-reference)
- [Transmission Modes](#transmission-modes)
- [Handshake](#handshake)
- [Advanced Usage](#advanced-usage)
- [Examples](#examples)
- [Contact](#contact)

---

## Features

- **Handshake Layer** -- optional session bootstrap for packet signing and replay protection
- **Type Validation** -- Runtime shape validation with a rich type factory system
- **Multiple Modes** -- Reliable, Unreliable, and Invoke (request-response)
- **Channel Objects** -- Encapsulated define + subscribe + post in one object
- **Flexible Subscriptions** -- `subscribe`, `like` (one-time), and `buffer` (yield-until-received)
- **Namespace Support** -- Organize controls into logical groups with Parties
- **Promise Integration** -- Async invoke flows via `.next()`


---

## Installation

Place the Schema module in `ReplicatedStorage` and require it:

```lua
local Schema = require(game:GetService("ReplicatedStorage"):WaitForChild("Schema"))
```

---

## Quick Start

**Server**

```lua
local Schema = require(game:GetService("ReplicatedStorage"):WaitForChild("Schema"))
local T      = Schema.Type

Schema.define("PlayerGreeting", {
    playerName = T.string(),
    message    = T.string(),
}, { mode = "reliable" })

Schema.subscribe("PlayerGreeting", function(player, data)
    print(player.Name .. " says: " .. data.message)
end)

Schema.post("PlayerGreeting", player, { playerName = "Server", message = "Welcome!" })
Schema.postAll("PlayerGreeting", { playerName = "Server", message = "Server is up!" })
```

**Client**

```lua
local Schema = require(game:GetService("ReplicatedStorage"):WaitForChild("Schema"))
local T      = Schema.Type

Schema.define("PlayerGreeting", {
    playerName = T.string(),
    message    = T.string(),
}, { mode = "reliable" })

Schema.subscribe("PlayerGreeting", function(_, data)
    print(data.playerName .. " says: " .. data.message)
end)

Schema.post("PlayerGreeting", {
    playerName = game.Players.LocalPlayer.Name,
    message    = "Hello server!",
})
```

---

## Core Concepts

### Controls
Named communication channels with a defined shape and transmission mode. Must be defined before use -- both server and client define the same control.

### Shapes
A table mapping field names to type strings. Required fields must be present and non-nil. Nullable fields (marked with `!`) may be nil.

```lua
{
    name   = T.string(),    -- required
    age    = T.number(true) -- nullable -- may be nil
}
```

### Subscriptions
Listeners that fire when data arrives on a control. Return a `Subscription` object with an `Unsubscribe` method.

---

## Type System

Schema provides 30+ type factory functions under `Schema.Type`. Every factory accepts an optional `nullable: boolean` parameter -- when `true`, a `!` is appended to the type string, allowing the field to be nil.

```lua
local T = Schema.Type

T.string()        -- "string"   -- required
T.string(true)    -- "string!"  -- nullable
```

### Primitives

| Factory | Type String |
|---|---|
| `T.string()` | `"string"` |
| `T.number()` | `"number"` |
| `T.float()` | `"float"` |
| `T.int()` | `"int"` |
| `T.boolean()` | `"boolean"` |
| `T.table()` | `"table"` |
| `T.any()` | `"any"` |

### Roblox Datatypes

| Factory | Type String |
|---|---|
| `T.Vector2()` | `"Vector2"` |
| `T.Vector3()` | `"Vector3"` |
| `T.CFrame()` | `"CFrame"` |
| `T.Color3()` | `"Color3"` |
| `T.UDim2()` | `"UDim2"` |
| `T.TweenInfo()` | `"TweenInfo"` |
| `T.EnumItem()` | `"EnumItem"` |
| `T.Instance()` | `"Instance"` |
| *(and 10 more)* | |

### Composite Types

```lua
-- Typed array
T.Array(T.string())                        -- "Array(string)"
T.Array(T.Vector3(), true)                 -- "Array(Vector3)!"  -- nullable

-- Typed dictionary
T.Dict(T.string(), T.number())             -- "Dict(string,number)"
T.Dict(T.string(), T.any(), true)          -- "Dict(string,any)!"

-- Variadic tuple
T.Tuple(T.string(), T.number())            -- "Tuple(string,number)"
T.Tuple(T.string(), T.number(), true)      -- "Tuple(string,number)!"
```

### Union and Intersection

**Union (`|`)** -- passes if the value satisfies any one of the listed types:

```lua
T.union(T.string(), T.number())            -- "string|number"
T.union(T.Vector3(), T.CFrame(), true)     -- "Vector3|CFrame!"  -- nullable
```

**Intersection (`&`)** -- passes only if the value satisfies every listed type:

```lua
T.intersect(T.table(), T.any())            -- "table&any"
T.intersect(T.string(), T.any(), true)     -- "string&any!"
```

Unions and intersections compose with all other types:

```lua
T.Array(T.union(T.string(), T.number()))           -- "Array(string|number)"
T.Dict(T.string(), T.union(T.Vector3(), T.CFrame())) -- "Dict(string,Vector3|CFrame)"
```

---

## API Reference

### `Schema.define(name, shape, opts?)`

Defines a new control.

```lua
Schema.define("HitData", {
    origin    = T.Vector3(),
    damage    = T.number(),
    tags      = T.Array(T.string()),
    meta      = T.Dict(T.string(), T.any(), true),
}, { mode = "reliable" })
```

| Parameter | Type | Description |
|---|---|---|
| `name` | `string` | Unique control name |
| `shape` | `table` | Field-to-type-string mapping |
| `opts` | `ControlOptions?` | Mode, timeout, retries |

---

### `Schema.channel(name, shape, opts?)`

Defines a control and returns a `Channel` object -- define, subscribe, and post all in one place.

```lua
local Chat = Schema.channel("Chat", { message = T.string() }, { mode = "reliable" })

Chat.subscribe(function(sender, data)
    print(sender.Name .. ": " .. data.message)
end)

Chat.post(player, { message = "Hello!" })     -- server
Chat.post({ message = "Hello!" })             -- client
Chat.postAll({ message = "Broadcast!" })      -- server only
```

| Method | Description |
|---|---|
| `subscribe(callback)` | Listen for incoming data |
| `post(playerOrData, data?)` | Send data |
| `postAll(data)` | Broadcast to all clients (server only) |
| `validate(data)` | Manually validate a payload |

---

### `Schema.subscribe(name, callback)`

Subscribes to all messages on a control. The callback receives `(sender: Player?, data: {})`.

On invoke channels, `data` contains a `remit` function -- call it to send a response back.

```lua
Schema.subscribe("GetStats", function(player, data)
    data.remit({ level = 50, xp = 1200 })
end)
```

**Returns:** `Subscription` -- call `subscription:Unsubscribe()` to disconnect.

---

### `Schema.like(name, callback)`

One-time subscription -- fires once then auto-disconnects.

```lua
Schema.like("ServerReady", function(_, data)
    print("Server came online at " .. data.timestamp)
end)
```

---

### `Schema.buffer(name, callback)`

Yields the current thread until a message is received, then resumes with the data.

```lua
local sub = Schema.buffer("PlayerReady", function(player, data)
    print(player.Name .. " is ready")
end)

print(sub.Data)    -- the received data
sub:Unsubscribe()
```

**Returns:** `Subscription` with a `Data` field containing the received payload.

---

### `Schema.post(name, playerOrData, data?)`

Sends data on a control.

```lua
-- Server -- requires a Player target
Schema.post("PlayerUpdate", player, { health = 100 })

-- Client -- no player argument
Schema.post("PlayerInput", { action = "jump" })
```

**Returns:** `Thenable?` for invoke-mode controls -- call `.next(fn)` to handle the response.

---

### `Schema.postAll(name, data)`

Broadcasts to all connected clients. Server-only. Not available on invoke controls.

```lua
Schema.postAll("GameAnnouncement", { message = "Round starting in 10s" })
```

---

### `Schema.validate(name, data)`

Manually validates a payload against a control's shape.

```lua
local ok, err = Schema.validate("HitData", { origin = Vector3.new(), damage = 25 })
if not ok then
    warn("Validation failed: " .. err)
end
```

**Returns:** `(boolean, string?)` -- success flag and optional error message.

---

### `Schema.party(namespace)`

Returns a namespaced Party object. All control names are prefixed with `namespace.` automatically.

```lua
local Player = Schema.party("player")

Player.define("update", { health = T.number() }, { mode = "unreliable" })
Player.subscribe("update", function(player, data) end)
Player.post("update", player, { health = 100 })
-- actual control name: "player.update"
```

**Party methods:** `define`, `channel`, `subscribe`, `post`, `postAll` (server)

---

### `Schema.load(controls)`

Bulk-defines multiple controls at once.

```lua
Schema.load({
    { Name = "Chat",   Shape = { text = T.string() },   Options = { mode = "reliable" } },
    { Name = "Move",   Shape = { pos  = T.Vector3() },  Options = { mode = "unreliable" } },
})
```

---

### `Schema.destroy()`

Cleans up all registered connections and controls.

---

## Transmission Modes

### `"reliable"`

Guaranteed delivery, ordered. Equivalent to `RemoteEvent`.

```lua
Schema.define("ImportantUpdate", { data = T.string() }, { mode = "reliable" })
```

Use for: game state, critical messages, anything that must arrive.

---

### `"unreliable"`

Fast, unordered, may drop. Equivalent to `UnreliableRemoteEvent`.

```lua
Schema.define("PlayerPosition", { pos = T.Vector3() }, { mode = "unreliable" })
```

Use for: high-frequency updates (positions, animations) where occasional loss is fine.

---

### `"invoke"`

Request-response. The sender awaits a reply via `.next()`. Equivalent to `RemoteFunction` but non-blocking and promise-based.

```lua
-- Server -- subscriber must call data.remit()
Schema.define("GetStats", { userId = T.number() }, { mode = "invoke", timeout = 5, retries = 1 })

Schema.subscribe("GetStats", function(player, data)
    data.remit({ level = 50, xp = 1200 })
end)

-- Client -- post returns a Thenable
Schema.post("GetStats", { userId = 123 }).next(function(stats)
    print("Level: " .. stats.level)
end)
```

| Option | Type | Description |
|---|---|---|
| `timeout` | `number` | Seconds before the invoke fails |
| `retries` | `number` | How many times to retry on failure |

---

## Handshake

Schema includes an optional handshake layer. Once bootstrapped, outgoing packets are signed and sequence-numbered. Call `Schema.Handshake.bootstrap()` on both server and client before posting if you want this active:


### `Schema.Handshake.bootstrap(success?, yield?)`

Call on both server and client before any posts. Optional -- only needed if you want packet signing active.

```lua
-- Server
Schema.Handshake.bootstrap(function()
    print("Bootstrap complete")
end, true)  -- true = yield until complete

-- Client
Schema.Handshake.bootstrap(function()
    print("Bootstrap complete")
end, true)
```

---

### `Schema.Handshake.establish(opts)`

Configure handshake behaviour and flag handling.

```lua
Schema.Handshake.establish({
    timeout = 10,
    onFlag  = function(player, reason)
        warn(player.Name .. " flagged: " .. reason)
    end,
})
```

---

### `Schema.Handshake.intercept(middleware)`

Add middleware to inspect or drop incoming packets before they reach subscribers.

```lua
Schema.Handshake.intercept(function(packet, next)
    local data = packet.data

    if packet.name == "DamagePlayer" and data.damage >= 999 then
        packet.drop()   -- reject
        return
    end

    next()  -- allow
end)
```

---

### `Schema.Handshake.flag(player, reason)`

Manually flag a player. Triggers the `onFlag` callback if configured.

```lua
Schema.Handshake.flag(player, "Attempted packet spoofing")
```

---

## Advanced Usage

### Channel pattern (recommended)

Using `Schema.channel` keeps definitions and usage colocated and avoids repeated name strings:

```lua
local Damage = Schema.channel("Damage", {
    amount = T.number(),
    origin = T.Vector3(),
    tags   = T.Array(T.string(), true),
}, { mode = "reliable" })

-- Server
Damage.subscribe(function(player, data)
    applyDamage(player, data.amount)
end)

-- Server broadcast
Damage.post(player, { amount = 25, origin = hit, tags = { "fire" } })
```

### Nullable fields

```lua
Schema.define("PlayerState", {
    health   = T.number(),           -- required
    shield   = T.number(true),       -- optional -- can be nil
    position = T.Vector3(),          -- required
    status   = T.union(T.string(), T.number(), true),  -- string, number, or nil
})
```

### Invoke with error handling

```lua
-- Server
Schema.subscribe("FetchData", function(player, data)
    local result = fetchFromStore(data.key)
    if not result then
        data.remit({ ok = false, error = "Not found" })
        return
    end
    data.remit({ ok = true, value = result })
end)

-- Client
Schema.post("FetchData", { key = "coins" }).next(function(res)
    if res.ok then
        print("Value: " .. res.value)
    else
        warn("Error: " .. res.error)
    end
end)
```

---

## Examples

### Chat System

```lua
-- Server
local Chat = Schema.channel("Chat.Send",    { author = T.string(), message = T.string() }, { mode = "reliable" })
local Recv = Schema.channel("Chat.Receive", { author = T.string(), message = T.string() }, { mode = "reliable" })

Chat.subscribe(function(player, data)
    Recv.postAll({ author = player.Name, message = data.message })
end)

-- Client
local Chat = Schema.channel("Chat.Send",    { author = T.string(), message = T.string() }, { mode = "reliable" })
local Recv = Schema.channel("Chat.Receive", { author = T.string(), message = T.string() }, { mode = "reliable" })

Recv.subscribe(function(_, data)
    print("[" .. data.author .. "] " .. data.message)
end)

Chat.post({ author = game.Players.LocalPlayer.Name, message = "Hello!" })
```

---

### Frequent Position Updates

```lua
-- Server
local Pos = Schema.channel("Player.Position", { pos = T.Vector3(), vel = T.Vector3(true) }, { mode = "unreliable" })

Pos.subscribe(function(player, data)
    updatePlayerPosition(player, data.pos)
end)

-- Client
local Pos = Schema.channel("Player.Position", { pos = T.Vector3(), vel = T.Vector3(true) }, { mode = "unreliable" })

game:GetService("RunService").Heartbeat:Connect(function()
    local root = game.Players.LocalPlayer.Character and
                 game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root then
        Pos.post({ pos = root.Position, vel = root.AssemblyLinearVelocity })
    end
end)
```

---

### Request-Response (Invoke)

```lua
-- Server
Schema.define("GetUserInfo", { userId = T.number() }, { mode = "invoke", timeout = 5, retries = 1 })

Schema.subscribe("GetUserInfo", function(player, data)
    data.remit({
        name   = "Player_" .. data.userId,
        joined = os.time(),
    })
end)

-- Client
Schema.define("GetUserInfo", { userId = T.number() }, { mode = "invoke", timeout = 5, retries = 1 })

Schema.post("GetUserInfo", { userId = 123 }).next(function(info)
    print("Name: " .. info.name .. " joined: " .. info.joined)
end)
```

---

## Exported Types

```lua
export type Shape = { [string]: string }

export type ControlOptions = {
    mode    : ("reliable" | "unreliable" | "invoke")?,
    timeout : number?,
    retries : number?,
}

export type Thenable = {
    next : (fn: (data: any) -> ()) -> ()
}

export type Subscription = {
    Unsubscribe : () -> (),
    Data        : { [string]: any }?,
}

export type Channel = {
    subscribe : (callback: (sender: Player?, data: { [string]: any }) -> any) -> Subscription,
    post      : (playerOrData: any, data: { [string]: any }?) -> Thenable?,
    postAll   : ((data: { [string]: any }) -> ())?,
    validate  : (data: { [string]: any }) -> (boolean, string?),
}

export type Party = {
    define    : (name: string, shape: Shape, opts: ControlOptions?) -> (),
    channel   : (name: string, shape: Shape, opts: ControlOptions?) -> Channel,
    subscribe : (name: string, callback: (sender: Player?, data: { [string]: any }) -> any) -> Subscription,
    post      : (name: string, playerOrData: any, data: { [string]: any }?) -> Thenable?,
    postAll   : ((name: string, data: { [string]: any }) -> ())?,
}
```

---

## Contact

| Platform | Handle |
|---|---|
| Roblox | [Kr3ativeKrayon](https://www.roblox.com/users/1911367519/profile) |
| YouTube | [TotallyKr3ative](https://www.youtube.com/channel/UCpNZQoKVclQ74Pk5GmzdQDA) |
| X (Twitter) | [TotallyNotKr3ative](https://x.com/TheRealKr3ative) |
| Email | [TheRealKr3ative@gmail.com](mailto:TheRealKr3ative@gmail.com) |

---

*Last Updated: April 27, 2026*

---