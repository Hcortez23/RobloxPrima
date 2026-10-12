-- Texto "Generando mundo..." mientras el servidor construye el terreno (workspace.WorldReady = false).
local Players = game:GetService("Players")

return {
	Start = function()
		local gui = Instance.new("ScreenGui")
		gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn, gui.DisplayOrder = "Loading", true, false, 100

		local label = Instance.new("TextLabel")
		label.Size, label.BackgroundColor3 = UDim2.fromScale(1, 1), Color3.fromRGB(14, 12, 14)
		label.Text, label.TextColor3 = "Generando mundo...", Color3.fromRGB(230, 190, 150)
		label.Font, label.TextSize = Enum.Font.GothamBold, 28
		label.Parent = gui

		local function refresh()
			gui.Enabled = workspace:GetAttribute("WorldReady") ~= true
		end
		refresh()
		workspace:GetAttributeChangedSignal("WorldReady"):Connect(refresh)
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end,
}
