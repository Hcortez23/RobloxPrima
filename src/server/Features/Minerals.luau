-- Disparar a un mineral ("Mineral") lo hace explotar: desaparece, suelta materiales nuevos ("Loot")
-- y detona en cadena a los minerales cercanos. Capture recoge el Loot.
-- Fracture puede suscribirse a Minerals.Exploded(position, radius) para romper el escenario cercano.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.MineralBehavior)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Weapon = require(script.Parent.Weapon)

local exploded = Instance.new("BindableEvent")
local explosionRemote, lootFolder

local function spawnLoot(pos: Vector3, rarity: string, color: Color3)
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.7, 1.1, 0.7)
	p.Material, p.Color = Enum.Material.Neon, color
	p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	p:SetAttribute("Rarity", rarity)
	p:SetAttribute("Free", true)
	CollectionService:AddTag(p, "Loot")
	p.Parent = lootFolder
	p:SetNetworkOwner(nil) -- física en el servidor

	local att = Instance.new("Attachment")
	att.Parent = p
	local lift = Instance.new("VectorForce")
	lift.Attachment0, lift.RelativeTo, lift.ApplyAtCenterOfMass = att, Enum.ActuatorRelativeTo.World, true
	lift.Force = Vector3.new(0, p.AssemblyMass * workspace.Gravity * Config.GravityCancel, 0)
	lift.Parent = p

	local dir = (Random.new():NextUnitVector() + Vector3.yAxis * 0.8).Unit
	p:ApplyImpulse(dir * p.AssemblyMass * Config.DropKick)
	Debris:AddItem(p, Config.Lifetime)
end

local function detonate(node: BasePart)
	if not node.Parent or node:GetAttribute("Detonated") then return end
	node:SetAttribute("Detonated", true)
	local pos, rarity, color = node.Position, node:GetAttribute("Rarity"), node.Color
	node:Destroy()

	explosionRemote:FireAllClients(pos, color, Config.ExplosionRadius)
	exploded:Fire(pos, Config.ExplosionRadius)

	for _, loot in CollectionService:GetTagged("Loot") do -- empuja el Loot que ya andaba suelto
		local away = loot.Position - pos
		if away.Magnitude <= Config.ExplosionRadius and away.Magnitude > 0.01 then
			loot:ApplyImpulse(away.Unit * loot.AssemblyMass * Config.PushStrength)
		end
	end
	for _ = 1, Config.DropCount do spawnLoot(pos, rarity, color) end

	for _, other in CollectionService:GetTagged("Mineral") do -- cadena
		local d = (other.Position - pos).Magnitude
		if d <= Config.ExplosionRadius then
			task.delay(Config.ChainDelay + d / Config.ChainSpeed, detonate, other)
		end
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
			if CollectionService:HasTag(instance, "Mineral") then detonate(instance) end
		end)
	end,
}
