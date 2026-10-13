-- Bases de los jugadores: cada una es una cueva propia alrededor de la cueva del foso (disposición en shared/BaseLayout,
-- la talla World), unida por un pasaje. A cada jugador que entra le toca una libre (atributo BaseIndex); aparece y
-- reaparece en ella, y al salir se libera.
--
-- Dentro de cada cueva-base (coordenadas locales: origen en el centro del piso, -Z hacia la boca del pasaje; quien entra
-- mira hacia +Z, así que su izquierda es +X y su derecha -X):
--  · Arcos con el nombre del dueño en las dos bocas del pasaje.
--  · Derecha: andén de carritos (los envíos de las estaciones de los hubs llegan directo al almacén; aquí el dueño
--    puede "Descargar minerales" a mano), tolva, grúa y cinta hacia el almacén; mural de exhibición (5 pedestales).
--  · Izquierda: panel grande de estadísticas mirando hacia la entrada.
--  · Al fondo, la nave de almacén: un silo por cada tipo de mineral de Config/Minerals, en filas (sirve para ~100 tipos),
--    con una barra de neón que se llena según lo guardado y una placa con nombre y cantidad.
--
-- Datos (atributos del jugador; solo en memoria hasta que haya DataStore): Stored_<Mineral>, Stat_Carts, Stat_Captured,
-- Stat_DeepestLayer. API: Bases.Get(player), Bases.All(), Bases.Deposit(player, counts, viaCart),
-- Bases.TakeInventory(player). Pone workspace.BasesReady = true al terminar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseLayout = require(ReplicatedStorage.Shared.BaseLayout)
local WorldConfig = require(ReplicatedStorage.Shared.Config.World)
local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)
local Inventory = require(script.Parent.Inventory)

local Config = BaseLayout.Config

-- tipos de mineral, del más barato al más valioso (el almacén y el panel salen de esta lista)
local TYPES = {}
for key in Minerals do table.insert(TYPES, key) end
table.sort(TYPES, function(a, b) return (Minerals[a].Value or 0) < (Minerals[b].Value or 0) end)
local NAMES = { Comun = "Común", Epico = "Épico" } -- nombres con tilde; los demás usan Minerals[key].Name o la clave
local function displayName(key: string): string
	return Minerals[key].Name or NAMES[key] or key
end

local DARK = Color3.fromRGB(48, 50, 56)
local STEEL = Color3.fromRGB(96, 100, 108)
local RUST = Color3.fromRGB(110, 62, 40)
local HAZARD = Color3.fromRGB(230, 180, 40)
local RUBBER = Color3.fromRGB(24, 24, 26)
local WOOD = Color3.fromRGB(120, 88, 56)
local LAMP = Color3.fromRGB(255, 214, 160)
local RAIL = Color3.fromRGB(96, 92, 90)

local R = Config.CaveRadius
local LANE_X = -8 -- eje del andén y de su vía (a la derecha de quien entra)
local DOCK_Z = -95 -- donde se detiene el carrito
local HALL_Z = -28 -- primera fila del almacén
local SILO_H = 8
local SILO_FILL = 6.5 -- alto máximo de la barra de llenado

export type Base = {
	index: number,
	frame: CFrame, -- centro del piso de la cueva-base, -Z hacia la boca del pasaje
	spawn: CFrame,
	passageStart: Vector3, -- vía del andén en la boca del pasaje del lado de la cueva del foso
	laneEntry: Vector3, -- vía del andén en la boca del pasaje del lado de la cueva-base
	dock: Vector3, -- donde se detiene el carrito
	color: Color3,
	owner: Player?,
	board: { [string]: TextLabel },
	silos: { [string]: { fill: Part, label: TextLabel, base: CFrame } },
	prompt: ProximityPrompt,
	ownerLabels: { TextLabel },
}

local bases: { Base } = {}
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

-- decoración: sin colisión, sin rayos, sin sombra
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

