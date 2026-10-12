-- Pasa el aura de un modelo de VFX (ej. un paquete del Marketplace puesto en Workspace) a otro objeto y luego
-- borra el modelo de origen, según Config.Aura.TransferEffects. Lo hace el servidor al iniciar la partida:
-- todos los jugadores ven el aura en el destino y nadie ve el modelo de origen. En Studio (modo edición)
-- el origen sigue existiendo; esto ocurre en cada partida.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Aura)
local EffectCopy = require(ReplicatedStorage.Shared.EffectCopy)

local function transfer(entry)
	local source = EffectCopy.findSource(entry.From)
	local target = EffectCopy.findInWorkspace(entry.To)
	if not (source and target) then
		warn(`[AuraTransfer] no se encontró {table.concat(if source then entry.To else entry.From, ".")}`)
		return
	end
	if EffectCopy.copy(source, target) == 0 then
		return -- no se copió nada: mejor no borrar el origen
	end
	-- Solo se borra si está en el mapa; si vino de ReplicatedStorage.Assets se conserva para otras copias.
	if entry.RemoveSource and source:IsDescendantOf(workspace) then
		source:Destroy()
	end
end

return {
	Start = function()
		for _, entry in Config.TransferEffects do
			task.spawn(transfer, entry)
		end
	end,
}
