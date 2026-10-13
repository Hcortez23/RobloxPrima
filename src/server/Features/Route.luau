-- Ruta principal marcada en el mundo (orientación sin luces fuertes): a lo largo de la entrada inicial y de los túneles
-- entre arenas (World.Route) van rieles con durmientes por el suelo, cables por el techo con focos pequeños de neón (sin
-- luz propia) y letreros colgantes: "▲ BASE" mirando hacia lo profundo y "▲ DESCENSO" mirando hacia la base. Seguir los
-- rieles hacia arriba lleva de vuelta a la base. El suelo y el techo se encuentran con rayos contra el terreno.
local World = require(script.Parent.World)

local STEP = 3 -- studs entre muestras del suelo y del techo
local SLEEPER_EVERY = 2 -- un durmiente cada tantas muestras
local SIGN_EVERY = 60 -- studs entre letreros
local GAUGE = 1.6 -- media separación entre rieles

local RAIL = Color3.fromRGB(96, 92, 90)
local SLEEPER = Color3.fromRGB(70, 52, 40)
local CABLE = Color3.fromRGB(28, 28, 32)
local BULB = Color3.fromRGB(255, 190, 90)
local SIGN = Color3.fromRGB(40, 42, 48)
local SIGN_TEXT = Color3.fromRGB(230, 180, 40)

local folder: Folder
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CastShadow = name, true, collide, false
	p.CanTouch, p.CanQuery = false, collide -- decoración: ni contactos ni rayos (disparos y gancho la atraviesan)
	p.Size, p.CFrame, p.Color, p.Material = size, cframe, color, material
	p.Parent = folder
	return p
end

-- pieza entre dos puntos (largo a lo largo de Z)
local function between(name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material): Part?
	local length = (b - a).Magnitude
	if length < 0.05 then return nil end
	return part(name, Vector3.new(thickness, thickness, length + 0.05), CFrame.lookAt((a + b) / 2, b), color, material, false)
end

-- placa colgante con un texto por cada cara: "front" lo ve quien mira hacia -facing, "back" quien mira hacia facing
local function sign(pos: Vector3, facing: Vector3, front: string, back: string)
	local plate = part("RouteSign", Vector3.new(7, 2.2, 0.4), CFrame.lookAt(pos, pos + facing), SIGN, Enum.Material.Metal, false)
	for _, face in { { Enum.NormalId.Front, front }, { Enum.NormalId.Back, back } } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face[1]
		gui.LightInfluence = 0.3
		gui.PixelsPerStud = 40
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = SIGN_TEXT
		label.Text = face[2]
		label.Parent = gui
		gui.Parent = plate
	end
end

