--!native
--!optimize 2
-- Mundo: meseta enorme con un pozo estrecho y vertical que baja directo al núcleo, hecho con Terrain por código.
--  · Bajo la meseta, 10 capas de roca con 4 biomas cada una (shared/BiomeMap dice cuál va en cada sitio; cada bioma
--    tiene su material de roca). La zona común de arriba (cuevas del foso y de las bases) es de roca neutra.
--  · Cueva de la base (spawn, bases y tiendas) unida por una gran puerta de arco a la cueva del foso: caverna enorme
--    bajo el centro con el pozo al núcleo en su piso, tapado por una rejilla (Hub.luau pone la puerta, la rejilla, luces
--    y máquinas). Ninguna cueva ni túnel cruza el pozo ni se puede excavar hacia él: se entra por los hubs.
--  · Un hub por capa alrededor del pozo (shared/HubLayout): el pozo queda abierto en cada uno (LayerHubs le pone
--    baranda y elevador), con la estación de carritos y galerías hacia las minas de su capa.
--  · Superficie llana en el centro con lomas y montañas hacia los bordes; entradas repartidas (rampas y pozos).
--  · Al fondo, la cámara del núcleo: el último eslabón de la cadena de arenas.
--  · Cavernas-arena por capa (grandes y verticales, con salientes, pilares y estalactitas para el gancho), unidas por
--    una cadena de túneles desde una entrada de la meseta hasta lo más profundo.
--  · Iluminación del subsuelo con cristales luminosos; los minerales también brillan.
--  · Pool de minerales por capas (más raros hacia el núcleo), repuestos con el tiempo, más unos cuantos a la vista.
--  · Las explosiones de minerales excavan el terreno (Minerals.Exploded).
-- Se genera por celdas y solo lo necesario (ver «Generación por celdas»): los jugadores entran cuando está la capa 1
-- cerca del centro; la columna del pozo se completa en segundo plano y el resto aparece alrededor de los jugadores.
-- El límite de caída (FallenPartsDestroyHeight) va en default.project.json: un script no tiene permiso para cambiarlo.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.World)
local BiomeMap = require(ReplicatedStorage.Shared.BiomeMap)
local BaseLayout = require(ReplicatedStorage.Shared.BaseLayout)
local HubLayout = require(ReplicatedStorage.Shared.HubLayout)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.Progression)
local MineralData = require(ReplicatedStorage.Shared.Config.Minerals)

local Terrain = workspace.Terrain
local RES = 4 -- tamaño de voxel de Roblox
local CHUNK = 128 -- studs por lado de cada bloque que se escribe de una vez
-- alto que se genera sobre y = 0: montañas + lomas + margen (múltiplo del voxel)
local TOP = math.ceil((Config.MountainHeight + Config.HillHeight + 12) / 4) * 4
local CAVE_SHARP = 18 -- qué tan nítido es el borde de las cuevas (voxel ~ 0.056 de ruido)
local PIT_NOISE = 1 / 28 -- escala del ruido que desordena las paredes del pozo

local seed = Config.Seed or (tonumber(os.date("!%Y%m%d")) :: number)
local seedRng = Random.new(seed)

-- offsets de ruido (no enteros, para evitar los nodos donde el ruido vale 0)
local function offsets()
	return { seedRng:NextNumber(0, 1000) + 0.37, seedRng:NextNumber(0, 1000) + 0.61, seedRng:NextNumber(0, 1000) + 0.19 }
end
local o1, o2, o3, o4 = offsets(), offsets(), offsets(), offsets()
local o5 = offsets() -- relieve de la superficie

local function smoothstep(a: number, b: number, t: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1)
	return x * x * (3 - 2 * x)
end

-- Altura de la superficie en (x, z): plano en el centro (encima de la base), lomas suaves y montañas hacia los bordes.
local SPAWN2D = Vector2.new(Config.SpawnPosition.X, Config.SpawnPosition.Z)
local function surfaceHeight(x: number, z: number): number
	local p = Vector2.new(x, z)
	local edge = math.max(math.abs(x), math.abs(z)) / Config.HalfSize
	local ms = Config.MountainScale
	-- montañas: crestas (ruido "doblado") + forma general, subiendo hacia los bordes
	local ridge = 1 - math.abs(math.noise(x * ms + o5[1], z * ms + o5[2], o5[3]))
	local mass = math.noise(x * ms * 0.5 + o5[2], z * ms * 0.5 + o5[3], o5[1]) * 0.5 + 0.5
	local mountains = Config.MountainHeight * smoothstep(Config.MountainStart, 0.95, edge) * (0.35 + 0.65 * ridge * ridge) * (0.6 + 0.4 * mass)
	-- lomas, aplanadas cerca del spawn y del pozo
	local nearFlat = math.min((p - SPAWN2D).Magnitude, (p - Config.PitCenter).Magnitude - Config.PitRadius)
	local hills = Config.HillHeight * (math.noise(x / 60 + o5[3], z / 60 + o5[1], o5[2]) * 0.5 + 0.5) * smoothstep(0, Config.FlatRadius, nearFlat - Config.FlatRadius * 0.5)
	return math.max(mountains, hills)
end

local function layerIndex(depth: number): number
	for i, layer in Config.Layers do
		if depth <= layer.MaxDepth then return i end
	end
	return #Config.Layers
end

-- Material de la roca: el del bioma de (x, z) en esa capa; por encima de la zona de biomas (cuevas del foso y de las
-- bases, y la corteza sobre ellas), roca neutra.
local NEUTRAL = Enum.Material.Rock
local COMMON_DEPTH = -BiomeMap.CommonZoneY
local function materialAt(x: number, z: number, depth: number): Enum.Material
	if depth < COMMON_DEPTH then return NEUTRAL end
	return BiomeMap.Biome(x, z, layerIndex(depth)).Material
end
-- color de luz de la capa a esa profundidad (las capas sin color propio usan el primero)
local function lightColor(depth: number): Color3
	return Config.LightColors[layerIndex(depth)] or Config.LightColors[1]
end

local function layerTop(i: number): number
	return if i == 1 then 0 else Config.Layers[i - 1].MaxDepth
end

-- Datos por fila de voxel (dependen solo de la profundidad), calculados una vez. Fila 1 = la más profunda.
local NY = (Config.Depth + TOP) / RES
local rowCommon, rowLayer, rowWidth, rowThr = table.create(NY), table.create(NY), table.create(NY), table.create(NY)
for j = 1, NY do
	local depth = -(-Config.Depth + (j - 0.5) * RES)
	local t = math.clamp(depth / Config.Depth, 0, 1)
	rowCommon[j], rowLayer[j] = depth < COMMON_DEPTH, layerIndex(depth)
	rowWidth[j] = Config.TunnelWidth[1] + (Config.TunnelWidth[2] - Config.TunnelWidth[1]) * t
	rowThr[j] = Config.CavernThreshold[1] + (Config.CavernThreshold[2] - Config.CavernThreshold[1]) * t
end

local CORE_FLOOR = -Config.Depth + Config.CoreHeight -- bajo esta altura el pozo termina en roca sólida
local PIT_NEAR2 = (Config.PitRadius + Config.PitRagged + 2 * RES) ^ 2
local PIT_SEAL2 = (Config.PitRadius + Config.PitRagged + Config.PitSeal) ^ 2 -- aquí no se abren cuevas
local HUB_FLOOR = Config.Hub.Center.Y - Config.Hub.Height / 2 -- el pozo empieza en el piso de la base

-- Entrada inicial: sale de la pared de la cueva del foso (EXIT_FROM) y baja hasta la cámara de cruce (JUNCTION).
-- Las cuevas naturales solo se abren por debajo de esa cámara y cerca del pozo: todo empieza desde la cueva inicial.
local EXIT_DIR = Config.Hub.ExitDown.Unit
local EXIT_FROM = Vector3.new(Config.Hub.Center.X, HUB_FLOOR + Config.Hub.TunnelRadius, Config.Hub.Center.Z)
	+ EXIT_DIR * (Config.Hub.Radius - Config.Hub.TunnelRadius)
local JUNCTION = EXIT_FROM + EXIT_DIR * Config.Hub.Junction.Distance - Vector3.yAxis * Config.Hub.Junction.Drop
local CAVE_TOP = JUNCTION.Y + Config.Hub.Junction.Radius
local CAVE_R2 = Config.CaveRadius ^ 2
local CAVES_BOTTOM_Y = -Config.CaveZoneDepth + 8 -- de aquí para abajo, roca maciza que se excava

-- Caparazón de roca maciza alrededor de la cueva del foso, las cuevas-base (shared/BaseLayout) y sus pasajes: ahí no se
-- abren cuevas naturales ni se puede excavar (las cuevas empiezan desde la cámara de cruce). Devuelve el rango de
-- alturas sellado en la columna (x, z), o nil si la columna queda fuera.
local BASE = BaseLayout.Config
local SHELL = Config.CaveShell
local SHELL_BOTTOM = HUB_FLOOR - SHELL
local HUB_TOP = Config.Hub.Center.Y + Config.Hub.Height / 2 + Config.Hub.DomeRadius + SHELL
local BASE_TOP = HUB_FLOOR + BASE.CaveHeight + BASE.DomeRadius + SHELL
local PASSAGE_TOP = HUB_FLOOR + BASE.PassageHeight + BASE.PassageWidth / 2 + SHELL

-- Datos de cada cueva-base en números sueltos (shellRange se llama por cada columna de voxels: sin crear vectores).
local BASES_XZ = {}
for _, layout in BaseLayout.All do
	local ax, az = layout.hubMouth.X, layout.hubMouth.Z
	local bx, bz = layout.baseMouth.X - ax, layout.baseMouth.Z - az
	table.insert(BASES_XZ, { x = layout.floor.X, z = layout.floor.Z, ax = ax, az = az, bx = bx, bz = bz, len2 = bx * bx + bz * bz })
end
local HUB_X, HUB_Z = Config.Hub.Center.X, Config.Hub.Center.Z
local SHELL_REACH = BASE.RingRadius + BASE.CaveRadius + SHELL -- más lejos del centro no hay caparazón

-- ¿(x, z) está a menos de PassageWidth / 2 + extra del eje del pasaje de esa base?
local function nearPassage(x: number, z: number, b, extra: number): boolean
	local px, pz = x - b.ax, z - b.az
	local t = math.clamp((px * b.bx + pz * b.bz) / b.len2, 0, 1)
	local dx, dz = px - b.bx * t, pz - b.bz * t
	local r = BASE.PassageWidth / 2 + extra
	return dx * dx + dz * dz <= r * r
