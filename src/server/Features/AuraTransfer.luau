-- Pasa el aura de un modelo de VFX (ej. un paquete del Marketplace puesto en Workspace) a otro objeto y luego
-- borra el modelo de origen, según Config.Aura.TransferEffects. Lo hace el servidor al iniciar la partida:
-- todos los jugadores ven el aura en el destino y nadie ve el modelo de origen. En Studio (modo edición)
-- el origen sigue existiendo; esto ocurre en cada partida.
-- Antes, saca del mapa los paquetes de auras de ejemplo (Config.Aura.HideFromMap) moviéndolos a ReplicatedStorage:
-- dejan de verse en el escenario pero siguen disponibles para copiar sus efectos (arma, minerales, etc.).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Aura)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.Weapon)
local EffectCopy = require(ReplicatedStorage.Shared.EffectCopy)

-- ¿Es un modelo de ejemplo de auras? Los de Config.HideFromMap por nombre, y además cualquier modelo que muestre
-- efectos en un maniquí (tiene Humanoid y partículas/haces) o que diga "aura" en el nombre y tenga efectos.
-- Nunca los jugadores, los minerales ni los modelos que CustomWeapons convierte en armas.
local function isExample(instance: Instance): boolean
	if table.find(Config.HideFromMap, instance.Name) then
		return true
	end
	if not (instance:IsA("Model") or instance:IsA("Folder")) then
		return false
	end
	if Players:GetPlayerFromCharacter(instance) or CollectionService:HasTag(instance, "Mineral") then
		return false
	end
	for _, weapon in WeaponConfig.CustomWeapons do
		if instance.Name == weapon.Path[#weapon.Path] then
			return false
		end
	end
	local hasHumanoid, hasEffect = false, false
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Humanoid") then
			hasHumanoid = true
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			hasEffect = true
		end
	end
	return hasEffect and (hasHumanoid or instance.Name:lower():find("aura") ~= nil)
end

-- Mueve los modelos de ejemplo del Workspace a ReplicatedStorage (no se borran). EffectCopy.findSource los busca
-- ahí con la misma ruta, así que las auras que los usan siguen funcionando.
local function hideExamples()
	local moved = {}
	for _, child in workspace:GetChildren() do
		if isExample(child) then
			child.Parent = ReplicatedStorage
			table.insert(moved, child.Name)
		end
	end
	if #moved > 0 then
		print(`[AuraTransfer] sacados del mapa (siguen en ReplicatedStorage): {table.concat(moved, ", ")}`)
	end
end
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
		hideExamples()
		for _, entry in Config.TransferEffects do
			task.spawn(transfer, entry)
		end
	end,
}
