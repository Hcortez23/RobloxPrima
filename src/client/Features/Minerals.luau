-- Efectos de la explosión de un mineral: destello, onda expansiva, chispas, luz y temblor de cámara.
-- Cuando haya sonido/arte final, se añade aquí; la lógica del servidor no cambia.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local function newPart(pos: Vector3, color: Color3, shape: Enum.PartType, size: Vector3, transparency: number)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material, p.Color, p.Shape, p.Size, p.Transparency = Enum.Material.Neon, color, shape, size, transparency
	p.Position = pos
	p.Parent = workspace
	return p
end

local function expand(part: BasePart, size: Vector3, time: number)
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = size,
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, time)
end

local function shake(pos: Vector3, radius: number)
	local char = Players.LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return end
	local power = math.clamp(1 - (root.Position - pos).Magnitude / (radius * 4), 0, 1) * 0.9
	if power <= 0 then return end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = 1 - (os.clock() - t0) / 0.35
		if k <= 0 then
			hum.CameraOffset = Vector3.zero
			conn:Disconnect()
			return
		end
		hum.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 2 * power * k
	end)
end

local function explosion(pos: Vector3, color: Color3, radius: number)
	local hot = color:Lerp(Color3.new(1, 1, 1), 0.6)

	expand(newPart(pos, hot, Enum.PartType.Ball, Vector3.one * 2, 0.1), Vector3.one * radius * 1.6, 0.35) -- destello

	local ring = newPart(pos, color, Enum.PartType.Cylinder, Vector3.new(0.4, 2, 2), 0.2) -- onda expansiva
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	expand(ring, Vector3.new(0.4, radius * 3, radius * 3), 0.5)

	local emitterPart = newPart(pos, color, Enum.PartType.Ball, Vector3.one, 1) -- chispas + luz
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(hot, color)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.5, 1.1)
	sparks.Speed = NumberRange.new(25, 70)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.LightEmission = 1
	sparks.Rate = 0
	sparks.Parent = emitterPart
	sparks:Emit(60)
	Debris:AddItem(emitterPart, 1.5)

	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = color, radius * 2, 8
	light.Parent = emitterPart
	TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()

	shake(pos, radius)
end

return {
	Start = function()
		Remotes.get("Minerals_Explosion").OnClientEvent:Connect(explosion)
	end,
}
