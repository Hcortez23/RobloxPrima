-- Utilería de las cuevas de arriba, estilo apocalíptico-industrial. Se construye cuando World termina de tallarlas
-- (atributo WorldReady). Cueva del foso: rejilla con cristal sobre el pozo al núcleo (se ve el brillo, no se puede bajar),
-- torres de reflectores, generadores con humo y neón, tuberías por las paredes y lámparas colgando del techo; la gran
-- puerta de arco hacia la cueva de la base. Cueva de la base: plataforma de spawn y luces (ahí irán bases y tiendas). Todo con Parts; para cambiar el arte, reemplazar estas funciones por modelos de assets/models.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.World)

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
local toSpawnCave, gate, spawnCave -- se definen más abajo (las usan wallPipes y build)

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
	local exits = { HUB.ExitDown.Unit, toSpawnCave() }
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

-- Dirección (en XZ) desde la cueva del foso hacia la cueva de la base.
function toSpawnCave(): Vector3
	local s = Config.SpawnCave.Center
	return Vector3.new(s.X - HUB.Center.X, 0, s.Z - HUB.Center.Z).Unit
end

-- Gran puerta de arco entre la cueva de la base y la del foso, del lado de la cueva del foso: pilares con franjas de
-- advertencia, arco de metal con luces de neón por dentro, clave iluminada, portones abiertos contra las paredes del
-- pasaje y letreros a cada lado.
function gate()
	local spec = Config.Gate
	local dir = toSpawnCave()
	local side = dir:Cross(Vector3.yAxis).Unit
	local up = Vector3.yAxis
	local base = CENTER + dir * (HUB.Radius - 6) -- en la boca del pasaje, a ras del piso
	local half = spec.Width / 2 + 2.5

	for _, s in { -1, 1 } do -- pilares
		local pillarPos = base + side * (s * half) + up * (spec.Height / 2)
		part("GatePillar", Vector3.new(5, spec.Height, 7), CFrame.lookAt(pillarPos, pillarPos + dir), DARK, Enum.Material.Metal)
		for band = 1, 3 do
			local bandPos = base + side * (s * half) + up * (band * 4)
			local stripe = part("GateStripe", Vector3.new(5.2, 1.2, 7.2), CFrame.lookAt(bandPos, bandPos + dir), if band % 2 == 0 then DARK else HAZARD, Enum.Material.SmoothPlastic)
			stripe.CanCollide = false
		end
		-- portón abierto, apoyado contra la pared del pasaje
		local doorPos = base + side * (s * (spec.Width / 2 - 1)) + dir * (spec.Width / 4 + 3) + up * (spec.Height / 2)
		part("GateDoor", Vector3.new(1.2, spec.Height - 2, spec.Width / 2), CFrame.lookAt(doorPos, doorPos + dir), RUST, Enum.Material.DiamondPlate)
	end

	-- arco: segmentos sobre media circunferencia, con una franja de neón por dentro
	local center = base + up * spec.Height
	local segments = 14
	for i = 0, segments - 1 do
		local t = (i + 0.5) / segments * math.pi
		local radial = side * math.cos(t) + up * math.sin(t)
		local tangent = -side * math.sin(t) + up * math.cos(t)
		local length = half * math.pi / segments + 0.6
		part("GateArch", Vector3.new(length, 5, 7), CFrame.fromMatrix(center + radial * half, tangent, radial), DARK, Enum.Material.Metal)
		local glow = part("GateArchLight", Vector3.new(length, 0.6, 1.6), CFrame.fromMatrix(center + radial * (half - 2.8), tangent, radial), NEON_ORANGE, Enum.Material.Neon)
		glow.CanCollide = false
		if i % 3 == 1 then
			light(glow, "PointLight", { Color = NEON_ORANGE, Range = 20, Brightness = 1.2, Shadows = false })
		end
	end
	local keystone = part("GateKeystone", Vector3.new(6, 6, 8), CFrame.lookAt(center + up * (half + 1), center + up * (half + 1) + dir), RUST, Enum.Material.CorrodedMetal)
	local lamp = part("GateKeystoneLight", Vector3.new(3, 3, 8.4), keystone.CFrame, NEON_CYAN, Enum.Material.Neon)
	lamp.CanCollide = false
	light(lamp, "PointLight", { Color = NEON_CYAN, Range = 30, Brightness = 2, Shadows = false })

	-- letreros sobre el arco: hacia la cueva de la base y hacia la del foso
	local signPos = center + up * (half + 7)
	local sign = part("GateSign", Vector3.new(spec.Width, 4, 1), CFrame.lookAt(signPos, signPos + dir), DARK, Enum.Material.Metal)
	for _, face in { { Enum.NormalId.Front, "ACCESO AL NÚCLEO" }, { Enum.NormalId.Back, "BASE" } } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face[1]
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.PixelsPerStud = 40
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = HAZARD
		label.Text = face[2]
		label.Parent = gui
		gui.Parent = sign
	end
end

-- Cueva de la base (spawn): por ahora iluminación; el piso queda libre para las bases y las tiendas.
function spawnCave()
	local spec = Config.SpawnCave
	local floor = Vector3.new(spec.Center.X, spec.Center.Y - spec.Height / 2, spec.Center.Z)
	for i = 0, 5 do
		hangingLamp(floor, math.rad(i * 60), spec.Radius * 0.55, 30)
	end
	hangingLamp(floor, 0, 0, 34)
end

local function build()
	folder = Instance.new("Folder")
	folder.Name = "Hub"
	folder.Parent = workspace

	grate()
	spawnPad()
	-- las salidas y el spawn quedan libres: torres y generadores entre ellos
	-- ángulos desde +X hacia +Z: 0° salida de arriba, 90° salida de abajo, 270° spawn
	for _, a in { 20, 60, 120, 160, 200, 340 } do
		floodlight(math.rad(a), HUB.Radius * 0.72)
	end
	for i, a in { 45, 135, 225, 315 } do
		generator(math.rad(a), HUB.Radius - 16, if i % 2 == 0 then NEON_CYAN else NEON_ORANGE)
	end
	wallPipes()
	for i = 0, 7 do
		hangingLamp(CENTER, math.rad(i * 45 + 22.5), if i % 2 == 0 then HUB.Radius * 0.45 else HUB.Radius * 0.75, 34)
	end
	gate()
	spawnCave()
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
