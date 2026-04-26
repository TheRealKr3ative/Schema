local sha256 = {}

local band    = bit32.band
local bxor    = bit32.bxor
local bnot    = bit32.bnot
local bor     = bit32.bor
local rshift  = bit32.rshift
local lshift  = bit32.lshift
local rrotate = bit32.rrotate

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
	0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
	0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
	0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
	0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
	0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
	0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
	0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
	0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function uint32(n: number): number
	return band(n, 0xFFFFFFFF)
end

local function bytesToUint32(b1: number, b2: number, b3: number, b4: number): number
	return bor(lshift(b1, 24), lshift(b2, 16), lshift(b3, 8), b4)
end

local function preprocess(msg: string): string
	local len  = #msg
	local bits = len * 8

	msg = msg .. "\x80"
	while #msg % 64 ~= 56 do
		msg = msg .. "\x00"
	end

	for i = 7, 0, -1 do
		msg = msg .. string.char(band(rshift(bits, i * 8), 0xFF))
	end

	return msg
end

function sha256.digest(msg: string): string
	msg = preprocess(msg)

	local h0 = 0x6a09e667
	local h1 = 0xbb67ae85
	local h2 = 0x3c6ef372
	local h3 = 0xa54ff53a
	local h4 = 0x510e527f
	local h5 = 0x9b05688c
	local h6 = 0x1f83d9ab
	local h7 = 0x5be0cd19

	for i = 1, #msg, 64 do
		local w = {}

		for j = 0, 15 do
			local o = i + j * 4
			w[j] = bytesToUint32(
				string.byte(msg, o),
				string.byte(msg, o + 1),
				string.byte(msg, o + 2),
				string.byte(msg, o + 3)
			)
		end

		for j = 16, 63 do
			local s0 = bxor(rrotate(w[j-15], 7), rrotate(w[j-15], 18), rshift(w[j-15], 3))
			local s1 = bxor(rrotate(w[j-2], 17), rrotate(w[j-2], 19),  rshift(w[j-2], 10))
			w[j] = uint32(w[j-16] + s0 + w[j-7] + s1)
		end

		local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7

		for j = 0, 63 do
			local S1   = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
			local ch   = bxor(band(e, f), band(bnot(e), g))
			local tmp1 = uint32(h + S1 + ch + K[j+1] + w[j])
			local S0   = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
			local maj  = bxor(band(a, b), band(a, c), band(b, c))
			local tmp2 = uint32(S0 + maj)

			h = g; g = f; f = e
			e = uint32(d + tmp1)
			d = c; c = b; b = a
			a = uint32(tmp1 + tmp2)
		end

		h0 = uint32(h0 + a)
		h1 = uint32(h1 + b)
		h2 = uint32(h2 + c)
		h3 = uint32(h3 + d)
		h4 = uint32(h4 + e)
		h5 = uint32(h5 + f)
		h6 = uint32(h6 + g)
		h7 = uint32(h7 + h)
	end

	return string.format(
		"%08x%08x%08x%08x%08x%08x%08x%08x",
		h0, h1, h2, h3, h4, h5, h6, h7
	)
end

return sha256
