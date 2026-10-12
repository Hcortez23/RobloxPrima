-- Mochila: los datos viven en atributos "Inv_<Rareza>" del jugador (fuente de verdad, sobreviven al respawn y
-- serán lo que se guarde en DataStore). La barra de Roblox es solo la vista: un Tool por tipo, apilado ("Raro x3").
-- Inventory.Add(player, item, amount) / Inventory.Count(player, item)
-- ponytail: solo en memoria; guardar/cargar con DataStore y perder al morir lo decide Economy/Progression.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)

local PREFIX = "Inv_"

local function findTool(player: Player, item: string): Tool?
	for _, container in { player:FindFirstChild("Backpack"), player.Character } do
		for _, t in container:GetChildren() do
			if t:IsA("Tool") and t:GetAttribute("Item") == item then return t end
		end
	end
	return nil
end

local function buildTool(item: string): Tool
	local tool = Instance.new("Tool")
	tool:SetAttribute("Item", item)
	tool.CanBeDropped = false
	tool.ToolTip = item

	local handle = Instance.new("Part") -- placeholder; sustituir por el modelo del Marketplace de cada material
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 1.2, 0.6)
	handle.Material, handle.Color = Enum.Material.Neon, Minerals[item].Color
	handle.CanCollide = false
	handle.Parent = tool
	return tool
end

-- deja la barra igual que los atributos: crea, actualiza o quita el slot de ese item
local function sync(player: Player, item: string)
	local count = player:GetAttribute(PREFIX .. item) or 0
	local tool = findTool(player, item)
	if count <= 0 then
		if tool then tool:Destroy() end
		return
	end
	if not tool then
		local backpack = player:FindFirstChild("Backpack")
		if not backpack then return end
		tool = buildTool(item)
		tool.Parent = backpack
	end
	tool.Name = `{item} x{count}`
end

local Inventory = {}

function Inventory.Add(player: Player, item: string, amount: number)
	player:SetAttribute(PREFIX .. item, Inventory.Count(player, item) + amount)
	sync(player, item)
end

function Inventory.Count(player: Player, item: string): number
	return player:GetAttribute(PREFIX .. item) or 0
end

function Inventory.Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait() -- Roblox recrea la mochila al reaparecer; reponemos los slots
			player:WaitForChild("Backpack")
			for item in Minerals do sync(player, item) end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do onPlayer(p) end
end

return Inventory
