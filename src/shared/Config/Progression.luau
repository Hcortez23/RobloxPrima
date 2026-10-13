-- Progresión por capas (server/Features/Progression): cada jugador tiene sus propias capas desbloqueadas, aunque el
-- terreno sea el mismo para todos.
--  · Permiso de descenso: en el hub de su capa más profunda compra el permiso para la siguiente, pagando con el valor
--    de los minerales guardados en su base (se gastan primero los más baratos), y además necesita un arma con
--    DigPower suficiente para la dureza de esa capa (DigPower >= Hardness * MinRadius / BaseRadius de Config/Excavation).
--  · Solo puede excavar hasta el fondo de su última capa desbloqueada.
--  · Presión: si entra a una capa sin permiso (por el túnel de otro), aviso y daño creciente hasta que suba o muera.
--  · Hubs: una caverna alrededor del pozo en cada capa (la de la capa 1 es la cueva del foso). Al entrar en uno se
--    descubre; el elevador del pozo lleva a los hubs descubiertos de capas desbloqueadas.
-- Por ahora no se guarda entre sesiones (pendiente: DataStore).
return {
	-- costo del permiso para bajar A cada capa, en valor de minerales (Config/Minerals: Value)
	PermitCost = { [2] = 40, [3] = 150, [4] = 400, [5] = 1000, [6] = 2500, [7] = 5000, [8] = 10000, [9] = 20000, [10] = 40000 },

	Pressure = {
		Grace = 3, -- segundos de aviso antes de empezar a hacer daño
		Damage = 0.06, -- fracción de la vida máxima por segundo al empezar
		Ramp = 0.06, -- cuánto sube esa fracción por cada segundo que sigue ahí
	},

	-- hubs de las capas 2 a 10 (la cueva del foso hace de hub de la capa 1)
	Hub = {
		FloorOffset = 180, -- profundidad del piso bajo el techo de su capa
		Radius = 100,
		Height = 44, -- la cúpula agrega más
		DomeRadius = 40,
		Galleries = 4, -- galerías que salen hacia las minas de la capa
		GallerySize = Vector2.new(14, 13),
		MaxSlope = 0.3, -- pendiente máxima de una galería (si ninguna mina queda a esa pendiente, termina en una sala)
	},
	ElevatorAngle = 0, -- dónde está el elevador alrededor del pozo (radianes desde +X hacia +Z), igual en todos los hubs
	StationAngle = math.pi, -- dónde está la estación de carritos (en la pared)
	ElevatorRange = 16, -- distancia máxima a la cabina para usar el elevador
}
