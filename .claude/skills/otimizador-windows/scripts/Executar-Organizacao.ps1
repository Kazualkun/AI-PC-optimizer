<#
.SYNOPSIS
    Executa um plano de organização gerado por Planejar-Organizacao.ps1.
.DESCRIPTION
    SEM -Executar: apenas valida o plano e mostra o que seria feito (prévia).
    COM -Executar: COPIA cada arquivo para o destino e verifica a cópia (tamanho + SHA-256).
    Os ORIGINAIS NUNCA são apagados por este script. Ao final, gera um CSV de resultado que pode
    ser usado com Remover-Arquivos.ps1 depois que o usuário responder se quer apagar os originais.
.PARAMETER Modo
    Copiar (padrão, mantém originais) ou Mover (somente dentro do MESMO disco: instantâneo, sem
    espaço extra, NÃO mantém original - use apenas com aprovação explícita do usuário).
.PARAMETER VerificacaoRapida
    Verifica só o tamanho (sem hash). Mais rápido para muitos vídeos grandes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Plano,
    [ValidateSet('Copiar', 'Mover')][string]$Modo = 'Copiar',
    [switch]$VerificacaoRapida,
    [switch]$Executar
)

. "$PSScriptRoot\Common.ps1"

if (-not (Test-Path -LiteralPath $Plano)) { Write-Host "Plano não encontrado: $Plano"; exit 1 }
$linhas = @(Import-Csv -LiteralPath $Plano -Delimiter ';' -Encoding UTF8)
$acoes = @($linhas | Where-Object { $_.Acao -eq 'Copiar' -and $_.Destino })
$jaExistem = @($linhas | Where-Object { $_.Acao -eq 'JaExiste' -and $_.Destino })
$bytesTotal = [int64](($acoes | ForEach-Object { [int64]$_.Bytes } | Measure-Object -Sum).Sum)

function Get-Letra { param([string]$c) return $c.Substring(0, 1).ToUpper() }

# ------------------------------------------------------------- validação --
$problemas = @()
foreach ($l in $acoes) {
    if (-not (Test-Path -LiteralPath $l.Origem)) { $problemas += "Origem não existe mais: $($l.Origem)" }
    if ($Modo -eq 'Mover' -and (Get-Letra $l.Origem) -ne (Get-Letra $l.Destino)) { $problemas += "Mover entre discos diferentes não é permitido (use Copiar): $($l.Origem)" }
}
$espaco = @()
if ($Modo -eq 'Copiar') {
    foreach ($g in ($acoes | Group-Object { Get-Letra $_.Destino })) {
        $u = Get-InfoUnidade $g.Name
        $need = [int64](($g.Group | ForEach-Object { [int64]$_.Bytes } | Measure-Object -Sum).Sum)
        $ok = ($u -and $u.Livre -gt ($need * 1.1))
        $espaco += [pscustomobject]@{ Unidade = $g.Name; Necessario = (Format-Tamanho $need); Livre = $(if ($u) { Format-Tamanho $u.Livre } else { '?' }); Situacao = $(if ($ok) { 'OK' } else { 'INSUFICIENTE' }) }
        if (-not $ok) { $problemas += "Espaço insuficiente na unidade $($g.Name): precisa de $(Format-Tamanho $need)" }
    }
}

$titulo = if ($Executar) { "ORGANIZAÇÃO - EXECUÇÃO ($Modo)" } else { "ORGANIZAÇÃO - PRÉVIA ($Modo) - nada será alterado" }
Write-Titulo $titulo
Write-Host "Plano: $Plano"
Write-Host "Itens a $(if ($Modo -eq 'Copiar') { 'copiar' } else { 'mover' }): $($acoes.Count) ($(Format-Tamanho $bytesTotal)) | Já existentes no destino: $($jaExistem.Count)"
if ($espaco) { Write-Secao 'Espaço'; Write-Tabela $espaco }
Write-Secao 'Destinos'
Write-Tabela ($acoes | Group-Object { Split-Path $_.Destino -Parent } | ForEach-Object { [pscustomobject]@{ Pasta = $_.Name; Itens = $_.Count } } | Sort-Object Pasta) @('Pasta', 'Itens')

if ($problemas.Count) {
    Write-Secao "PROBLEMAS ($($problemas.Count))"
    $problemas | Select-Object -First 30 | ForEach-Object { Write-Host " ! $_" }
    if ($Executar) { Write-Host ''; Write-Host 'Execução cancelada: resolva os problemas acima (ou edite o plano) e tente de novo.'; exit 2 }
}

if (-not $Executar) {
    Write-Host ''
    if ($Modo -eq 'Copiar') { Write-Host 'Na execução, os originais serão MANTIDOS. Cada cópia é verificada antes de ser considerada concluída.' }
    else { Write-Host 'ATENÇÃO: no modo Mover os arquivos saem da pasta de origem (sem cópia de segurança).' }
    Write-Host 'Para executar após aprovação do usuário, repita o comando com -Executar.'
    exit 0
}

