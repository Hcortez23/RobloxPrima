-- Decoración de cada cueva-base (la llama Bases.luau al armarla; no es una feature con Start). Todo es ambientación:
-- revestimiento de las paredes, techo con vigas y una corona de luz, pasarela iluminada, plataforma de mando al fondo,
-- monumento con un cristal del color de la base, contenedores, fondo del mural, tuberías, respiraderos con vapor y
-- estandartes con el nombre del dueño. Luces pocas y suaves; casi todo sin colisión.
--
-- Coordenadas locales de la base (como en Bases.luau): origen en el centro del piso, -Z hacia la entrada, +X a la
-- izquierda de quien entra. `ctx` trae las medidas de lo que ya armó Bases para no taparlo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local WorldConfig = require(ReplicatedStorage.Shared.Config.World)
local SignKit = require(script.Parent.SignKit)

local PANEL = Color3.fromRGB(58, 61, 68)
local PANEL_FRAME = Color3.fromRGB(84, 88, 96)
local DARK = Color3.fromRGB(40, 42, 48)
local STEEL = Color3.fromRGB(110, 114, 122)
local RUST = Color3.fromRGB(110, 62, 40)
local HAZARD = Color3.fromRGB(230, 180, 40)
local LAMP = Color3.fromRGB(255, 214, 160)
local WALK = Color3.fromRGB(72, 75, 82)
local CYAN = Color3.fromRGB(110, 210, 255)
local CONTAINERS = { Color3.fromRGB(122, 52, 40), Color3.fromRGB(46, 84, 92), Color3.fromRGB(88, 92, 52), Color3.fromRGB(60, 64, 96) }

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

-- pieza recta entre dos puntos (largo en Z)
local function between(parent: Instance, name: string, a: Vector3, b: Vector3, thickness: Vector2, color: Color3, material: Enum.Material): Part
	return deco(parent, name, Vector3.new(thickness.X, thickness.Y, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material)
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = color, range, brightness, false
	l.Parent = parent
end

-- Texto sobre un estandarte de tela: letras grandes con contorno oscuro, márgenes y una línea de acento debajo.
-- `vertical` lo escribe a lo largo de un estandarte alto (girado). Devuelve el TextLabel (el nombre del dueño).
local function bannerText(cloth: BasePart, value: string, accent: Color3, vertical: boolean): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face, gui.LightInfluence, gui.Brightness = Enum.NormalId.Front, 0, 1.3
	gui.SizingMode, gui.PixelsPerStud = Enum.SurfaceGuiSizingMode.PixelsPerStud, 50
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint, holder.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.48)
	local w, h = cloth.Size.X, cloth.Size.Y
	if vertical then
		holder.Size = UDim2.fromScale((h * 0.8) / w, (w * 0.82) / h) -- girado: el largo del estandarte es el ancho del texto
		holder.Rotation = -90
	else
		holder.Size = UDim2.fromScale(0.88, 0.8)
	end
	holder.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.8)
	label.BackgroundTransparency = 1
	label.Font, label.TextScaled, label.TextWrapped = Enum.Font.GothamBlack, true, true
	label.TextColor3, label.Text = Color3.new(1, 1, 1), value
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness, stroke.Transparency = Color3.new(0, 0, 0), 3, 0.1
	stroke.Parent = label
	label.Parent = holder
	local rule = Instance.new("Frame")
	rule.AnchorPoint, rule.Position = Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.88)
	rule.Size = UDim2.new(0.5, 0, 0, 5)
	rule.BackgroundColor3, rule.BorderSizePixel = accent, 0
	rule.Parent = holder
	gui.Parent = cloth
	return label
end
local BaseDecor = {}

