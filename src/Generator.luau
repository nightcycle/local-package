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
type CallbackFn<V> = (
	inst: Template,
	parameters: Types.GenerationFunctionParams<V & Types.PackageAttributes>,
	targetContainer: GeneratedFolder
) -> ()
type TemplateGroup = { Template: Template, Parameters: Parameters, Count: number }
type ExtraAttributes = { [string]: any }

-- Constants
-- Private Functions
local function parseTags(value: string): { string }
	local tags: { string } = {}
	for _, entry in string.split(value, ",") do
		local tag = string.match(entry, "^%s*(.-)%s*$")
		if tag and tag ~= "" then
			table.insert(tags, tag)
		end
	end
	return tags
end

local function getRangeAttribute(template: Template, name: string, fallback: NumberRange): NumberRange
	local value: unknown = template:GetAttribute(name)
	if value == nil then
		return fallback
	end
	assert(typeof(value) == "NumberRange", `template "{template:GetFullName()}" attribute {name} must be a NumberRange`)
	return value
end

local function resolveTemplateAttributes(
	template: Template,
	attributes: Types.PackageAttributes,
	extraAttributes: ExtraAttributes
): Types.PackageAttributes
	local resolved = table.clone(attributes)
	local pauseInterval: unknown = template:GetAttribute("PauseInterval")
	if pauseInterval ~= nil then
		assert(
			typeof(pauseInterval) == "number",
			`template "{template:GetFullName()}" attribute PauseInterval must be a number`
		)
		resolved.PauseInterval = pauseInterval
	end
	local alignment: unknown = template:GetAttribute("GeneratedAlignment")
	if alignment ~= nil then
		assert(
			alignment == "Center" or alignment == "Floor",
			`template "{template:GetFullName()}" attribute GeneratedAlignment must be Center or Floor`
		)
		resolved.GeneratedAlignment = alignment
	end
	local scale: unknown = template:GetAttribute("GeneratedScale")
	if scale ~= nil then
		assert(
			scale == "Default" or scale == "Fit" or scale == "Height",
			`template "{template:GetFullName()}" attribute GeneratedScale must be Default, Fit, or Height`
		)
		resolved.GeneratedScale = scale
	end
	resolved.GeneratedCount = getRangeAttribute(template, "GeneratedCount", attributes.GeneratedCount)
	resolved.RandomRoll = getRangeAttribute(template, "RandomRoll", attributes.RandomRoll)
	resolved.RandomPan = getRangeAttribute(template, "RandomPan", attributes.RandomPan)
	resolved.RandomTilt = getRangeAttribute(template, "RandomTilt", attributes.RandomTilt)
	for k, v in extraAttributes do
		local tempV = template:GetAttribute(k)
		if type(tempV) == "nil" then
			resolved[k] = v
			continue
		elseif type(tempV) == type(v) then
			resolved[k] = tempV
		end
	end
	return resolved
end

local function withAttributes(parameters: Parameters, attributes: Types.PackageAttributes): Parameters
	return {
		Attributes = attributes,
		Size = parameters.Size,
		Pause = function(_self: Parameters)
			parameters:Pause()
		end,
	}
end

local function validatePauseInterval(attributes: Types.PackageAttributes)
	local interval = attributes.PauseInterval
	assert(
		interval >= 1 and interval < math.huge and interval % 1 == 0,
		"PauseInterval must be a finite positive integer"
	)
end

local function sampleCount(range: NumberRange, random: Random): number
	local minimum, maximum = math.ceil(range.Min), math.floor(range.Max)
	assert(minimum >= 0 and minimum <= maximum, "GeneratedCount must contain a non-negative integer")
	return random:NextInteger(minimum, maximum)
end

