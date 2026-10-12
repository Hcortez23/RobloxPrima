-- Sala de pruebas generada por código. Borrar (o desactivar) cuando exista el mapa real.
-- Paredes: celdas Part con tag "Fracturable". Minerales: Part Neon con tag "Mineral" y atributo Rarity.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)

local CELL = 4
local COLS, ROWS = 10, 6

local function wall(parent: Instance, origin: Vector3)
	for x = 0, COLS - 1 do
		for y = 0, ROWS - 1 do
			local p = Instance.new("Part")
			p.Size = Vector3.new(CELL, CELL, CELL)
			p.Position = origin + Vector3.new(x * CELL, y * CELL + CELL / 2, 0)
			p.Anchored = true
			p.Material = Enum.Material.Concrete
			p.Color = Color3.fromRGB(110, 115, 125)
			CollectionService:AddTag(p, "Fracturable")
			p.Parent = parent
		end
	end
end

local function mineral(parent: Instance, rarity: string, pos: Vector3)
	local p = Instance.new("Part")
	p.Size = Vector3.new(1, 1.6, 1)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(45), math.rad(20))
	p.Anchored = true
	p.Material = Enum.Material.Neon
	p.Color = Minerals[rarity].Color
	p:SetAttribute("Rarity", rarity)
	CollectionService:AddTag(p, "Mineral")
	p.Parent = parent
end

return {
	Start = function()
		local room = Instance.new("Folder")
		room.Name = "TestRoom"
		room.Parent = workspace

		wall(room, Vector3.new(-COLS * CELL / 2, 0, -30))
		wall(room, Vector3.new(-COLS * CELL / 2, 0, -50))

		-- dos aislados (explosión simple) y un cúmulo en el centro (cadena)
		local spots = {
			{ "Comun", -40, 6 }, { "Legendario", 40, 6 },
			{ "Raro", -6, 6 }, { "Raro", 0, 8 }, { "Epico", 5, 6 }, { "Raro", -2, 4 }, { "Comun", 8, 9 },
		}
		for _, s in spots do
			mineral(room, s[1], Vector3.new(s[2], s[3], -20))
		end
	end,
}
