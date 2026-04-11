local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local IS_SERVER = RunService:IsServer()
local runtime   = require(script.Parent.Parent.elements.runtime)
local strict    = require(script.Parent.Parent.elements.strict)

local handshake = {}

export type Context = {
	player : Player,
	name   : string,
	data   : { [string]: any },
	drop   : () -> (),
}

export type Middleware = (ctx: Context, next: () -> ()) -> ()

export type HandshakeConfig = {
	maxPayloadSize    : number?,
	rateLimitCount    : number?,
	rateLimitWindow   : number?, 
	floodThreshold    : number?,
	onFlag            : ((player: Player, reason: string) -> ())?,
}

local config: HandshakeConfig = {
	maxPayloadSize  = 1024,
	rateLimitCount  = 20,
	rateLimitWindow = 1,
	floodThreshold  = 5,
	onFlag          = nil,
}

local tokens: { [Player]: string } = {}
local hashMaps: { [Player]: { [string]: string } } = {}
local buckets: { [Player]: { [string]: { count: number, reset: number } } } = {}
local floodTrackers: { [Player]: { [string]: { posts: number, window: number } } } = {}
local middlewareStack: { Middleware } = {}

function handshake.establish(opts: HandshakeConfig)
	for k, v in opts do
		(config :: any)[k] = v
	end
end

function handshake.intercept(middleware: Middleware)
	assert(typeof(middleware) == "function", "[Schema] middleware must be a function")
	table.insert(middlewareStack, middleware)
end

local function flag(player: Player, reason: string)
	warn(`[Schema] flagged {player.Name}: {reason}`)
	if config.onFlag then
		task.spawn(config.onFlag, player, reason)
	end
end

function handshake.generateToken(player: Player): string
	local token = HttpService:GenerateGUID(false):gsub("-", "")
	tokens[player] = token
	return token
end

function handshake.getToken(player: Player): string?
	return tokens[player]
end

function handshake.revokeToken(player: Player)
	tokens[player] = nil
end

function handshake.buildHashMap(player: Player): { [string]: string }
	local map: { [string]: string } = {}
	local controls = runtime.getControls()

	for name in controls do
		local hash = HttpService:GenerateGUID(false):gsub("-", "")
		map[hash] = name
	end

	hashMaps[player] = map

	local inverted: { [string]: string } = {}
	for hash, name in map do
		inverted[name] = hash
	end
	return inverted
end

function handshake.resolveHash(player: Player, hash: string): string?
	local map = hashMaps[player]
	if not map then return nil end
	return map[hash]
end

function handshake.clearHashMap(player: Player)
	hashMaps[player] = nil
end

local function checkRateLimit(player: Player, name: string): boolean
	local now     = os.clock()
	local limit   = config.rateLimitCount  :: number
	local window  = config.rateLimitWindow :: number

	if not buckets[player] then
		buckets[player] = {}
	end

	local bucket = buckets[player][name]
	if not bucket or now >= bucket.reset then
		buckets[player][name] = { count = 1, reset = now + window }
		return true
	end

	bucket.count += 1
	if bucket.count > limit then
		return false
	end

	return true
end

local function checkFlood(player: Player, name: string): boolean
	local now       = os.clock()
	local threshold = config.floodThreshold :: number

	if not floodTrackers[player] then
		floodTrackers[player] = {}
	end

	local tracker = floodTrackers[player][name]
	if not tracker or now - tracker.window > 0.1 then
		floodTrackers[player][name] = { posts = 1, window = now }
		return true
	end

	tracker.posts += 1
	if tracker.posts > threshold then
		return false
	end

	return true
end

local function sanityCheck(ctx: Context): (boolean, string?)
	local player  = ctx.player
	local name    = ctx.name
	local data    = ctx.data
	local control = runtime.getControl(name)

	if not control then
		return false, `unknown control "{name}"`
	end

	local char = player.Character
	if not char or not char.Parent then
		return false, "player has no valid character"
	end

	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
	if ok then
		local size = #encoded
		if size > (config.maxPayloadSize :: number) then
			return false, `payload too large ({size} bytes)`
		end
	end

	local shape = control.shape
	for field in data do
		if shape[field] == nil then
			return false, `unknown field "{field}" in data`
		end
	end

	if not checkFlood(player, name) then
		return false, `flood detected on "{name}"`
	end

	return true
end

local function buildChain(ctx: Context, dispatch: () -> ()): () -> ()
	local index = #middlewareStack

	local function run(i: number): () -> ()
		if i == 0 then
			return dispatch
		end
		local mw = middlewareStack[i]
		return function()
			mw(ctx, run(i - 1))
		end
	end

	return run(index)
end

function handshake.process(
	player   : Player,
	hash     : string,
	token    : string,
	data     : any,
	dispatch : (ctx: Context) -> ()
)
	local dropped = false

	local ctx: Context = {
		player = player,
		name   = "",
		data   = data,
		drop   = function()
			dropped = true
		end,
	}

	local expected = tokens[player]
	if not expected or token ~= expected then
		flag(player, "invalid session token")
		return
	end

	local name = handshake.resolveHash(player, hash)
	if not name then
		flag(player, `unresolvable hash "{hash}"`)
		return
	end
	ctx.name = name

	local sane, reason = sanityCheck(ctx)
	if not sane then
		flag(player, reason :: string)
		return
	end

	if not checkRateLimit(player, name) then
		flag(player, `rate limit exceeded on "{name}"`)
		return
	end

	local chain = buildChain(ctx, function()
		if not dropped then
			dispatch(ctx)
		end
	end)

	chain()
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player)
		handshake.revokeToken(player)
		handshake.clearHashMap(player)
		buckets[player]       = nil
		floodTrackers[player] = nil
	end)
end

return handshake
