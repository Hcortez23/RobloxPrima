-- Pantalla de la progresión por capas (server/Features/Progression):
--  · Presión: borde rojo que se intensifica y aviso "PRESIÓN · Sin permiso para la CAPA N" (atributo Pressure 0..1).
--  · Avisos del servidor (Progress_Notify): permiso concedido, falta de valor o de poder de excavación, hub descubierto.
--  · Elevador (remote Elevator): menú con los hubs (disponible, sin descubrir o sin permiso) y transición a negro al viajar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local HAZARD = Color3.fromRGB(230, 180, 40)
local COLORS = { info = Color3.new(1, 1, 1), ok = Color3.fromRGB(120, 255, 150), error = Color3.fromRGB(255, 110, 90) }

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do (l :: any)[k] = v end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "ProgressionUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

-- Borde rojo de presión (cuatro franjas con degradado hacia dentro) y el aviso.
local function pressureOverlay(gui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Pressure"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui
	local edges = {}
	for _, spec in { { UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0), 90 }, { UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0.82), -90 }, { UDim2.fromScale(0.14, 1), UDim2.fromScale(0, 0), 0 }, { UDim2.fromScale(0.14, 1), UDim2.fromScale(0.86, 0), 180 } } do
		local edge = Instance.new("Frame")
		edge.Size, edge.Position = spec[1], spec[2]
		edge.BackgroundColor3 = Color3.fromRGB(200, 20, 10)
		edge.BorderSizePixel = 0
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec[3]
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = edge
		edge.Parent = frame
		table.insert(edges, edge)
	end
	local warning = label(frame, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.22), Size = UDim2.fromOffset(640, 34),
		Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 90, 70),
	})
	local hint = label(frame, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.22, 38), Size = UDim2.fromOffset(560, 22),
	})
	local function refresh()
		local level = player:GetAttribute("Pressure") or 0
		frame.Visible = level > 0
		for _, edge in edges do edge.BackgroundTransparency = 1 - (0.25 + 0.6 * level) end
		local layer = player:GetAttribute("PressureLayer") or 0
		warning.Text = `PRESIÓN · Sin permiso para la CAPA {layer}`
		hint.Text = if level >= 1 then "¡Sube ya! La presión te está aplastando." else "Sube a una capa con permiso antes de que te aplaste."
	end
	player:GetAttributeChangedSignal("Pressure"):Connect(refresh)
	refresh()
end

-- Avisos que llegan del servidor: uno a la vez, abajo al centro.
local function notifications(gui: ScreenGui)
	local toast = label(gui, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.fromOffset(720, 30), Visible = false,
	})
	local shownAt = 0
	Remotes.get("Progress_Notify").OnClientEvent:Connect(function(text: string, kind: string)
		toast.Text = text
		toast.TextColor3 = COLORS[kind] or COLORS.info
		toast.Visible = true
		local at = os.clock()
		shownAt = at
		task.delay(4.5, function()
			if shownAt == at then toast.Visible = false end
		end)
	end)
end

-- Menú del elevador y transición del viaje.
local function elevator(gui: ScreenGui)
	local remote = Remotes.get("Elevator")
	local menu = Instance.new("Frame")
	menu.Name = "ElevatorMenu"
	menu.AnchorPoint = Vector2.new(0.5, 0.5)
	menu.Position = UDim2.fromScale(0.5, 0.5)
	menu.Size = UDim2.fromOffset(380, 470)
	menu.BackgroundColor3 = Color3.fromRGB(16, 18, 22)
	menu.BackgroundTransparency = 0.1
	menu.Visible = false
	menu.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = menu
	local border = Instance.new("UIStroke")
	border.Color, border.Thickness = HAZARD, 2
	border.Parent = menu
	label(menu, { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 30), Text = "ELEVADOR", Font = Enum.Font.GothamBlack, TextColor3 = HAZARD })
	local list = Instance.new("Frame")
	list.Position = UDim2.fromOffset(14, 50)
	list.Size = UDim2.new(1, -28, 1, -100)
	list.BackgroundTransparency = 1
	list.Parent = menu
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -10)
	close.Size = UDim2.fromOffset(140, 30)
	close.BackgroundColor3 = Color3.fromRGB(60, 62, 70)
	close.Font, close.TextScaled, close.TextColor3 = Enum.Font.GothamBold, true, Color3.new(1, 1, 1)
	close.Text = "Cerrar"
	close.Parent = menu
	close.Activated:Connect(function() menu.Visible = false end)

	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.ZIndex = 10
	fade.Parent = gui
	local fadeText = label(fade, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 34), ZIndex = 11, TextTransparency = 1, TextColor3 = HAZARD })

	remote.OnClientEvent:Connect(function(action: string, a, b)
		if action == "open" then
			for _, child in list:GetChildren() do
				if child:IsA("TextButton") then child:Destroy() end
			end
			for _, entry in a do
				local button = Instance.new("TextButton")
				button.Size = UDim2.new(1, 0, 0, 32)
				button.Font, button.TextScaled = Enum.Font.GothamBold, true
				button.BorderSizePixel = 0
				button.LayoutOrder = entry.layer
				local here = entry.layer == b
				if here then
					button.Text = `CAPA {entry.layer} · {entry.name}  (aquí)`
					button.BackgroundColor3, button.TextColor3 = Color3.fromRGB(40, 44, 52), HAZARD
				elseif entry.state == "ok" then
					button.Text = `CAPA {entry.layer} · {entry.name}`
					button.BackgroundColor3, button.TextColor3 = Color3.fromRGB(34, 80, 50), Color3.new(1, 1, 1)
					button.Activated:Connect(function()
						menu.Visible = false
						remote:FireServer("go", entry.layer)
					end)
				elseif entry.state == "unknown" then
					button.Text = `CAPA {entry.layer} · sin descubrir`
					button.BackgroundColor3, button.TextColor3 = Color3.fromRGB(36, 38, 44), Color3.fromRGB(150, 150, 150)
				else
					button.Text = `CAPA {entry.layer} · sin permiso`
					button.BackgroundColor3, button.TextColor3 = Color3.fromRGB(60, 30, 30), Color3.fromRGB(200, 130, 120)
				end
				button.Parent = list
			end
			menu.Visible = true
		elseif action == "travel" then
			fadeText.Text = `Elevador → CAPA {a} · {b}`
			local inInfo, outInfo = TweenInfo.new(0.6), TweenInfo.new(0.8)
			TweenService:Create(fade, inInfo, { BackgroundTransparency = 0 }):Play()
			TweenService:Create(fadeText, inInfo, { TextTransparency = 0 }):Play()
			task.delay(1.8, function()
				TweenService:Create(fade, outInfo, { BackgroundTransparency = 1 }):Play()
				TweenService:Create(fadeText, outInfo, { TextTransparency = 1 }):Play()
			end)
		end
	end)
end

return {
	Start = function()
		local gui = build()
		pressureOverlay(gui)
		notifications(gui)
		elevator(gui)
	end,
}
