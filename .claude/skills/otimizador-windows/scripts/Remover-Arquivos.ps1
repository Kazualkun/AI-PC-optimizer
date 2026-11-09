<#
.SYNOPSIS
    Remove arquivos de uma lista aprovada pelo usuário - por padrão para a LIXEIRA.
.DESCRIPTION
    Aceita dois tipos de CSV (delimitador ';'):
      1) Resultado de Executar-Organizacao.ps1 (colunas Origem/DestinoFinal/Status): remove apenas os
         ORIGINAIS cuja cópia foi verificada, conferindo de novo que a cópia ainda existe e tem o mesmo tamanho.
      2) Lista de candidatos de Analisar-Pasta.ps1 (coluna Caminho; opcional Manter): remove os arquivos
         listados; se houver "Manter" (duplicados), confere que a cópia mantida ainda existe.
    SEM -Executar: só mostra a prévia (quantidade, tamanho, caminhos).
.PARAMETER Modo
    Lixeira (padrão, recuperável) ou Definitivo (irreversível - só com aprovação explícita do usuário).
.PARAMETER Somente
    Filtra por Categoria ou por trecho do caminho (ex.: -Somente Instaladores ou -Somente '\Downloads\').
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Lista,
    [ValidateSet('Lixeira', 'Definitivo')][string]$Modo = 'Lixeira',
    [string[]]$Somente,
    [switch]$Executar
)

. "$PSScriptRoot\Common.ps1"

if (-not (Test-Path -LiteralPath $Lista)) { Write-Host "Lista não encontrada: $Lista"; exit 1 }
$linhas = @(Import-Csv -LiteralPath $Lista -Delimiter ';' -Encoding UTF8)
$Somente = Split-Lista $Somente
$ehResultado = ($linhas.Count -gt 0 -and ($linhas[0].PSObject.Properties.Name -contains 'Status'))

$candidatos = New-Object System.Collections.Generic.List[object]
$recusados = New-Object System.Collections.Generic.List[object]
foreach ($l in $linhas) {
    if ($ehResultado) {
        if ($l.Status -notlike 'Verificado*') { continue }
        $alvo = $l.Origem; $copia = $l.DestinoFinal
    } else {
        $alvo = $l.Caminho; $copia = $l.Manter
    }
    if (-not $alvo) { continue }
    if ($Somente.Count) {
        $casa = $false
        foreach ($s in $Somente) { if ($l.Categoria -eq $s -or $alvo -like "*$s*") { $casa = $true } }
        if (-not $casa) { continue }
    }
    if (-not (Test-Path -LiteralPath $alvo)) { $recusados.Add([pscustomobject]@{ Caminho = $alvo; Motivo = 'Já não existe' }); continue }
    if (Test-CaminhoProtegido $alvo) { $recusados.Add([pscustomobject]@{ Caminho = $alvo; Motivo = 'Caminho protegido (pasta do sistema/perfil)' }); continue }
    $item = Get-Item -LiteralPath $alvo -Force
    if ($copia) {
        if (-not (Test-Path -LiteralPath $copia)) { $recusados.Add([pscustomobject]@{ Caminho = $alvo; Motivo = "Cópia não encontrada: $copia" }); continue }
        $ci = Get-Item -LiteralPath $copia -Force
        if (-not $item.PSIsContainer -and $ci.Length -ne $item.Length) { $recusados.Add([pscustomobject]@{ Caminho = $alvo; Motivo = 'Cópia com tamanho diferente' }); continue }
        if ($item.PSIsContainer) {
            $tA = Get-TamanhoPasta $alvo; $tC = Get-TamanhoPasta $copia
            if ($tA.Bytes -ne $tC.Bytes -or $tA.Arquivos -ne $tC.Arquivos) { $recusados.Add([pscustomobject]@{ Caminho = $alvo; Motivo = 'Pasta copiada difere da original' }); continue }
        }
    }
    $bytes = if ($item.PSIsContainer) { (Get-TamanhoPasta $alvo).Bytes } else { [int64]$item.Length }
    $candidatos.Add([pscustomobject]@{ Caminho = $alvo; Bytes = $bytes; Tamanho = (Format-Tamanho $bytes); Pasta = $item.PSIsContainer; Copia = $copia })
}
$total = [int64](($candidatos | Measure-Object Bytes -Sum).Sum)

