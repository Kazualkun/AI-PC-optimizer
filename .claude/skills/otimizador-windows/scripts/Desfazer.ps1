<#
.SYNOPSIS
    Desfaz alterações feitas pela skill, a partir dos backups em %LOCALAPPDATA%\OtimizadorPC\backups.
.DESCRIPTION
    -Listar: mostra os backups disponíveis.
    -Backup <arquivo>: prévia do que será restaurado (ordem inversa da aplicação).
    -Backup <arquivo> -Executar: restaura. Entradas que exigem administrador usam -Elevar (UAC).
    Apps removidos não voltam sozinhos: a prévia mostra como reinstalar pela Microsoft Store.
#>
[CmdletBinding()]
param(
    [string]$Backup,
    [switch]$Listar,
    [switch]$Executar,
    [switch]$Elevar,
    [switch]$SomenteAdmin
)

. "$PSScriptRoot\Common.ps1"
$ehAdmin = Test-Admin
$dir = Get-PastaDados 'backups'

if ($Listar -or -not $Backup) {
    Write-Titulo 'BACKUPS DISPONÍVEIS'
    $lista = foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try { $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        $tipos = (@($j.Entradas) | Group-Object Tipo | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
        [pscustomobject]@{ Data = $f.LastWriteTime.ToString('dd/MM/yyyy HH:mm'); Entradas = @($j.Entradas).Count; Conteudo = $tipos; Arquivo = $f.FullName }
    }
    Write-Tabela $lista @('Data', 'Entradas', 'Conteudo', 'Arquivo')
    Write-Host ''
    Write-Host 'Uso: Desfazer.ps1 -Backup <arquivo> (prévia) e depois -Executar [-Elevar].'
    exit 0
}

if (-not (Test-Path -LiteralPath $Backup)) { Write-Host "Backup não encontrado: $Backup"; exit 1 }
$b = Get-Content -LiteralPath $Backup -Raw | ConvertFrom-Json
$entradas = @($b.Entradas)
[array]::Reverse($entradas)

$mapaStart = @{ 0 = 'boot'; 1 = 'system'; 2 = 'auto'; 3 = 'demand'; 4 = 'disabled' }
function Get-Descricao {
    param($e)
    switch ($e.Tipo) {
        'Registro' { if ($e.Existia) { "Registro: $($e.Chave)\$($e.Nome) volta ao valor anterior" } else { "Registro: remover $($e.Chave)\$($e.Nome) (não existia antes)" } }
        'Servico' { $m = $mapaStart[[int]$e.Start]; if ([int]$e.Start -eq 2 -and $e.Delayed -eq 1) { $m = 'delayed-auto' }; "Serviço $($e.Nome): inicialização volta para '$m'" }
        'Comando' { "Executar: $($e.Desfazer)" }
        'Recurso' { "Reativar recurso do Windows: $($e.Nome)" }
        'Tarefa' { "Reativar tarefa agendada: $($e.Caminho)$($e.Nome)" }
        'Appx' { "App $($e.Nome): reinstalar manualmente pela Microsoft Store (ms-windows-store://search/?query=$($e.Nome))" }
        'Info' { "Informação: $($e.Descricao)" }
        default { "Tipo desconhecido: $($e.Tipo)" }
    }
}

$titulo = if ($Executar) { 'DESFAZER - EXECUÇÃO' } else { 'DESFAZER - PRÉVIA (nada será alterado)' }
if ($SomenteAdmin) { $titulo += ' [janela de administrador]' }
Write-Titulo $titulo
Write-Host "Backup: $Backup (criado em $($b.Criado))"
Write-Secao 'Entradas (ordem de restauração)'
foreach ($e in $entradas) { Write-Host " - [$(if ($e.Admin) { 'admin' } else { 'usuário' })] $(Get-Descricao $e)$(if ($e.Descricao -and $e.Tipo -ne 'Info') { "  ($($e.Descricao))" })" }

if (-not $Executar) { Write-Host ''; Write-Host 'Para restaurar após aprovação do usuário, repita com -Executar.'; exit 0 }

$pend = 0; $ok = 0; $erros = 0
foreach ($e in $entradas) {
    if ($e.Tipo -in @('Info', 'Appx')) { continue }
    if ($e.Admin -and -not $ehAdmin) { $pend++; continue }
    if ($SomenteAdmin -and -not $e.Admin) { continue }
    try {
        switch ($e.Tipo) {
            'Registro' {
                if ($e.Existia) {
                    $v = $e.Valor
                    switch ($e.TipoValor) {
                        'Binary' { $v = [Convert]::FromBase64String([string]$e.Valor) }
                        'MultiString' { $v = [string[]]@($e.Valor) }
                        'DWord' { $v = [int]$e.Valor }
                        'QWord' { $v = [long]$e.Valor }
                    }
                    Set-ValorRegistro -Chave $e.Chave -Nome $e.Nome -Valor $v -Tipo $e.TipoValor
                } else {
                    Remove-ItemProperty -LiteralPath $e.Chave -Name $e.Nome -ErrorAction SilentlyContinue
                }
            }
            'Servico' {
                $m = $mapaStart[[int]$e.Start]; if (-not $m) { $m = 'demand' }
                if ([int]$e.Start -eq 2 -and $e.Delayed -eq 1) { $m = 'delayed-auto' }
                $o = & sc.exe config $e.Nome 'start=' $m 2>&1
                if ($LASTEXITCODE -ne 0) { throw "sc.exe: $($o -join ' ')" }
                if ($m -in @('auto', 'delayed-auto')) { Start-Service -Name $e.Nome -ErrorAction SilentlyContinue }
            }
            'Comando' {
                $o = & cmd.exe /c $e.Desfazer 2>&1
                if ($LASTEXITCODE -ne 0) { throw "$($e.Desfazer): $($o -join ' ')" }
            }
            'Recurso' { Enable-WindowsOptionalFeature -Online -FeatureName $e.Nome -NoRestart -ErrorAction Stop | Out-Null }
            'Tarefa' { Enable-ScheduledTask -TaskPath $e.Caminho -TaskName $e.Nome -ErrorAction Stop | Out-Null }
        }
        $ok++
        Write-Host " OK: $(Get-Descricao $e)"
    } catch {
        $erros++
        Write-Host " ERRO: $(Get-Descricao $e) -> $($_.Exception.Message)"
    }
}
Write-Secao 'Resumo'
Write-Host "Restaurados: $ok | Erros: $erros | Pendentes (admin): $pend"
$apps = @($entradas | Where-Object { $_.Tipo -eq 'Appx' })
if ($apps.Count) { Write-Host "Apps para reinstalar manualmente pela Microsoft Store: $(($apps | ForEach-Object { $_.Nome }) -join ', ')" }
Write-Host 'Algumas restaurações só valem após reiniciar o PC ou sair e entrar na conta.'

if ($pend -gt 0 -and -not $ehAdmin) {
    if ($Elevar) { $null = Invoke-ComoAdmin -Script $PSCommandPath -Parametros @{ Backup = $Backup; Executar = $true; SomenteAdmin = $true } }
    else { Write-Host "Para restaurar as $pend entrada(s) de administrador: repita com -Executar -Elevar." }
}
