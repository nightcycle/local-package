--!strict
-- Services
local RunService = game:GetService("RunService")
-- Packages
local IndexUtil = require(script.Parent.Parent.IndexUtil)
-- Types
local Types = require(script.Parent.Types)
type GenerationFunctionParams<Attributes> = Types.GenerationFunctionParams<Attributes>
type GeneratorModuleDefinition<Attributes> = Types.GeneratorModuleDefinition<Attributes>
-- Constants

-- Class
local Module = {}

function Module.new()
	local DEFAULT_ATTRIBUTES: Types.PackageAttributes = {
		SourcePath = "",
		SourcePathDelimiter = ".",
		SourceMaxYield = 15,
		AlignType = "Floor",
		ScaleType = "Default",
	}
	local Generator: GeneratorModuleDefinition<Types.PackageAttributes> = {
		Attributes = DEFAULT_ATTRIBUTES,
		OnGenerate = function(parameters, targetContainer)
			targetContainer.Archivable = false
			if parameters.Attributes.SourcePath == nil then
				error("missing 'Path' attribute")
			end
			if parameters.Attributes.SourcePath:len() <= 0 then
				return
			end
			local template = IndexUtil.waitForPath(
				parameters.Attributes.SourcePath,
				parameters.Attributes.SourceMaxYield :: number,
				parameters.Attributes.SourcePathDelimiter
			)
			assert(template, `failed to find template at path: {parameters.Attributes.SourcePath}`)
			assert(
				template:IsA("PVInstance"),
				`template at path "{parameters.Attributes.SourcePath}" is not a PVInstance`
			)
			local sizeOverride = template:GetAttribute("Size") :: Vector3?
			local pivotOffsetOverride = template:GetAttribute("PivotOffset") :: CFrame?
			if template:IsA("BasePart") then
				local newInst = template:Clone()
				newInst.Size = parameters.Size

				if pivotOffsetOverride then
					newInst.PivotOffset = pivotOffsetOverride
				end
				newInst:PivotTo(CFrame.new(0, parameters.Size.Y / 2, 0))
				newInst.Parent = targetContainer
			elseif template:IsA("Model") then
				local newInst = template:Clone()
				local size = sizeOverride or (template:GetExtentsSize() / newInst:GetScale())

				if pivotOffsetOverride then
					newInst.WorldPivot = newInst:GetPivot() * pivotOffsetOverride
				end

				local xScale = parameters.Size.X / size.X
				local yScale = parameters.Size.Y / size.Y
				local zScale = parameters.Size.Z / size.Z
				newInst:ScaleTo(
					math.max(
						0.001,
						parameters.Attributes.GeneratedScale == "Height" and yScale or math.min(xScale, yScale, zScale)
					)
				)
				newInst:PivotTo(CFrame.new(0, parameters.Size.Y / 2, 0))
				newInst.Parent = targetContainer
			else
				error(`unsupported instance type: "{template.ClassName}"`)
			end
		end,
	}

	return Generator
end

return Module
