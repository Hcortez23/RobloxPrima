-- Mural de exhibición (server/Features/Mural): en este cliente los minerales de las vitrinas giran y flotan despacio
-- (solo los cercanos a la cámara), y el aviso del estand solo lo ve el dueño de esa base ("Poner <mineral> aquí" con un
-- mineral de la mochila en la mano, "Cambiar mineral" sin nada).
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

-- texto del aviso según lo que lleva en la mano: un mineral de la mochila se pone en el estand; sin nada, se cambia
local function promptText(): string
	local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	local item = tool and tool:GetAttribute("Item")
	return if typeof(item) == "string" then `Poner {item} aquí` else "Cambiar mineral"
end

return {
	Start = function()
		CollectionService:GetInstanceAddedSignal("MuralPrompt"):Connect(watchPrompt)
		for _, prompt in CollectionService:GetTagged("MuralPrompt") do watchPrompt(prompt) end
		task.spawn(function()
			while true do
				local text = promptText()
				for _, prompt in CollectionService:GetTagged("MuralPrompt") do
					if prompt:IsA("ProximityPrompt") and prompt.Enabled and prompt.ActionText ~= text then prompt.ActionText = text end
				end
				task.wait(0.3)
			end
		end)

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
