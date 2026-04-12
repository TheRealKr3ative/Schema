# Welcome to Schema

## Table of Contents
* **[Overview](#overview)**
* **[Types](#types)**
* **[Usage](#usage)**
* **[Contact](#contact)**

---

## Overview
Schema is a networking library designed to make networking as simple as possible while keeping a median level of security. It uses a handshake, token, key,packet signing system to ensure only your client and server communicate. It's also strictly typed, so any data sent is checked against your definitions first.

---

## Types
* **Controls**: Data structures that describe Definitions. 
* **Definitions**: These are basically the events/interface you interact with.

---

## Usage

### Basics
First, require the module:
```lua
local Schema = require(path.to.Schema)
```
---
**Defining a Control**
```lua
Schema.define("Example", {message = "string!"}, {})
```

**Name:** ``"Example"``

**Parameters:** Use ``!`` to allow a parameter to be nil (like string?).

**Options:**
* invoke: Behaves like a RemoteFunction.
* reliable: Standard RemoteEvent.
* unreliable: UnreliableRemoteEvent.

**Example of modificaions**
```lua
    Schema.define("Exmaple", {message = "string!"}, {mode = "invoke"})
```

Firing & Listening
---

**Firing a control**

```lua
Schema.post("Example", {message = "Hello World!"})
```

**Listening for a control**

```lua
Schema.subscribe("Example", function(plr, data)
    print(data.message)
end)
```

**Handling "Invoke" (RemoteFunctions)**
If you use mode = "invoke", you need to use .next() to get return data:
```lua
Schema.post("Example", {message = "Hello!"}).next(function(data)
    print(data)
end)
```

**To return data back from a listener, use data.remit():**

```lua
Schema.subscribe("Example", function(plr, data)
    if data.request == "Hello" then
        return data.remit("World")
    end
end)
```

## Contact

Feel free to reach out for suggestions or bug reports.

| Platform | Handle |
|----------|--------|
| Roblox | [`Kr3ativeKrayon`](https://www.roblox.com/users/1911367519/profile) |
| YouTube | [`TotallyKr3ative`](https://www.youtube.com/channel/UCpNZQoKVclQ74Pk5GmzdQDA) |
| X(Twitter)| [`TotallyNotKr3ative`](https://x.com/TheRealKr3ative) |
| Email | [`TheRealKr3ative@gmail.com`](mailto:TheRealKr3ative@gmail.com) |