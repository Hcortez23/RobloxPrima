-- HUD mínimo del inventario (esquina inferior izquierda): cantidad por rareza. UI final se hace después.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Minerals = require(ReplicatedStorage.Shared.Config.Minerals)

local PREFIX = "Inv_"
local player = Players.LocalPlayer

return {
	Start = function()
		local gui = Instance.new("ScreenGui")
		gui.Name, gui.ResetOnSpawn = "InventoryHud", false

		local list = Instance.new("Frame")
		list.AnchorPoint, list.Position = Vector2.new(0, 1), UDim2.new(0, 16, 1, -16)
		list.Size, list.AutomaticSize = UDim2.fromOffset(140, 0), Enum.AutomaticSize.Y
		list.BackgroundColor3, list.BackgroundTransparency = Color3.new(0, 0, 0), 0.5
		list.Parent = gui
		Instance.new("UIListLayout").Parent = list
		Instance.new("UIPadding", list).PaddingLeft = UDim.new(0, 8)

		local sorted = {}
		for name in Minerals do table.insert(sorted, name) end
		table.sort(sorted, function(a, b) return Minerals[a].Value < Minerals[b].Value end)

		local labels = {}
		for _, name in sorted do
			local l = Instance.new("TextLabel")
			l.Size, l.BackgroundTransparency = UDim2.new(1, 0, 0, 22), 1
			l.TextXAlignment, l.Font, l.TextSize = Enum.TextXAlignment.Left, Enum.Font.GothamBold, 16
			l.TextColor3 = Minerals[name].Color
			l.Parent = list
			labels[name] = l
		end

		local function refresh(name: string)
			labels[name].Text = `{name}: {player:GetAttribute(PREFIX .. name) or 0}`
		end
		for name in labels do refresh(name) end
		player.AttributeChanged:Connect(function(attr)
			local name = attr:match("^" .. PREFIX .. "(.+)$")
			if name and labels[name] then refresh(name) end
		end)

		gui.Parent = player:WaitForChild("PlayerGui")
	end,
}
