# Genera assets/models/Minerals/Mineral_<Rareza>.model.json (una forma distinta por rareza) y
# src/workspace/TestRoom.model.json (la sala de pruebas ya colocada, visible también sin darle a Play).
# Uso (desde la raíz del repo): powershell -ExecutionPolicy Bypass -File tools/generate-mineral-models.ps1
# Los modelos están centrados en el origen; TestRoom los clona y los coloca con PivotTo.
$ErrorActionPreference = "Stop"
$Scale = 2 # tamaño de todos los minerales (1 = diseño original de ~2-3 studs)
$outDir = Join-Path $PSScriptRoot "..\assets\models\Minerals"
New-Item -ItemType Directory -Force $outDir | Out-Null

function Rad([double]$deg) { $deg * [Math]::PI / 180 }

# Matrices 3x3 como arreglos de filas.
function MatMul($a, $b) {
	$r = @(@(0.0, 0.0, 0.0), @(0.0, 0.0, 0.0), @(0.0, 0.0, 0.0))
	for ($i = 0; $i -lt 3; $i++) { for ($j = 0; $j -lt 3; $j++) {
		$r[$i][$j] = $a[$i][0] * $b[0][$j] + $a[$i][1] * $b[1][$j] + $a[$i][2] * $b[2][$j]
	} }
	return , $r
}
function RotX([double]$deg) { $c = [Math]::Cos((Rad $deg)); $s = [Math]::Sin((Rad $deg)); return , @(@(1.0, 0.0, 0.0), @(0.0, $c, - $s), @(0.0, $s, $c)) }
function RotY([double]$deg) { $c = [Math]::Cos((Rad $deg)); $s = [Math]::Sin((Rad $deg)); return , @(@($c, 0.0, $s), @(0.0, 1.0, 0.0), @(- $s, 0.0, $c)) }
function RotZ([double]$deg) { $c = [Math]::Cos((Rad $deg)); $s = [Math]::Sin((Rad $deg)); return , @(@($c, - $s, 0.0), @($s, $c, 0.0), @(0.0, 0.0, 1.0)) }
function MatVec($m, $v) { return , @(($m[0][0] * $v[0] + $m[0][1] * $v[1] + $m[0][2] * $v[2]), ($m[1][0] * $v[0] + $m[1][1] * $v[1] + $m[1][2] * $v[2]), ($m[2][0] * $v[0] + $m[2][1] * $v[1] + $m[2][2] * $v[2])) }
function Round3($m) { return , @($m | ForEach-Object { , @($_ | ForEach-Object { [Math]::Round($_, 4) }) }) }

function Color($rgb) { return , @(($rgb[0] / 255), ($rgb[1] / 255), ($rgb[2] / 255)) }

function NewPart([string]$name, $size, $position, $rotation, [string]$material, $rgb, [double]$transparency = 0, [string]$shape = "Block") {
	$part = [ordered]@{
		name       = $name
		className  = "Part"
		properties = [ordered]@{
			Anchored     = $true
			CanCollide   = $false
			CastShadow   = $false
			Material     = $material
			Color        = (Color $rgb)
			Transparency = $transparency
			Size         = @($size | ForEach-Object { [Math]::Round($_ * $Scale, 4) })
			CFrame       = @{ CFrame = @{ position = @($position | ForEach-Object { [Math]::Round($_ * $Scale, 4) }); orientation = (Round3 $rotation) } }
		}
	}
	if ($shape -ne "Block") { $part.properties["Shape"] = $shape }
	return $part
}

