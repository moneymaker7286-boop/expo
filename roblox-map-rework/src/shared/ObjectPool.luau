--!strict
--[[
	Instance pool. Reuse rather than Instance.new/Destroy per spawn.

	Hardened against two flaws in the reference implementation this is based on:
	  - a Destroyed instance handed back to the pool used to poison it, so the
	    next :Get() returned something already torn down;
	  - the pool had no upper bound, so a burst grew it permanently.
]]

local ObjectPool = {}
ObjectPool.__index = ObjectPool

export type ObjectPool = typeof(setmetatable(
	{} :: {
		_template: Instance,
		_available: { Instance },
		_reset: ((Instance) -> ())?,
		_maxIdle: number,
	},
	ObjectPool
))

local function isAlive(instance: Instance): boolean
	-- Destroy() locks the Parent property, so any assignment to it throws
	-- afterwards. Self-assignment is a no-op on a live instance and the only
	-- reliable probe for a destroyed one -- reading Parent cannot tell them
	-- apart, because a pooled instance is deliberately parentless too.
	return (pcall(function()
		instance.Parent = instance.Parent
	end))
end

function ObjectPool.new(template: Instance, initialSize: number, reset: ((Instance) -> ())?, maxIdle: number?): ObjectPool
	local self = setmetatable({
		_template = template,
		_available = {},
		_reset = reset,
		_maxIdle = maxIdle or math.max(initialSize * 2, 8),
	}, ObjectPool)

	for _ = 1, initialSize do
		local clone = template:Clone()
		table.insert(self._available, clone)
	end

	return self
end

function ObjectPool.Get(self: ObjectPool, parent: Instance?): Instance
	local instance = table.remove(self._available)

	while instance and not isAlive(instance) do
		instance = table.remove(self._available)
	end

	instance = instance or self._template:Clone()

	if self._reset then
		self._reset(instance)
	end
	instance.Parent = parent

	return instance
end

function ObjectPool.Return(self: ObjectPool, instance: Instance)
	if not isAlive(instance) then
		return
	end

	-- Past the idle cap, drop it instead of growing forever.
	if #self._available >= self._maxIdle then
		instance:Destroy()
		return
	end

	instance.Parent = nil
	table.insert(self._available, instance)
end

function ObjectPool.Destroy(self: ObjectPool)
	for _, instance in self._available do
		instance:Destroy()
	end
	table.clear(self._available)
end

return ObjectPool
