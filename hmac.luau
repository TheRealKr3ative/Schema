local sha256 = require(script.Parent.sha256)

local hmac = {}

local BLOCK_SIZE = 64

local function padKey(key: string): string
	if #key > BLOCK_SIZE then
		local hex = sha256.digest(key)
		local bin = ""
		for i = 1, #hex, 2 do
			bin = bin .. string.char(tonumber(hex:sub(i, i+1), 16))
		end
		key = bin
	end
	while #key < BLOCK_SIZE do
		key = key .. "\x00"
	end
	return key
end

local function xorKey(key: string, byte: number): string
	local result = ""
	for i = 1, #key do
		result = result .. string.char(bit32.bxor(string.byte(key, i), byte))
	end
	return result
end

function hmac.sign(key: string, message: string): string
	key = padKey(key)

	local ipad = xorKey(key, 0x36)
	local opad = xorKey(key, 0x5C)

	local innerHex = sha256.digest(ipad .. message)
	local innerBin = ""
	for i = 1, #innerHex, 2 do
		innerBin = innerBin .. string.char(tonumber(innerHex:sub(i, i+1), 16))
	end

	return sha256.digest(opad .. innerBin)
end

function hmac.verify(key: string, message: string, expected: string): boolean
	local actual = hmac.sign(key, message)
	if #actual ~= #expected then return false end

	-- constant-time comparison
	local diff = 0
	for i = 1, #actual do
		diff = bit32.bor(diff, bit32.bxor(string.byte(actual, i), string.byte(expected, i)))
	end

	return diff == 0
end

return hmac
