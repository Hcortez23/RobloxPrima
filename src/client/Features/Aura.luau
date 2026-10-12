-- Aura elegante para cualquier Model o BasePart con el tag "Aura" (se pone en Studio: Properties -> Tags)
-- o cuyo nombre esté en Config.Aura.WorkspaceTargets.
-- Además copia efectos de modelos de VFX (ej. del Marketplace) a otros objetos según Config.Aura.CopyEffects.
-- Contorno brillante que "respira", luz suave y destellos finos que flotan desde la superficie.
-- Color opcional con el atributo AuraColor (Color3) en el objeto; si no, usa el de Config/Aura.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Aura)

local TAG = "Aura"
local NAME = "AuraEffect" -- nombre de todo lo que crea el aura, para poder quitarlo

-- Pieza más grande del objeto: ahí van la luz y los destellos.
local function largestPart(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	end
	local best, bestVolume = nil, 0
	for _, part in target:GetDescendants() do
		if part:IsA("BasePart") then
			local volume = part.Size.X * part.Size.Y * part.Size.Z
			if volume > bestVolume then
				best, bestVolume = part, volume
			end
		end
	end
	return best
end

local function removeAura(target: Instance)
	for _, child in target:GetDescendants() do
		if child.Name == NAME then
			child:Destroy()
		end
	end
end

-- Clases que se consideran "efecto" al copiar desde un modelo de VFX (los scripts nunca se copian).
local EFFECT_CLASSES = { "ParticleEmitter", "Beam", "Trail", "PointLight", "SpotLight", "SurfaceLight", "Fire", "Smoke", "Sparkles" }

local function isEffect(instance: Instance): boolean
	for _, className in EFFECT_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local function scaleSequence(sequence: NumberSequence, factor: number): NumberSequence
	local keypoints = {}
	for _, keypoint in sequence.Keypoints do
		table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * factor, keypoint.Envelope * factor))
	end
	return NumberSequence.new(keypoints)
end

local function extents(instance: Instance): Vector3
	return if instance:IsA("Model") then instance:GetExtentsSize() else (instance :: BasePart).Size
end

-- Busca Workspace.<path[1]>.<path[2]>... esperando a que cargue cada nivel.
local function findInWorkspace(path: { string }): Instance?
	local current: Instance? = workspace
	for _, name in path do
		current = current and current:WaitForChild(name, 10)
	end
	return current
end

-- Copia los efectos de `source` (ej. un Dummy de un paquete de auras del Marketplace) a `target`.
-- Las piezas del destino no coinciden con las del origen, así que todo va a la pieza más grande del destino:
-- los Attachments conservan su posición relativa (escalada al tamaño del destino) y los efectos que estaban
-- directo en una pieza pasan a emitir desde la superficie de esa pieza. Tamaños y velocidades se escalan igual.
local function copyEffects(source: Instance, target: Instance)
	local targetPart = largestPart(target)
	if not targetPart then
		warn(`[Aura] "{target.Name}" no tiene piezas donde poner efectos`)
		return
	end
	local scale = extents(target).Magnitude / math.max(extents(source).Magnitude, 0.01)
	local sourcePivot = (source :: PVInstance):GetPivot()
	local targetPivot = (target :: PVInstance):GetPivot()

	local attachments: { [Attachment]: Attachment } = {}
	local function placeAttachment(original: Attachment): Attachment
		if attachments[original] then
			return attachments[original]
		end
		local offset = sourcePivot:ToObjectSpace(original.WorldCFrame)
		local copy = Instance.new("Attachment")
		copy.Name = NAME
		copy.Parent = targetPart
		copy.WorldCFrame = targetPivot * (offset.Rotation + offset.Position * scale)
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
		effect.Name = NAME
		if original:IsA("ParticleEmitter") then
			effect.Size = scaleSequence(effect.Size, scale)
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

	if copied == 0 then
		warn(`[Aura] "{source.Name}" no tiene efectos (ParticleEmitter, Beam, luces...) para copiar`)
	end
	if skippedScripts > 0 then
		-- Algunos paquetes animan sus efectos con scripts; esos efectos pueden verse quietos o apagados en la copia.
		warn(`[Aura] se ignoraron {skippedScripts} script(s) de "{source.Name}"; si algún efecto no se ve, revísalos`)
	end
end

local function addAura(target: Instance)	if not (target:IsA("Model") or target:IsA("BasePart")) then
		return
	end
	removeAura(target)
	local color = target:GetAttribute("AuraColor")
	if typeof(color) ~= "Color3" then
		color = Config.Color
	end
	local pulse = TweenInfo.new(Config.PulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

	-- Contorno y relleno tenue que respiran.
	local highlight = Instance.new("Highlight")
	highlight.Name = NAME
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.92
	highlight.OutlineTransparency = 0.6
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = target
	highlight.Parent = target
	TweenService:Create(highlight, pulse, { FillTransparency = 0.8, OutlineTransparency = 0.15 }):Play()

	local part = largestPart(target)
	if not part then
		return
	end
	local radius = part.Size.Magnitude / 2

	local glow = Instance.new("PointLight")
	glow.Name = NAME
	glow.Color = color
	glow.Shadows = false
	glow.Range = radius + 4
	glow.Brightness = 0.6
	glow.Parent = part
	TweenService:Create(glow, pulse, { Brightness = 1.6, Range = radius + 7 }):Play()

	-- Destellos: la cantidad crece con el tamaño de la pieza, sin pasar de un tope para que siga siendo sutil.
	local motes = Instance.new("ParticleEmitter")
	motes.Name = NAME
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	motes.Rate = math.clamp(radius * 3, 4, Config.MaxParticles)
	motes.Lifetime = NumberRange.new(1.4, 2.4)
	motes.Speed = NumberRange.new(0.3, 0.8)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.SpreadAngle = Vector2.new(30, 30)
	motes.Acceleration = Vector3.new(0, 0.6, 0)
	motes.Drag = 1
	motes.Rotation = NumberRange.new(0, 360)
	motes.RotSpeed = NumberRange.new(-30, 30)
	local moteSize = math.clamp(radius * 0.06, 0.12, 0.4)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, moteSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Parent = part
end

return {
	Start = function()
		CollectionService:GetInstanceAddedSignal(TAG):Connect(addAura)
		CollectionService:GetInstanceRemovedSignal(TAG):Connect(removeAura)
		for _, target in CollectionService:GetTagged(TAG) do
			task.spawn(addAura, target)
		end
		-- Objetos puestos a mano en Workspace (ej. modelos del Marketplace), buscados por nombre.
		for _, name in Config.WorkspaceTargets do
			task.spawn(function()
				local target = workspace:WaitForChild(name, 10)
				if target then
					addAura(target)
				else
					warn(`[Aura] no se encontró "{name}" en Workspace`)
				end
			end)
		end
		-- Efectos copiados de un modelo de VFX a otro objeto (ver Config.Aura.CopyEffects).
		for _, entry in Config.CopyEffects do
			task.spawn(function()
				local source = findInWorkspace(entry.From)
				local target = findInWorkspace(entry.To)
				if source and target then
					copyEffects(source, target)
				else
					warn(`[Aura] no se encontró {table.concat(if source then entry.To else entry.From, ".")} en Workspace`)
				end
			end)
		end
	end,
}