-- Arma la decoración de una base. Devuelve los TextLabel que muestran el nombre del dueño (Bases los actualiza).
function BaseDecor.Build(model: Model, frame: CFrame, ctx): { TextLabel }
	local R, color = ctx.R, ctx.color
	local ownerLabels = {}
	local folder = Instance.new("Model")
	folder.Name = "Decor"
	folder.Parent = model
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local function polar(a: number, r: number, y: number): Vector3
		return at(math.cos(a) * r, y, math.sin(a) * r).Position
	end
	-- mirando hacia el centro (su -Z apunta al eje de la cueva)
	local function inward(a: number, r: number, y: number): CFrame
		local p = polar(a, r, y)
		return CFrame.lookAt(p, at(0, y, 0).Position)
	end
	-- la entrada está en a = -π/2 (z = -R): ahí no van paneles, vigas ni tuberías
	local entranceHalf = math.asin(math.min((ctx.passageWidth / 2 + 4) / R, 1))
	local function atEntrance(a: number): boolean
		return math.abs((a + math.pi / 2 + math.pi) % (math.pi * 2) - math.pi) < entranceHalf
	end
	local soft = color:Lerp(Color3.new(1, 1, 1), 0.15)

	-- 1) Revestimiento de las paredes: paneles con marcos, zócalo oscuro y una línea fina del color de la base arriba
	local panels = 48
	local wallR = R - 1.4
	local panelW = 2 * math.pi * wallR / panels - 0.5
	for k = 0, panels - 1 do
		local a = (k + 0.5) * math.pi * 2 / panels
		if not atEntrance(a) then
			local cf = inward(a, wallR, 6)
			part(folder, "WallPanel", Vector3.new(panelW, 12, 0.6), cf, PANEL, Enum.Material.Metal)
			deco(folder, "WallBaseboard", Vector3.new(panelW + 0.1, 1, 0.8), inward(a, wallR - 0.15, 0.5), DARK, Enum.Material.DiamondPlate)
			deco(folder, "WallTrim", Vector3.new(panelW + 0.5, 0.15, 0.2), inward(a, wallR - 0.4, 12.3), soft, Enum.Material.Neon).Transparency = 0.45
			local edge = (k + 1) * math.pi * 2 / panels
			if not atEntrance(edge) then
				part(folder, "WallRib", Vector3.new(0.9, 13, 1), inward(edge, wallR - 0.2, 6.5), PANEL_FRAME, Enum.Material.Metal)
			end
		end
	end

	-- 2) Tuberías a lo largo de la pared, con abrazaderas, y dos respiraderos con un vapor suave
	local pipeSegments = 24
	for k = 0, pipeSegments - 1 do
		local a0, a1 = k * math.pi * 2 / pipeSegments, (k + 1) * math.pi * 2 / pipeSegments
		if not atEntrance(a0) and not atEntrance(a1) then
			for _, pipe in { { 9, R - 2.7, 1.1, RUST }, { 10.6, R - 2.4, 0.7, STEEL } } do
				local y, r, thick, c = pipe[1], pipe[2], pipe[3], pipe[4]
				between(folder, "WallPipe", polar(a0, r, y), polar(a1, r, y), Vector2.new(thick, thick), c, Enum.Material.CorrodedMetal)
			end
			deco(folder, "PipeBracket", Vector3.new(0.5, 2.6, 1.6), inward(a0, R - 2.2, 9.8), DARK, Enum.Material.Metal)
		end
	end
	for _, a in { math.pi / 2 - 0.95, math.pi / 2 + 0.95 } do
		local cf = inward(a, wallR - 0.4, 2.4)
		part(folder, "Vent", Vector3.new(4, 3, 0.6), cf, DARK, Enum.Material.Metal)
		for n = -1, 1 do
			deco(folder, "VentSlat", Vector3.new(3.4, 0.25, 0.2), cf * CFrame.new(0, n * 0.8, -0.35), STEEL, Enum.Material.Metal)
		end
		local steam = Instance.new("ParticleEmitter")
		steam.Color = ColorSequence.new(Color3.fromRGB(190, 190, 195))
		steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 5) })
		steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
		steam.Lifetime, steam.Speed, steam.Rate = NumberRange.new(2.5, 4), NumberRange.new(1.5, 3), 2.5
		steam.Acceleration = Vector3.new(0, 1.5, 0)
		steam.EmissionDirection = Enum.NormalId.Front
		steam.SpreadAngle = Vector2.new(20, 20)
		steam.Parent = deco(folder, "VentMouth", Vector3.new(3.4, 2.4, 0.1), cf * CFrame.new(0, 0, -0.4), DARK, Enum.Material.Metal)
	end

	-- 3) Techo: viga en anillo sobre los paneles, 8 vigas hacia una corona central con luz hacia abajo y lámparas en
	--    cada viga (reemplazan las lámparas colgantes)
	local ringY, crownY, crownR = 20, 31, 7
	for k = 0, 23 do
		local a0, a1 = k * math.pi * 2 / 24, (k + 1) * math.pi * 2 / 24
		if not atEntrance(a0) and not atEntrance(a1) then
			between(folder, "RingBeam", polar(a0, R - 2.2, ringY), polar(a1, R - 2.2, ringY), Vector2.new(1.4, 1.4), RUST, Enum.Material.CorrodedMetal)
		end
	end
	for k = 0, 7 do
		local a = math.pi / 8 + k * math.pi / 4
		local from, to = polar(a, R - 2.5, ringY), polar(a, crownR, crownY)
		between(folder, "Girder", from, to, Vector2.new(1, 1.6), DARK, Enum.Material.Metal)
		between(folder, "GirderChord", from - Vector3.yAxis * 1.8, to - Vector3.yAxis * 1.2, Vector2.new(0.4, 0.4), STEEL, Enum.Material.Metal)
		local mid = from:Lerp(to, 0.45)
		deco(folder, "GirderLampArm", Vector3.new(0.2, 1.6, 0.2), CFrame.new(mid - Vector3.yAxis * 1.6), DARK, Enum.Material.Metal)
		deco(folder, "GirderLamp", Vector3.new(1.6, 1.2, 1.6), CFrame.new(mid - Vector3.yAxis * 2.8), RUST, Enum.Material.CorrodedMetal)
		local bulb = deco(folder, "GirderBulb", Vector3.new(1.2, 0.3, 1.2), CFrame.new(mid - Vector3.yAxis * 3.5), LAMP, Enum.Material.Neon)
		light(bulb, LAMP, 34, 1.15)
	end
	for k = 0, 11 do -- corona
		local a0, a1 = k * math.pi * 2 / 12, (k + 1) * math.pi * 2 / 12
		between(folder, "Crown", polar(a0, crownR, crownY), polar(a1, crownR, crownY), Vector2.new(1.2, 1.2), DARK, Enum.Material.Metal)
		deco(folder, "CrownGlow", Vector3.new(0.25, 0.25, 0.25), CFrame.new(polar(a0, crownR, crownY - 0.8)), soft, Enum.Material.Neon)
	end
	local disc = deco(folder, "CrownLight", Vector3.new(0.3, crownR * 1.4, crownR * 1.4), at(0, crownY - 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2), LAMP, Enum.Material.Neon, Enum.PartType.Cylinder)
	disc.Transparency = 0.35
	local spot = Instance.new("SpotLight")
	spot.Face, spot.Angle, spot.Range, spot.Brightness, spot.Color, spot.Shadows = Enum.NormalId.Left, 110, 55, 1.2, LAMP, false
	spot.Parent = disc
	local crownTop = at(0, crownY + 0.6, 0).Position
	local hit = workspace:Raycast(crownTop, Vector3.yAxis * 60, terrainOnly)
	local cableLen = math.max((if hit then hit.Position.Y else crownTop.Y + 10) - crownTop.Y, 1)
	for _, x in { -2, 2 } do
		deco(folder, "CrownCable", Vector3.new(0.25, cableLen, 0.25), CFrame.new(crownTop + frame.RightVector * x + Vector3.yAxis * cableLen / 2), DARK, Enum.Material.Metal)
	end

	-- 4) Pasarela de la entrada al almacén: placas con bordes de luz tenue y luces en el piso
	local walkX, walkW = 8, 8
	local walkFrom, walkTo = -R + 6, ctx.hallFront - 0.5
	local walkLen = walkTo - walkFrom
	part(folder, "Walkway", Vector3.new(walkW, 0.3, walkLen), at(walkX, 0.15, (walkFrom + walkTo) / 2), WALK, Enum.Material.DiamondPlate)
	for _, s in { -1, 1 } do
		deco(folder, "WalkwayEdge", Vector3.new(0.25, 0.08, walkLen), at(walkX + s * (walkW / 2 - 0.3), 0.34, (walkFrom + walkTo) / 2), soft, Enum.Material.Neon).Transparency = 0.4
	end
	for z = walkFrom + 4, walkTo - 2, 8 do
		for _, s in { -1, 1 } do
			deco(folder, "FloorLight", Vector3.new(0.6, 0.06, 0.6), at(walkX + s * (walkW / 2 - 1.2), 0.33, z), LAMP, Enum.Material.Neon)
		end
	end
	-- bolardos entre la vía del andén y la pasarela
	for z = -R + 8, ctx.dockZ + 4, 7 do
		local cf = at(ctx.laneX + 5.5, 0, z)
		part(folder, "Bollard", Vector3.new(2.4, 0.8, 0.8), cf * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.pi / 2), HAZARD, Enum.Material.Metal, Enum.PartType.Cylinder)
		deco(folder, "BollardBand", Vector3.new(0.3, 0.85, 0.85), cf * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.pi / 2), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	-- pórtico con letrero sobre la vía del andén
	local gantryZ = -R + 12
	for _, x in { ctx.laneX - 4.5, ctx.laneX + 4.5 } do
		part(folder, "GantryPost", Vector3.new(0.8, 9, 0.8), at(x, 4.5, gantryZ), DARK, Enum.Material.Metal)
	end
	part(folder, "GantryBeam", Vector3.new(10, 0.8, 0.8), at(ctx.laneX, 9.2, gantryZ), DARK, Enum.Material.Metal)
	for _, x in { -3, 3 } do
		deco(folder, "DockSignChain", Vector3.new(0.15, 0.6, 0.15), at(ctx.laneX + x, 8.9, gantryZ), DARK, Enum.Material.Metal)
	end
	SignKit.Build(folder, "DockSign", at(ctx.laneX, 7.3, gantryZ), 8.6, 2.6, { -- el frente (-Z) mira hacia la entrada
		title = "ANDÉN", sub = "DESCARGA DE MINERALES", backTitle = "ANDÉN", backSub = "DESCARGA DE MINERALES", accent = SignKit.HAZARD,
	})

	-- 5) Fondo del mural: pared con letrero y línea de luz detrás de los estands
	local muralFrom, muralTo = ctx.muralZ - 4, ctx.muralZ + (ctx.muralSlots - 1) * ctx.muralStep + 4
	local muralLen = muralTo - muralFrom
	local backX = ctx.muralX - 5.5
	part(folder, "MuralWall", Vector3.new(1, 11, muralLen), at(backX, 5.5, (muralFrom + muralTo) / 2), PANEL, Enum.Material.Metal)
	deco(folder, "MuralWallTrim", Vector3.new(0.2, 0.2, muralLen - 1), at(backX + 0.6, 10.2, (muralFrom + muralTo) / 2), soft, Enum.Material.Neon).Transparency = 0.3
	for _, z in { muralFrom, muralTo } do
		part(folder, "MuralWallPost", Vector3.new(1.4, 12, 1.4), at(backX, 6, z), PANEL_FRAME, Enum.Material.Metal)
	end
	-- letrero sobre la pared, mirando hacia el centro (+X local)
	SignKit.Build(folder, "MuralHeader", at(backX + 0.9, 13, (muralFrom + muralTo) / 2) * CFrame.Angles(0, -math.pi / 2, 0), 15, 3.2, {
		title = "COLECCIÓN", sub = "LOS MINERALES MÁS VALIOSOS", accent = color, glow = true,
	})

	-- 6) Contenedores apilados a los lados del almacén (fuera de su ancho)
	local sideX = ctx.hallW / 2 + 9
	local function container(cf: CFrame, c: Color3)
		part(folder, "Container", Vector3.new(5, 5.5, 12), cf * CFrame.new(0, 2.75, 0), c, Enum.Material.CorrodedMetal)
		for z = -5, 5, 2.5 do
			for _, s in { -1, 1 } do
				deco(folder, "ContainerRib", Vector3.new(0.2, 5.2, 0.4), cf * CFrame.new(s * 2.55, 2.75, z), c:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Metal)
			end
		end
		deco(folder, "ContainerStripe", Vector3.new(5.05, 0.5, 0.1), cf * CFrame.new(0, 4.6, -6.02), color, Enum.Material.SmoothPlastic)
	end
	for side, s in { -1, 1 } do
		local x = s * sideX
		if math.sqrt(x * x + 32 * 32) + 6 < R - 3 then -- solo si caben
			local z0 = ctx.hallFront + 6
			container(at(x, 0, z0 + 6), CONTAINERS[side])
			container(at(x, 0, z0 + 19), CONTAINERS[side + 2])
			container(at(x, 5.5, z0 + 12.5) * CFrame.Angles(0, 0.05 * s, 0), CONTAINERS[3 - side])
			for k = 0, 2 do -- tarima con cajas al lado
				part(folder, "PalletCrate", Vector3.new(2.2, 2.2, 2.2), at(x - s * 5.5, 1.1 + (if k == 2 then 2.2 else 0), z0 + 2 + (k % 2) * 2.4) * CFrame.Angles(0, 0.2 * k, 0), Color3.fromRGB(120, 88, 56), Enum.Material.WoodPlanks)
			end
		end
	end

	-- 7) Al fondo: plataforma de mando (escalones, baranda, consolas, silla y pantalla grande) y, entre el almacén y la
	--    plataforma, un monumento con un cristal del color de la base. Se ponen solo si queda sitio detrás del almacén.
	local platformFront = math.max(R - 21, ctx.hallBack + 5)
	local platformBack = R - 6
	if platformBack - platformFront >= 9 then
		local depth = platformBack - platformFront
		local pz = (platformFront + platformBack) / 2
		part(folder, "Platform", Vector3.new(24, 3, depth), at(0, 1.5, pz), DARK, Enum.Material.Metal)
		part(folder, "PlatformDeck", Vector3.new(24, 0.2, depth), at(0, 3.1, pz), WALK, Enum.Material.DiamondPlate)
		deco(folder, "PlatformEdge", Vector3.new(24, 0.15, 0.3), at(0, 3.2, platformFront + 0.2), HAZARD, Enum.Material.SmoothPlastic)
		for step = 1, 3 do
			part(folder, "Step", Vector3.new(8, step, 1.2), at(0, step / 2, platformFront - (4 - step) * 1.2 + 0.6), WALK, Enum.Material.DiamondPlate)
		end
		local railY = 3.2
		for _, run in { { -12, -4.5 }, { 4.5, 12 } } do -- baranda al frente (sin tapar los escalones)
			local a, b = at(run[1], railY + 3, platformFront + 0.3).Position, at(run[2], railY + 3, platformFront + 0.3).Position
			between(folder, "Railing", a, b, Vector2.new(0.25, 0.25), STEEL, Enum.Material.Metal)
			for x = run[1], run[2], 2.5 do
				deco(folder, "RailingPost", Vector3.new(0.25, 3, 0.25), at(x, railY + 1.5, platformFront + 0.3), STEEL, Enum.Material.Metal)
			end
		end
		for _, s in { -1, 1 } do
			between(folder, "Railing", at(s * 12, railY + 3, platformFront + 0.3).Position, at(s * 12, railY + 3, platformBack).Position, Vector2.new(0.25, 0.25), STEEL, Enum.Material.Metal)
			local post = deco(folder, "RailLamp", Vector3.new(0.6, 0.6, 0.6), at(s * 12, railY + 3.5, platformFront + 0.3), LAMP, Enum.Material.Neon)
			light(post, LAMP, 14, 0.6)
		end
		-- consolas en arco mirando hacia la pantalla del fondo
		for k, x in { -4.5, 0, 4.5 } do
			local cz = platformBack - 5.5 + (if k == 2 then 0.8 else 0)
			local cf = at(x, railY, cz) * CFrame.Angles(0, (k - 2) * -0.35, 0)
			part(folder, "Console", Vector3.new(3.6, 2.6, 1.6), cf * CFrame.new(0, 1.3, 0), DARK, Enum.Material.Metal)
			local readout = ({ { "ENERGÍA", "▮▮▮▮▮▯  83%" }, { "EXTRACCIÓN", "EN LÍNEA" }, { "PRESIÓN", "ESTABLE" } })[k]
			SignKit.Build(folder, "ConsoleScreen", cf * CFrame.new(0, 3.3, 0.4) * CFrame.Angles(math.rad(20), 0, 0), 3.2, 1.7, {
				title = readout[1], sub = readout[2], style = "screen", accent = CYAN, depth = 0.15, subRatio = 0.4,
			})
			deco(folder, "ConsoleKeys", Vector3.new(3, 0.1, 0.8), cf * CFrame.new(0, 2.65, -0.3), Color3.fromRGB(70, 74, 82), Enum.Material.SmoothPlastic)
		end
		local chair = at(0, railY, platformBack - 8.5)
		part(folder, "ChairBase", Vector3.new(0.5, 1.4, 0.5), chair * CFrame.new(0, 0.7, 0), DARK, Enum.Material.Metal)
		part(folder, "ChairSeat", Vector3.new(2, 0.4, 2), chair * CFrame.new(0, 1.6, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric)
		part(folder, "ChairBack", Vector3.new(2, 2.4, 0.4), chair * CFrame.new(0, 2.9, -0.9), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric)
		-- pantalla grande en la pared del fondo: las capas del mundo
		local lines = {}
		for i, layer in WorldConfig.Layers do table.insert(lines, `CAPA {if i < 10 then " " else ""}{i}   {layer.Name}`) end
		SignKit.Build(folder, "WallScreen", at(0, 11, platformBack + 1.6), 18, 8.5, {
			title = "RED DE EXTRACCIÓN", sub = table.concat(lines, "\n"), style = "screen", accent = CYAN, subRatio = 0.74, glow = true,
		})
		-- estandarte con el nombre del dueño sobre la pantalla
		local banner = part(folder, "BackBanner", Vector3.new(16, 4, 0.2), at(0, 18, platformBack + 1.4), color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Fabric)
		for _, s in { -1, 1 } do -- bordes del estandarte
			deco(folder, "BackBannerEdge", Vector3.new(16.1, 0.3, 0.24), at(0, 18 + s * 1.85, platformBack + 1.4), SignKit.HAZARD, Enum.Material.Fabric)
		end
		table.insert(ownerLabels, bannerText(banner, "LIBRE", color, false))

		-- monumento entre el almacén y la plataforma
		local gap0, gap1 = ctx.hallBack + 4, platformFront - 5
		if gap1 - gap0 >= 16 then
			local mz = (gap0 + gap1) / 2
			local base = at(0, 0, mz)
			local function disc(r: number, h: number, y: number, c: Color3, m: Enum.Material): Part
				return part(folder, "Dais", Vector3.new(h, r * 2, r * 2), base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2), c, m, Enum.PartType.Cylinder)
			end
			disc(7, 0.6, 0.3, DARK, Enum.Material.Metal)
			disc(5, 0.6, 0.9, PANEL_FRAME, Enum.Material.DiamondPlate)
			local trim = deco(folder, "DaisTrim", Vector3.new(0.12, 14.3, 14.3), base * CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2), soft, Enum.Material.Neon, Enum.PartType.Cylinder)
			trim.Transparency = 0.5
			part(folder, "Plinth", Vector3.new(2.4, 3, 3), base * CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, math.pi / 2), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
			for k = 0, 3 do -- pilones con punta de luz
				local a = math.pi / 4 + k * math.pi / 2
				local p = base * CFrame.new(math.cos(a) * 5.6, 0, math.sin(a) * 5.6)
				part(folder, "Pylon", Vector3.new(0.8, 5.5, 0.8), p * CFrame.new(0, 3.95, 0), DARK, Enum.Material.Metal)
				deco(folder, "PylonTip", Vector3.new(0.5, 0.5, 0.5), p * CFrame.new(0, 6.9, 0), soft, Enum.Material.Neon, Enum.PartType.Ball)
			end
			for k = 0, 15 do -- anillo que rodea el cristal
				local a0, a1 = k * math.pi * 2 / 16, (k + 1) * math.pi * 2 / 16
				local p0 = (base * CFrame.new(math.cos(a0) * 3.4, 7, math.sin(a0) * 3.4)).Position
				local p1 = (base * CFrame.new(math.cos(a1) * 3.4, 7, math.sin(a1) * 3.4)).Position
				between(folder, "OrbitRing", p0, p1, Vector2.new(0.2, 0.35), STEEL, Enum.Material.Metal)
			end
			-- el cristal (gira y flota en el cliente, como los minerales del mural)
			local crystal = Instance.new("Model")
			crystal.Name = "BaseCrystal"
			local shell = deco(crystal, "CrystalShell", Vector3.new(2.2, 5.5, 2.2), base * CFrame.new(0, 7, 0) * CFrame.Angles(0, math.rad(45), 0), color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Glass)
			shell.Transparency = 0.35
			local core = deco(crystal, "CrystalCore", Vector3.new(1, 4, 1), base * CFrame.new(0, 7, 0), color, Enum.Material.Neon)
			light(core, color, 26, 1.1)
			crystal.PrimaryPart = core
			crystal:SetAttribute("Base", base * CFrame.new(0, 7, 0))
			CollectionService:AddTag(crystal, "MuralExhibit")
			crystal.Parent = folder
		end
	end

	-- 8) Estandartes con el nombre del dueño a los lados (colgando de la viga en anillo)
	for _, a in { 0, math.pi } do
		local cf = inward(a, R - 3.2, ringY - 7.5)
		part(folder, "BannerRod", Vector3.new(7, 0.3, 0.3), cf * CFrame.new(0, 7.2, 0), DARK, Enum.Material.Metal)
		local cloth = part(folder, "Banner", Vector3.new(6, 14, 0.15), cf, color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Fabric)
		cloth.CanCollide = false
		deco(folder, "BannerStripe", Vector3.new(6.05, 0.5, 0.17), cf * CFrame.new(0, -6, 0), HAZARD, Enum.Material.Fabric)
		table.insert(ownerLabels, bannerText(cloth, "LIBRE", SignKit.HAZARD, true))
	end

	return ownerLabels
end

return BaseDecor
