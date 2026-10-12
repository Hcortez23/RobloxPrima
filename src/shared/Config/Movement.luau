return {
	DoubleJumpPower = 85,
	DoubleJumpCooldown = 2, -- segundos entre un doble salto y el siguiente
	DoubleJumpDelay = 0.2, -- segundos en el aire antes de poder usar el segundo salto
	DoubleJumpFlipTime = 0.45, -- duración del mortal del doble salto
	DoubleJumpTuckHip = 100, -- grados que suben los muslos al encoger las piernas
	DoubleJumpTuckKnee = 120, -- grados que se doblan las rodillas
	SprintSpeed = 26, -- velocidad al correr con Shift (la normal de Roblox es 16)
	GrappleRange = 120, -- alcance máximo del gancho en studs
	GrapplePullSpeed = 80, -- velocidad con la que jala el gancho
	GrappleReleaseDistance = 4, -- se suelta solo al llegar a esta distancia del punto
	GrappleCooldown = 1, -- segundos entre un disparo del gancho y el siguiente
	GrappleRopeColor = Color3.fromRGB(255, 255, 255),
	GrappleIconId = "", -- "rbxassetid://<número>" de assets/icons/gancho.png subido a Roblox; vacío = sin ícono
	GrappleAccentColor = Color3.fromRGB(80, 220, 255), -- detalles de neón del lanzagancho
	GrappleHookSpeed = 300, -- studs por segundo que vuela la garra hasta el punto
	GrappleClampTime = 0.15, -- segundos que tarda la garra en cerrarse al agarrarse
	GrapplePoseLean = 35, -- grados máximos que se inclina el cuerpo hacia el punto al ser jalado
	GrappleRopeSlack = 3, -- qué tan floja va la cuerda mientras vuela la garra
	DashSpeed = 90,
	DashCooldown = 1.5,
}
