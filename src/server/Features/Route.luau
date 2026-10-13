-- Ruta principal marcada en el mundo (orientación sin luces fuertes): a lo largo de la entrada inicial y de los túneles
-- entre arenas (World.Route) van rieles con durmientes por el suelo, cables por el techo con focos pequeños de neón (sin
-- luz propia) y letreros colgantes: "▲ BASE" mirando hacia lo profundo y "▲ DESCENSO" mirando hacia la base. Seguir los
-- rieles hacia arriba lleva de vuelta a la base. El suelo y el techo se encuentran con rayos contra el terreno.
local World = require(script.Parent.World)

local STEP = 4 -- studs entre durmientes
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

-- Marca un tramo y devuelve la distancia acumulada y los puntos del suelo por donde van los rieles (los usan los
-- carritos, Carts.luau).
local function markSegment(seg, distanceSoFar: number): (number, { Vector3 })
	local floorPoints = {}
	local axis = seg.to - seg.from
	local length = axis.Magnitude
	if length < STEP then return distanceSoFar, floorPoints end
	local dir = axis.Unit
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.05 then return distanceSoFar + length, floorPoints end -- tramo vertical: sin rieles
	local side = flat.Unit:Cross(Vector3.yAxis).Unit

	local lastFloor, lastCeiling = nil, nil
	for d = STEP / 2, length, STEP do
		local center = seg.from + dir * d
		local floorHit = workspace:Raycast(center, Vector3.yAxis * -(seg.radius + 6), terrainOnly)
		local ceilingHit = workspace:Raycast(center, Vector3.yAxis * (seg.radius + 6), terrainOnly)
		if floorHit then
			local floor = floorHit.Position + Vector3.yAxis * 0.15
			table.insert(floorPoints, floorHit.Position)
			part("Sleeper", Vector3.new(GAUGE * 2 + 1.4, 0.3, 0.8), CFrame.lookAt(floor, floor + flat), SLEEPER, Enum.Material.WoodPlanks, false)
			if lastFloor then
				for _, s in { -1, 1 } do
					between("Rail", lastFloor + side * (s * GAUGE) + Vector3.yAxis * 0.3, floor + side * (s * GAUGE) + Vector3.yAxis * 0.3, 0.3, RAIL, Enum.Material.Metal)
				end
			end
			lastFloor = floor
		end
		if ceilingHit then
			local cable = ceilingHit.Position - Vector3.yAxis * 1.2 + side * 2
			if lastCeiling then
				between("Cable", lastCeiling, cable, 0.25, CABLE, Enum.Material.SmoothPlastic)
			end
			if math.floor(d / STEP) % 5 == 0 then -- foco pequeño, solo neón (sin luz que ilumine de más)
				local bulb = part("CableBulb", Vector3.one * 0.6, CFrame.new(cable - Vector3.yAxis * 0.4), BULB, Enum.Material.Neon, false)
				bulb.Shape = Enum.PartType.Ball
			end
			local total = distanceSoFar + d
			if math.floor(total / SIGN_EVERY) ~= math.floor((total - STEP) / SIGN_EVERY) then
				local signPos = ceilingHit.Position - Vector3.yAxis * 3
				-- "▲ BASE" para quien viene de lo profundo, de regreso; "▲ DESCENSO" para quien va bajando
				sign(signPos, flat, "▲ BASE", "▲ DESCENSO")
			end
			lastCeiling = cable
		end
	end
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
