param([int]$Port = 0)
$ErrorActionPreference = 'Stop'
foreach ($command in @('initdb','pg_ctl','createdb','psql')) {
  if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Instale PostgreSQL e adicione $command ao PATH." }
}
if ($Port -eq 0) {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
  $listener.Start()
  $Port = $listener.LocalEndpoint.Port
  $listener.Stop()
}
$testRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) ('rmmi-db-test-' + [guid]::NewGuid().ToString('N'))))
$dataPath = Join-Path $testRoot 'data'
$logPath = Join-Path $testRoot 'postgres.log'
$running = $false
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
  & initdb -D $dataPath -A trust -U postgres --encoding=UTF8 --locale=C | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao inicializar banco de testes.' }
  # PostgreSQL descendants can inherit a PowerShell pipeline handle on Windows.
  # Redirect startup output to files so a server does not keep this pipeline open.
  $startArgs = '-D "' + $dataPath + '" -l "' + $logPath + '" -o "-h 127.0.0.1 -c wal_level=logical -p ' + $Port + '" -w start'
  $startProcess = Start-Process -FilePath (Get-Command pg_ctl).Source -ArgumentList $startArgs -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $testRoot 'start.out') -RedirectStandardError (Join-Path $testRoot 'start.err')
  $null = $startProcess.Handle
  $startProcess.WaitForExit()
  $running = Test-Path -LiteralPath (Join-Path $dataPath 'postmaster.pid')
  if (-not $running) { throw 'Falha ao iniciar PostgreSQL de testes.' }
  & createdb -h 127.0.0.1 -p $Port -U postgres rmmi_test
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar banco isolado.' }
  $sqlFiles = @((Join-Path $PSScriptRoot 'bootstrap.sql'))
  $sqlFiles += Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\migrations') -Filter '*.sql' | Sort-Object Name | ForEach-Object FullName
  $sqlFiles += Join-Path $PSScriptRoot 'integration.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'project_operations.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'pull_performance.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_management.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'sso_bridge.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_catalogs.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_engineering.sql'
  foreach ($sqlFile in $sqlFiles) {
    Write-Output "Validando $([System.IO.Path]::GetFileName($sqlFile))"
    $executionFile = $sqlFile
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '017_rm_web_catalog_management.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_catalogs_upgrade.sql'
    }
    & psql -X -q -h 127.0.0.1 -p $Port -U postgres -d rmmi_test -v ON_ERROR_STOP=1 -c 'SET client_min_messages=warning' -f $executionFile
    if ($LASTEXITCODE -ne 0) { throw "Falha em $sqlFile" }
  }
  # The production switch must refuse accidental execution without the explicit
  # readiness setting. This also compiles the complete activation DO block.
  $activationErrorPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $activationOutput = & psql -X -q -h 127.0.0.1 -p $Port -U postgres -d rmmi_test -v ON_ERROR_STOP=1 `
      -f (Join-Path $PSScriptRoot '..\scripts\activate_web_sso.sql') 2>&1
    $activationExitCode = $LASTEXITCODE
  } finally { $ErrorActionPreference = $activationErrorPreference }
  if ($activationExitCode -eq 0 -or ($activationOutput -join "`n") -notmatch 'Verify production BFF') {
    throw 'Activation script did not reject the missing production-readiness setting.'
  }
  Write-Output 'PASS: migrations e testes transacionais executados em PostgreSQL isolado.'
}
finally {
  if ($running -or (Test-Path -LiteralPath (Join-Path $dataPath 'postmaster.pid'))) {
    & pg_ctl -D $dataPath -m fast -w stop | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Falha ao parar banco isolado; preservado em $testRoot" }
  }
  # Delete only the exact randomly created child of the OS temporary directory.
  $tempPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\','/') + [System.IO.Path]::DirectorySeparatorChar
  if (-not $testRoot.StartsWith($tempPrefix,[System.StringComparison]::OrdinalIgnoreCase) -or
      [System.IO.Path]::GetFileName($testRoot) -notmatch '^rmmi-db-test-[0-9a-f]{32}$') {
    throw 'Recusado limpar caminho inesperado.'
  }
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