end

local function shellRange(x: number, z: number): (number?, number?)
	local hx, hz = x - HUB_X, z - HUB_Z
	local d2 = hx * hx + hz * hz
	if d2 > SHELL_REACH * SHELL_REACH then return nil, nil end
	local top: number? = nil
	if d2 <= (Config.Hub.Radius + SHELL) ^ 2 then top = HUB_TOP end
	local caveR2 = (BASE.CaveRadius + SHELL) ^ 2
	for _, b in BASES_XZ do
		local dx, dz = x - b.x, z - b.z
		if dx * dx + dz * dz <= caveR2 then
			top = math.max(top or -math.huge, BASE_TOP)
		elseif nearPassage(x, z, b, SHELL) then
			top = math.max(top or -math.huge, PASSAGE_TOP)
		end
	end
	if top then return SHELL_BOTTOM, top end
	return nil, nil
end

-- ¿Un punto (x, z) cae sobre las cuevas de arriba (con su caparazón)? Para alejar de ahí las entradas de la superficie.
local function overCaves(x: number, z: number, extra: number): boolean
	local hx, hz = x - HUB_X, z - HUB_Z
	if hx * hx + hz * hz <= (Config.Hub.Radius + SHELL + extra) ^ 2 then return true end
	for _, b in BASES_XZ do
		local dx, dz = x - b.x, z - b.z
		if dx * dx + dz * dz <= (BASE.CaveRadius + SHELL + extra) ^ 2 or nearPassage(x, z, b, SHELL + extra) then
			return true
		end
	end
	return false
end
local generatedDepth = 0 -- la capa 1 está generada hasta aquí (lo profundo se genera por celdas, ver ensureBox)

-- Ruta principal (entrada inicial y túneles entre arenas): Route.luau le pone rieles, cables y letreros.
-- stop = el tramo termina en una parada (la cámara de cruce o una arena): ahí va una estación de carritos
type Segment = { from: Vector3, to: Vector3, radius: number, stop: boolean }
local route: { Segment } = {}

-- Genera las filas [jA, jB] de un bloque de CHUNK x CHUNK. stats[capa] = { aire, total } para ajustar las cuevas.
-- Es el bucle más caro de la generación: funciones y Enums en locales, sin crear tablas por voxel, y los ruidos solo
-- donde cambian el resultado.
local AIR, ROCK, GROUND = Enum.Material.Air, Enum.Material.Rock, Enum.Material.Ground
local noise, abs, clamp, min, max, sqrt = math.noise, math.abs, math.clamp, math.min, math.max, math.sqrt
local function generateChunk(x0: number, z0: number, jA: number, jB: number, stats)
	local n = CHUNK / RES
	local f = Config.NoiseScale
	local mats, occs = table.create(n), table.create(n)
	local z1, z2, z3, dz2 = table.create(n), table.create(n), table.create(n), table.create(n)
	local heights = table.create(n, 0) -- altura de la superficie por columna (i, k)
	local shellLow, shellHigh = table.create(n), table.create(n) -- rango sellado por columna (caparazón de las cuevas)
	local zs = table.create(n)
	for k = 1, n do
		local z = z0 + (k - 0.5) * RES
		zs[k], z1[k], z2[k], z3[k] = z, z * f + o1[3], z * f + o2[3], z * f + o3[3]
		dz2[k] = (z - Config.PitCenter.Y) ^ 2
	end
	-- el relieve solo importa si las filas llegan a la superficie, y el caparazón solo si llegan a su altura
	local yTop = -Config.Depth + jB * RES
	local needSurface, needShell = yTop > -8, yTop >= SHELL_BOTTOM
	-- una franja toca a lo más dos capas: material de la roca por columna para cada una (se calcula al necesitarlo)
	local layerA, layerB = rowLayer[jA], rowLayer[jB]
	local matA, matB = table.create(n), table.create(n)
	local pitR, pitRagged = Config.PitRadius, Config.PitRagged
	for i = 1, n do
		local rows = jB - jA + 1
		local mi, oi = table.create(rows), table.create(rows)
		mats[i], occs[i] = mi, oi
		local x = x0 + (i - 0.5) * RES
		local x1, x2, x3 = x * f + o1[1], x * f + o2[1], x * f + o3[1]
		local dx2 = (x - Config.PitCenter.X) ^ 2
		for k = 1, n do
			if needSurface then heights[k] = surfaceHeight(x, zs[k]) end
			if needShell then shellLow[k], shellHigh[k] = shellRange(x, zs[k]) end
			matA[k], matB[k] = nil, nil
		end
		for j = jA, jB do
			local y = -Config.Depth + (j - 0.5) * RES
			local y1, y2, y3 = y * f + o1[2], y * f + o2[2], y * f + o3[2]
			local mj, oj = table.create(n), table.create(n)
			mi[j - jA + 1], oi[j - jA + 1] = mj, oj
			local width, thr, layer, common = rowWidth[j], rowThr[j], rowLayer[j], rowCommon[j]
			local caveRow = y < CAVE_TOP and y > CAVES_BOTTOM_Y
			local pitRow = y > CORE_FLOOR and y < HUB_FLOOR + RES
			local belowHub = y < HUB_FLOOR
			local air = 0
			for k = 1, n do
				local ground = heights[k]
				local below = ground - y -- profundidad bajo la superficie (con montañas)
				local occ = clamp(below / RES + 0.5, 0, 1)
				if occ > 0 then
					local r2 = dx2 + dz2[k]
					if pitRow and r2 < PIT_NEAR2 then
						-- pozo vertical con paredes irregulares: aire dentro del radio
						local edge = pitR + pitRagged * noise(x * PIT_NOISE + o4[1], y * PIT_NOISE * 0.5 + o4[2], zs[k] * PIT_NOISE + o4[3])
						occ = min(occ, clamp((sqrt(r2) - edge) / RES + 0.5, 0, 1))
					end
					-- cuevas solo en la capa 1, por debajo de la cámara de cruce, cerca del pozo y fuera de lo sellado
					-- (el caparazón del pozo y el de las cuevas de arriba)
					if occ > 0 and caveRow and r2 < CAVE_R2 and not (r2 < PIT_SEAL2 and belowHub) then
						local low = shellLow[k]
						if not (low ~= nil and y >= low and y <= shellHigh[k]) then
							-- negativo = aire (cueva), positivo = roca; se saltan los ruidos que no cambian el resultado
							local tunnel = abs(noise(x1, y1, z1[k])) - width
							if tunnel * CAVE_SHARP < 0.5 then -- si el primero ya da roca maciza, el máximo también
								tunnel = max(tunnel, abs(noise(x2, y2, z2[k])) - width)
							end
							if tunnel * CAVE_SHARP + 0.5 <= 0 then
								occ = 0 -- túnel: aire, sin importar la caverna
							else
								local cavern = thr - noise(x3, y3, z3[k])
								occ = min(occ, clamp(min(tunnel, cavern) * CAVE_SHARP + 0.5, 0, 1))
							end
						end
					end
				end
				if occ < 0.5 then air += 1 end
				if occ <= 0.01 then
					mj[k], oj[k] = AIR, 0
				else
					if below < 5 then -- tierra en la superficie llana; roca desnuda en las montañas
						mj[k] = if ground > 26 then ROCK else GROUND
					elseif common then
						mj[k] = NEUTRAL
					elseif layer == layerA then
						local m = matA[k]
						if not m then
							m = BiomeMap.Biome(x, zs[k], layer).Material
							matA[k] = m
						end
						mj[k] = m
					else
						local m = matB[k]
						if not m then
							m = BiomeMap.Biome(x, zs[k], layer).Material
							matB[k] = m
						end
						mj[k] = m
					end
					oj[k] = occ
				end
			end
			if stats and y < 0 then
				local s = stats[layer]
				s[1] += air
				s[2] += n
			end
		end
	end
	local yBottom = -Config.Depth + (jA - 1) * RES
	Terrain:WriteVoxels(Region3.new(Vector3.new(x0, yBottom, z0), Vector3.new(x0 + CHUNK, yTop, z0 + CHUNK)), RES, mats, occs)
end

-- Tramo de roca maciza de una capa en un cuadrado: si todo el cuadrado cae en el mismo bioma va de un solo bloque; si
-- lo cruza un borde de bioma, se divide en cuatro (hasta MIN_BLOCK de lado).
local MIN_BLOCK = 16
local SAMPLES = { { 0, 0 }, { 0.5, 0 }, { 1, 0 }, { 0, 0.5 }, { 1, 0.5 }, { 0, 1 }, { 0.5, 1 }, { 1, 1 } }
local function fillBiomeBlock(x0: number, z0: number, size: number, top: number, bottom: number, layer: number)
	local sector = BiomeMap.Sector(x0 + size / 2, z0 + size / 2, layer)
	local uniform = true
	if size > MIN_BLOCK then
		for _, f in SAMPLES do
			if BiomeMap.Sector(x0 + f[1] * size, z0 + f[2] * size, layer) ~= sector then
				uniform = false
				break
			end
		end
	end
	if uniform then
		local center = Vector3.new(x0 + size / 2, -(top + bottom) / 2, z0 + size / 2)
		Terrain:FillBlock(CFrame.new(center), Vector3.new(size, bottom - top, size), Config.Layers[layer].Biomes[sector].Material)
	else
		local h = size / 2
		for _, o in { { 0, 0 }, { h, 0 }, { 0, h }, { h, h } } do
			fillBiomeBlock(x0 + o[1], z0 + o[2], h, top, bottom, layer)
		end
	end
end

-- Bloque de roca maciza: cada tramo de capa con el material de sus biomas, sin calcular voxel a voxel.
local function fillSolidChunk(x0: number, z0: number, fromDepth: number, toDepth: number)
	if fromDepth < COMMON_DEPTH then -- corteza de la zona común: roca neutra
		local bottom = math.min(toDepth, COMMON_DEPTH)
		Terrain:FillBlock(CFrame.new(x0 + CHUNK / 2, -(fromDepth + bottom) / 2, z0 + CHUNK / 2), Vector3.new(CHUNK, bottom - fromDepth, CHUNK), NEUTRAL)
		fromDepth = bottom
	end
	for i, layer in Config.Layers do
		local top, bottom = math.max(fromDepth, layerTop(i)), math.min(toDepth, layer.MaxDepth)
		if bottom > top then
			fillBiomeBlock(x0, z0, CHUNK, top, bottom, i)
		end
	end
