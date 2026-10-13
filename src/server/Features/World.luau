-- Mundo: meseta enorme con un pozo estrecho y vertical que baja directo al núcleo, hecho con Terrain por código.
--  · Bajo la meseta hay capas de roca con cuevas naturales.
--  · Cueva de la base (spawn, bases y tiendas) unida por una gran puerta de arco a la cueva del foso: caverna enorme
--    bajo el centro con el pozo al núcleo en su piso, tapado por una rejilla (Hub.luau pone la puerta, la rejilla, luces
--    y máquinas). El pozo está sellado: ninguna cueva ni túnel lo cruza.
--  · Superficie llana en el centro con lomas y montañas hacia los bordes; entradas repartidas (rampas y pozos).
--  · Al fondo, la cámara del núcleo: el último eslabón de la cadena de arenas.
--  · Cavernas-arena por capa (grandes y verticales, con salientes, pilares y estalactitas para el gancho), unidas por
--    una cadena de túneles desde una entrada de la meseta hasta lo más profundo.
--  · Iluminación del subsuelo con cristales luminosos; los minerales también brillan.
--  · Pool de minerales por capas (más raros hacia el núcleo), repuestos con el tiempo, más unos cuantos a la vista.
--  · Las explosiones de minerales excavan el terreno (Minerals.Exploded).
-- Se genera por franjas de arriba hacia abajo: los jugadores entran cuando está lista Config.ReadyDepth y el resto
-- se genera en segundo plano. El límite de caída (FallenPartsDestroyHeight) va en default.project.json: un script
-- no tiene permiso para cambiarlo.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.World)
local MineralData = require(ReplicatedStorage.Shared.Config.Minerals)
local MineralsFeature = require(script.Parent.Minerals)

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

local function materialAt(depth: number): Enum.Material
	for _, m in Config.Materials do
		if depth <= m[1] then return m[2] end
	end
	return Enum.Material.Rock
end

local function layerIndex(depth: number): number
	for i, layer in Config.Layers do
		if depth <= layer.MaxDepth then return i end
	end
	return #Config.Layers
end

local function layerTop(i: number): number
	return if i == 1 then 0 else Config.Layers[i - 1].MaxDepth
end

-- Datos por fila de voxel (dependen solo de la profundidad), calculados una vez. Fila 1 = la más profunda.
local NY = (Config.Depth + TOP) / RES
local rowMat, rowLayer, rowWidth, rowThr = table.create(NY), table.create(NY), table.create(NY), table.create(NY)
for j = 1, NY do
	local depth = -(-Config.Depth + (j - 0.5) * RES)
	local t = math.clamp(depth / Config.Depth, 0, 1)
	rowMat[j], rowLayer[j] = materialAt(depth), layerIndex(depth)
	rowWidth[j] = Config.TunnelWidth[1] + (Config.TunnelWidth[2] - Config.TunnelWidth[1]) * t
	rowThr[j] = Config.CavernThreshold[1] + (Config.CavernThreshold[2] - Config.CavernThreshold[1]) * t
end

local CORE_FLOOR = -Config.Depth + Config.CoreHeight -- bajo esta altura el pozo termina en roca sólida
local PIT_NEAR2 = (Config.PitRadius + Config.PitRagged + 2 * RES) ^ 2
local PIT_SEAL2 = (Config.PitRadius + Config.PitRagged + Config.PitSeal) ^ 2 -- aquí no se abren cuevas
local HUB_FLOOR = Config.Hub.Center.Y - Config.Hub.Height / 2 -- el pozo empieza en el piso de la base

-- Caparazón de roca maciza alrededor de la cueva de la base, la del foso y el pasaje entre ellas: ahí no se abren
-- cuevas naturales (las cuevas empiezan desde la cámara de cruce). Devuelve el rango de alturas sellado en la columna
-- (x, z), o nil si la columna queda fuera.
local SHELL = Config.CaveShell
local SHELL_BOTTOM = HUB_FLOOR - SHELL
local function shellTop(cave): number
	return cave.Center.Y + cave.Height / 2 + cave.DomeRadius + SHELL
