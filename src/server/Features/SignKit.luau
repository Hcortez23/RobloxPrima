-- Carteles con texto, todos con el mismo acabado (no es una feature con Start: lo usan Bases, BaseDecor, Mural,
-- LayerHubs, Carts, Hub, Route y Mines). Cada cartel es una placa con marco metálico, perfil de neón del color de
-- acento, tornillos en las esquinas y, en la cara, un fondo con degradado, una franja de color arriba y el texto con
-- contorno oscuro y márgenes amplios para que se lea bien de lejos. Opcionalmente un subtítulo separado por una línea,
-- texto en las dos caras y un brillo suave.
--
-- SignKit.Build(parent, name, cframe, width, height, options) → { model, title, sub, backTitle, backSub }
--   cframe: centro de la placa; su frente (-Z, LookVector) mira hacia quien lee.
--   options.title / options.sub: texto del frente (sub opcional, más chico, debajo).
--   options.backTitle / options.backSub: texto del dorso (sin backTitle, el dorso queda liso).
--   options.accent: color del perfil, la franja y el título (por defecto amarillo de advertencia).
--   options.style: "metal" (por defecto), "rust" (oxidado, para las minas) o "screen" (pantalla: letra monoespaciada,
--     texto alineado a la izquierda, sin tornillos).
--   options.bolts (true), options.glow (false: luz suave del color de acento), options.depth (0.4),
--   options.titleColor / options.subColor, options.subRatio (alto del subtítulo, 0.34), options.font.
-- Los TextLabel devueltos se pueden cambiar después (por ejemplo, el nombre del dueño en los arcos).
local SignKit = {}

SignKit.HAZARD = Color3.fromRGB(240, 190, 50)
SignKit.CYAN = Color3.fromRGB(110, 210, 255)
SignKit.GREEN = Color3.fromRGB(110, 255, 150)

local STYLES = {
	metal = {
		plate = Color3.fromRGB(26, 28, 34), plateMaterial = Enum.Material.SmoothPlastic,
		frame = Color3.fromRGB(78, 82, 92), frameMaterial = Enum.Material.Metal,
		top = Color3.fromRGB(34, 37, 46), bottom = Color3.fromRGB(14, 15, 20),
		font = Enum.Font.GothamBlack, subFont = Enum.Font.GothamBold, align = Enum.TextXAlignment.Center,
	},
	rust = {
		plate = Color3.fromRGB(52, 36, 28), plateMaterial = Enum.Material.CorrodedMetal,
		frame = Color3.fromRGB(110, 62, 40), frameMaterial = Enum.Material.CorrodedMetal,
		top = Color3.fromRGB(58, 40, 30), bottom = Color3.fromRGB(28, 20, 16),
		font = Enum.Font.GothamBlack, subFont = Enum.Font.GothamBold, align = Enum.TextXAlignment.Center,
	},
	screen = {
		plate = Color3.fromRGB(8, 10, 14), plateMaterial = Enum.Material.Glass,
		frame = Color3.fromRGB(44, 47, 54), frameMaterial = Enum.Material.Metal,
		top = Color3.fromRGB(12, 22, 30), bottom = Color3.fromRGB(4, 6, 10),
		font = Enum.Font.Code, subFont = Enum.Font.Code, align = Enum.TextXAlignment.Left,
	},
}

