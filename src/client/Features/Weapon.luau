-- Mira fija al centro de la pantalla; mantener clic izquierdo dispara el arma equipada.
-- El rayo real sale de la boca del arma (lo traza el servidor) hacia el punto que cubre la mira.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config.Weapon)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local held, firing = false, false

local function buildCrosshair()
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn = "Crosshair", true, false
	local function bar(x, y, w, h)
		local f = Instance.new("Frame")
		f.AnchorPoint, f.Position = Vector2.new(0.5, 0.5), UDim2.new(0.5, x, 0.5, y)
		f.Size, f.BackgroundColor3, f.BorderSizePixel = UDim2.fromOffset(w, h), Color3.new(1, 1, 1), 0
		f.Parent = gui
	end
	bar(0, 0, 2, 2) -- punto central
	bar(0, -9, 2, 7) bar(0, 9, 2, 7) bar(-9, 0, 7, 2) bar(9, 0, 7, 2)
	gui.Parent = player:WaitForChild("PlayerGui")
end

return {
	Start = function()
		local fire, tracer = Remotes.get("Weapon_Fire"), Remotes.get("Weapon_Tracer")
		buildCrosshair()

		-- mouse fijo al centro para que la mira coincida con el cursor en 1ª y 3ª persona
		UserInputService.MouseIconEnabled = false
		RunService.RenderStepped:Connect(function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end)

		local function equipWhenGiven(character: Model)
			local hum = character:WaitForChild("Humanoid")
			local backpack = player:WaitForChild("Backpack")
			local function try(tool: Instance)
				if tool.Name == Config.ToolName then task.defer(function() hum:EquipTool(tool) end) end
			end
			backpack.ChildAdded:Connect(try)
			for _, t in backpack:GetChildren() do try(t) end
		end
		if player.Character then equipWhenGiven(player.Character) end
		player.CharacterAdded:Connect(equipWhenGiven)

		local function shoot()
			local char = player.Character
			if not (char and char:FindFirstChild(Config.ToolName)) then return end
			local cam = workspace.CurrentCamera
			local ray = cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char }
			local result = workspace:Raycast(ray.Origin, ray.Direction * Config.Range, params)
			fire:FireServer(result and result.Position or ray.Origin + ray.Direction * Config.Range)
		end

		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			held = true
			if firing then return end
			firing = true
			while held do
				shoot()
				task.wait(Config.Cooldown)
			end
			firing = false
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then held = false end
		end)

		-- trazador placeholder; reemplazar por efecto real cuando haya arte
		tracer.OnClientEvent:Connect(function(a: Vector3, b: Vector3)
			local p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
			p.Material, p.Color = Enum.Material.Neon, Color3.fromRGB(255, 220, 120)
			p.Size = Vector3.new(0.08, 0.08, (b - a).Magnitude)
			p.CFrame = CFrame.lookAt((a + b) / 2, b)
			p.Parent = workspace
			Debris:AddItem(p, 0.08)
		end)
	end,
}
