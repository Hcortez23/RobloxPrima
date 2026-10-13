-- Biomas: 10 capas (de arriba hacia el núcleo) con 4 biomas cada una. Dentro de una capa, cada bioma ocupa un cuarto
-- del mundo alrededor del pozo (cuadrantes con bordes irregulares; ver shared/BiomeMap), y el reparto gira de una
-- capa a otra, así que bajando en línea recta se pasa por biomas distintos.
--
-- Orden por dificultad: las primeras capas tienen biomas que ayudan (impulsos, flotación, puntos de recolección); en
-- medio, biomas de combos y de reacción en cadena; luego presión de tiempo y entornos hostiles (visibilidad, suelo,
-- gravedad); al fondo, reglas rotas y biomas letales. Cada capa mezcla temas distintos para que haya variedad.
--
-- Por bioma: Name, Theme, Material (roca; cada bioma de una capa usa uno distinto), Ambient (luz ambiental) y Tint
-- (tinte; el cliente los cambia suavemente en client/Features/Biomes), y Effect: la mecánica propia del bioma
-- (diseño; todavía no está implementada, ver NUCLEO_FRACTURA.md).
-- Profundidad, dureza, rareza y cantidad de minerales de cada capa se calculan en Config/World.
local M = Enum.Material

local Biomes = {}

-- Color de cada material de roca. Roblox colorea el terreno por material (no por zona), así que dos biomas con el
-- mismo material comparten color: solo se repiten materiales entre capas distintas y con colores que sirven a ambos.
-- Ground (tierra de la meseta) lo pinta Ambience; Rock también se usa en las montañas y alrededor de las cuevas de arriba.
Biomes.MaterialColors = {
	[M.Rock] = Color3.fromRGB(92, 86, 84), -- gris neutro
	[M.LeafyGrass] = Color3.fromRGB(40, 92, 84), -- musgo verde azulado bioluminiscente
	[M.Mud] = Color3.fromRGB(70, 74, 50), -- lodo oliva, enfermizo
	[M.Slate] = Color3.fromRGB(58, 68, 78), -- pizarra mojada
	[M.Limestone] = Color3.fromRGB(176, 170, 158), -- caliza pálida, depósitos minerales
	[M.Sandstone] = Color3.fromRGB(150, 100, 60), -- arenisca ocre calentada
	[M.Grass] = Color3.fromRGB(52, 70, 42), -- raíces y vegetación oscura
	[M.Pavement] = Color3.fromRGB(108, 98, 128), -- piedra lavanda
	[M.Cobblestone] = Color3.fromRGB(92, 112, 124), -- roca fracturada gris azulada
	[M.Basalt] = Color3.fromRGB(34, 30, 38), -- negro con reflejo violeta (obsidiana, hierro)
	[M.Salt] = Color3.fromRGB(226, 208, 214), -- sal y cuarzo blanco rosado
	[M.Glacier] = Color3.fromRGB(150, 200, 232), -- hielo azul
	[M.Ice] = Color3.fromRGB(182, 222, 242), -- hielo claro
	[M.Snow] = Color3.fromRGB(222, 232, 242), -- escarcha
	[M.Concrete] = Color3.fromRGB(104, 104, 110), -- metal y hormigón gris plata
	[M.Brick] = Color3.fromRGB(110, 62, 40), -- óxido de maquinaria
	[M.CrackedLava] = Color3.fromRGB(70, 36, 30), -- roca agrietada sobre magma
	[M.Asphalt] = Color3.fromRGB(46, 44, 46), -- ceniza oscura
	[M.Sand] = Color3.fromRGB(76, 46, 100), -- arena iridiscente del abismo
}

local function biome(name: string, theme: string, material: Enum.Material, ambient: Color3, tint: Color3, effect: string)
	return { Name = name, Theme = theme, Material = material, Ambient = ambient, Tint = tint, Effect = effect }
end
local rgb = Color3.fromRGB

