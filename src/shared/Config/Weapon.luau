return {
	ToolName = "Rifle",
	Cooldown = 0.15, -- segundos entre disparos (mantener clic = fuego automático)
	Range = 400,
	ShoulderOffset = Vector3.new(2.2, 0.4, 0), -- cámara sobre el hombro derecho en modo Lock (x = lateral, y = altura)
	Debug = true, -- imprime en el Output cada disparo y lo que golpea (poner en false cuando todo funcione)
	Damage = 50, -- vida que quita cada disparo a un mineral con barra de vida
	-- Modelos del mapa que se convierten en armas equipables al iniciar (server/Features/CustomWeapons).
	-- Path: ruta en Workspace. ShotEffect: hijo del modelo cuyos efectos lleva cada disparo (se saca del arma).
	-- GripAlong (fracción del largo desde el centro, -0.25 por defecto) y GripDrop (studs) mueven el punto de agarre.
	-- MuzzleUp: studs que se sube la boca del cañón sobre el centro del arma (medido en Blender para cada modelo).
	-- TrailColor: color del rastro de bala de esa arma (si no, ShotTrailColor).
	-- AuraBack: studs que se corre el aura del arma hacia atrás (hacia la culata, del lado del jugador).
	CustomWeapons = {
		-- Rifle de Blender con textura anime (Descargas\blender arma_anime.fbx, importado en Studio con File → Import 3D).
		-- Se busca por su nombre en todo el Workspace. RaijinContorno no repinta: conserva la textura.
		{ Path = { "blender arma_anime" }, ToolName = "Rifle Raijin", Damage = 5, Skin = "RaijinContorno", FlipFront = true,
			GripAlong = 0.1, GripDrop = 0.2, MuzzleUp = 0.23,
			ShotEffect = "Aura_WaterBubbleTrio", AuraBack = 2.6, TrailColor = Color3.fromRGB(120, 220, 255) }, -- agarrada más adelante y más abajo: el arma queda más cerca de la cámara
	},
	ShotSpeed = 250, -- studs/s del proyectil de las armas con ShotEffect
	ShotEffectScale = 0.7, -- tamaño de los efectos en el proyectil comparado con el aura original
	WeaponAuraScale = 0.8, -- tamaño del aura del arma comparado con el arma (1 = del tamaño del arma)
	WeaponAuraBoost = 0.5, -- intensidad del aura del arma: menos de 1 = más tenue, más de 1 = más visible (1 = como venía)
	ShotAuraBoost = 0.2, -- intensidad del aura en los disparos (1 = como venía)
	ShotTrailColor = Color3.fromRGB(255, 235, 140), -- rastro que deja la bala en el aire
	ShotTrailWidth = 0.25, -- grosor del rastro en studs
	ShotTrailTime = 0.6, -- segundos que tarda el rastro en desvanecerse
	-- Skins para armas de CustomWeapons (campo Skin). Las piezas del arma se reparten por tamaño: las más grandes
	-- usan Body, las medianas Trim y las más pequeñas Glow (sin Body no se repinta nada). Outline: contorno tipo dibujo.
	Skins = {
		-- Estilo shōnen de ninja de rayo, diseño propio (no copia nombres, símbolos ni armas de ninguna serie).
		Raijin = {
			Body = { Color = Color3.fromRGB(22, 26, 44), Material = Enum.Material.SmoothPlastic },
			Trim = { Color = Color3.fromRGB(215, 230, 255), Material = Enum.Material.SmoothPlastic },
			Glow = { Color = Color3.fromRGB(80, 170, 255), Material = Enum.Material.Neon },
			Outline = Color3.fromRGB(0, 0, 0),
			Light = Color3.fromRGB(110, 190, 255),
		},
		-- Solo contorno de dibujo y luz azul, sin cambiar colores: para armas que ya traen su textura.
		RaijinContorno = {
			Outline = Color3.fromRGB(0, 0, 0),
			Light = Color3.fromRGB(110, 190, 255),
		},
	},
}