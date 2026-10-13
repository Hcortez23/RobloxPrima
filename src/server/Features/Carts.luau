-- Carritos de mina: llevan los minerales del jugador desde las estaciones de la ruta hasta el andén de su base.
--  · Estaciones: en la cueva del foso (junto al portal DESCENSO), en la cámara de cruce y en cada arena (paradas de
--    World.Route). Ahí el jugador "Envía minerales a su base": se le vacía el inventario y sale un carrito con ellos.
--  · Vía: los rieles de la ruta (Route.Paths) hacia arriba hasta la cueva del foso; de ahí una vía nueva rodea la
--    rejilla del pozo, cruza la puerta de arco y el pasaje, da vuelta por el anillo de la cueva de la base y entra al
--    andén de cada base.
--  · Al llegar, lo que trae se suma al almacén de la base (Bases.Deposit) y cuenta como un envío.
-- Los carritos se mueven en el servidor (piezas ancladas, PivotTo por frame) para que todos los vean igual.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config.Carts)
local WorldConfig = require(ReplicatedStorage.Shared.Config.World)
local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)
local World = require(script.Parent.World)
local Route = require(script.Parent.Route)
local Bases = require(script.Parent.Bases)

local RARITIES = { "Comun", "Raro", "Epico", "Legendario" }

local DARK = Color3.fromRGB(48, 50, 56)
local RUST = Color3.fromRGB(110, 62, 40)
local RAIL = Color3.fromRGB(96, 92, 90)
local WOOD = Color3.fromRGB(70, 52, 40)
local HAZARD = Color3.fromRGB(230, 180, 40)
local LAMP = Color3.fromRGB(255, 214, 160)

local HUB = WorldConfig.Hub
local HUB_FLOOR = HUB.Center.Y - HUB.Height / 2
local HUB_XZ = Vector2.new(HUB.Center.X, HUB.Center.Z)
local SPAWN = WorldConfig.SpawnCave
local SPAWN_XZ = Vector2.new(SPAWN.Center.X, SPAWN.Center.Z)
local GATE_DIR = (SPAWN_XZ - HUB_XZ).Unit -- de la cueva del foso hacia la cueva de la base

local folder: Folder
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanTouch = name, true, false
	p.Size, p.CFrame, p.Color, p.Material = size, cframe, color, material
	p.Shape = shape or Enum.PartType.Block
	p.Parent = parent
	return p
end

