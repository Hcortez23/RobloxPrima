-- Estaciones de carritos: una en el hub de cada capa (shared/HubLayout; el túnel lo talla World). El carrito es solo
-- visual, para ahorrar: el jugador "Envía minerales a su base", se le vacía el inventario y el carrito entra lleno por
-- el túnel (solo para carritos: una reja invisible no deja pasar a los jugadores). Apenas se pierde de vista, lo que
-- lleva se suma al almacén de su base (Bases.Deposit, cuenta como un envío) y el carrito desaparece; enseguida sale
-- uno vacío del túnel para el siguiente envío. Los carritos se mueven en el servidor (piezas ancladas, PivotTo).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Carts)
local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)
local HubLayout = require(ReplicatedStorage.Shared.HubLayout)
local World = require(script.Parent.World)
local Bases = require(script.Parent.Bases)
local SignKit = require(script.Parent.SignKit)

local DARK = Color3.fromRGB(48, 50, 56)
local RUST = Color3.fromRGB(110, 62, 40)
local RAIL = Color3.fromRGB(96, 92, 90)
local WOOD = Color3.fromRGB(70, 52, 40)
local HAZARD = Color3.fromRGB(230, 180, 40)
local LAMP = Color3.fromRGB(255, 214, 160)

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

-- suelo bajo `p` (rayo corto contra el terreno)
local function floorAt(p: Vector3): Vector3
	local hit = workspace:Raycast(p + Vector3.yAxis * 4, Vector3.yAxis * -14, terrainOnly)
	return if hit then hit.Position else p
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
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = LAMP, 12, 0.8, false
	glow.Parent = lamp
	for k, c in ore do -- trozos de mineral asomando
		local x, z = ((k - 1) % 2 - 0.5) * 1.2, (math.floor((k - 1) / 2) - 1) * 1.2
		deco(model, "Ore", Vector3.new(1, 0.9, 1), origin * CFrame.new(x, 2.4, z) * CFrame.Angles(0.4 * k, 0.7 * k, 0.3 * k), c, Enum.Material.Neon)
	end
	model.PrimaryPart = chassis
	model.WorldPivot = origin
	return model
end

-- Mueve el carrito en línea recta de `a` a `b` a velocidad constante. onPass(distancia recorrida) se llama en cada
-- frame; si devuelve true, se detiene ahí. onArrive, al llegar.
local function roll(cart: Model, a: Vector3, b: Vector3, onPass: ((number) -> boolean)?, onArrive: (() -> ())?)
	local total = math.max((b - a).Magnitude, 0.01)
	local facing = CFrame.lookAt(Vector3.zero, b - a).Rotation
	local distance = 0
	cart:PivotTo(CFrame.new(a) * facing)
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not cart.Parent then
			connection:Disconnect()
			return
		end
		distance = math.min(distance + dt * Config.Speed, total)
		cart:PivotTo(CFrame.new(a:Lerp(b, distance / total)) * facing)
		if onPass and onPass(distance) then
			connection:Disconnect()
			return
		end
		if distance >= total then
			connection:Disconnect()
			if onArrive then onArrive() end
		end
	end)
end