end
-- ¿El bloque toca la columna del pozo? (ahí hace falta el cálculo voxel a voxel para su borde irregular)
local function chunkNearPit(x0: number, z0: number): boolean
	local px, pz = Config.PitCenter.X, Config.PitCenter.Y
	local dx = math.max(x0 - px, 0, px - (x0 + CHUNK))
	local dz = math.max(z0 - pz, 0, pz - (z0 + CHUNK))
	return math.sqrt(dx * dx + dz * dz) < Config.PitRadius + Config.PitRagged + 3 * RES
end

-- ¿El bloque toca la zona de cuevas (alrededor del pozo)?
local function chunkNearCaves(x0: number, z0: number): boolean
	local px, pz = Config.PitCenter.X, Config.PitCenter.Y
	local dx = math.max(x0 - px, 0, px - (x0 + CHUNK))
	local dz = math.max(z0 - pz, 0, pz - (z0 + CHUNK))
	return math.sqrt(dx * dx + dz * dz) < Config.CaveRadius + 2 * RES
end

-- piel de la superficie que se calcula voxel a voxel fuera de la zona de cuevas (relieve y montañas); debajo, bloques
local SURFACE_SKIN = 12
local SURFACE_J = (Config.Depth - SURFACE_SKIN) / RES + 1

-- Generación por celdas ------------------------------------------------------------
-- El mundo se divide en celdas de CHUNK x CHUNK x BandHeight. Para ahorrar memoria y tiempo, solo se genera lo que hace
-- falta: al inicio, la capa 1 cerca del centro (cuevas, cueva del foso y cuevas-base); en segundo plano, la columna
-- del pozo completa (se ve desde todos los hubs); y el resto, cuando un jugador se acerca (ensureBox). Una celda
-- generada nunca se vuelve a generar (no taparía lo excavado). Antes de tallar algo (minas, hubs) se aseguran sus celdas.
local CHUNKS = Config.HalfSize * 2 / CHUNK -- celdas por lado
local BANDS = Config.Depth / Config.BandHeight
local TOP_RADIUS = BASE.RingRadius + BASE.CaveRadius + SHELL + 30 -- lo que se genera al inicio en la capa 1
local cellDone: { [number]: boolean } = {}
local deepCells: { [number]: { { number } } } = {} -- [capa] = { { x0, z0, profundidad de arriba, de abajo } } ya generadas
local onDeepCell: ((x0: number, z0: number, top: number, bottom: number, layer: number) -> ())? = nil -- siembra minerales

local function cellKey(cx: number, cz: number, band: number): number
	return cx + cz * CHUNKS + band * CHUNKS * CHUNKS
end

-- distancia horizontal del pozo al punto más cercano del bloque
local function chunkDistance(x0: number, z0: number): number
	local px, pz = Config.PitCenter.X, Config.PitCenter.Y
	local dx = math.max(x0 - px, 0, px - (x0 + CHUNK))
	local dz = math.max(z0 - pz, 0, pz - (z0 + CHUNK))
	return math.sqrt(dx * dx + dz * dz)
end

-- La roca profunda recién generada se anota (para sembrar y reponer minerales) y recibe sus vetas.
local function registerDeep(x0: number, z0: number, fromDepth: number, toDepth: number)
	if toDepth <= Config.CaveZoneDepth then return end
	for i, layer in Config.Layers do
		local top, bottom = math.max(fromDepth, layerTop(i)), math.min(toDepth, layer.MaxDepth)
		if i > 1 and bottom > top then
			deepCells[i] = deepCells[i] or {}
			table.insert(deepCells[i], { x0, z0, top, bottom })
			if onDeepCell then onDeepCell(x0, z0, top, bottom, i) end
		end
	end
end

-- filas de voxels [jA, jB] de un tramo de profundidades [top, bottom) (múltiplos de RES)
local function rowsOf(top: number, bottom: number): (number, number)
	return (Config.Depth - bottom) / RES + 1, (Config.Depth - top) / RES
end
local CAVE_TOP_DEPTH = math.floor(-CAVE_TOP / RES) * RES - RES -- más arriba no hay cuevas naturales
local PIT_TOP_DEPTH = math.floor(-HUB_FLOOR / RES) * RES - RES -- el pozo empieza en el piso de la cueva del foso

-- bloques que tocan la columna del pozo (bajo la zona de cuevas se generan juntos, ver generatePitBand)
local PIT_CHUNKS = {}
for cx = 0, CHUNKS - 1 do
	for cz = 0, CHUNKS - 1 do
		if chunkNearPit(-Config.HalfSize + cx * CHUNK, -Config.HalfSize + cz * CHUNK) then table.insert(PIT_CHUNKS, { cx, cz }) end
	end
end

-- Bajo la zona de cuevas, el pozo no se calcula voxel a voxel: los bloques que lo rodean se rellenan de roca y el pozo
-- se talla con un cilindro y huecos redondos en la pared (borde irregular). Todos los bloques de la franja van juntos,
-- para que ninguno tape después lo tallado.
local function generatePitBand(band: number)
	local fromDepth, toDepth = band * Config.BandHeight, (band + 1) * Config.BandHeight
	for _, c in PIT_CHUNKS do
		local key = cellKey(c[1], c[2], band)
		if not cellDone[key] then
			cellDone[key] = true
			local x0, z0 = -Config.HalfSize + c[1] * CHUNK, -Config.HalfSize + c[2] * CHUNK
			fillSolidChunk(x0, z0, fromDepth, toDepth)
			registerDeep(x0, z0, fromDepth, toDepth)
		end
	end
	local top, bottom = fromDepth, math.min(toDepth, -CORE_FLOOR)
	if bottom <= top then return end
	local pit = Config.PitCenter
	Terrain:FillCylinder(CFrame.new(pit.X, -(top + bottom) / 2, pit.Y), bottom - top, Config.PitRadius, Enum.Material.Air)
	local rng = Random.new(seed + 1000 + band)
	for depth = top + 5, bottom - 2, 9 do
		for _ = 1, 5 do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = Config.PitRadius - 1
			Terrain:FillBall(Vector3.new(pit.X + math.cos(a) * r, -depth, pit.Y + math.sin(a) * r), rng:NextNumber(3, Config.PitRagged + 1), Enum.Material.Air)
		end
	end
end

-- Genera una celda. Solo se calcula voxel a voxel lo que lo necesita (la piel de la superficie y, en la zona de
-- cuevas, las profundidades donde puede haber cuevas o pozo); el resto es roca maciza y se rellena por bloques (mucho
-- más rápido). Devuelve si hizo trabajo voxel a voxel (para repartirlo en frames).
local function generateCell(cx: number, cz: number, band: number, stats): boolean
	local key = cellKey(cx, cz, band)
	if cellDone[key] then return false end
	local x0, z0 = -Config.HalfSize + cx * CHUNK, -Config.HalfSize + cz * CHUNK
	local fromDepth, toDepth = band * Config.BandHeight, (band + 1) * Config.BandHeight
	local pit = chunkNearPit(x0, z0)
	if pit and fromDepth >= Config.CaveZoneDepth then
		generatePitBand(band)
		return false
	end
	cellDone[key] = true
	local voxel = false
	local solidFrom = fromDepth
	if fromDepth <= 0 and Config.SurfaceRelief then -- piel de la superficie (relieve y montañas)
		generateChunk(x0, z0, SURFACE_J, NY, stats)
		solidFrom = SURFACE_SKIN
		voxel = true
	end
	-- tramo voxel a voxel: donde puede haber cuevas (o el pozo) dentro de la zona de cuevas
	local vTop, vBottom = math.huge, -math.huge
	if fromDepth < Config.CaveZoneDepth and (pit or chunkNearCaves(x0, z0)) then
		vTop, vBottom = if pit then math.min(CAVE_TOP_DEPTH, PIT_TOP_DEPTH) else CAVE_TOP_DEPTH, Config.CaveZoneDepth
	end
	local a = math.clamp(vTop, solidFrom, toDepth)
	local b = math.clamp(vBottom, a, toDepth)
	if a > solidFrom then fillSolidChunk(x0, z0, solidFrom, a) end
	if b > a then
		local jA, jB = rowsOf(a, b)
		generateChunk(x0, z0, jA, jB, stats)
		voxel = true
	end
	if toDepth > b then fillSolidChunk(x0, z0, b, toDepth) end
	registerDeep(x0, z0, fromDepth, toDepth)
	return voxel
end
-- Genera todas las celdas que tocan la caja [low, high] (lo que falte). Devuelve cuántas generó.
local function ensureBox(low: Vector3, high: Vector3, stats): number
	local function cell(v: number, n: number): number return math.clamp(v, 0, n - 1) end
	local cx0, cx1 = cell(math.floor((low.X + Config.HalfSize) / CHUNK), CHUNKS), cell(math.floor((high.X + Config.HalfSize) / CHUNK), CHUNKS)
	local cz0, cz1 = cell(math.floor((low.Z + Config.HalfSize) / CHUNK), CHUNKS), cell(math.floor((high.Z + Config.HalfSize) / CHUNK), CHUNKS)
	local b0, b1 = cell(math.floor(math.max(-high.Y, 0) / Config.BandHeight), BANDS), cell(math.floor(math.max(-low.Y, 0) / Config.BandHeight), BANDS)
	local made = 0
	for band = b0, b1 do
		for cx = cx0, cx1 do
			for cz = cz0, cz1 do
				if not cellDone[cellKey(cx, cz, band)] then
					if generateCell(cx, cz, band, stats) then task.wait() end -- lo voxel a voxel, repartido en frames
					made += 1
				end
			end
		end
	end
	return made
end

-- Generación inicial: la capa 1 cerca del centro (todo lo que se ve desde las cuevas de arriba y la zona de cuevas).
local function generateStart(stats)
	for band = 0, Config.ReadyDepth / Config.BandHeight - 1 do
		for cx = 0, CHUNKS - 1 do
			for cz = 0, CHUNKS - 1 do
				local x0, z0 = -Config.HalfSize + cx * CHUNK, -Config.HalfSize + cz * CHUNK
				if chunkDistance(x0, z0) < TOP_RADIUS and generateCell(cx, cz, band, stats) then task.wait() end
			end
			task.wait()
		end
	end
	generatedDepth = Config.ReadyDepth
end

