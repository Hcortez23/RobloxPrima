-- Utilería de los hubs de cada capa (shared/HubLayout), en cuanto World los talla (World.Hubs[capa]):
--  · Elevador junto al pozo: cabina de rejas con guías que bajan por el pozo; "Usar elevador" abre el menú con los
--    hubs (Progression decide a cuáles se puede ir).
--  · Terminal del permiso de descenso a la capa siguiente (precio y poder de excavación que pide; Progression cobra).
--  · Hubs de las capas 2 a 10: baranda de vidrio alrededor del pozo abierto, letrero con la capa y lámparas tenues.
-- La cueva del foso (capa 1) ya tiene su utilería en Hub.luau; aquí solo se le agregan el elevador y el terminal.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.World)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.Progression)
local HubLayout = require(ReplicatedStorage.Shared.HubLayout)
local World = require(script.Parent.World)
local Progression = require(script.Parent.Progression)

local LAYERS = WorldConfig.Layers
local DARK = Color3.fromRGB(48, 50, 56)
local STEEL = Color3.fromRGB(110, 114, 120)
local RUST = Color3.fromRGB(110, 62, 40)
local HAZARD = Color3.fromRGB(230, 180, 40)
local LAMP = Color3.fromRGB(255, 214, 160)
local GO = Color3.fromRGB(90, 255, 140)

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

