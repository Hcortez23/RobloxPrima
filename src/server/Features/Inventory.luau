-- Inventario del jugador: un atributo "Inv_<Rareza>" por tipo de objeto (replica solo al cliente para la UI).
-- Inventory.Add(player, item, amount). El servidor es la única fuente de verdad.
-- ponytail: solo en memoria; guardar/cargar con DataStore cuando se defina la persistencia (Economy/Progression).
local PREFIX = "Inv_"

local Inventory = {}

function Inventory.Add(player: Player, item: string, amount: number)
	local key = PREFIX .. item
	player:SetAttribute(key, (player:GetAttribute(key) or 0) + amount)
end

function Inventory.Count(player: Player, item: string): number
	return player:GetAttribute(PREFIX .. item) or 0
end

return Inventory
