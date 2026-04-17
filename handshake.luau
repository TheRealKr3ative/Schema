local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local IS_SERVER = RunService:IsServer()
local runtime   = require(script.Parent.Parent.elements.runtime)
local hmac      = require(script.Parent.crypto.hmac)

local handshake = {}

export type Context = {
	player : Player,
	name   : string,
	data   : { [string]: any },
	drop   : () -> (),
}

export type Middleware = (ctx: Context, next: () -> ()) -> ()

export type HandshakeConfig = {
	maxPayloadSize  : number?,
	rateLimitCount  : number?,
	rateLimitWindow : number?,
	floodThreshold  : number?,
	onFlag          : ((player: Player, reason: string) -> ())?,
}

local config: HandshakeConfig = {
	maxPayloadSize  = 1024,
	rateLimitCount  = 20,
	rateLimitWindow = 1,
	floodThreshold  = 5,
	onFlag          = nil,
}

local tokens:       { [Player]: string }                                          = {}
local sessionKeys:  { [Player]: string }                                          = {}
local lastSeqs:     { [Player]: number }                                          = {}
local hashMaps:     { [Player]: { [string]: string } }                            = {}
local buckets:      { [Player]: { [string]: { count: number, reset: number } } }  = {}
local floodTrackers:{ [Player]: { [string]: { posts: number, window: number } } } = {}
local middlewareStack: { Middleware } = {}

local function flag(player: Player, reason: string)
	warn(`[Schema] flagged {player.Name}: {reason}`)
	if config.onFlag then
		task.spawn(config.onFlag, player, reason)
	end
end

local function checkRateLimit(player: Player, name: string): boolean
	local now    = os.clock()
	local limit  = config.rateLimitCount  :: number
	local window = config.rateLimitWindow :: number

	if not buckets[player] then buckets[player] = {} end

	local bucket = buckets[player][name]
	if not bucket or now >= bucket.reset then
		buckets[player][name] = { count = 1, reset = now + window }
		return true
	end

	bucket.count += 1
	return bucket.count <= limit
end

local function checkFlood(player: Player, name: string): boolean
	local now       = os.clock()
	local threshold = config.floodThreshold :: number

	if not floodTrackers[player] then floodTrackers[player] = {} end

	local tracker = floodTrackers[player][name]
	if not tracker or now - tracker.window > 0.1 then
		floodTrackers[player][name] = { posts = 1, window = now }
		return true
	end

	tracker.posts += 1
	return tracker.posts <= threshold
end

local function sanityCheck(ctx: Context): (boolean, string?)
	local control = runtime.getControl(ctx.name)
	if not control then
		return false, `unknown control "{ctx.name}"`
	end

	local char = ctx.player.Character
	if not char or not char.Parent then
		return false, "player has no valid character"
	end

	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, ctx.data)
	if ok and #encoded > (config.maxPayloadSize :: number) then
		return false, `payload too large ({#encoded} bytes)`
	end

	for field in ctx.data do
		if control.shape[field] == nil then
			return false, `unknown field "{field}" in data`
		end
	end

	if not checkFlood(ctx.player, ctx.name) then
		return false, `flood detected on "{ctx.name}"`
	end

	return true
end

local function buildChain(ctx: Context, dispatch: () -> ()): () -> ()
	local index = #middlewareStack

	local function run(i: number): () -> ()
		if i == 0 then return dispatch end
		local mw = middlewareStack[i]
		return function()
			mw(ctx, run(i - 1))
		end
	end

	return run(index)
end

function handshake.establish(opts: HandshakeConfig)
	for k, v in opts do
		(config :: any)[k] = v
	end
end

function handshake.intercept(middleware: Middleware)
	assert(typeof(middleware) == "function", "[Schema] middleware must be a function")
	table.insert(middlewareStack, middleware)
end


function handshake.generateToken(player: Player): string
	local token = HttpService:GenerateGUID(false):gsub("-", "")
	tokens[player] = token
	return token
end

function handshake.generateSessionKey(player: Player): string
	local key = HttpService:GenerateGUID(false):gsub("-", "")
		.. HttpService:GenerateGUID(false):gsub("-", "")
	sessionKeys[player] = key
	lastSeqs[player]    = -1
	return key
end

function handshake.getSessionKey(player: Player): string?
	return sessionKeys[player]
end

function handshake.getToken(player: Player): string?
	return tokens[player]
end

function handshake.revokeToken(player: Player)
	tokens[player]      = nil
	sessionKeys[player] = nil
	lastSeqs[player]    = nil
end

function handshake.buildHashMap(player: Player): { [string]: string }
	local map: { [string]: string } = {}
	local controls = runtime.getControls()

	for name in controls do
		local hash = HttpService:GenerateGUID(false):gsub("-", "")
		map[hash]  = name
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

function handshake.process(
	player   : Player,
	hash     : string,
	token    : string,
	seq      : number,
	sig      : string,
	data     : any,
	dispatch : (ctx: Context) -> ()
)
	local expectedToken = tokens[player]
	if not expectedToken or token ~= expectedToken then
		flag(player, "invalid session token")
		return
	end

	local lastSeq = lastSeqs[player] or -1
	if seq <= lastSeq then
		flag(player, `replay attack detected (seq {seq} <= last {lastSeq})`)
		return
	end

	local sessionKey = sessionKeys[player]
	if not sessionKey then
		flag(player, "no session key — not bootstrapped")
		return
	end

	local payload = tostring(seq) .. hash .. HttpService:JSONEncode(data or {})
	if not hmac.verify(sessionKey, payload, sig) then
		flag(player, "HMAC signature invalid")
		return
	end

	lastSeqs[player] = seq

	local name = handshake.resolveHash(player, hash)
	if not name then
		flag(player, `unresolvable hash "{hash}"`)
		return
	end

	local dropped = false
	local ctx: Context = {
		player = player,
		name   = name,
		data   = data,
		drop   = function()
			dropped = true
		end,
	}

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
		buckets[player]        = nil
		floodTrackers[player]  = nil
	end)
end

return handshake