-- En segundo plano: la columna del pozo hasta el núcleo (se ve desde todos los hubs).
local function generatePitColumn(stats)
	for band = 0, BANDS - 1 do
		for cx = 0, CHUNKS - 1 do
			for cz = 0, CHUNKS - 1 do
				local x0, z0 = -Config.HalfSize + cx * CHUNK, -Config.HalfSize + cz * CHUNK
				if chunkNearPit(x0, z0) then
					generateCell(cx, cz, band, stats)
					task.wait()
				end
			end
		end
	end
end
-- túnel recto (cilindro) con una cámara al final, para entrar al subsuelo
local function tunnel(from: Vector3, to: Vector3, radius: number, chamber: number)
	local mid = (from + to) / 2
	local axis = (to - from).Unit
	-- los pozos verticales no pueden usar lookAt (el eje coincide con "arriba"); el cilindro ya es vertical por defecto
	local frame = if math.abs(axis.Y) > 0.999 then CFrame.new(mid) else CFrame.lookAt(mid, to) * CFrame.Angles(math.pi / 2, 0, 0)
	Terrain:FillCylinder(frame, (to - from).Magnitude, radius, Enum.Material.Air)
	if chamber > 0 then
		Terrain:FillBall(to, chamber, Enum.Material.Air)
	end
end

-- Entradas repartidas: rampas inclinadas (se caminan) y pozos verticales, lejos del gran pozo y del spawn.
-- Devuelve las cámaras del fondo de cada entrada (la cadena de arenas empieza en una de ellas).
local function carveEntrances(): { Vector3 }
	local rng = Random.new(seed + 7)
	local pit = Config.PitCenter
	local spawn2d = Vector2.new(Config.SpawnPosition.X, Config.SpawnPosition.Z)
	local lim = Config.HalfSize * Config.MountainStart - 20 -- en la zona llana, no bajo las montañas
	local chambers = {}

	local function randomSpot(): Vector2?
		for _ = 1, 100 do
			local p = Vector2.new(rng:NextNumber(-lim, lim), rng:NextNumber(-lim, lim))
			if (p - pit).Magnitude > Config.PitRadius + 40 and (p - spawn2d).Magnitude > 40 and not overCaves(p.X, p.Y, 20) then return p end
		end
		return nil
	end

	for _ = 1, Config.PlateauRamps do
		local p = randomSpot()
		if p then
			local a = rng:NextNumber(0, math.pi * 2)
			local slope = math.rad(rng:NextNumber(22, 32))
			local len = rng:NextNumber(70, 110)
			local from = Vector3.new(p.X, surfaceHeight(p.X, p.Y) + 2, p.Y)
			local to = from + Vector3.new(math.cos(a) * math.cos(slope), -math.sin(slope), math.sin(a) * math.cos(slope)) * len
			if not overCaves(to.X, to.Z, 20) then -- la rampa no debe acabar sobre las cuevas de arriba
				tunnel(from, to, 6, 13)
				table.insert(chambers, to)
			end
		end
	end
	for _ = 1, Config.PlateauShafts do
		local p = randomSpot()
		if p then
			local to = Vector3.new(p.X, -rng:NextNumber(50, 110), p.Y)
			tunnel(Vector3.new(p.X, surfaceHeight(p.X, p.Y) + 2, p.Y), to, 5, 13)
			table.insert(chambers, to)
		end
	end
	return chambers
end

-- Caverna con piso plano y techo de bóvedas irregulares (forma de la cueva del foso y de la cueva de la base).
local function carveCavern(c: Vector3, r: number, h: number, domeRadius: number)
	Terrain:FillCylinder(CFrame.new(c), h, r, Enum.Material.Air) -- cuerpo: piso plano en c.Y - h / 2
	local top = c.Y + h / 2
	Terrain:FillBall(Vector3.new(c.X, top, c.Z), domeRadius, Enum.Material.Air) -- bóveda central
	for i = 0, 5 do -- anillo de bóvedas para un techo irregular
		local a = i * math.pi / 3 + 0.3
		Terrain:FillBall(Vector3.new(c.X + math.cos(a) * r * 0.62, top - 4, c.Z + math.sin(a) * r * 0.62), domeRadius * 0.8, Enum.Material.Air)
	end
end

-- Pasaje de la cueva del foso a una cueva-base: piso plano, paredes rectas y techo abovedado (los arcos con el nombre
-- del dueño los pone Bases.luau en las dos bocas).
local function carvePassage(layout)
	local dir = Vector3.new(layout.dir.X, 0, layout.dir.Y)
	local from = layout.hubMouth - dir * 12 -- un poco dentro de cada cueva, para que no quede un escalón
	local to = layout.baseMouth + dir * 12
	local mid, length = (from + to) / 2, (to - from).Magnitude
	local walls = mid + Vector3.yAxis * (BASE.PassageHeight / 2)
	Terrain:FillBlock(CFrame.lookAt(walls, walls + dir), Vector3.new(BASE.PassageWidth, BASE.PassageHeight, length), Enum.Material.Air)
	local roof = mid + Vector3.yAxis * BASE.PassageHeight
	Terrain:FillCylinder(CFrame.lookAt(roof, roof + dir) * CFrame.Angles(math.pi / 2, 0, 0), length, BASE.PassageWidth / 2, Enum.Material.Air)
end

local function carveHub(): Vector3
	local hub = Config.Hub
	local c, r = hub.Center, hub.Radius
	carveCavern(c, r, hub.Height, hub.DomeRadius) -- cueva del foso
	for _, layout in BaseLayout.All do -- cuevas-base alrededor, cada una con su pasaje
		carveCavern(layout.center, BASE.CaveRadius, BASE.CaveHeight, BASE.DomeRadius)
		carvePassage(layout)
	end
	-- salida hacia arriba (opcional): rampa desde la pared hasta salir por la superficie
	if hub.ExitUp then
		local up = hub.ExitUp.Unit
		local fromUp = Vector3.new(c.X, HUB_FLOOR + hub.TunnelRadius, c.Z) + up * (r - hub.TunnelRadius)
		local outXZ = Vector2.new(c.X, c.Z) + Vector2.new(up.X, up.Z) * (r + 150)
		tunnel(fromUp, Vector3.new(outXZ.X, surfaceHeight(outXZ.X, outXZ.Y) + 6, outXZ.Y), hub.TunnelRadius, 0)
	end

	-- la entrada inicial: única salida de la cueva del foso. Baja desde la pared hasta una cámara de cruce (fuera del
	-- caparazón) y de ahí se bifurcan ramales que se abren a las cuevas naturales; la cadena de arenas parte del cruce.
	local down = EXIT_DIR
	local junction = hub.Junction
	local from, cross = EXIT_FROM, JUNCTION
	tunnel(from, cross, hub.TunnelRadius, junction.Radius)
	table.insert(route, { from = from, to = cross, radius = hub.TunnelRadius, stop = true })
	Terrain:FillBall(from, hub.TunnelRadius * 1.4, Enum.Material.Air) -- boca ensanchada, bien visible desde la cueva
	local rng = Random.new(seed + 17)
	local baseAngle = math.atan2(down.Z, down.X)
	for i = 1, junction.Branches do
		-- abanico de ramales hacia adelante (nunca de vuelta hacia las cuevas de arriba)
		local spread = (i - (junction.Branches + 1) / 2) / math.max(junction.Branches - 1, 1)
		local a = baseAngle + spread * math.rad(130) + rng:NextNumber(-0.15, 0.15)
		local len = rng:NextNumber(junction.BranchLength[1], junction.BranchLength[2])
		local to = cross + Vector3.new(math.cos(a) * len, -rng:NextNumber(15, 50), math.sin(a) * len)
		tunnel(cross, to, 9, 13)
	end
	return cross
end

-- Cavernas-arena -----------------------------------------------------------------

type Arena = { center: Vector3, radius: number, height: number, bottomDepth: number, rng: Random, carved: boolean, isCore: boolean? }

-- Cámara final alrededor del núcleo, al fondo del pozo (el último eslabón de la cadena de arenas).
local function coreChamber(): Arena
	local spec = Config.CoreChamber
	local center = Vector3.new(Config.PitCenter.X, CORE_FLOOR + spec.Height / 2, Config.PitCenter.Y)
	return {
		center = center,
		radius = spec.Radius,
		height = spec.Height,
		bottomDepth = Config.Depth,
		rng = Random.new(seed + 13),
		carved = false,
		isCore = true,
	}
end

-- Planea todas las arenas de una vez (misma semilla = mismas arenas), ordenadas de la más alta a la más profunda.
local function planArenas(): { Arena }
	local rng = Random.new(seed + 11)
	local spec = Config.Arenas
	local arenas = {}
	-- en toda la zona de cuevas: por debajo de las cuevas de arriba (y su caparazón) y hasta CaveZoneDepth
	local top, bottom = -SHELL_BOTTOM + 20, Config.CaveZoneDepth
	do
		for _ = 1, spec.Count do
			for _ = 1, 30 do -- busca un sitio lejos del pozo y de las otras arenas
				local radius = rng:NextNumber(spec.Radius[1], spec.Radius[2])
				local height = rng:NextNumber(spec.Height[1], spec.Height[2])
				local margin = height / 2 + radius + 12
				-- siempre por debajo de las cuevas de arriba y su caparazón, para que ningún túnel pase por ellas
				local shallowest = top + margin
				if bottom - margin <= shallowest then break end
				local depth = rng:NextNumber(shallowest, bottom - margin)
				-- dentro del radio de cuevas, alrededor del pozo (y lejos de él, ver abajo)
				local a, d = rng:NextNumber(0, math.pi * 2), math.sqrt(rng:NextNumber(0, 1)) * (Config.CaveRadius - radius - 16)
				local center = Vector3.new(Config.PitCenter.X + math.cos(a) * d, -depth, Config.PitCenter.Y + math.sin(a) * d)
				local fromPit = Vector2.new(center.X, center.Z) - Config.PitCenter
				local ok = fromPit.Magnitude > Config.PitRadius + radius + 30
				for _, other in arenas do
					if (other.center - center).Magnitude < other.radius + radius + 40 then ok = false end
				end
				if ok then
					table.insert(arenas, {
						center = center,
						radius = radius,
						height = height,
						bottomDepth = depth + height / 2 + radius,
						rng = Random.new(rng:NextInteger(1, 1e9)),
						carved = false,
					})
					break
				end
			end
		end
	end
	table.sort(arenas, function(a, b) return a.center.Y > b.center.Y end)
	table.insert(arenas, coreChamber()) -- siempre al final: el núcleo es el fondo del recorrido
	return arenas
end

