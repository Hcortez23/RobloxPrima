-- Bases de los jugadores en la cueva de la base (server/Features/Bases.luau): un anillo de bahías abiertas hacia el
-- centro (la plaza, para las tiendas). A cada jugador que entra le toca una libre y aparece (y reaparece) en ella.
return {
	Count = 8, -- cuántas bases (= jugadores que pueden tener base a la vez)
	RingRadius = 98, -- distancia del centro de la cueva al centro de cada base
	Width = 44, -- ancho de la bahía
	Depth = 36, -- fondo de la bahía
	WallHeight = 18,
	PassageGap = 40, -- grados libres alrededor del pasaje hacia la puerta de arco (no se ponen bases ahí)
	MuralSlots = 5, -- pedestales del mural de exhibición en la pared del fondo (ver Mural)
	-- un color por base (borde de neón y letrero); si hay más bases que colores, se repiten
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