local function deco(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = part(parent, name, size, cframe, color, material, shape)
	p.CanCollide, p.CanQuery, p.CastShadow = false, false, false
	return p
end

-- suelo bajo (x, z) en las cuevas de arriba (el piso de las dos cuevas está a la misma altura)
local function floorAt(x: number, z: number): Vector3
	local hit = workspace:Raycast(Vector3.new(x, HUB_FLOOR + 8, z), Vector3.new(0, -30, 0), terrainOnly)
	return if hit then hit.Position else Vector3.new(x, HUB_FLOOR, z)
end

local function xz(v: Vector3): Vector2
	return Vector2.new(v.X, v.Z)
end

-- puntos del suelo de `a` a `b` cada SampleStep (sin incluir `a`)
local function line(a: Vector2, b: Vector2, out: { Vector3 })
	local n = math.max(math.ceil((b - a).Magnitude / Config.SampleStep), 1)
	for k = 1, n do
		local p = a:Lerp(b, k / n)
		table.insert(out, floorAt(p.X, p.Y))
	end
end

-- puntos en línea recta de `a` a `b` conservando su altura (sin incluir `a`): dentro del andén, sobre el piso de la base
local function straight(a: Vector3, b: Vector3, out: { Vector3 })
	local n = math.max(math.ceil((b - a).Magnitude / Config.SampleStep), 1)
	for k = 1, n do
		table.insert(out, a:Lerp(b, k / n))
	end
end

-- arco por el anillo de la cueva de la base, de un ángulo a otro por el lado más corto (sin incluir el inicial)
local function arc(fromAngle: number, toAngle: number, out: { Vector3 })
	local delta = (toAngle - fromAngle + math.pi) % (math.pi * 2) - math.pi
	local n = math.max(math.ceil(math.abs(delta) * Config.RingRadius / Config.SampleStep), 1)
	for k = 1, n do
		local a = fromAngle + delta * k / n
		local p = SPAWN_XZ + Vector2.new(math.cos(a), math.sin(a)) * Config.RingRadius
		table.insert(out, floorAt(p.X, p.Y))
	end
end

local function angleOf(p: Vector2): number
	local d = p - SPAWN_XZ
	return math.atan2(d.Y, d.X)
end

-- Rieles y durmientes entre puntos consecutivos.
local function drawRails(points: { Vector3 }, closed: boolean?)
	local count = #points
	for k = 1, if closed then count else count - 1 do
		local a, b = points[k], points[k % count + 1]
		local dir = b - a
		if dir.Magnitude > 0.05 then
			local side = dir:Cross(Vector3.yAxis)
			side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
			for _, s in { -1, 1 } do
				local ra, rb = a + side * (s * 1.6) + Vector3.yAxis * 0.45, b + side * (s * 1.6) + Vector3.yAxis * 0.45
				deco(folder, "Rail", Vector3.new(0.3, 0.3, (rb - ra).Magnitude + 0.1), CFrame.lookAt((ra + rb) / 2, rb), RAIL, Enum.Material.Metal)
			end
			deco(folder, "Sleeper", Vector3.new(4.6, 0.3, 0.8), CFrame.lookAt(a + Vector3.yAxis * 0.15, a + Vector3.yAxis * 0.15 + Vector3.new(dir.X, 0, dir.Z)), WOOD, Enum.Material.WoodPlanks)
		end
	end
end

-- Carrito: caja de metal oxidado con ruedas, borde del color de la base y farol; `ore` = colores del mineral que lleva.
local function makeCart(color: Color3, ore: { Color3 }): Model
	local model = Instance.new("Model")
	model.Name = "MineCart"
	local origin = CFrame.new()
	local chassis = deco(model, "Chassis", Vector3.new(3.2, 0.4, 4.6), origin * CFrame.new(0, 0.9, 0), DARK, Enum.Material.Metal)
	for _, s in { -1, 1 } do
		deco(model, "Wall", Vector3.new(3.2, 1.6, 0.25), origin * CFrame.new(0, 1.9, s * 2.2), RUST, Enum.Material.CorrodedMetal)
		deco(model, "Wall", Vector3.new(0.25, 1.6, 4.6), origin * CFrame.new(s * 1.5, 1.9, 0), RUST, Enum.Material.CorrodedMetal)
		deco(model, "Rim", Vector3.new(3.4, 0.15, 0.15), origin * CFrame.new(0, 2.75, s * 2.25), color, Enum.Material.Neon)
		deco(model, "Rim", Vector3.new(0.15, 0.15, 4.6), origin * CFrame.new(s * 1.55, 2.75, 0), color, Enum.Material.Neon)
		for _, w in { -1.5, 1.5 } do
			deco(model, "Wheel", Vector3.new(0.4, 1, 1), origin * CFrame.new(s * 1.7, 0.55, w), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end
	local lamp = deco(model, "Lamp", Vector3.one * 0.6, origin * CFrame.new(0, 2.1, -2.45), LAMP, Enum.Material.Neon, Enum.PartType.Ball)
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = LAMP, 14, 0.9, false
	glow.Parent = lamp
	for k, c in ore do -- trozos de mineral asomando
		local x, z = ((k - 1) % 2 - 0.5) * 1.2, (math.floor((k - 1) / 2) - 1) * 1.2
		deco(model, "Ore", Vector3.new(1, 0.9, 1), origin * CFrame.new(x, 2.4, z) * CFrame.Angles(0.4 * k, 0.7 * k, 0.3 * k), c, Enum.Material.Neon)
	end
	model.PrimaryPart = chassis
	model.WorldPivot = origin
	return model
end

-- Mueve el carrito por los puntos a velocidad constante y llama a onArrive al final.
local function run(cart: Model, points: { Vector3 }, onArrive: () -> ())
	local cumulative = { 0 }
	for k = 2, #points do
		cumulative[k] = cumulative[k - 1] + (points[k] - points[k - 1]).Magnitude
	end
	local total, distance, k = cumulative[#points], 0, 1
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not cart.Parent then
			connection:Disconnect()
			return
		end
		distance += dt * Config.Speed
		if distance >= total then
			connection:Disconnect()
			onArrive()
			return
		end
		while cumulative[k + 1] < distance do k += 1 end
		local a, b = points[k], points[k + 1]
		local span = cumulative[k + 1] - cumulative[k]
		local pos = if span > 0.001 then a:Lerp(b, (distance - cumulative[k]) / span) else a
		local dir = b - a
		if dir.Magnitude > 0.01 then
			cart:PivotTo(CFrame.lookAt(pos, pos + dir))
		end
	end)
end

-- Estación de carga junto a la vía: andén, techo con letrero y terminal con el aviso para enviar.
local function buildStation(index: number, at: Vector3, along: Vector3): ProximityPrompt
	local flat = Vector3.new(along.X, 0, along.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local side = flat:Cross(Vector3.yAxis).Unit
	local center = at + side * 5.5
	local frame = CFrame.lookAt(center, center + flat)
	local model = Instance.new("Model")
	model.Name = `Station{index}`
	model.Parent = folder
	part(model, "Platform", Vector3.new(6, 0.6, 10), frame * CFrame.new(0, 0.3, 0), DARK, Enum.Material.DiamondPlate)
	deco(model, "PlatformEdge", Vector3.new(0.4, 0.1, 10), frame * CFrame.new(-3, 0.65, 0), HAZARD, Enum.Material.SmoothPlastic)
	for _, z in { -4.4, 4.4 } do
		part(model, "Post", Vector3.new(0.6, 7, 0.6), frame * CFrame.new(2.4, 3.6, z), RUST, Enum.Material.CorrodedMetal)
	end
	part(model, "Roof", Vector3.new(6.6, 0.4, 10.4), frame * CFrame.new(0.3, 7.2, 0), RUST, Enum.Material.CorrodedMetal)
	local sign = part(model, "Sign", Vector3.new(0.3, 1.6, 8), frame * CFrame.new(-2.9, 6.2, 0), DARK, Enum.Material.Metal)
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.PixelsPerStud = 40
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = HAZARD
		label.Text = if index == 0 then "ESTACIÓN · FOSO" else `ESTACIÓN {index}`
		label.Parent = gui
		gui.Parent = sign
	end
	local terminal = part(model, "Terminal", Vector3.new(1.4, 3, 2), frame * CFrame.new(1, 2.1, 0), DARK, Enum.Material.Metal)
	local screen = deco(model, "Screen", Vector3.new(0.1, 1.2, 1.6), terminal.CFrame * CFrame.new(-0.75, 0.5, 0), Color3.fromRGB(90, 255, 140), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = screen.Color, 10, 0.7, false
	glow.Parent = screen
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enviar minerales a tu base"
	prompt.ObjectText = "Carrito"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = terminal
	return prompt
end

local function build()
	folder = Instance.new("Folder")
	folder.Name = "Carts"
	folder.Parent = workspace

	-- línea principal bajo tierra: los rieles de la ruta en orden; las paradas son el final de cada tramo con stop
	local main, stops = {}, {}
	for k, points in Route.Paths do
		for _, p in points do
			if #main == 0 or (main[#main] - p).Magnitude > 0.5 then table.insert(main, p) end
		end
		local seg = World.Route[k]
		if seg and seg.stop and #main > 0 then table.insert(stops, #main) end
	end
	if #main == 0 then
		warn("[Carts] la ruta no tiene rieles; no hay carritos")
		return
	end

	-- vía de superficie: boca del portal → rodea la rejilla → puerta de arco → pasaje → anillo de la cueva de la base
	local start = main[1]
	local hubPath = { start }
	local exit = Vector2.new(HUB.ExitDown.X, HUB.ExitDown.Z).Unit
	local wp = Config.HubWaypoint
	local waypointA = HUB_XZ + exit * 80
	local waypointB = HUB_XZ + Vector2.new(math.cos(math.rad(wp.Angle)), math.sin(math.rad(wp.Angle))) * wp.Distance
	local gateMouth = HUB_XZ + GATE_DIR * (HUB.Radius - 2)
	local spawnWall = SPAWN_XZ - GATE_DIR * (SPAWN.Radius - 2)
	local ringEntry = SPAWN_XZ - GATE_DIR * Config.RingRadius
	line(xz(start), waypointA, hubPath)
	line(waypointA, waypointB, hubPath)
	line(waypointB, gateMouth, hubPath)
	line(gateMouth, spawnWall, hubPath)
	line(spawnWall, ringEntry, hubPath)
	drawRails(hubPath)

	local ring = {}
	local ringStart = angleOf(ringEntry)
	for k = 0, math.ceil(math.pi * 2 * Config.RingRadius / 4) - 1 do
		local a = ringStart + k * 4 / Config.RingRadius
		local p = SPAWN_XZ + Vector2.new(math.cos(a), math.sin(a)) * Config.RingRadius
		table.insert(ring, floorAt(p.X, p.Y))
	end
	drawRails(ring, true)

	-- de la boca del portal hasta el andén de cada base
	local toBase = {}
	for _, base in Bases.All() do
		local path = table.clone(hubPath)
		local laneAngle = angleOf(xz(base.laneEntry))
		arc(ringStart, laneAngle, path)
		local branch = { path[#path] }
		line(xz(path[#path]), xz(base.laneEntry), branch)
		drawRails(branch)
		for k = 2, #branch do table.insert(path, branch[k]) end
		straight(base.laneEntry, base.dock, path) -- dentro del andén, sobre su piso (los rieles ya los tiene la base)
		toBase[base.index] = path
	end

	-- estaciones: la del foso (al inicio de la vía) y una en cada parada de la ruta
	local cooldown: { [Player]: number } = {}
	local function addStation(stationIndex: number, mainIndex: number)
		local at = main[mainIndex]
		local nextPoint = main[math.min(mainIndex + 1, #main)]
		local prevPoint = main[math.max(mainIndex - 1, 1)]
		local along = if nextPoint ~= at then nextPoint - at else at - prevPoint
		if mainIndex == 1 then along = Vector3.new(waypointA.X, 0, waypointA.Y) - Vector3.new(at.X, 0, at.Z) end
		local prompt = buildStation(stationIndex, at, along)
		prompt.Triggered:Connect(function(player)
			local base = Bases.Get(player)
			if not base or not toBase[base.index] then return end
			if os.clock() - (cooldown[player] or 0) < Config.SendCooldown then return end
			local counts, total = Bases.TakeInventory(player)
			if total == 0 then return end
			cooldown[player] = os.clock()

			-- recorrido: de la estación hacia arriba por la ruta y luego la vía de superficie hasta su andén
			local path = {}
			for k = mainIndex, 1, -1 do table.insert(path, main[k]) end
			for k = 2, #toBase[base.index] do table.insert(path, toBase[base.index][k]) end

			local ore = {}
			for _, rarity in RARITIES do
				if counts[rarity] then
					for _ = 1, math.min(counts[rarity], 2) do table.insert(ore, Minerals[rarity].Color) end
				end
			end
			while #ore > 6 do table.remove(ore, 1) end
			local cart = makeCart(base.color, ore)
			cart:PivotTo(CFrame.lookAt(path[1], path[math.min(2, #path)] + Vector3.new(0, 0.001, 0)))
			cart.Parent = folder
			run(cart, path, function()
				-- llegó al andén: descarga en el almacén de la base (si el dueño sigue en el juego)
				if player.Parent == Players and Bases.Get(player) == base then
					Bases.Deposit(player, counts, true)
				end
				for _, piece in cart:GetChildren() do
					if piece.Name == "Ore" then piece:Destroy() end
				end
				task.delay(2, function() cart:Destroy() end)
			end)
		end)
	end
	addStation(0, 1)
	for n, mainIndex in stops do
		addStation(n, mainIndex)
	end
	Players.PlayerRemoving:Connect(function(p) cooldown[p] = nil end)
end

return {
	Start = function()
		-- espera a que estén la ruta (con sus rieles) y las bases
		while workspace:GetAttribute("RouteReady") ~= true or workspace:GetAttribute("BasesReady") ~= true do
			task.wait(0.25)
		end
		local ok, err = pcall(build)
		if not ok then
			warn(`[Carts] no se pudo construir el sistema de carritos: {err}`)
		end
	end,
}
