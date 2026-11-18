param([int]$Port = 0, [switch]$WorkshopInventory)
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
  $sqlFiles += Join-Path $PSScriptRoot 'web_form_templates.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_stage_approvals.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_pcp_queues.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_photo_selection.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_photo_title_deletion.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_route.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_operational_photos.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_form_reviewer_assignments.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_stage_rules.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_cell_availability.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_dossier.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_dossier_search.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_equipment.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_comment_revisions.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_attachment_versions.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_milestone_dates.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_equipment_bundle.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_equipment_bundle_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_route_instances.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_route_instances_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_audit.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_delete.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_delete_integrity.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_delete_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_route_configuration.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_route_configuration_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_allocation_status.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_allocation_status_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_planning_export.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_project_document_folders.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'mobile_receiving_drafts.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_form_template_delete.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_form_template_delete_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_gantt_planning.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_gantt_planning_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_workshop_snapshot.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_gantt_calendars.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_gantt_calendars_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_capacity_planning.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_capacity_planning_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'web_capacity_planning_limits.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'execution_events.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'execution_events_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'execution_events_limits.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'mobile_receiving_openings.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'mobile_receiving_openings_concurrency.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'workshop_ownership_foundation.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'workshop_origin_retention.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'workshop_direct_references.sql'
  $sqlFiles += Join-Path $PSScriptRoot 'workshop_catalog_ownership.sql'
  foreach ($sqlFile in $sqlFiles) {
    Write-Output "Validando $([System.IO.Path]::GetFileName($sqlFile))"
    $executionFile = $sqlFile
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '017_rm_web_catalog_management.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_catalogs_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '020_rm_web_stage_approvals.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_stage_approvals_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '021_rm_web_pcp_queues.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_pcp_queues_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '022_rm_web_project_photo_selection.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_photo_selection_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '023_rm_web_photo_title_deletion.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_photo_title_deletion_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '024_rm_web_project_route.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_route_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '025_rm_web_operational_photos.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_operational_photos_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '026_rm_web_form_reviewer_assignments.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_form_reviewer_assignments_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '027_rm_web_stage_rules.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_stage_rules_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '028_rm_web_cell_availability.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_cell_availability_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '029_rm_web_project_dossier.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_dossier_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '030_rm_web_project_dossier_search.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_dossier_search_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '031_rm_web_project_equipment.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_equipment_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '032_rm_web_project_comment_revisions.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_comment_revisions_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '033_rm_web_project_attachment_versions.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_attachment_versions_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '036_rm_web_project_equipment_bundle.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_equipment_bundle_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '037_rm_web_project_route_instances.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_route_instances_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '038_rm_web_project_audit.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_audit_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '039_rm_web_project_delete.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_delete_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '040_rm_web_project_route_configuration.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_route_configuration_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '041_rm_cell_collection_status_values.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_cell_status_values_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '042_rm_web_allocation_status.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_allocation_status_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '043_rm_web_planning_export.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_planning_export_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '044_rm_web_project_document_folders.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_project_document_folders_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '047_rm_web_gantt_planning.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_gantt_planning_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '049_rm_web_gantt_calendars.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_gantt_calendars_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '050_rm_web_capacity_planning.sql') {
      $executionFile = Join-Path $PSScriptRoot 'web_capacity_planning_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '051_rm_execution_events.sql') {
      $executionFile = Join-Path $PSScriptRoot 'execution_events_upgrade.sql'
    }
    if ([System.IO.Path]::GetFileName($sqlFile) -eq '052_rm_receiving_openings.sql') {
      $executionFile = Join-Path $PSScriptRoot 'mobile_receiving_openings_upgrade.sql'
    }
    $migration028Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\028_rm_web_cell_availability.sql'))
    $migration029Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\029_rm_web_project_dossier.sql'))
    $migration030Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\030_rm_web_project_dossier_search.sql'))
    $migration031Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\031_rm_web_project_equipment.sql'))
    $migration032Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\032_rm_web_project_comment_revisions.sql'))
    $migration033Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\033_rm_web_project_attachment_versions.sql'))
    $migration036Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\036_rm_web_project_equipment_bundle.sql'))
    $migration037Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\037_rm_web_project_route_instances.sql'))
    $migration038Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\038_rm_web_project_audit.sql'))
    $migration039Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\039_rm_web_project_delete.sql'))
    $migration040Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\040_rm_web_project_route_configuration.sql'))
    $migration041Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\041_rm_cell_collection_status_values.sql'))
    $migration042Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\042_rm_web_allocation_status.sql'))
    $migration043Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\043_rm_web_planning_export.sql'))
    $migration044Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\044_rm_web_project_document_folders.sql'))
    $migration047Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\047_rm_web_gantt_planning.sql'))
    $migration049Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\049_rm_web_gantt_calendars.sql'))
    $migration050Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\050_rm_web_capacity_planning.sql'))
    $migration051Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\051_rm_execution_events.sql'))
    $migration052Path = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\migrations\052_rm_receiving_openings.sql'))
    & psql -X -q -h 127.0.0.1 -p $Port -U postgres -d rmmi_test -v ON_ERROR_STOP=1 -v "rm_migration_028_path=$migration028Path" -v "rm_migration_029_path=$migration029Path" -v "rm_migration_030_path=$migration030Path" -v "rm_migration_031_path=$migration031Path" -v "rm_migration_032_path=$migration032Path" -v "rm_migration_033_path=$migration033Path" -v "rm_migration_036_path=$migration036Path" -v "rm_migration_037_path=$migration037Path" -v "rm_migration_038_path=$migration038Path" -v "rm_migration_039_path=$migration039Path" -v "rm_migration_040_path=$migration040Path" -v "rm_migration_041_path=$migration041Path" -v "rm_migration_042_path=$migration042Path" -v "rm_migration_043_path=$migration043Path" -v "rm_migration_044_path=$migration044Path" -v "rm_migration_047_path=$migration047Path" -v "rm_migration_049_path=$migration049Path" -v "rm_migration_050_path=$migration050Path" -v "rm_migration_051_path=$migration051Path" -v "rm_migration_052_path=$migration052Path" -c 'SET client_min_messages=warning' -f $executionFile
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
  if ($WorkshopInventory) {
    $inventorySource = Join-Path $testRoot 'workshop-metadata.json'
    $inventoryReport = Join-Path $testRoot 'workshop-review.json'
    $inventorySql = Join-Path $PSScriptRoot '..\scripts\workshop_scope_inventory.sql'
    $inventoryRaw = & psql -X -q -A -t -h 127.0.0.1 -p $Port -U postgres -d rmmi_test -v ON_ERROR_STOP=1 -f $inventorySql
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao inventariar metadados em modo somente leitura.' }
    [IO.File]::WriteAllText($inventorySource, ($inventoryRaw -join [Environment]::NewLine).Trim(), [Text.UTF8Encoding]::new($false))
    & node (Join-Path $PSScriptRoot '..\..\desktop\node_modules\tsx\dist\cli.mjs') (Join-Path $PSScriptRoot '..\scripts\prepare_workshop_inventory.ts') $inventorySource $inventoryReport
    if ($LASTEXITCODE -ne 0) { throw 'O parser recusou o inventário real do PostgreSQL isolado.' }
    Write-Output 'PASS: inventario de oficinas SQL -> JSON -> parser, sem acesso a dados de negocio.'
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
