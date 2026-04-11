local runtime = {}

runtime.activeConnections = {} :: { [string]: { activeConnection } }
runtime.activePends       = {} :: { [string]: any }
runtime.controls          = {} :: { [string]: any }

export type activeConnection = {
	id         : number,
	timestamp  : number,
	connection : RBXScriptConnection | ((...any) -> any),
	destroy    : () -> (),
}

local function assertName(name: string)
	assert(typeof(name) == "string" and #name > 0, "[Schema] name must be a non-empty string")
end

local nextId = 0
local function genId(): number
	nextId += 1
	return nextId
end

function runtime.registerConnection(name: string, connection: ((...any) -> any)): number
	assertName(name)

	if not runtime.activeConnections[name] then
		runtime.activeConnections[name] = {}
	end

	local id = genId()

	local entry: activeConnection = {
		id         = id,
		timestamp  = os.clock(),
		connection = connection,
		destroy    = function()
			if typeof(connection) == "RBXScriptConnection" then
				(connection :: RBXScriptConnection):Disconnect()
			end
		end,
	}

	table.insert(runtime.activeConnections[name], entry)
	return id
end

function runtime.removeConnection(name: string, id: number)
	assertName(name)

	local entries = runtime.activeConnections[name]
	if not entries then return end

	for i, entry in entries do
		if entry.id == id then
			entry.destroy()
			table.remove(entries, i)
			return
		end
	end
end

function runtime.getConnections(name: string): { activeConnection }?
	assertName(name)
	return runtime.activeConnections[name]
end

function runtime.destroyConnection(name: string)
	assertName(name)

	local entries = runtime.activeConnections[name]
	if not entries then return end

	for _, entry in entries do
		entry.destroy()
	end

	runtime.activeConnections[name] = nil
end

function runtime.destroyAllConnections()
	for _, entries in runtime.activeConnections do
		for _, entry in entries do
			entry.destroy()
		end
	end
	table.clear(runtime.activeConnections)
end

function runtime.registerPend(name: string, pend: any)
	assertName(name)
	runtime.activePends[name] = pend
end

function runtime.getPend(name: string): any?
	assertName(name)
	return runtime.activePends[name]
end

function runtime.resolvePend(name: string): any?
	assertName(name)

	local pend = runtime.activePends[name]
	if not pend then return nil end

	runtime.activePends[name] = nil
	return pend
end

function runtime.destroyAllPends()
	for _, pend in runtime.activePends do
		if typeof(pend) == "table" and typeof(pend.reject) == "function" then
			pend:reject("[Schema] destroyed")
		end
	end
	table.clear(runtime.activePends)
end

function runtime.registerControl(name: string, control: any)
	assertName(name)
	runtime.controls[name] = control
end

function runtime.getControl(name: string): any?
	assertName(name)
	return runtime.controls[name]
end

function runtime.getControls(): { [string]: any }
	return runtime.controls
end

function runtime.destroyControl(name: string)
	assertName(name)

	local control = runtime.controls[name]
	if not control then return end

	if typeof(control) == "table" and typeof(control.Destroy) == "function" then
		control:Destroy()
	end

	runtime.controls[name] = nil
end

function runtime.destroyAllControls()
	for _, control in runtime.controls do
		if typeof(control) == "table" and typeof(control.Destroy) == "function" then
			control:Destroy()
		end
	end
	table.clear(runtime.controls)
end

function runtime.destroyAll()
	runtime.destroyAllConnections()
	runtime.destroyAllPends()
	runtime.destroyAllControls()
end

return runtime