# Un cristal: cuerpo de sección de rombo (girado 45°) y una punta más fina encima.
# Nace en `base`, se inclina `tilt` grados y apunta hacia `yaw`.
function Shard([string]$name, $base, [double]$yaw, [double]$tilt, [double]$width, [double]$height, [string]$material, $rgb, [double]$transparency = 0) {
	$rot = MatMul (MatMul (RotY $yaw) (RotX $tilt)) (RotY 45)
	$bodyCenter = MatVec $rot @(0, ($height / 2), 0)
	$tipHeight = $height * 0.35
	$tipCenter = MatVec $rot @(0, ($height + $tipHeight / 2 - 0.05), 0)
	$tipRot = MatMul $rot (RotY 0)
	return @(
		(NewPart $name @($width, $height, $width) @(($base[0] + $bodyCenter[0]), ($base[1] + $bodyCenter[1]), ($base[2] + $bodyCenter[2])) $rot $material $rgb $transparency),
		(NewPart "$($name)Tip" @(($width * 0.55), $tipHeight, ($width * 0.55)) @(($base[0] + $tipCenter[0]), ($base[1] + $tipCenter[1]), ($base[2] + $tipCenter[2])) $tipRot $material $rgb $transparency)
	)
}

# Columna de sección octagonal (dos bloques cruzados a 45°) con la cara de arriba plana, como cuarzo.
function Prism([string]$name, $base, [double]$yaw, [double]$tilt, [double]$width, [double]$height, [string]$material, $rgb, [double]$transparency = 0) {
	$rot = MatMul (RotY $yaw) (RotX $tilt)
	$center = MatVec $rot @(0, ($height / 2), 0)
	$position = @(($base[0] + $center[0]), ($base[1] + $center[1]), ($base[2] + $center[2]))
	return @(
		(NewPart $name @($width, $height, $width) $position $rot $material $rgb $transparency),
		(NewPart "$($name)B" @($width, $height, $width) $position (MatMul $rot (RotY 45)) $material $rgb $transparency)
	)
}

# Bloque de roca girado en los tres ejes, para armar trozos irregulares.
function RockChunk([string]$name, $size, $position, [double]$rx, [double]$ry, [double]$rz, $rgb, [string]$material = "Slate") {
	return NewPart $name $size $position (MatMul (MatMul (RotY $ry) (RotX $rx)) (RotZ $rz)) $material $rgb
}

$rockColor = @(55, 58, 64)
$models = [ordered]@{}

# Común (~1.8 studs): trozo de roca irregular con vetas de mineral gris asomando. Mena tosca, sin brillo.
$c = @(150, 150, 160)
$models["Comun"] = @(
	(RockChunk "Rock1" @(1.3, 0.9, 1.1) @(0, 0, 0) 12 20 8 $rockColor)
	(RockChunk "Rock2" @(0.9, 0.8, 0.8) @(0.45, 0.25, -0.2) -18 55 22 $rockColor "Basalt")
	(RockChunk "Rock3" @(0.8, 0.7, 0.9) @(-0.4, 0.15, 0.3) 25 -30 -15 $rockColor "Basalt")
	(RockChunk "Rock4" @(0.7, 0.6, 0.6) @(0.1, 0.5, 0.35) -10 70 30 $rockColor)
	(RockChunk "Vein1" @(0.35, 0.35, 0.35) @(0.55, 0.55, 0.15) 45 45 0 $c "Metal")
	(RockChunk "Vein2" @(0.3, 0.3, 0.3) @(-0.55, 0.4, -0.15) 30 15 45 $c "Metal")
	(RockChunk "Vein3" @(0.28, 0.28, 0.28) @(0.05, 0.65, -0.3) 10 60 35 $c "Metal")
	(RockChunk "Vein4" @(0.25, 0.25, 0.25) @(-0.2, -0.35, 0.5) 50 20 10 $c "Metal")
)