end
local HUB_XZ = Vector2.new(Config.Hub.Center.X, Config.Hub.Center.Z)
local SPAWN_XZ = Vector2.new(Config.SpawnCave.Center.X, Config.SpawnCave.Center.Z)
local function shellRange(x: number, z: number): (number?, number?)
	local p = Vector2.new(x, z)
	local top: number? = nil
	if (p - HUB_XZ).Magnitude <= Config.Hub.Radius + SHELL then top = shellTop(Config.Hub) end
	if (p - SPAWN_XZ).Magnitude <= Config.SpawnCave.Radius + SHELL then
		top = math.max(top or -math.huge, shellTop(Config.SpawnCave))
	end
	-- pasaje: distancia al segmento entre los centros de las dos cuevas
	local ab = SPAWN_XZ - HUB_XZ
	local t = math.clamp((p - HUB_XZ):Dot(ab) / ab:Dot(ab), 0, 1)
	if (p - (HUB_XZ + ab * t)).Magnitude <= Config.Gate.Width / 2 + SHELL then
		top = math.max(top or -math.huge, HUB_FLOOR + Config.Gate.Height + Config.Gate.Width / 2 + SHELL)
	end
	if top then return SHELL_BOTTOM, top end
	return nil, nil
end

-- ¿Un punto (x, z) cae sobre las cuevas de arriba (con su caparazón)? Para alejar de ahí las entradas de la superficie.
local function overCaves(x: number, z: number, extra: number): boolean
	local p = Vector2.new(x, z)
	return (p - HUB_XZ).Magnitude <= Config.Hub.Radius + SHELL + extra
		or (p - SPAWN_XZ).Magnitude <= Config.SpawnCave.Radius + SHELL + extra
		or (p - (HUB_XZ + SPAWN_XZ) / 2).Magnitude <= (SPAWN_XZ - HUB_XZ).Magnitude / 2 + extra
end

local generatedDepth = 0 -- hasta qué profundidad ya hay terreno (crece mientras se genera)

-- Genera las filas [jA, jB] de un bloque de CHUNK x CHUNK. stats[capa] = { aire, total } para ajustar las cuevas.
local function generateChunk(x0: number, z0: number, jA: number, jB: number, stats)
	local n = CHUNK / RES
	local f = Config.NoiseScale
	local mats, occs = table.create(n), table.create(n)
	local z1, z2, z3, dz2 = table.create(n), table.create(n), table.create(n), table.create(n)
	local heights = table.create(n) -- altura de la superficie por columna (i, k)
	local shellLow, shellHigh = table.create(n), table.create(n) -- rango sellado por columna (caparazón de las cuevas)
	local zs = table.create(n)
	for k = 1, n do
		local z = z0 + (k - 0.5) * RES
		zs[k], z1[k], z2[k], z3[k] = z, z * f + o1[3], z * f + o2[3], z * f + o3[3]
		dz2[k] = (z - Config.PitCenter.Y) ^ 2
	end
	for i = 1, n do
		local mi, oi = table.create(jB - jA + 1), table.create(jB - jA + 1)
		mats[i], occs[i] = mi, oi
		local x = x0 + (i - 0.5) * RES
		local x1, x2, x3 = x * f + o1[1], x * f + o2[1], x * f + o3[1]
		local dx2 = (x - Config.PitCenter.X) ^ 2
		for k = 1, n do
			heights[k] = surfaceHeight(x, zs[k])
			shellLow[k], shellHigh[k] = shellRange(x, zs[k])
		end
		for j = jA, jB do
			local y = -Config.Depth + (j - 0.5) * RES
			local y1, y2, y3 = y * f + o1[2], y * f + o2[2], y * f + o3[2]
			local mj, oj = table.create(n), table.create(n)
			mi[j - jA + 1], oi[j - jA + 1] = mj, oj
			local width, thr, layer = rowWidth[j], rowThr[j], rowLayer[j]
			for k = 1, n do
				local ground = heights[k]
				local below = ground - y -- profundidad bajo la superficie (con montañas)
				local occ = math.clamp(below / RES + 0.5, 0, 1)
				if occ > 0 then
					local r2 = dx2 + dz2[k]
					local low = shellLow[k]
					local sealed = (r2 < PIT_SEAL2 and y < HUB_FLOOR) -- roca maciza alrededor del pozo (sin atajos)
						or (low ~= nil and y >= low and y <= shellHigh[k]) -- caparazón de las cuevas de arriba
					if r2 < PIT_NEAR2 and y > CORE_FLOOR and y < HUB_FLOOR + RES then
						-- pozo vertical con paredes irregulares: aire dentro del radio
						local edge = Config.PitRadius + Config.PitRagged * math.noise(x * PIT_NOISE + o4[1], y * PIT_NOISE * 0.5 + o4[2], zs[k] * PIT_NOISE + o4[3])
						occ = math.min(occ, math.clamp((math.sqrt(r2) - edge) / RES + 0.5, 0, 1))
					end
					if occ > 0 and below > Config.CaveMinDepth and not sealed then
						-- negativo = aire (cueva), positivo = roca
						local tunnel = math.max(math.abs(math.noise(x1, y1, z1[k])), math.abs(math.noise(x2, y2, z2[k]))) - width
						local cavern = thr - math.noise(x3, y3, z3[k])
						occ = math.min(occ, math.clamp(math.min(tunnel, cavern) * CAVE_SHARP + 0.5, 0, 1))
					end
				end
				if y < 0 then
					local s = stats[layer]
					s[2] += 1
					if occ < 0.5 then s[1] += 1 end
				end
				if occ <= 0.01 then
					mj[k], oj[k] = Enum.Material.Air, 0
				else
					-- tierra en la superficie llana; roca desnuda en las montañas
					mj[k] = if below < 5 then (if ground > 26 then Enum.Material.Rock else Enum.Material.Ground) else rowMat[j]
					oj[k] = occ
				end
			end
		end
	end
	local yBottom = -Config.Depth + (jA - 1) * RES
	local yTop = -Config.Depth + jB * RES
	Terrain:WriteVoxels(Region3.new(Vector3.new(x0, yBottom, z0), Vector3.new(x0 + CHUNK, yTop, z0 + CHUNK)), RES, mats, occs)
