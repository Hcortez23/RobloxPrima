-- Disposición de los hubs de cada capa (la usan World para tallarlos, LayerHubs para la utilería, Carts para las
-- estaciones y Progression para descubrirlos y para el elevador). Todos están alrededor del pozo, uno encima de otro:
-- el de la capa 1 es la cueva del foso; los de las capas 2 a 10, cavernas a FloorOffset bajo el techo de su capa.
local WorldConfig = require(script.Parent.Config.World)
local Progression = require(script.Parent.Config.Progression)

local PIT = WorldConfig.PitCenter
local MAIN = WorldConfig.Hub
local SPEC = Progression.Hub

export type Hub = {
	layer: number,
	main: boolean, -- la cueva del foso
	center: Vector3, -- centro del piso, sobre el eje del pozo
	radius: number,
	height: number,
	domeRadius: number,
	elevator: CFrame, -- piso de la cabina; -Z (LookVector) hacia fuera del pozo, donde está la puerta
	permit: CFrame, -- terminal del permiso de descenso; su frente mira hacia fuera del pozo
	station: { stop: Vector3, mouth: Vector3, tunnelEnd: Vector3, dir: Vector3 }, -- dir: del centro hacia la pared
}

local function around(center: Vector3, angle: number, distance: number): Vector3
	return center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local hubs: { Hub } = {}
for i in WorldConfig.Layers do
	local main = i == 1
	local top = if i == 1 then 0 else WorldConfig.Layers[i - 1].MaxDepth
	local floorY = if main then MAIN.Center.Y - MAIN.Height / 2 else -(top + SPEC.FloorOffset)
	local center = Vector3.new(PIT.X, floorY, PIT.Y)
	local radius = if main then MAIN.Radius else SPEC.Radius
	local cabin = around(center, Progression.ElevatorAngle, 64)
	local terminal = around(center, Progression.ElevatorAngle + 0.3, 66)
	local dir = Vector3.new(math.cos(Progression.StationAngle), 0, math.sin(Progression.StationAngle))
	hubs[i] = {
		layer = i,
		main = main,
		center = center,
		radius = radius,
		height = if main then MAIN.Height else SPEC.Height,
		domeRadius = if main then MAIN.DomeRadius else SPEC.DomeRadius,
		elevator = CFrame.lookAt(cabin, cabin + (cabin - center).Unit),
		permit = CFrame.lookAt(terminal, terminal + (terminal - center).Unit),
		station = {
			stop = center + dir * (radius - 16),
			mouth = center + dir * (radius - 1),
			tunnelEnd = center + dir * (radius + 44),
			dir = dir,
		},
	}
end

local HubLayout = {}
HubLayout.All = hubs

-- hub de la capa `i`
function HubLayout.Get(i: number): Hub
	return hubs[i]
end

-- hub en el que está `position` (dentro de su caverna), o nil
function HubLayout.At(position: Vector3): Hub?
	for _, hub in hubs do
		local flat = Vector2.new(position.X - hub.center.X, position.Z - hub.center.Z).Magnitude
		local up = position.Y - hub.center.Y
		if flat <= hub.radius and up >= -6 and up <= hub.height + hub.domeRadius then return hub end
	end
	return nil
end

return HubLayout
