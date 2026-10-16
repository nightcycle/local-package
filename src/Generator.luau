--!strict
-- Packages
local IndexUtil = require(script.Parent.Parent.IndexUtil)
-- Modules
local ENV = require(script.Parent.ENV)
-- Types
local Types = require(script.Parent.Types)
type Parameters = Types.GenerationFunctionParams<Types.PackageAttributes>
type Template = BasePart | Model
type Bounds = { Center: Vector3, Size: Vector3 }

-- Constants

-- Private Functions
local function getTemplates(source: Instance, parameters: Parameters): { Template }
	if source:IsA("BasePart") or source:IsA("Model") then
		return { source }
	end
	assert(source:IsA("Folder"), `unsupported source type: "{source.ClassName}"`)
	local templates: { Template } = {}
	for index, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Model") then
			table.insert(templates, descendant)
		end
		if index % parameters.Attributes.PauseInterval == 0 then
			parameters:Pause()
		end
	end
	-- Uniquely named templates retain their selection order when insertion order changes.
	table.sort(templates, function(a, b)
		local aPath, bPath = a:GetFullName(), b:GetFullName()
		return if aPath == bPath then a.ClassName < b.ClassName else aPath < bPath
	end)
	assert(#templates > 0, `source folder "{source:GetFullName()}" contains no BaseParts or Models`)
	return templates
end

local function getGrid(size: Vector3, count: number, parameters: Parameters): Vector3
	if parameters.Attributes.RandomPlacement == "Line" then
		return Vector3.new(count, 1, 1)
	end
	local x, y, z = 1, 1, 1
	local iterations = 0
	while x * y * z < count do
		local width = size.X / x
		local height = if parameters.Attributes.GeneratedAlignment == "Center" then size.Y / y else 0
		local depth = size.Z / z
		if width >= height and width >= depth then
			x += 1
		elseif height >= depth then
			y += 1
		else
			z += 1
		end
		iterations += 1
		if iterations % parameters.Attributes.PauseInterval == 0 then
			parameters:Pause()
		end
	end
	return Vector3.new(x, y, z)
end

-- Convert an oriented bounding box into bounds along the generation box's axes.
local function axisAlignedSize(frame: CFrame, size: Vector3): Vector3
	local right, up, look = frame.RightVector, frame.UpVector, frame.LookVector
	return Vector3.new(
		math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z,
		math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(look.Y) * size.Z,
		math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z
	)
end

local function getBounds(instance: Template): (Vector3, Vector3)
	local frame: CFrame
	local size: Vector3
	if instance:IsA("BasePart") then
		frame, size = instance.CFrame, instance.Size
	else
		frame, size = instance:GetBoundingBox()
	end
	return frame.Position, axisAlignedSize(frame, size)
end

local function prepareClone(template: Template, size: Vector3, rotation: CFrame, scaleType: Types.ScaleType): Template
	assert(template.Archivable, `template "{template:GetFullName()}" must be Archivable`)
	local instance = template:Clone()
	local pivotOffset = template:GetAttribute("PivotOffset")
	if typeof(pivotOffset) == "CFrame" then
		if instance:IsA("BasePart") then
			instance.PivotOffset = pivotOffset
		elseif instance.PrimaryPart then
			local primaryPart = instance.PrimaryPart
			primaryPart.PivotOffset = primaryPart.CFrame:ToObjectSpace(instance:GetPivot() * pivotOffset)
		else
			instance.WorldPivot = instance:GetPivot() * pivotOffset
		end
	end
	instance:PivotTo(rotation)
	if instance:IsA("BasePart") and scaleType == "Default" then
		instance.Size = size
	else
		local _, sourceSize = getBounds(instance)
		local sizeOverride = template:GetAttribute("Size")
		if typeof(sizeOverride) == "Vector3" then
			-- Model overrides describe dimensions at scale 1, as in the original generator.
			local templateScale = if instance:IsA("Model") then instance:GetScale() else 1
			sourceSize = axisAlignedSize(rotation, sizeOverride * templateScale)
		end
		assert(
			sourceSize.X > 0 and sourceSize.Y > 0 and sourceSize.Z > 0,
			`template "{template:GetFullName()}" must have positive dimensions`
		)
		local scale = if scaleType == "Height"
			then size.Y / sourceSize.Y
			else math.min(size.X / sourceSize.X, size.Y / sourceSize.Y, size.Z / sourceSize.Z)
		if instance:IsA("BasePart") then
			instance.Size *= scale
			local offset = instance.PivotOffset
			instance.PivotOffset = CFrame.new(offset.Position * scale) * offset.Rotation
		else
			instance:ScaleTo(math.max(ENV.MIN_MODEL_SCALE, instance:GetScale() * scale))
		end
		instance:PivotTo(rotation)
	end
	return instance
end

local function checkPadding(center: Vector3, size: Vector3, placed: { Bounds }, padding: number, parameters: Parameters)
	if padding <= 0 then
		return
	end
	for index, bounds in placed do
		local delta = center - bounds.Center
		local halfSize = (size + bounds.Size) / 2
		local gap = Vector3.new(
			math.max(0, math.abs(delta.X) - halfSize.X),
			math.max(0, math.abs(delta.Y) - halfSize.Y),
			math.max(0, math.abs(delta.Z) - halfSize.Z)
		)
		assert(gap.Magnitude + 0.0001 >= padding, "RandomPadding cannot be satisfied; reduce rotation/count or use Fit")
		if index % parameters.Attributes.PauseInterval == 0 then
			parameters:Pause()
		end
	end
end

-- Class
local Module = {}

function Module.new(): Types.GeneratorModuleDefinition<Types.PackageAttributes>
	return {
		Attributes = {
			SourcePath = ENV.SOURCE_PATH,
			SourcePathDelimiter = ENV.SOURCE_PATH_DELIMITER,
			SourceMaxYield = ENV.SOURCE_MAX_YIELD,
			PauseInterval = ENV.PAUSE_INTERVAL,
			GeneratedAlignment = ENV.GENERATED_ALIGNMENT,
			GeneratedScale = ENV.GENERATED_SCALE,
			GeneratedTags = ENV.GENERATED_TAGS,
			GeneratedCount = ENV.GENERATED_COUNT,
			RandomSeed = ENV.RANDOM_SEED,
			RandomPadding = ENV.RANDOM_PADDING,
			RandomRoll = ENV.RANDOM_ROLL,
			RandomPan = ENV.RANDOM_PAN,
			RandomTilt = ENV.RANDOM_TILT,
			RandomPlacement = ENV.RANDOM_PLACEMENT,
		},
		OnGenerate = function(parameters: Parameters, targetContainer: GeneratedFolder): ()
			targetContainer.Archivable = false
			local attributes = parameters.Attributes
			if attributes.SourcePath == "" then
				return
			end
			local size = parameters.Size
			assert(size.X > 0 and size.Y > 0 and size.Z > 0, "generation Size must have positive dimensions")
			assert(attributes.SourcePathDelimiter ~= "", "SourcePathDelimiter must not be empty")
			assert(attributes.SourceMaxYield >= 0, "SourceMaxYield must not be negative")
			local pauseInterval = attributes.PauseInterval
			assert(
				pauseInterval >= 1 and pauseInterval < math.huge and pauseInterval % 1 == 0,
				"PauseInterval must be a finite positive integer"
			)
			local minCount = math.ceil(attributes.GeneratedCount.Min)
			local maxCount = math.floor(attributes.GeneratedCount.Max)
			assert(minCount >= 0 and minCount <= maxCount, "GeneratedCount must contain a non-negative integer")
			assert(attributes.RandomPadding.Min >= 0, "RandomPadding must not be negative")
			local random = Random.new(attributes.RandomSeed)
			local count = random:NextInteger(minCount, maxCount)
			if count == 0 then
				return
			end
			local padding = random:NextNumber(attributes.RandomPadding.Min, attributes.RandomPadding.Max)
			local source =
				IndexUtil.waitForPath(attributes.SourcePath, attributes.SourceMaxYield, attributes.SourcePathDelimiter)
			assert(source, `failed to find template at path: {attributes.SourcePath}`)
			local templates = getTemplates(source, parameters)
			local grid = getGrid(size, count, parameters)
			local cellSize = (size - (grid - Vector3.one) * padding) / grid
			assert(
				cellSize.X > 0 and cellSize.Y > 0 and cellSize.Z > 0,
				"RandomPadding leaves no room for generated instances"
			)
			local cells: { number } = {}
			for index = 1, grid.X * grid.Y * grid.Z do
				cells[index] = index - 1
				if index % pauseInterval == 0 then
					parameters:Pause()
				end
			end
			if attributes.RandomPlacement == "Random" then
				random:Shuffle(cells)
			end
			local tags: { string } = {}
			for _, value in string.split(attributes.GeneratedTags, ",") do
				local tag = string.match(value, "^%s*(.-)%s*$")
				if tag and tag ~= "" then
					table.insert(tags, tag)
				end
			end

			local placed: { Bounds } = {}
			for index = 1, count do
				local template = templates[random:NextInteger(1, #templates)]
				local rotation = CFrame.Angles(
					math.rad(random:NextNumber(attributes.RandomRoll.Min, attributes.RandomRoll.Max)),
					math.rad(random:NextNumber(attributes.RandomPan.Min, attributes.RandomPan.Max)),
					math.rad(random:NextNumber(attributes.RandomTilt.Min, attributes.RandomTilt.Max))
				)
				local instance = prepareClone(template, cellSize, rotation, attributes.GeneratedScale)
				local boundsCenter, boundsSize = getBounds(instance)
				local cellIndex = cells[index]
				local coordinates = Vector3.new(
					cellIndex % grid.X,
					math.floor(cellIndex / (grid.X * grid.Z)),
					math.floor(cellIndex / grid.X) % grid.Z
				)
				local center = -size / 2 + cellSize / 2 + coordinates * (cellSize + Vector3.one * padding)
				if attributes.RandomPlacement == "Random" then
					local available = Vector3.new(
						math.max(0, cellSize.X - boundsSize.X),
						math.max(0, cellSize.Y - boundsSize.Y),
						math.max(0, cellSize.Z - boundsSize.Z)
					)
					center += Vector3.new(
						random:NextNumber(-0.5, 0.5) * available.X,
						random:NextNumber(-0.5, 0.5) * available.Y,
						random:NextNumber(-0.5, 0.5) * available.Z
					)
				end
				if attributes.GeneratedAlignment == "Floor" then
					center = Vector3.new(center.X, (boundsSize.Y - size.Y) / 2, center.Z)
				end
				checkPadding(center, boundsSize, placed, padding, parameters)
				table.insert(placed, { Center = center, Size = boundsSize })
				-- Align the geometry, including templates with an offset pivot.
				instance:PivotTo(CFrame.new(center - boundsCenter) * instance:GetPivot())
				for _, tag in tags do
					instance:AddTag(tag)
				end
				(instance :: Instance).Parent = targetContainer
				if index % pauseInterval == 0 then
					parameters:Pause()
				end
			end
		end,
	}
end

return Module
