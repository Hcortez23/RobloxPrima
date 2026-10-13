-- Efectos visuales de los minerales según su rareza (client/Features/MineralFX.luau). Más raro = más llamativo.
-- Light: brillo máximo de la luz que late (0 = sin luz). Twinkles/Motes: destellos y partículas que suben por segundo.
-- Comets: estelas que orbitan el mineral. Rays: rayos de luz girando. Highlight: contorno brillante que late.
-- Spin (grados/s) y Bob (studs): giro y flotación; solo en los modelos de assets/models/Minerals.
-- FlashEvery (s, aprox.) y FlashSize (veces el tamaño del mineral): destello en estrella con golpe de luz y chispas.
return {
	Comun = { Light = 0.6, LightRange = 8, Twinkles = 4, Motes = 0, Comets = 0, Rays = 0, Highlight = false, Spin = 0, Bob = 0, FlashEvery = 5, FlashSize = 1.6 },
	Raro = { Light = 2, LightRange = 14, Twinkles = 10, Motes = 0, Comets = 0, Rays = 0, Highlight = false, Spin = 0, Bob = 0, FlashEvery = 3.5, FlashSize = 2 },
	Epico = { Light = 3.5, LightRange = 18, Twinkles = 16, Motes = 0, Comets = 0, Rays = 0, Highlight = true, Spin = 30, Bob = 0.5, FlashEvery = 2.5, FlashSize = 2.4 },
	Legendario = { Light = 5, LightRange = 24, Twinkles = 24, Motes = 0, Comets = 0, Rays = 6, Highlight = true, Spin = 18, Bob = 0.6, FlashEvery = 1.8, FlashSize = 3 },
	PulseTime = 1.2, -- segundos de cada latido de luz y contorno
	ActiveRadius = 160, -- solo los minerales a esta distancia de la cámara llevan efectos (rendimiento)
	LightRadius = 220, -- más lejos, la luz propia de cada mineral se apaga
	FlashSparks = false, -- chispas que salen disparadas con cada destello
	FlashRainbow = true, -- destello en colores de arcoíris (false = blanco y color de la rareza)
}
