-- Bases de los jugadores: cada una es una cueva propia (del tamaño de la antigua cueva de spawn) en un anillo alrededor
-- de la cueva del foso, unida a ella por un pasaje con arco. A cada jugador que entra le toca una libre y aparece
-- (y reaparece) en ella. La disposición la calcula shared/BaseLayout; lo de dentro, server/Features/Bases.
return {
	Count = 8, -- cuántas bases (= jugadores que pueden tener base a la vez)
	RingRadius = 450, -- distancia del centro de la cueva del foso al centro de cada cueva-base
	CaveRadius = 140,
	CaveHeight = 80, -- el piso queda a la misma altura que el de la cueva del foso
	DomeRadius = 50,
	PassageWidth = 32, -- pasaje entre la cueva del foso y la cueva-base
	PassageHeight = 26, -- paredes rectas; el techo abovedado agrega PassageWidth / 2
	-- Almacén: un silo por cada tipo de mineral de Config/Minerals, en filas (sirve para ~100 tipos).
	StorageColumns = 10,
	StorageSpacing = Vector2.new(7, 9), -- separación entre silos (x, z)
	MuralSlots = 5, -- pedestales del mural de exhibición (ver Mural)
	-- un color por base (arcos, neón y letreros); si hay más bases que colores, se repiten
	Colors = {
		Color3.fromRGB(80, 200, 255),
		Color3.fromRGB(255, 140, 50),
		Color3.fromRGB(120, 255, 140),
		Color3.fromRGB(255, 80, 120),
		Color3.fromRGB(190, 120, 255),
		Color3.fromRGB(255, 220, 70),
		Color3.fromRGB(70, 255, 220),
		Color3.fromRGB(255, 120, 220),
	},
}
