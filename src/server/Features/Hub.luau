-- Utilería de las cuevas de arriba, estilo apocalíptico-industrial. Se construye cuando World termina de tallarlas
-- (atributo WorldReady). Cueva del foso: rejilla con cristal sobre el pozo al núcleo (se ve el brillo, no se puede bajar),
-- torres de reflectores, generadores con humo y neón, tuberías por las paredes, lámparas colgando del techo, el portal
-- DESCENSO y la plataforma del spawn general. Los arcos de los pasajes a las cuevas-base los pone Bases.luau; el
-- elevador y el permiso de descenso, LayerHubs.luau; la estación de carritos, Carts.luau.
-- Todo con Parts; para cambiar el arte, reemplazar estas funciones por modelos de assets/models.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.World)
local BaseLayout = require(ReplicatedStorage.Shared.BaseLayout)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.Progression)

local HUB = Config.Hub
local FLOOR = HUB.Center.Y - HUB.Height / 2
local CENTER = Vector3.new(HUB.Center.X, FLOOR, HUB.Center.Z)

local RUST = Color3.fromRGB(110, 62, 40)
local DARK = Color3.fromRGB(48, 50, 56)
local STEEL = Color3.fromRGB(120, 124, 130)
local HAZARD = Color3.fromRGB(230, 180, 40)
local NEON_ORANGE = Color3.fromRGB(255, 140, 50)
local NEON_CYAN = Color3.fromRGB(80, 200, 255)
local LAMP = Color3.fromRGB(255, 214, 160)

local folder: Folder
local descentPortal -- se define más abajo (la usa build)

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CanTouch = false -- utilería: sin eventos de contacto (rendimiento)
	p.Parent = folder
	return p
end

-- cilindro vertical (los cilindros de Roblox tienen el eje en X)
local function column(name: string, base: Vector3, height: number, radius: number, color: Color3, material: Enum.Material): Part
	return part(name, Vector3.new(height, radius * 2, radius * 2), CFrame.new(base + Vector3.yAxis * height / 2) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder)
end

local function light(parent: Instance, className: string, props: { [string]: any })
	local l = Instance.new(className)
	for k, v in props do (l :: any)[k] = v end
	l.Parent = parent
end

-- punto en el piso de la base a cierta distancia y ángulo del centro
local function onFloor(angle: number, distance: number): Vector3
	return CENTER + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function facingCenter(pos: Vector3): CFrame
	return CFrame.lookAt(pos, Vector3.new(CENTER.X, pos.Y, CENTER.Z))
end

-- Rejilla sobre el pozo: cristal anaranjado que se puede pisar, marco circular, vigas cruzadas y aro de advertencia.
local function grate()
	local radius = Config.PitRadius + Config.PitRagged + 6
	local glass = part("PitGlass", Vector3.new(1, radius * 2, radius * 2), CFrame.new(CENTER - Vector3.yAxis * 0.5) * CFrame.Angles(0, 0, math.pi / 2), NEON_ORANGE, Enum.Material.Glass, Enum.PartType.Cylinder)
	glass.Transparency = 0.6
	local segments = 28
	for i = 0, segments - 1 do -- marco
		local a = i * math.pi * 2 / segments
		local pos = CENTER + Vector3.new(math.cos(a) * radius, 0.75, math.sin(a) * radius)
		part("GrateFrame", Vector3.new(1.4, 1.5, radius * 2 * math.pi / segments + 0.4), CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a))), RUST, Enum.Material.CorrodedMetal)
		local warn = CENTER + Vector3.new(math.cos(a) * (radius + 2.2), 0.08, math.sin(a) * (radius + 2.2))
		local stripe = part("GrateWarning", Vector3.new(1.6, 0.15, radius * 2 * math.pi / segments * 0.55), CFrame.lookAt(warn, warn + Vector3.new(-math.sin(a), 0, math.cos(a))), if i % 2 == 0 then HAZARD else DARK, Enum.Material.SmoothPlastic)
		stripe.CanCollide = false
	end
	for _, dir in { Vector3.xAxis, Vector3.zAxis } do -- vigas en cuadrícula
		for offset = -radius + 6, radius - 6, 9 do
			local half = math.sqrt(radius * radius - offset * offset)
			local side = if dir == Vector3.xAxis then Vector3.zAxis else Vector3.xAxis
			local pos = CENTER + side * offset + Vector3.yAxis * 0.4
			part("GrateBeam", Vector3.new(0.9, 0.8, half * 2), CFrame.lookAt(pos, pos + dir), DARK, Enum.Material.DiamondPlate)
		end
	end
