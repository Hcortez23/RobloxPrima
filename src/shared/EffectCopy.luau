-- Copiar efectos (partículas, haces, luces...) de un modelo de VFX, ej. un paquete de auras del Marketplace,
-- a otro objeto. Lo usan client/Features/Aura (efectos solo visuales) y server/Features/AuraTransfer
-- (efectos que ven todos y luego se borra el modelo de origen).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectCopy = {}

EffectCopy.NAME = "AuraEffect" -- nombre de todo lo copiado, para poder quitarlo

-- Clases que se consideran "efecto" (los scripts nunca se copian).
local EFFECT_CLASSES = { "ParticleEmitter", "Beam", "Trail", "PointLight", "SpotLight", "SurfaceLight", "Fire", "Smoke", "Sparkles" }

local function isEffect(instance: Instance): boolean
	for _, className in EFFECT_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

function EffectCopy.scaleSequence(sequence: NumberSequence, factor: number): NumberSequence
	local keypoints = {}
	for _, keypoint in sequence.Keypoints do
		table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * factor, keypoint.Envelope * factor))
	end
	return NumberSequence.new(keypoints)
end

-- Tamaño y pivote de cualquier origen: Model, pieza, o una carpeta/Attachment suelto (usa la pieza que lo contiene).
function EffectCopy.extents(instance: Instance): Vector3
	if instance:IsA("Model") then
		return instance:GetExtentsSize()
	elseif instance:IsA("BasePart") then
		return instance.Size
	end
	local holder = instance:FindFirstAncestorWhichIsA("PVInstance")
	return if holder then EffectCopy.extents(holder) else Vector3.one * 4
end

function EffectCopy.pivot(instance: Instance): CFrame
	if instance:IsA("PVInstance") then
		return instance:GetPivot()
	elseif instance:IsA("Attachment") then
		return instance.WorldCFrame
	end
	local holder = instance:FindFirstAncestorWhichIsA("PVInstance")
	return if holder then holder:GetPivot() else CFrame.identity
end

