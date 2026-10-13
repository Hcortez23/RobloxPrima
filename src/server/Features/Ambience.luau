-- Ambiente del mundo según Config.Ambience.Mode:
--  · "Prueba": de día, luz neutra y sin bruma, para ver bien el terreno mientras se ajusta.
--  · "Apocaliptico": atardecer oscuro con el cielo entre morado (arriba) y amarillo-naranja (en el horizonte, junto
--    al sol), bruma de ceniza, nubes moradas y colores sucios donde el neón destaca.
-- Todo se crea por código para poder afinarlo aquí en un solo sitio.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Ambience)

local function child(parent: Instance, className: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	for k, v in props do (inst :: any)[k] = v end
	inst.Parent = parent
	return inst
end

local function testing()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.ExposureCompensation = 0
	Lighting.Ambient = Color3.fromRGB(110, 110, 115) -- las cuevas se ven sin depender de las luces
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 132)
	Lighting.ColorShift_Top = Color3.new(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	child(Lighting, "Atmosphere", { Density = 0.2, Offset = 0, Haze = 0, Glare = 0 }) -- apenas un poco de lejanía
	child(Lighting, "BloomEffect", { Intensity = 0.5, Size = 24, Threshold = 0.95 }) -- el neón se nota un poco
end

local function apocalyptic()
	-- sol en el horizonte: luz rasante y cálida, sombras largas
	Lighting.ClockTime = 18.1
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 1.3
	Lighting.ExposureCompensation = -0.3
	Lighting.Ambient = Color3.fromRGB(30, 22, 42) -- el subsuelo no queda negro del todo, con tono morado
	Lighting.OutdoorAmbient = Color3.fromRGB(78, 58, 92)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 176, 92) -- luz del sol amarilla-naranja
	Lighting.ColorShift_Bottom = Color3.fromRGB(96, 64, 138) -- rebote morado desde el cielo
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true

	-- el cielo toma su color de la atmósfera: morado oscuro arriba y resplandor amarillo cerca del sol
	child(Lighting, "Sky", {
		SunAngularSize = 24, -- sol grande y bajo
		MoonAngularSize = 9,
		StarCount = 2500, -- estrellas que asoman en la parte oscura
		CelestialBodiesShown = true,
	})
	child(Lighting, "Atmosphere", {
		Density = 0.46,
		Offset = 0.22,
		Color = Color3.fromRGB(118, 72, 150), -- bruma morada
		Decay = Color3.fromRGB(255, 184, 72), -- horizonte amarillo-naranja
		Glare = 0.85,
		Haze = 2.6,
	})
	child(Lighting, "ColorCorrection", { -- colores sucios, contraste duro, ligero tinte morado
		Saturation = -0.12,
		Contrast = 0.22,
		Brightness = -0.03,
		TintColor = Color3.fromRGB(238, 222, 255),
	})
	child(Lighting, "BloomEffect", { Intensity = 0.85, Size = 30, Threshold = 0.88 }) -- el neón brilla
	child(Lighting, "SunRaysEffect", { Intensity = 0.2, Spread = 0.55 })

	local terrain = workspace.Terrain
	-- ceniza, óxido y roca quemada
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(74, 64, 66))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(82, 72, 76))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(62, 56, 72))
	terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(40, 35, 46))
	terrain:SetMaterialColor(Enum.Material.CrackedLava, Color3.fromRGB(58, 34, 30))
	child(terrain, "Clouds", { Cover = 0.7, Density = 0.62, Color = Color3.fromRGB(88, 62, 100) }) -- nubes moradas pesadas
end

return {
	Start = function()
		if Config.Mode == "Apocaliptico" then
			apocalyptic()
		else
			testing()
		end
	end,
}
