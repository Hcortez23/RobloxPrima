-- Carritos (server/Features/Carts.luau): en cada estación de la ruta (la cueva del foso, la cámara de cruce y cada
-- arena) el jugador carga los minerales que lleva y un carrito los lleva por los rieles hasta el andén de su base.
return {
	Speed = 45, -- studs por segundo
	SendCooldown = 2, -- segundos entre envíos del mismo jugador
	RingRadius = 72, -- vía circular de la cueva de la base (por dentro del anillo de bases)
	SampleStep = 3, -- separación de los puntos de la vía en la superficie (y de los durmientes)
	-- Vía por la cueva del foso, de la boca del portal DESCENSO a la puerta de arco: rodea la rejilla del pozo por este
	-- punto (ángulo en grados desde +X hacia +Z, y distancia al centro de la cueva).
	HubWaypoint = { Angle = 140, Distance = 70 },
}