-- Cuerpo vertical con cúpula y fondo redondeados, bordes irregulares, salientes, pilares y estalactitas.
local function carveArena(arena: Arena)
	local spec, rng = Config.Arenas, arena.rng
	local c, r, h = arena.center, arena.radius, arena.height
	local rock = materialAt(c.X, c.Z, -c.Y)
	local up = Vector3.yAxis

	Terrain:FillCylinder(CFrame.new(c), h, r, Enum.Material.Air)
	Terrain:FillBall(c + up * (h / 2), r * 0.92, Enum.Material.Air) -- cúpula
	Terrain:FillBall(c - up * (h / 2), r * 0.8, Enum.Material.Air) -- fondo en tazón
	for _ = 1, 10 do -- huecos en las paredes para que no sea un cilindro perfecto
		local a = rng:NextNumber(0, math.pi * 2)
		local y = rng:NextNumber(-h / 2, h / 2)
		Terrain:FillBall(c + Vector3.new(math.cos(a) * r * 0.85, y, math.sin(a) * r * 0.85), rng:NextNumber(r * 0.3, r * 0.55), Enum.Material.Air)
	end

	if arena.isCore then
		-- piso plano y macizo: el fondo en tazón y los huecos de las paredes llegarían bajo el fondo del mundo
		local thick = Config.CoreHeight + 24
		Terrain:FillBlock(CFrame.new(c.X, CORE_FLOOR - thick / 2, c.Z), Vector3.new(r * 2.8, thick, r * 2.8), rock)
	end

	-- salientes: losas de roca que salen de la pared hacia el centro, a distintas alturas
	for _ = 1, rng:NextInteger(spec.Ledges[1], spec.Ledges[2]) do
		local a = rng:NextNumber(0, math.pi * 2)
		local y = rng:NextNumber(-h / 2 + 10, h / 2 - 6)
		local len = rng:NextNumber(10, 18)
		local wallPoint = c + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
		local inward = Vector3.new(-math.cos(a), 0, -math.sin(a))
		local mid = wallPoint + inward * (len / 2 - 3)
		Terrain:FillBlock(CFrame.lookAt(mid, mid + inward), Vector3.new(rng:NextNumber(8, 14), 4, len), rock)
	end

	-- pilares de piso a techo: obstáculos y anclas para el gancho (la fase 2 los hará rompibles); en la cámara del
	-- núcleo no, para no taparlo
	for _ = 1, if arena.isCore then 0 else rng:NextInteger(spec.Pillars[1], spec.Pillars[2]) do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(r * 0.25, r * 0.6)
		local base = c + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		Terrain:FillCylinder(CFrame.new(base), h + r * 1.6, rng:NextNumber(3, 6), rock)
	end

	-- estalactitas: colgando del techo, más gruesas arriba
	for _ = 1, rng:NextInteger(spec.Stalactites[1], spec.Stalactites[2]) do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, r * 0.7)
		local len = rng:NextNumber(8, 18)
		local topY = c.Y + h / 2 + math.sqrt(math.max((r * 0.92) ^ 2 - d * d, 0)) - 2
		local x, z = c.X + math.cos(a) * d, c.Z + math.sin(a) * d
		Terrain:FillCylinder(CFrame.new(x, topY - len / 4, z), len / 2, rng:NextNumber(2, 3.5), rock)
		Terrain:FillCylinder(CFrame.new(x, topY - len * 0.7, z), len / 2, rng:NextNumber(1, 1.8), rock)
	end
	arena.carved = true
end