local function getTemplates(source: Instance, parameters: Parameters): { Template }
	if source:IsA("BasePart") or source:IsA("Model") then
		return { source }
	end
	assert(source:IsA("Folder"), `unsupported source type: "{source.ClassName}"`)
	local excludedTags = parseTags(parameters.Attributes.GeneratedExcludedTags)
	local function isExcluded(candidate: Instance): boolean
		for _, tag in excludedTags do
			if candidate:HasTag(tag) then
				return true
			end
		end
		return false
	end
	local templates: { Template } = {}
	local function gatherTemplates(root: Instance)
		for _, v in root:GetChildren() do
			if isExcluded(v) then
				continue
			end
			if v:IsA("Model") or v:IsA("BasePart") then
				table.insert(templates, v)
			else
				gatherTemplates(v)
			end
		end
	end
	gatherTemplates(source)

	-- Uniquely named templates retain their selection order when insertion order changes.
	table.sort(templates, function(a, b)
		local aPath, bPath = a:GetFullName(), b:GetFullName()
		return if aPath == bPath then a.ClassName < b.ClassName else aPath < bPath
	end)

	assert(
		#templates > 0,
		`source folder "{source:GetFullName()}" contains no eligible BaseParts or Models after applying GeneratedExcludedTags`
	)

	return templates
end

