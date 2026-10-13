-- Ambiente por bioma y aviso de bioma (Config/Biomes, shared/BiomeMap): según dónde esté la cámara, la luz ambiental y
-- el tinte cambian suavemente al pasar de un bioma a otro (cada capa tiene 4, repartidos alrededor del pozo), y al
-- entrar en un bioma o capa nueva aparece su nombre unos segundos ("CAPA 3 · Caverna Magnética"). En la zona común de
-- arriba (cuevas del foso y de las bases) no hay bioma. Solo en este cliente; la roca la pinta el servidor.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BiomeMap = require(ReplicatedStorage.Shared.BiomeMap)
local WorldConfig = require(ReplicatedStorage.Shared.Config.World)

local FADE = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local BANNER_TIME = 3.5 -- segundos que se ve el nombre de la capa

-- Aviso centrado arriba: capa y bioma, y debajo el tema, el nombre de la capa y su dureza.
local function buildBanner(): (ScreenGui, TextLabel, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LayerBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0.12, 0)
	title.Size = UDim2.fromOffset(700, 46)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = title
	title.Parent = gui
	local subtitle = title:Clone()
	subtitle.Position = UDim2.new(0.5, 0, 0.12, 50)
	subtitle.Size = UDim2.fromOffset(620, 26)
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextColor3 = Color3.fromRGB(230, 180, 40)
	subtitle.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui, title, subtitle
end

return {
	Start = function()
		-- la luz ambiental del modo de ambiente (la pone el servidor); los biomas sin Ambient vuelven a ella
		task.wait(2)
		local defaultAmbient = Lighting.Ambient
		local tint = Instance.new("ColorCorrectionEffect")
		tint.Name = "BiomeTint"
		tint.Parent = Lighting
		local banner, title, subtitle = buildBanner()

		local currentBiome, currentLayer, shownAt = nil, nil, 0
		local first = true
		local lastSeen = nil -- bioma de la muestra anterior: un cambio cuenta si se repite (sin parpadeo en los bordes)
		while true do
			local layer, biome = BiomeMap.At(workspace.CurrentCamera.CFrame.Position)
			local stable = biome == lastSeen or first
			lastSeen = biome
			if stable and (biome ~= currentBiome or (biome and layer ~= currentLayer)) then
				if biome ~= currentBiome then
					TweenService:Create(Lighting, FADE, { Ambient = if biome then biome.Ambient else defaultAmbient }):Play()
					TweenService:Create(tint, FADE, { TintColor = if biome then biome.Tint else Color3.new(1, 1, 1) }):Play()
				end
				currentBiome, currentLayer = biome, layer
				-- el aviso sale al entrar en un bioma (no al aparecer, ni al volver a la zona común)
				if biome and not first then
					local info = WorldConfig.Layers[layer]
					title.Text = `CAPA {layer} · {biome.Name}`
					subtitle.Text = `{biome.Theme}  ·  {info.Name}  ·  dureza {info.Hardness}`
					banner.Enabled = true
					shownAt = os.clock()
				end
			end
			first = false
			if banner.Enabled and os.clock() - shownAt > BANNER_TIME then
				banner.Enabled = false
			end
			task.wait(0.3)
		end
	end,
}
