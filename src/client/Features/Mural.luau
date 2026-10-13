-- Mural de exhibición (server/Features/Mural): en este cliente los minerales de las vitrinas giran y flotan despacio
-- (solo los cercanos a la cámara), y el aviso "Exhibir otro mineral" solo lo ve el dueño de esa base.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local SPIN = 25 -- grados por segundo
local BOB = 0.15 -- studs de flotación
local NEAR = 140 -- solo se animan a esta distancia de la cámara

-- el aviso solo para el dueño del estand (atributo Owner = UserId en el modelo del estand)
local function watchPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then return end
	local stand = prompt:FindFirstAncestorOfClass("Model")
	while stand and not string.match(stand.Name, "^MuralStand") do
		stand = stand.Parent and stand.Parent:FindFirstAncestorOfClass("Model")
	end
	if not stand then return end
	local function refresh()
		prompt.Enabled = stand:GetAttribute("Owner") == player.UserId
	end
	stand:GetAttributeChangedSignal("Owner"):Connect(refresh)
	refresh()
end

return {
	Start = function()
		CollectionService:GetInstanceAddedSignal("MuralPrompt"):Connect(watchPrompt)
		for _, prompt in CollectionService:GetTagged("MuralPrompt") do watchPrompt(prompt) end

		RunService.RenderStepped:Connect(function()
			local t = os.clock()
			local camera = workspace.CurrentCamera.CFrame.Position
			for _, exhibit in CollectionService:GetTagged("MuralExhibit") do
				local base = exhibit:GetAttribute("Base")
				if typeof(base) == "CFrame" and exhibit:IsA("PVInstance") and (base.Position - camera).Magnitude < NEAR then
					exhibit:PivotTo(base * CFrame.new(0, math.sin(t * 1.4) * BOB, 0) * CFrame.Angles(0, math.rad(t * SPIN), 0))
				end
			end
		end)
	end,
}
