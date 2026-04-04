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
