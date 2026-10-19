$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$version = '2.46.1'
$sha256 = 'd25c519bbde940dc953cff8901130ce18b73013dc19a8f8b90b8b4b1c5eb252f'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$toolsDirectory = Join-Path $projectDirectory '.tools'
$archive = Join-Path $toolsDirectory "allure-commandline-$version.zip"
$command = Join-Path $toolsDirectory "allure-$version\bin\allure.bat"
$url = "https://repo.maven.apache.org/maven2/io/qameta/allure/allure-commandline/$version/allure-commandline-$version.zip"

if (-not $env:JAVA_HOME -or -not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    throw 'Set JAVA_HOME to an installed JDK before running this script.'
}

New-Item -ItemType Directory -Path $toolsDirectory -Force | Out-Null
if (-not (Test-Path $archive)) {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
}

if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $sha256) {
    throw "SHA-256 mismatch for $archive. The archive was not extracted."
}

if (-not (Test-Path $command)) {
    Expand-Archive -LiteralPath $archive -DestinationPath $toolsDirectory
}

$actualVersion = & $command --version
if ($LASTEXITCODE -ne 0 -or "$actualVersion".Trim() -ne $version) {
    throw "Expected Allure Report $version, got: $actualVersion"
}

Write-Output "Allure Report $actualVersion is ready: $command"
