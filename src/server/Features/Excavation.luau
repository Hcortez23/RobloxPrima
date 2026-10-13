-- Excavación: de la capa 2 hacia abajo todo es roca maciza que se abre disparando (y con las explosiones de minerales).
-- Hueco de un disparo = BaseRadius * DigPower del arma / Hardness de la capa (Config/Excavation, Config/World). Si es
-- menor que MinRadius, la roca es demasiado dura para esa arma: no se abre y el cliente muestra chispas. Nunca se
-- excavan las zonas protegidas (World.CanDig): el caparazón del pozo, las cuevas de arriba y el fondo del mundo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Excavation)
local WorldConfig = require(ReplicatedStorage.Shared.Config.World)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Weapon = require(script.Parent.Weapon)
local World = require(script.Parent.World)
local Minerals = require(script.Parent.Minerals)

local Terrain = workspace.Terrain
local digRemote: RemoteEvent

-- color de la roca en el punto golpeado (para los trozos que saltan)
local function rockColor(pos: Vector3, normal: Vector3): Color3
	local p = pos - normal * 2
	local materials = Terrain:ReadVoxels(Region3.new(p - Vector3.one, p + Vector3.one):ExpandToGrid(4), 4)
	local material = materials[1][1][1]
	if material == Enum.Material.Air or material == Enum.Material.Water then
		return Color3.fromRGB(110, 104, 100)
	end
	return Terrain:GetMaterialColor(material)
end

local function dig(pos: Vector3, radius: number, normal: Vector3)
	local color = rockColor(pos, normal)
	Terrain:FillBall(pos, radius, Enum.Material.Air)
	digRemote:FireAllClients("dig", pos, radius, normal, color)
end

return {
	Start = function()
		digRemote = Remotes.get("Excavation_Dig")

		Weapon.Hit:Connect(function(player, position, normal, instance, _damage, digPower)
			if instance ~= Terrain then return end
			local hardness = World.Hardness(-position.Y)
			local radius = math.min(Config.BaseRadius * (digPower or Config.DefaultDigPower) / hardness, Config.MaxRadius)
			if radius < Config.MinRadius or not World.CanDig(position, radius) then
				digRemote:FireClient(player, "hard", position, normal) -- demasiado dura (o zona protegida)
				return
			end
			dig(position, radius, normal)
		end)

		-- las explosiones de minerales excavan más, pero la roca dura también las frena
		Minerals.Exploded:Connect(function(pos: Vector3, radius: number)
			local hardness = World.Hardness(-pos.Y)
			local r = math.min(radius * WorldConfig.CarveFactor / math.sqrt(hardness), Config.MaxRadius * 1.5)
			if r >= Config.MinRadius and World.CanDig(pos, r) then
				dig(pos, r, Vector3.yAxis)
			end
		end)
	end,
}