local function piece(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = name, true, false, false, false, false
	p.Size, p.CFrame, p.Color, p.Material = size, cframe, color, material
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- texto con contorno oscuro (se lee sobre cualquier fondo y desde lejos)
local function label(parent: Instance, order: number, height: number, text: string, color: Color3, font: Enum.Font, align: Enum.TextXAlignment, stroke: number): TextLabel
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.fromScale(1, height)
	l.BackgroundTransparency = 1
	l.Font, l.TextScaled, l.TextWrapped = font, true, true
	l.TextColor3, l.Text = color, text
	l.TextXAlignment = align
	l.LineHeight = 1.05
	local outline = Instance.new("UIStroke")
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = stroke
	outline.Transparency = 0.15
	outline.Parent = l
	l.Parent = parent
	return l
end

-- Cara del cartel: fondo con degradado, franja de color arriba, márgenes, título y (si hay) línea y subtítulo.
local function face(plate: BasePart, normal: Enum.NormalId, title: string, sub: string?, opts, style, accent: Color3): (TextLabel, TextLabel?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = normal
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(style.top, style.bottom)
	gradient.Rotation = 90
	gradient.Parent = back
	back.Parent = gui
	local band = Instance.new("Frame") -- franja de color arriba
	band.Size = UDim2.new(1, 0, 0.07, 0)
	band.BackgroundColor3 = accent
	band.BorderSizePixel = 0
	band.Parent = back
	local glow = Instance.new("UIGradient")
	glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.6) })
	glow.Parent = band
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromScale(0, 0.07)
	content.Size = UDim2.fromScale(1, 0.93)
	content.Parent = back
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.07, 0), UDim.new(0.07, 0)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.13, 0), UDim.new(0.13, 0)
	pad.Parent = content
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0.04, 0)
	list.Parent = content
	local align = opts.align or style.align
	local titleColor = opts.titleColor or (if opts.style == "screen" then accent else accent:Lerp(Color3.new(1, 1, 1), 0.2))
	if not sub then
		return label(content, 1, 1, title, titleColor, opts.font or style.font, align, 3), nil
	end
	local subRatio = opts.subRatio or 0.34
	local t = label(content, 1, 0.96 - subRatio - 0.06, title, titleColor, opts.font or style.font, align, 3)
	local rule = Instance.new("Frame") -- línea entre título y subtítulo
	rule.LayoutOrder = 2
	rule.Size = UDim2.new(if align == Enum.TextXAlignment.Center then 0.45 else 1, 0, 0, 4)
	rule.BackgroundColor3 = accent
	rule.BackgroundTransparency = 0.25
	rule.BorderSizePixel = 0
	rule.Parent = content
	local s = label(content, 3, subRatio, sub, opts.subColor or Color3.fromRGB(225, 228, 235), style.subFont, align, 2)
	return t, s
end

function SignKit.Build(parent: Instance, name: string, cframe: CFrame, width: number, height: number, opts)
	opts = opts or {}
	local style = STYLES[opts.style or "metal"]
	local accent = opts.accent or SignKit.HAZARD
	local depth = opts.depth or 0.4
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local plate = piece(model, "Plate", Vector3.new(width, height, depth), cframe, style.plate, style.plateMaterial)
	-- marco: cuatro barras que sobresalen un poco por delante y por detrás
	local t = math.clamp(math.min(width, height) * 0.06, 0.18, 0.4)
	local frameDepth = depth + 0.16
	for _, s in { -1, 1 } do
		piece(model, "Frame", Vector3.new(width + t * 2, t, frameDepth), cframe * CFrame.new(0, s * (height / 2 + t / 2), 0), style.frame, style.frameMaterial)
		piece(model, "Frame", Vector3.new(t, height, frameDepth), cframe * CFrame.new(s * (width / 2 + t / 2), 0, 0), style.frame, style.frameMaterial)
	end
	-- perfil de neón por dentro del marco, en las caras con texto
	local edge = 0.07
	local faces = { -1 }
	if opts.backTitle then table.insert(faces, 1) end
	for _, side in faces do
		local z = side * (depth / 2 + 0.02)
		for _, s in { -1, 1 } do
			piece(model, "Edge", Vector3.new(width, edge, 0.04), cframe * CFrame.new(0, s * (height / 2 - edge / 2), z), accent, Enum.Material.Neon).Transparency = 0.1
			piece(model, "Edge", Vector3.new(edge, height, 0.04), cframe * CFrame.new(s * (width / 2 - edge / 2), 0, z), accent, Enum.Material.Neon).Transparency = 0.1
		end
		-- tornillos en las esquinas
		if opts.bolts ~= false and opts.style ~= "screen" and math.min(width, height) >= 1.2 then
			for _, cx in { -1, 1 } do
				for _, cy in { -1, 1 } do
					piece(model, "Bolt", Vector3.one * 0.22, cframe * CFrame.new(cx * (width / 2 + t / 2), cy * (height / 2 + t / 2), side * (frameDepth / 2 + 0.03)), Color3.fromRGB(150, 154, 162), Enum.Material.Metal, Enum.PartType.Ball)
				end
			end
		end
	end
	if opts.glow then
		local l = Instance.new("PointLight")
		l.Color, l.Range, l.Brightness, l.Shadows = accent, math.max(width, height) * 0.9, 0.35, false
		l.Parent = plate
	end

	local result = { model = model, plate = plate, title = nil, sub = nil, backTitle = nil, backSub = nil }
	result.title, result.sub = face(plate, Enum.NormalId.Front, opts.title or "", opts.sub, opts, style, accent)
	if opts.backTitle then
		result.backTitle, result.backSub = face(plate, Enum.NormalId.Back, opts.backTitle, opts.backSub, opts, style, accent)
	end
	return result
end

return SignKit