local function deco(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = part(parent, name, size, cframe, color, material, shape)
	p.CanCollide, p.CanQuery, p.CastShadow = false, false, false
	return p
end

local function text(parent: BasePart, face: Enum.NormalId, value: string, color: Color3, font: Enum.Font?): TextLabel
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
	label.TextWrapped = true
	label.Text = value
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = color, range, brightness, false
	l.Parent = parent
end

local function prompt(parent: Instance, action: string, object: string): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText, p.ObjectText = action, object
	p.HoldDuration = 0.3
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- Cabina del elevador: piso, rejas a los lados y atrás, techo con luz, puerta abierta hacia el hub y guías que bajan
-- por el pozo detrás de ella. `at` = centro del piso, -Z hacia la puerta.
local function elevator(model: Model, hub, at: CFrame)
	local w, d, h = 9, 9, 10
	part(model, "CabinFloor", Vector3.new(w, 0.6, d), at * CFrame.new(0, 0.3, 0), DARK, Enum.Material.DiamondPlate)
	part(model, "CabinRoof", Vector3.new(w, 0.6, d), at * CFrame.new(0, h, 0), DARK, Enum.Material.Metal)
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		part(model, "CabinPost", Vector3.new(0.6, h, 0.6), at * CFrame.new(corner[1] * (w / 2 - 0.3), h / 2, corner[2] * (d / 2 - 0.3)), HAZARD, Enum.Material.Metal)
	end
	-- rejas: barrotes a los lados y atrás (colisión con una pared de vidrio)
	for _, side in { { CFrame.new(-w / 2 + 0.3, h / 2, 0), Vector3.new(0.3, h, d) }, { CFrame.new(w / 2 - 0.3, h / 2, 0), Vector3.new(0.3, h, d) }, { CFrame.new(0, h / 2, d / 2 - 0.3), Vector3.new(w, h, 0.3) } } do
		local wall = part(model, "CabinWall", side[2], at * side[1], STEEL, Enum.Material.Glass)
		wall.Transparency = 0.8
	end
	for x = -w / 2 + 1.5, w / 2 - 1.5, 1.5 do
		deco(model, "CabinBar", Vector3.new(0.15, h - 0.6, 0.15), at * CFrame.new(x, h / 2, d / 2 - 0.3), STEEL, Enum.Material.Metal)
	end
	for z = -d / 2 + 1.5, d / 2 - 1.5, 1.5 do
		for _, x in { -w / 2 + 0.3, w / 2 - 0.3 } do
			deco(model, "CabinBar", Vector3.new(0.15, h - 0.6, 0.15), at * CFrame.new(x, h / 2, z), STEEL, Enum.Material.Metal)
		end
	end
	local lamp = deco(model, "CabinLamp", Vector3.new(3, 0.2, 3), at * CFrame.new(0, h - 0.4, 0), LAMP, Enum.Material.Neon)
	light(lamp, LAMP, 14, 0.8)
	-- panel con el aviso para usarlo
	local panel = part(model, "CabinPanel", Vector3.new(1.4, 2, 0.4), at * CFrame.new(w / 2 - 1.2, 4, -d / 2 + 0.6), DARK, Enum.Material.Metal)
	deco(model, "CabinPanelLight", Vector3.new(1, 0.4, 0.1), panel.CFrame * CFrame.new(0, 0.5, -0.25), GO, Enum.Material.Neon)
	prompt(panel, "Usar elevador", "Elevador").Triggered:Connect(Progression.OpenElevator)
	-- letrero sobre la puerta
	local sign = part(model, "CabinSign", Vector3.new(w, 1.6, 0.3), at * CFrame.new(0, h + 1.2, -d / 2 + 0.2), DARK, Enum.Material.Metal)
	text(sign, Enum.NormalId.Front, `ELEVADOR · CAPA {hub.layer}`, HAZARD)
	-- guías y cable que bajan por el pozo detrás de la cabina (hacia el núcleo y hacia arriba)
	local back = at * CFrame.new(0, 0, d / 2 + 1.5)
	local top = if hub.main then 40 else hub.height + 20
	for _, x in { -3, 3 } do
		deco(model, "ElevatorGuide", Vector3.new(0.8, top + 60, 0.8), back * CFrame.new(x, (top - 60) / 2, 0), RUST, Enum.Material.CorrodedMetal)
	end
	deco(model, "ElevatorCable", Vector3.new(0.25, top + 60, 0.25), back * CFrame.new(0, (top - 60) / 2, -0.5), DARK, Enum.Material.Metal)
end

-- Terminal del permiso de descenso: consola con pantalla (capa, precio, poder de excavación) y el aviso para comprarlo.
local function permitTerminal(model: Model, hub, at: CFrame)
	local target = hub.layer + 1
	part(model, "PermitBase", Vector3.new(4, 4, 2.4), at * CFrame.new(0, 2, 0), DARK, Enum.Material.Metal)
	local screen = part(model, "PermitScreen", Vector3.new(4.4, 3, 0.4), at * CFrame.new(0, 5.4, 0.3) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(10, 12, 16), Enum.Material.SmoothPlastic)
	deco(model, "PermitStripe", Vector3.new(4.1, 0.4, 2.5), at * CFrame.new(0, 3.2, 0), HAZARD, Enum.Material.SmoothPlastic)
	local glow = deco(model, "PermitGlow", Vector3.new(4.6, 0.15, 0.2), screen.CFrame * CFrame.new(0, -1.6, -0.2), GO, Enum.Material.Neon)
	light(glow, GO, 10, 0.6)
	if LAYERS[target] then
		local cost = ProgressionConfig.PermitCost[target] or 0
		local power = Progression.RequiredDigPower(target)
		text(screen, Enum.NormalId.Front, `PERMISO DE DESCENSO\nCAPA {target} · {LAYERS[target].Name}\nCosto: {cost}  ·  Excavación: {power}`, Color3.new(1, 1, 1), Enum.Font.GothamBold)
		prompt(screen, `Comprar permiso (capa {target})`, `Costo {cost}`).Triggered:Connect(function(player)
			Progression.BuyPermit(player, target)
		end)
	else
		text(screen, Enum.NormalId.Front, "ÚLTIMA CAPA\nMás abajo: el núcleo", HAZARD, Enum.Font.GothamBold)
	end
end

-- Hubs de las capas 2 a 10: baranda alrededor del pozo, letrero de la capa y lámparas colgando.
local function layerDecor(model: Model, hub)
	local c = hub.center
	local rail = WorldConfig.PitRadius + WorldConfig.PitRagged + 5
	local segments = 32
	local elevatorDir = Vector3.new(math.cos(ProgressionConfig.ElevatorAngle), 0, math.sin(ProgressionConfig.ElevatorAngle))
	for i = 0, segments - 1 do
		local a = (i + 0.5) * math.pi * 2 / segments
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local pos = c + dir * rail
		local frame = CFrame.lookAt(pos, pos + Vector3.new(-dir.Z, 0, dir.X))
		local length = rail * math.pi * 2 / segments + 0.2
		-- baranda: pared de vidrio (no se cae nadie al pozo) con pasamanos y postes
		local glass = part(model, "PitRailGlass", Vector3.new(0.3, 4, length), frame * CFrame.new(0, 2, 0), STEEL, Enum.Material.Glass)
		glass.Transparency = 0.75
		deco(model, "PitRailTop", Vector3.new(0.5, 0.4, length), frame * CFrame.new(0, 4.1, 0), HAZARD, Enum.Material.Metal)
		deco(model, "PitRailPost", Vector3.new(0.5, 4.2, 0.5), frame * CFrame.new(0, 2.1, -length / 2), DARK, Enum.Material.Metal)
		-- franja de advertencia en el piso, salvo frente al elevador
		if dir:Dot(elevatorDir) < 0.95 then
			local stripePos = c + dir * (rail + 2.5)
			deco(model, "PitWarning", Vector3.new(1.4, 0.15, length * 0.55), CFrame.lookAt(stripePos, stripePos + Vector3.new(-dir.Z, 0, dir.X)), if i % 2 == 0 then HAZARD else DARK, Enum.Material.SmoothPlastic)
		end
	end
	-- letrero colgando sobre el pozo, visible desde todo el hub
	local signPos = c + Vector3.yAxis * (hub.height - 6)
	for k = 0, 3 do
		local a = k * math.pi / 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = signPos + dir * 6
		local sign = part(model, "LayerSign", Vector3.new(14, 4, 0.5), CFrame.lookAt(p, p + dir), DARK, Enum.Material.Metal)
		text(sign, Enum.NormalId.Front, `CAPA {hub.layer} · {LAYERS[hub.layer].Name}`, HAZARD)
	end
	for _, s in { -1, 1 } do
		deco(model, "SignChain", Vector3.new(0.2, 12, 0.2), CFrame.new(signPos + Vector3.new(s * 6, 8, 0)), DARK, Enum.Material.Metal)
	end
	-- lámparas tenues colgando del techo
	for k = 0, 5 do
		local a = k * math.pi / 3 + 0.4
		local base = c + Vector3.new(math.cos(a) * hub.radius * 0.7, 26, math.sin(a) * hub.radius * 0.7)
		local hit = workspace:Raycast(base, Vector3.yAxis * 80, terrainOnly)
		local length = math.max((if hit then hit.Position.Y else base.Y + 12) - base.Y, 1)
		deco(model, "LampChain", Vector3.new(0.15, length, 0.15), CFrame.new(base + Vector3.yAxis * length / 2), DARK, Enum.Material.Metal)
		deco(model, "Lamp", Vector3.new(2, 2.6, 2.6), CFrame.new(base) * CFrame.Angles(0, 0, math.pi / 2), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
		local bulb = deco(model, "LampBulb", Vector3.one * 1.4, CFrame.new(base - Vector3.yAxis * 1.1), LAMP, Enum.Material.Neon, Enum.PartType.Ball)
		light(bulb, LAMP, 40, 1.2)
	end
end

local function build(hub)
	local model = Instance.new("Model")
	model.Name = `LayerHub{hub.layer}`
	if not hub.main then layerDecor(model, hub) end
	elevator(model, hub, hub.elevator)
	permitTerminal(model, hub, hub.permit)
	model.Parent = folder
end

return {
	Start = function()
		folder = Instance.new("Folder")
		folder.Name = "LayerHubs"
		folder.Parent = workspace
		local built, count = {}, 0
		-- cada hub se arma en cuanto World lo talla (los profundos, mientras se genera el resto del mundo)
		while count < #HubLayout.All do
			for i, hub in HubLayout.All do
				if not built[i] and World.Hubs[i] then
					built[i], count = true, count + 1
					local ok, err = pcall(build, hub)
					if not ok then warn(`[LayerHubs] no se pudo armar el hub de la capa {i}: {err}`) end
				end
			end
			task.wait(1)
		end
	end,
}