end

-- Genera la franja de profundidades [fromDepth, toDepth) en todo el mundo (fromDepth = 0 incluye la superficie).
local function generateBand(fromDepth: number, toDepth: number, stats)
	local jB = if fromDepth <= 0 then NY else (Config.Depth - fromDepth) / RES
	local jA = (Config.Depth - toDepth) / RES + 1
	for x0 = -Config.HalfSize, Config.HalfSize - CHUNK, CHUNK do
		for z0 = -Config.HalfSize, Config.HalfSize - CHUNK, CHUNK do
			generateChunk(x0, z0, jA, jB, stats)
			task.wait()
		end
	end
	generatedDepth = toDepth
	print(`[World] terreno generado hasta {toDepth} de {Config.Depth}`)
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

-- Talla la cueva del foso (encima del pozo), la cueva de la base (spawn) y el pasaje de la gran puerta entre ambas.
-- Abre una salida que sube a la superficie y devuelve el punto donde empieza la salida que baja (la cadena de arenas
-- parte de ahí).
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

-- Pasaje entre la cueva de la base y la del foso: piso plano, paredes rectas y techo abovedado (la gran puerta de
-- arco la pone Hub.luau del lado de la cueva del foso).
local function carveGatePassage()
	local hub, spawnCave, gate = Config.Hub, Config.SpawnCave, Config.Gate
	local dir = Vector3.new(spawnCave.Center.X - hub.Center.X, 0, spawnCave.Center.Z - hub.Center.Z).Unit
	local from = Vector3.new(hub.Center.X, HUB_FLOOR, hub.Center.Z) + dir * (hub.Radius - 12)
	local to = Vector3.new(spawnCave.Center.X, HUB_FLOOR, spawnCave.Center.Z) - dir * (spawnCave.Radius - 12)
	local mid, length = (from + to) / 2, (to - from).Magnitude
	local walls = mid + Vector3.yAxis * (gate.Height / 2)
	Terrain:FillBlock(CFrame.lookAt(walls, walls + dir), Vector3.new(gate.Width, gate.Height, length), Enum.Material.Air)
	local roof = mid + Vector3.yAxis * gate.Height
	Terrain:FillCylinder(CFrame.lookAt(roof, roof + dir) * CFrame.Angles(math.pi / 2, 0, 0), length, gate.Width / 2, Enum.Material.Air)
end

