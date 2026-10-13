-- Dónde está cada bioma (lo usan World para pintar la roca y el cliente para el ambiente y el aviso de capa, así
-- coinciden). Cada capa de Config/Biomes se reparte en 4 cuadrantes alrededor del pozo, con bordes ondulados por
-- ruido y girados de una capa a otra. No depende de la semilla del día: los biomas siempre están en el mismo sitio.
local WorldConfig = require(script.Parent.Config.World)
local Biomes = require(script.Parent.Config.Biomes)

local PIT = WorldConfig.PitCenter
local LAYERS = WorldConfig.Layers
local TAU = math.pi * 2
local TURN = 0.9 -- giro del reparto por capa (radianes, ~52°)
local WARP = 0.5 -- cuánto se ondulan los bordes (radianes)
local WARP_SCALE = 1 / 180 -- tamaño de las ondas de los bordes
local DETAIL = 0.12 -- ondas pequeñas encima
local DETAIL_SCALE = 1 / 55

local BiomeMap = {}

-- por encima de esta altura (el piso de la cueva del foso menos su caparazón) están la cueva del foso, las cuevas-base
-- y la superficie: zona común, de roca neutra y sin bioma
BiomeMap.CommonZoneY = WorldConfig.Hub.Center.Y - WorldConfig.Hub.Height / 2 - WorldConfig.CaveShell

-- capa (1..10) a esa profundidad (positiva hacia abajo)
function BiomeMap.Layer(depth: number): number
	for i, layer in LAYERS do
		if depth <= layer.MaxDepth then return i end
	end
	return #LAYERS
end

-- cuadrante (1..4) del bioma en (x, z) dentro de la capa `layer`
function BiomeMap.Sector(x: number, z: number, layer: number): number
	local angle = math.atan2(z - PIT.Y, x - PIT.X) + (layer - 1) * TURN
	angle += math.noise(x * WARP_SCALE + 0.37, z * WARP_SCALE + 0.71, layer * 3.13 + 0.5) * WARP * 2
	angle += math.noise(x * DETAIL_SCALE + 5.29, z * DETAIL_SCALE + 9.83, layer * 1.77 + 0.5) * DETAIL * 2
	return math.floor((angle / TAU) % 1 * 4) + 1
end

-- bioma en (x, z) dentro de la capa `layer`
function BiomeMap.Biome(x: number, z: number, layer: number)
	return LAYERS[layer].Biomes[BiomeMap.Sector(x, z, layer)]
end

-- capa y bioma en una posición del mundo (el bioma es nil en la zona común de arriba)
function BiomeMap.At(position: Vector3): (number, any)
	local layer = BiomeMap.Layer(-position.Y)
	if position.Y > BiomeMap.CommonZoneY then return layer, nil end
	return layer, BiomeMap.Biome(position.X, position.Z, layer)
end

BiomeMap.MaterialColors = Biomes.MaterialColors

return BiomeMap
