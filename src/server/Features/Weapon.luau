-- Hitscan desde la boca del arma (Tool en la mano). El cliente solo manda hacia dónde apunta;
-- el origen lo toma el servidor del Muzzle. Hit: Weapon.Hit:Connect(function(player, position, normal, instance) end)
-- Otras features (Fracture, etc.) se suscriben a Hit; Weapon no sabe qué es "Fracturable".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Weapon)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local hitEvent = Instance.new("BindableEvent")
local lastFire: { [Player]: number } = {}

-- Arma placeholder hecha de Parts; reemplazar por modelo real conservando Handle y Handle.Muzzle.
local function buildTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = Config.ToolName
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, 0, 0.6)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 0.5, 2)
	handle.Color = Color3.fromRGB(35, 38, 45)
	handle.Material = Enum.Material.Metal
	handle.Parent = tool

	local barrel = Instance.new("Part")
	barrel.Size = Vector3.new(0.15, 0.15, 0.9)
	barrel.Color = Color3.fromRGB(80, 85, 95)
	barrel.Material = Enum.Material.Metal
	barrel.CanCollide, barrel.Massless = false, true
	barrel.CFrame = handle.CFrame * CFrame.new(0, 0.1, -1.4)
	barrel.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = handle, barrel
	weld.Parent = barrel

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.1, -1.9)
	muzzle.Parent = handle
	return tool
end

return {
	Hit = hitEvent.Event,

	Start = function()
		-- El rifle se entrega al aparecer cada personaje (sin StarterPack, para no depender del orden de arranque).
		local template = buildTool()
		local function give(player: Player)
			local backpack = player:WaitForChild("Backpack")
			local char = player.Character
			if backpack:FindFirstChild(Config.ToolName) or (char and char:FindFirstChild(Config.ToolName)) then return end
			template:Clone().Parent = backpack
		end
		local function onPlayer(player: Player)
			player.CharacterAdded:Connect(function()
				task.wait()
				give(player)
			end)
			if player.Character then task.spawn(give, player) end
		end
		Players.PlayerAdded:Connect(onPlayer)
		for _, p in Players:GetPlayers() do onPlayer(p) end

		local fire, tracer = Remotes.get("Weapon_Fire"), Remotes.get("Weapon_Tracer")

		-- aim: punto del mundo al que apunta la mira del jugador
		fire.OnServerEvent:Connect(function(player, aim)
			if typeof(aim) ~= "Vector3" then return end
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local tool = char and char:FindFirstChild(Config.ToolName)
			local muzzle = tool and tool:FindFirstChild("Muzzle", true)
			if not (hum and hum.Health > 0 and muzzle) then return end

			local origin = muzzle.WorldPosition
			local toAim = aim - origin
			if toAim.Magnitude < 0.5 then return end

			local now = os.clock()
			if now - (lastFire[player] or 0) < Config.Cooldown * 0.9 then return end
			lastFire[player] = now

			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char }
			local dir = toAim.Unit * Config.Range
			local result = workspace:Raycast(origin, dir, params)

			tracer:FireAllClients(origin, result and result.Position or origin + dir)
			if result then hitEvent:Fire(player, result.Position, result.Normal, result.Instance) end
		end)

		Players.PlayerRemoving:Connect(function(p) lastFire[p] = nil end)
	end,
}
