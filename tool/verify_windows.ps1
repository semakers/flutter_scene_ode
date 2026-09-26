# Compila ODE para Windows con MSVC y coteja el binario, SIN construir la app.
#
# Es el hermano de tool/verify_apple.sh y existe por lo mismo: la maquina que
# compila Windows tiene 4 nucleos, y un `flutter build windows` entero se paga
# en minutos. Esto compila solo las 75 unidades y dice si la DLL sirve.
#
# La carga de ODE es de fallo BLANDO: sin este banco, una DLL sin simbolos, en
# doble precision o que ni se copia da exactamente el mismo sintoma que no
# tener soporte de Windows -- la pantalla honesta del mecano.
#
# Uso (desde la maquina Linux):
#   scp tool/verify_windows.ps1 winpc:C:/dev/flutter_scene_ode/tool/
#   ssh winpc powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\flutter_scene_ode\tool\verify_windows.ps1
#
# NUNCA en linea: el escapado ssh -> cmd.exe -> powershell se come las comillas.

param(
  [string]$Repo = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$Config = 'Release'
)

$ErrorActionPreference = 'Stop'
$paso = 0
function Paso($t) { $script:paso++; Write-Output ""; Write-Output "== $script:paso. $t" }

Write-Output "flutter_scene_ode: verificando el build de Windows"
Write-Output "repo:   $Repo"
Write-Output "config: $Config"

# Fuera de %TEMP%: MSBuild avisa (MSB8029) de que un directorio intermedio en
# el temporal rompe el build incremental.
$Build = 'C:\dev\flutter-scene-ode-verify'
if (Test-Path $Build) { Remove-Item $Build -Recurse -Force }
New-Item -ItemType Directory -Path $Build | Out-Null

# ---------------------------------------------------------------------------
Paso 'configurando cmake'

# Se configura a traves de un envoltorio con add_subdirectory, y no apuntando
# cmake -S directamente a windows/, PORQUE ASI ES COMO LO CONSUME FLUTTER:
# generated_plugins.cmake hace add_subdirectory(...\.plugin_symlinks\flutter_scene_ode\windows).
# Solo por esta via existe un ambito padre donde comprobar que
# flutter_scene_ode_bundled_libraries llega de verdad -- que es la linea de la que
# depende que la DLL acabe junto al .exe.
# Here-string de comilla SIMPLE: en uno de comilla doble PowerShell interpola
# ${...}, que es justo la sintaxis de variable de CMake, y el fichero sale roto.
$wrapper = @'
cmake_minimum_required(VERSION 3.14)
project(verify_flutter_scene_ode LANGUAGES CXX C)
# EL ARNES TIENE QUE MENTIR COMO MIENTE LA APP.
# nairda_robot_programming/windows/CMakeLists.txt:33 hace esto antes de incluir
# generated_plugins.cmake, y add_definitions se hereda por add_subdirectory. Sin
# esta linea el banco daria VERDE y `flutter build windows` moriria despues en
# ode/src/error.cpp:145 con un C2664 de MessageBoxW. Un banco que no reproduce
# el entorno del build de verdad no esta probando nada.
add_definitions(-DUNICODE -D_UNICODE)
# La app define una configuracion Profile ademas de Debug/Release.
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")
add_subdirectory("@REPO@/windows" plugin)
if(NOT flutter_scene_ode_bundled_libraries)
  message(FATAL_ERROR "flutter_scene_ode_bundled_libraries llego VACIA al ambito padre: la DLL no viajaria junto al .exe")
endif()
message(STATUS "bundled_libraries = ${flutter_scene_ode_bundled_libraries}")
'@ -replace '@REPO@', ($Repo -replace '\\','/')
Set-Content -Path (Join-Path $Build 'CMakeLists.txt') -Value $wrapper -Encoding ASCII

Push-Location $Build
try {
  $cfg = & cmake -S $Build -B "$Build\out" -G 'Visual Studio 17 2022' -A x64 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Write-Output $cfg; throw "cmake configure fallo (codigo $LASTEXITCODE)" }
  ($cfg -split "`n") | Where-Object { $_ -match 'bundled_libraries|unidades' } | ForEach-Object { "   $($_.Trim())" }
} finally { Pop-Location }

