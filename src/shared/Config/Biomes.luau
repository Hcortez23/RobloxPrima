-- Biomas: 5 biomas de 4 capas cada uno (20 capas, de arriba hacia el núcleo). Cada bioma tiene su propio material de
-- roca (Material + Color, los pinta el servidor en World) y su ambiente (Ambient = luz ambiental, Tint = tinte; el
-- cliente los cambia suavemente al bajar y muestra el nombre de cada capa al entrar, en client/Features/Biomes).
-- Profundidad, dureza, rareza y cantidad de minerales de cada capa se calculan en Config/World.
-- Cada bioma debe usar un material distinto: Roblox colorea el terreno por material, no por zona.
local Biomes = {
	{
		Name = "Corteza en ruinas",
		LayerNames = { "Sótanos colapsados", "Galerías de escombro", "Vetas de ceniza", "Fosas de chatarra" },
		Material = Enum.Material.Rock,
		Color = Color3.fromRGB(92, 86, 84), -- roca gris con ceniza
		Ambient = nil, -- usa la luz ambiental del modo de ambiente (Config/Ambience)
		Tint = Color3.fromRGB(255, 255, 255),
	},
	{
		Name = "Salares de cristal",
		LayerNames = { "Llanuras de sal", "Geodas rosadas", "Bosque de prismas", "Cámara de ecos" },
		Material = Enum.Material.Salt,
		Color = Color3.fromRGB(226, 208, 214), -- blanco rosado
		Ambient = Color3.fromRGB(185, 176, 200), -- brillo frío
		Tint = Color3.fromRGB(246, 236, 255),
	},
	{
		Name = "Criogrietas",
		LayerNames = { "Grietas de escarcha", "Glaciar enterrado", "Lagos congelados", "Corazón de hielo" },
		Material = Enum.Material.Glacier,
		Color = Color3.fromRGB(150, 200, 232), -- hielo azul
		Ambient = Color3.fromRGB(140, 176, 212), -- ambiente helado
		Tint = Color3.fromRGB(222, 240, 255),
	},
	{
		Name = "Basalto ferroso",
		LayerNames = { "Coladas de basalto", "Minas de hierro", "Forja olvidada", "Columnas negras" },
		Material = Enum.Material.Basalt,
		Color = Color3.fromRGB(58, 46, 44), -- roca oscura oxidada
		Ambient = Color3.fromRGB(150, 112, 98),
		Tint = Color3.fromRGB(255, 228, 212),
	},
	{
		Name = "Manto incandescente",
		LayerNames = { "Brasas dormidas", "Ríos de magma", "Cámara de presión", "Umbral del núcleo" },
		Material = Enum.Material.CrackedLava,
		Color = Color3.fromRGB(70, 36, 30), -- roca agrietada sobre lava
		Ambient = Color3.fromRGB(200, 118, 76), -- luz naranja, cerca del núcleo
		Tint = Color3.fromRGB(255, 214, 186),
	},
}

-- Layers = { primera, última }: rango de capas de cada bioma, en orden.
local nextLayer = 1
for _, biome in Biomes do
	biome.Layers = { nextLayer, nextLayer + #biome.LayerNames - 1 }
	nextLayer += #biome.LayerNames
end

return Biomes