# --------------------------------------------------------------- execução --
$resultado = New-Object System.Collections.Generic.List[object]
$i = 0; $ok = 0; $falhas = 0
foreach ($l in $acoes) {
    $i++
    $status = ''; $erro = ''; $hash = ''; $destFinal = $l.Destino
    try {
        $origItem = Get-Item -LiteralPath $l.Origem -Force -ErrorAction Stop
        $pastaDest = Split-Path $destFinal -Parent
        if (-not (Test-Path -LiteralPath $pastaDest)) { New-Item -ItemType Directory -Path $pastaDest -Force | Out-Null }
        if (Test-Path -LiteralPath $destFinal) {
            # surgiu um arquivo com o mesmo nome desde o planejamento -> novo nome, nunca sobrescreve
            $b = [IO.Path]::GetFileNameWithoutExtension($destFinal); $e = [IO.Path]::GetExtension($destFinal); $n = 2
            do { $destFinal = Join-Path $pastaDest "$b ($n)$e"; $n++ } while (Test-Path -LiteralPath $destFinal)
        }
        if ($Modo -eq 'Mover') {
            Move-Item -LiteralPath $l.Origem -Destination $destFinal -ErrorAction Stop
            $status = 'Movido'
        } elseif ($origItem.PSIsContainer) {
            $null = robocopy $l.Origem $destFinal /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NP /NFL /NDL /NJH /NJS
            if ($LASTEXITCODE -ge 8) { throw "robocopy retornou código $LASTEXITCODE" }
            $tO = Get-TamanhoPasta $l.Origem; $tD = Get-TamanhoPasta $destFinal
            if ($tO.Arquivos -ne $tD.Arquivos -or $tO.Bytes -ne $tD.Bytes) { throw "Verificação falhou: origem $($tO.Arquivos) arq/$($tO.Bytes) B, destino $($tD.Arquivos) arq/$($tD.Bytes) B" }
            $status = 'Verificado'
        } else {
            Copy-Item -LiteralPath $l.Origem -Destination $destFinal -ErrorAction Stop
            $dItem = Get-Item -LiteralPath $destFinal -Force
            $dItem.CreationTime = $origItem.CreationTime
            $dItem.LastWriteTime = $origItem.LastWriteTime
            if ($dItem.Length -ne $origItem.Length) { throw 'Tamanho da cópia diferente do original' }
            if (-not $VerificacaoRapida) {
                $hO = (Get-FileHash -LiteralPath $l.Origem -Algorithm SHA256).Hash
                $hD = (Get-FileHash -LiteralPath $destFinal -Algorithm SHA256).Hash
                if ($hO -ne $hD) { throw 'Hash SHA-256 da cópia diferente do original' }
                $hash = $hO
            }
            $status = 'Verificado'
        }
        $ok++
    } catch {
        $status = 'Falhou'; $erro = $_.Exception.Message; $falhas++
    }
    $resultado.Add([pscustomobject]@{ Tipo = $l.Tipo; Categoria = $l.Categoria; Origem = $l.Origem; DestinoFinal = $destFinal; Bytes = $l.Bytes; Status = $status; Hash = $hash; Erro = $erro })
    if ($i % 25 -eq 0) { Write-Host "  ... $i/$($acoes.Count) processados" }
}

foreach ($l in $jaExistem) {
    $status = 'Falhou'; $erro = ''
    try {
        if ((Get-FileHash -LiteralPath $l.Origem -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $l.Destino -Algorithm SHA256).Hash) { $status = 'Verificado (já existia)' }
        else { $erro = 'Conteúdo mudou desde o planejamento' }
    } catch { $erro = $_.Exception.Message }
    $resultado.Add([pscustomobject]@{ Tipo = $l.Tipo; Categoria = $l.Categoria; Origem = $l.Origem; DestinoFinal = $l.Destino; Bytes = $l.Bytes; Status = $status; Hash = ''; Erro = $erro })
}

$arqRes = Join-Path (Get-PastaDados 'logs') ('resultado-organizacao-' + (New-Carimbo) + '.csv')
$resultado | Export-Csv -LiteralPath $arqRes -Delimiter ';' -NoTypeInformation -Encoding UTF8

Write-Secao 'Resultado'
Write-Tabela ($resultado | Group-Object Status | ForEach-Object { [pscustomobject]@{ Status = $_.Name; Itens = $_.Count } }) @('Status', 'Itens')
if ($falhas) { Write-Secao 'Falhas'; Write-Tabela ($resultado | Where-Object { $_.Status -eq 'Falhou' } | Select-Object -First 20) @('Origem', 'Erro') }
Write-Host ''
Write-Host "Resultado salvo: $arqRes"
if ($Modo -eq 'Copiar') {
    Write-Host 'OS ORIGINAIS FORAM MANTIDOS.'
    Write-Host 'PERGUNTA OBRIGATÓRIA AO USUÁRIO: "Deseja apagar o arquivo original antigo ou mantê-lo?"'
    Write-Host "Se apagar: Remover-Arquivos.ps1 -Lista '$arqRes'  (prévia; depois -Executar; vai para a Lixeira)"
}
