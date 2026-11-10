param([Parameter(Mandatory)][string] $CMakePath)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hgm_cmake_prefix_' + [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $testRoot 'source'
$buildRoot = Join-Path $testRoot 'build'
New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'flutter'),(Join-Path $sourceRoot 'runner') -Force | Out-Null
try {
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'windows\CMakeLists.txt') -Destination (Join-Path $sourceRoot 'CMakeLists.txt')
  @'
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/stub" "测试资源")
set(FLUTTER_ICU_DATA_FILE "${CMAKE_CURRENT_BINARY_DIR}/stub" PARENT_SCOPE)
set(FLUTTER_LIBRARY "${CMAKE_CURRENT_BINARY_DIR}/stub" PARENT_SCOPE)
set(AOT_LIBRARY "${CMAKE_CURRENT_BINARY_DIR}/stub" PARENT_SCOPE)
set(PROJECT_BUILD_DIR "${CMAKE_BINARY_DIR}/" PARENT_SCOPE)
'@ | Set-Content -LiteralPath (Join-Path $sourceRoot 'flutter\CMakeLists.txt')
  'add_executable(hgame_manager main.cpp)' | Set-Content -LiteralPath (Join-Path $sourceRoot 'runner\CMakeLists.txt')
  'int main() { return 0; }' | Set-Content -LiteralPath (Join-Path $sourceRoot 'runner\main.cpp')
  @'
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/allow-configure")
  message(FATAL_ERROR "模拟依赖配置中断")
endif()
'@ | Set-Content -LiteralPath (Join-Path $sourceRoot 'flutter\generated_plugins.cmake')
  & $CMakePath -S $sourceRoot -B $buildRoot -G 'Visual Studio 17 2022' -A x64 *> (Join-Path $testRoot 'first.log')
  if ($LASTEXITCODE -eq 0) { throw '首次配置没有按预期中断' }
  $expected = 'CMAKE_INSTALL_PREFIX:PATH=$<TARGET_FILE_DIR:hgame_manager>'
  $prefix = (Select-String -LiteralPath (Join-Path $buildRoot 'CMakeCache.txt') -Pattern '^CMAKE_INSTALL_PREFIX:PATH=').Line
  if ($prefix -ne $expected) { throw '首次配置中断后留下了错误安装路径' }
  Set-Content -LiteralPath (Join-Path $sourceRoot 'allow-configure') -Value '允许继续'
  & $CMakePath -S $sourceRoot -B $buildRoot *> (Join-Path $testRoot 'retry.log')
  if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath (Join-Path $testRoot 'retry.log') -Tail 15; throw '重试配置失败' }
  $prefix = (Select-String -LiteralPath (Join-Path $buildRoot 'CMakeCache.txt') -Pattern '^CMAKE_INSTALL_PREFIX:PATH=').Line
  if ($prefix -ne $expected) { throw '重试配置未保留构建目录' }
  & $CMakePath -S $sourceRoot -B $buildRoot '-DCMAKE_INSTALL_PREFIX=C:/Program Files/hgame_manager' *> (Join-Path $testRoot 'stale.log')
  if ($LASTEXITCODE -ne 0) { throw '旧缓存检查配置失败' }
  $prefix = (Select-String -LiteralPath (Join-Path $buildRoot 'CMakeCache.txt') -Pattern '^CMAKE_INSTALL_PREFIX:PATH=').Line
  if ($prefix -ne $expected) { throw '已有错误前缀未被纠正' }
  '通过：首次配置中断、重试配置、旧系统安装前缀均保持构建目录输出'
} finally {
  $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
  $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
  if (-not $resolvedRoot.StartsWith($temporaryRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
      -not [IO.Path]::GetFileName($resolvedRoot).StartsWith('hgm_cmake_prefix_')) { throw '拒绝清理测试范围外目录' }
  Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}