-- Simplifica una línea de puntos (Ramer-Douglas-Peucker): quita los puntos que se desvían menos de `tolerance` del
-- tramo recto entre sus vecinos. Así los rieles y el cable van en pocas piezas largas en vez de una cada pocos studs.
local function simplify(points: { Vector3 }, tolerance: number): { Vector3 }
	if #points <= 2 then return points end
	local keep = table.create(#points, false)
	keep[1], keep[#points] = true, true
	local stack = { { 1, #points } }
	while #stack > 0 do
		local range = table.remove(stack)
		local first, last = range[1], range[2]
		local a, b = points[first], points[last]
		local ab = b - a
		local lengthSq = ab:Dot(ab)
		local worst, worstIndex = 0, nil
		for k = first + 1, last - 1 do
			local ap = points[k] - a
			local t = if lengthSq > 0 then math.clamp(ap:Dot(ab) / lengthSq, 0, 1) else 0
			local d = (ap - ab * t).Magnitude
			if d > worst then worst, worstIndex = d, k end
		end
		if worstIndex and worst > tolerance then
			keep[worstIndex] = true
			table.insert(stack, { first, worstIndex })
			table.insert(stack, { worstIndex, last })
		end
	end
	local result = {}
	for k, p in points do
		if keep[k] then table.insert(result, p) end
	end
	return result
end

-- piezas entre puntos consecutivos de una línea
local function chain(name: string, points: { Vector3 }, thickness: number, color: Color3, material: Enum.Material)
	for k = 2, #points do
		between(name, points[k - 1], points[k], thickness, color, material)
	end
end

-- Marca un tramo y devuelve la distancia acumulada y los puntos del suelo por donde van los rieles.
local function markSegment(seg, distanceSoFar: number): (number, { Vector3 })
	local floorPoints = {}
	local axis = seg.to - seg.from
	local length = axis.Magnitude
	if length < STEP then return distanceSoFar, floorPoints end
	local dir = axis.Unit
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.05 then return distanceSoFar + length, floorPoints end -- tramo vertical: sin rieles
	local side = flat.Unit:Cross(Vector3.yAxis).Unit

	local rails = { {}, {} }
	local cable = {}
	local sample = 0
	for d = STEP / 2, length, STEP do
		sample += 1
		local center = seg.from + dir * d
		local floorHit = workspace:Raycast(center, Vector3.yAxis * -(seg.radius + 6), terrainOnly)
		local ceilingHit = workspace:Raycast(center, Vector3.yAxis * (seg.radius + 6), terrainOnly)
		if floorHit then
			local floor = floorHit.Position + Vector3.yAxis * 0.15
			table.insert(floorPoints, floorHit.Position)
			if sample % SLEEPER_EVERY == 0 then
				part("Sleeper", Vector3.new(GAUGE * 2 + 1.4, 0.3, 0.8), CFrame.lookAt(floor, floor + flat), SLEEPER, Enum.Material.WoodPlanks, false)
			end
			table.insert(rails[1], floor - side * GAUGE + Vector3.yAxis * 0.3)
			table.insert(rails[2], floor + side * GAUGE + Vector3.yAxis * 0.3)
		end
		if ceilingHit then
			local point = ceilingHit.Position - Vector3.yAxis * 1.2 + side * 2
			table.insert(cable, point)
			if sample % (5 * SLEEPER_EVERY) == 0 then -- foco pequeño, solo neón (sin luz que ilumine de más)
				local bulb = part("CableBulb", Vector3.one * 0.6, CFrame.new(point - Vector3.yAxis * 0.4), BULB, Enum.Material.Neon, false)
				bulb.Shape = Enum.PartType.Ball
			end
			local total = distanceSoFar + d
			if math.floor(total / SIGN_EVERY) ~= math.floor((total - STEP) / SIGN_EVERY) then
				-- "▲ BASE" para quien viene de lo profundo, de regreso; "▲ DESCENSO" para quien va bajando
				sign(ceilingHit.Position - Vector3.yAxis * 3, flat, "▲ BASE", "▲ DESCENSO")
			end
		end
	end
	for _, rail in rails do
		chain("Rail", simplify(rail, 0.25), 0.3, RAIL, Enum.Material.Metal)
	end
	chain("Cable", simplify(cable, 0.6), 0.25, CABLE, Enum.Material.SmoothPlastic)
	return distanceSoFar + length, floorPoints
end
local Route = {
	-- Paths[k] = puntos del suelo del tramo k de World.Route, en orden desde la cueva del foso hacia abajo.
	-- Listo cuando workspace.RouteReady = true.
	Paths = {} :: { { Vector3 } },
}

function Route.Start()
	while workspace:GetAttribute("WorldReady") ~= true do -- la ruta de la capa 1 ya está tallada
		task.wait(0.25)
	end
	folder = Instance.new("Folder")
	folder.Name = "Route"
	folder.Parent = workspace
	local ok, err = pcall(function()
		local distance = 0
		for k, seg in World.Route do
			local points
			distance, points = markSegment(seg, distance)
			Route.Paths[k] = points
		end
	end)
	if not ok then
		warn(`[Route] no se pudo marcar la ruta: {err}`)
	end
	workspace:SetAttribute("RouteReady", true)
end

return Route
