--!strict
-- Services
-- Packages
-- Modules
-- Types
local Types = require(script.Parent.Types)
type Env = {
	PAUSE_INTERVAL: number,
	MIN_MODEL_SCALE: number,
	SOURCE_PATH: string,
	SOURCE_PATH_DELIMITER: string,
	SOURCE_MAX_YIELD: number,
	GENERATED_ALIGNMENT: Types.AlignType,
	GENERATED_SCALE: Types.ScaleType,
	GENERATED_TAGS: string,
	GENERATED_COUNT: NumberRange,
	RANDOM_SEED: number,
	RANDOM_PADDING: NumberRange,
	RANDOM_ROLL: NumberRange,
	RANDOM_PAN: NumberRange,
	RANDOM_TILT: NumberRange,
	RANDOM_PLACEMENT: Types.PlacementType,
	SMALL: number,
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
	SOURCE_PATH = "",
	SOURCE_PATH_DELIMITER = ".",
	SOURCE_MAX_YIELD = 15,
	GENERATED_ALIGNMENT = "Floor",
	GENERATED_SCALE = "Default",
	GENERATED_TAGS = "",
	GENERATED_COUNT = NumberRange.new(1),
	RANDOM_SEED = 0,
	RANDOM_PADDING = NumberRange.new(0),
	RANDOM_ROLL = NumberRange.new(0),
	RANDOM_PAN = NumberRange.new(0),
	RANDOM_TILT = NumberRange.new(0),
	RANDOM_PLACEMENT = "Grid",
	SMALL = 0.0001,
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