-- Pieza más grande del objeto: ahí van los efectos.
function EffectCopy.largestPart(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	end
	local best, bestVolume = nil, 0
	for _, part in target:GetDescendants() do
		-- MineralFX pone su propia pieza invisible y la borra al limpiar; los efectos no deben ir ahí
		if part:IsA("BasePart") and part.Name ~= "MineralFX" then
			local volume = part.Size.X * part.Size.Y * part.Size.Z
			if volume > bestVolume then
				best, bestVolume = part, volume
			end
		end
	end
	return best
end

-- Busca Workspace.<path[1]>.<path[2]>... esperando a que cargue cada nivel.
function EffectCopy.findInWorkspace(path: { string }): Instance?
	local current: Instance? = workspace
	for _, name in path do
		current = current and current:WaitForChild(name, 10)
	end
	return current
end

-- El modelo de VFX puede guardarse fuera del mapa para que no se vea: primero se busca solo por su nombre
-- (el último de la ruta) en ReplicatedStorage.Assets (assets/models, como queda al guardarlo con Save to File)
-- y en ReplicatedStorage (si se arrastró ahí en Studio); luego por la ruta completa y al final en Workspace.
function EffectCopy.findSource(path: { string }): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local saved = (assets and assets:FindFirstChild(path[#path])) or ReplicatedStorage:FindFirstChild(path[#path])
	if saved then
		return saved
	end
	for _, root in { assets, ReplicatedStorage } do
		local current: Instance? = root
		for _, name in path do
			current = current and current:FindFirstChild(name)
		end
		if current then
			return current
		end
	end
	return EffectCopy.findInWorkspace(path)
end

local warnedSources: { [Instance]: boolean } = {}

-- Copia los efectos de `source` a `target`. Las piezas del destino no coinciden con las del origen, así que
-- todo va a la pieza más grande del destino: los Attachments conservan su posición relativa (escalada al
-- tamaño del destino) y los efectos que estaban directo en una pieza pasan a emitir desde la superficie de
-- esa pieza. Tamaños y velocidades se escalan igual (o con `scaleOverride`). `sourcePivot`/`targetPivot`
-- permiten fijar los puntos de referencia a mano. Devuelve cuántos efectos copió.
function EffectCopy.copy(source: Instance, target: Instance, scaleOverride: number?, sourcePivot: CFrame?, targetPivot: CFrame?): number
	local targetPart = EffectCopy.largestPart(target)
	if not targetPart then
		warn(`[EffectCopy] "{target.Name}" no tiene piezas donde poner efectos`)
		return 0
	end
	local scale = scaleOverride
		or EffectCopy.extents(target).Magnitude / math.max(EffectCopy.extents(source).Magnitude, 0.01)
	local fromPivot = sourcePivot or EffectCopy.pivot(source)
	local toPivot = targetPivot or EffectCopy.pivot(target)

	local attachments: { [Attachment]: Attachment } = {}
	local function placeAttachment(original: Attachment): Attachment
		if attachments[original] then
			return attachments[original]
		end
		local offset = fromPivot:ToObjectSpace(original.WorldCFrame)
		local copy = Instance.new("Attachment")
		copy.Name = EffectCopy.NAME
		copy.Parent = targetPart
		copy.WorldCFrame = toPivot * (offset.Rotation + offset.Position * scale)
		attachments[original] = copy
		return copy
	end

	local copied, skippedScripts = 0, 0
	for _, original in source:GetDescendants() do
		if original:IsA("LuaSourceContainer") then
			skippedScripts += 1
			continue
		end
		if not isEffect(original) then
			continue
		end
		local parent = original.Parent
		local newParent: Instance
		if parent and parent:IsA("Attachment") then
			newParent = placeAttachment(parent)
		elseif parent and parent:IsA("BasePart") or original:IsA("Beam") then
			newParent = targetPart
		else
			continue
		end

		local effect: any = original:Clone()
		effect.Name = EffectCopy.NAME
		if original:IsA("ParticleEmitter") then
			effect.Size = EffectCopy.scaleSequence(effect.Size, scale)
			effect.Speed = NumberRange.new(effect.Speed.Min * scale, effect.Speed.Max * scale)
			effect.Acceleration *= scale
		elseif original:IsA("Beam") or original:IsA("Trail") then
			effect.Attachment0 = if effect.Attachment0 then placeAttachment(effect.Attachment0) else nil
			effect.Attachment1 = if effect.Attachment1 then placeAttachment(effect.Attachment1) else nil
		elseif original:IsA("Light") then
			effect.Range *= scale
		elseif original:IsA("Fire") or original:IsA("Smoke") then
			effect.Size *= scale
		end
		effect.Parent = newParent
		copied += 1
	end

	-- los avisos salen una sola vez por modelo de origen, aunque se copie a muchos objetos
	if not warnedSources[source] then
		warnedSources[source] = true
		if copied == 0 then
			warn(`[EffectCopy] "{source.Name}" no tiene efectos (ParticleEmitter, Beam, luces...) para copiar`)
		end
		if skippedScripts > 0 then
			-- Algunos paquetes animan sus efectos con scripts; esos efectos pueden verse quietos o apagados en la copia.
			warn(`[EffectCopy] se ignoraron {skippedScripts} script(s) de "{source.Name}"; si algún efecto no se ve, revísalos`)
		end
	end
	return copied
end

-- Cambia qué tan visibles son los efectos: con `boost` > 1 más opacos, brillantes y con más partículas;
-- con `boost` < 1 más tenues.
function EffectCopy.boostVisibility(root: Instance, boost: number)
	local function opaquer(sequence: NumberSequence): NumberSequence
		local keypoints = {}
		for _, keypoint in sequence.Keypoints do
			table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.Time, math.min(keypoint.Value / boost, 1), keypoint.Envelope))
		end
		return NumberSequence.new(keypoints)
	end
	for _, effect in root:GetDescendants() do
		if effect:IsA("ParticleEmitter") then
			effect.Rate *= boost
			effect.Brightness *= boost
			effect.LightEmission = math.max(effect.LightEmission, 0.8)
			effect.Transparency = opaquer(effect.Transparency)
		elseif effect:IsA("Beam") or effect:IsA("Trail") then
			effect.Brightness *= boost
			effect.LightEmission = math.max(effect.LightEmission, 0.8)
			effect.Transparency = opaquer(effect.Transparency)
		elseif effect:IsA("Light") then
			effect.Brightness *= boost
		end
	end
end

-- Achica los efectos sin moverlos de lugar (tamaño de partículas, grosor de haces y alcance de luces).
function EffectCopy.shrink(root: Instance, factor: number)
	for _, effect in root:GetDescendants() do
		if effect:IsA("ParticleEmitter") then
			effect.Size = EffectCopy.scaleSequence(effect.Size, factor)
			effect.Speed = NumberRange.new(effect.Speed.Min * factor, effect.Speed.Max * factor)
			effect.Acceleration *= factor
		elseif effect:IsA("Beam") then
			effect.Width0 *= factor
			effect.Width1 *= factor
		elseif effect:IsA("Trail") then
			effect.WidthScale = EffectCopy.scaleSequence(effect.WidthScale, factor)
		elseif effect:IsA("Light") then
			effect.Range *= factor
		elseif effect:IsA("Fire") or effect:IsA("Smoke") then
			(effect :: any).Size *= factor
		end
	end
end

return EffectCopy