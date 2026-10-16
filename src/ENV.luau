--!strict
-- Services
-- Packages
-- Modules
-- Types
type Env = {
	PAUSE_INTERVAL: number,
	MIN_MODEL_SCALE: number,
	[any]: never,
}
-- Constants
local PREFIX = "__LOCALPACKAGE__"
-- Variables
-- References
-- Private Functions
-- Class
local DEFAULT_ENV: Env = {
	PAUSE_INTERVAL = 100,
	MIN_MODEL_SCALE = 0.001,
}
local out: Env = setmetatable({}, {
	__index = function(_, readableKey: string): any?
		local k = PREFIX .. readableKey
		local v = _G[k]
		local dV = rawget(DEFAULT_ENV, readableKey)
		if dV == nil then
			error(`Attempt to access undefined key "{readableKey}" in ENV`)
		end
		if typeof(v) == "string" then
			if typeof(dV) == "boolean" then
				if v == "true" then
					return true
				elseif v == "false" then
					return false
				else
					return dV
				end
			elseif typeof(dV) == "number" then
				local n = tonumber(v)
				if n ~= nil then
					return n
				else
					return dV
				end
			end
		end
		if v == nil then
			return dV
		else
			return v
		end
	end,
	__newindex = function(_, readableKey, v)
		local k = PREFIX .. readableKey
		assert(rawget(DEFAULT_ENV, readableKey) ~= nil, `Attempt to set undefined key "{readableKey}" in ENV`)
		_G[k] = v
	end,
}) :: any

return out :: Env