end

-- Plataforma de spawn: placa industrial con borde de neón.
local function spawnPad()
	local pos = Vector3.new(Config.SpawnPosition.X, FLOOR + 0.3, Config.SpawnPosition.Z)
	part("SpawnPad", Vector3.new(18, 0.6, 18), CFrame.new(pos), DARK, Enum.Material.DiamondPlate)
	for _, s in { -1, 1 } do
		local edgeA = part("SpawnEdge", Vector3.new(18, 0.2, 0.5), CFrame.new(pos + Vector3.new(0, 0.35, s * 9)), NEON_CYAN, Enum.Material.Neon)
		local edgeB = part("SpawnEdge", Vector3.new(0.5, 0.2, 18), CFrame.new(pos + Vector3.new(s * 9, 0.35, 0)), NEON_CYAN, Enum.Material.Neon)
		edgeA.CanCollide, edgeB.CanCollide = false, false
	end
end

-- Torre de reflectores: poste, travesaño y foco apuntando hacia el centro de la base.
local function floodlight(angle: number, distance: number)
	local base = onFloor(angle, distance)
	local height = 26
	part("TowerBase", Vector3.new(5, 1, 5), facingCenter(base + Vector3.yAxis * 0.5), DARK, Enum.Material.DiamondPlate)
	column("TowerPole", base, height, 0.8, RUST, Enum.Material.CorrodedMetal)
	local headPos = base + Vector3.yAxis * height
	local head = part("Floodlight", Vector3.new(5, 2.5, 2), facingCenter(headPos) * CFrame.Angles(math.rad(-30), 0, 0), DARK, Enum.Material.Metal)
	local lens = part("FloodlightLens", Vector3.new(4.4, 1.9, 0.3), head.CFrame * CFrame.new(0, 0, -1.1), LAMP, Enum.Material.Neon)
	lens.CanCollide = false
	light(lens, "SpotLight", { Face = Enum.NormalId.Front, Brightness = 4, Range = 75, Angle = 70, Color = LAMP, Shadows = true })
end

-- Generador: bloque con dos tanques, franjas de neón, escape con humo.
local function generator(angle: number, distance: number, glow: Color3)
	local pos = onFloor(angle, distance)
	local frame = facingCenter(pos + Vector3.yAxis * 3)
	part("Generator", Vector3.new(11, 6, 7), frame, DARK, Enum.Material.Metal)
	part("GeneratorPlate", Vector3.new(11.2, 1, 7.2), frame * CFrame.new(0, -2.6, 0), HAZARD, Enum.Material.SmoothPlastic)
	for _, s in { -1, 1 } do
		local tank = frame * CFrame.new(s * 3, 5.5, 0)
		part("Tank", Vector3.new(5, 4, 4), tank * CFrame.Angles(0, 0, math.pi / 2), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	local stripe = part("GeneratorStripe", Vector3.new(9, 0.5, 0.2), frame * CFrame.new(0, 1, -3.6), glow, Enum.Material.Neon)
	light(stripe, "PointLight", { Color = glow, Range = 18, Brightness = 1.5, Shadows = false })
	local exhaust = part("Exhaust", Vector3.new(6, 1.4, 1.4), frame * CFrame.new(4, 9, 2) * CFrame.Angles(0, 0, math.pi / 2), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 66, 70), Color3.fromRGB(120, 112, 110))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime, smoke.Speed, smoke.Rate = NumberRange.new(4, 6), NumberRange.new(3, 5), 4
	smoke.EmissionDirection = Enum.NormalId.Right -- el eje del cilindro (X) queda vertical
	smoke.Parent = exhaust
