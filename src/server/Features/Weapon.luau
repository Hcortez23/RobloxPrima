-- Hitscan. Valida el disparo y publica el impacto: Weapon.Hit:Connect(function(player, position, normal, instance) end)
-- Otras features (Fracture, etc.) se suscriben a Hit; Weapon no sabe qué es "Fracturable".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Weapon)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local hitEvent = Instance.new("BindableEvent")
local lastFire: { [Player]: number } = {}

return {
	Hit = hitEvent.Event,

	Start = function()
		local fire, tracer = Remotes.get("Weapon_Fire"), Remotes.get("Weapon_Tracer")

		fire.OnServerEvent:Connect(function(player, origin, direction)
			if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then return end
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not (root and hum and hum.Health > 0) then return end
			if (origin - root.Position).Magnitude > Config.MaxOriginOffset then return end

			local now = os.clock()
			if now - (lastFire[player] or 0) < Config.Cooldown * 0.9 then return end
			lastFire[player] = now

			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char }
			local dir = direction.Unit * Config.Range
			local result = workspace:Raycast(origin, dir, params)

			tracer:FireAllClients(origin, result and result.Position or origin + dir)
			if result then hitEvent:Fire(player, result.Position, result.Normal, result.Instance) end
		end)

		Players.PlayerRemoving:Connect(function(p) lastFire[p] = nil end)
	end,
}
