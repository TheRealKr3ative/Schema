local strict = {}

export type Shape    = { [string]: string }
export type Checker  = (value: any) -> (boolean, string?)

local CHECKERS: { [string]: (any) -> boolean } = {
	string         = function(v) return typeof(v) == "string"         end,
	number         = function(v) return typeof(v) == "number"         end,
	int            = function(v) return typeof(v) == "number" and v == math.floor(v) end,
	float          = function(v) return typeof(v) == "number"         end,
	boolean        = function(v) return typeof(v) == "boolean"        end,
	table          = function(v) return typeof(v) == "table"          end,
	any            = function()  return true                          end,

	Vector3        = function(v) return typeof(v) == "Vector3"        end,
	Vector2        = function(v) return typeof(v) == "Vector2"        end,
	CFrame         = function(v) return typeof(v) == "CFrame"         end,
	Color3         = function(v) return typeof(v) == "Color3"         end,
	Instance       = function(v) return typeof(v) == "Instance"       end,
	UDim2          = function(v) return typeof(v) == "UDim2"          end,
	UDim           = function(v) return typeof(v) == "UDim"           end,
	EnumItem       = function(v) return typeof(v) == "EnumItem"       end,
	BrickColor     = function(v) return typeof(v) == "BrickColor"     end,
	NumberSequence = function(v) return typeof(v) == "NumberSequence" end,
	ColorSequence  = function(v) return typeof(v) == "ColorSequence"  end,
	NumberRange    = function(v) return typeof(v) == "NumberRange"    end,
	Rect           = function(v) return typeof(v) == "Rect"           end,
	Region3        = function(v) return typeof(v) == "Region3"        end,
	Ray            = function(v) return typeof(v) == "Ray"            end,
	TweenInfo      = function(v) return typeof(v) == "TweenInfo"      end,
	Vector3int16   = function(v) return typeof(v) == "Vector3int16"   end,
	Vector2int16   = function(v) return typeof(v) == "Vector2int16"   end,
}

local function splitOn(s: string, char: string): { string }?
	local parts = {}
	local depth = 0
	local cur   = ""
	local found = false

	for i = 1, #s do
		local c = s:sub(i, i)
		if c == "(" then
			depth += 1
			cur ..= c
		elseif c == ")" then
			depth -= 1
			cur ..= c
		elseif c == char and depth == 0 then
			found = true
			table.insert(parts, cur:match("^%s*(.-)%s*$"))
			cur = ""
		else
			cur ..= c
		end
	end

	if #cur > 0 then
		table.insert(parts, cur:match("^%s*(.-)%s*$"))
	end

	return found and parts or nil
end

local function splitArgs(inner: string): { string }
	return splitOn(inner, ",") or { inner }
end

local parseType: (typeStr: string) -> Checker

parseType = function(typeStr: string): Checker
	local nullable = typeStr:sub(-1) == "!"
	local base     = nullable and typeStr:sub(1, -2) or typeStr

	local function wrap(checker: Checker): Checker
		if not nullable then return checker end
		return function(v)
			if v == nil then return true end
			return checker(v)
		end
	end

	local unionParts = splitOn(base, "|")
	if unionParts then
		local checkers = {}
		for _, t in unionParts do
			table.insert(checkers, parseType(t))
		end
		return wrap(function(v)
			for _, checker in checkers do
				local ok = checker(v)
				if ok then return true end
			end
			return false, `expected ({base}), got {typeof(v)}`
		end)
	end

	local intersectParts = splitOn(base, "&")
	if intersectParts then
		local checkers = {}
		for _, t in intersectParts do
			table.insert(checkers, parseType(t))
		end
		return wrap(function(v)
			for _, checker in checkers do
				local ok, err = checker(v)
				if not ok then
					return false, `intersection failed [{base}]: {err}`
				end
			end
			return true
		end)
	end

	local arrayInner = base:match("^Array%((.+)%)$")
	if arrayInner then
		local inner = parseType(arrayInner)
		return wrap(function(v)
			if typeof(v) ~= "table" then
				return false, `expected Array, got {typeof(v)}`
			end
			for i, item in ipairs(v) do
				local ok, err = inner(item)
				if not ok then
					return false, `Array[{i}]: {err}`
				end
			end
			return true
		end)
	end

	local dictInner = base:match("^Dict%((.+)%)$")
	if dictInner then
		local args = splitArgs(dictInner)
		assert(#args == 2, `[Schema] Dict requires exactly 2 type args, got {#args}`)
		local keyCheck = parseType(args[1])
		local valCheck = parseType(args[2])
		return wrap(function(v)
			if typeof(v) ~= "table" then
				return false, `expected Dict, got {typeof(v)}`
			end
			for k, val in pairs(v) do
				local ok, err = keyCheck(k)
				if not ok then
					return false, `Dict key: {err}`
				end
				ok, err = valCheck(val)
				if not ok then
					return false, `Dict value [{tostring(k)}]: {err}`
				end
			end
			return true
		end)
	end

	local tupleInner = base:match("^Tuple%((.+)%)$")
	if tupleInner then
		local args     = splitArgs(tupleInner)
		local checkers = {}
		for _, t in args do
			table.insert(checkers, parseType(t))
		end
		return wrap(function(v)
			if typeof(v) ~= "table" then
				return false, `expected Tuple, got {typeof(v)}`
			end
			for i, checker in checkers do
				local ok, err = checker(v[i])
				if not ok then
					return false, `Tuple[{i}]: {err}`
				end
			end
			return true
		end)
	end

	local checker = CHECKERS[base]
	assert(checker ~= nil, `[Schema] unknown type "{base}"`)

	return wrap(function(v)
		if not checker(v) then
			return false, `expected {base}, got {typeof(v)}`
		end
		return true
	end)
end

function strict.validate(data: any, shape: Shape): (boolean, string?)
	if typeof(data) ~= "table" then
		return false, "[Schema] data must be a table"
	end

	for field, typeStr in shape do
		local nullable = typeStr:sub(-1) == "!"
		local value    = data[field]

		if value == nil then
			if not nullable then
				return false, `[Schema] missing required field "{field}"`
			end
			continue
		end

		local checker    = parseType(typeStr)
		local ok, err    = checker(value)
		if not ok then
			return false, `[Schema] field "{field}": {err}`
		end
	end

	return true
end

function strict.assertShape(data: any, shape: Shape)
	local ok, err = strict.validate(data, shape)
	assert(ok, err)
end

function strict.parseType(typeStr: string): Checker
	return parseType(typeStr)
end

return strict
