-- Parámetros del mundo (foso circular hacia el núcleo, hecho con Terrain). Todo en studs.
-- Seed = nil usa la fecha UTC (el mundo "se reinicia" cada día); pon un número fijo para depurar el mismo mundo.
return {
	Seed = nil,

	HalfSize = 256, -- el mundo ocupa [-HalfSize, HalfSize) en X y Z (múltiplo de 128)
	Depth = 208, -- hacia el núcleo, bajo y = 0

	PitCenter = Vector2.new(0, 150), -- (x, z) del centro del foso
	PitRadius = 90,
	PitDepth = 60, -- profundidad del foso en su centro

	SpawnPosition = Vector3.new(0, 0.8, -110), -- en la meseta, lejos del foso

	-- Cuevas naturales: túneles (dos ruidos que se cruzan) + cavernas (un ruido). Lo "abierto" se reduce con la profundidad.
	CaveMinDepth = 8, -- bajo la superficie local no hay cuevas, para que la meseta no se agujeree sola
	TunnelWidth = { 0.10, 0.045 }, -- { en la superficie, en el núcleo }; más alto = túneles más anchos
	CavernThreshold = { 0.30, 0.50 }, -- más bajo = más cavernas
	NoiseScale = 1 / 35, -- más bajo = cuevas más grandes y suaves

	-- Accesos garantizados: pozos verticales con una cámara al fondo.
	PlateauEntrances = 8, -- en la meseta, a poca profundidad (fáciles)
	PitShafts = 4, -- en el fondo del foso, más profundos

	-- Capas hacia el núcleo (profundidad bajo y = 0). Rareza = pesos al elegir qué mineral aparece ahí.
	Layers = {
		{ MaxDepth = 70, SpawnWeight = 50, Rarity = { Comun = 80, Raro = 18, Epico = 2 } },
		{ MaxDepth = 140, SpawnWeight = 35, Rarity = { Comun = 40, Raro = 40, Epico = 18, Legendario = 2 } },
		{ MaxDepth = 208, SpawnWeight = 15, Rarity = { Raro = 30, Epico = 50, Legendario = 20 } },
	},
	-- Material del terreno según la profundidad.
	Materials = {
		{ 70, Enum.Material.Rock },
		{ 140, Enum.Material.Slate },
		{ 190, Enum.Material.Basalt },
		{ math.huge, Enum.Material.CrackedLava },
	},

	-- Pool de minerales: se mantienen MineralCount en el mundo y se reponen por lotes.
	MineralCount = 150,
	RespawnInterval = 30, -- segundos entre reposiciones
	RespawnBatch = 10,
	ClusterSizes = { 1, 1, 1, 2, 3, 4 }, -- tamaños posibles de grupo (se elige uno al azar)

	CarveFactor = 0.6, -- las explosiones de minerales excavan el terreno con radio = ExplosionRadius * CarveFactor
}