$titulo = if ($Executar) { "REMOÇÃO - EXECUÇÃO ($Modo)" } else { "REMOÇÃO - PRÉVIA ($Modo) - nada será apagado" }
Write-Titulo $titulo
Write-Host "Lista: $Lista"
Write-Host "Tipo: $(if ($ehResultado) { 'originais de uma organização (cópias verificadas)' } else { 'lista de candidatos' })"
Write-Host "A remover: $($candidatos.Count) item(ns), $(Format-Tamanho $total)"
if ($Modo -eq 'Lixeira') { Write-Host 'Destino: LIXEIRA (recuperável). Itens grandes demais para a Lixeira fazem o Windows pedir confirmação antes de apagar de vez.' }
else { Write-Host 'ATENÇÃO: modo DEFINITIVO - os arquivos NÃO poderão ser recuperados.' }
Write-Secao 'Itens (até 25, maiores primeiro)'
Write-Tabela ($candidatos | Sort-Object Bytes -Descending | Select-Object -First 25) @('Tamanho', 'Caminho')
if ($recusados.Count) { Write-Secao "Ignorados por segurança ($($recusados.Count))"; Write-Tabela ($recusados | Select-Object -First 20) @('Motivo', 'Caminho') }

if (-not $Executar) { Write-Host ''; Write-Host 'Para executar após aprovação explícita do usuário, repita com -Executar.'; exit 0 }

$log = New-Object System.Collections.Generic.List[object]
$livreAntes = (Get-InfoUnidade $env:SystemDrive).Livre
$ok = 0; $falhas = 0; $liberado = [int64]0
foreach ($c in $candidatos) {
    try {
        if ($Modo -eq 'Lixeira') { Send-ParaLixeira $c.Caminho }
        else { Remove-Item -LiteralPath $c.Caminho -Recurse -Force -ErrorAction Stop }
        $ok++; $liberado += $c.Bytes
        $log.Add([pscustomobject]@{ Caminho = $c.Caminho; Bytes = $c.Bytes; Status = "Removido ($Modo)"; Erro = '' })
    } catch {
        $falhas++
        $log.Add([pscustomobject]@{ Caminho = $c.Caminho; Bytes = $c.Bytes; Status = 'Falhou'; Erro = $_.Exception.Message })
    }
}
# Remove pastas que ficaram VAZIAS (sobe na árvore enquanto vazia; nunca raízes protegidas como Downloads/Área de Trabalho).
$vazias = 0
$pais = @($log | Where-Object { $_.Status -like 'Removido*' } | ForEach-Object { Split-Path $_.Caminho -Parent } | Sort-Object -Unique | Sort-Object Length -Descending)
foreach ($p in $pais) {
    $atual = $p
    while ($atual -and (Test-Path -LiteralPath $atual) -and -not (Test-CaminhoProtegido $atual)) {
        try {
            if ([IO.Directory]::EnumerateFileSystemEntries($atual).GetEnumerator().MoveNext()) { break }
            [IO.Directory]::Delete($atual, $false); $vazias++
        } catch { break }
        $atual = Split-Path $atual -Parent
    }
}
if ($vazias) { Write-Host "Pastas que ficaram vazias e foram removidas: $vazias" }

$arqLog = Join-Path (Get-PastaDados 'logs') ('remocao-' + (New-Carimbo) + '.csv')
$log | Export-Csv -LiteralPath $arqLog -Delimiter ';' -NoTypeInformation -Encoding UTF8
Write-Secao 'Resultado'
Write-Host "Removidos: $ok ($(Format-Tamanho $liberado)) | Falhas: $falhas"
if ($Modo -eq 'Lixeira') { Write-Host 'Os itens estão na Lixeira: o espaço só é liberado de fato quando ela for esvaziada (Limpeza-Sistema.ps1 -Itens Lixeira).' }
else { Write-Host "Espaço livre no disco $($env:SystemDrive) antes $(Format-Tamanho $livreAntes), agora $(Format-Tamanho (Get-InfoUnidade $env:SystemDrive).Livre)" }
if ($falhas) { Write-Tabela ($log | Where-Object { $_.Status -eq 'Falhou' } | Select-Object -First 15) @('Caminho', 'Erro') }
Write-Host "Log: $arqLog"