-- Une un punto con la arena (túnel hasta su fondo, sin cámara: la arena ya es el espacio abierto). Si la línea recta
-- pasaría cerca del pozo, da un rodeo por fuera del sellado para no abrirle un hueco (sería un atajo al núcleo).
local function connect(from: Vector3, arena: Arena, allowPit: boolean?)
	local to = arena.center + Vector3.new(0, -arena.height / 2 + 6, 0)
	local radius = Config.Arenas.TunnelRadius
	if not allowPit then
		local pit = Config.PitCenter
		local a, b = Vector2.new(from.X, from.Z), Vector2.new(to.X, to.Z)
		local ab = b - a
		local t = if ab.Magnitude > 0 then math.clamp((pit - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
		local closest = a + ab * t
		local safe = Config.PitRadius + Config.PitRagged + Config.PitSeal + radius + 8
		if (closest - pit).Magnitude < safe then
			local away = closest - pit
			if away.Magnitude < 1 then away = Vector2.new(-ab.Y, ab.X) end
			local detour = pit + away.Unit * (safe + 20)
			local mid = Vector3.new(detour.X, from.Y + (to.Y - from.Y) * t, detour.Y)
			tunnel(from, mid, radius, radius + 2)
			tunnel(mid, to, radius, 0)
			table.insert(route, { from = from, to = mid, radius = radius, stop = false }) -- desvío alrededor del pozo
			table.insert(route, { from = mid, to = to, radius = radius, stop = true })
			return
		end
	end
	tunnel(from, to, radius, 0)
	table.insert(route, { from = from, to = to, radius = radius, stop = true })
end


-- Talla las arenas que ya caben en la zona generada y las une en cadena (la primera, a la cueva inicial o, si no hay,
-- a la entrada de la meseta más cercana).
local function carveReadyArenas(arenas: { Arena }, entrances: { Vector3 }, start: Vector3?)
	for i, arena in arenas do
		if not arena.carved and arena.bottomDepth <= generatedDepth then
			carveArena(arena)
			local previous = arenas[i - 1]
			if arena.isCore then
				-- la cámara del núcleo no se conecta: se llega excavando a través de las capas
			elseif previous then
				connect(previous.center + Vector3.new(0, -previous.height / 2 + 6, 0), arena)
			elseif start then
				connect(start, arena)
			elseif #entrances > 0 then
				-- la entrada de la meseta más cercana a la primera arena
				local best = entrances[1]
				for _, e in entrances do
					if (e - arena.center).Magnitude < (best - arena.center).Magnitude then best = e end
				end
				connect(best, arena)
			end
		end
	end
end

-- Minas abandonadas -----------------------------------------------------------
-- De la capa 2 hacia abajo no hay cuevas naturales: hay minas talladas en la roca maciza. Cada una guarda su forma
-- (galerías, salas y pozos, con el suelo en `from`/`to`/`center`); server/Features/Mines les pone la utilería cuando hay
-- jugadores cerca, con la misma semilla (siempre igual).

export type MineTunnel = { from: Vector3, to: Vector3, width: number, height: number, rails: boolean, collapsed: boolean }
export type MineRoom = { center: Vector3, size: Vector3, yaw: number, kind: string }
export type Mine = {
	id: number,
	layer: number,
	camp: boolean,
	gallery: boolean?, -- tramo de una galería de un hub (sin letrero de sector)
	failed: boolean?, -- no se pudo tallar (no se reintenta)
	center: Vector3, -- suelo de la sala central
	tunnels: { MineTunnel },
	rooms: { MineRoom },
	shaft: { from: Vector3, height: number }?,
	seed: number,
	bottomDepth: number,
	carved: boolean,
}

local ROOM_KINDS = { "Almacen", "Taller", "Dormitorio", "Almacen", "Taller" }
local mines: { Mine } = {}
local minesByLayer: { [number]: { Mine } } = {}

-- Planea todas las minas de una vez (misma semilla = mismas minas).
local function planMines()
	local spec = Config.Mines
	local rng = Random.new(seed + 23)
	local up = Vector3.yAxis
	for i = 2, #Config.Layers do
		minesByLayer[i] = {}
		local top, bottom = layerTop(i) + spec.Margin, Config.Layers[i].MaxDepth - spec.Margin
		for n = 1, spec.Complexes + spec.Camps do
			local camp = n > spec.Complexes
			local spacing = if camp then spec.Spacing / 2 else spec.Spacing
			local clearance = if camp then spec.PitClearance / 2 else spec.PitClearance
			for _ = 1, 25 do
				local a, d = rng:NextNumber(0, math.pi * 2), clearance + math.sqrt(rng:NextNumber(0, 1)) * (spec.Radius - clearance)
				local center = Vector3.new(Config.PitCenter.X + math.cos(a) * d, -rng:NextNumber(top, bottom), Config.PitCenter.Y + math.sin(a) * d)
				local ok = true
				for _, other in minesByLayer[i] do
					local need = if other.camp or camp then spacing else spec.Spacing
					if (other.center - center).Magnitude < need then ok = false break end
				end
				if ok then
					local mine: Mine = {
						id = #mines + 1, layer = i, camp = camp, center = center, tunnels = {}, rooms = {}, shaft = nil,
						seed = rng:NextInteger(1, 1e9), bottomDepth = -center.Y + 40, carved = false,
					}
					local size = spec.TunnelSize
					if camp then
						table.insert(mine.rooms, { center = center, size = Vector3.new(rng:NextNumber(13, 17), 9, rng:NextNumber(13, 17)), yaw = a, kind = "Campamento" })
						local dir = Vector3.new(math.cos(a + rng:NextNumber(-1, 1)), 0, math.sin(a + rng:NextNumber(-1, 1)))
						table.insert(mine.tunnels, { from = center, to = center + dir * rng:NextNumber(20, 35), width = spec.BranchSize.X, height = spec.BranchSize.Y, rails = false, collapsed = rng:NextNumber() < 0.5 })
					else
						table.insert(mine.rooms, { center = center, size = Vector3.new(rng:NextNumber(22, 30), 13, rng:NextNumber(22, 30)), yaw = rng:NextNumber(0, math.pi), kind = ROOM_KINDS[rng:NextInteger(1, #ROOM_KINDS)] })
						local count = rng:NextInteger(spec.Tunnels[1], spec.Tunnels[2])
						local base = rng:NextNumber(0, math.pi * 2)
						for k = 1, count do
							local angle = base + (k - 1) * math.pi * 2 / count + rng:NextNumber(-0.3, 0.3)
							local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
							local length = rng:NextNumber(spec.TunnelLength[1], spec.TunnelLength[2])
							local rise = math.clamp(rng:NextNumber(-0.12, 0.12) * length, -(bottom + spec.Margin / 2 + center.Y), -center.Y - (top - spec.Margin / 2))
							local to = center + dir * length + up * rise
							local ending = rng:NextNumber()
							table.insert(mine.tunnels, { from = center, to = to, width = size.X, height = size.Y, rails = rng:NextNumber() < 0.65, collapsed = ending > 0.75 })
							if ending < 0.45 then -- sala al final de la galería
								local kind = ROOM_KINDS[rng:NextInteger(1, #ROOM_KINDS)]
								table.insert(mine.rooms, { center = to + dir * 6, size = Vector3.new(rng:NextNumber(14, 19), 10, rng:NextNumber(14, 19)), yaw = angle, kind = kind })
							end
							if rng:NextNumber() < 0.35 then -- ramal desde la mitad
								local side = angle + (if rng:NextNumber() < 0.5 then 1 else -1) * rng:NextNumber(0.9, 1.4)
								local from = center:Lerp(to, rng:NextNumber(0.4, 0.7))
								local branchTo = from + Vector3.new(math.cos(side), 0, math.sin(side)) * rng:NextNumber(30, 60)
								table.insert(mine.tunnels, { from = from, to = branchTo, width = spec.BranchSize.X, height = spec.BranchSize.Y, rails = false, collapsed = rng:NextNumber() < 0.3 })
							end
						end
						if rng:NextNumber() < spec.ShaftChance then
							mine.shaft = { from = center + up * 13, height = rng:NextNumber(spec.ShaftHeight[1], spec.ShaftHeight[2]) }
						end
					end
					table.insert(mines, mine)
					table.insert(minesByLayer[i], mine)
					break
				end
			end
		end
	end
end

-- Talla una mina en la roca: galerías de techo plano, salas, derrumbes y el pozo.
local function carveMine(mine: Mine)
	local rng = Random.new(mine.seed)
	local up = Vector3.yAxis
	for _, room in mine.rooms do
		local frame = CFrame.new(room.center + up * (room.size.Y / 2)) * CFrame.Angles(0, room.yaw, 0)
		Terrain:FillBlock(frame, room.size, Enum.Material.Air)
		Terrain:FillBall(room.center + up * room.size.Y, math.min(room.size.X, room.size.Z) * 0.32, Enum.Material.Air) -- techo irregular
	end
	for _, t in mine.tunnels do
		local length = (t.to - t.from).Magnitude
		local a, b = t.from + up * (t.height / 2), t.to + up * (t.height / 2)
		Terrain:FillBlock(CFrame.lookAt((a + b) / 2, b), Vector3.new(t.width, t.height, length + t.width * 0.4), Enum.Material.Air)
		for _ = 1, math.floor(length / 30) do -- paredes menos rectas
			local p = t.from:Lerp(t.to, rng:NextNumber(0.15, 0.85)) + up * (t.height * 0.6)
			Terrain:FillBall(p, t.width * rng:NextNumber(0.45, 0.6), Enum.Material.Air)
		end
		if t.collapsed then -- derrumbe: roca caída que tapa el final
			local p = t.to + up * (t.height * 0.35)
			Terrain:FillBall(p, t.width * 0.75, materialAt(p.X, p.Z, -p.Y))
		end
	end
	if mine.shaft then
		local s = mine.shaft
		Terrain:FillBlock(CFrame.new(s.from + up * (s.height / 2)), Vector3.new(7, s.height, 7), Enum.Material.Air)
	end
	mine.carved = true
end

-- Caja que ocupa una mina (para generar sus celdas antes de tallarla).
local function mineBounds(mine: Mine): (Vector3, Vector3)
	local low, high = mine.center, mine.center
	local function add(p: Vector3, pad: number, up: number)
		low = low:Min(p - Vector3.new(pad, 4, pad))
		high = high:Max(p + Vector3.new(pad, up, pad))
	end
	for _, room in mine.rooms do add(room.center, math.max(room.size.X, room.size.Z), room.size.Y * 1.4) end
	for _, t in mine.tunnels do
		add(t.from, t.width, t.height + 4)
		add(t.to, t.width, t.height + 4)
	end
	if mine.shaft then add(mine.shaft.from, 6, mine.shaft.height + 4) end
	return low, high
end
-- Hubs de las capas ---------------------------------------------------------------
-- Una caverna alrededor del pozo en cada capa (shared/HubLayout; la de la capa 1 es la cueva del foso): el pozo queda
-- abierto en medio (LayerHubs le pone baranda y elevador). Cada hub tiene el túnel corto de su estación de carritos y,
-- de la capa 2 hacia abajo, galerías hacia las minas de su capa (se amueblan como minas).
local hubCarved: { [number]: boolean } = {}

-- túnel solo para carritos, en la pared del hub (Carts le pone rieles y una reja que no deja pasar a los jugadores)
local function carveStationTunnel(hub)
	local s = hub.station
	local up = Vector3.yAxis
	local a, b = s.mouth - s.dir * 4 + up * 4.5, s.tunnelEnd + up * 4.5
	Terrain:FillBlock(CFrame.lookAt((a + b) / 2, b), Vector3.new(8, 9, (b - a).Magnitude), Enum.Material.Air)
end

-- Galerías del hub hacia minas de su capa: en cada dirección, el complejo más cercano al que se llega con pendiente
-- suave; si no hay ninguno, una galería recta que termina en una sala. Se agregan a `mines` por tramos (para que Mines
-- los amueble solo cerca de los jugadores) y se tallan como minas.
local function carveGalleries(hub)
	local spec = ProgressionConfig.Hub
	local rng = Random.new(seed + 31 + hub.layer)
	local up = Vector3.yAxis
	for k = 1, spec.Galleries do
		local angle = math.pi / 4 + (k - 1) * math.pi * 2 / spec.Galleries + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local start = hub.center + dir * (hub.radius - 6)
		local best, bestDist = nil, math.huge
		for _, mine in minesByLayer[hub.layer] or {} do
			if not mine.camp then
				local flat = Vector3.new(mine.center.X - start.X, 0, mine.center.Z - start.Z)
				local dist = flat.Magnitude
				if dist > 40 and flat.Unit:Dot(dir) > 0.75 and math.abs(mine.center.Y - start.Y) / dist <= spec.MaxSlope and dist < bestDist then
					best, bestDist = mine, dist
				end
			end
		end
		local finish = if best then best.center else start + dir * rng:NextNumber(140, 190)
		local rooms = {}
		if not best then
			table.insert(rooms, { center = finish + dir * 6, size = Vector3.new(18, 11, 18), yaw = angle, kind = ROOM_KINDS[rng:NextInteger(1, #ROOM_KINDS)] })
		end
		local length = (finish - start).Magnitude
		local pieces = math.max(math.ceil(length / 100), 1)
		for n = 1, pieces do
			local a, b = start:Lerp(finish, (n - 1) / pieces), start:Lerp(finish, n / pieces)
			local gallery: Mine = {
				id = #mines + 1, layer = hub.layer, camp = false, gallery = true, center = (a + b) / 2,
				tunnels = { { from = a, to = b, width = spec.GallerySize.X, height = spec.GallerySize.Y, rails = true, collapsed = false } },
				rooms = if n == pieces then rooms else {}, shaft = nil,
				seed = rng:NextInteger(1, 1e9), bottomDepth = 0, carved = false,
			}
			local low, high = mineBounds(gallery)
			ensureBox(low, high)
			carveMine(gallery)
			table.insert(mines, gallery)
		end
		-- boca de la galería: un poco más ancha, sin escalón con el piso del hub
		local mouth = start + up * (spec.GallerySize.Y / 2)
		Terrain:FillBlock(CFrame.lookAt(mouth, mouth + dir), Vector3.new(spec.GallerySize.X + 4, spec.GallerySize.Y, 16), Enum.Material.Air)
	end
end

-- Talla el hub de una capa profunda (primero genera sus celdas; sus galerías aseguran las suyas).
local function carveLayerHub(hub)
	local reach = hub.radius + 60
	ensureBox(hub.center - Vector3.new(reach, 20, reach), hub.center + Vector3.new(reach, hub.height + hub.domeRadius + 10, reach))
	carveCavern(hub.center + Vector3.yAxis * (hub.height / 2), hub.radius, hub.height, hub.domeRadius)
	carveStationTunnel(hub)
	carveGalleries(hub)
	hubCarved[hub.layer] = true
end
-- El núcleo: una esfera incandescente al fondo del pozo, visible desde la superficie.
local function buildCore()
	local core = Instance.new("Part")
	core.Name, core.Shape, core.Anchored = "Core", Enum.PartType.Ball, true
	core.Size = Vector3.one * Config.CoreRadius * 2
	core.Position = Vector3.new(Config.PitCenter.X, CORE_FLOOR + Config.CoreRadius * 0.6, Config.PitCenter.Y)
	core.Material, core.Color = Enum.Material.Neon, Config.CoreColor
	core:SetAttribute("Core", true) -- marcador para la muerte por caída (pendiente)
	core.Parent = workspace

	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = Config.CoreColor, 60, 6, false
	glow.Parent = core

	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Config.CoreColor)
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime, embers.Speed = NumberRange.new(4, 7), NumberRange.new(8, 22)
	embers.EmissionDirection, embers.SpreadAngle = Enum.NormalId.Top, Vector2.new(25, 25)
	embers.LightEmission, embers.Rate = 1, 30
	embers.Parent = core
end

local function buildBorders()
	local half, thick = Config.HalfSize, 4
	local function wall(pos: Vector3, size: Vector3)
		local p = Instance.new("Part")
		p.Name, p.Anchored, p.Transparency, p.CanQuery = "WorldBorder", true, 1, false
		p.Size, p.Position = size, pos
		p.Parent = workspace
	end
	local tall = Config.Depth + 300
	for _, s in { -1, 1 } do
		wall(Vector3.new(s * (half + thick / 2), -Config.Depth / 2 + 100, 0), Vector3.new(thick, tall, half * 2 + thick * 2))
		wall(Vector3.new(0, -Config.Depth / 2 + 100, s * (half + thick / 2)), Vector3.new(half * 2 + thick * 2, tall, thick))
	end
end

local function buildSpawn()
	local spawn = Instance.new("SpawnLocation") -- invisible: solo marca dónde aparecen los jugadores
	spawn.Anchored, spawn.Neutral, spawn.Duration = true, true, 0
	spawn.Size, spawn.Position, spawn.Transparency = Vector3.new(14, 1, 14), Config.SpawnPosition, 1
	spawn.CanCollide, spawn.CanQuery, spawn.CanTouch = false, false, false -- no estorba disparos ni gancho
	spawn.Parent = workspace
end

-- Minerales y luces ----------------------------------------------------------

local mineralFolder, lightFolder
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = { Terrain }

local function pickWeighted(rng: Random, weights: { [any]: number }): any
	local total = 0
	for _, w in weights do total += w end
	local roll = rng:NextNumber(0, total)
	for key, w in weights do
		roll -= w
		if roll <= 0 then return key end
	end
	return next(weights)
end

-- suelo bajo `p` si `p` está en aire; nil si está dentro de roca o no hay suelo cerca
local function floorBelow(p: Vector3, reach: number): RaycastResult?
	local cell = Terrain:ReadVoxels(Region3.new(p - Vector3.one * 0.5, p + Vector3.one * 0.5):ExpandToGrid(RES), RES)
	if cell[1][1][1] ~= Enum.Material.Air then return nil end
	return workspace:Raycast(p, Vector3.new(0, -reach, 0), floorParams)
end

local function newMineral(rarity: string, pos: Vector3)
	local p = Instance.new("Part")
	p.Size = Vector3.new(1, 1.6, 1)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.random() * 6, math.rad(20))
	p.Anchored, p.Material, p.Color = true, Enum.Material.Neon, MineralData[rarity].Color
	p:SetAttribute("Rarity", rarity)
	p:SetAttribute("MaxHealth", MineralData[rarity].Health)
	CollectionService:AddTag(p, "Mineral")
	local glow = Instance.new("PointLight") -- los minerales se ven desde lejos en la oscuridad
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = MineralData[rarity].Color, 14, 1, false
	glow.Parent = p
	p.Parent = mineralFolder
end

local function newCrystal(pos: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.8, 2, 0.8)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.random() * 6, 0)
	p.Anchored, p.CanCollide, p.CanQuery, p.Material, p.Color = true, false, false, Enum.Material.Neon, color
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = color, Config.LightRange, Config.LightBrightness, false
	light.Parent = p
	p.Parent = lightFolder
end

-- ¿Se puede excavar una esfera de `radius` en `pos`? No: el caparazón del pozo (sería un atajo al núcleo), las cuevas
-- de la base y del foso con su caparazón, y el fondo del mundo. Se prueban el centro y los extremos de la esfera.
local function canDig(pos: Vector3, radius: number): boolean
	local pitSealR = Config.PitRadius + Config.PitRagged + Config.PitSeal
	local offsets = { Vector3.zero, Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis, Vector3.yAxis, -Vector3.yAxis }
	for _, o in offsets do
		local p = pos + o * radius
		if p.Y < CORE_FLOOR then return false end
		local fromPit = Vector2.new(p.X, p.Z) - Config.PitCenter
		if p.Y < HUB_FLOOR and fromPit.Magnitude < pitSealR then return false end
		local low, high = shellRange(p.X, p.Z)
		if low and p.Y >= low and p.Y <= high then return false end
	end
	return true
end

local CAVE_LAYER_BOTTOM = Config.CaveZoneDepth -- solo la zona de cuevas tiene cuevas (las primeras capas)

-- capa elegida por peso entre las que ya tienen algo generado (la 1 al inicio; las profundas, por celdas) y más hondas
-- que `minDepth`; nil si no hay
local function pickLayer(rng: Random, minDepth: number?): number?
	local low = math.max(minDepth or 8, 8)
	local weights = {}
	for i, layer in Config.Layers do
		local ready = if i == 1 then generatedDepth > 0 else deepCells[i] ~= nil
		if ready and layer.MaxDepth > low then weights[i] = layer.SpawnWeight end
	end
	if next(weights) == nil then return nil end
	return pickWeighted(rng, weights)
end

-- profundidad al azar dentro de la capa, sin pasar de lo generado, de `minDepth` ni de `maxDepth`; nil si no cabe
local function depthInLayer(rng: Random, i: number, minDepth: number?, maxDepth: number?): number?
	local top = math.max(layerTop(i), minDepth or 8, 8)
	local bottom = math.min(Config.Layers[i].MaxDepth, generatedDepth, maxDepth or math.huge) - 4
	if bottom <= top then return nil end
	return rng:NextNumber(top, bottom)
end

-- punto (x, z) al azar dentro del radio de cuevas, alrededor del pozo
local function pointNearPit(rng: Random, margin: number): (number, number)
	local a, r = rng:NextNumber(0, math.pi * 2), math.sqrt(rng:NextNumber(0, 1)) * (Config.CaveRadius - margin)
	return Config.PitCenter.X + math.cos(a) * r, Config.PitCenter.Y + math.sin(a) * r
end

-- punto de aire al azar en las cuevas de la capa `i` (dentro de la zona de cuevas), con su suelo; nil si no se halló
local function randomCavePoint(rng: Random, i: number, minDepth: number?): RaycastResult?
	if (minDepth or 0) >= CAVE_LAYER_BOTTOM then return nil end
	for _ = 1, 40 do
		local d = depthInLayer(rng, i, minDepth, CAVE_LAYER_BOTTOM)
		if not d then return nil end
		local x, z = pointNearPit(rng, 8)
		local hit = floorBelow(Vector3.new(x, -d, z), 50)
		if hit then return hit end
	end
	return nil
end

-- Un grupo (1 o varios cerca) a partir de `hit`. Devuelve cuántos puso.
local function placeCluster(rng: Random, hit: RaycastResult): number
	local size = Config.ClusterSizes[rng:NextInteger(1, #Config.ClusterSizes)]
	local count = 0
	for c = 1, size do
		local spot = hit
		if c > 1 then
			spot = floorBelow(hit.Position + Vector3.new(rng:NextNumber(-5, 5), 3, rng:NextNumber(-5, 5)), 12)
		end
		if spot then
			local rarity = pickWeighted(rng, Config.Layers[layerIndex(-spot.Position.Y)].Rarity)
			newMineral(rarity, spot.Position + spot.Normal * 0.9)
			count += 1
		end
	end
	return count
end

-- Veta: varios minerales juntos incrustados en la roca maciza de una capa profunda, dentro de una celda ya generada
-- ({ x0, z0, profundidad de arriba, de abajo }); se encuentran excavando y su brillo se nota un poco a través de la
-- roca. Devuelve cuántos puso.
local function placeVeinIn(rng: Random, cell: { number }, i: number): number
	local x0, z0, top, bottom = cell[1], cell[2], cell[3], cell[4]
	if bottom - top < 16 then return 0 end
	local center = Vector3.new(rng:NextNumber(x0 + 8, x0 + CHUNK - 8), -rng:NextNumber(top + 8, bottom - 8), rng:NextNumber(z0 + 8, z0 + CHUNK - 8))
	if not canDig(center, 6) then return 0 end -- nunca dentro de zonas protegidas (el pozo y su caparazón)
	local count = 0
	for _ = 1, rng:NextInteger(2, 5) do
		local spot = center + Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-3, 3), rng:NextNumber(-4, 4))
		newMineral(pickWeighted(rng, Config.Layers[i].Rarity), spot)
		count += 1
	end
	return count
end

-- Veta en una celda generada al azar de la capa `i`.
local function placeVein(rng: Random, i: number): number
	local cells = deepCells[i]
	if not cells then return 0 end
	return placeVeinIn(rng, cells[rng:NextInteger(1, #cells)], i)
end

-- Un grupo en el suelo de una mina ya tallada (`mine`, o una al azar de la capa `i`), en una sala o en una galería.
-- Devuelve cuántos puso.
local function placeMineMinerals(rng: Random, i: number, mine: Mine?): number
	if not mine then
		local list = minesByLayer[i]
		if not list or #list == 0 then return 0 end
		for _ = 1, 6 do -- una ya tallada (las demás todavía no existen)
			local pick = list[rng:NextInteger(1, #list)]
			if pick.carved then mine = pick break end
		end
	end
	if not mine or not mine.carved then return 0 end
	local p
	if rng:NextNumber() < 0.5 and #mine.rooms > 0 then
		local room = mine.rooms[rng:NextInteger(1, #mine.rooms)]
		local spread = math.min(room.size.X, room.size.Z) * 0.3
		p = room.center + Vector3.new(rng:NextNumber(-spread, spread), 4, rng:NextNumber(-spread, spread))
	else
		local t = mine.tunnels[rng:NextInteger(1, #mine.tunnels)]
		p = t.from:Lerp(t.to, rng:NextNumber(0.2, 0.8)) + Vector3.yAxis * 4
	end
	local hit = floorBelow(p, 12)
	return if hit then placeCluster(rng, hit) else 0
end

-- Llena el pool hasta `cap` minerales (o `limit` grupos): en la capa 1, grupos sobre el suelo de las cuevas; más
-- abajo (solo en lo ya generado), parte en el suelo de las minas y el resto en vetas dentro de la roca. Un intento
-- fallido no corta el llenado.
local function fillMinerals(rng: Random, limit: number, cap: number, minDepth: number?)
	local have = #CollectionService:GetTagged("Mineral")
	local misses = 0
	while have < cap and limit > 0 and misses < 25 do
		local i = pickLayer(rng, minDepth)
		local placed = 0
		if i and layerTop(i) < CAVE_LAYER_BOTTOM then
			local hit = randomCavePoint(rng, i, minDepth)
			if hit then placed = placeCluster(rng, hit) end
		elseif i then
			if rng:NextNumber() < Config.Mines.MineralShare then placed = placeMineMinerals(rng, i) end
			if placed == 0 then placed = placeVein(rng, i) end
		end
		if placed > 0 then
			have += placed
			limit -= 1
		else
			misses += 1
		end
	end
end
-- Luces y minerales propios de cada arena, sobre sus salientes y su fondo.
local function furnishArena(arena: Arena)
	local rng = arena.rng
	local function spotInside(): RaycastResult?
		for _ = 1, 20 do
			local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, arena.radius * 0.85)
			local p = arena.center + Vector3.new(math.cos(a) * d, rng:NextNumber(-arena.height / 2, arena.height / 2), math.sin(a) * d)
			local hit = floorBelow(p, arena.height + arena.radius)
			if hit then return hit end
		end
		return nil
	end
	local color = lightColor(-arena.center.Y)
	for _ = 1, Config.Arenas.Lights do
		local hit = spotInside()
		if hit then newCrystal(hit.Position + hit.Normal * 0.9, color) end
	end
	for _ = 1, Config.Arenas.MineralClusters do
		local hit = spotInside()
		if hit then placeCluster(rng, hit) end
	end
end

-- Unos cuantos minerales en el piso de la base (lejos de la rejilla), para probar sin salir.
local function placeHubMinerals(rng: Random)
	local hub = Config.Hub
	local placed = 0
	for _ = 1, hub.Minerals * 10 do
		if placed >= hub.Minerals then break end
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(Config.PitRadius + 20, hub.Radius - 12)
		local hit = floorBelow(hub.Center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), hub.Height)
		if hit and hit.Normal.Y > 0.6 then
			newMineral(pickWeighted(rng, Config.Layers[1].Rarity), hit.Position + hit.Normal * 0.9)
			placed += 1
		end
	end
end

-- Minerales a la vista sobre la meseta: rayo desde arriba en puntos al azar (en todo el mundo o cerca de `center`).
local function spawnSurfaceMinerals(rng: Random, count: number, center: Vector2?, radius: number)
	local lim = Config.HalfSize - 20
	local placed = 0
	for _ = 1, count * 20 do
		if placed >= count then break end
		local x, z
		if center then
			local a, r = rng:NextNumber(0, math.pi * 2), math.sqrt(rng:NextNumber(0, 1)) * radius
			x, z = center.X + math.cos(a) * r, center.Y + math.sin(a) * r
		else
			x, z = rng:NextNumber(-lim, lim), rng:NextNumber(-lim, lim)
		end
		local hit = workspace:Raycast(Vector3.new(x, TOP + 20, z), Vector3.new(0, -(TOP + 400), 0), floorParams)
		if hit and hit.Position.Y > -5 and hit.Normal.Y > 0.6 then -- solo la superficie (no el fondo del pozo ni laderas empinadas)
			newMineral(pickWeighted(rng, Config.Layers[1].Rarity), hit.Position + hit.Normal * 0.9)
			placed += 1
		end
	end
end

local function spawnLights(rng: Random, count: number, minDepth: number?)
	for _ = 1, count do
		local i = pickLayer(rng, minDepth)
		local hit = i and layerTop(i) < CAVE_LAYER_BOTTOM and randomCavePoint(rng, i, minDepth)
		if hit then
			newCrystal(hit.Position + hit.Normal * 0.9, lightColor(-hit.Position.Y))
		end
	end
end

-- Cada fase va protegida: si una falla se avisa en el Output y el resto sigue, y los jugadores siempre acaban apareciendo.
local function phase(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then warn(`[World] fase "{name}" falló: {err}`) end
end

return {
	-- para otras features (Excavation, Route)
	Route = route, -- segmentos de la ruta principal (completa cuando WorldReady = true)
	CanDig = canDig,
	Hubs = hubCarved, -- [capa] = true cuando su hub ya está tallado (shared/HubLayout)
	Mines = mines, -- minas abandonadas (server/Features/Mines les pone la utilería); `carved` = ya talladas
	Hardness = function(depth: number): number
		return Config.Layers[layerIndex(depth)].Hardness
	end,

	Start = function()
		workspace:SetAttribute("WorldReady", false) -- el cliente muestra "Generando mundo" hasta que sea true
		if workspace.FallenPartsDestroyHeight > -Config.Depth then
			warn(`[World] FallenPartsDestroyHeight es {workspace.FallenPartsDestroyHeight}: quien baje de ahí muere. Se ajusta en default.project.json (Workspace) y se aplica al conectar Rojo.`)
		end
		Players.CharacterAutoLoads = false
		for material, color in BiomeMap.MaterialColors do -- color de la roca de los biomas (Roblox colorea el terreno por material)
			Terrain:SetMaterialColor(material, color)
		end
		-- la base gris de las plantillas de Roblox tapa la meseta (su cara de arriba está en y = 0): se quita
		local baseplate = workspace:FindFirstChild("Baseplate")
		if baseplate then baseplate:Destroy() end

		local t0 = os.clock()
		local stats = {}
		for i in Config.Layers do stats[i] = { 0, 0 } end
		local arenas = planArenas()
		phase("plan de minas", planMines)
		local entrances = {}
		local starter: Vector3? = nil

		-- 1) La capa 1 cerca del centro, antes de dejar entrar a nadie (lo demás se genera por celdas, ver ensureBox).
		phase("terreno inicial", function()
			Terrain:Clear()
			generateStart(stats)
		end)
		phase("entradas", function() entrances = carveEntrances() end)
		phase("base", function()
			starter = carveHub()
			carveStationTunnel(HubLayout.Get(1)) -- estación de carritos de la cueva del foso
			hubCarved[1] = true
		end)
		phase("arenas", function() carveReadyArenas(arenas, entrances, starter) end)
		phase("núcleo", buildCore)
		phase("bordes", buildBorders)
		phase("spawn", buildSpawn)

		mineralFolder = Instance.new("Folder")
		mineralFolder.Name = "WorldMinerals"
		mineralFolder.Parent = workspace
		lightFolder = Instance.new("Folder")
		lightFolder.Name = "CaveLights"
		lightFolder.Parent = workspace
		local rng = Random.new(seed + 1) -- misma distribución inicial todo el día
		phase("minerales de la meseta", function()
			spawnSurfaceMinerals(rng, Config.SurfaceMinerals, nil, 0)
		end)
		phase("minerales de la base", function() placeHubMinerals(rng) end)
		phase("arenas: luces y minerales", function()
			for _, arena in arenas do
				if arena.carved then furnishArena(arena) end
			end
		end)
		phase("minerales de las cuevas", function()
			fillMinerals(rng, math.huge, math.floor(Config.MineralCount * Config.InitialMineralShare))
		end)
		phase("luces", function() spawnLights(rng, Config.LightCount) end)
		local s1 = stats[1]
		print(`[World] semilla {seed}, capa 1 lista en {string.format("%.1f", os.clock() - t0)} s ({string.format("%.0f", 100 * s1[1] / math.max(s1[2], 1))}% de aire), {#CollectionService:GetTagged("Mineral")} minerales`)

		-- Todos aparecen (o reaparecen) en el spawn, incluso quien haya salido antes de tiempo y caído al vacío.
		Players.CharacterAutoLoads = true
		workspace:SetAttribute("WorldReady", true)
		for _, p in Players:GetPlayers() do
			task.spawn(function() p:LoadCharacter() end)
		end

		-- las explosiones de minerales excavan en Excavation.luau (respetando la dureza y las zonas protegidas)

		-- 2) En segundo plano: la columna del pozo hasta el núcleo y la cámara del núcleo.
		task.spawn(function()
			phase("pozo", function() generatePitColumn(stats) end)
			phase("cámara del núcleo", function()
				local core = arenas[#arenas]
				if core and core.isCore and not core.carved then
					carveArena(core)
					furnishArena(core)
				end
			end)
			print(`[World] pozo completo hasta el núcleo en {string.format("%.1f", os.clock() - t0)} s`)
		end)

		-- 3) Bajo demanda: alrededor de cada jugador se generan las celdas que falten, se tallan las minas y los hubs
		-- cercanos y se siembran minerales en la roca nueva (todo lo lejano no existe hasta que alguien llegue).
		local spec = Config.Generation
		local seedRng = Random.new(seed + 41)
		onDeepCell = function(x0, z0, top, bottom, i)
			if #CollectionService:GetTagged("Mineral") >= Config.MineralCount then return end
			local expected = Config.Layers[i].SpawnWeight * spec.VeinsPerWeight * (bottom - top) / Config.BandHeight
			for _ = 1, math.floor(expected + seedRng:NextNumber()) do
				placeVeinIn(seedRng, { x0, z0, top, bottom }, i)
			end
		end
		local function generateNear(pos: Vector3)
			local reach = Vector3.new(spec.Radius, spec.Vertical, spec.Radius)
			ensureBox(pos - reach, pos + reach, stats)
			for _, mine in mines do
				if not mine.carved and not mine.failed and (mine.center - pos).Magnitude < spec.MineRange then
					local ok, err = pcall(function()
						local low, high = mineBounds(mine)
						ensureBox(low, high, stats)
						carveMine(mine)
						if #CollectionService:GetTagged("Mineral") < Config.MineralCount then
							for _ = 1, seedRng:NextInteger(1, 3) do placeMineMinerals(seedRng, mine.layer, mine) end
						end
					end)
					if not ok then
						mine.failed = true
						warn(`[World] no se pudo tallar la mina {mine.id}: {err}`)
					end
				end
			end
			for i, hub in HubLayout.All do
				if not hub.main and not hubCarved[i] and (hub.center - pos).Magnitude < spec.HubRange then
					phase(`hub de la capa {i}`, function() carveLayerHub(hub) end)
					hubCarved[i] = true -- aunque falle, no reintentar cada vez
				end
			end
		end
		-- Con el tope de minerales lleno, los de las capas profundas lejos de todos los jugadores se reciclan, para que la
		-- roca nueva (donde sí hay jugadores) reciba los suyos.
		local function recycleMinerals(positions: { Vector3 })
			local all = CollectionService:GetTagged("Mineral")
			local excess = #all - math.floor(Config.MineralCount * spec.RecycleTo)
			if #all < Config.MineralCount * spec.RecycleAt or excess <= 0 then return end
			for _, mineral in all do
				if excess <= 0 then break end
				local pos = (mineral :: PVInstance):GetPivot().Position
				if pos.Y < -Config.CaveZoneDepth and mineral:IsDescendantOf(mineralFolder) then
					local far = true
					for _, p in positions do
						if (p - pos).Magnitude < spec.RecycleDistance then far = false break end
					end
					if far then
						mineral:Destroy()
						excess -= 1
					end
				end
			end
		end
		task.spawn(function()
			local ticks = 0
			local checkedAt: { [any]: Vector3 } = {} -- dónde se revisó por última vez a cada jugador
			while true do
				task.wait(spec.Interval)
				ticks += 1
				local positions = {}
				local present = {}
				for _, p in Players:GetPlayers() do
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					if root then
						local pos = root.Position
						table.insert(positions, pos)
						present[p] = true
						-- solo si se movió lo suficiente desde la última revisión (quieto no hay nada nuevo que generar)
						local last = checkedAt[p]
						if not last or (pos - last).Magnitude >= spec.Recheck then
							checkedAt[p] = pos
							phase("cerca de jugadores", function() generateNear(pos) end)
						end
					end
				end
				for p in checkedAt do
					if not present[p] then checkedAt[p] = nil end
				end
				if ticks % 10 == 0 then phase("reciclaje de minerales", function() recycleMinerals(positions) end) end
			end
		end)

		-- 4) Reposición de minerales (en la capa 1 y en lo ya generado de las demás).
		task.spawn(function()
			local respawnRng = Random.new()
			while true do
				task.wait(Config.RespawnInterval)
				phase("reposición", function() fillMinerals(respawnRng, Config.RespawnBatch, Config.MineralCount) end)
			end
		end)	end,
}
