-- Ambiente del mundo según Config.Ambience.Mode:
--  · "Prueba": de día, luz neutra y sin bruma, para ver bien el terreno mientras se ajusta.
--  · "Apocaliptico": luz rasante cálida, tonos morados, nubes pesadas y colores sucios donde el neón destaca.
-- En los dos, el cielo es del color del núcleo y la luz ambiental es alta para que las cuevas no queden oscuras.
-- Todo se crea por código para poder afinarlo aquí en un solo sitio.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Ambience)
local WorldConfig = require(ReplicatedStorage.Shared.Config.World)


local function child(parent: Instance, className: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	for k, v in props do (inst :: any)[k] = v end
	inst.Parent = parent
	return inst
end

-- Cielo del color del núcleo: lo pinta la atmósfera (no cambia la luz del mundo) y se ocultan sol, luna y estrellas
-- para que quede un color liso. La atmósfera se dibuja en cualquier calidad de gráficos.
local function coreSky(density: number)
	local core = WorldConfig.CoreColor
	child(Lighting, "Sky", { CelestialBodiesShown = false, StarCount = 0 })
	child(Lighting, "Atmosphere", {
		Density = density,
		Offset = 0.6, -- concentra el color en el cielo y el horizonte, poco en lo cercano
		Color = core,
		Decay = core:Lerp(Color3.new(0, 0, 0), 0.35), -- un poco más oscuro hacia arriba
		Glare = 0,
		Haze = 0,
	})
end

local function testing()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.ExposureCompensation = 0
	Lighting.Ambient = Color3.fromRGB(175, 170, 165) -- luz pareja que llega a todo, también al fondo de las cuevas (sin fuentes de luz)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 132)
	Lighting.ColorShift_Top = Color3.new(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	coreSky(0.3)
	child(Lighting, "BloomEffect", { Intensity = 0.5, Size = 24, Threshold = 0.95 }) -- el neón se nota un poco
end

local function apocalyptic()
	-- sol en el horizonte: luz rasante y cálida, sombras largas
	Lighting.ClockTime = 18.1
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 1.3
	Lighting.ExposureCompensation = -0.3
	Lighting.Ambient = Color3.fromRGB(105, 88, 118) -- luz pareja que llega al fondo de las cuevas, con tono morado
	Lighting.OutdoorAmbient = Color3.fromRGB(78, 58, 92)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 176, 92) -- luz del sol amarilla-naranja
	Lighting.ColorShift_Bottom = Color3.fromRGB(96, 64, 138) -- rebote morado desde el cielo
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true

	coreSky(0.42)
	child(Lighting, "ColorCorrection", { -- colores sucios, contraste duro, ligero tinte morado
		Saturation = -0.12,
		Contrast = 0.22,
		Brightness = -0.03,
		TintColor = Color3.fromRGB(238, 222, 255),
	})
	child(Lighting, "BloomEffect", { Intensity = 0.85, Size = 30, Threshold = 0.88 }) -- el neón brilla
	child(Lighting, "SunRaysEffect", { Intensity = 0.2, Spread = 0.55 })

	local terrain = workspace.Terrain
	-- ceniza en la superficie
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(74, 64, 66))
	-- el color de la roca de las capas lo pone cada bioma (Config/Biomes)
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