local function carveHub(): Vector3
	local hub = Config.Hub
	local c, r = hub.Center, hub.Radius
	carveCavern(c, r, hub.Height, hub.DomeRadius) -- cueva del foso
	local spawnCave = Config.SpawnCave
	carveCavern(spawnCave.Center, spawnCave.Radius, spawnCave.Height, spawnCave.DomeRadius) -- cueva de la base (spawn)
	carveGatePassage()

	-- salida hacia arriba (opcional): rampa desde la pared hasta salir por la superficie
	if hub.ExitUp then
		local up = hub.ExitUp.Unit
		local fromUp = Vector3.new(c.X, HUB_FLOOR + hub.TunnelRadius, c.Z) + up * (r - hub.TunnelRadius)
		local outXZ = Vector2.new(c.X, c.Z) + Vector2.new(up.X, up.Z) * (r + 150)
		tunnel(fromUp, Vector3.new(outXZ.X, surfaceHeight(outXZ.X, outXZ.Y) + 6, outXZ.Y), hub.TunnelRadius, 0)
	end

	-- la entrada inicial: única salida de la cueva del foso. Baja desde la pared hasta una cámara de cruce (fuera del
	-- caparazón) y de ahí se bifurcan ramales que se abren a las cuevas naturales; la cadena de arenas parte del cruce.
	local down = hub.ExitDown.Unit
	local junction = hub.Junction
	local from = Vector3.new(c.X, HUB_FLOOR + hub.TunnelRadius, c.Z) + down * (r - hub.TunnelRadius)
	local cross = from + down * junction.Distance - Vector3.yAxis * junction.Drop
	tunnel(from, cross, hub.TunnelRadius, junction.Radius)
	local rng = Random.new(seed + 17)
	local baseAngle = math.atan2(down.Z, down.X)
	for i = 1, junction.Branches do
		-- abanico de ramales hacia adelante (nunca de vuelta hacia las cuevas de arriba)
		local spread = (i - (junction.Branches + 1) / 2) / math.max(junction.Branches - 1, 1)
		local a = baseAngle + spread * math.rad(130) + rng:NextNumber(-0.15, 0.15)
		local len = rng:NextNumber(junction.BranchLength[1], junction.BranchLength[2])
		local to = cross + Vector3.new(math.cos(a) * len, -rng:NextNumber(15, 50), math.sin(a) * len)
		tunnel(cross, to, 7, 11)
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
	local lim = Config.HalfSize - spec.Radius[2] - 16
	local arenas = {}
	for layer, count in spec.PerLayer do
		local top, bottom = layerTop(layer), Config.Layers[layer].MaxDepth
		for _ = 1, count do
			for _ = 1, 30 do -- busca un sitio lejos del pozo y de las otras arenas
				local radius = rng:NextNumber(spec.Radius[1], spec.Radius[2])
				local height = rng:NextNumber(spec.Height[1], spec.Height[2])
				local margin = height / 2 + radius + 12
				-- siempre por debajo de las cuevas de arriba y su caparazón, para que ningún túnel pase por ellas
				local shallowest = math.max(top + margin, -SHELL_BOTTOM + 20 + margin)
				if bottom - margin <= shallowest then break end
				local depth = rng:NextNumber(shallowest, bottom - margin)
				local center = Vector3.new(rng:NextNumber(-lim, lim), -depth, rng:NextNumber(-lim, lim))
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
	local rock = materialAt(-c.Y)
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
			return
		end
	end
	tunnel(from, to, radius, 0)
end


-- Talla las arenas que ya caben en la zona generada y las une en cadena (la primera, a la cueva inicial o, si no hay,
-- a la entrada de la meseta más cercana).
local function carveReadyArenas(arenas: { Arena }, entrances: { Vector3 }, start: Vector3?)
	for i, arena in arenas do
		if not arena.carved and arena.bottomDepth <= generatedDepth then
			carveArena(arena)
			local previous = arenas[i - 1]
			if previous then
				connect(previous.center + Vector3.new(0, -previous.height / 2 + 6, 0), arena, arena.isCore)
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
	light.Color, light.Range, light.Brightness, light.Shadows = color, Config.LightRange, 1.4, false
	light.Parent = p
	p.Parent = lightFolder
end

-- punto de aire al azar, con su suelo, en una capa elegida por peso y dentro de [minDepth, lo ya generado];
-- nil si no se halló
local function randomCavePoint(rng: Random, minDepth: number?): RaycastResult?
	local lim = Config.HalfSize - 12
	local low = math.max(minDepth or 8, 8)
	local weights = {}
	for i, layer in Config.Layers do
		if layerTop(i) < generatedDepth and layer.MaxDepth > low then weights[i] = layer.SpawnWeight end
	end
	if next(weights) == nil then return nil end
	for _ = 1, 40 do
		local i = pickWeighted(rng, weights)
		local top = math.max(layerTop(i), low)
		local bottom = math.min(Config.Layers[i].MaxDepth, generatedDepth) - 4
		if bottom > top then
			local d = rng:NextNumber(top, bottom)
			local hit = floorBelow(Vector3.new(rng:NextNumber(-lim, lim), -d, rng:NextNumber(-lim, lim)), 50)
			if hit then return hit end
		end
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