-- Estación de un hub: vía de la parada al fondo del túnel, reja en la boca, andén con techo y terminal con el aviso.
local function buildStation(hub)
	local s = hub.station
	local up = Vector3.yAxis
	local dir = s.dir
	local side = dir:Cross(up).Unit
	local model = Instance.new("Model")
	model.Name = `Station{hub.layer}`
	model.Parent = folder

	local stop = floorAt(s.stop)
	local finish = Vector3.new(s.tunnelEnd.X, stop.Y, s.tunnelEnd.Z) - dir * 3
	local stopFrame = CFrame.lookAt(stop, stop + dir)
	-- vía: rieles y durmientes de la parada al fondo del túnel
	local railFrom, railTo = stop - dir * 5, finish
	for _, x in { -1.6, 1.6 } do
		local ra, rb = railFrom + side * x + up * 0.45, railTo + side * x + up * 0.45
		deco(model, "Rail", Vector3.new(0.3, 0.3, (rb - ra).Magnitude), CFrame.lookAt((ra + rb) / 2, rb), RAIL, Enum.Material.Metal)
	end
	for d = 0, (railTo - railFrom).Magnitude, 4 do
		local p = railFrom + dir * d + up * 0.15
		deco(model, "Sleeper", Vector3.new(4.6, 0.3, 0.8), CFrame.lookAt(p, p + dir), WOOD, Enum.Material.WoodPlanks)
	end
	deco(model, "BufferStop", Vector3.new(4.4, 1.6, 0.8), stopFrame * CFrame.new(0, 0.8, 4.2), RUST, Enum.Material.CorrodedMetal)

	-- reja de la boca: marco, persiana que sube cuando pasa un carrito y pared invisible que no deja pasar a nadie
	local mouth = Vector3.new(s.mouth.X, stop.Y, s.mouth.Z)
	local mouthFrame = CFrame.lookAt(mouth, mouth + dir)
	for _, x in { -4.6, 4.6 } do
		part(model, "GatePost", Vector3.new(1.2, 9.5, 1.2), mouthFrame * CFrame.new(x, 4.75, 0), DARK, Enum.Material.Metal)
		for band = 1, 3 do
			deco(model, "GateStripe", Vector3.new(1.3, 0.9, 1.3), mouthFrame * CFrame.new(x, band * 2.4, 0), HAZARD, Enum.Material.SmoothPlastic)
		end
	end
	part(model, "GateHeader", Vector3.new(10.4, 1.4, 1.4), mouthFrame * CFrame.new(0, 10, 0), RUST, Enum.Material.CorrodedMetal)
	local shutter = Instance.new("Model")
	shutter.Name = "GateShutter"
	local closed = mouthFrame * CFrame.new(0, 4.4, 0.4)
	local shutterBase = deco(shutter, "ShutterFrame", Vector3.new(8, 8.6, 0.2), closed, DARK, Enum.Material.Glass)
	shutterBase.Transparency = 0.9
	for x = -3.5, 3.5, 1 do
		deco(shutter, "ShutterBar", Vector3.new(0.25, 8.6, 0.25), closed * CFrame.new(x, 0, 0), RUST, Enum.Material.CorrodedMetal)
	end
	shutter.PrimaryPart = shutterBase
	shutter.Parent = model
	local blocker = part(model, "GateBlocker", Vector3.new(9, 12, 1), mouthFrame * CFrame.new(0, 6, -1.5), DARK, Enum.Material.SmoothPlastic)
	blocker.Transparency, blocker.CanQuery = 1, false -- los carritos no chocan (son decoración); los jugadores sí
	-- letrero sobre la reja, mirando hacia el hub (de espaldas al túnel)
	SignKit.Build(model, "GateSign", mouthFrame * CFrame.new(0, 12.6, 0.5) * CFrame.Angles(0, math.pi, 0), 10.4, 2.8, {
		title = "ENVÍOS A LA BASE", sub = "SOLO CARRITOS", accent = HAZARD, glow = true,
	})

	local openValue = Instance.new("NumberValue") -- 0 = cerrada, 1 = abierta
	openValue.Changed:Connect(function(v) shutter:PivotTo(closed * CFrame.new(0, v * 8.5, 0)) end)
	local function gate(open: boolean)
		TweenService:Create(openValue, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Value = if open then 1 else 0 }):Play()
	end

	-- andén a un lado de la parada, con techo y terminal
	local platform = stopFrame * CFrame.new(5.5, 0, 0)
	part(model, "Platform", Vector3.new(6, 0.6, 10), platform * CFrame.new(0, 0.3, 0), DARK, Enum.Material.DiamondPlate)
	deco(model, "PlatformEdge", Vector3.new(0.4, 0.1, 10), platform * CFrame.new(-3, 0.65, 0), HAZARD, Enum.Material.SmoothPlastic)
	for _, z in { -4.4, 4.4 } do
		part(model, "Post", Vector3.new(0.6, 7, 0.6), platform * CFrame.new(2.4, 3.6, z), RUST, Enum.Material.CorrodedMetal)
	end
	part(model, "Roof", Vector3.new(6.6, 0.4, 10.4), platform * CFrame.new(0.3, 7.2, 0), RUST, Enum.Material.CorrodedMetal)
	local terminal = part(model, "Terminal", Vector3.new(1.4, 3, 2), platform * CFrame.new(1, 2.1, 0), DARK, Enum.Material.Metal)
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
	prompt.Enabled = false
	prompt.Parent = terminal

	-- el carrito vacío que sale del túnel y espera en la parada
	local waiting: Model? = nil
	local function bringEmptyCart()
		local cart = makeCart(HAZARD, {})
		cart.Parent = model
		gate(true)
		roll(cart, finish, stop, nil, function()
			cart:PivotTo(CFrame.lookAt(stop, stop + dir)) -- de frente al túnel, listo para salir
			gate(false)
			waiting = cart
			prompt.ObjectText = "Carrito"
			prompt.Enabled = true
		end)
	end
	bringEmptyCart()

	prompt.Triggered:Connect(function(player)
		local base = Bases.Get(player)
		if not waiting or not base then return end
		local counts, total = Bases.TakeInventory(player)
		if total == 0 then return end
		prompt.Enabled = false
		prompt.ObjectText = "Carrito en camino"
		-- el carrito vacío se cambia por uno cargado (con el color de la base y lo más valioso que lleva)
		waiting:Destroy()
		waiting = nil
		local keys = {}
		for key in counts do table.insert(keys, key) end
		table.sort(keys, function(a, b) return (Minerals[a].Value or 0) > (Minerals[b].Value or 0) end)
		local ore = {}
		for _, key in keys do
			for _ = 1, math.min(counts[key], 2) do table.insert(ore, Minerals[key].Color) end
		end
		while #ore > 6 do table.remove(ore) end
		local cart = makeCart(base.color, ore)
		cart.Parent = model
		gate(true)
		local deliverAt = (mouth - stop).Magnitude + Config.DepositDistance
		roll(cart, stop, finish, function(distance)
			if distance < deliverAt then return false end
			-- ya no se ve: se entrega en la base y el carrito desaparece
			if player.Parent == Players and Bases.Get(player) == base then
				Bases.Deposit(player, counts, true)
			end
			cart:Destroy()
			gate(false)
			task.delay(Config.RespawnDelay, bringEmptyCart)
			return true
		end)
	end)
end

return {
	Start = function()
		folder = Instance.new("Folder")
		folder.Name = "Carts"
		folder.Parent = workspace
		while workspace:GetAttribute("BasesReady") ~= true do
			task.wait(0.25)
		end
		-- cada estación se arma en cuanto World talla su hub
		local built, count = {}, 0
		while count < #HubLayout.All do
			for i, hub in HubLayout.All do
				if not built[i] and World.Hubs[i] then
					built[i], count = true, count + 1
					local ok, err = pcall(buildStation, hub)
					if not ok then warn(`[Carts] no se pudo armar la estación de la capa {i}: {err}`) end
				end
			end
			task.wait(1)
		end
	end,
}