end

-- Tubería que recorre la pared a cierta altura, con soportes; se corta en las salidas.
local function wallPipes()
	local radius = HUB.Radius - 4
	local height = 18
	local exits = {}
	for _, o in BaseLayout.Openings() do table.insert(exits, Vector3.new(o.X, 0, o.Y)) end -- portal y pasajes a las bases
	if HUB.ExitUp then table.insert(exits, HUB.ExitUp.Unit) end -- la salida a la superficie es opcional
	local segments = 36
	for i = 0, segments - 1 do
		local a0, a1 = i * math.pi * 2 / segments, (i + 1) * math.pi * 2 / segments
		local mid = (a0 + a1) / 2
		local dir = Vector3.new(math.cos(mid), 0, math.sin(mid))
		local nearExit = false
		for _, e in exits do
			if dir:Dot(e) > 0.94 then nearExit = true end
		end
		if not nearExit then
			local p0, p1 = onFloor(a0, radius) + Vector3.yAxis * height, onFloor(a1, radius) + Vector3.yAxis * height
			local center = (p0 + p1) / 2
			part("WallPipe", Vector3.new((p1 - p0).Magnitude + 0.3, 2.4, 2.4), CFrame.lookAt(center, p1) * CFrame.Angles(0, math.pi / 2, 0), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
			if i % 3 == 0 then
				column("PipeSupport", onFloor(a0, radius), height, 0.4, DARK, Enum.Material.Metal)
			end
		end
	end
end

-- Lámpara colgando del techo: cadena hasta el techo (se mide con un rayo) y foco cálido. `floor` es el punto del piso
-- en el centro de la cueva.
local function hangingLamp(floor: Vector3, angle: number, distance: number, height: number)
	local base = floor + Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(base, Vector3.yAxis * 120, params)
	local ceiling = if hit then hit.Position.Y else base.Y + 20
	local length = math.max(ceiling - base.Y, 1)
	local chain = column("LampChain", base, length, 0.15, DARK, Enum.Material.Metal)
	chain.CanCollide = false
	local lamp = part("Lamp", Vector3.new(2, 3, 3), CFrame.new(base) * CFrame.Angles(0, 0, math.pi / 2), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	local bulb = part("LampBulb", Vector3.one * 1.6, CFrame.new(base - Vector3.yAxis * 1.2), LAMP, Enum.Material.Neon, Enum.PartType.Ball)
	bulb.CanCollide = false
	light(bulb, "PointLight", { Color = LAMP, Range = 40, Brightness = 2, Shadows = true })
	lamp.CanCollide = false
end

-- Portal de la entrada inicial (la única salida de la cueva del foso hacia abajo): marco con franjas de advertencia,
-- viga con neón verde, balizas y el letrero "DESCENSO", para que se vea desde toda la cueva.
function descentPortal()
	local dir = HUB.ExitDown.Unit
	local side = dir:Cross(Vector3.yAxis).Unit
	local up = Vector3.yAxis
	local opening = HUB.TunnelRadius
	local half = opening + 3
	local height = opening * 2 + 4
	local base = CENTER + dir * (HUB.Radius - opening - 8)
	local go = Color3.fromRGB(90, 255, 140)

	for _, s in { -1, 1 } do
		local postPos = base + side * (s * half) + up * (height / 2)
		part("PortalPost", Vector3.new(4, height, 6), CFrame.lookAt(postPos, postPos + dir), DARK, Enum.Material.Metal)
		for band = 1, math.floor(height / 5) do
			local bandPos = base + side * (s * half) + up * (band * 5 - 2)
			local stripe = part("PortalStripe", Vector3.new(4.2, 1.6, 6.2), CFrame.lookAt(bandPos, bandPos + dir), if band % 2 == 0 then DARK else HAZARD, Enum.Material.SmoothPlastic)
			stripe.CanCollide = false
		end
		local strip = part("PortalLight", Vector3.new(0.6, height - 4, 0.6), CFrame.lookAt(postPos - side * (s * 2.3), postPos - side * (s * 2.3) + dir), go, Enum.Material.Neon)
		strip.CanCollide = false
		local beaconPos = base + side * (s * half) + up * (height + 1.5)
		local beacon = part("PortalBeacon", Vector3.one * 2.4, CFrame.new(beaconPos), Color3.fromRGB(255, 70, 50), Enum.Material.Neon, Enum.PartType.Ball)
		light(beacon, "PointLight", { Color = beacon.Color, Range = 18, Brightness = 1.5, Shadows = false })
	end
	local beamPos = base + up * (height + 1)
	local beam = part("PortalBeam", Vector3.new(half * 2 + 4, 3, 6), CFrame.lookAt(beamPos, beamPos + dir), RUST, Enum.Material.CorrodedMetal)
	local beamLight = part("PortalBeamLight", Vector3.new(half * 2, 0.6, 0.6), beam.CFrame * CFrame.new(0, -1.7, -2.6), go, Enum.Material.Neon)
	beamLight.CanCollide = false
	light(beamLight, "PointLight", { Color = go, Range = 30, Brightness = 1.6, Shadows = false })

	-- letrero mirando hacia la cueva
	local signPos = base + up * (height + 6)
	local sign = part("PortalSign", Vector3.new(half * 2, 4.5, 1), CFrame.lookAt(signPos, signPos - dir), DARK, Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = go
	label.Text = "DESCENSO"
	label.Parent = gui
	gui.Parent = sign
end

-- Ángulos (desde +X hacia +Z) en el medio de cada hueco ancho entre aberturas de la pared de la cueva del foso.
local function gapAngles(): { number }
	local angles = {}
	for _, o in BaseLayout.Openings() do table.insert(angles, math.atan2(o.Y, o.X) % (math.pi * 2)) end
	table.sort(angles)
	local result = {}
	for k, a in angles do
		local nextA = angles[k % #angles + 1] + (if k == #angles then math.pi * 2 else 0)
		if nextA - a >= math.rad(40) then table.insert(result, (a + nextA) / 2) end
	end
	return result
end

local function build()
	folder = Instance.new("Folder")
	folder.Name = "Hub"
	folder.Parent = workspace

	grate()
	spawnPad()
	-- torres y generadores en los huecos entre las aberturas (portal y pasajes a las bases), nunca delante de una;
	-- frente al spawn general no va torre para no taparlo
	local spawnAngle = math.atan2(Config.SpawnPosition.Z - CENTER.Z, Config.SpawnPosition.X - CENTER.X)
	local function near(a: number, b: number): boolean
		return math.abs((a - b + math.pi) % (math.pi * 2) - math.pi) < math.rad(15)
	end
	for k, a in gapAngles() do
		local nearSpawn = near(a, spawnAngle)
		local station = near(a, ProgressionConfig.StationAngle) -- ahí va la estación de carritos (Carts)
		if not nearSpawn and not station then
			floodlight(a, HUB.Radius * 0.72)
		end
		if (k % 2 == 1 or nearSpawn) and not station then
			generator(a, HUB.Radius - 16, if k % 4 == 1 then NEON_CYAN else NEON_ORANGE)
		end
	end
	wallPipes()
	for i = 0, 7 do
		hangingLamp(CENTER, math.rad(i * 45 + 22.5), if i % 2 == 0 then HUB.Radius * 0.45 else HUB.Radius * 0.75, 34)
	end
	descentPortal()
end

return {
	Start = function()
		-- World pone WorldReady en true cuando la caverna ya está tallada
		while workspace:GetAttribute("WorldReady") ~= true do
			task.wait(0.2)
		end
		local ok, err = pcall(build)
		if not ok then
			warn(`[Hub] no se pudo construir la base: {err}`)
		end
	end,
}