local function getCopies(
	source: Instance,
	parameters: Parameters,
	random: Random,
	extraAttributes: ExtraAttributes
): ({ TemplateGroup }, Parameters)
	local templates = getTemplates(source, parameters)
	local groups: { TemplateGroup } = {}
	local selected: { TemplateGroup } = {}
	local layoutParameters = parameters
	if not source:IsA("Folder") then
		local template = templates[1]
		layoutParameters =
			withAttributes(parameters, resolveTemplateAttributes(template, parameters.Attributes, extraAttributes))
		validatePauseInterval(layoutParameters.Attributes)
		table.insert(groups, {
			Template = template,
			Parameters = layoutParameters,
			Count = sampleCount(layoutParameters.Attributes.GeneratedCount, random),
		})
	else
		validatePauseInterval(parameters.Attributes)
		local count = sampleCount(parameters.Attributes.GeneratedCount, random)
		local byTemplate: { [Instance]: TemplateGroup } = {}
		local function getGroup(template: Template): TemplateGroup
			local existing = byTemplate[template]
			if existing then
				return existing
			end
			local scoped =
				withAttributes(parameters, resolveTemplateAttributes(template, parameters.Attributes, extraAttributes))
			validatePauseInterval(scoped.Attributes)
			local group: TemplateGroup = { Template = template, Parameters = scoped, Count = 0 }
			byTemplate[template] = group
			table.insert(groups, group)
			return group
		end
		for index = 1, count do
			local template = templates[random:NextInteger(1, #templates)]
			local group = getGroup(template)
			group.Count += 1
			table.insert(selected, group)
			if index % parameters.Attributes.PauseInterval == 0 then
				parameters:Pause()
			end
		end
		for _, group in groups do
			if group.Template:GetAttribute("GeneratedCount") ~= nil then
				group.Count = sampleCount(group.Parameters.Attributes.GeneratedCount, random)
			end
		end
	end

	local copies: { TemplateGroup } = {}
	-- Preserve selection order where possible, then append extra copies requested by a template.
	for index, group in selected do
		if group.Count > 0 then
			table.insert(copies, group)
			group.Count -= 1
		end
		if index % parameters.Attributes.PauseInterval == 0 then
			parameters:Pause()
		end
	end
	for _, group in groups do
		for index = 1, group.Count do
			table.insert(copies, group)
			if index % group.Parameters.Attributes.PauseInterval == 0 then
				group.Parameters:Pause()
			end
		end
	end
	return copies, layoutParameters
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
			instance:ScaleTo(math.max(ENV.DEFAULT_MIN_MODEL_SCALE, instance:GetScale() * scale))
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
		assert(
			gap.Magnitude + ENV.DEFAULT_SMALL >= padding,
			"RandomPadding cannot be satisfied; reduce rotation/count or use Fit"
		)
		if index % parameters.Attributes.PauseInterval == 0 then
			parameters:Pause()
		end
	end
end

function newGenerator(
	extraDefaultAttributes: ExtraAttributes?,
	fn: CallbackFn<ExtraAttributes>?
): Types.GeneratorModuleDefinition<Types.PackageAttributes>
	local defaultAttributes: Types.PackageAttributes = {
		SourcePath = ENV.DEFAULT_SOURCE_PATH,
		SourcePathDelimiter = ENV.DEFAULT_SOURCE_PATH_DELIMITER,
		SourceMaxYield = ENV.DEFAULT_SOURCE_MAX_YIELD,
		PauseInterval = ENV.DEFAULT_PAUSE_INTERVAL,
		GeneratedAlignment = ENV.DEFAULT_GENERATED_ALIGNMENT,
		GeneratedScale = ENV.DEFAULT_GENERATED_SCALE,
		GeneratedTags = ENV.DEFAULT_GENERATED_TAGS,
		GeneratedExcludedTags = ENV.DEFAULT_GENERATED_EXCLUDED_TAGS,
		GeneratedCount = ENV.DEFAULT_GENERATED_COUNT,
		RandomSeed = ENV.DEFAULT_RANDOM_SEED,
		RandomPadding = ENV.DEFAULT_RANDOM_PADDING,
		RandomRoll = ENV.DEFAULT_RANDOM_ROLL,
		RandomPan = ENV.DEFAULT_RANDOM_PAN,
		RandomTilt = ENV.DEFAULT_RANDOM_TILT,
		RandomPlacement = ENV.DEFAULT_RANDOM_PLACEMENT,
	}
	if extraDefaultAttributes then
		for k, v in extraDefaultAttributes do
			if defaultAttributes[k] == nil then
				defaultAttributes[k] = v
			end
		end
	end
	return {
		Attributes = defaultAttributes,
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
			assert(attributes.RandomPadding.Min >= 0, "RandomPadding must not be negative")
			local random = Random.new(attributes.RandomSeed)
			local source =
				IndexUtil.waitForPath(attributes.SourcePath, attributes.SourceMaxYield, attributes.SourcePathDelimiter)
			assert(source, `failed to find template at path: {attributes.SourcePath}`)
			local extraAttributes = {}
			if extraDefaultAttributes then
				for k, v in extraDefaultAttributes do
					extraAttributes[k] = parameters.Attributes[k]
				end
			end
			local copies, layoutParameters = getCopies(source, parameters, random, extraAttributes)
			local count = #copies
			if count == 0 then
				return
			end
			local padding = random:NextNumber(attributes.RandomPadding.Min, attributes.RandomPadding.Max)
			local pauseInterval = layoutParameters.Attributes.PauseInterval
			local grid = getGrid(size, count, layoutParameters)
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
			local tags = parseTags(attributes.GeneratedTags)

			local placed: { Bounds } = {}
			local generatedByTemplate: { [Instance]: number } = {}
			for index, copy in copies do
				local template = copy.Template
				local copyParameters = copy.Parameters
				local copyAttributes = copyParameters.Attributes
				local rotation = CFrame.Angles(
					math.rad(random:NextNumber(copyAttributes.RandomRoll.Min, copyAttributes.RandomRoll.Max)),
					math.rad(random:NextNumber(copyAttributes.RandomPan.Min, copyAttributes.RandomPan.Max)),
					math.rad(random:NextNumber(copyAttributes.RandomTilt.Min, copyAttributes.RandomTilt.Max))
				)
				local instance = prepareClone(template, cellSize, rotation, copyAttributes.GeneratedScale)
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
				if copyAttributes.GeneratedAlignment == "Floor" then
					local cellBottom = -size.Y / 2 + coordinates.Y * (cellSize.Y + padding)
					center = Vector3.new(center.X, cellBottom + boundsSize.Y / 2, center.Z)
				end
				checkPadding(center, boundsSize, placed, padding, copyParameters)
				table.insert(placed, { Center = center, Size = boundsSize })
				-- Align the geometry, including templates with an offset pivot.
				instance:PivotTo(CFrame.new(center - boundsCenter) * instance:GetPivot())
				for _, tag in tags do
					instance:AddTag(tag)
				end
				if fn then
					fn(instance, layoutParameters, targetContainer)
				end
				(instance :: Instance).Parent = targetContainer
				local generated = (generatedByTemplate[template] or 0) + 1
				generatedByTemplate[template] = generated
				if generated % copyAttributes.PauseInterval == 0 then
					copyParameters:Pause()
				end
			end
		end,
	}
end

-- Class
local Module = {}

Module.new = function()
	return newGenerator()
end

Module.append = function<Attributes>(
	attributes: Attributes,
	fn: CallbackFn<Attributes & Types.PackageAttributes>
): Types.GeneratorModuleDefinition<Attributes & Types.PackageAttributes>
	return newGenerator(attributes :: any, fn :: any) :: any
end

return Module
