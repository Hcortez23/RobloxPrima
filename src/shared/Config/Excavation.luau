-- Excavación (server/Features/Excavation.luau): los disparos al terreno abren huecos; cuanto más hondo, más dura la
-- roca (Hardness por capa en Config/World). Radio del hueco = BaseRadius * DigPower del arma / Hardness de la capa.
-- Si sale menor que MinRadius, la roca es demasiado dura para esa arma: no se abre y saltan chispas.
return {
	BaseRadius = 1.5,
	MinRadius = 1.2,
	MaxRadius = 8,
	DefaultDigPower = 3, -- armas sin atributo DigPower (el Rifle)
	-- Las explosiones de minerales también excavan: ExplosionRadius * CarveFactor (Config/World) / raíz de Hardness.
	DebrisCount = 8, -- trozos de roca que saltan en cada hueco (solo visual, en el cliente)
}
