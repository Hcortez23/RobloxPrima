-- Un disparo a un mineral anclado lo suelta: sale despedido, flota un rato y desaparece si no lo capturan.
-- Capture (otro archivo) se encarga de recogerlo; aquí solo lo marcamos con el atributo "Free".
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.MineralBehavior)
local Weapon = require(script.Parent.Weapon)

local function release(mineral: BasePart, normal: Vector3)
	mineral.Anchored = false
	mineral:SetAttribute("Free", true)
	mineral:SetNetworkOwner(nil) -- física en el servidor

	local att = Instance.new("Attachment")
	att.Parent = mineral
	local lift = Instance.new("VectorForce")
	lift.Attachment0, lift.RelativeTo, lift.ApplyAtCenterOfMass = att, Enum.ActuatorRelativeTo.World, true
	lift.Force = Vector3.new(0, mineral.AssemblyMass * workspace.Gravity * Config.GravityCancel, 0)
	lift.Parent = mineral

	local away = (-normal + Vector3.yAxis * 0.8).Unit -- hacia dentro de la superficie y arriba
	mineral:ApplyImpulse(away * mineral.AssemblyMass * Config.KickSpeed)
	Debris:AddItem(mineral, Config.Lifetime)
end

return {
	Start = function()
		Weapon.Hit:Connect(function(_player, _position, normal, instance)
			if instance.Anchored and CollectionService:HasTag(instance, "Mineral") then
				release(instance, normal)
			end
		end)
	end,
}
