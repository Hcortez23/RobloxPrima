-- Utilería de las minas abandonadas (World.Mines: la forma ya está tallada en la roca). Cada mina se amuebla solo
-- cuando algún jugador anda cerca y se quita cuando todos se alejan; se arma con la semilla de la mina, así que
-- siempre sale igual. Lo que lleva:
--  · Galerías: entibado de madera (postes y vigas, alguno roto), faroles colgados (pocos encendidos, luz tenue),
--    rieles con durmientes y a veces un carrito abandonado (algunos volcados), piedras sueltas y vigas caídas en los
--    derrumbes.
--  · Salas: almacén (cajas, barriles, estantería), taller (perforadora, generador, banco con herramientas),
--    dormitorio (literas, mesa, banquitos) o campamento (tienda, fogata apagada, saco de dormir, mochila).
--  · Sala central de cada complejo: letrero "SECTOR capa-número"; si tiene pozo, una escalera para subir.
local Players = game:GetService("Players")

local World = require(script.Parent.World)
local SignKit = require(script.Parent.SignKit)

local ACTIVATE = 230 -- se amuebla si hay un jugador a menos de esto del centro de la mina
local DEACTIVATE = 330 -- se quita si todos están más lejos
local BUILDS_PER_TICK = 3

local WOOD = Color3.fromRGB(96, 70, 48)
local OLD_WOOD = Color3.fromRGB(78, 62, 50)
local RUST = Color3.fromRGB(110, 62, 40)
local DARK = Color3.fromRGB(48, 50, 56)
local STEEL = Color3.fromRGB(96, 100, 108)
local RAIL = Color3.fromRGB(86, 82, 80)
local HAZARD = Color3.fromRGB(190, 150, 40) -- amarillo desgastado
local FABRIC = Color3.fromRGB(92, 84, 64)
local STONE = Color3.fromRGB(70, 68, 66)
local LAMP = Color3.fromRGB(255, 196, 130)

