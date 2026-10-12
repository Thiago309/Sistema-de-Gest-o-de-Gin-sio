<#
.SYNOPSIS
    Executa o ambiente e os testes automatizados do Sistema de Gestão de Ginásio.

.DESCRIPTION
    1. Garante que o container PostgreSQL está a correr (docker compose).
    2. Recria o esquema e os dados (gestao_ginasio.sql).
    3. Executa a suite de testes (testes_ginasio.sql).
    Termina com código 0 se todos os testes passarem, 1 caso contrário.

.EXAMPLE
    .\run_tests.ps1
#>
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location $PSScriptRoot

$container = 'ginasio_postgres'
$psql = @('exec', $container, 'psql', '-U', 'ginasio_admin', '-d', 'ginasio')

Write-Host "`n[1/3] A iniciar o PostgreSQL (Docker)..." -ForegroundColor Cyan
docker compose up -d --wait
if ($LASTEXITCODE -ne 0) { Write-Host 'Falha ao iniciar o Docker.' -ForegroundColor Red; exit 1 }

Write-Host "`n[2/3] A carregar esquema e dados (gestao_ginasio.sql)..." -ForegroundColor Cyan
# O erro do INSERT inválido é propositado (demonstração da constraint).
$ErrorActionPreference = 'Continue'
docker @psql -q -f /scripts/gestao_ginasio.sql 2>&1 |
    ForEach-Object { "$_" } |
    Where-Object { $_ -match 'ck_percentagem_gordura_valida|OK - Constraint' } |
    ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
$ErrorActionPreference = 'Stop'

Write-Host "`n[3/3] A executar os testes (testes_ginasio.sql)..." -ForegroundColor Cyan
docker cp "$PSScriptRoot\testes_ginasio.sql" "${container}:/tmp/testes_ginasio.sql"
$ErrorActionPreference = 'Continue'
docker @psql -v ON_ERROR_STOP=1 -f /tmp/testes_ginasio.sql 2>&1 | ForEach-Object { "$_" }
$codigo = $LASTEXITCODE
$ErrorActionPreference = 'Stop'

Write-Host ''
if ($codigo -eq 0) {
    Write-Host 'TODOS OS TESTES PASSARAM.' -ForegroundColor Green
} else {
    Write-Host 'HÁ TESTES A FALHAR (ver tabela acima).' -ForegroundColor Red
}
exit $(if ($codigo -eq 0) { 0 } else { 1 })