# Raro (~2.4 studs): drusa de columnas de cuarzo azul de caras planas sobre una losa, con núcleo de neón.
$c = @(60, 140, 255)
$models["Raro"] = @(
	(RockChunk "Base" @(1.6, 0.35, 1.3) @(0, -0.9, 0) 0 15 0 $rockColor)
	(Prism "Column1" @(0, -0.75, 0) 0 0 0.5 1.9 "Glass" $c 0.25)
	(NewPart "Core" @(0.2, 1.5, 0.2) @(0, 0.05, 0) (RotY 22.5) "Neon" $c)
	(Prism "Column2" @(0.42, -0.75, 0.1) 20 12 0.38 1.35 "Glass" $c 0.2)
	(Prism "Column3" @(-0.38, -0.75, 0.2) 60 10 0.36 1.15 "Glass" $c 0.2)
	(Prism "Column4" @(0.1, -0.75, -0.42) 35 14 0.34 1.0 "Glass" $c 0.2)
	(Prism "Column5" @(-0.3, -0.75, -0.3) 80 18 0.28 0.75 "Glass" $c 0.2)
	(Prism "Column6" @(0.5, -0.75, -0.3) 10 22 0.24 0.6 "Glass" $c 0.2)
)

# Épico (~2.8 studs): erizo flotante sin roca; esfera de energía con púas de cristal en todas direcciones.
$c = @(170, 70, 255)
$epic = @(
	(NewPart "Core" @(0.75, 0.75, 0.75) @(0, 0, 0) (RotY 0) "Neon" $c 0 "Ball")
	(NewPart "Shell" @(1.0, 1.0, 1.0) @(0, 0, 0) (RotY 0) "Glass" $c 0.6 "Ball")
)
# (inclinación desde arriba, giro): una arriba, una abajo y dos anillos de púas alternando neón y vidrio
$spikes = @(@(0, 0), @(180, 0))
foreach ($yaw in 0, 90, 180, 270) { $spikes += , @(60, $yaw) }
foreach ($yaw in 45, 135, 225, 315) { $spikes += , @(120, $yaw) }
$i = 0
foreach ($spike in $spikes) {
	$i++
	$material = if ($i % 2 -eq 0) { "Neon" } else { "Glass" }
	$length = if ($spike[0] -eq 0) { 1.0 } else { 0.8 }
	$epic += , (Shard "Spike$i" @(0, 0, 0) $spike[1] $spike[0] 0.26 $length $material $c 0)
}
$models["Epico"] = $epic

