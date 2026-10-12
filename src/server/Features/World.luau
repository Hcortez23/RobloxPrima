-- Mundo: gran foso hacia el núcleo, generado por código con Terrain al arrancar el servidor.
--  · Meseta plana con un foso enorme de paredes empinadas; bajo tierra, capas de roca con cuevas naturales (ruido 3D).
--  · Accesos repartidos: pozos en la meseta, bocas de cueva en las paredes y pozos en el fondo del foso.
--  · Iluminación del subsuelo con cristales luminosos; los minerales también brillan.
--  · Pool de minerales por capas (más raros hacia el núcleo), repuestos con el tiempo, más unos cuantos a la vista.
--  · Las explosiones de minerales excavan el terreno (Minerals.Exploded).
-- Los jugadores no aparecen hasta que el terreno termina de generarse.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.World)
local MineralData = require(ReplicatedStorage.Shared.Config.Minerals)
local MineralsFeature = require(script.Parent.Minerals)

local Terrain = workspace.Terrain
local RES = 4 -- tamaño de voxel de Roblox
local CHUNK = 128 -- studs por lado de cada bloque que se escribe de una vez
local TOP = 4 -- filas de voxel sobre y = 0 (para suavizar la superficie)
local CAVE_SHARP = 18 -- qué tan nítido es el borde de las cuevas (voxel ~ 0.056 de ruido)

local seed = Config.Seed or (tonumber(os.date("!%Y%m%d")) :: number)
local seedRng = Random.new(seed)

-- offsets de ruido (no enteros, para evitar los nodos donde el ruido vale 0)
local function offsets()
	return { seedRng:NextNumber(0, 1000) + 0.37, seedRng:NextNumber(0, 1000) + 0.61, seedRng:NextNumber(0, 1000) + 0.19 }
end
local o1, o2, o3 = offsets(), offsets(), offsets()

local function surfaceHeight(x: number, z: number): number
	local dx, dz = x - Config.PitCenter.X, z - Config.PitCenter.Y
	local t = math.sqrt(dx * dx + dz * dz) / Config.PitRadius
	if t >= 1 then return 0 end
	return -Config.PitDepth * (1 - t * t)
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

-- Datos por fila de voxel (dependen solo de la profundidad), calculados una vez.
local NY = (Config.Depth + TOP) / RES
local rowMat, rowLayer, rowWidth, rowThr = table.create(NY), table.create(NY), table.create(NY), table.create(NY)
for j = 1, NY do
	local depth = -(-Config.Depth + (j - 0.5) * RES)
	local t = math.clamp(depth / Config.Depth, 0, 1)
	rowMat[j], rowLayer[j] = materialAt(depth), layerIndex(depth)
	rowWidth[j] = Config.TunnelWidth[1] + (Config.TunnelWidth[2] - Config.TunnelWidth[1]) * t
	rowThr[j] = Config.CavernThreshold[1] + (Config.CavernThreshold[2] - Config.CavernThreshold[1]) * t
end

