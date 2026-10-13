-- Parámetros del mundo (Terrain generado por código en server/Features/World.luau). Todo en studs.
-- Seed = nil usa la fecha UTC (el mundo "se reinicia" cada día); pon un número fijo para depurar el mismo mundo.
local Biomes = require(script.Parent.Biomes)

local Config = {
	Seed = nil,

	HalfSize = 1024, -- el mundo ocupa [-HalfSize, HalfSize) en X y Z (múltiplo de 128)
	Depth = 8000, -- hacia el núcleo, bajo y = 0 (= LayerHeight * número de capas); si cambia, ajustar
	-- FallenPartsDestroyHeight en default.project.json (unos 800 por debajo, en negativo)
	LayerHeight = 800, -- alto de cada capa (Config/Biomes define 10 capas, con 4 biomas cada una)

	-- Generación por celdas (128 x 128 x BandHeight): antes de dejar entrar se genera la capa 1 cerca del centro (hasta
	-- ReadyDepth); la columna del pozo se completa en segundo plano y el resto se genera alrededor de los jugadores
	-- (Generation, más abajo). La roca maciza se rellena por bloques enteros (mucho más rápido que voxel a voxel).
	BandHeight = 200, -- alto de cada celda (múltiplo de 4)
	ReadyDepth = 800, -- profundidad generada antes de dejar entrar (múltiplo de BandHeight): toda la zona de cuevas

	-- El gran pozo: tubo estrecho y vertical desde el piso de la cueva del foso hasta el núcleo, tapado por una rejilla
	-- (se ve el brillo del núcleo pero no se puede bajar por aquí).
	PitCenter = Vector2.new(0, 0), -- (x, z)
	PitRadius = 42,
	PitRagged = 7, -- cuánto se desordena el borde y las paredes (roca irregular)
	CoreHeight = 14, -- grosor de roca sólida al fondo; sobre ella flota el núcleo

	SpawnPosition = Vector3.new(0, -149, -75), -- spawn general en la cueva del foso, entre dos pasajes (cada jugador aparece en su cueva-base)

	-- Relieve de la superficie: el centro queda plano, con lomas suaves, y hacia los bordes se levantan montañas.
	-- Apagado mientras la superficie no sea accesible (nadie la ve): sin él, arriba queda roca plana en y = 0 y la
	-- generación inicial es bastante más rápida.
	SurfaceRelief = false,
	MountainHeight = 110, -- altura máxima de las montañas (múltiplo de 4)
	MountainStart = 0.45, -- fracción de HalfSize desde el centro donde empiezan a subir
	MountainScale = 1 / 90, -- tamaño de las formas de las montañas (más bajo = montañas más anchas)
	HillHeight = 8, -- lomas en la zona central
	FlatRadius = 60, -- alrededor del centro del mapa todo queda plano

	-- Cueva del foso: caverna enorme bajo el centro del mapa, la zona común y la entrada a la experiencia. El pozo al
	-- núcleo está en su piso tapado por una rejilla; tiene luces y máquinas industriales (server/Features/Hub). Salidas:
	-- el portal DESCENSO (baja a la cámara de cruce) y un pasaje con arco hacia cada cueva-base (Config/Bases).
	Hub = {
		Center = Vector3.new(0, -115, 0), -- centro de la caverna (encima del pozo)
		Radius = 110,
		Height = 70, -- alto del cuerpo (el piso queda en Center.Y - Height / 2); la cúpula agrega más
		DomeRadius = 48, -- bóvedas del techo
		ExitDown = Vector3.new(0, 0, 1), -- dirección (en XZ) de la salida que baja a las arenas
		ExitUp = nil, -- Vector3 para abrir una salida a la superficie (desactivada: la única salida es la de abajo)
		TunnelRadius = 15, -- la entrada inicial: grande y visible (Hub.luau le pone un portal)
		Minerals = 10, -- minerales en el piso de la cueva del foso, para probar rápido
		-- La salida de abajo llega a una cámara de cruce; de ahí sale el camino a la primera arena y varios ramales.
		Junction = { Distance = 75, Drop = 60, Radius = 24, Branches = 4, BranchLength = { 90, 170 } },
	},
	-- Caparazón de roca maciza alrededor de la cueva del foso, las cuevas-base y sus pasajes: ahí no se abren cuevas
	-- naturales ni se puede excavar (las cuevas empiezan desde la cámara de cruce).
	CaveShell = 30,
	PitSeal = 18, -- grosor de roca alrededor del pozo donde no se abren cuevas ni se excava (sin atajo al núcleo)
	CoreChamber = { Radius = 80, Height = 60 }, -- cámara final alrededor del núcleo; se llega excavando

	-- Zona de cuevas: cuevas naturales (túneles + cavernas de ruido) y arenas, solo cerca del pozo, por debajo de la
	-- cámara de cruce y hasta CaveZoneDepth. Más abajo todo es roca maciza que se excava (server/Features/Excavation).
	CaveRadius = 560, -- distancia horizontal máxima al pozo
	CaveZoneDepth = 800, -- profundidad hasta donde hay cuevas (la capa 1; más abajo solo minas)
	TunnelWidth = { 0.155, 0.125 }, -- { arriba, abajo }; más alto = túneles más anchos
	CavernThreshold = { 0.26, 0.34 }, -- más bajo = más cavernas
	NoiseScale = 1 / 66, -- más bajo = cuevas más grandes y suaves (túneles anchos e interconectados)

	-- Entradas desde la superficie (apagadas: las cuevas solo empiezan desde la cueva inicial).
	PlateauRamps = 0,
	PlateauShafts = 0,

	-- Cavernas-arena dentro de la zona de cuevas: grandes y verticales, para perseguir fragmentos con gancho, dash y
	-- doble salto. Una cadena de túneles (con rieles, ver Route) las une desde la cámara de cruce.
	Arenas = {
		Count = 7,
		Radius = { 40, 64 }, -- radio (mín, máx)
		Height = { 90, 150 }, -- alto del cuerpo (mín, máx); la cúpula y el fondo agregan más
		Ledges = { 5, 9 }, -- salientes en las paredes
		Pillars = { 1, 3 }, -- pilares de piso a techo
		Stalactites = { 4, 8 },
		TunnelRadius = 10, -- túneles que las conectan
		Lights = 0, -- cristales de luz dentro de cada una (apagados, ver LightCount)
		MineralClusters = 3, -- grupos de minerales dentro de cada una
	},

	-- Iluminación del subsuelo con cristales (apagada: iluminaban demasiado; las cuevas usan la luz ambiental).
	LightCount = 0,
	LightColors = { Color3.fromRGB(90, 220, 255) },
	LightRange = 45,
	LightBrightness = 2.2,

	-- Núcleo visible al fondo del pozo.
	CoreColor = Color3.fromRGB(255, 110, 30),
	CoreRadius = 28,

	-- Pool de minerales: se mantienen MineralCount en el mundo y se reponen por lotes. En la zona de cuevas van sobre
	-- el suelo; más abajo, en vetas dentro de la roca.
	MineralCount = 1400,
	InitialMineralShare = 0.45, -- parte del pool que se llena antes de que entren los jugadores (zona ya generada)
	SurfaceMinerals = 0, -- repartidos por la meseta (apagados: la superficie no es accesible)
	RespawnInterval = 30, -- segundos entre reposiciones
	RespawnBatch = 10,
	ClusterSizes = { 1, 1, 1, 2, 3, 4 }, -- tamaños posibles de grupo (se elige uno al azar)

	-- Minas abandonadas: de la capa 2 hacia abajo no hay cuevas naturales, pero sí minas excavadas en la roca, muy
	-- seguidas. Complejos (sala central con galerías entibadas, rieles, ramales, salas al final, derrumbes y a veces un
	-- pozo con escalera) y campamentos (una sala pequeña con su túnel). Los túneles se tallan al generar; la utilería
	-- (entibado, carritos, máquinas, cajas...) la pone server/Features/Mines solo cerca de los jugadores.
	Mines = {
		Radius = 820, -- distancia máxima al pozo (con sus galerías no llegan al borde del mundo)
		PitClearance = 300, -- distancia mínima al pozo de los complejos (los campamentos, la mitad)
		Complexes = 34, -- por capa
		Camps = 40, -- por capa
		Spacing = 150, -- distancia mínima entre complejos (campamentos: la mitad)
		Margin = 90, -- distancia mínima a los bordes de arriba y abajo de la capa
		Tunnels = { 3, 5 }, -- galerías que salen de la sala central
		TunnelLength = { 45, 110 },
		TunnelSize = Vector2.new(13, 12), -- ancho y alto de las galerías
		BranchSize = Vector2.new(10, 10), -- ramales
		ShaftChance = 0.4, -- pozo vertical con escalera sobre la sala central
		ShaftHeight = { 30, 70 },
		MineralShare = 0.5, -- parte de los minerales de las capas profundas que aparece dentro de las minas (el resto, en vetas)
	},
	-- Generación bajo demanda (server/Features/World): fuera de la capa 1 cerca del centro y de la columna del pozo, el
	-- terreno se genera solo alrededor de los jugadores (ahorra mucha memoria y tiempo). Cada celda de roca profunda que
	-- se genera recibe vetas de minerales según el SpawnWeight de su capa.
	Generation = {
		Radius = 240, -- distancia horizontal alrededor de cada jugador que tiene que estar generada
		Vertical = 280, -- y hacia arriba y abajo
		MineRange = 380, -- a esta distancia se tallan las minas (con su utilería, ver Mines)
		HubRange = 480, -- y los hubs de las capas
		Interval = 0.4, -- segundos entre revisiones
		Recheck = 24, -- un jugador se vuelve a revisar cuando se movió al menos esto (quieto no cuesta nada)
		VeinsPerWeight = 0.05, -- vetas por celda completa = SpawnWeight de la capa * esto (capa 2: ~1; capa 10: ~0.25)
		-- con más de RecycleAt * MineralCount minerales, se quitan los de las capas profundas a más de RecycleDistance
		-- de todos los jugadores hasta bajar a RecycleTo * MineralCount (así la roca nueva siempre recibe los suyos)
		RecycleAt = 0.9,
		RecycleTo = 0.7,
		RecycleDistance = 450,
	},

	CarveFactor = 0.6, -- las explosiones de minerales excavan con radio = ExplosionRadius * CarveFactor / raíz(Hardness)

	-- Progresión de las capas (de la primera a la última; t = 0 arriba, t = 1 en el núcleo):
	HardnessGrowth = 1.34, -- Hardness de la capa i = HardnessGrowth ^ (i - 1): 1 arriba, ~14 en la capa 10
	SpawnWeight = { 20, 5 }, -- cuántos minerales aparecen (peso), de arriba al núcleo
	-- Rareza (pesos) en puntos de la profundidad; entre puntos se interpola.
	RarityCurve = {
		{ t = 0, Comun = 80, Raro = 18, Epico = 2, Legendario = 0 },
		{ t = 0.25, Comun = 55, Raro = 33, Epico = 10, Legendario = 2 },
		{ t = 0.5, Comun = 25, Raro = 40, Epico = 26, Legendario = 9 },
		{ t = 0.75, Comun = 6, Raro = 28, Epico = 44, Legendario = 22 },
		{ t = 1, Comun = 0, Raro = 8, Epico = 45, Legendario = 47 },
	},
}

