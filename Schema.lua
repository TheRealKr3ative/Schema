local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local runtime   = require(script.elements.runtime)
local strict    = require(script.elements.strict)
local events    = require(script.net.events)
local handshake = require(script.net.handshake)
local Promise   = require(script.net.promise)

local Schema = {}

export type Shape          = strict.Shape
export type ControlOptions = {
	mode    : ("reliable" | "unreliable" | "invoke")?,
	timeout : number?,
	retries : number?,
}
export type Control = {
	name    : string,
	shape   : Shape,
	mode    : "reliable" | "unreliable" | "invoke",
	timeout : number?,
	retries : number?,
}
export type Middleware      = handshake.Middleware
export type HandshakeConfig = handshake.HandshakeConfig
export type Connection      = { Unsubscribe: () -> () }
export type Thenable        = { next: (fn: (data: any) -> ()) -> () }
export type HandshakePin    = {
	post   : (data: { [string]: any }) -> Thenable,
	invoke : (data: { [string]: any }) -> Thenable,
}

export type party = {
	define: (name: string, shape: Shape, opts: ControlOptions?) -> (),
	post: (name: string, data: { [string]: any }) -> Thenable?,
	subscribe: (name: string, callback: (sender: Player?, data: { [string]: any }) -> any) -> Connection,
	postAll: (name: string, data: { [string]: any }) -> (),
}

