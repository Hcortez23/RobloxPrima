-- Disparar a un mineral ("Mineral") lo hace explotar: desaparece, suelta materiales nuevos ("Loot")
-- y detona en cadena a los minerales cercanos. Capture recoge el Loot.
-- Un mineral puede ser una Part o un Model (ej. del Marketplace). Si tiene atributo MaxHealth, cada disparo le
-- quita Weapon.Damage, muestra una barra de vida y explota al llegar a 0; sin MaxHealth explota de un tiro.
-- Fracture puede suscribirse a Minerals.Exploded(position, radius) para romper el escenario cercano.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.MineralBehavior)
local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.Weapon)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Weapon = require(script.Parent.Weapon)

local exploded = Instance.new("BindableEvent")
local explosionRemote, lootFolder

-- Placeholder genérico (cristal alargado); para usar un modelo del Marketplace, reemplazar solo esta función.
-- Control de carga: vive Lifetime s, hay tope de MaxLoot en el mundo, y al asentarse se ancla (deja de costar física).
local function spawnLoot(pos: Vector3, rarity: string, color: Color3)
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.6, 1.2, 0.6)
	p.Material, p.Color = Enum.Material.Neon, color
	p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	p:SetAttribute("Rarity", rarity)
	p:SetAttribute("Free", true)
	CollectionService:AddTag(p, "Loot")
	p.Parent = lootFolder
	p:SetNetworkOwner(nil) -- física en el servidor

	local children = lootFolder:GetChildren()
	if #children > Config.MaxLoot then children[1]:Destroy() end -- el más viejo

	local att = Instance.new("Attachment")
	att.Parent = p
	local lift = Instance.new("VectorForce")
	lift.Attachment0, lift.RelativeTo, lift.ApplyAtCenterOfMass = att, Enum.ActuatorRelativeTo.World, true
	lift.Force = Vector3.new(0, p.AssemblyMass * workspace.Gravity * Config.GravityCancel, 0)
	lift.Parent = p

	local dir = (Random.new():NextUnitVector() + Vector3.yAxis * 0.8).Unit
	p:ApplyImpulse(dir * p.AssemblyMass * Config.DropKick)
	Debris:AddItem(p, Config.Lifetime)

	task.spawn(function()
		task.wait(Config.FloatTime)
		if not p.Parent then return end
		lift:Destroy() -- deja de flotar y cae
		local still = 0
		for _ = 1, 40 do -- espera hasta 20 s a que se quede quieto
			task.wait(0.5)
			if not p.Parent then return end
			still = p.AssemblyLinearVelocity.Magnitude < 1 and still + 1 or 0
			if still >= 2 then break end
		end
		p.Anchored = true
	end)
end

local function mineralPosition(node: Instance): Vector3
	return (node :: PVInstance):GetPivot().Position
end

local function mineralColor(node: Instance): Color3
	if node:IsA("BasePart") then return node.Color end
	local rarity = Minerals[node:GetAttribute("Rarity")]
	return if rarity then rarity.Color else Color3.new(1, 1, 1)
end

-- El rayo golpea una pieza; si es parte de un Model mineral, sube hasta el Model.
local function findMineral(instance: Instance?): Instance?
	while instance and instance ~= workspace do
		if CollectionService:HasTag(instance, "Mineral") then return instance end
		instance = instance.Parent
	end
	return nil
end

