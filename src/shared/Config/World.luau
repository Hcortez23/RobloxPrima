-- Parámetros del mundo (meseta con un pozo directo al núcleo, hecho con Terrain). Todo en studs.
-- Seed = nil usa la fecha UTC (el mundo "se reinicia" cada día); pon un número fijo para depurar el mismo mundo.
return {
	Seed = nil,

	HalfSize = 384, -- el mundo ocupa [-HalfSize, HalfSize) en X y Z (múltiplo de 128)
	Depth = 800, -- hacia el núcleo, bajo y = 0

	-- El gran pozo: estrecho y vertical, un vistazo directo al núcleo (nadie debería bajar por aquí).
	PitCenter = Vector2.new(0, 0), -- (x, z)
	PitRadius = 42,
	PitRagged = 7, -- cuánto se desordena el borde y las paredes (roca irregular)
	CoreHeight = 14, -- grosor de roca sólida al fondo; sobre ella flota el núcleo

	SpawnPosition = Vector3.new(0, 0.8, -105), -- en la meseta, a la vista del pozo (punto invisible)

	-- Cuevas naturales: túneles (dos ruidos que se cruzan) + cavernas (un ruido). Lo "abierto" se reduce con la profundidad.
	CaveMinDepth = 8, -- bajo la superficie no hay cuevas, para que la meseta no se agujeree sola
	TunnelWidth = { 0.10, 0.045 }, -- { en la superficie, en el núcleo }; más alto = túneles más anchos
	CavernThreshold = { 0.30, 0.50 }, -- más bajo = más cavernas
	NoiseScale = 1 / 35, -- más bajo = cuevas más grandes y suaves

	-- Entradas repartidas por la meseta, todas con una cámara al fondo.
	PlateauRamps = 10, -- rampas inclinadas que se pueden caminar hacia abajo
	PlateauShafts = 8, -- pozos verticales poco profundos

	-- Capas hacia el núcleo (profundidad bajo y = 0). Rareza = pesos al elegir qué mineral aparece ahí.
	Layers = {
		{ MaxDepth = 270, SpawnWeight = 50, Rarity = { Comun = 80, Raro = 18, Epico = 2 } },
		{ MaxDepth = 540, SpawnWeight = 35, Rarity = { Comun = 40, Raro = 40, Epico = 18, Legendario = 2 } },
		{ MaxDepth = 800, SpawnWeight = 15, Rarity = { Raro = 30, Epico = 50, Legendario = 20 } },
	},
	-- Material del terreno según la profundidad.
	Materials = {
		{ 200, Enum.Material.Rock },
		{ 420, Enum.Material.Slate },
		{ 680, Enum.Material.Basalt },
		{ math.huge, Enum.Material.CrackedLava },
	},

	-- Iluminación del subsuelo: cristales luminosos sobre el suelo de las cuevas (un color por capa).
	LightCount = 420,
	LightColors = { Color3.fromRGB(90, 220, 255), Color3.fromRGB(170, 110, 255), Color3.fromRGB(255, 150, 60) },
	LightRange = 30,

	-- Núcleo visible al fondo del pozo.
	CoreColor = Color3.fromRGB(255, 110, 30),
	CoreRadius = 28,

	-- Pool de minerales: se mantienen MineralCount en el mundo y se reponen por lotes.
	MineralCount = 260,
	SurfaceMinerals = 25, -- repartidos por la meseta (a la vista, para probar rápido)
	NearSpawnMinerals = 8, -- además, unos cuantos cerca del spawn
	RespawnInterval = 30, -- segundos entre reposiciones
	RespawnBatch = 10,
	ClusterSizes = { 1, 1, 1, 2, 3, 4 }, -- tamaños posibles de grupo (se elige uno al azar)

	CarveFactor = 0.6, -- las explosiones de minerales excavan el terreno con radio = ExplosionRadius * CarveFactor
}
