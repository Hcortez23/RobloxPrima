return {
	Color = Color3.fromRGB(80, 220, 255), -- color por defecto; cada objeto puede cambiarlo con el atributo AuraColor
	PulseTime = 1.6, -- segundos de cada "respiración" del brillo
	MaxParticles = 14, -- tope de destellos por segundo, aunque el objeto sea grande
	-- Nombres de objetos directos de Workspace que reciben el aura sin necesidad del tag "Aura".
	WorkspaceTargets = {},
	-- Copiar los efectos de un modelo (From) a otro (To), un nombre por nivel. To está en Workspace;
	-- From se busca en ReplicatedStorage.Assets, luego en ReplicatedStorage y al final en Workspace.
	-- Paquetes de auras de ejemplo que se sacan del mapa al iniciar la partida (se mueven a ReplicatedStorage, no se
	-- borran): no se ven en el escenario pero sus auras siguen usándose (server/Features/AuraTransfer).
	HideFromMap = {
		"Aura Pack Premium By Sanzzzzz",
		"VFX Auras",
	},
	-- Rareza -> modelo cuyos efectos reciben todos los minerales de esa rareza (misma búsqueda que From).
	RarityEffects = {
		Raro = { "Aura Pack Premium By Sanzzzzz", "Aura Kurama" },
	},
	CopyEffects = {},
	-- Como CopyEffects pero lo hace el servidor (lo ven todos) y, con RemoveSource, borra el modelo de origen
	-- del mapa después de copiar (server/Features/AuraTransfer).
	TransferEffects = {
		{ From = { "Aura Pack Premium By Sanzzzzz", "Aura_pumpk" }, To = { "super ore" }, RemoveSource = true },
		{ From = { "Aura Pack Premium By Sanzzzzz", "Aura_Purp" }, To = { "TestRoom", "Mineral_Comun" }, RemoveSource = true },
	},
}
