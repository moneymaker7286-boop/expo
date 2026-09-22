--!strict
--[[
	Minimal cleanup container. Every :Connect() in this project goes through a
	Trove, because undisconnected connections on per-part handlers are the
	most common memory leak in a Roblox place.
]]

local Trove = {}
Trove.__index = Trove

export type Trove = typeof(setmetatable({} :: { _items: { any } }, Trove))

function Trove.new(): Trove
	return setmetatable({ _items = {} }, Trove)
end

function Trove.Add<T>(self: Trove, item: T): T
	table.insert(self._items, item)
	return item
end

function Trove.Connect(self: Trove, signal: RBXScriptSignal, handler: (...any) -> ()): RBXScriptConnection
	return self:Add(signal:Connect(handler))
end

-- Cleans in reverse order, so teardown mirrors construction.
function Trove.Clean(self: Trove)
	for index = #self._items, 1, -1 do
		local item = self._items[index]
		self._items[index] = nil

		if typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
		elseif typeof(item) == "Instance" then
			item:Destroy()
		elseif type(item) == "function" then
			item()
		elseif type(item) == "table" then
			local destroy = (item :: any).Destroy or (item :: any).Clean
			if type(destroy) == "function" then
				destroy(item)
			end
		end
	end
end

Trove.Destroy = Trove.Clean

return Trove
