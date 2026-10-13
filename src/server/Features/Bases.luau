-- Bases de los jugadores en la cueva de la base (spawn): un anillo de bahías industriales abiertas hacia la plaza
-- central (libre para las tiendas), sin tapar el pasaje hacia la puerta de arco. A cada jugador que entra le toca una
-- base libre (atributo BaseIndex); aparece y reaparece en ella, y al salir se libera.
--
-- Cada base (coordenadas locales: origen en el centro del piso, -Z hacia la plaza):
--  · Andén de carritos a la izquierda: rieles desde el frente hasta un tope; ahí llegan los carritos (Carts.luau) y el
--    dueño puede "Descargar minerales" a mano. Encima, una tolva con su rampa.
--  · Cinta transportadora por el fondo hasta una tubería que reparte el mineral en 4 silos (uno por rareza), con una
--    ventana cuya barra de neón se llena según lo guardado.
--  · Panel de estadísticas en la pared del fondo; mural de exhibición (5 pedestales) en el lado izquierdo; grúa
--    pórtico, techo sobre la mitad de atrás con lámparas, y utilería.
--
-- Datos (atributos del jugador; solo en memoria hasta que haya DataStore):
--  Stored_<Rareza> (lo guardado en la base), Stat_Carts (envíos), Stat_Captured (minerales recogidos), Stat_DeepestLayer.
-- API: Bases.Get(player), Bases.All(), Bases.Deposit(player, counts, viaCart). workspace.BasesReady = true al terminar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Bases)
local WorldConfig = require(ReplicatedStorage.Shared.Config.World)
local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)
local Inventory = require(script.Parent.Inventory)

local RARITIES = { "Comun", "Raro", "Epico", "Legendario" }
local RARITY_NAMES = { Comun = "Común", Raro = "Raro", Epico = "Épico", Legendario = "Legendario" }

local DARK = Color3.fromRGB(48, 50, 56)
local STEEL = Color3.fromRGB(96, 100, 108)
local RUST = Color3.fromRGB(110, 62, 40)
local HAZARD = Color3.fromRGB(230, 180, 40)
local RUBBER = Color3.fromRGB(24, 24, 26)
local WOOD = Color3.fromRGB(120, 88, 56)
local LAMP = Color3.fromRGB(255, 214, 160)
local RAIL = Color3.fromRGB(96, 92, 90)

local cave = WorldConfig.SpawnCave
local CAVE_FLOOR = cave.Center.Y - cave.Height / 2
local CENTER = Vector3.new(cave.Center.X, CAVE_FLOOR, cave.Center.Z)

local W, D, H = Config.Width, Config.Depth, Config.WallHeight
local FT = 0.6 -- alto del piso de la base
local LANE = -W / 4 -- eje x del andén de carritos
local DOCK_Z = 6 -- donde se detiene el carrito
local SILO_MAX = 10 -- alto de la barra de llenado de un silo

export type Base = {
	index: number,
	frame: CFrame, -- centro del piso, -Z hacia la plaza
	spawn: CFrame,
	laneEntry: Vector3, -- donde la vía de la cueva entra al andén
	dock: Vector3, -- donde se detiene el carrito
	color: Color3,
	owner: Player?,
	board: { [string]: TextLabel },
	silos: { [string]: { fill: Part, label: TextLabel } },
	prompt: ProximityPrompt,
	ownerLabel: TextLabel,
}