local folder: Folder
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanTouch = name, true, false
	p.Size, p.CFrame, p.Color, p.Material = size, cframe, color, material
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- decoración: sin colisión, sin rayos (disparos y gancho la atraviesan), sin sombra
local function deco(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = part(parent, name, size, cframe, color, material, shape)
	p.CanCollide, p.CanQuery, p.CastShadow = false, false, false
	return p
end

local function light(parent: Instance, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = LAMP, range, brightness, false
	l.Parent = parent
end

-- suelo bajo `p` (rayo corto contra el terreno); si no lo encuentra, `p`
local function floorAt(p: Vector3): Vector3
	local hit = workspace:Raycast(p + Vector3.yAxis * 3, Vector3.yAxis * -12, terrainOnly)
	return if hit then hit.Position else p
end

-- cilindro vertical (los de Roblox tienen el eje en X)
local function upright(at: CFrame, height: number, radius: number): CFrame
	return at * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
end

-- Farol colgando: encendido (luz tenue) o roto.
local function lantern(model: Model, at: CFrame, lit: boolean)
	deco(model, "LanternChain", Vector3.new(0.12, 1.2, 0.12), at * CFrame.new(0, -0.6, 0), DARK, Enum.Material.Metal)
	deco(model, "Lantern", Vector3.new(0.8, 0.3, 0.8), at * CFrame.new(0, -1.3, 0), RUST, Enum.Material.CorrodedMetal)
	local glass = deco(model, "LanternGlass", Vector3.new(0.6, 0.8, 0.6), at * CFrame.new(0, -1.85, 0), if lit then LAMP else Color3.fromRGB(40, 40, 38), if lit then Enum.Material.Neon else Enum.Material.Glass)
	if lit then
		glass.Transparency = 0.2
		light(glass, 16, 0.6)
	end
end

-- Carrito de mina viejo, sin brillo; algunos con roca dentro.
local function oldCart(model: Model, at: CFrame, loaded: boolean)
	part(model, "CartChassis", Vector3.new(3.2, 0.4, 4.6), at * CFrame.new(0, 0.9, 0), DARK, Enum.Material.Metal)
	for _, s in { -1, 1 } do
		part(model, "CartWall", Vector3.new(3.2, 1.6, 0.25), at * CFrame.new(0, 1.9, s * 2.2), RUST, Enum.Material.CorrodedMetal)
		part(model, "CartWall", Vector3.new(0.25, 1.6, 4.6), at * CFrame.new(s * 1.5, 1.9, 0), RUST, Enum.Material.CorrodedMetal)
		for _, w in { -1.5, 1.5 } do
			deco(model, "CartWheel", Vector3.new(0.4, 1, 1), at * CFrame.new(s * 1.7, 0.55, w), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end
	if loaded then
		for k = 1, 4 do
			deco(model, "CartRock", Vector3.one * 1.3, at * CFrame.new(((k - 1) % 2 - 0.5) * 1.3, 2.3, (math.floor((k - 1) / 2) - 0.5) * 1.6), STONE, Enum.Material.Slate, Enum.PartType.Ball)
		end
	end
end

local function crate(model: Model, at: CFrame, size: number)
	part(model, "Crate", Vector3.one * size, at * CFrame.new(0, size / 2, 0), WOOD, Enum.Material.WoodPlanks)
end

local function barrel(model: Model, at: CFrame, color: Color3)
	part(model, "Barrel", Vector3.new(3, 2.2, 2.2), upright(at, 3, 1.1), color, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
end

local function pickaxe(model: Model, at: CFrame)
	deco(model, "PickHandle", Vector3.new(0.25, 3, 0.25), at, OLD_WOOD, Enum.Material.Wood)
	deco(model, "PickHead", Vector3.new(2.2, 0.3, 0.3), at * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, 0.15), STEEL, Enum.Material.Metal)
end

-- Galería: entibado, faroles, rieles, carrito, piedras y, si se derrumbó, vigas caídas.
local function furnishTunnel(model: Model, mine, t, rng: Random)
	local up = Vector3.yAxis
	local along = t.to - t.from
	local length = along.Magnitude
	if length < 6 then return end
	local flat = Vector3.new(along.X, 0, along.Z).Unit
	-- las galerías que salen de la sala central empiezan dentro de ella: la utilería empieza en su pared
	local skip = if t.from == mine.center then (if mine.camp then 8 else 15) else t.width / 2 + 1
	local stop = if t.collapsed then length - t.width * 0.8 else length - 2
	if stop <= skip + 4 then return end
	local floorA = floorAt(t.from:Lerp(t.to, skip / length))
	local floorB = floorAt(t.from:Lerp(t.to, stop / length))
	local function frameAt(s: number): CFrame
		local p = floorA:Lerp(floorB, (s - skip) / (stop - skip))
		return CFrame.lookAt(p, p + flat)
	end
	local postX = t.width / 2 - 0.8
	local postH = t.height - 1.2
	local k = 0
	for s = skip + 2, stop, 8 do
		k += 1
		local f = frameAt(s)
		local broken = rng:NextNumber() < 0.12
		part(model, "Post", Vector3.new(0.9, postH, 0.9), f * CFrame.new(-postX, postH / 2, 0), WOOD, Enum.Material.Wood)
		if not broken then
			part(model, "Post", Vector3.new(0.9, postH, 0.9), f * CFrame.new(postX, postH / 2, 0), WOOD, Enum.Material.Wood)
			deco(model, "Beam", Vector3.new(t.width - 0.6, 0.9, 0.9), f * CFrame.new(0, postH + 0.45, 0), WOOD, Enum.Material.Wood)
			if k % 3 == 0 then lantern(model, f * CFrame.new(0, postH, 0), rng:NextNumber() < 0.3) end
		else -- viga suelta, apoyada en un poste y en el suelo
			deco(model, "Beam", Vector3.new(t.width - 0.6, 0.9, 0.9), f * CFrame.new(-0.6, postH / 2, 0) * CFrame.Angles(0, 0.2, 0.75), OLD_WOOD, Enum.Material.Wood)
		end
	end
	if t.rails then
		local a, b = frameAt(skip), frameAt(stop)
		for _, x in { -1.6, 1.6 } do
			local ra, rb = (a * CFrame.new(x, 0.45, 0)).Position, (b * CFrame.new(x, 0.45, 0)).Position
			deco(model, "Rail", Vector3.new(0.3, 0.3, (rb - ra).Magnitude), CFrame.lookAt((ra + rb) / 2, rb), RAIL, Enum.Material.Metal)
		end
		for s = skip, stop, 4 do
			deco(model, "Sleeper", Vector3.new(4.6, 0.3, 0.8), frameAt(s) * CFrame.new(0, 0.15, 0), OLD_WOOD, Enum.Material.WoodPlanks)
		end
		if rng:NextNumber() < 0.55 then
			local f = frameAt(skip + (stop - skip) * rng:NextNumber(0.25, 0.8))
			if rng:NextNumber() < 0.3 then -- volcado a un lado
				oldCart(model, f * CFrame.new(2.6, 1.6, 0) * CFrame.Angles(0, 0, -1.35), false)
			else
				oldCart(model, f, rng:NextNumber() < 0.6)
			end
		end
	end
	for _ = 1, rng:NextInteger(2, 4) do -- piedras sueltas junto a las paredes
		local f = frameAt(skip + (stop - skip) * rng:NextNumber())
		local size = rng:NextNumber(0.8, 2.2)
		deco(model, "Rubble", Vector3.one * size, f * CFrame.new((if rng:NextNumber() < 0.5 then -1 else 1) * (postX - 1.2), size * 0.35, 0), STONE, Enum.Material.Slate, Enum.PartType.Ball)
	end
	if t.collapsed then
		local f = frameAt(stop)
		for n = 1, 2 do
			deco(model, "FallenBeam", Vector3.new(0.9, 0.9, t.width), f * CFrame.new(0, 1 + n, -1 - n) * CFrame.Angles(0.5 * n, 0.6 * n, 0.3), OLD_WOOD, Enum.Material.Wood)
		end
	end
end

-- Muebles de cada tipo de sala, en coordenadas de la sala (origen en el centro del suelo).
local ROOMS = {}

function ROOMS.Almacen(model: Model, room: CFrame, sx: number, sz: number, rng: Random)
	for _ = 1, rng:NextInteger(4, 7) do -- pilas de cajas junto a las paredes
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local base = room * CFrame.new(side * (sx / 2 - 2.5), 0, rng:NextNumber(-sz / 2 + 3, sz / 2 - 3)) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)
		for level = 0, rng:NextInteger(0, 2) do
			crate(model, base * CFrame.new(0, level * 3, 0) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0), 3)
		end
	end
	local corner = room * CFrame.new(rng:NextNumber(-sx / 4, sx / 4), 0, sz / 2 - 2.5)
	for k = 1, rng:NextInteger(3, 6) do
		barrel(model, corner * CFrame.new((k - 1) * 2.4 - 3, 0, (k % 2) * 1.2), if k % 3 == 0 then HAZARD else RUST)
	end
	local shelf = room * CFrame.new(0, 0, -sz / 2 + 1.5)
	for _, x in { -3.5, 3.5 } do
		part(model, "ShelfPost", Vector3.new(0.4, 7, 0.4), shelf * CFrame.new(x, 3.5, 0), OLD_WOOD, Enum.Material.Wood)
	end
	for level = 1, 3 do
		part(model, "Shelf", Vector3.new(7.6, 0.3, 1.6), shelf * CFrame.new(0, level * 2, 0), OLD_WOOD, Enum.Material.WoodPlanks)
		for _ = 1, rng:NextInteger(1, 3) do
			deco(model, "Box", Vector3.new(1.2, 0.9, 1), shelf * CFrame.new(rng:NextNumber(-3, 3), level * 2 + 0.6, 0), FABRIC, Enum.Material.Cardboard)
		end
	end
end

function ROOMS.Taller(model: Model, room: CFrame, sx: number, sz: number, rng: Random)
	-- perforadora abandonada: orugas, cuerpo, cabina y broca
	local drill = room * CFrame.new(-sx / 4, 0, rng:NextNumber(-sz / 6, sz / 6)) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0)
	for _, x in { -2, 2 } do
		part(model, "DrillTrack", Vector3.new(1.4, 1.4, 7), drill * CFrame.new(x, 0.7, 0), DARK, Enum.Material.Metal)
	end
	part(model, "DrillBody", Vector3.new(4.4, 2.6, 5.5), drill * CFrame.new(0, 2.7, 0.3), HAZARD, Enum.Material.Metal)
	part(model, "DrillCab", Vector3.new(2.6, 2, 2.4), drill * CFrame.new(0.6, 5, 1.2), RUST, Enum.Material.CorrodedMetal)
	part(model, "DrillArm", Vector3.new(1.4, 1.4, 3), drill * CFrame.new(0, 2.8, -4), DARK, Enum.Material.Metal)
	part(model, "DrillBit", Vector3.new(3, 2.4, 2.4), drill * CFrame.new(0, 2.8, -6.6) * CFrame.Angles(0, math.pi / 2, 0), STEEL, Enum.Material.DiamondPlate, Enum.PartType.Cylinder)
	-- generador con tubo de escape
	local gen = room * CFrame.new(sx / 2 - 3, 0, -sz / 4)
	part(model, "Generator", Vector3.new(3, 2.4, 4), gen * CFrame.new(0, 1.2, 0), DARK, Enum.Material.Metal)
	deco(model, "GeneratorStripe", Vector3.new(3.05, 0.4, 4.05), gen * CFrame.new(0, 2, 0), HAZARD, Enum.Material.SmoothPlastic)
	deco(model, "Exhaust", Vector3.new(4, 0.6, 0.6), upright(gen * CFrame.new(0.8, 2.4, 1.2), 4, 0.3), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	-- banco de trabajo con herramientas
	local bench = room * CFrame.new(sx / 2 - 2.5, 0, sz / 4) * CFrame.Angles(0, math.pi / 2, 0)
	part(model, "Bench", Vector3.new(6, 0.4, 2.4), bench * CFrame.new(0, 3, 0), OLD_WOOD, Enum.Material.WoodPlanks)
	for _, x in { -2.6, 2.6 } do
		for _, z in { -0.9, 0.9 } do
			part(model, "BenchLeg", Vector3.new(0.3, 3, 0.3), bench * CFrame.new(x, 1.5, z), OLD_WOOD, Enum.Material.Wood)
		end
	end
	pickaxe(model, bench * CFrame.new(-1.2, 3.35, 0) * CFrame.Angles(0, 0, math.pi / 2))
	deco(model, "Toolbox", Vector3.new(1.6, 0.8, 0.8), bench * CFrame.new(1.6, 3.6, 0), Color3.fromRGB(140, 40, 34), Enum.Material.Metal)
	-- herramientas apoyadas en la pared
	local wall = room * CFrame.new(0, 0, sz / 2 - 1)
	for k = 1, 3 do
		pickaxe(model, wall * CFrame.new(-2 + k * 1.2, 1.5, 0) * CFrame.Angles(0.25, 0, 0))
	end
end

function ROOMS.Dormitorio(model: Model, room: CFrame, sx: number, sz: number, rng: Random)
	for k = 1, rng:NextInteger(2, 3) do -- literas contra la pared
		local bunk = room * CFrame.new(-sx / 2 + 2.2, 0, -sz / 2 + 4 + (k - 1) * 4.5)
		for _, x in { -1.4, 1.4 } do
			for _, z in { -3, 3 } do
				part(model, "BunkPost", Vector3.new(0.3, 6, 0.3), bunk * CFrame.new(x, 3, z) * CFrame.Angles(0, math.pi / 2, 0), OLD_WOOD, Enum.Material.Wood)
			end
		end
		for _, y in { 1.4, 4.4 } do
			part(model, "Bunk", Vector3.new(3, 0.5, 6.2), bunk * CFrame.new(0, y, 0), FABRIC, Enum.Material.Fabric)
		end
	end
	local table_ = room * CFrame.new(sx / 6, 0, 0) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
	part(model, "Table", Vector3.new(4.5, 0.3, 3), table_ * CFrame.new(0, 2.6, 0), OLD_WOOD, Enum.Material.WoodPlanks)
	for _, x in { -1.9, 1.9 } do
		for _, z in { -1.1, 1.1 } do
			part(model, "TableLeg", Vector3.new(0.3, 2.6, 0.3), table_ * CFrame.new(x, 1.3, z), OLD_WOOD, Enum.Material.Wood)
		end
	end
	for _, z in { -2.4, 2.4 } do
		part(model, "Stool", Vector3.new(1.4, 1.6, 1.4), table_ * CFrame.new(rng:NextNumber(-1, 1), 0.8, z), OLD_WOOD, Enum.Material.WoodPlanks)
	end
	deco(model, "Mug", Vector3.new(0.6, 0.5, 0.5), upright(table_ * CFrame.new(-1, 2.75, 0.4), 0.6, 0.25), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	lantern(model, table_ * CFrame.new(1, 4.95, 0), rng:NextNumber() < 0.5)
end

function ROOMS.Campamento(model: Model, room: CFrame, sx: number, sz: number, rng: Random)
	-- tienda en A
	local tent = room * CFrame.new(-sx / 4, 0, -sz / 5) * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0)
	for _, s in { -1, 1 } do
		part(model, "TentSide", Vector3.new(0.2, 4.2, 6), tent * CFrame.new(s * 1.25, 1.75, 0) * CFrame.Angles(0, 0, s * 0.6), FABRIC, Enum.Material.Fabric)
	end
	deco(model, "TentPole", Vector3.new(0.2, 0.2, 6.4), tent * CFrame.new(0, 3.5, 0), OLD_WOOD, Enum.Material.Wood)
	-- fogata apagada: piedras en anillo, troncos y ceniza
	local fire = room * CFrame.new(sx / 6, 0, sz / 8)
	deco(model, "Ash", Vector3.new(0.2, 2.6, 2.6), fire * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(36, 34, 34), Enum.Material.Sand, Enum.PartType.Cylinder)
	for k = 0, 6 do
		local a = k * math.pi * 2 / 7
		part(model, "FireStone", Vector3.one * 0.9, fire * CFrame.new(math.cos(a) * 1.6, 0.35, math.sin(a) * 1.6), STONE, Enum.Material.Slate, Enum.PartType.Ball)
	end
	for k = 0, 2 do
		deco(model, "Log", Vector3.new(2.4, 0.5, 0.5), fire * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, k * 2.1, 0.35), Color3.fromRGB(44, 34, 28), Enum.Material.Wood, Enum.PartType.Cylinder)
	end
	part(model, "Bedroll", Vector3.new(4.5, 1, 1), room * CFrame.new(sx / 4, 0.5, -sz / 4) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color3.fromRGB(70, 82, 60), Enum.Material.Fabric, Enum.PartType.Cylinder)
	part(model, "Backpack", Vector3.new(1.4, 1.8, 0.9), room * CFrame.new(-sx / 6, 0.9, sz / 4) * CFrame.Angles(0.3, rng:NextNumber(0, 3), 0), Color3.fromRGB(96, 70, 44), Enum.Material.Fabric)
	crate(model, room * CFrame.new(sx / 3, 0, sz / 5), 2.4)
	pickaxe(model, room * CFrame.new(sx / 3 + 1.8, 1.5, sz / 5) * CFrame.Angles(0, 0, 0.3))
	local stand = room * CFrame.new(-sx / 6, 0, sz / 8)
	part(model, "LanternStand", Vector3.new(0.3, 3.4, 0.3), stand * CFrame.new(0, 1.7, 0), DARK, Enum.Material.Metal)
	lantern(model, stand * CFrame.new(0.3, 3.4, 0), rng:NextNumber() < 0.6)
