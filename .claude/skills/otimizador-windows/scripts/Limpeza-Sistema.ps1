<#
.SYNOPSIS
    Limpeza segura de temporários, caches e sobras do Windows (itens do Catalogo.ps1).
.DESCRIPTION
    SEM -Executar: prévia - mede cada item (caminho, tamanho, arquivos, se requer admin, apps abertos).
    COM -Executar: apaga o conteúdo dos itens escolhidos. Arquivos em uso são pulados.
    Itens que exigem administrador são pulados, a menos que -Elevar seja usado (abre o UAC).
.PARAMETER Itens
    Ids do catálogo (ex.: TempUsuario,CacheNavegadores). Use -Listar para ver todos.
.EXAMPLE
    Limpeza-Sistema.ps1 -Itens TempUsuario,CacheMiniaturas            # prévia
    Limpeza-Sistema.ps1 -Itens TempUsuario,CacheMiniaturas -Executar  # executa (após aprovação)
#>
[CmdletBinding()]
param(
    [string[]]$Itens,
    [switch]$Executar,
    [switch]$Elevar,
    [switch]$SomenteAdmin,
    [switch]$Listar
)

. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Catalogo.ps1"

$ehAdmin = Test-Admin
$Itens = Split-Lista $Itens

if ($Listar -or $Itens.Count -eq 0) {
    Write-Titulo 'ITENS DE LIMPEZA DISPONÍVEIS'
    Write-Tabela ($Script:CatalogoLimpeza | ForEach-Object {
            $adm = ($_.Tipo -in @('CleanMgr', 'DISM', 'OtimizacaoEntrega')) -or [bool](@($_.Alvos) | Where-Object { $_ -is [hashtable] -and $_.Admin })
            [pscustomobject]@{ Id = $_.Id; Nome = $_.Nome; Risco = $_.Risco; Admin = $(if ($adm) { 'sim/parcial' } else { 'não' }) }
        }) @('Id', 'Nome', 'Risco', 'Admin')
    Write-Host ''
    Write-Host 'Uso: Limpeza-Sistema.ps1 -Itens Id1,Id2 [-Executar] [-Elevar]'
    exit 0
}

$selecionados = @()
foreach ($id in $Itens) {
    $it = $Script:CatalogoLimpeza | Where-Object { $_.Id -ieq $id } | Select-Object -First 1
    if (-not $it) { Write-Host "Item desconhecido: '$id'. Use -Listar."; exit 1 }
    $selecionados += $it
}

