-- Recoger: cada Loot (material suelto) lleva un ProximityPrompt (E). Al activarlo, pasa al inventario del jugador.
local CollectionService = game:GetService("CollectionService")

local Inventory = require(script.Parent.Inventory)

local function watch(loot: Instance)
	if not loot:IsA("BasePart") then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Recoger"
	prompt.ObjectText = loot:GetAttribute("Rarity")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false -- el Loot flota, no debe depender de la línea de vista
	prompt.Parent = loot
	prompt.Triggered:Connect(function(player)
		if not loot:GetAttribute("Free") then return end -- evita recogerlo dos veces
		loot:SetAttribute("Free", nil)
		Inventory.Add(player, loot:GetAttribute("Rarity"), 1)
		loot:Destroy()
	end)
end

return {
	Start = function()
		CollectionService:GetInstanceAddedSignal("Loot"):Connect(watch)
		for _, l in CollectionService:GetTagged("Loot") do watch(l) end
	end,
}
