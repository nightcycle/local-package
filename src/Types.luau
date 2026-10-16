--!strict
local Type = require(script.Parent.Parent.Type)
local Types = {}
export type AlignType = "Center" | "Floor"
Types.AlignType = Type.literal("Center", "Floor")
export type ScaleType = "Default" | "Fit" | "Height"
Types.ScaleType = Type.literal("Default", "Fit", "Height")
export type PlacementType = "Grid" | "Random" | "Line" -- partially constrained by AlignType
Types.PlacementType = Type.literal("Grid", "Random", "Line")
export type PackageAttributes = {
	SourcePath: string, -- where the original template is found, if a folder it will randomly select one of the basePart / model descendants using the seed
	SourcePathDelimiter: string, -- in case you want to use "/" instead of "." for the path
	SourceMaxYield: number, -- how long to wait for the template to appear (if streaming enabled keep high, if not, do whatever)
	GeneratedAlignment: AlignType, -- where it will place the instance within the box
	GeneratedScale: ScaleType, -- how it will try to size the instance within the box
	GeneratedTags: string, -- tags it will add to the copies of the template in comma delimited format (aka "tag1,tag2,tag3"), spaces immediately after commas are ignored
	GeneratedCount: NumberRange, -- how many copies of the source will be created
	RandomSeed: number, -- used to keep regeneration deterministic
	RandomRoll: NumberRange, -- X axis random rotation
	RandomPan: NumberRange, -- Y axis random rotation
	RandomTilt: NumberRange, -- Z axis random rotation
	RandomPlacement: PlacementType, -- how multiple
}

export type GenerationFunctionParams<Attributes> = {
	Attributes: Attributes,
	Size: Vector3,
	Pause: (self: GenerationFunctionParams<Attributes>) -> (),
}

export type GeneratorModuleDefinition<Attributes> = {
	Attributes: Attributes,
	OnGenerate: (parameters: GenerationFunctionParams<Attributes>, targetContainer: GeneratedFolder) -> (),
}

return Types