-- Capas: una por cada capa de Config/Biomes, de LayerHeight de alto. Cada una: Name, Biomes (sus 4 biomas), MaxDepth (profundidad
-- de su fondo), Hardness, SpawnWeight y Rarity (pesos por rareza, sin las que valen 0).
local function rarityAt(t: number): { [string]: number }
	local curve = Config.RarityCurve
	for k = 1, #curve - 1 do
		local a, b = curve[k], curve[k + 1]
		if t <= b.t then
			local f = (t - a.t) / (b.t - a.t)
			local weights = {}
			for _, rarity in { "Comun", "Raro", "Epico", "Legendario" } do
				local w = math.floor(a[rarity] + (b[rarity] - a[rarity]) * f + 0.5)
				if w > 0 then weights[rarity] = w end
			end
			return weights
		end
	end
	return { Legendario = 1 }
end

Config.Layers = {}
local total = #Biomes.Layers
for i, spec in Biomes.Layers do
	local t = (i - 1) / math.max(total - 1, 1)
	table.insert(Config.Layers, {
		Name = spec.Name,
		Biomes = spec.Biomes,
		MaxDepth = i * Config.LayerHeight,
		Hardness = math.floor(Config.HardnessGrowth ^ (i - 1) * 10 + 0.5) / 10,
		SpawnWeight = Config.SpawnWeight[1] + (Config.SpawnWeight[2] - Config.SpawnWeight[1]) * t,
		Rarity = rarityAt(t),
	})
end
assert(#Config.Layers * Config.LayerHeight == Config.Depth, "Config.World: Depth debe ser LayerHeight * número de capas")

return Config