function Remove-ConteudoAlvo {
    param($Alvo)
    $r = [pscustomobject]@{ Caminho = $Alvo.Caminho; Bytes = [int64]0; Arquivos = 0; Falhas = 0 }
    if (-not (Test-Path -LiteralPath $Alvo.Caminho -ErrorAction SilentlyContinue)) { return $r }
    if (Test-CaminhoProtegido $Alvo.Caminho) { Write-Host "   ! Recusado (caminho protegido): $($Alvo.Caminho)"; return $r }
    $limite = (Get-Date).AddDays(-1 * $Alvo.DiasMinimos)
    $item = Get-Item -LiteralPath $Alvo.Caminho -Force
    if (-not $item.PSIsContainer) {
        try { $len = $item.Length; $item.Attributes = 'Normal'; $item.Delete(); $r.Bytes += $len; $r.Arquivos++ } catch { $r.Falhas++ }
        return $r
    }
    $dirs = New-Object System.Collections.Generic.List[string]
    $pilha = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pilha.Push((New-Object System.IO.DirectoryInfo -ArgumentList $item.FullName))
    while ($pilha.Count -gt 0) {
        $d = $pilha.Pop()
        $arqs = @()
        try { $arqs = @($d.GetFiles($Alvo.Filtro)) } catch { $r.Falhas++; continue }
        foreach ($f in $arqs) {
            if ($Alvo.DiasMinimos -gt 0 -and $f.LastWriteTime -gt $limite) { continue }
            try {
                $len = $f.Length
                if ($f.IsReadOnly) { $f.IsReadOnly = $false }
                $f.Delete()
                $r.Bytes += $len; $r.Arquivos++
            } catch { $r.Falhas++ }
        }
        if (-not $Alvo.SemRecursao) {
            try {
                foreach ($s in $d.GetDirectories()) {
                    if (([int]$s.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    $dirs.Add($s.FullName); $pilha.Push($s)
                }
            } catch {}
        }
    }
    foreach ($p in ($dirs | Sort-Object Length -Descending)) {
        try { if (-not [IO.Directory]::EnumerateFileSystemEntries($p).GetEnumerator().MoveNext()) { [IO.Directory]::Delete($p, $false) } } catch {}
    }
    return $r
}

function Invoke-CleanMgr {
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $usados = @()
    foreach ($h in $Script:HandlersCleanMgr) {
        $k = Join-Path $base $h
        if (Test-Path -LiteralPath $k) { New-ItemProperty -LiteralPath $k -Name 'StateFlags0777' -Value 2 -PropertyType DWord -Force | Out-Null; $usados += $k }
    }
    Write-Host "   Executando a Limpeza de Disco oficial ($($usados.Count) categorias). Pode levar vários minutos..."
    Start-Process -FilePath "$env:windir\System32\cleanmgr.exe" -ArgumentList '/sagerun:777' -Wait
    foreach ($k in $usados) { Remove-ItemProperty -LiteralPath $k -Name 'StateFlags0777' -ErrorAction SilentlyContinue }
}

$titulo = if ($Executar) { 'LIMPEZA - EXECUÇÃO' } else { 'LIMPEZA - PRÉVIA (nada será apagado)' }
if ($SomenteAdmin) { $titulo += ' [janela de administrador]' }
Write-Titulo $titulo
$livreAntes = (Get-InfoUnidade $env:SystemDrive).Livre
Write-Host "Espaço livre no disco $($env:SystemDrive) $(Format-Tamanho $livreAntes) | Administrador: $(if ($ehAdmin) { 'sim' } else { 'não' })"

$pendentesAdmin = @()
$relatorio = @()
$medidas = @()
$totalPrevisto = [int64]0
$totalLiberado = [int64]0

foreach ($item in $selecionados) {
    $m = Measure-ItemLimpeza -Item $item -EhAdmin $ehAdmin
    $medidas += $m
    $tipo = $m.Tipo
    Write-Secao "$($item.Nome)  [$($item.Id) | risco $($item.Risco)]"
    Write-Host " $($item.Explicacao)"
    if ($m.Alvos.Count) { Write-Tabela $m.Alvos @('Tamanho', 'Arquivos', 'Admin', 'Estado', 'Caminho') }
    if ($tipo -eq 'Lixeira' -and -not $Executar) {
        $lx = Get-ItensLixeira -Top 15
        Write-Host " Itens na Lixeira: $($lx.Quantidade). Maiores (confira se não há nada para recuperar):"
        Write-Tabela $lx.Maiores @('Tamanho', 'Excluido', 'Nome', 'LocalOriginal')
    }
    $txtTam = if ($tipo -eq 'DISM') { $m.Observacao } else { "$(Format-Tamanho $m.Bytes)$(if (-not $m.MedicaoCompleta) { ' (medição parcial - pode ser maior)' })" }
    Write-Host " Total previsto: $txtTam"
    $totalPrevisto += $m.Bytes
    $liberadoItem = [int64]0
    $estadoItem = 'Prévia'

    if ($Executar) {
        $precisaAdminItem = $false
        switch ($tipo) {
            'Lixeira' {
                if ($SomenteAdmin) { break }
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                $liberadoItem = $m.Bytes; $estadoItem = 'Concluído'
                Write-Host ' -> Lixeira esvaziada.'
            }
            'DISM' {
                if (-not $ehAdmin) { $precisaAdminItem = $true; break }
                Write-Host ' -> Executando DISM /StartComponentCleanup (5-30 min)...'
                & "$env:windir\System32\Dism.exe" /Online /Cleanup-Image /StartComponentCleanup | ForEach-Object { if ($_ -match '\d+(\.\d+)?%|conclu|complet|erro|error') { Write-Host "    $_" } }
                $estadoItem = "Concluído (código $LASTEXITCODE)"
            }
            'CleanMgr' {
                if (-not $ehAdmin) { $precisaAdminItem = $true; break }
                Invoke-CleanMgr
                $estadoItem = 'Concluído'
            }
            'OtimizacaoEntrega' {
                if (-not $ehAdmin) { $precisaAdminItem = $true; break }
                if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                    Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
                } else {
                    foreach ($a in (Get-AlvosExpandidos $item)) { $null = Remove-ConteudoAlvo $a }
                }
                $liberadoItem = $m.Bytes; $estadoItem = 'Concluído'
            }
            default {
                $alvos = @(Get-AlvosExpandidos $item)
                $paraExecutar = @()
                foreach ($a in $alvos) {
                    if ($SomenteAdmin -and -not $a.Admin) { continue }
                    if ($a.Admin -and -not $ehAdmin) { $precisaAdminItem = $true; continue }
                    if (-not (Test-Path -LiteralPath $a.Caminho -ErrorAction SilentlyContinue)) { continue }
                    if ($a.Processo -and (Get-Process -Name $a.Processo -ErrorAction SilentlyContinue)) { Write-Host " -> PULADO (app aberto: $($a.Processo)): $($a.Caminho)"; continue }
                    $paraExecutar += $a
                }
                $servicosParados = @()
                if ($item.PararServicos -and $paraExecutar.Count -and $ehAdmin) {
                    foreach ($sn in $item.PararServicos) {
                        $sv = Get-Service -Name $sn -ErrorAction SilentlyContinue
                        if ($sv -and $sv.Status -eq 'Running') { Stop-Service -Name $sn -Force -ErrorAction SilentlyContinue; $servicosParados += $sn }
                    }
                }
                foreach ($a in $paraExecutar) {
                    $res = Remove-ConteudoAlvo $a
                    $liberadoItem += $res.Bytes
                    $falhaTxt = if ($res.Falhas) { " ($($res.Falhas) em uso/sem permissão, mantidos)" } else { '' }
                    Write-Host " -> $(Format-Tamanho $res.Bytes) liberados em $($a.Caminho)$falhaTxt"
                }
                foreach ($sn in $servicosParados) { Start-Service -Name $sn -ErrorAction SilentlyContinue }
                $estadoItem = 'Concluído'
            }
        }
        if ($precisaAdminItem) { $pendentesAdmin += $item.Id; Write-Host ' -> Parte deste item requer administrador.'; if ($estadoItem -eq 'Prévia') { $estadoItem = 'Pendente (admin)' } }
        $totalLiberado += $liberadoItem
    }
    $relatorio += [pscustomobject]@{ Id = $item.Id; Nome = $item.Nome; Previsto = $m.Bytes; Liberado = $liberadoItem; Estado = $estadoItem }
}

Write-Secao 'Resumo'
if (-not $Executar) {
    Write-Host "Total previsto: $(Format-Tamanho $totalPrevisto) (itens de admin podem liberar mais)"
    $adm = @($medidas | Where-Object { $_.RequerAdmin })
    if ($adm.Count -and -not $ehAdmin) { Write-Host "Itens que pedem administrador: $(($adm | ForEach-Object { $_.Id }) -join ', ') -> na execução, use -Elevar para abrir o UAC." }
    Write-Host 'Para executar após aprovação do usuário, repita com -Executar.'
    exit 0
}

$arqLog = Join-Path (Get-PastaDados 'logs') ('limpeza-' + (New-Carimbo) + '.json')
Save-Json -Objeto @{ Data = (Get-Date).ToString('s'); Admin = $ehAdmin; Itens = $relatorio } -Caminho $arqLog
Write-Tabela ($relatorio | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Previsto = (Format-Tamanho $_.Previsto); Liberado = (Format-Tamanho $_.Liberado); Estado = $_.Estado } }) @('Id', 'Previsto', 'Liberado', 'Estado')

$pendentesAdmin = @($pendentesAdmin | Sort-Object -Unique)
if ($pendentesAdmin.Count -and -not $ehAdmin) {
    if ($Elevar) {
        $null = Invoke-ComoAdmin -Script $PSCommandPath -Parametros @{ Itens = $pendentesAdmin; Executar = $true; SomenteAdmin = $true }
    } else {
        Write-Host ''
        Write-Host "Pendentes por exigir administrador: $($pendentesAdmin -join ', ')"
        Write-Host "Para concluí-los (com aprovação do usuário): Limpeza-Sistema.ps1 -Itens $($pendentesAdmin -join ',') -Executar -Elevar"
    }
}
$livreDepois = (Get-InfoUnidade $env:SystemDrive).Livre
Write-Host ''
Write-Host "Espaço livre no disco $($env:SystemDrive) antes $(Format-Tamanho $livreAntes) -> agora $(Format-Tamanho $livreDepois) (ganho real: $(Format-Tamanho ([Math]::Max([int64]0, [int64]($livreDepois - $livreAntes)))))"
Write-Host "Log: $arqLog"