-- Barra de vida flotando sobre el mineral (se crea con el primer disparo y la ven todos).
local function healthBar(node: Instance): BillboardGui?
	local existing = node:FindFirstChild("HealthBar")
	if existing then return existing :: BillboardGui end

	local adornee = if node:IsA("BasePart") then node else (node :: Model).PrimaryPart or node:FindFirstChildWhichIsA("BasePart", true)
	if not adornee then return nil end
	local center, size
	if node:IsA("Model") then
		center, size = node:GetBoundingBox()
	else
		center, size = (node :: BasePart).CFrame, Vector3.one * (node :: BasePart).Size.Magnitude
	end
	local top = center.Position + Vector3.new(0, size.Y / 2 + 1.5, 0)

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = adornee
	gui.StudsOffsetWorldSpace = top - adornee.Position
	gui.Size = UDim2.fromOffset(160, 20)
	gui.LightInfluence = 0
	gui.MaxDistance = 150

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = gui
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke", back)
	stroke.Color, stroke.Thickness = Color3.new(0, 0, 0), 1.5

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = 2
	label.Parent = back
	Instance.new("UIStroke", label).Thickness = 1

	gui.Parent = node
	return gui
end

local function updateHealthBar(node: Instance, health: number, maxHealth: number)
	local gui = healthBar(node)
	if not gui then return end
	local ratio = math.clamp(health / maxHealth, 0, 1)
	local fill = gui:FindFirstChild("Fill", true) :: Frame
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = Color3.fromRGB(230, 60, 60):Lerp(Color3.fromRGB(70, 220, 100), ratio)
	local label = gui:FindFirstChild("Text", true) :: TextLabel
	label.Text = `{math.ceil(health)} / {maxHealth}`
end

local function detonate(node: Instance)
	if not node.Parent or node:GetAttribute("Detonated") then return end
	node:SetAttribute("Detonated", true)
	local pos, rarity, color = mineralPosition(node), node:GetAttribute("Rarity"), mineralColor(node)
	node:Destroy()

	explosionRemote:FireAllClients(pos, color, Config.ExplosionRadius)
	exploded:Fire(pos, Config.ExplosionRadius)

	for _, loot in CollectionService:GetTagged("Loot") do -- empuja el Loot que ya andaba suelto
		local away = loot.Position - pos
		if not loot.Anchored and away.Magnitude <= Config.ExplosionRadius and away.Magnitude > 0.01 then
			loot:ApplyImpulse(away.Unit * loot.AssemblyMass * Config.PushStrength)
		end
	end
	for _ = 1, Config.DropCount do spawnLoot(pos, rarity, color) end

	for _, other in CollectionService:GetTagged("Mineral") do -- cadena
		local d = (mineralPosition(other) - pos).Magnitude
		if d <= Config.ExplosionRadius then
			task.delay(Config.ChainDelay + d / Config.ChainSpeed, detonate, other)
		end
	end
end

-- Resta vida si el mineral la tiene; si no, o si llega a 0, explota.
local function damage(node: Instance, amount: number)
	local maxHealth = node:GetAttribute("MaxHealth")
	if typeof(maxHealth) ~= "number" then
		detonate(node)
		return
	end
	local health = (node:GetAttribute("Health") or maxHealth) - amount
	node:SetAttribute("Health", math.max(health, 0))
	if health <= 0 then
		detonate(node)
	else
		updateHealthBar(node, health, maxHealth)
	end
end

return {
	Exploded = exploded.Event,
	Start = function()
		explosionRemote = Remotes.get("Minerals_Explosion")
		lootFolder = Instance.new("Folder")
		lootFolder.Name = "Loot"
		lootFolder.Parent = workspace

		Weapon.Hit:Connect(function(_player, _position, _normal, instance)
			local node = findMineral(instance)
			if node then damage(node, WeaponConfig.Damage) end
		end)

		-- Objetos puestos a mano en Workspace que cuentan como mineral (ver Config.MineralBehavior.WorkspaceMinerals).
		for name, settings in Config.WorkspaceMinerals do
			task.spawn(function()
				local node = workspace:WaitForChild(name, 10)
				if not node then
					warn(`[Minerals] no se encontró "{name}" en Workspace`)
					return
				end
				node:SetAttribute("Rarity", settings.Rarity)
				node:SetAttribute("MaxHealth", settings.Health)
				node:SetAttribute("Health", settings.Health)
				CollectionService:AddTag(node, "Mineral")
			end)
		end
	end,
}
