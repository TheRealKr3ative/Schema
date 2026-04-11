local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local instances = script.Parent.instances

local events = {}

local RELIABLE   = "__Schema"
local UNRELIABLE = "__Schema_Unreliable"
local INVOKE     = "__Schema_Invoke"

local reliable:   RemoteEvent
local unreliable: UnreliableRemoteEvent
local invoke:     RemoteFunction

events.__Internal = {
	["__Schema_RequestBootstrap"] = true,
	["__Schema_Bootstrap"]        = true,
}

events.BoostrapSettled = false

function events.init()
	if IS_SERVER then
		reliable = Instance.new("RemoteEvent")
		reliable.Name = RELIABLE
		reliable.Parent = instances

		unreliable = Instance.new("UnreliableRemoteEvent")
		unreliable.Name = UNRELIABLE
		unreliable.Parent = instances

		invoke = Instance.new("RemoteFunction")
		invoke.Name = INVOKE
		invoke.Parent = instances
	else
		reliable   = instances:WaitForChild(RELIABLE)   :: RemoteEvent
		unreliable = instances:WaitForChild(UNRELIABLE) :: UnreliableRemoteEvent
		invoke     = instances:WaitForChild(INVOKE)     :: RemoteFunction
	end
end

function events.postServer(name: string, data: { [string]: any })
	reliable:FireServer(name, data)
end

function events.postClient(player: Player, name: string, data: { [string]: any })
	reliable:FireClient(player, name, data)
end

function events.postAllClients(name: string, data: { [string]: any })
	reliable:FireAllClients(name, data)
end

function events.postServerUnreliable(name: string, data: { [string]: any })
	unreliable:FireServer(name, data)
end

function events.postClientUnreliable(player: Player, name: string, data: { [string]: any })
	unreliable:FireClient(player, name, data)
end

function events.postAllClientsUnreliable(name: string, data: { [string]: any })
	unreliable:FireAllClients(name, data)
end

function events.invokeServer(name: string, data: { [string]: any }): any
	return invoke:InvokeServer(name, data)
end

function events.invokeClient(player: Player, name: string, data: { [string]: any }): any
	return invoke:InvokeClient(player, name, data)
end

function events.onReliable(handler: (sender: Player?, name: string, data: { [string]: any }) -> ())
	if IS_SERVER then
		reliable.OnServerEvent:Connect(function(player, name, data)
			handler(player, name, data)
		end)
	else
		reliable.OnClientEvent:Connect(function(name, data)
			handler(nil, name, data)
		end)
	end
end

function events.onUnreliable(handler: (sender: Player?, name: string, data: { [string]: any }) -> ())
	if IS_SERVER then
		unreliable.OnServerEvent:Connect(function(player, name, data)
			handler(player, name, data)
		end)
	else
		unreliable.OnClientEvent:Connect(function(name, data)
			handler(nil, name, data)
		end)
	end
end

function events.onInvoke(handler: (sender: Player?, name: string, data: { [string]: any }) -> any)
	if IS_SERVER then
		invoke.OnServerInvoke = function(player, name, data)
			return handler(player, name, data)
		end
	else
		invoke.OnClientInvoke = function(name, data)
			return handler(nil, name, data)
		end
	end
end

return events
