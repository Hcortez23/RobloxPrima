-- Inicia en 1ª persona; la rueda del ratón aleja a 3ª persona (y vuelve a 1ª al acercar).
-- Guardia de paredes: el desplazamiento sobre el hombro (Humanoid.CameraOffset, Weapon.luau) se aplica después de que
-- Roblox aparta la cámara de las paredes, así que podía quedar dentro de la roca y dejar ver fuera del mundo. Cada
-- frame, justo después de la cámara de Roblox, se lanza una esfera de la cabeza hacia la cámara y, si choca, la
-- cámara se acerca hasta quedar delante de la pared.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local MAX_ZOOM = 12
local GUARD_RADIUS = 0.6 -- grosor de la esfera (cubre el plano cercano de la cámara)

local function firstPerson()
	-- ponytail: truco de zoom (clamp a 0.5 un instante); si Roblox cambia el comportamiento, usar CameraMode = LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	task.wait(0.1)
	player.CameraMaxZoomDistance = MAX_ZOOM
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true -- solo paredes de verdad (no decoración, ni el vidrio sin colisión)

local function guard()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head then return end
	local focus = head.Position
	local offset = camera.CFrame.Position - focus
	local distance = offset.Magnitude
	if distance < 0.8 then return end -- 1ª persona
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Spherecast(focus, GUARD_RADIUS, offset, params)
	if hit then
		local safe = focus + offset.Unit * math.max(hit.Distance - 0.1, 0)
		camera.CFrame = CFrame.new(safe) * camera.CFrame.Rotation
	end
end

return {
	Start = function()
		player.CameraMode = Enum.CameraMode.Classic
		firstPerson()
		player.CharacterAdded:Connect(firstPerson)
		RunService:BindToRenderStep("CameraWallGuard", Enum.RenderPriority.Camera.Value + 1, guard)
	end,
}
