-- Mira fija al centro de la pantalla (1ª y 3ª persona, estilo Fortnite) mientras hay arma o gancho en la mano.
-- Mantener clic izquierdo dispara el arma equipada; el rayo real sale de la boca del arma (lo traza el
-- servidor) hacia el punto que cubre la mira.
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
	-- contenedor que se mueve a la posición del mouse; las barras van centradas en él
	local center = Instance.new("Frame")
	center.Name, center.Size, center.BackgroundTransparency = "Center", UDim2.fromOffset(0, 0), 1
	center.Parent = gui
	local function bar(x, y, w, h)
		local f = Instance.new("Frame")
		f.AnchorPoint, f.Position = Vector2.new(0.5, 0.5), UDim2.new(0.5, x, 0.5, y)
		f.Size, f.BackgroundColor3, f.BorderSizePixel = UDim2.fromOffset(w, h), Color3.new(1, 1, 1), 0
		f.Parent = center
	end
	bar(0, 0, 2, 2) -- punto central
	bar(0, -9, 2, 7) bar(0, 9, 2, 7) bar(-9, 0, 7, 2) bar(9, 0, 7, 2)
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, center
end

-- ponytail: 1ª persona = cámara casi pegada a su foco (Camera.luau la acerca a 0.5)
local function isFirstPerson(): boolean
	local cam = workspace.CurrentCamera
	return (cam.CFrame.Position - cam.Focus.Position).Magnitude < 1
end

-- la mira solo se ve con el arma o con un Tool que tenga el atributo "Crosshair" (ej. el gancho) en la mano
local function wantsCrosshair(character: Model): boolean
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and (child.Name == Config.ToolName or child:GetAttribute("Crosshair")) then
			return true
		end
	end
	return false
end

return {
	Start = function()
		local fire, tracer = Remotes.get("Weapon_Fire"), Remotes.get("Weapon_Tracer")
		local crosshair, crosshairCenter = buildCrosshair()
		local function watchCrosshair(character: Model)
			local function update() crosshair.Enabled = wantsCrosshair(character) end
			character.ChildAdded:Connect(update)
			character.ChildRemoved:Connect(update)
			update()
		end
		if player.Character then watchCrosshair(player.Character) end
		player.CharacterAdded:Connect(watchCrosshair)

		-- Con arma/gancho en la mano (mira visible), en 1ª y 3ª persona: mouse fijo al centro y la mira siempre
		-- en el centro, como en Fortnite; en 3ª el personaje mira hacia donde apunta la cámara.
		-- Sin arma en 3ª persona: mouse libre y cursor normal.
		RunService.RenderStepped:Connect(function()
			local cam = workspace.CurrentCamera
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local first, armed = isFirstPerson(), crosshair.Enabled

			if first or armed then
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				UserInputService.MouseIconEnabled = false
			else
				-- clic derecho sostenido = la cámara de Roblox está girando; no pisarle el mouse
				if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end
				UserInputService.MouseIconEnabled = true
			end
			crosshairCenter.Position = UDim2.fromOffset(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)

			if hum and root and hum.Health > 0 then
				local turn = armed and not first
				hum.AutoRotate = not turn
				local look = cam.CFrame.LookVector
				if turn and Vector3.new(look.X, 0, look.Z).Magnitude > 0.01 then
					root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(look.X, 0, look.Z))
				end
			end
		end)

		-- solo la primera vez por vida: al cambiar a otro slot el arma vuelve a la mochila y no debe re-equiparse
		local function equipWhenGiven(character: Model)
			local hum = character:WaitForChild("Humanoid")
			local backpack = player:WaitForChild("Backpack")
			local equipped = false
			local function try(tool: Instance)
				if equipped or tool.Name ~= Config.ToolName then return end
				equipped = true
				task.defer(function() hum:EquipTool(tool) end)
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
			local mouse = cam.ViewportSize / 2 -- la mira siempre está en el centro
			local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
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
