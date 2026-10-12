-- Mundo: foso circular hacia el núcleo, generado por código con Terrain al arrancar el servidor.
--  · Meseta plana con un foso en forma de cuenco; bajo tierra, capas de roca con cuevas naturales (ruido 3D).
--  · Pozos de acceso garantizados, plataforma de spawn y muros invisibles en el borde.
--  · Pool de minerales repartidos por capas (más raros hacia el núcleo) y repuestos con el tiempo.
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

local seed = Config.Seed or tonumber(os.date("!%Y%m%d")) :: number
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

-- negativo = aire (cueva), positivo = roca
local function caveMeasure(x: number, y: number, z: number): number
	local t = math.clamp(-y / Config.Depth, 0, 1)
	local w = Config.TunnelWidth[1] + (Config.TunnelWidth[2] - Config.TunnelWidth[1]) * t
	local thr = Config.CavernThreshold[1] + (Config.CavernThreshold[2] - Config.CavernThreshold[1]) * t
	local f = Config.NoiseScale
	local n1 = math.noise(x * f + o1[1], y * f + o1[2], z * f + o1[3])
	local n2 = math.noise(x * f + o2[1], y * f + o2[2], z * f + o2[3])
	local n3 = math.noise(x * f + o3[1], y * f + o3[2], z * f + o3[3])
	return math.min(math.max(math.abs(n1), math.abs(n2)) - w, thr - n3)
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

-- stats[capa] = { aire, total } para ajustar las cuevas viendo el Output
local function generateChunk(x0: number, z0: number, stats)
	local n = CHUNK / RES
	local ny = (Config.Depth + TOP) / RES
	local mats, occs = table.create(n), table.create(n)
	for i = 1, n do
		local mi, oi = table.create(ny), table.create(ny)
		mats[i], occs[i] = mi, oi
		local x = x0 + (i - 0.5) * RES
		for j = 1, ny do
			local y = -Config.Depth + (j - 0.5) * RES
			local mj, oj = table.create(n), table.create(n)
			mi[j], oi[j] = mj, oj
			for k = 1, n do
				local z = z0 + (k - 0.5) * RES
				local h = surfaceHeight(x, z)
				local occ = math.clamp((h - y) / RES + 0.5, 0, 1)
				local below = h - y
				if occ > 0 and below > Config.CaveMinDepth then
					occ = math.min(occ, math.clamp(caveMeasure(x, y, z) * CAVE_SHARP + 0.5, 0, 1))
				end
				if below > 0 then
					local s = stats[layerIndex(-y)]
					s[2] += 1
					if occ < 0.5 then s[1] += 1 end
				end
				if occ <= 0.01 then
					mj[k], oj[k] = Enum.Material.Air, 0
				else
					mj[k] = if h == 0 and below < 5 then Enum.Material.Ground else materialAt(-y)
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

-- pozo vertical con una cámara al fondo, para entrar al subsuelo
local function shaft(x: number, z: number, topY: number, bottomY: number, radius: number, chamber: number)
	Terrain:FillCylinder(CFrame.new(x, (topY + bottomY) / 2, z), topY - bottomY + 4, radius, Enum.Material.Air)
	Terrain:FillBall(Vector3.new(x, bottomY, z), chamber, Enum.Material.Air)
end

local function carveEntrances()
	local rng = Random.new(seed + 7)
	local pit = Config.PitCenter
	local lim = Config.HalfSize - 40
	local placed = 0
	for _ = 1, 200 do
		if placed >= Config.PlateauEntrances then break end
		local x, z = rng:NextNumber(-lim, lim), rng:NextNumber(-lim, lim)
		local farFromPit = (Vector2.new(x, z) - pit).Magnitude > Config.PitRadius + 15
		local farFromSpawn = (Vector2.new(x, z) - Vector2.new(Config.SpawnPosition.X, Config.SpawnPosition.Z)).Magnitude > 30
		if farFromPit and farFromSpawn then
			shaft(x, z, 2, -45, 5, 13)
			placed += 1
		end
	end
	for i = 1, Config.PitShafts do
		local a = (i / Config.PitShafts) * math.pi * 2
		local x, z = pit.X + math.cos(a) * Config.PitRadius * 0.5, pit.Y + math.sin(a) * Config.PitRadius * 0.5
		shaft(x, z, surfaceHeight(x, z) + 2, -95, 6, 14)
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
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored, spawn.Neutral, spawn.Duration = true, true, 0
	spawn.Size, spawn.Position = Vector3.new(14, 1, 14), Config.SpawnPosition
	spawn.Material, spawn.Color = Enum.Material.Metal, Color3.fromRGB(70, 75, 85)
	spawn.Parent = workspace
end

-- Minerales ----------------------------------------------------------------

local mineralFolder
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

-- punto del suelo bajo `p` si `p` está en aire; nil si está dentro de roca o no hay suelo cerca
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
	p.Parent = mineralFolder
end

-- Un grupo (1 o varios cerca) en un punto al azar de una capa elegida por peso. Devuelve cuántos puso.
local function spawnCluster(rng: Random): number
	local lim = Config.HalfSize - 12
	for _ = 1, 40 do
		local layerWeights = {}
		for i, layer in Config.Layers do layerWeights[i] = layer.SpawnWeight end
		local i = pickWeighted(rng, layerWeights)
		local minDepth = if i == 1 then 8 else Config.Layers[i - 1].MaxDepth
		local d = rng:NextNumber(minDepth, Config.Layers[i].MaxDepth - 4)
		local p = Vector3.new(rng:NextNumber(-lim, lim), -d, rng:NextNumber(-lim, lim))
		local hit = floorBelow(p, 50)
		if hit then
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
	end
	return 0
end

local function fillMinerals(rng: Random, limit: number)
	local have = #CollectionService:GetTagged("Mineral")
	while have < Config.MineralCount and limit > 0 do
		local n = spawnCluster(rng)
		have += n
		limit -= 1
		if n == 0 then break end
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
		fillMinerals(Random.new(seed + 1), math.huge) -- misma distribución inicial todo el día

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

		local rng = Random.new()
		while true do
			task.wait(Config.RespawnInterval)
			fillMinerals(rng, Config.RespawnBatch)
		end
	end,
}