end

-- Sala: entibado en las esquinas con vigas, y los muebles de su tipo.
local function furnishRoom(model: Model, room, central: boolean, mine, rng: Random)
	local floor = floorAt(room.center)
	local frame = CFrame.new(floor) * CFrame.Angles(0, room.yaw, 0)
	local sx, sz, h = room.size.X, room.size.Z, room.size.Y
	if room.kind ~= "Campamento" then
		local px, pz = sx / 2 - 1.2, sz / 2 - 1.2
		for _, x in { -px, px } do
			for _, z in { -pz, pz } do
				part(model, "RoomPost", Vector3.new(1, h - 1.4, 1), frame * CFrame.new(x, (h - 1.4) / 2, z), WOOD, Enum.Material.Wood)
			end
			deco(model, "RoomBeam", Vector3.new(1, 1, sz - 1.4), frame * CFrame.new(x, h - 1.4, 0), WOOD, Enum.Material.Wood)
		end
	end
	ROOMS[room.kind](model, frame, sx, sz, rng)
	if central then
		-- letrero oxidado con el sector
		local post = frame * CFrame.new(sx / 2 - 4, 0, -sz / 2 + 4) * CFrame.Angles(0, math.rad(45), 0)
		part(model, "SignPost", Vector3.new(0.4, 5, 0.4), post * CFrame.new(0, 2.5, 0), OLD_WOOD, Enum.Material.Wood)
		SignKit.Build(model, "Sign", post * CFrame.new(0, 4.7, -0.35), 4.8, 2.2, {
			title = `SECTOR {mine.layer}-{mine.id}`, sub = "MINA ABANDONADA", style = "rust",
			accent = Color3.fromRGB(200, 130, 70), titleColor = Color3.fromRGB(235, 215, 175), depth = 0.25,
		})
	end