-- stats[capa] = { aire, total } para ajustar las cuevas viendo el Output
local function generateChunk(x0: number, z0: number, stats)
	local n = CHUNK / RES
	local f = Config.NoiseScale
	local mats, occs = table.create(n), table.create(n)
	local z1, z2, z3, zs = table.create(n), table.create(n), table.create(n), table.create(n)
	for k = 1, n do
		local z = z0 + (k - 0.5) * RES
		zs[k], z1[k], z2[k], z3[k] = z, z * f + o1[3], z * f + o2[3], z * f + o3[3]
	end
	for i = 1, n do
		local mi, oi = table.create(NY), table.create(NY)
		mats[i], occs[i] = mi, oi
		local x = x0 + (i - 0.5) * RES
		local x1, x2, x3 = x * f + o1[1], x * f + o2[1], x * f + o3[1]
		for j = 1, NY do
			local y = -Config.Depth + (j - 0.5) * RES
			local y1, y2, y3 = y * f + o1[2], y * f + o2[2], y * f + o3[2]
			local mj, oj = table.create(n), table.create(n)
			mi[j], oi[j] = mj, oj
			local width, thr, layer = rowWidth[j], rowThr[j], rowLayer[j]
			for k = 1, n do
				local h = surfaceHeight(x, zs[k])
				local below = h - y
				local occ = math.clamp(below / RES + 0.5, 0, 1)
				if occ > 0 and below > Config.CaveMinDepth then
					-- negativo = aire (cueva), positivo = roca
					local tunnel = math.max(math.abs(math.noise(x1, y1, z1[k])), math.abs(math.noise(x2, y2, z2[k]))) - width
					local cavern = thr - math.noise(x3, y3, z3[k])
					occ = math.min(occ, math.clamp(math.min(tunnel, cavern) * CAVE_SHARP + 0.5, 0, 1))
				end
				if below > 0 then
					local s = stats[layer]
					s[2] += 1
					if occ < 0.5 then s[1] += 1 end
				end
				if occ <= 0.01 then
					mj[k], oj[k] = Enum.Material.Air, 0
				else
					mj[k] = if h == 0 and below < 5 then Enum.Material.Ground else rowMat[j]
					oj[k] = occ
				end
			end
		end
	end
	Terrain:WriteVoxels(
		Region3.new(Vector3.new(x0, -Config.Depth, z0), Vector3.new(x0 + CHUNK, TOP, z0 + CHUNK)),
		RES,
		mats,
		occs
	)
end

-- túnel recto (cilindro) con una cámara al final, para entrar al subsuelo
local function tunnel(from: Vector3, to: Vector3, radius: number, chamber: number)
	local mid = (from + to) / 2
	Terrain:FillCylinder(CFrame.lookAt(mid, to) * CFrame.Angles(math.pi / 2, 0, 0), (to - from).Magnitude, radius, Enum.Material.Air)
	Terrain:FillBall(to, chamber, Enum.Material.Air)
end

local function carveEntrances()
	local rng = Random.new(seed + 7)
	local pit = Config.PitCenter
	local spawn2d = Vector2.new(Config.SpawnPosition.X, Config.SpawnPosition.Z)
	local lim = Config.HalfSize - 40

	-- pozos en la meseta, repartidos alrededor del foso
	local placed = 0
	for _ = 1, 400 do
		if placed >= Config.PlateauShafts then break end
		local p = Vector2.new(rng:NextNumber(-lim, lim), rng:NextNumber(-lim, lim))
		if (p - pit).Magnitude > Config.PitRadius + 15 and (p - spawn2d).Magnitude > 30 then
			tunnel(Vector3.new(p.X, 2, p.Y), Vector3.new(p.X, -rng:NextNumber(50, 110), p.Y), 5, 13)
			placed += 1
		end
	end

	-- bocas de cueva horizontales en las paredes del foso, a distintas alturas
	for _ = 1, Config.WallCaves do
		local a = rng:NextNumber(0, math.pi * 2)
		local y = -rng:NextNumber(20, Config.PitDepth - 20)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = math.sqrt(1 + y / Config.PitDepth) * Config.PitRadius -- radio donde la pared está a altura y
		local wall = Vector3.new(pit.X + dir.X * r, y, pit.Y + dir.Z * r)
		tunnel(wall - dir * 8, wall + dir * 46, 6, 12)
	end

	-- pozos en el fondo del foso hacia las capas profundas
	for i = 1, Config.PitShafts do
		local a = (i / Config.PitShafts) * math.pi * 2
		local x, z = pit.X + math.cos(a) * Config.PitRadius * 0.4, pit.Y + math.sin(a) * Config.PitRadius * 0.4
		local top = surfaceHeight(x, z) + 2
		tunnel(Vector3.new(x, top, z), Vector3.new(x, top - 60, z), 6, 14)
	end
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
	spawn.Size, spawn.Position, spawn.Transparency, spawn.CanCollide = Vector3.new(14, 1, 14), Config.SpawnPosition, 1, false
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