local bases: { Base } = {}
local folder: Folder

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanTouch = name, true, false
	p.Size, p.CFrame, p.Color, p.Material = size, cframe, color, material
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- decoración pequeña: sin colisión, sin rayos, sin sombra
local function deco(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = part(parent, name, size, cframe, color, material, shape)
	p.CanCollide, p.CanQuery, p.CastShadow = false, false, false
	return p
end

local function surfaceText(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = color, range, brightness, false
	l.Parent = parent
end

-- cilindro vertical (los cilindros de Roblox tienen el eje en X)
local function column(parent: Instance, name: string, at: CFrame, height: number, radius: number, color: Color3, material: Enum.Material): Part
	return part(parent, name, Vector3.new(height, radius * 2, radius * 2), at * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder)
end

-- Panel de estadísticas: título y filas (texto actualizable).
local function buildBoard(model: Model, at: CFrame, color: Color3): { [string]: TextLabel }
	local screen = part(model, "StatsScreen", Vector3.new(16, 8, 0.4), at, DARK, Enum.Material.SmoothPlastic)
	local frame = deco(model, "StatsFrame", Vector3.new(16.8, 8.8, 0.3), at * CFrame.new(0, 0, 0.15), color, Enum.Material.Neon)
	frame.Transparency = 0.2
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.PixelsPerStud = 30
	local list = Instance.new("Frame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
	list.BorderSizePixel = 0
	list.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0.04, 0), UDim.new(0.04, 0)
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0.05, 0), UDim.new(0.05, 0)
	padding.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.012, 0)
	layout.Parent = list

	local rows = {}
	local order = 0
	local function row(key: string, height: number, textColor: Color3, font: Enum.Font, align: Enum.TextXAlignment?)
		order += 1
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.fromScale(1, height)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextScaled = true
		label.TextColor3 = textColor
		label.TextXAlignment = align or Enum.TextXAlignment.Left
		label.Text = ""
		label.Parent = list
		rows[key] = label
	end
	row("Title", 0.14, color, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	row("StoreHeader", 0.08, HAZARD, Enum.Font.GothamBold)
	for _, rarity in RARITIES do
		row(rarity, 0.085, Minerals[rarity].Color, Enum.Font.GothamBold)
	end
	row("Value", 0.09, Color3.fromRGB(120, 255, 140), Enum.Font.GothamBlack)
	row("Carts", 0.075, Color3.new(1, 1, 1), Enum.Font.Gotham)
	row("Captured", 0.075, Color3.new(1, 1, 1), Enum.Font.Gotham)
	row("Deepest", 0.075, Color3.new(1, 1, 1), Enum.Font.Gotham)
	gui.Parent = screen
	return rows
end

local function buildBase(index: number, frame: CFrame): Base
	local color = Config.Colors[(index - 1) % #Config.Colors + 1]
	local model = Instance.new("Model")
	model.Name = `Base{index}`
	model.Parent = folder
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	-- piso, bordes de neón y franja de advertencia en la entrada
	local floor = part(model, "Floor", Vector3.new(W, FT, D), at(0, FT / 2, 0), DARK, Enum.Material.DiamondPlate)
	deco(model, "EdgeFront", Vector3.new(W, 0.2, 0.5), at(0, FT + 0.1, -D / 2), color, Enum.Material.Neon)
	for _, s in { -1, 1 } do
		deco(model, "EdgeSide", Vector3.new(0.5, 0.2, D), at(s * W / 2, FT + 0.1, 0), color, Enum.Material.Neon)
	end
	for k = 0, 9 do
		local x = -W / 2 + W / 20 + k * W / 10
		deco(model, "Hazard", Vector3.new(W / 10, 0.06, 1.2), at(x, FT + 0.03, -D / 2 + 1.4), if k % 2 == 0 then HAZARD else RUBBER, Enum.Material.SmoothPlastic)
	end

	-- paredes con nervaduras, pilares de la entrada, viga, letrero y techo sobre la mitad de atrás
	part(model, "BackWall", Vector3.new(W, H, 1.5), at(0, H / 2, D / 2), STEEL, Enum.Material.Metal)
	for x = -W / 2 + 3, W / 2 - 3, 6 do
		part(model, "Rib", Vector3.new(1, H, 0.8), at(x, H / 2, D / 2 - 1.1), RUST, Enum.Material.CorrodedMetal)
	end
	for _, s in { -1, 1 } do
		part(model, "SideWall", Vector3.new(1.5, H, D), at(s * W / 2, H / 2, 0), STEEL, Enum.Material.Metal)
		part(model, "Pillar", Vector3.new(2.2, H + 1, 2.2), at(s * W / 2, (H + 1) / 2, -D / 2), RUST, Enum.Material.CorrodedMetal)
	end
	local beam = part(model, "TopBeam", Vector3.new(W + 2.2, 1.6, 2.2), at(0, H + 0.8, -D / 2), RUST, Enum.Material.CorrodedMetal)
	local beamLight = deco(model, "BeamLight", Vector3.new(W - 2, 0.3, 0.3), beam.CFrame * CFrame.new(0, -0.95, 0), color, Enum.Material.Neon)
	light(beamLight, color, 18, 0.8)
	local sign = part(model, "Sign", Vector3.new(W - 6, 3, 0.4), at(0, H + 3.2, -D / 2), DARK, Enum.Material.Metal)
	local ownerLabel = surfaceText(sign, Enum.NormalId.Front, "LIBRE", color)
	local roofDepth = D * 0.55
	part(model, "Roof", Vector3.new(W, 0.8, roofDepth), at(0, H + 0.4, D / 2 - roofDepth / 2), STEEL, Enum.Material.Metal)
	deco(model, "RoofEdge", Vector3.new(W, 0.3, 0.3), at(0, H - 0.15, D / 2 - roofDepth), color, Enum.Material.Neon)
	for _, x in { -W / 4, W / 4 } do -- lámparas colgando del techo
		deco(model, "LampChain", Vector3.new(0.15, 2.6, 0.15), at(x, H - 1.3, D / 2 - roofDepth / 2), DARK, Enum.Material.Metal)
		local bulb = deco(model, "Lamp", Vector3.new(1.4, 1.4, 1.4), at(x, H - 3, D / 2 - roofDepth / 2), LAMP, Enum.Material.Neon, Enum.PartType.Ball)
		light(bulb, LAMP, 26, 1.3)
	end

	-- andén de carritos: rieles con durmientes, líneas del carril y tope con luz roja
	local railLen = DOCK_Z + D / 2
	for _, s in { -1, 1 } do
		deco(model, "DockRail", Vector3.new(0.3, 0.3, railLen), at(LANE + s * 1.6, FT + 0.45, -D / 2 + railLen / 2), RAIL, Enum.Material.Metal)
		deco(model, "LaneLine", Vector3.new(0.3, 0.05, railLen), at(LANE + s * 2.8, FT + 0.03, -D / 2 + railLen / 2), HAZARD, Enum.Material.SmoothPlastic)
	end
	for z = -D / 2 + 1, DOCK_Z, 3 do
		deco(model, "DockSleeper", Vector3.new(4.6, 0.3, 0.8), at(LANE, FT + 0.15, z), WOOD, Enum.Material.WoodPlanks)
	end
	local buffer = part(model, "BufferStop", Vector3.new(5, 2.2, 1.2), at(LANE, FT + 1.1, DOCK_Z + 2), RUST, Enum.Material.CorrodedMetal)
	for _, s in { -1, 1 } do
		deco(model, "BufferStripe", Vector3.new(1, 2.3, 1.3), buffer.CFrame * CFrame.new(s * 1.6, 0, 0), HAZARD, Enum.Material.SmoothPlastic)
	end
	local stopLight = deco(model, "BufferLight", Vector3.one * 0.9, buffer.CFrame * CFrame.new(0, 1.6, 0), Color3.fromRGB(255, 70, 50), Enum.Material.Neon, Enum.PartType.Ball)
	light(stopLight, stopLight.Color, 10, 1)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Descargar minerales"
	prompt.ObjectText = "Andén"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = buffer

	-- tolva sobre el andén y rampa hacia la cinta
	for _, cx in { -2.6, 2.6 } do
		for _, cz in { 1.4, 6.6 } do
			part(model, "HopperLeg", Vector3.new(0.6, 9, 0.6), at(LANE + cx, FT + 4.5, cz + 4), DARK, Enum.Material.Metal)
		end
	end
	part(model, "Hopper", Vector3.new(6, 3, 6), at(LANE, FT + 10, 8), STEEL, Enum.Material.Metal)
	part(model, "HopperNeck", Vector3.new(3, 2, 3), at(LANE, FT + 7.8, 8), RUST, Enum.Material.CorrodedMetal)
	local chuteFrom, chuteTo = (at(LANE, FT + 6.8, 8)).Position, (at(LANE, FT + 3.4, 13)).Position
	part(model, "Chute", Vector3.new(2.6, 0.4, (chuteTo - chuteFrom).Magnitude), CFrame.lookAt((chuteFrom + chuteTo) / 2, chuteTo), STEEL, Enum.Material.Metal)

	-- cinta transportadora por el fondo, con patas y flechas de neón
	local beltStart, beltEnd = LANE, 1
	local beltLen = beltEnd - beltStart
	part(model, "Belt", Vector3.new(beltLen, 0.4, 3), at((beltStart + beltEnd) / 2, FT + 2.8, 13), RUBBER, Enum.Material.Fabric)
	for _, s in { -1, 1 } do
		part(model, "BeltRail", Vector3.new(beltLen, 0.6, 0.3), at((beltStart + beltEnd) / 2, FT + 3, 13 + s * 1.6), HAZARD, Enum.Material.SmoothPlastic)
	end
	for x = beltStart + 1.5, beltEnd - 1, 4 do
		part(model, "BeltLeg", Vector3.new(0.5, 2.6, 2.8), at(x, FT + 1.3, 13), DARK, Enum.Material.Metal)
		deco(model, "BeltArrow", Vector3.new(0.8, 0.05, 0.8), at(x + 2, FT + 3.03, 13) * CFrame.Angles(0, math.rad(45), 0), color, Enum.Material.Neon)
	end

	-- silos (uno por rareza) con ventana y barra de llenado; tubería que los alimenta desde la cinta
	local silos = {}
	for k, rarity in RARITIES do
		local x = 4.5 + (k - 1) * 4.5
		local base = at(x, FT, 12)
		column(model, "Silo", base, 11, 2, STEEL, Enum.Material.Metal)
		part(model, "SiloCap", Vector3.one * 4, base * CFrame.new(0, 11, 0), STEEL, Enum.Material.Metal, Enum.PartType.Ball)
		for _, y in { 2.5, 8.5 } do
			deco(model, "SiloBand", Vector3.new(0.6, 4.2, 4.2), base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
		end
		local fill = deco(model, "SiloFill", Vector3.new(0.8, 0.1, 0.2), base * CFrame.new(0, 0.6, -1.95), Minerals[rarity].Color, Enum.Material.Neon)
		local window = deco(model, "SiloWindow", Vector3.new(1.1, SILO_MAX, 0.15), base * CFrame.new(0, 0.5 + SILO_MAX / 2, -2.08), Color3.fromRGB(180, 200, 220), Enum.Material.Glass)
		window.Transparency = 0.55
		local plate = part(model, "SiloPlate", Vector3.new(4, 1.4, 0.3), base * CFrame.new(0, 0.9, -2.6), DARK, Enum.Material.Metal)
		local label = surfaceText(plate, Enum.NormalId.Front, "", Minerals[rarity].Color, Enum.Font.GothamBold)
		silos[rarity] = { fill = fill, label = label, base = base }
		-- bajante desde la tubería
		deco(model, "SiloFeed", Vector3.new(1.5, 0.7, 0.7), at(x, FT + 12.8, 12) * CFrame.Angles(0, 0, math.pi / 2), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	end
	local manifoldFrom, manifoldTo = at(beltEnd, FT + 13.4, 12).Position, at(4.5 + 3 * 4.5, FT + 13.4, 12).Position
	deco(model, "Manifold", Vector3.new((manifoldTo - manifoldFrom).Magnitude, 0.9, 0.9), CFrame.lookAt((manifoldFrom + manifoldTo) / 2, manifoldTo) * CFrame.Angles(0, math.pi / 2, 0), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	deco(model, "Riser", Vector3.new(10.6, 0.9, 0.9), at(beltEnd, FT + 8.1, 12) * CFrame.Angles(0, 0, math.pi / 2), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)

	-- panel de estadísticas en la pared del fondo
	local board = buildBoard(model, at(-3, FT + 10.5, D / 2 - 1.9), color) -- delante de las nervaduras, mirando a la plaza

	-- mural de exhibición: pedestales en el lado izquierdo (los usará Mural)
	for slot = 1, Config.MuralSlots do
		local z = -D / 2 + 5 + (slot - 1) * 5
		local pedestal = part(model, "MuralSlot", Vector3.new(2.4, 3, 2.4), at(-W / 2 + 5.5, FT + 1.5, z), DARK, Enum.Material.Metal)
		pedestal:SetAttribute("Slot", slot)
		deco(model, "MuralSlotLight", Vector3.new(2, 0.2, 2), pedestal.CFrame * CFrame.new(0, 1.6, 0), color, Enum.Material.Neon)
	end

	-- grúa pórtico con gancho sobre el andén
	for _, s in { -1, 1 } do
		part(model, "CraneColumn", Vector3.new(1.2, H - 1, 1.2), at(s * (W / 2 - 1.4), (H - 1) / 2, -3), HAZARD, Enum.Material.Metal)
	end
	part(model, "CraneBeam", Vector3.new(W - 2, 1.2, 1.4), at(0, H - 1.5, -3), HAZARD, Enum.Material.Metal)
	part(model, "CraneTrolley", Vector3.new(2.4, 1, 2), at(LANE, H - 2.6, -3), DARK, Enum.Material.Metal)
	deco(model, "CraneCable", Vector3.new(0.15, 5, 0.15), at(LANE, H - 5.6, -3), RUBBER, Enum.Material.Metal)
	deco(model, "CraneHook", Vector3.new(0.8, 1.2, 0.4), at(LANE, H - 8.7, -3), STEEL, Enum.Material.Metal)

	-- utilería: cajas, barriles y una terminal
	for k, offset in { Vector3.new(15, 1.5, -12), Vector3.new(18, 1.5, -12), Vector3.new(16.5, 4.5, -12) } do
		part(model, "Crate", Vector3.new(3, 3, 3), at(offset.X, FT + offset.Y - 0.6 + 0.6, offset.Z) * CFrame.Angles(0, math.rad(k * 7), 0), WOOD, Enum.Material.WoodPlanks)
	end
	for k, x in { 14, 16.2, 18.4 } do
		column(model, "Barrel", at(x, FT, -6 + (k % 2) * 1.5), 3.2, 1.1, if k == 2 then HAZARD else RUST, Enum.Material.CorrodedMetal)
	end
	part(model, "Terminal", Vector3.new(3, 3.2, 1.6), at(8, FT + 1.6, -13), DARK, Enum.Material.Metal)
	local terminalScreen = deco(model, "TerminalScreen", Vector3.new(2.4, 1.4, 0.1), at(8, FT + 2.6, -13.85), color, Enum.Material.Neon)
	surfaceText(terminalScreen, Enum.NormalId.Front, "TERMINAL", Color3.fromRGB(10, 12, 16))

	-- marca de spawn
	deco(model, "Spawn", Vector3.new(4, 0.1, 4), at(0, FT + 0.05, -9), color, Enum.Material.Neon).Transparency = 0.4

	model.PrimaryPart = floor
	return {
		index = index,
		frame = frame,
		spawn = at(0, FT + 3, -9),
		laneEntry = at(LANE, FT, -D / 2 - 3).Position,
		dock = at(LANE, FT, DOCK_Z).Position,
		color = color,
		owner = nil,
		board = board,
		silos = silos,
		prompt = prompt,
		ownerLabel = ownerLabel,
	}
end

-- Pinta el panel y los silos de una base con los datos de su dueño.
local function refresh(base: Base)
	local player = base.owner
	local board = base.board
	board.Title.Text = if player then `BASE · {player.DisplayName}` else "BASE LIBRE"
	board.StoreHeader.Text = "ALMACÉN"
	local value = 0
	for _, rarity in RARITIES do
		local stored = if player then player:GetAttribute("Stored_" .. rarity) or 0 else 0
		value += stored * Minerals[rarity].Value
		board[rarity].Text = `  {RARITY_NAMES[rarity]}: {stored}`
		local silo = base.silos[rarity]
		-- barra de llenado en escala logarítmica: 1 = un poco, 1000 = lleno
		local level = math.clamp(math.log10(stored + 1) / 3, 0, 1)
		local height = math.max(SILO_MAX * level, 0.1)
		silo.fill.Size = Vector3.new(0.8, height, 0.2)
		silo.fill.CFrame = silo.base * CFrame.new(0, 0.5 + height / 2, -1.95)
		silo.label.Text = `{RARITY_NAMES[rarity]} {stored}`
	end
	board.Value.Text = `VALOR TOTAL: {value}`
	local carts = if player then player:GetAttribute("Stat_Carts") or 0 else 0
	local captured = if player then player:GetAttribute("Stat_Captured") or 0 else 0
	local deepest = if player then player:GetAttribute("Stat_DeepestLayer") or 0 else 0
	board.Carts.Text = `Envíos en carrito: {carts}`
	board.Captured.Text = `Minerales capturados: {captured}`
	local layer = WorldConfig.Layers[deepest]
	board.Deepest.Text = if layer then `Capa más profunda: {deepest} · {layer.Name}` else "Capa más profunda: —"
end

local function baseOf(player: Player): Base?
	local index = player:GetAttribute("BaseIndex")
	return if index then bases[index] else nil
end

local Bases = {}

function Bases.Get(player: Player): Base?
	return baseOf(player)
end

function Bases.All(): { Base }
	return bases
end

-- Suma minerales al almacén de la base del jugador. viaCart = llegó en carrito (cuenta un envío).
function Bases.Deposit(player: Player, counts: { [string]: number }, viaCart: boolean)
	for rarity, n in counts do
		if n > 0 then
			player:SetAttribute("Stored_" .. rarity, (player:GetAttribute("Stored_" .. rarity) or 0) + n)
		end
	end
	if viaCart then
		player:SetAttribute("Stat_Carts", (player:GetAttribute("Stat_Carts") or 0) + 1)
	end
end

-- Saca del inventario todo lo que lleva el jugador; devuelve { rareza = cantidad } y el total.
function Bases.TakeInventory(player: Player): ({ [string]: number }, number)
	local counts, total = {}, 0
	for _, rarity in RARITIES do
		local n = Inventory.Count(player, rarity)
		if n > 0 then
			Inventory.Add(player, rarity, -n)
			counts[rarity] = n
			total += n
		end
	end
	return counts, total
end

local function buildAll()
	folder = Instance.new("Folder")
	folder.Name = "Bases"
	folder.Parent = workspace
	-- el pasaje hacia la cueva del foso queda libre
	local toHub = Vector3.new(WorldConfig.Hub.Center.X - cave.Center.X, 0, WorldConfig.Hub.Center.Z - cave.Center.Z).Unit
	local gapAngle = math.atan2(toHub.Z, toHub.X)
	local gap = math.rad(Config.PassageGap)
	local span = math.pi * 2 - gap
	for i = 1, Config.Count do
		local a = gapAngle + gap / 2 + span * (i - 0.5) / Config.Count
		local pos = CENTER + Vector3.new(math.cos(a), 0, math.sin(a)) * Config.RingRadius
		local frame = CFrame.lookAt(pos, Vector3.new(CENTER.X, pos.Y, CENTER.Z)) -- -Z hacia la plaza
		local base = buildBase(i, frame)
		table.insert(bases, base)
		refresh(base)
		base.prompt.Triggered:Connect(function(player)
			if base.owner ~= player then return end -- solo el dueño descarga en su base
			local counts, total = Bases.TakeInventory(player)
			if total > 0 then
				Bases.Deposit(player, counts, false)
			end
		end)
	end
end

local function assign(player: Player)
	for _, base in bases do
		if not base.owner then
			base.owner = player
			base.ownerLabel.Text = player.DisplayName
			player:SetAttribute("BaseIndex", base.index)
			for _, rarity in RARITIES do
				player:SetAttribute("Stored_" .. rarity, player:GetAttribute("Stored_" .. rarity) or 0)
			end
			refresh(base)
			return
		end
	end
	warn(`[Bases] no hay base libre para {player.Name}; aparecerá en el spawn general`)
end

local function release(player: Player)
	for _, base in bases do
		if base.owner == player then
			base.owner = nil
			base.ownerLabel.Text = "LIBRE"
			refresh(base)
		end
	end
end

-- lleva al personaje a su base al aparecer (con streaming, primero se pide cargar esa zona)
local function moveToBase(player: Player, character: Model)
	local base = baseOf(player)
	if not base then return end
	pcall(function() player:RequestStreamAroundAsync(base.spawn.Position) end)
	character:WaitForChild("HumanoidRootPart")
	task.wait() -- deja que Roblox termine de colocarlo en el spawn general
	character:PivotTo(base.spawn)
end

-- estadísticas: minerales capturados (lo que entra al inventario) y capa más profunda alcanzada
local function trackStats(player: Player)
	local last = {}
	for _, rarity in RARITIES do last[rarity] = player:GetAttribute("Inv_" .. rarity) or 0 end
	player.AttributeChanged:Connect(function(name)
		local rarity = string.match(name, "^Inv_(.+)$")
		if rarity and last[rarity] then
			local now = player:GetAttribute(name) or 0
			if now > last[rarity] then
				player:SetAttribute("Stat_Captured", (player:GetAttribute("Stat_Captured") or 0) + now - last[rarity])
			end
			last[rarity] = now
		end
		local base = baseOf(player)
		if base and base.owner == player and (string.find(name, "^Stored_") or string.find(name, "^Stat_")) then
			refresh(base)
		end
	end)
end

local function layerAt(depth: number): number
	if depth <= 0 then return 0 end
	for i, layer in WorldConfig.Layers do
		if depth <= layer.MaxDepth then return i end
	end
	return #WorldConfig.Layers
end

Bases.Start = function()
	local function onPlayer(player: Player)
		trackStats(player)
		player.CharacterAdded:Connect(function(character) moveToBase(player, character) end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do onPlayer(p) end

	-- las bases se arman cuando la cueva ya está tallada
	while workspace:GetAttribute("WorldReady") ~= true do
		task.wait(0.2)
	end
	local ok, err = pcall(buildAll)
	if not ok then
		warn(`[Bases] no se pudieron construir las bases: {err}`)
		return
	end
	for _, p in Players:GetPlayers() do
		assign(p)
		if p.Character then task.spawn(moveToBase, p, p.Character) end
	end
	Players.PlayerAdded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
	workspace:SetAttribute("BasesReady", true)

	-- capa más profunda: la cuenta el servidor, para que no se pueda falsear
	while true do
		task.wait(1)
		for _, p in Players:GetPlayers() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local layer = layerAt(-root.Position.Y)
				if layer > (p:GetAttribute("Stat_DeepestLayer") or 0) then
					p:SetAttribute("Stat_DeepestLayer", layer)
				end
			end
		end
	end
end

return Bases
