local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local IS_SERVER = RunService:IsServer()

local runtime   = require(script.elements.runtime)
local strict    = require(script.elements.strict)
local events    = require(script.net.events)
local handshake = require(script.net.handshake)
local Promise   = require(script.net.promise)
local hmac      = require(script.net.crypto.hmac)

local Schema = {Handshake = {}, Events = events, Promise = Promise, Type = {}}

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
export type Thenable        = { next: (fn: (data: any) -> ()) -> () }
export type Subscription    = { Unsubscribe: () -> (), Data: { [string]: any }? }

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

local _clientToken:      string               = ""
local _clientSessionKey: string               = ""
local _clientHashMap:    { [string]: string } = {}
local _clientSeq:        number               = 0
local _clientReady:      boolean              = false

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

local function signedPacket(name: string, data: { [string]: any }): { [string]: any }
	assert(_clientReady, "[Schema] post called before Bootstrap completed")

	local hash = _clientHashMap[name]
	assert(hash, `[Schema] no session hash for control "{name}" — was it defined before Bootstrap?`)

	_clientSeq += 1

	local payload = tostring(_clientSeq) .. hash .. HttpService:JSONEncode(data or {})
	local sig     = hmac.sign(_clientSessionKey, payload)

	return {
		hash  = hash,
		token = _clientToken,
		seq   = _clientSeq,
		sig   = sig,
		data  = data,
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

	injectedData["remit"] = function(value: any)
		returnValue = value
		returned    = true
	end

	connections[1].connection(ctx.player, injectedData)

	if not returned then
		warn(`[Schema] invoke handler for "{ctx.name}" did not call data.remit()`)
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

	injectedData["remit"] = function(value: any)
		returnValue = value
		returned    = true
	end
	
	connections[1].connection(sender, injectedData)

	if not returned then
		warn(`[Schema] invoke handler for "{name}" did not call data.remit()`)
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
	local seq   = data.seq
	local sig   = data.sig
	local inner = data.data

	if typeof(hash) == "string" and typeof(token) == "string"
		and typeof(seq) == "number" and typeof(sig) == "string" then

		handshake.process(sender :: Player, hash, token, seq, sig, inner, function(ctx)
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

	local hash  = data.hash
	local token = data.token
	local seq   = data.seq
	local sig   = data.sig
	local inner = data.data

	if typeof(hash) == "string" and typeof(token) == "string"
		and typeof(seq) == "number" and typeof(sig) == "string" then

		local result = nil
		handshake.process(sender :: Player, hash, token, seq, sig, inner, function(ctx)
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

function Schema.channel(name: string, shape: Shape, opts: ControlOptions?): Channel
	Schema.define(name, shape, opts)

	local ch: Channel = {
		validate = function(data: { [string]: any }): (boolean, string?)
			return strict.validate(data, shape)
		end,

		subscribe = function(callback: (sender: Player?, data: { [string]: any }) -> any): Subscription
			return Schema.subscribe(name, callback)
		end,

		post = function(playerOrData: any, data: { [string]: any }?): Thenable?
			if IS_SERVER then
				assert(typeof(playerOrData) == "Instance" and playerOrData:IsA("Player"), "[Schema] expected a Player")
				return Schema.post(name, playerOrData :: Player, data :: { [string]: any })
			else
				return Schema.post(name, playerOrData :: { [string]: any })
			end
		end,
	}

	if IS_SERVER then
		ch.postAll = function(data: { [string]: any })
			Schema.postAll(name, data)
		end
	end

	return ch
end

function Schema.subscribe(name: string, callback: (sender: Player?, data: { [string]: any }) -> any): Subscription
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

function Schema.like(name: string, callback: (sender: Player?, data: { [string]: any }) -> any): Subscription
	assertName(name)
	assert(typeof(callback) == "function", "[Schema] callback must be a function")
	assert(runtime.getControl(name), `[Schema] cannot view undefined control "{name}"`)

	local id: number
	local wrapped = function(sender, data)
		if not data then return end
		callback(sender, data)
		runtime.removeConnection(name, id)
	end

	id = runtime.registerConnection(name, wrapped)

	return {
		Unsubscribe = function()
			runtime.removeConnection(name, id)
		end,
	}
end

function Schema.buffer(name: string, callback: (sender: Player?, data: { [string]: any }) -> any): Subscription
	assertName(name)
	assert(typeof(callback) == "function", "[Schema] callback must be a function")
	assert(runtime.getControl(name), `[Schema] cannot buffer undefined control "{name}"`)

	local thread     = coroutine.running()
	local hasResumed = false
	local id: number

	local wrapped = function(sender, data)
		if not data then return end
		callback(sender, data)
		if not hasResumed then
			hasResumed = true
			task.spawn(thread, data)
		end
	end

	id = runtime.registerConnection(name, wrapped)
	local receivedData = coroutine.yield()

	return {
		Unsubscribe = function()
			runtime.removeConnection(name, id)
		end,
		Data = receivedData,
	}
end

function Schema.validate(name: string, data: { [string]: any }): (boolean, string?)
	assertName(name)
	local control: Control? = runtime.getControl(name)
	assert(control, `[Schema] cannot validate undefined control "{name}"`)
	return strict.validate(data, control.shape)
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

		if control.mode == "invoke" then
			if _clientReady then
				local packet = signedPacket(name, data)
				local p = invokeWithOptions(events.invokeServer, { "__Schema_Packet", packet }, control)
				return makeThenable(p)
			else
				local p = invokeWithOptions(events.invokeServer, { name, data }, control)
				return makeThenable(p)
			end
		end

		if _clientReady then
			local packet = signedPacket(name, data)
			if control.mode == "unreliable" then
				events.postServerUnreliable("__Schema_Packet", packet)
			else
				events.postServer("__Schema_Packet", packet)
			end
		else
			if control.mode == "unreliable" then
				events.postServerUnreliable(name, data)
			else
				events.postServer(name, data)
			end
		end

		return nil
	end
end

function Schema.party(ns: string): Party
	assert(typeof(ns) == "string" and #ns > 0, "[Schema] party must be a non-empty string")

	local function prefixed(controlName: string): string
		return ns .. "." .. controlName
	end

	local party: Party = {
		define = function(name: string, shape: Shape, opts: ControlOptions?)
			Schema.define(prefixed(name), shape, opts)
		end,

		channel = function(name: string, shape: Shape, opts: ControlOptions?): Channel
			return Schema.channel(prefixed(name), shape, opts)
		end,

		subscribe = function(name: string, callback: (sender: Player?, data: { [string]: any }) -> any): Subscription
			return Schema.subscribe(prefixed(name), callback)
		end,

		post = function(name: string, playerOrData: any, data: { [string]: any }?): Thenable?
			if IS_SERVER then
				return Schema.post(prefixed(name), playerOrData :: Player, data :: { [string]: any })
			else
				return Schema.post(prefixed(name), playerOrData :: { [string]: any })
			end
		end,
	}

	if IS_SERVER then
		party.postAll = function(name: string, data: { [string]: any })
			Schema.postAll(prefixed(name), data)
		end
	end

	return party
end

function Schema.Handshake.establish(opts: HandshakeConfig)
	handshake.establish(opts)
end

function Schema.Handshake.bootstrap(success: (() -> ())?, yield: boolean?)
	if IS_SERVER then
		local thread = if yield then coroutine.running() else nil

		events.onReliable(function(player: Player, name: string, _data: any)
			if name ~= "__Schema_RequestBootstrap" then return end

			local token      = handshake.generateToken(player)
			local sessionKey = handshake.generateSessionKey(player)
			local hashMap    = handshake.buildHashMap(player)

			events.postClient(player, "__Schema_Bootstrap", {
				token      = token,
				sessionKey = sessionKey,
				hashMap    = hashMap,
			})
		end)
		
		events.onReliable(function(playera: Player, name: UIStroke, _data: any)
			if name ~= "__Schema_BootstrapEstablish" then return end
			
			if typeof(success) == "function" then
				success()
			end
			
			if thread then
				task.spawn(thread)
			end
		end)
		
		if yield and coroutine.running() then
			coroutine.yield()
		end
	else
		local thread = if yield then coroutine.running() else nil

		events.postServer("__Schema_RequestBootstrap", {})

		events.onReliable(function(_, name, data)
			if name ~= "__Schema_Bootstrap" then return end

			_clientToken      = data.token
			_clientSessionKey = data.sessionKey
			_clientHashMap    = data.hashMap
			_clientSeq        = 0
			_clientReady      = true

			events.postServer("__Schema_BootstrapEstablish", {})
			
			if typeof(success) == "function" then
				success()
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

function Schema.Handshake.intercept(middleware: Middleware)
	handshake.intercept(middleware)
end

function Schema.Handshake.flag(player: Player, reason: string)
	local cfg = (handshake :: any).config
	warn(`[Schema] manually flagged {player.Name}: {reason}`)
	if cfg and typeof(cfg.onFlag) == "function" then
		task.spawn(cfg.onFlag, player, reason)
	end
end

function Schema.load(controls: { { Name: string, Shape: Shape, Options: ControlOptions? } })
	assert(typeof(controls) == "table", "[Schema] load expects a table of control definitions")
	for _, entry in controls do
		assert(typeof(entry.Name)  == "string", "[Schema] each entry requires a Name")
		assert(typeof(entry.Shape) == "table",  "[Schema] each entry requires a Shape")
		Schema.define(entry.Name, entry.Shape, entry.Options)
	end
end

function Schema.destroy()
	runtime.destroyAll()
end

-- Luau primitives
function Schema.Type.string(nullable: boolean?)  return "string"  .. (nullable and "!" or "") end
function Schema.Type.number(nullable: boolean?)  return "number"  .. (nullable and "!" or "") end
function Schema.Type.float(nullable: boolean?)   return "float"   .. (nullable and "!" or "") end
function Schema.Type.int(nullable: boolean?)     return "int"     .. (nullable and "!" or "") end
function Schema.Type.boolean(nullable: boolean?) return "boolean" .. (nullable and "!" or "") end
function Schema.Type.table(nullable: boolean?)   return "table"   .. (nullable and "!" or "") end
function Schema.Type.any(nullable: boolean?)     return "any"     .. (nullable and "!" or "") end

function Schema.Type.Vector2(nullable: boolean?)       return "Vector2"       .. (nullable and "!" or "") end
function Schema.Type.Vector3(nullable: boolean?)       return "Vector3"       .. (nullable and "!" or "") end
function Schema.Type.Vector2int16(nullable: boolean?)  return "Vector2int16"  .. (nullable and "!" or "") end
function Schema.Type.Vector3int16(nullable: boolean?)  return "Vector3int16"  .. (nullable and "!" or "") end
function Schema.Type.CFrame(nullable: boolean?)        return "CFrame"        .. (nullable and "!" or "") end
function Schema.Type.Color3(nullable: boolean?)        return "Color3"        .. (nullable and "!" or "") end
function Schema.Type.UDim(nullable: boolean?)          return "UDim"          .. (nullable and "!" or "") end
function Schema.Type.UDim2(nullable: boolean?)         return "UDim2"         .. (nullable and "!" or "") end
function Schema.Type.BrickColor(nullable: boolean?)    return "BrickColor"    .. (nullable and "!" or "") end
function Schema.Type.Rect(nullable: boolean?)          return "Rect"          .. (nullable and "!" or "") end
function Schema.Type.Ray(nullable: boolean?)           return "Ray"           .. (nullable and "!" or "") end
function Schema.Type.Region3(nullable: boolean?)       return "Region3"       .. (nullable and "!" or "") end
function Schema.Type.TweenInfo(nullable: boolean?)     return "TweenInfo"     .. (nullable and "!" or "") end
function Schema.Type.NumberRange(nullable: boolean?)   return "NumberRange"   .. (nullable and "!" or "") end
function Schema.Type.ColorSequence(nullable: boolean?) return "ColorSequence" .. (nullable and "!" or "") end
function Schema.Type.NumberSequence(nullable: boolean?) return "NumberSequence" .. (nullable and "!" or "") end
function Schema.Type.EnumItem(nullable: boolean?)      return "EnumItem"      .. (nullable and "!" or "") end
function Schema.Type.Instance(nullable: boolean?)      return "Instance"      .. (nullable and "!" or "") end

function Schema.Type.Array(innerType: string, nullable: boolean?)
	return "Array(" .. innerType .. ")" .. (nullable and "!" or "")
end

function Schema.Type.Dict(keyType: string, valueType: string, nullable: boolean?)
	return "Dict(" .. keyType .. "," .. valueType .. ")" .. (nullable and "!" or "")
end

function Schema.Type.Tuple(...: string)
	local args = { ... }
	local nullable = false
	if typeof(args[#args]) == "boolean" then
		nullable = table.remove(args) :: any
	end
	return "Tuple(" .. table.concat(args, ",") .. ")" .. (nullable and "!" or "")
end

function Schema.Type.union(...: string)
	local args     = { ... }
	local nullable = false
	if typeof(args[#args]) == "boolean" then
		nullable = table.remove(args) :: any
	end
	return table.concat(args, "|") .. (nullable and "!" or "")
end

function Schema.Type.intersect(...: string)
	local args     = { ... }
	local nullable = false
	if typeof(args[#args]) == "boolean" then
		nullable = table.remove(args) :: any
	end
	return table.concat(args, "&") .. (nullable and "!" or "")
end

return Schema