-- punto de aire al azar en una capa elegida por peso, con su suelo; nil si no se halló
local function randomCavePoint(rng: Random): RaycastResult?
	local lim = Config.HalfSize - 12
	local weights = {}
	for i, layer in Config.Layers do weights[i] = layer.SpawnWeight end
	for _ = 1, 40 do
		local i = pickWeighted(rng, weights)
		local minDepth = if i == 1 then 8 else Config.Layers[i - 1].MaxDepth
		local d = rng:NextNumber(minDepth, Config.Layers[i].MaxDepth - 4)
		local hit = floorBelow(Vector3.new(rng:NextNumber(-lim, lim), -d, rng:NextNumber(-lim, lim)), 50)
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

local function fillMinerals(rng: Random, limit: number)
	local have = #CollectionService:GetTagged("Mineral")
	while have < Config.MineralCount and limit > 0 do
		local hit = randomCavePoint(rng)
		if not hit then break end
		have += placeCluster(rng, hit)
		limit -= 1
	end
end

-- Minerales a la vista (meseta y paredes del foso): rayo desde arriba en puntos al azar.
local function spawnSurfaceMinerals(rng: Random, count: number, center: Vector2?, radius: number)
	local lim = Config.HalfSize - 20
	local placed = 0
	for _ = 1, count * 20 do
		if placed >= count then break end
		local x, z
		if center then
			local a, r = rng:NextNumber(0, math.pi * 2), math.sqrt(rng:NextNumber()) * radius
			x, z = center.X + math.cos(a) * r, center.Y + math.sin(a) * r
		else
			x, z = rng:NextNumber(-lim, lim), rng:NextNumber(-lim, lim)
		end
		local hit = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -400, 0), floorParams)
		if hit and hit.Normal.Y > 0.3 then -- no en paredes casi verticales
			newMineral(pickWeighted(rng, Config.Layers[1].Rarity), hit.Position + hit.Normal * 0.9)
			placed += 1
		end
	end
end

local function spawnLights(rng: Random)
	lightFolder = Instance.new("Folder")
	lightFolder.Name = "CaveLights"
	lightFolder.Parent = workspace
	for _ = 1, Config.LightCount do
		local hit = randomCavePoint(rng)
		if hit then
			newCrystal(hit.Position + hit.Normal * 0.9, Config.LightColors[layerIndex(-hit.Position.Y)])
		end
	end
end

return {
	Start = function()
		Players.CharacterAutoLoads = false

		local t0 = os.clock()
		local stats = { { 0, 0 }, { 0, 0 }, { 0, 0 } }
		Terrain:Clear()
		for x0 = -Config.HalfSize, Config.HalfSize - CHUNK, CHUNK do
			for z0 = -Config.HalfSize, Config.HalfSize - CHUNK, CHUNK do
				generateChunk(x0, z0, stats)
				task.wait()
			end
		end
		carveEntrances()
		buildBorders()
		buildSpawn()

		mineralFolder = Instance.new("Folder")
		mineralFolder.Name = "WorldMinerals"
		mineralFolder.Parent = workspace
		local rng = Random.new(seed + 1) -- misma distribución inicial todo el día
		spawnSurfaceMinerals(rng, Config.SurfaceMinerals, nil, 0)
		spawnSurfaceMinerals(rng, Config.NearSpawnMinerals, Vector2.new(Config.SpawnPosition.X, Config.SpawnPosition.Z), 45)
		fillMinerals(rng, math.huge)
		spawnLights(rng)

		print(`[World] semilla {seed}, listo en {string.format("%.1f", os.clock() - t0)} s, {#CollectionService:GetTagged("Mineral")} minerales`)
		for i, s in stats do
			print(`[World] capa {i}: {string.format("%.0f", 100 * s[1] / math.max(s[2], 1))}% de aire`)
		end

		Players.CharacterAutoLoads = true
		for _, p in Players:GetPlayers() do
			if not p.Character then p:LoadCharacter() end
		end

		MineralsFeature.Exploded:Connect(function(pos: Vector3, radius: number)
			Terrain:FillBall(pos, radius * Config.CarveFactor, Enum.Material.Air)
		end)

		local respawnRng = Random.new()
		while true do
			task.wait(Config.RespawnInterval)
			fillMinerals(respawnRng, Config.RespawnBatch)
		end
	end,
}
