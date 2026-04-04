# Welcome to Schema

## Table of Contents
* [Overview](#overview)
* [Types](#types)
* [Usage](#usage)
* [Contact](#contact)

---

## Overview
Schema is a network library designed to make networking as simple as possible while keeping a minimal level of security. It uses a handshake, token, and key system to ensure only your client and server communicate. It's also strictly typed, so any data sent is checked against your definitions first.

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
-- Defining a Control --
```lua
Schema.define("Example", {message = "string!"}, {})
```

Name: "Example"
Parameters: Use ! to allow a parameter to be nil (like string?).
Options:
* invoke: Behaves like a RemoteFunction.
* reliable: Standard RemoteEvent.
* unreliable: UnreliableRemoteEvent.

Firing & Listening
---

** Firing a control **

```lua
Schema.post("Example", {message = "Hello World!"})
```

** Listening for a control **

```lua
Schema.subscribe("Example", function(plr, data)
    print(data.message)
end)
```

** Handling "Invoke" (RemoteFunctions) **
If you use mode = "invoke", you need to use .next() to get return data:
```
Schema.post("Example", {message = "Hello!"}).next(function(data)
    print(data)
end)
```

** To return data back from a listener, use data.remit(): **

```lua
Schema.subscribe("Example", function(plr, data)
    if data.request == "Hello" then
        return data.remit("World")
    end
end)
```

## Contact
Feel free to reach out for suggestions or bug reports:
---
* Roblox: Kr3ativeKrayon

* Github: TheRealKr3ative

* Youtube: TotallyKr3ative

* Discord: @TheRealKr3ative / @TotallyNotKr3ative

* Email: TheRealKr3ative@gmail.com
