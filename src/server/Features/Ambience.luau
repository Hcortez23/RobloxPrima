-- Ambiente postapocalíptico sci-fi: atardecer polvoriento, bruma ocre, colores apagados y neón que destaca.
-- Todo se crea por código para poder afinarlo aquí en un solo sitio.
local Lighting = game:GetService("Lighting")

local function child(parent: Instance, className: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	for k, v in props do (inst :: any)[k] = v end
	inst.Parent = parent
	return inst
end

return {
	Start = function()
		Lighting.ClockTime = 17.3 -- sol bajo, luz naranja rasante
		Lighting.Brightness = 1.8
		Lighting.ExposureCompensation = -0.15
		Lighting.Ambient = Color3.fromRGB(38, 32, 38) -- el subsuelo no queda negro del todo
		Lighting.OutdoorAmbient = Color3.fromRGB(92, 74, 68)
		Lighting.ColorShift_Top = Color3.fromRGB(255, 160, 100)
		Lighting.EnvironmentDiffuseScale = 0.5
		Lighting.EnvironmentSpecularScale = 0.35

		child(Lighting, "Atmosphere", { -- bruma de polvo
			Density = 0.42,
			Offset = 0.3,
			Color = Color3.fromRGB(205, 160, 125),
			Decay = Color3.fromRGB(120, 88, 70),
			Glare = 0.45,
			Haze = 2.4,
		})
		child(Lighting, "ColorCorrection", { -- colores apagados, contraste sucio
			Saturation = -0.28,
			Contrast = 0.16,
			TintColor = Color3.fromRGB(255, 232, 210),
		})
		child(Lighting, "BloomEffect", { Intensity = 0.7, Size = 28, Threshold = 0.9 }) -- el neón brilla
		child(Lighting, "SunRaysEffect", { Intensity = 0.12, Spread = 0.6 })

		local terrain = workspace.Terrain
		terrain.Decoration = false
		terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(112, 98, 86)) -- ceniza y polvo
		terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(94, 86, 84))
		terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(66, 64, 74))
		terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(42, 40, 48))
		child(terrain, "Clouds", { Cover = 0.62, Density = 0.55, Color = Color3.fromRGB(112, 96, 90) })
	end,
}
