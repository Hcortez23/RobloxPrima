-- Mantener clic izquierdo para disparar hacia donde apunta el cursor/mira (sirve en 1ª y 3ª persona).
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config.Weapon)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local held, firing = false, false

return {
	Start = function()
		local fire, tracer = Remotes.get("Weapon_Fire"), Remotes.get("Weapon_Tracer")

		local function shoot()
			local m = UserInputService:GetMouseLocation()
			local ray = workspace.CurrentCamera:ViewportPointToRay(m.X, m.Y)
			fire:FireServer(ray.Origin, ray.Direction)
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