# Legendario (~3.2 studs): gema gigante flotando sobre su vértice, núcleo brillante, halo inclinado de
# segmentos de neón y tres fragmentos en órbita. Luz propia.
$c = @(255, 190, 40)
$gem = MatMul (RotZ 54.7356) (RotY 45) # cubo apoyado en un vértice: diagonal (1,1,1) apuntando hacia arriba
$legendary = @(
	(NewPart "Gem" @(1.35, 1.35, 1.35) @(0, 0, 0) $gem "Glass" $c 0.15)
	(NewPart "Core" @(0.75, 0.75, 0.75) @(0, 0, 0) (MatMul $gem (RotY 45)) "Neon" $c)
)
$haloRadius = 1.45
$haloTilt = RotX 18
for ($k = 0; $k -lt 16; $k++) {
	$a = $k * 360 / 16
	$position = MatVec $haloTilt @(($haloRadius * [Math]::Cos((Rad $a))), 0, ($haloRadius * [Math]::Sin((Rad $a))))
	$segmentLength = 2 * [Math]::PI * $haloRadius / 16 * 1.05
	$legendary += , (NewPart "Halo$($k + 1)" @(0.1, 0.08, $segmentLength) $position (MatMul $haloTilt (RotY (-$a))) "Neon" $c)
}
foreach ($i in 0..2) {
	$angle = Rad (30 + $i * 120)
	$legendary += , (Shard "Orbit$($i + 1)" @((1.05 * [Math]::Cos($angle)), (-0.6 + 0.6 * $i), (1.05 * [Math]::Sin($angle))) (30 + $i * 120) 25 0.2 0.45 "Neon" $c)
}
$models["Legendario"] = $legendary
$parts = [ordered]@{}
foreach ($rarity in $models.Keys) {
	$children = @()
	foreach ($item in $models[$rarity]) { if ($item -is [array]) { $children += $item } else { $children += , $item } }
	if ($rarity -eq "Legendario") {
		$core = $children | Where-Object { $_.name -eq "Core" } | Select-Object -First 1
		$core["children"] = @(@{ className = "PointLight"; properties = [ordered]@{ Color = (Color $c); Range = 12; Brightness = 1.8; Shadows = $false } })
	}
	$parts[$rarity] = $children
	$model = [ordered]@{
		className  = "Model"
		attributes = @{ Rarity = $rarity; MineralModel = $true } # MineralModel: MineralFX lo hace girar y flotar
		children   = $children
	}
	$path = Join-Path $outDir "Mineral_$rarity.model.json"
	[IO.File]::WriteAllText($path, ($model | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
	"Generado $path ($($children.Count) piezas)"
}

# ---------------------------------------------------------------------------------------------------------
# Sala de pruebas ya colocada en Workspace (src/workspace/TestRoom.model.json), para verla también en modo
# edición. Mismo diseño que server/Features/TestRoom.luau, que no la vuelve a crear si ya existe.

# Copia de un mineral colocado en `position` y girado `yaw` grados, con tag Mineral para que el juego lo use.
function PlacedMineral([string]$rarity, $position, [double]$yaw) {
	$rot = RotY $yaw
	$children = @()
	foreach ($template in $parts[$rarity]) {
		$part = $template | ConvertTo-Json -Depth 20 | ConvertFrom-Json # copia profunda
		$cf = $part.properties.CFrame.CFrame
		$orientation = @($cf.orientation | ForEach-Object { , @($_) })
		$offset = MatVec $rot @($cf.position)
		$cf.position = @(($position[0] + $offset[0]), ($position[1] + $offset[1]), ($position[2] + $offset[2])) | ForEach-Object { [Math]::Round($_, 4) }
		$cf.orientation = Round3 (MatMul $rot $orientation)
		$children += , $part
	}
	return [ordered]@{
		name       = "Mineral_$rarity"
		className  = "Model"
		attributes = @{ Rarity = $rarity; MineralModel = $true } # MineralModel: MineralFX lo hace girar y flotar
		properties = @{ Tags = @("Mineral") }
		children   = $children
	}
}

$cell = 4
$roomChildren = @()
foreach ($wallZ in -30, -50) {
	for ($x = 0; $x -lt 10; $x++) {
		for ($y = 0; $y -lt 6; $y++) {
			$roomChildren += , [ordered]@{
				name       = "Cell"
				className  = "Part"
				properties = [ordered]@{
					Anchored = $true
					Material = "Concrete"
					Color    = (Color @(110, 115, 125))
					Size     = @($cell, $cell, $cell)
					Position = @((-20 + $x * $cell), ($y * $cell + $cell / 2), $wallZ)
					Tags     = @("Fracturable")
				}
			}
		}
	}
}
# dos aislados (explosión simple) y un cúmulo en el centro (cadena, vecinos a menos de 14 studs); giros fijos
# para que el archivo no cambie solo
$spots = @(
	@("Comun", -40, 6, 0), @("Legendario", 40, 8, 40),
	@("Raro", -11, 6, 80), @("Raro", 0, 10, 150), @("Epico", 10, 7, 210), @("Raro", -4, 4, 260), @("Comun", 17, 11, 320)
)
foreach ($spot in $spots) {
	$roomChildren += , (PlacedMineral $spot[0] @($spot[1], $spot[2], -20) $spot[3])
}
$room = [ordered]@{ className = "Folder"; children = $roomChildren }
$roomPath = Join-Path $PSScriptRoot "..\src\workspace\TestRoom.model.json"
[IO.File]::WriteAllText($roomPath, ($room | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
"Generado $roomPath ($($roomChildren.Count) objetos)"