-- Arco de entrada: pilares con franjas, arco de metal con neón por dentro, clave y letrero (frente = nombre del dueño,
-- dorso = `backText`). `at` está a ras del piso, mirando hacia quien llega (su -Z es el frente del letrero).
local function arch(model: Model, at: CFrame, color: Color3, backText: string): TextLabel
	local width, height = Config.PassageWidth, Config.PassageHeight
	local half = width / 2 + 2.5
	for _, s in { -1, 1 } do
		part(model, "ArchPillar", Vector3.new(5, height, 7), at * CFrame.new(s * half, height / 2, 0), DARK, Enum.Material.Metal)
		for band = 1, 3 do
			deco(model, "ArchStripe", Vector3.new(5.2, 1.2, 7.2), at * CFrame.new(s * half, band * 4, 0), if band % 2 == 0 then DARK else HAZARD, Enum.Material.SmoothPlastic)
		end
	end
	local center = at * CFrame.new(0, height, 0)
	local segments = 14
	for k = 0, segments - 1 do
		local t = (k + 0.5) / segments * math.pi
		local length = half * math.pi / segments + 0.6
		-- cada tramo gira alrededor del centro del arco, de un pilar al otro
		local turn = center * CFrame.Angles(0, 0, t - math.pi / 2)
		part(model, "Arch", Vector3.new(length, 5, 7), turn * CFrame.new(0, half, 0), DARK, Enum.Material.Metal)
		local glow = deco(model, "ArchLight", Vector3.new(length, 0.6, 1.6), turn * CFrame.new(0, half - 2.8, 0), color, Enum.Material.Neon)
		if k % 4 == 1 then light(glow, color, 20, 1) end
	end
	part(model, "Keystone", Vector3.new(6, 6, 8), center * CFrame.new(0, half + 1, 0), RUST, Enum.Material.CorrodedMetal)
	local sign = part(model, "ArchSign", Vector3.new(width, 4, 1), center * CFrame.new(0, half + 7, 0), DARK, Enum.Material.Metal)
	surfaceText(sign, Enum.NormalId.Back, backText, HAZARD)
	return surfaceText(sign, Enum.NormalId.Front, "LIBRE", color)
end

