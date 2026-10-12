return {
	ExplosionRadius = 14, -- studs; minerales dentro de este radio explotan en cadena
	ChainDelay = 0.06, -- espera mínima antes de que explote el siguiente
	ChainSpeed = 70, -- studs/s a los que avanza la cadena (más bajo = onda más lenta y vistosa)
	DropCount = 3, -- materiales que suelta cada mineral al explotar
	DropKick = 32, -- impulso de salida de los materiales
	PushStrength = 28, -- empuje de la explosión a materiales ya sueltos cercanos
	GravityCancel = 0.8, -- 0 = cae normal, 1 = flota; más alto = más tiempo en el aire para capturarlo
	FloatTime = 6, -- segundos flotando (ventana para capturarlo en el aire) antes de caer
	Lifetime = 300, -- segundos antes de desaparecer si nadie lo recoge (5 min)
	MaxLoot = 300, -- tope de objetos sueltos en el mundo; al pasarse se borra el más viejo
	-- Objetos puestos a mano en Workspace que cuentan como mineral: nombre -> rareza y vida.
	WorkspaceMinerals = {
		["super ore"] = { Rarity = "Legendario", Health = 100 },
	},
}