# ---------------------------------------------------------------------------
Paso 'compilando las 75 unidades'

$log = "$Build\build.log"
& cmake --build "$Build\out" --config $Config -- /m /nologo /verbosity:minimal *>&1 |
  Tee-Object -FilePath $log | Select-Object -Last 6 | ForEach-Object { "   $_" }
if ($LASTEXITCODE -ne 0) {
  Write-Output ""
  Write-Output "-- errores --"
  Select-String -Path $log -Pattern 'error [A-Z]+[0-9]+' |
    Select-Object -First 25 | ForEach-Object { "   $($_.Line.Trim())" }
  throw "la compilacion fallo (codigo $LASTEXITCODE). Log entero: $log"
}

# Solo los del target `ode`: el arbol de build trae ademas los de las sondas
# del compilador de cmake (CMakeCXXCompilerId y compania), que no son ODE.
$objs = @(Get-ChildItem "$Build\out" -Recurse -Filter '*.obj' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\ode\.dir\\' })
Write-Output "   $($objs.Count) objetos del target ode"
if ($objs.Count -ne 75) { throw "esperaba 75 objetos y hay $($objs.Count)" }

$dll = Get-ChildItem "$Build\out" -Recurse -Filter 'ode.dll' | Select-Object -First 1
if ($null -eq $dll) {
  # El nombre importa: ode_library.dart busca literalmente 'ode.dll'.
  $otras = (Get-ChildItem "$Build\out" -Recurse -Filter '*.dll' | ForEach-Object { $_.Name }) -join ', '
  throw "no se genero ode.dll (hay: $otras). El target de CMake debe llamarse 'ode'."
}
Write-Output ("   ode.dll: {0:N0} bytes" -f $dll.Length)

# ---------------------------------------------------------------------------
Paso 'simbolos exportados'

$dumpbin = Get-ChildItem 'C:\Program Files*\Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe' -ErrorAction SilentlyContinue |
  Sort-Object FullName -Descending | Select-Object -First 1
if ($null -eq $dumpbin) { throw "no encuentro dumpbin.exe" }

$exports = & $dumpbin.FullName /exports $dll.FullName 2>&1 | Out-String

# Sin ODE_DLL+ODE_EXPORTS la DLL se construye igual y no exporta NADA:
# DynamicLibrary.open la abriria y el primer lookup fallaria en ejecucion.
$faltan = @()
foreach ($s in @('dInitODE2','dWorldQuickStep','dCreateCylinder','dCheckConfiguration','dCreateRay','dJointGetHingeAnchor')) {
  # Comparacion explicita contra $null: Select-String sin -Quiet devuelve
  # objetos, y una coleccion vacia no siempre es falsa en un if.
  if ($null -eq ($exports | Select-String -Pattern "\b$s\b" -Quiet | Where-Object { $_ })) {
    $faltan += $s
  } else { Write-Output "   OK    $s" }
}
if ($faltan.Count -gt 0) {
  throw "faltan simbolos exportados: $($faltan -join ', '). Revisa ODE_DLL/ODE_EXPORTS."
}

$n = ([regex]::Matches($exports, '(?m)^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]{8}\s+\w')).Count
Write-Output "   $n simbolos exportados en total"

# ---------------------------------------------------------------------------
Paso 'guardia de ABI: precision simple'

# Los bindings tienen dReal = ffi.Float CLAVADO. Un ODE en doble precision no
# da error de enlace ni de carga: lee basura. La cadena la pone dGetConfiguration.
$bytes = [System.IO.File]::ReadAllBytes($dll.FullName)
$texto = [System.Text.Encoding]::ASCII.GetString($bytes)
if (-not $texto.Contains('ODE_single_precision')) {
  if ($texto.Contains('ODE_double_precision')) {
    throw "la DLL es DOBLE precision: los bindings leerian basura. Falta -DdIDESINGLE."
  }
  throw "no encuentro la cadena de configuracion de ODE en la DLL"
}
Write-Output "   OK    ODE_single_precision"

Write-Output ""
Write-Output "VERDE: ode.dll compila, exporta y es precision simple."
Write-Output "ruta: $($dll.FullName)"
