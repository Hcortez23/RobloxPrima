return {
	Color = Color3.fromRGB(80, 220, 255), -- color por defecto; cada objeto puede cambiarlo con el atributo AuraColor
	PulseTime = 1.6, -- segundos de cada "respiración" del brillo
	MaxParticles = 14, -- tope de destellos por segundo, aunque el objeto sea grande
	-- Nombres de objetos directos de Workspace que reciben el aura sin necesidad del tag "Aura".
	WorkspaceTargets = {},
	-- Copiar los efectos de un modelo (From) a otro (To). Rutas dentro de Workspace, un nombre por nivel.
	CopyEffects = {
		{ From = { "VFX Auras", "Dummy" }, To = { "super ore" } },
	},
}
