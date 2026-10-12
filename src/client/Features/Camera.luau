-- Inicia en 1ª persona; la rueda del ratón aleja a 3ª persona (y vuelve a 1ª al acercar).
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local MAX_ZOOM = 12

local function firstPerson()
	-- ponytail: truco de zoom (clamp a 0.5 un instante); si Roblox cambia el comportamiento, usar CameraMode = LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	task.wait(0.1)
	player.CameraMaxZoomDistance = MAX_ZOOM
end

return {
	Start = function()
		player.CameraMode = Enum.CameraMode.Classic
		firstPerson()
		player.CharacterAdded:Connect(firstPerson)
	end,
}
