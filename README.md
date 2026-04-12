# Schema - Roblox Networking Library

A secure, type-safe networking library for Roblox Studio that simplifies client-server communication with built-in validation, handshake security, and multiple transmission modes.

## Table of Contents

1. [Features](#features)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Core Concepts](#core-concepts)
5. [API Reference](#api-reference)
6. [Types](#types)
7. [Transmission Modes](#transmission-modes)
8. [Security & Handshake](#security--handshake)
9. [Advanced Usage](#advanced-usage)
10. [Examples](#examples)
11. [Contact](#contact)

---

## Features

-  **Secure Communication** - HMAC packet signing and token-based authentication
-  **Type Validation** - Runtime validation of data against defined schemas
-  **Multiple Modes** - Reliable, Unreliable, and Invoke (request-response) transmission
-  **Flexible Subscription System** - subscribe, like (one-time), and buffer modes
-  **Namespace Support** - Organize controls into logical groups with Parties
-  **Promise Support** - Built-in Promise integration for async operations
-  **Handshake System** - Secure client-server connection establishment

---

## Installation

1. Place the Schema module in your `ReplicatedStorage` or `ServerScriptService`
2. Require it in your scripts:

```lua
local Schema = require(game:GetService("ReplicatedStorage"):WaitForChild("Schema"))
```

---

## Quick Start

### Server-Side

```lua
local Schema = require(game:GetService("ReplicatedStorage"):WaitForChild("Schema"))

-- Define a control
Schema.define("PlayerGreeting", {
    playerName = "string",
    message = "string"
}, {mode = "reliable"})

-- Subscribe to messages
Schema.subscribe("PlayerGreeting", function(player, data)
    print(player.Name .. " says: " .. data.message)
end)

-- Send to a specific client
Schema.post("PlayerGreeting", player, {
    playerName = "Server",
    message = "Welcome!"
})

-- Broadcast to all clients
Schema.postAll("PlayerGreeting", {
    playerName = "Server",
    message = "Server is up!"
})
```

### Client-Side

```lua
local Schema = require(game:GetService("ReplicatedStorage"):WaitForChild("Schema"))

-- Define the same control
Schema.define("PlayerGreeting", {
    playerName = "string",
    message = "string"
}, {mode = "reliable"})

-- Subscribe to server messages
Schema.subscribe("PlayerGreeting", function(_, data)
    print(data.playerName .. " says: " .. data.message)
end)

-- Send to server
Schema.post("PlayerGreeting", {
    playerName = game.Players.LocalPlayer.Name,
    message = "Hello server!"
})
```

---

## Core Concepts

### Controls
Controls are named communication channels with defined data shapes and transmission modes. They must be defined before use.

### Shapes
A shape is a table defining the expected data structure. Values ending with `!` are required; values without are optional.

```lua
{
    name = "string!",      -- Required string
    age = "number",        -- Optional number
    active = "boolean!"    -- Required boolean
}
```

### Subscriptions
Functions that listen for incoming data. They return a Subscription object with an `Unsubscribe` method.

---

## API Reference

### Schema.define(name, shape, opts?)

Defines a new control with a name, shape, and optional configuration.

```lua
Schema.define("ChatMessage", {
    author = "string!",
    content = "string!",
    timestamp = "number"
}, {
    mode = "reliable",
    timeout = 5,
    retries = 2
})
```

**Parameters:**
- `name` (string): Unique control name
- `shape` (table): Data validation schema
- `opts` (ControlOptions, optional): Configuration options

---

### Schema.channel(name, shape, opts?)

Creates a Channel object that encapsulates define, subscribe, and post operations.

```lua
local chatChannel = Schema.channel("Chat", {message = "string!"}, {mode = "reliable"})

chatChannel.subscribe(function(sender, data)
    print(sender.Name .. ": " .. data.message)
end)

chatChannel.post(player, {message = "Hello!"})
```

**Returns:** Channel object with methods: `subscribe`, `post`, `postAll` (server), `validate`

---

### Schema.subscribe(name, callback)

Subscribes to a control and receives all messages.

```lua
local subscription = Schema.subscribe("PlayerJoined", function(player, data)
    print(player.Name .. " joined with level " .. data.level)
end)

-- Unsubscribe
subscription:Unsubscribe()
```

**Returns:** Subscription object with `Unsubscribe` method

---

### Schema.like(name, callback)

One-time subscription - triggers once then automatically unsubscribes.

```lua
Schema.like("FirstConnection", function(player, data)
    print("Got first connection from " .. player.Name)
    -- Automatically unsubscribed after this
end)
```

**Returns:** Subscription object

---

### Schema.buffer(name, callback)

Blocks execution until data is received, then returns the data.

```lua
local subscription = Schema.buffer("PlayerReady", function(player, data)
    print(player.Name .. " is ready")
end)

print(subscription.Data) -- Contains the received data
subscription:Unsubscribe()
```

**Returns:** Subscription object with `Data` field containing received data

---

### Schema.post(name, playerOrData, data?)

Sends data through a control. Behavior differs between server and client.

**Server:**
```lua
Schema.post("PlayerUpdate", player, {health = 100, mana = 50})
```

**Client:**
```lua
Schema.post("PlayerInput", {action = "jump", direction = Vector3.new(1, 0, 0)})
```

**Returns:** Thenable (for invoke mode) or nil

---

### Schema.postAll(name, data)

Broadcasts data to all connected clients. Server-only.

```lua
Schema.postAll("GameAnnouncement", {
    title = "Server Maintenance",
    duration = 3600
})
```

---

### Schema.validate(name, data)

Manually validates data against a control's shape.

```lua
local ok, err = Schema.validate("PlayerStats", {
    level = 50,
    experience = 10000
})

if not ok then
    warn("Validation failed: " .. err)
end
```

**Returns:** (boolean, string?) - success and optional error message

---

### Schema.party(namespace)

Creates a namespaced group of controls for organization.

```lua
local playerParty = Schema.party("player")

playerParty.define("level", {value = "number!"})
playerParty.subscribe("level", function(player, data)
    print("Level: " .. data.value)
end)

playerParty.post("level", player, {value = 50})
-- Control name becomes "player.level"
```

**Returns:** Party object with `define`, `channel`, `subscribe`, `post`, `postAll` (server)

---

### Schema.Handshake.bootstrap(success?, yield?)

Establishes secure connection between client and server using token-based authentication.

```lua
-- Server
Schema.Handshake.bootstrap(function()
    print("Client bootstrapped successfully")
end, true)

-- Client
Schema.Handshake.bootstrap(function()
    print("Connected to server securely")
end, true)
```

**Parameters:**
- `success` (function, optional): Callback on successful bootstrap
- `yield` (boolean, optional): If true, blocks until bootstrap completes

---

### Schema.Handshake.establish(opts)

Establishes handshake configuration with custom middleware.

```lua
Schema.Handshake.establish({
    timeout = 10,
    onFlag = function(player, reason)
        print("Player flagged: " .. reason)
    end
})
```

---

### Schema.Handshake.intercept(middleware)

Adds middleware to intercept and modify handshake packets.

```lua
Schema.Handshake.intercept(function(packet, next)
    local player = packet.player
    local data = packet.data
    local name = packet.name
    local drop = packet.drop

    print("Intercepted packet from " .. player.Name)
    if name == "DamagePlayer" then
        local damage = data.damage
        
        if damage >= 999 then -- Block suspicious values
            drop()
            return
        end
        
        next() -- Continue processing
end)
```

---

### Schema.Handshake.flag(player, reason)

Manually flag a player as suspicious or invalid.

```lua
Schema.Handshake.flag(player, "Attempted packet spoofing")
```

---

### Schema.load(controls)

Bulk-load multiple control definitions at once.

```lua
Schema.load({
    {Name = "ChatMessage", Shape = {text = "string!"}, Options = {mode = "reliable"}},
    {Name = "PlayerUpdate", Shape = {health = "number!"}, Options = {mode = "unreliable"}},
})
```

---

### Schema.destroy()

Cleans up all connections and resources.

```lua
Schema.destroy()
```

---

## Types

### Shape
```lua
type Shape = strict.Shape
-- Table mapping field names to type strings
```

### ControlOptions
```lua
type ControlOptions = {
    mode: ("reliable" | "unreliable" | "invoke")?,
    timeout: number?,
    retries: number?
}
```

### Control
```lua
type Control = {
    name: string,
    shape: Shape,
    mode: "reliable" | "unreliable" | "invoke",
    timeout: number?,
    retries: number?
}
```

### Thenable
```lua
type Thenable = {
    next: (fn: (data: any) -> ()) -> ()
}
```

### Subscription
```lua
type Subscription = {
    Unsubscribe: () -> (),
    Data: { [string]: any }?
}
```

### Channel
```lua
type Channel = {
    subscribe: (callback: (sender: Player?, data: { [string]: any }) -> any) -> Subscription,
    post: (playerOrData: any, data: { [string]: any }?) -> Thenable?,
    postAll: ((data: { [string]: any }) -> ())?,
    validate: (data: { [string]: any }) -> (boolean, string?)
}
```

### Party
```lua
type Party = {
    define: (name: string, shape: Shape, opts: ControlOptions?) -> (),
    channel: (name: string, shape: Shape, opts: ControlOptions?) -> Channel,
    subscribe: (name: string, callback: (sender: Player?, data: { [string]: any }) -> any) -> Subscription,
    post: (name: string, playerOrData: any, data: { [string]: any }?) -> Thenable?,
    postAll: ((name: string, data: { [string]: any }) -> ())?
}
```

---

## Transmission Modes

### Reliable
Standard RemoteEvent-like behavior. Messages are guaranteed to arrive in order and without loss.

```lua
Schema.define("ImportantUpdate", {data = "string!"}, {mode = "reliable"})
```

**Use for:** Game state updates, critical messages, anything that must arrive

---

### Unreliable
UnreliableRemoteEvent-like behavior. Messages may be lost but are sent faster.

```lua
Schema.define("PlayerPosition", {x = "number!", y = "number!"}, {mode = "unreliable"})
```

**Use for:** Frequent updates (positions, animations), where occasional loss is acceptable

---

### Invoke
RemoteFunction-like behavior. Waits for a response from the recipient.

```lua
Schema.define("GetPlayerStats", {playerName = "string!"}, {
    mode = "invoke",
    timeout = 5,
    retries = 2
})

Schema.post("GetPlayerStats", {playerName = "Player1"}).next(function(stats)
    print("Stats: " .. stats.level)
end)
```

**Use for:** Request-response patterns, asking for data, calling remote functions

---

## Security & Handshake

Schema uses a multi-layered security system:

1. **Handshake** - Initial secure connection between client and server
2. **Token Authentication** - Each client receives a unique token
3. **Session Keys** - HMAC signing using secure session keys
4. **Packet Signing** - Each packet is signed with HMAC-SHA256
5. **Sequence Numbers** - Prevent replay attacks

### Bootstrap Process

```lua
-- Must be called before posting signed packets
Schema.Handshake.bootstrap(function()
    print("Ready for secure communication")
end, true) -- true = yield until complete
```

---

## Advanced Usage

### Custom Middleware

```lua
Schema.Handshake.establish({
    onFlag = function(player, reason)
        print(player.Name .. " flagged for: " .. reason)
        -- Ban player, log, etc.
    end
})

Schema.Handshake.intercept(function(packet, player)
    if isPlayerBanned(player) then
        return nil -- Reject packet
    end
    return packet
end)
```

### Error Handling

```lua
local ok, err = Schema.validate("ChatMessage", {
    author = "Player1",
    content = "Hello"
})

if not ok then
    warn("Validation error: " .. err)
    return
end
```

### Promise Integration

```lua
-- Schema includes Promise support for complex async flows
local result = Schema.post("FetchData", {query = "user:1"})
result.next(function(data)
    print("Got data: " .. data.name)
end)
```

---

## Examples

### Example 1: Simple Chat System

```lua
-- Server
local Schema = require(game:GetService("ReplicatedStorage"):WaitForChild("Schema"))

Schema.define("SendMessage", {author = "string!", message = "string!"}, {mode = "reliable"})

Schema.subscribe("SendMessage", function(player, data)
    print(data.author .. ": " .. data.message)
    Schema.postAll("ReceiveMessage", data)
end)

-- Client
local Schema = require(game:GetService("ReplicatedStorage"):WaitForChild("Schema"))

Schema.define("SendMessage", {author = "string!", message = "string!"}, {mode = "reliable"})
Schema.define("ReceiveMessage", {author = "string!", message = "string!"}, {mode = "reliable"})

Schema.subscribe("ReceiveMessage", function(_, data)
    print("[" .. data.author .. "] " .. data.message)
end)

Schema.post("SendMessage", {
    author = game.Players.LocalPlayer.Name,
    message = "Hello everyone!"
})
```

### Example 2: Player Status Updates

```lua
-- Server
local playerParty = Schema.party("player")

playerParty.define("update", {
    health = "number!",
    mana = "number!",
    level = "number!"
}, {mode = "unreliable"})

game.Players.PlayerAdded:Connect(function(player)
    while player.Parent do
        playerParty.post("update", player, {
            health = 100,
            mana = 50,
            level = 1
        })
        task.wait(1)
    end
end)

-- Client
local playerParty = Schema.party("player")

playerParty.define("update", {
    health = "number!",
    mana = "number!",
    level = "number!"
}, {mode = "unreliable"})

playerParty.subscribe("update", function(_, data)
    print("Health: " .. data.health .. " | Mana: " .. data.mana .. " | Level: " .. data.level)
end)
```

### Example 3: Request-Response with Invoke

```lua
-- Server
Schema.define("GetUserInfo", {userID = "number!"}, {
    mode = "invoke",
    timeout = 5,
    retries = 1
})

Schema.subscribe("GetUserInfo", function(player, data)
    data.remit({
        name = "Player_" .. data.userID,
        joined = os.time()
    })
end)

-- Client
Schema.define("GetUserInfo", {userID = "number!"}, {
    mode = "invoke",
    timeout = 5,
    retries = 1
})

Schema.post("GetUserInfo", {userID = 123}).next(function(response)
    print("User: " .. response.name .. " (joined: " .. response.joined .. ")")
end)
```

---

## Contact Information

For suggestions, bug reports, or questions about Schema:

| Platform | Handle |
|----------|--------|
| Roblox | [Kr3ativeKrayon](https://www.roblox.com/users/1911367519/profile) |
| YouTube | [TotallyKr3ative](https://www.youtube.com/channel/UCpNZQoKVclQ74Pk5GmzdQDA) |
| X (Twitter) | [TotallyNotKr3ative](https://x.com/TheRealKr3ative) |
| Email | [TheRealKr3ative@gmail.com](mailto:TheRealKr3ative@gmail.com) |

---

**Last Updated:** April 12, 2026

---