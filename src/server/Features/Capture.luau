-- Tocar un mineral "Free" lo captura: se destruye y suma su valor al atributo "Carried" del jugador
-- (lo que lleva en el run; Extraction lo convertirá en materiales guardados).
-- ponytail: Touched, suficiente para prototipo; si se pierden capturas a alta velocidad, usar GetPartBoundsInRadius.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)

local function watch(mineral: Instance)
	if not mineral:IsA("BasePart") then return end
	mineral.Touched:Connect(function(other)
		if not mineral:GetAttribute("Free") or not mineral.Parent then return end
		local player = Players:GetPlayerFromCharacter(other.Parent)
		if not player then return end
		mineral:SetAttribute("Free", nil) -- evita doble captura
		local value = Minerals[mineral:GetAttribute("Rarity")].Value
		player:SetAttribute("Carried", (player:GetAttribute("Carried") or 0) + value)
		mineral:Destroy()
	end)
end

return {
	Start = function()
		CollectionService:GetInstanceAddedSignal("Mineral"):Connect(watch)
		for _, m in CollectionService:GetTagged("Mineral") do watch(m) end
	end,
}