-- Panel de estadísticas sobre dos patas (frente = -Z de `at`).
local function buildBoard(model: Model, at: CFrame, color: Color3): { [string]: TextLabel }
	local w, h = 22, 11
	for _, s in { -1, 1 } do
		part(model, "BoardLeg", Vector3.new(1, 6, 1), at * CFrame.new(s * (w / 2 - 2), -h / 2 - 3, 0.6), DARK, Enum.Material.Metal)
	end
	local screen = part(model, "StatsScreen", Vector3.new(w, h, 0.5), at, DARK, Enum.Material.SmoothPlastic)
	local frame = deco(model, "StatsFrame", Vector3.new(w + 0.8, h + 0.8, 0.3), at * CFrame.new(0, 0, 0.2), color, Enum.Material.Neon)
	frame.Transparency = 0.2
	light(frame, color, 18, 0.6)
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
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0.05, 0), UDim.new(0.05, 0)
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0.05, 0), UDim.new(0.05, 0)
	padding.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.015, 0)
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
	row("Title", 0.15, color, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	row("Total", 0.1, Color3.new(1, 1, 1), Enum.Font.GothamBold)
	row("Value", 0.11, Color3.fromRGB(120, 255, 140), Enum.Font.GothamBlack)
	row("Types", 0.09, HAZARD, Enum.Font.GothamBold)
	row("Top", 0.09, Color3.new(1, 1, 1), Enum.Font.Gotham)
	row("Carts", 0.09, Color3.new(1, 1, 1), Enum.Font.Gotham)
	row("Captured", 0.09, Color3.new(1, 1, 1), Enum.Font.Gotham)
	row("Deepest", 0.09, Color3.new(1, 1, 1), Enum.Font.Gotham)
	gui.Parent = screen
	return rows
end

-- Lámpara colgando del techo de la cueva (la cadena se mide con un rayo).
local function hangingLamp(model: Model, floor: Vector3)
	local base = floor + Vector3.yAxis * 30
	local hit = workspace:Raycast(base, Vector3.yAxis * 120, terrainOnly)
	local length = math.max((if hit then hit.Position.Y else base.Y + 20) - base.Y, 1)
	deco(model, "LampChain", Vector3.new(0.15, length, 0.15), CFrame.new(base + Vector3.yAxis * length / 2), DARK, Enum.Material.Metal)
	deco(model, "Lamp", Vector3.new(2, 3, 3), CFrame.new(base) * CFrame.Angles(0, 0, math.pi / 2), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	local bulb = deco(model, "LampBulb", Vector3.one * 1.6, CFrame.new(base - Vector3.yAxis * 1.2), LAMP, Enum.Material.Neon, Enum.PartType.Ball)
	light(bulb, LAMP, 45, 1.6)
end

local function buildBase(layout): Base
	local index = layout.index
	local color = Config.Colors[(index - 1) % #Config.Colors + 1]
	local outward = Vector3.new(layout.dir.X, 0, layout.dir.Y) -- de la cueva del foso hacia la base
	local frame = CFrame.lookAt(layout.floor, layout.floor - outward) -- -Z hacia la boca del pasaje
	local model = Instance.new("Model")
	model.Name = `Base{index}`
	model.Parent = folder
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	-- arcos en las dos bocas del pasaje, con el frente hacia quien llega desde la cueva del foso
	local hubArchPos = layout.hubMouth - outward * 6
	local ownerLabels = {
		arch(model, CFrame.lookAt(hubArchPos, hubArchPos - outward), color, "▲ FOSO"),
		arch(model, at(0, 0, -R + 6), color, "▲ FOSO"),
	}

	-- andén: rieles desde la boca del pasaje hasta el tope, plataforma, tope con luz y aviso para descargar a mano
	local railStart, railEnd = -R - 2, DOCK_Z + 1
	local railLen = railEnd - railStart
	for _, s in { -1, 1 } do
		deco(model, "DockRail", Vector3.new(0.3, 0.3, railLen), at(LANE_X + s * 1.6, 0.45, (railStart + railEnd) / 2), RAIL, Enum.Material.Metal)
	end
	for z = railStart + 1, railEnd, 3 do
		deco(model, "DockSleeper", Vector3.new(4.6, 0.3, 0.8), at(LANE_X, 0.15, z), WOOD, Enum.Material.WoodPlanks)
	end
	part(model, "DockPlatform", Vector3.new(12, 0.6, 18), at(LANE_X - 9, 0.3, DOCK_Z + 4), DARK, Enum.Material.DiamondPlate)
	deco(model, "DockEdge", Vector3.new(0.4, 0.1, 18), at(LANE_X - 3.2, 0.65, DOCK_Z + 4), HAZARD, Enum.Material.SmoothPlastic)
	local buffer = part(model, "BufferStop", Vector3.new(5, 2.2, 1.2), at(LANE_X, 1.1, DOCK_Z + 3), RUST, Enum.Material.CorrodedMetal)
	for _, s in { -1, 1 } do
		deco(model, "BufferStripe", Vector3.new(1, 2.3, 1.3), buffer.CFrame * CFrame.new(s * 1.6, 0, 0), HAZARD, Enum.Material.SmoothPlastic)
	end
	local stopLight = deco(model, "BufferLight", Vector3.one * 0.9, buffer.CFrame * CFrame.new(0, 1.6, 0), Color3.fromRGB(255, 70, 50), Enum.Material.Neon, Enum.PartType.Ball)
	light(stopLight, stopLight.Color, 12, 1)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Descargar minerales"
	prompt.ObjectText = "Andén"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = buffer

	-- tolva detrás del tope y grúa pórtico sobre el andén
	for _, cx in { -2.6, 2.6 } do
		for _, cz in { -2.6, 2.6 } do
			part(model, "HopperLeg", Vector3.new(0.6, 9, 0.6), at(LANE_X + cx, 4.5, DOCK_Z + 7 + cz), DARK, Enum.Material.Metal)
		end
	end
	part(model, "Hopper", Vector3.new(6, 3, 6), at(LANE_X, 10, DOCK_Z + 7), STEEL, Enum.Material.Metal)
	part(model, "HopperNeck", Vector3.new(3, 2, 3), at(LANE_X, 7.8, DOCK_Z + 7), RUST, Enum.Material.CorrodedMetal)
	for _, x in { LANE_X - 11, LANE_X + 11 } do
		part(model, "CraneColumn", Vector3.new(1.2, 17, 1.2), at(x, 8.5, DOCK_Z - 6), HAZARD, Enum.Material.Metal)
	end
	part(model, "CraneBeam", Vector3.new(23.2, 1.2, 1.4), at(LANE_X, 17, DOCK_Z - 6), HAZARD, Enum.Material.Metal)
	part(model, "CraneTrolley", Vector3.new(2.4, 1, 2), at(LANE_X, 15.9, DOCK_Z - 6), DARK, Enum.Material.Metal)
	deco(model, "CraneCable", Vector3.new(0.15, 5, 0.15), at(LANE_X, 12.9, DOCK_Z - 6), RUBBER, Enum.Material.Metal)
	deco(model, "CraneHook", Vector3.new(0.8, 1.2, 0.4), at(LANE_X, 9.8, DOCK_Z - 6), STEEL, Enum.Material.Metal)

	-- cinta elevada de la tolva al almacén, con patas y flechas de neón
	local beltFrom, beltTo = DOCK_Z + 11, HALL_Z - 7
	local beltLen = beltTo - beltFrom
	part(model, "Belt", Vector3.new(3, 0.4, beltLen), at(LANE_X, 6, (beltFrom + beltTo) / 2), RUBBER, Enum.Material.Fabric)
	for _, s in { -1, 1 } do
		part(model, "BeltRail", Vector3.new(0.3, 0.6, beltLen), at(LANE_X + s * 1.6, 6.2, (beltFrom + beltTo) / 2), HAZARD, Enum.Material.SmoothPlastic)
	end
	for z = beltFrom + 2, beltTo - 1, 6 do
		part(model, "BeltLeg", Vector3.new(2.8, 5.8, 0.5), at(LANE_X, 2.9, z), DARK, Enum.Material.Metal)
		deco(model, "BeltArrow", Vector3.new(0.8, 0.05, 0.8), at(LANE_X, 6.23, z + 3) * CFrame.Angles(0, math.rad(45), 0), color, Enum.Material.Neon)
	end

	-- mural de exhibición: pedestales a la derecha de la entrada (los usará Mural)
	for slot = 1, Config.MuralSlots do
		local pedestal = part(model, "MuralSlot", Vector3.new(2.4, 3, 2.4), at(-26, 1.5, -125 + (slot - 1) * 6), DARK, Enum.Material.Metal)
		pedestal:SetAttribute("Slot", slot)
		deco(model, "MuralSlotLight", Vector3.new(2, 0.2, 2), pedestal.CFrame * CFrame.new(0, 1.6, 0), color, Enum.Material.Neon)
	end

	-- panel de estadísticas a la izquierda de la entrada, mirando hacia quien entra
	local board = buildBoard(model, at(28, 11.5, -100), color)

	-- nave de almacén: plataforma, columnas y vigas, y un silo por cada tipo de mineral
	local cols = Config.StorageColumns
	local spacing = Config.StorageSpacing
	local rows = math.ceil(#TYPES / cols)
	local hallW = cols * spacing.X + 6
	local hallFront, hallBack = HALL_Z - 6, HALL_Z + (rows - 1) * spacing.Y + 6
	local hallLen = hallBack - hallFront
	part(model, "HallFloor", Vector3.new(hallW, 0.6, hallLen), at(0, 0.3, (hallFront + hallBack) / 2), DARK, Enum.Material.DiamondPlate)
	local columnStep = hallLen / math.max(math.floor(hallLen / 18), 1)
	for _, s in { -1, 1 } do
		deco(model, "HallEdge", Vector3.new(0.5, 0.2, hallLen), at(s * hallW / 2, 0.7, (hallFront + hallBack) / 2), color, Enum.Material.Neon)
		for z = hallFront, hallBack + 0.1, columnStep do
			part(model, "HallColumn", Vector3.new(1.4, 14, 1.4), at(s * hallW / 2, 7.6, z), RUST, Enum.Material.CorrodedMetal)
		end
		part(model, "HallBeam", Vector3.new(1.4, 1.4, hallLen), at(s * hallW / 2, 14.6, (hallFront + hallBack) / 2), RUST, Enum.Material.CorrodedMetal)
	end
	part(model, "HallHeader", Vector3.new(hallW, 1.4, 1.4), at(0, 14.6, hallFront), RUST, Enum.Material.CorrodedMetal)
	deco(model, "HallHeaderLight", Vector3.new(hallW - 2, 0.3, 0.3), at(0, 13.75, hallFront), color, Enum.Material.Neon)
	local sign = part(model, "HallSign", Vector3.new(24, 3, 0.4), at(0, 17.5, hallFront), DARK, Enum.Material.Metal)
	surfaceText(sign, Enum.NormalId.Front, "ALMACÉN", HAZARD)
	-- tubería sobre la nave que reparte el mineral de la cinta a cada fila
	local feedFrom, feedTo = at(LANE_X, 12.5, hallFront + 2).Position, at(-hallW / 2 + 3, 12.5, hallFront + 2).Position
	deco(model, "Feeder", Vector3.new(0.9, 0.9, (feedTo - feedFrom).Magnitude + 1), CFrame.lookAt((feedFrom + feedTo) / 2, feedTo), RUST, Enum.Material.CorrodedMetal)
	deco(model, "FeedRiser", Vector3.new(0.9, 6.5, 0.9), at(LANE_X, 9.25, hallFront + 2), RUST, Enum.Material.CorrodedMetal)

	local silos = {}
	for k, key in TYPES do
		local row, col = math.floor((k - 1) / cols), (k - 1) % cols
		local x = (col - (cols - 1) / 2) * spacing.X
		local z = HALL_Z + row * spacing.Y
		local base = at(x, 0.6, z)
		local mineralColor = Minerals[key].Color
		column(model, "Silo", base, SILO_H, 2, STEEL, Enum.Material.Metal)
		part(model, "SiloCap", Vector3.one * 4, base * CFrame.new(0, SILO_H, 0), STEEL, Enum.Material.Metal, Enum.PartType.Ball)
		deco(model, "SiloBand", Vector3.new(0.5, 4.2, 4.2), base * CFrame.new(0, SILO_H - 1.5, 0) * CFrame.Angles(0, 0, math.pi / 2), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
		local fill = deco(model, "SiloFill", Vector3.new(0.8, 0.1, 0.2), base * CFrame.new(0, 0.6, -1.95), mineralColor, Enum.Material.Neon)
		local window = deco(model, "SiloWindow", Vector3.new(1.1, SILO_FILL, 0.15), base * CFrame.new(0, 0.5 + SILO_FILL / 2, -2.08), Color3.fromRGB(180, 200, 220), Enum.Material.Glass)
		window.Transparency = 0.55
		local plate = part(model, "SiloPlate", Vector3.new(4.6, 1.8, 0.3), base * CFrame.new(0, 1, -2.7), DARK, Enum.Material.Metal)
		local label = surfaceText(plate, Enum.NormalId.Front, "", mineralColor, Enum.Font.GothamBold)
		local dropLen = 14.2 - SILO_H - 2
		deco(model, "SiloDrop", Vector3.new(0.6, dropLen, 0.6), base * CFrame.new(0, SILO_H + 2 + dropLen / 2, 0), RUST, Enum.Material.CorrodedMetal)
		silos[key] = { fill = fill, label = label, base = base }
	end
	for row = 0, rows - 1 do -- viga por fila, de donde cuelgan las bajantes
		part(model, "RowBeam", Vector3.new(hallW, 0.8, 0.8), at(0, 14.6, HALL_Z + row * spacing.Y), STEEL, Enum.Material.Metal)
	end

	-- utilería junto al andén y la nave
	for k, offset in { Vector3.new(-22, 1.5, -80), Vector3.new(-25, 1.5, -80), Vector3.new(-23.5, 4.5, -80), Vector3.new(36, 1.5, hallFront - 4) } do
		part(model, "Crate", Vector3.new(3, 3, 3), at(offset.X, offset.Y, offset.Z) * CFrame.Angles(0, math.rad(k * 9), 0), WOOD, Enum.Material.WoodPlanks)
	end
	for k, x in { 18, 20.2, 22.4 } do
		column(model, "Barrel", at(x, 0, -60 + (k % 2) * 1.5), 3.2, 1.1, if k == 2 then HAZARD else RUST, Enum.Material.CorrodedMetal)
	end

	-- lámparas colgando del techo de la cueva
	for k = 0, 5 do
		local a = k * math.pi / 3 + 0.5
		hangingLamp(model, at(math.cos(a) * 70, 0, math.sin(a) * 70).Position)
	end
	hangingLamp(model, at(0, 0, 0).Position)
	hangingLamp(model, at(0, 0, -100).Position)

	-- spawn junto a la entrada, mirando hacia la base (+Z local)
	local spawnPos = at(10, 0, -115).Position
	deco(model, "Spawn", Vector3.new(4, 0.1, 4), CFrame.new(spawnPos + Vector3.yAxis * 0.05), color, Enum.Material.Neon).Transparency = 0.4
	local spawnAt = spawnPos + Vector3.yAxis * 3

	local laneOffset = frame.RightVector * LANE_X
	return {
		index = index,
		frame = frame,
		spawn = CFrame.lookAt(spawnAt, spawnAt + outward),
		passageStart = layout.hubMouth + laneOffset,
		laneEntry = at(LANE_X, 0, -R).Position,
		dock = at(LANE_X, 0, DOCK_Z).Position,
		color = color,
		owner = nil,
		board = board,
		silos = silos,
		prompt = prompt,
		ownerLabels = ownerLabels,
	}
end

-- Pinta el panel y los silos de una base con los datos de su dueño.
local function refresh(base: Base)
	local player = base.owner
	local board = base.board
	local total, value, kinds, topKey, topCount = 0, 0, 0, nil, 0
	for _, key in TYPES do
		local stored = if player then player:GetAttribute("Stored_" .. key) or 0 else 0
		total += stored
		value += stored * (Minerals[key].Value or 0)
		if stored > 0 then kinds += 1 end
		if stored > topCount then topKey, topCount = key, stored end
		local silo = base.silos[key]
		-- barra de llenado en escala logarítmica: 1 = un poco, 1000 = lleno
		local height = math.max(SILO_FILL * math.clamp(math.log10(stored + 1) / 3, 0, 1), 0.1)
		silo.fill.Size = Vector3.new(0.8, height, 0.2)
		silo.fill.CFrame = silo.base * CFrame.new(0, 0.5 + height / 2, -1.95)
		silo.label.Text = `{displayName(key)}\n{stored}`
	end
	board.Title.Text = if player then `BASE · {player.DisplayName}` else "BASE LIBRE"
	board.Total.Text = `Minerales guardados: {total}`
	board.Value.Text = `VALOR TOTAL: {value}`
	board.Types.Text = `Tipos conseguidos: {kinds} / {#TYPES}`
	board.Top.Text = if topKey then `Más guardado: {displayName(topKey)} ({topCount})` else "Más guardado: —"
	board.Carts.Text = `Envíos en carrito: {if player then player:GetAttribute("Stat_Carts") or 0 else 0}`
	board.Captured.Text = `Minerales capturados: {if player then player:GetAttribute("Stat_Captured") or 0 else 0}`
	local deepest = if player then player:GetAttribute("Stat_DeepestLayer") or 0 else 0
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
	for key, n in counts do
		if n > 0 then
			player:SetAttribute("Stored_" .. key, (player:GetAttribute("Stored_" .. key) or 0) + n)
		end
	end
	if viaCart then
		player:SetAttribute("Stat_Carts", (player:GetAttribute("Stat_Carts") or 0) + 1)
	end
end

-- Saca del inventario todo lo que lleva el jugador; devuelve { mineral = cantidad } y el total.
function Bases.TakeInventory(player: Player): ({ [string]: number }, number)
	local counts, total = {}, 0
	for _, key in TYPES do
		local n = Inventory.Count(player, key)
		if n > 0 then
			Inventory.Add(player, key, -n)
			counts[key] = n
			total += n
		end
	end
	return counts, total
end

local function buildAll()
	folder = Instance.new("Folder")
	folder.Name = "Bases"
	folder.Parent = workspace
	for _, layout in BaseLayout.All do
		local base = buildBase(layout)
		table.insert(bases, base)
		refresh(base)
		base.prompt.Triggered:Connect(function(player)
			if base.owner ~= player then return end -- solo el dueño descarga en su base
			local counts, total = Bases.TakeInventory(player)
			if total > 0 then
				Bases.Deposit(player, counts, false)
			end
		end)
		task.wait() -- reparte la construcción en varios frames
	end
end

local function setOwnerText(base: Base, text: string)
	for _, label in base.ownerLabels do label.Text = text end
end

local function assign(player: Player)
	if baseOf(player) then return end
	for _, base in bases do
		if not base.owner then
			base.owner = player
			setOwnerText(base, player.DisplayName)
			player:SetAttribute("BaseIndex", base.index)
			for _, key in TYPES do
				player:SetAttribute("Stored_" .. key, player:GetAttribute("Stored_" .. key) or 0)
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
			setOwnerText(base, "LIBRE")
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

-- estadísticas: minerales capturados (lo que entra al inventario); el panel se repinta con cada cambio
local function trackStats(player: Player)
	local last = {}
	player.AttributeChanged:Connect(function(name)
		local key = string.match(name, "^Inv_(.+)$")
		if key then
			local now = player:GetAttribute(name) or 0
			if now > (last[key] or 0) then
				player:SetAttribute("Stat_Captured", (player:GetAttribute("Stat_Captured") or 0) + now - (last[key] or 0))
			end
			last[key] = now
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

	-- las bases se arman cuando las cuevas ya están talladas
	while workspace:GetAttribute("WorldReady") ~= true do
		task.wait(0.2)
	end
	local ok, err = pcall(buildAll)
	if not ok then
		warn(`[Bases] no se pudieron construir las bases: {err}`)
		return
	end
	Players.PlayerAdded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
	for _, p in Players:GetPlayers() do
		assign(p)
		if p.Character then task.spawn(moveToBase, p, p.Character) end
	end
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