end

local function build(mine): Model
	local rng = Random.new(mine.seed)
	local model = Instance.new("Model")
	model.Name = `Mine{mine.id}`
	for k, room in mine.rooms do
		furnishRoom(model, room, k == 1 and not mine.camp and not mine.gallery, mine, rng)
	end
	for _, t in mine.tunnels do
		furnishTunnel(model, mine, t, rng)
	end
	if mine.shaft then -- escalera (se trepa) desde el suelo de la sala hasta arriba del pozo
		local height = math.floor((mine.shaft.height + 13) / 2) * 2
		local floor = floorAt(mine.center)
		local ladder = Instance.new("TrussPart")
		ladder.Name, ladder.Anchored, ladder.CanTouch = "Ladder", true, false
		ladder.Style = Enum.Style.NoSupports
		ladder.Size = Vector3.new(2, height, 2)
		ladder.CFrame = CFrame.new(floor + Vector3.new(2.4, height / 2, 0))
		ladder.Color, ladder.Material = RUST, Enum.Material.CorrodedMetal
		ladder.Parent = model
	end
	model.Parent = folder
	return model
end

return {
	Start = function()
		folder = Instance.new("Folder")
		folder.Name = "Mines"
		folder.Parent = workspace
		local built: { [any]: Model } = {}
		while true do
			task.wait(0.5)
			local roots = {}
			for _, p in Players:GetPlayers() do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if root then table.insert(roots, root.Position) end
			end
			local builds = 0
			for _, mine in World.Mines do
				if mine.carved then
					local nearest = math.huge
					for _, pos in roots do
						nearest = math.min(nearest, (pos - mine.center).Magnitude)
					end
					local model = built[mine]
					if not model and nearest < ACTIVATE and builds < BUILDS_PER_TICK then
						builds += 1
						local ok, result = pcall(build, mine)
						if ok then
							built[mine] = result
						else
							warn(`[Mines] no se pudo amueblar la mina {mine.id}: {result}`)
							mine.carved = false -- no reintentar
						end
					elseif model and nearest > DEACTIVATE then
						model:Destroy()
						built[mine] = nil
					end
				end
			end
		end
	end,
}
