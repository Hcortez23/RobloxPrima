-- Ambiente por bioma y aviso de capa (Config/Biomes, Config/World): según la profundidad de la cámara, la luz ambiental
-- y el tinte cambian suavemente al pasar de un bioma a otro, y al entrar en una capa nueva aparece su nombre en
-- pantalla unos segundos ("CAPA 7 · Bosque de prismas"). Solo en este cliente; la roca la pinta el servidor.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Biomes = require(ReplicatedStorage.Shared.Config.Biomes)
local WorldConfig = require(ReplicatedStorage.Shared.Config.World)

local FADE = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local BANNER_TIME = 3.5 -- segundos que se ve el nombre de la capa

local function layerAt(depth: number): number
	for i, layer in WorldConfig.Layers do
		if depth <= layer.MaxDepth then return i end
	end
	return #WorldConfig.Layers
end

local function biomeOf(layer: number)
	for _, biome in Biomes do
		if layer >= biome.Layers[1] and layer <= biome.Layers[2] then return biome end
	end
	return Biomes[1]
end

-- Aviso centrado arriba: número y nombre de la capa, y debajo el bioma.
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
	subtitle.Size = UDim2.fromOffset(500, 26)
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
		while true do
			local camera = workspace.CurrentCamera
			local depth = -camera.CFrame.Position.Y
			local layer = layerAt(depth)
			local biome = biomeOf(layer)
			if biome ~= currentBiome then
				currentBiome = biome
				TweenService:Create(Lighting, FADE, { Ambient = biome.Ambient or defaultAmbient }):Play()
				TweenService:Create(tint, FADE, { TintColor = biome.Tint }):Play()
			end
			-- el aviso sale al entrar en una capa (no en la base ni en la cueva del foso, que están en la capa 1)
			if layer ~= currentLayer then
				local first = currentLayer == nil
				currentLayer = layer
				if not first then
					local info = WorldConfig.Layers[layer]
					title.Text = `CAPA {layer} · {info.Name}`
					subtitle.Text = `{info.Biome}  ·  dureza {info.Hardness}`
					banner.Enabled = true
					shownAt = os.clock()
				end
			end
			if banner.Enabled and os.clock() - shownAt > BANNER_TIME then
				banner.Enabled = false
			end
			task.wait(0.3)
		end
	end,
}