-- Llena el pool hasta `cap` minerales (o `limit` grupos). Un intento fallido no corta el llenado: antes se cortaba
-- al primero y quedaban muy pocos minerales.
local function fillMinerals(rng: Random, limit: number, cap: number, minDepth: number?)
	local have = #CollectionService:GetTagged("Mineral")
	local misses = 0
	while have < cap and limit > 0 and misses < 25 do
		local hit = randomCavePoint(rng, minDepth)
		if hit then
			have += placeCluster(rng, hit)
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
	local color = Config.LightColors[layerIndex(-arena.center.Y)]
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
		local hit = randomCavePoint(rng, minDepth)
		if hit then
			newCrystal(hit.Position + hit.Normal * 0.9, Config.LightColors[layerIndex(-hit.Position.Y)])
		end
	end
end

-- Cada fase va protegida: si una falla se avisa en el Output y el resto sigue, y los jugadores siempre acaban apareciendo.
local function phase(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then warn(`[World] fase "{name}" falló: {err}`) end
end

return {
	Start = function()
		workspace:SetAttribute("WorldReady", false) -- el cliente muestra "Generando mundo" hasta que sea true
		if workspace.FallenPartsDestroyHeight > -Config.Depth then
			warn(`[World] FallenPartsDestroyHeight es {workspace.FallenPartsDestroyHeight}: quien baje de ahí muere. Se ajusta en default.project.json (Workspace) y se aplica al conectar Rojo.`)
		end
		Players.CharacterAutoLoads = false
		-- la base gris de las plantillas de Roblox tapa la meseta (su cara de arriba está en y = 0): se quita
		local baseplate = workspace:FindFirstChild("Baseplate")
		if baseplate then baseplate:Destroy() end

		local t0 = os.clock()
		local stats = {}
		for i in Config.Layers do stats[i] = { 0, 0 } end
		local arenas = planArenas()
		local entrances = {}
		local starter: Vector3? = nil
		local depth = 0

		-- 1) Zona de arriba, antes de dejar entrar a nadie.
		phase("terreno inicial", function()
			Terrain:Clear()
			while depth < Config.ReadyDepth do
				generateBand(depth, depth + Config.BandHeight, stats)
				depth += Config.BandHeight
			end
		end)
		phase("entradas", function() entrances = carveEntrances() end)
		phase("base", function() starter = carveHub() end)
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
		local readyShare = Config.ReadyDepth / Config.Depth
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
		phase("luces", function() spawnLights(rng, math.floor(Config.LightCount * readyShare)) end)
		print(`[World] semilla {seed}, zona inicial lista en {string.format("%.1f", os.clock() - t0)} s, {#CollectionService:GetTagged("Mineral")} minerales`)

		-- Todos aparecen (o reaparecen) en el spawn, incluso quien haya salido antes de tiempo y caído al vacío.
		Players.CharacterAutoLoads = true
		workspace:SetAttribute("WorldReady", true)
		for _, p in Players:GetPlayers() do
			task.spawn(function() p:LoadCharacter() end)
		end

		MineralsFeature.Exploded:Connect(function(pos: Vector3, radius: number)
			Terrain:FillBall(pos, radius * Config.CarveFactor, Enum.Material.Air)
		end)

		-- 2) El resto, hacia el núcleo, mientras se juega.
		task.spawn(function()
			local furnished = {}
			for _, arena in arenas do
				if arena.carved then furnished[arena] = true end
			end
			while depth < Config.Depth do
				phase("terreno profundo", function()
					generateBand(depth, math.min(depth + Config.BandHeight, Config.Depth), stats)
				end)
				depth = math.min(depth + Config.BandHeight, Config.Depth)
				phase("arenas profundas", function()
					carveReadyArenas(arenas, entrances, starter)
					for _, arena in arenas do
						if arena.carved and not furnished[arena] then
							furnished[arena] = true
							furnishArena(arena)
						end
					end
				end)
			end
			phase("minerales profundos", function() fillMinerals(rng, math.huge, Config.MineralCount, Config.ReadyDepth) end)
			phase("luces profundas", function()
				spawnLights(rng, Config.LightCount - math.floor(Config.LightCount * readyShare), Config.ReadyDepth)
			end)
			print(`[World] mundo completo en {string.format("%.1f", os.clock() - t0)} s: {#arenas} arenas, {#CollectionService:GetTagged("Mineral")} minerales`)
			for i, s in stats do
				print(`[World] capa {i}: {string.format("%.0f", 100 * s[1] / math.max(s[2], 1))}% de aire`)
			end

			local respawnRng = Random.new()
			while true do
				task.wait(Config.RespawnInterval)
				phase("reposición", function() fillMinerals(respawnRng, Config.RespawnBatch, Config.MineralCount) end)
			end
		end)
	end,
}
