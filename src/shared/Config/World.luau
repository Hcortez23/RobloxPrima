-- Parámetros del mundo (meseta con un pozo directo al núcleo, hecho con Terrain). Todo en studs.
-- Seed = nil usa la fecha UTC (el mundo "se reinicia" cada día); pon un número fijo para depurar el mismo mundo.
return {
	Seed = nil,

	HalfSize = 384, -- el mundo ocupa [-HalfSize, HalfSize) en X y Z (múltiplo de 128)
	Depth = 2400, -- hacia el núcleo, bajo y = 0 (múltiplo de BandHeight)

	-- Generación progresiva: se genera por franjas de arriba hacia abajo. Los jugadores entran cuando está lista
	-- ReadyDepth; lo más profundo se genera en segundo plano mientras juegan (nadie llega tan rápido allá abajo).
	BandHeight = 200, -- alto de cada franja (múltiplo de 4)
	ReadyDepth = 600, -- profundidad generada antes de dejar entrar (múltiplo de BandHeight)

	-- El gran pozo: tubo estrecho y vertical desde el piso de la base hasta el núcleo, tapado por una rejilla (se ve el
	-- brillo del núcleo pero no se puede bajar por aquí).
	PitCenter = Vector2.new(0, 0), -- (x, z)
	PitRadius = 42,
	PitRagged = 7, -- cuánto se desordena el borde y las paredes (roca irregular)
	CoreHeight = 14, -- grosor de roca sólida al fondo; sobre ella flota el núcleo

	SpawnPosition = Vector3.new(0, -149, -275), -- en el piso de la cueva de la base (SpawnCave)

	-- Relieve de la superficie: el centro (spawn y pozo) queda plano, con lomas suaves, y hacia los bordes se
	-- levantan montañas.
	MountainHeight = 110, -- altura máxima de las montañas (múltiplo de 4)
	MountainStart = 0.45, -- fracción de HalfSize desde el centro donde empiezan a subir
	MountainScale = 1 / 90, -- tamaño de las formas de las montañas (más bajo = montañas más anchas)
	HillHeight = 8, -- lomas en la zona central
	FlatRadius = 60, -- alrededor del centro del mapa (encima de la base) todo queda plano

	-- Cueva del foso: caverna enorme bajo el centro del mapa, la entrada a la experiencia. El pozo al núcleo está en
	-- su piso tapado por una rejilla; tiene luces y máquinas industriales (server/Features/Hub). Salidas: un túnel que
	-- baja a la primera arena, otro que sube a la superficie y la gran puerta de arco hacia la cueva de la base.
	Hub = {
		Center = Vector3.new(0, -115, 0), -- centro de la caverna (encima del pozo)
		Radius = 110,
		Height = 70, -- alto del cuerpo (el piso queda en Center.Y - Height / 2); la cúpula agrega más
		DomeRadius = 48, -- bóvedas del techo
		ExitDown = Vector3.new(0, 0, 1), -- dirección (en XZ) de la salida que baja a las arenas
		ExitUp = nil, -- Vector3 para abrir una salida a la superficie (desactivada: la única salida es la de abajo)
		TunnelRadius = 10,
		Minerals = 10, -- minerales en el piso de la cueva del foso, para probar rápido
		-- La salida de abajo llega a una cámara de cruce; de ahí sale el camino a la primera arena y varios ramales.
		Junction = { Distance = 70, Drop = 60, Radius = 16, Branches = 3, BranchLength = { 70, 120 } },
	},
	-- Caparazón de roca maciza alrededor de la cueva de la base y la del foso: ahí no se abren cuevas naturales ni
	-- entradas de la superficie (las cuevas empiezan desde la cámara de cruce).
	CaveShell = 30,
	-- Cueva de la base (spawn): antes de la del foso, al mismo nivel de piso. Aquí van las bases y las tiendas.
	SpawnCave = {
		Center = Vector3.new(0, -120, -250), -- el piso queda en Center.Y - Height / 2 (igual que la cueva del foso)
		Radius = 90,
		Height = 60,
		DomeRadius = 40,
	},
	-- Pasaje entre las dos cuevas, con la gran puerta de arco del lado de la cueva del foso.
	Gate = {
		Width = 32, -- ancho del pasaje (y del arco)
		Height = 26, -- alto de las paredes rectas del pasaje; el techo abovedado agrega Width / 2
	},
	PitSeal = 18, -- grosor de roca alrededor del pozo donde no se abren cuevas (así no hay atajo al núcleo)
	CoreChamber = { Radius = 80, Height = 60 }, -- cámara final alrededor del núcleo, al fondo de la cadena de arenas
	-- Cuevas naturales: túneles (dos ruidos que se cruzan) + cavernas (un ruido). Lo "abierto" se reduce con la profundidad.
	CaveMinDepth = 8, -- bajo la superficie no hay cuevas, para que la meseta no se agujeree sola
	TunnelWidth = { 0.10, 0.05 }, -- { en la superficie, en el núcleo }; más alto = túneles más anchos
	CavernThreshold = { 0.30, 0.45 }, -- más bajo = más cavernas
	NoiseScale = 1 / 35, -- más bajo = cuevas más grandes y suaves

	-- Entradas repartidas por la meseta, todas con una cámara al fondo.
	PlateauRamps = 10, -- rampas inclinadas que se pueden caminar hacia abajo
	PlateauShafts = 8, -- pozos verticales poco profundos

	-- Cavernas-arena: grandes y verticales, para perseguir fragmentos con gancho, dash y doble salto.
	-- Una cadena de túneles las conecta de la más alta a la más profunda (la primera, a una entrada de la meseta).
	Arenas = {
		PerLayer = { 4, 4, 3, 3 }, -- cuántas en cada capa
		Radius = { 30, 46 }, -- radio (mín, máx)
		Height = { 70, 110 }, -- alto del cuerpo (mín, máx); la cúpula y el fondo agregan más
		Ledges = { 5, 9 }, -- salientes en las paredes
		Pillars = { 1, 3 }, -- pilares de piso a techo
		Stalactites = { 4, 8 },
		TunnelRadius = 8, -- túneles que las conectan
		Lights = 5, -- cristales de luz dentro de cada una
		MineralClusters = 3, -- grupos de minerales dentro de cada una
	},

	-- Capas hacia el núcleo (profundidad bajo y = 0). Rareza = pesos al elegir qué mineral aparece ahí.
	Layers = {
		{ MaxDepth = 500, SpawnWeight = 35, Rarity = { Comun = 75, Raro = 22, Epico = 3 } },
		{ MaxDepth = 1100, SpawnWeight = 30, Rarity = { Comun = 40, Raro = 40, Epico = 18, Legendario = 2 } },
		{ MaxDepth = 1750, SpawnWeight = 20, Rarity = { Raro = 35, Epico = 45, Legendario = 20 } },
		{ MaxDepth = 2400, SpawnWeight = 15, Rarity = { Raro = 10, Epico = 50, Legendario = 40 } },
	},
	-- Material del terreno según la profundidad.
	Materials = {
		{ 500, Enum.Material.Rock },
		{ 1100, Enum.Material.Slate },
		{ 1750, Enum.Material.Basalt },
		{ math.huge, Enum.Material.CrackedLava },
	},

	-- Iluminación del subsuelo: cristales luminosos sobre el suelo de las cuevas (un color por capa).
	LightCount = 700,
	LightColors = {
		Color3.fromRGB(90, 220, 255),
		Color3.fromRGB(170, 110, 255),
		Color3.fromRGB(255, 150, 60),
		Color3.fromRGB(255, 70, 50),
	},
	LightRange = 30,

	-- Núcleo visible al fondo del pozo.
	CoreColor = Color3.fromRGB(255, 110, 30),
	CoreRadius = 28,

	-- Pool de minerales: se mantienen MineralCount en el mundo y se reponen por lotes.
	MineralCount = 400,
	InitialMineralShare = 0.45, -- parte del pool que se llena antes de que entren los jugadores (zona ya generada)
	SurfaceMinerals = 25, -- repartidos por la meseta (a la vista, para probar rápido)
	RespawnInterval = 30, -- segundos entre reposiciones
	RespawnBatch = 10,
	ClusterSizes = { 1, 1, 1, 2, 3, 4 }, -- tamaños posibles de grupo (se elige uno al azar)

	CarveFactor = 0.6, -- las explosiones de minerales excavan el terreno con radio = ExplosionRadius * CarveFactor
}