local function assertName(name: string)
	assert(typeof(name) == "string" and #name > 0, "[Schema] name must be a non-empty string")
end

local function makeThenable(promise: any): Thenable
	return {
		next = function(fn: (data: any) -> ())
			promise:andThen(fn):catch(function(err)
				warn(`[Schema] unhandled error — {err}`)
			end)
		end,
	}
end

local function dispatch(ctx: handshake.Context)
	local connections = runtime.getConnections(ctx.name)
	if not connections then return end
	for _, entry in connections do
		task.spawn(entry.connection, ctx.player, ctx.data)
	end
end

local function dispatchInvoke(ctx: handshake.Context): any
	local connections = runtime.getConnections(ctx.name)
	if not connections or #connections == 0 then return nil end

	local returnValue = nil
	local returned    = false

	local injectedData = {}
	for k, v in ctx.data do
		injectedData[k] = v
	end

	injectedData["returns"] = function(value: any)
		returnValue = value
		returned    = true
	end

	connections[1].connection(ctx.player, injectedData)

	if not returned then
		warn(`[Schema] invoke handler for "{ctx.name}" did not call data.returns()`)
	end

	return returnValue
end

local function dispatchInvokeDirect(name: string, sender: Player?, data: { [string]: any }): any
	local connections = runtime.getConnections(name)
	if not connections or #connections == 0 then return nil end

	local returnValue = nil
	local returned    = false

	local injectedData = {}
	for k, v in data do
		injectedData[k] = v
	end
	
	injectedData["remit"] = function(v)
		returnValue = v
		returned    = true
	end

	connections[1].connection(sender, injectedData)

	if not returned then
		warn(`[Schema] invoke handler for "{name}" did not call data.returns()`)
	end

	return returnValue
end

local function handleIncoming(sender: Player?, name: string, data: any, mode: "reliable" | "unreliable")
	if events.__Internal[name] then return end

	if not IS_SERVER then
		local control: Control? = runtime.getControl(name)
		if not control or control.mode ~= mode then return end

		local ok, err = strict.validate(data, control.shape)
		if not ok then
			warn(`[Schema] validation failed for "{name}" — {err}`)
			return
		end

		local connections = runtime.getConnections(name)
		if not connections then return end
		for _, entry in connections do
			task.spawn(entry.connection, nil, data)
		end
		return
	end

	if typeof(data) ~= "table" then
		warn(`[Schema] malformed packet from {sender and sender.Name or "?"}`)
		return
	end

	local hash  = data.hash
	local token = data.token
	local inner = data.data

	if typeof(hash) == "string" and typeof(token) == "string" then
		handshake.process(sender :: Player, hash, token, inner, function(ctx)
			local control: Control? = runtime.getControl(ctx.name)
			if not control or control.mode ~= mode then return end
			dispatch(ctx)
		end)
		return
	end

	local control: Control? = runtime.getControl(name)
	if not control or control.mode ~= mode then return end

	local ok, err = strict.validate(data, control.shape)
	if not ok then
		warn(`[Schema] validation failed for "{name}" — {err}`)
		return
	end

	local connections = runtime.getConnections(name)
	if not connections then return end
	for _, entry in connections do
		task.spawn(entry.connection, sender, data)
	end
end

local function invokeWithOptions(invokeFn: (...any) -> any, args: { any }, control: Control): any
	local timeout = control.timeout
	local retries = control.retries or 0

	local function attempt(): any
		return Promise.new(function(resolve, reject)
			local ok, result = pcall(invokeFn, table.unpack(args))
			if ok then resolve(result) else reject(result) end
		end)
	end

	local function withTimeout(p: any): any
		if not timeout then return p end
		return Promise.race({
			p,
			Promise.delay(timeout):andThen(function()
				return Promise.reject(`[Schema] invoke timed out after {timeout}s`)
			end),
		})
	end

	local function withRetries(remaining: number): any
		local p = withTimeout(attempt())
		if remaining <= 0 then return p end
		return p:catch(function(err)
			warn(`[Schema] invoke failed, retrying ({remaining} left) — {err}`)
			return withRetries(remaining - 1)
		end)
	end

	return withRetries(retries)
end

events.init()

events.onReliable(function(sender, name, data)
	handleIncoming(sender, name, data, "reliable")
end)

events.onUnreliable(function(sender, name, data)
	handleIncoming(sender, name, data, "unreliable")
end)

events.onInvoke(function(sender, name, data)
	if events.__Internal[name] then return nil end

	if not IS_SERVER then
		local control: Control? = runtime.getControl(name)
		if not control or control.mode ~= "invoke" then return nil end

		local ok, err = strict.validate(data, control.shape)
		if not ok then
			warn(`[Schema] validation failed for invoke "{name}" — {err}`)
			return nil
		end

		return dispatchInvokeDirect(name, nil, data)
	end

	if typeof(data) ~= "table" then return nil end

	if typeof(data.hash) == "string" and typeof(data.token) == "string" then
		local result = nil
		handshake.process(sender :: Player, data.hash, data.token, data.data, function(ctx)
			local control: Control? = runtime.getControl(ctx.name)
			if not control or control.mode ~= "invoke" then return end
			result = dispatchInvoke(ctx)
		end)
		return result
	end

	local control: Control? = runtime.getControl(name)
	if not control or control.mode ~= "invoke" then return nil end

	local ok, err = strict.validate(data, control.shape)
	if not ok then
		warn(`[Schema] validation failed for invoke "{name}" — {err}`)
		return nil
	end

	return dispatchInvokeDirect(name, sender, data)
end)

function Schema.define(name: string, shape: Shape, opts: ControlOptions?)
	assertName(name)
	assert(typeof(shape) == "table", "[Schema] shape must be a table")
	assert(not runtime.getControl(name), `[Schema] control "{name}" is already defined`)

	local mode    = (opts and opts.mode) or "reliable"
	local timeout = opts and opts.timeout
	local retries = opts and opts.retries

	assert(
		mode == "reliable" or mode == "unreliable" or mode == "invoke",
		`[Schema] invalid mode "{mode}" for control "{name}"`
	)

	if timeout ~= nil then
		assert(mode == "invoke", "[Schema] timeout is only valid on invoke controls")
		assert(typeof(timeout) == "number" and timeout > 0, "[Schema] timeout must be a positive number")
	end

	if retries ~= nil then
		assert(mode == "invoke", "[Schema] retries is only valid on invoke controls")
		assert(typeof(retries) == "number" and retries >= 0, "[Schema] retries must be a non-negative number")
	end

	runtime.registerControl(name, {
		name    = name,
		shape   = shape,
		mode    = mode,
		timeout = timeout,
		retries = retries,
	} :: Control)
end

function Schema.subscribe(name: string, callback: (sender: Player?, data: { [string]: any }) -> any): Connection
	assertName(name)
	assert(typeof(callback) == "function", "[Schema] callback must be a function")
	assert(runtime.getControl(name), `[Schema] cannot subscribe to undefined control "{name}"`)

	local id = runtime.registerConnection(name, callback)

	return {
		Unsubscribe = function()
			runtime.removeConnection(name, id)
		end,
	}
end

if IS_SERVER then
	function Schema.post(name: string, player: Player, data: { [string]: any })
		assertName(name)
		assert(typeof(player) == "Instance" and player:IsA("Player"), "[Schema] expected a Player")

		local control: Control? = runtime.getControl(name)
		assert(control, `[Schema] unknown control "{name}"`)

		if control.mode == "reliable" then
			events.postClient(player, name, data)
		elseif control.mode == "unreliable" then
			events.postClientUnreliable(player, name, data)
		elseif control.mode == "invoke" then
			return invokeWithOptions(events.invokeClient, { player, name, data }, control)
		end
	end

	function Schema.postAll(name: string, data: { [string]: any })
		assertName(name)
		local control: Control? = runtime.getControl(name)
		assert(control, `[Schema] unknown control "{name}"`)
		assert(control.mode ~= "invoke", "[Schema] postAll is not supported for invoke controls")

		if control.mode == "reliable" then
			events.postAllClients(name, data)
		elseif control.mode == "unreliable" then
			events.postAllClientsUnreliable(name, data)
		end
	end
else
	function Schema.post(name: string, data: { [string]: any }): Thenable?
		assertName(name)
		local control: Control? = runtime.getControl(name)
		assert(control, `[Schema] unknown control "{name}"`)

		if control.mode == "reliable" then
			events.postServer(name, data)
			return nil
		elseif control.mode == "unreliable" then
			events.postServerUnreliable(name, data)
			return nil
		elseif control.mode == "invoke" then
			local p = invokeWithOptions(events.invokeServer, { name, data }, control)
			return makeThenable(p)
		end

		return nil
	end
end

function Schema.party(ns: string): party
	assert(typeof(ns) == "string" and #ns > 0, "[Schema] party must be a non-empty string")

	local function prefixed(controlName: string): string
		return ns .. "." .. controlName
	end

	local party = {}

	function party.define(name: string, shape: Shape, opts: ControlOptions?)
		Schema.define(prefixed(name), shape, opts)
	end

	function party.subscribe(name: string, callback: (sender: Player?, data: { [string]: any }) -> any): Connection
		return Schema.subscribe(prefixed(name), callback)
	end
	
	function party.post(name: string, data: { [string]: any }): Thenable?
		warn(runtime.getControls())
		warn(runtime.getControl(prefixed(name)))
		return Schema.post(prefixed(name), data)
	end
	
	if IS_SERVER then
		function party.postAll(name: string, data: { [string]: any })
			return Schema.postAll(prefixed(name), data)
		end
	end

	return party
end

function Schema.Bootstrap(success: ((control: { token: string, hash: { [string]: string } }) -> ())?, yield: boolean?)
	if IS_SERVER then
		events.onReliable(function(player: Player, name: string, _data: any)
			if name ~= "__Schema_RequestBootstrap" then return end

			local token   = handshake.generateToken(player)
			local hashMap = handshake.buildHashMap(player)

			events.postClient(player, "__Schema_Bootstrap", {
				token   = token,
				hashMap = hashMap,
			})
		end)
	else
		local thread = if yield then coroutine.running() else nil

		events.postServer("__Schema_RequestBootstrap", {})

		events.onReliable(function(_, name, data)
			if name ~= "__Schema_Bootstrap" then return end

			Schema.Handshake.Players[Players.LocalPlayer] = data

			if typeof(success) == "function" then
				success({ token = data.token, hash = data.hashMap })
			end

			if thread then
				task.spawn(thread)
			end
		end)

		if yield and coroutine.running() then
			coroutine.yield()
		end
	end
end

Schema.Handshake         = {}
Schema.Events            = events
Schema.Promise           = Promise
Schema.Handshake.Players = {}

function Schema.Handshake.establish(opts: HandshakeConfig)
	handshake.establish(opts)
end

function Schema.Handshake.intercept(middleware: Middleware)
	handshake.intercept(middleware)
end

function Schema.Handshake.pin(name: string): HandshakePin
	if IS_SERVER then
		warn("[Schema] cannot use Handshake.pin() on the server")
		return nil :: any
	end

	local player  = Players.LocalPlayer
	local control = Schema.Handshake.Players[player]
	assert(control, "[Schema] not bootstrapped yet")

	local token   = control.token
	local hashMap = control.hashMap

	return {
		post = function(data: { [string]: any }): Thenable
			local hash = hashMap[name]
			assert(hash, `[Schema] no hash mapped for control "{name}"`)

			local p = Promise.new(function(resolve, reject)
				local ok, result = pcall(events.postServer, "__Schema_Packet", {
					hash  = hash,
					token = token,
					data  = data,
				})
				if ok then resolve(result) else reject(result) end
			end)

			return makeThenable(p)
		end,

		invoke = function(data: { [string]: any }): Thenable
			local hash = hashMap[name]
			assert(hash, `[Schema] no hash mapped for control "{name}"`)

			local p = Promise.new(function(resolve, reject)
				local ok, result = pcall(events.invokeServer, "__Schema_Packet", {
					hash  = hash,
					token = token,
					data  = data,
				})
				if ok then resolve(result) else reject(result) end
			end)

			return makeThenable(p)
		end,
	}
end

function Schema.Handshake.flag(player: Player, reason: string)
	local cfg = (handshake :: any).config
	warn(`[Schema] manually flagged {player.Name}: {reason}`)
	if cfg and typeof(cfg.onFlag) == "function" then
		task.spawn(cfg.onFlag, player, reason)
	end
end

function Schema.destroy()
	runtime.destroyAll()
end

function Schema.load(t : {Control})
	for _, control : Control in t do
		local name = control.Name
		local shape = control.Shape
		local options = control.Options
		
		assert(typeof(control) == "table", `[Schema] invalid control: {name}`)
		assert(typeof(name) == "string", `[Schema] invalid control name: {name}`)
		assert(typeof(shape) == "table", `[Schema] invalid control shape: {name}`)
		assert(typeof(options) == "table" or options == nil, `[Schema] invalid control options: {name}`)
		
		Schema.define(name, shape, options)
	end
end

return Schema