Biomes.Layers = {
	{
		Name = "Umbral vivo", -- la zona de cuevas: biomas amables para aprender
		Biomes = {
			biome("Cueva Fúngica Bioluminiscente", "Bioluminiscencia", M.LeafyGrass, rgb(110, 170, 160), rgb(232, 255, 248),
				"Hongos que explotan en esporas al romperse, generando zonas de efecto temporal."),
			biome("Gruta de Esporas Flotantes", "Bioluminiscencia", M.Mud, rgb(150, 140, 110), rgb(255, 250, 232),
				"Partículas en el aire que se capturan como los fragmentos normales."),
			biome("Catarata Subterránea", "Agua", M.Slate, rgb(110, 140, 165), rgb(232, 244, 255),
				"Corriente fuerte que empuja fragmentos hacia un punto de recolección natural."),
			biome("Bolsillo de Microgravedad", "Gravedad", M.Limestone, rgb(160, 160, 180), rgb(245, 245, 255),
				"Flotación libre, ideal para cadenas de captura en 3D sin caída."),
		},
	},
	{
		Name = "Corrientes ascendentes", -- biomas que impulsan el movimiento
		Biomes = {
			biome("Chimenea Geotérmica", "Lava", M.Sandstone, rgb(175, 130, 95), rgb(255, 238, 220),
				"Corrientes ascendentes de calor que impulsan el doble salto más alto."),
			biome("Cueva de Géiseres", "Agua", M.Limestone, rgb(150, 165, 175), rgb(240, 250, 255),
				"Erupciones periódicas que lanzan al jugador verticalmente, útiles para rutas de extracción rápida."),
			biome("Caverna de Raíces Vivas", "Bioluminiscencia", M.Grass, rgb(125, 150, 105), rgb(240, 255, 232),
				"Raíces que se regeneran y pueden usarse como ganchos naturales improvisados."),
			biome("Cueva de Vórtices", "Gravedad", M.Rock, rgb(140, 145, 160), rgb(240, 245, 255),
				"Corrientes de aire que arrastran fragmentos hacia puntos de succión, creando pozos de loot."),
		},
	},
	{
		Name = "Ecos y cadenas", -- combos: romper bien multiplica el botín
		Biomes = {
			biome("Cueva Armónica", "Cristal", M.Pavement, rgb(150, 135, 180), rgb(245, 238, 255),
				"El sonido ambiental sube de intensidad y altera la física de los fragmentos flotantes."),
			biome("Caverna de Eco Fractal", "Cristal", M.Cobblestone, rgb(120, 155, 175), rgb(232, 248, 255),
				"Cada fragmento roto genera un eco que rompe una réplica a distancia, creando combos encadenados."),
			biome("Cueva de Líquenes Eléctricos", "Bioluminiscencia", M.LeafyGrass, rgb(120, 175, 185), rgb(232, 252, 255),
				"Líquenes que generan pequeñas descargas y potencian los combos si se encadenan bien."),
			biome("Caverna Magnética", "Gravedad", M.Basalt, rgb(130, 120, 150), rgb(240, 236, 255),
				"Los fragmentos metálicos se atraen entre sí; romper uno jala a los demás."),
		},
	},
	{
		Name = "Redes quebradizas", -- reacciones en cadena que premian el punto exacto
		Biomes = {
			biome("Cueva de Cuarzo Resonante", "Cristal", M.Salt, rgb(185, 165, 190), rgb(255, 242, 250),
				"Las paredes vibran con la frecuencia de tus disparos; dar en el tono correcto provoca reacciones en cadena masivas."),
			biome("Caverna Glacial", "Hielo", M.Glacier, rgb(135, 175, 210), rgb(228, 244, 255),
				"El hielo se agrieta en patrones predecibles; rompes un punto y toda la red colapsa."),
			biome("Gruta de Estalactitas Quebradizas", "Hielo", M.Ice, rgb(150, 180, 205), rgb(236, 248, 255),
				"Las estalactitas se desprenden del techo al dispararlas y pueden usarse como proyectiles."),
			biome("Caverna de Andamiaje Colapsado", "Industrial", M.Concrete, rgb(150, 140, 125), rgb(255, 246, 232),
				"Estructuras artificiales mezcladas con roca natural, rompibles en secuencia."),
		},
	},
	{
		Name = "Riesgo y reflejo", -- más botín a cambio de más riesgo y peor control
		Biomes = {
			biome("Gruta de Prismas", "Cristal", M.Limestone, rgb(175, 160, 190), rgb(255, 245, 255),
				"Los disparos se refractan en varias direcciones al atravesar cristales: multiplican el botín y también el riesgo."),
			biome("Caverna de Obsidiana", "Lava", M.Basalt, rgb(140, 105, 120), rgb(255, 232, 240),
				"Fragmentos ultra afilados que rompen en esquirlas secundarias al impactar."),
			biome("Jardín de Cristal Orgánico", "Bioluminiscencia", M.Grass, rgb(150, 175, 140), rgb(248, 255, 240),
				"Estructuras que laten y cambian de rareza según el tiempo que el jugador pasa cerca."),
			biome("Lago Subterráneo Congelado", "Hielo", M.Ice, rgb(140, 170, 200), rgb(232, 246, 255),
				"Superficie resbaladiza que afecta el control del dash."),
		},
	},
	{
		Name = "Contrarreloj", -- si no extraes rápido, el bioma se cierra o colapsa
		Biomes = {
			biome("Catedral de Sal Cristalina", "Cristal", M.Salt, rgb(195, 175, 185), rgb(255, 244, 248),
				"Estructuras frágiles que colapsan en cascada si no extraes rápido."),
			biome("Cueva de Escarcha Viva", "Hielo", M.Snow, rgb(160, 185, 210), rgb(236, 246, 255),
				"El hielo vuelve a crecer si no extraes rápido, cerrando rutas."),
			biome("Caverna de Permafrost", "Hielo", M.Glacier, rgb(125, 160, 195), rgb(226, 240, 255),
				"Minerales raros atrapados en hielo que requieren varios impactos para liberarse."),
			biome("Túnel de Minado Automatizado", "Industrial", M.Brick, rgb(165, 125, 100), rgb(255, 236, 222),
				"Maquinaria vieja que aún dispara fragmentos si se reactiva."),
		},
	},
	{
		Name = "Elementos hostiles", -- el entorno limita el movimiento o la vista
		Biomes = {
			biome("Túneles de Magma Vivo", "Lava", M.CrackedLava, rgb(190, 110, 75), rgb(255, 226, 205),
				"El magma se solidifica y se fractura en tiempo real al enfriarse con tus disparos."),
			biome("Caverna Inundada", "Agua", M.Slate, rgb(90, 125, 150), rgb(220, 238, 255),
				"Natación obligatoria, con fragmentos que flotan y se mueven con la corriente."),
			biome("Falla de Gravedad Pulsante", "Gravedad", M.Pavement, rgb(140, 125, 170), rgb(244, 236, 255),
				"La gravedad cambia de intensidad en ciclos, obligando a cronometrar el movimiento."),
			biome("Cueva de Ceniza Ardiente", "Lava", M.Asphalt, rgb(120, 100, 90), rgb(240, 225, 215),
				"Humo que reduce la visibilidad; premia orientarse por el sonido de los disparos."),
		},
	},
	{
		Name = "Suelo traicionero", -- no hay dónde quedarse quieto
		Biomes = {
			biome("Río de Lava Lenta", "Lava", M.CrackedLava, rgb(200, 105, 65), rgb(255, 222, 198),
				"Plataformas de roca que se funden si te quedas parado, forzando el movimiento constante."),
			biome("Caverna de Gravedad Invertida", "Gravedad", M.Cobblestone, rgb(120, 140, 170), rgb(236, 244, 255),
				"El gancho y el dash funcionan hacia arriba; los fragmentos caen hacia el techo."),
			biome("Gruta de Niebla Ácida", "Agua", M.Mud, rgb(135, 155, 95), rgb(245, 255, 225),
				"El agua corroe ciertos materiales con el tiempo, dando urgencia a la extracción."),
			biome("Lago de Mercurio Líquido", "Agua", M.Concrete, rgb(160, 165, 175), rgb(244, 246, 250),
				"Superficie reflectante que confunde la mira y el radar de minerales."),
		},
	},
	{
		Name = "Leyes rotas", -- la física deja de ser confiable
		Biomes = {
			biome("Núcleo Reactor Abandonado", "Industrial", M.Concrete, rgb(110, 175, 140), rgb(236, 255, 240),
				"Restos de tecnología que generan campos de energía inestables."),
			biome("Cueva de Anomalía Temporal", "Industrial", M.Pavement, rgb(165, 140, 190), rgb(250, 240, 255),
				"Zonas donde los fragmentos rotos rebobinan y pueden romperse de nuevo tras un ciclo."),
			biome("Vacío de Antimateria Contenida", "Industrial", M.Basalt, rgb(120, 95, 160), rgb(238, 228, 255),
				"Rompe las reglas de la física local; el gancho se comporta de forma errática."),
			biome("Pantano de Esporas Letales", "Peligro", M.Mud, rgb(140, 160, 80), rgb(245, 255, 215),
				"Niebla venenosa que se expande desde los puntos de ruptura; cada disparo libera más gas: botín o aire limpio."),
		},
	},
	{
		Name = "Zona letal", -- endgame junto al núcleo
		Biomes = {
			biome("Caldera del Colapso Térmico", "Peligro", M.CrackedLava, rgb(215, 105, 60), rgb(255, 215, 190),
				"La temperatura sube sin parar; sin fragmentos de enfriamiento a tiempo, el calor hace daño creciente hasta la incineración."),
			biome("Fosa del Cero Absoluto", "Peligro", M.Ice, rgb(120, 160, 210), rgb(220, 236, 255),
				"Zonas de hipotermia que drenan stamina y movimiento; quedarse quieto o sin fuentes de calor congela hasta matar."),
			biome("Cueva de Disonancia Cognitiva", "Peligro", M.Asphalt, rgb(150, 110, 150), rgb(255, 232, 250),
				"El escenario se distorsiona (geometría falsa, fragmentos fantasma) cuanto más tiempo pasas; hay que confiar en el oído."),
			biome("Abismo de Rareza Inestable", "Peligro", M.Sand, rgb(170, 110, 200), rgb(250, 232, 255),
				"La rareza de los minerales cambia en tiempo real según la actividad del servidor."),
		},
	},
}

-- comprobación: 4 biomas por capa, con materiales distintos dentro de la capa y con color definido
for i, layer in Biomes.Layers do
	assert(#layer.Biomes == 4, `Config.Biomes: la capa {i} debe tener 4 biomas`)
	local used = {}
	for _, b in layer.Biomes do
		assert(not used[b.Material], `Config.Biomes: material repetido en la capa {i} ({b.Name})`)
		assert(Biomes.MaterialColors[b.Material], `Config.Biomes: falta el color de {b.Material.Name}`)
		used[b.Material] = true
	end
end

return Biomes
