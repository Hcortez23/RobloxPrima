-- Disposición de las cuevas-base alrededor de la cueva del foso (la usan World, Hub, Bases y Carts para que todos
-- coincidan). Las bases van repartidas cada 360/Count grados, desfasadas medio paso respecto al portal DESCENSO (que
-- sale hacia Config.World.Hub.ExitDown), así ninguna boca de pasaje cae sobre el portal.
local WorldConfig = require(script.Parent.Config.World)
local Config = require(script.Parent.Config.Bases)

local HUB = WorldConfig.Hub
local FLOOR = HUB.Center.Y - HUB.Height / 2
local HUB_XZ = Vector2.new(HUB.Center.X, HUB.Center.Z)
local EXIT_ANGLE = math.atan2(HUB.ExitDown.Z, HUB.ExitDown.X)
local STEP = math.pi * 2 / Config.Count

export type Layout = {
	index: number,
	angle: number, -- desde +X hacia +Z, visto desde el centro de la cueva del foso
	dir: Vector2, -- de la cueva del foso hacia la base (en XZ)
	center: Vector3, -- centro de la cueva-base (a media altura)
	floor: Vector3, -- centro del piso de la cueva-base
	hubMouth: Vector3, -- boca del pasaje en la pared de la cueva del foso (a ras del piso)
	baseMouth: Vector3, -- boca del pasaje en la pared de la cueva-base (a ras del piso)
}

local layouts: { Layout } = {}
for i = 1, Config.Count do
	local angle = EXIT_ANGLE + STEP / 2 + (i - 1) * STEP
	local dir = Vector2.new(math.cos(angle), math.sin(angle))
	local c = HUB_XZ + dir * Config.RingRadius
	local hubMouth = HUB_XZ + dir * HUB.Radius
	local baseMouth = c - dir * Config.CaveRadius
	table.insert(layouts, {
		index = i,
		angle = angle,
		dir = dir,
		center = Vector3.new(c.X, FLOOR + Config.CaveHeight / 2, c.Y),
		floor = Vector3.new(c.X, FLOOR, c.Y),
		hubMouth = Vector3.new(hubMouth.X, FLOOR, hubMouth.Y),
		baseMouth = Vector3.new(baseMouth.X, FLOOR, baseMouth.Y),
	})
end

return {
	Config = Config,
	Floor = FLOOR,
	All = layouts,
	-- direcciones (en XZ, desde el centro de la cueva del foso) de todas las aberturas de su pared: las bases y el portal
	Openings = function(): { Vector2 }
		local list = { Vector2.new(HUB.ExitDown.X, HUB.ExitDown.Z).Unit }
		for _, layout in layouts do table.insert(list, layout.dir) end
		return list
	end,
}
