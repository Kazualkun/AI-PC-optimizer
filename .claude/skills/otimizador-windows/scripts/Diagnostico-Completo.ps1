<#
.SYNOPSIS
    Diagnóstico completo do PC - SOMENTE LEITURA. Não apaga, não move e não altera nada.
.DESCRIPTION
    Coleta sistema, discos (SSD/HD) e estratégia de armazenamento, uso de espaço, itens de limpeza,
    programas e jogos, memória e processos, inicialização, serviços, apps pré-instalados, recursos
    opcionais, configurações e as pastas Downloads/Área de Trabalho.
    Gera relatório .md + .json em %LOCALAPPDATA%\OtimizadorPC\relatorios com recomendações numeradas.
.PARAMETER Rapido
    Pula varreduras demoradas (perfil completo, pastas da raiz, jogos, duplicados). Ideal para o "depois".
#>
[CmdletBinding()]
param(
    [switch]$Rapido,
    [string]$PastaSaida
)

. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Catalogo.ps1"

$inicio = Get-Date
$carimbo = New-Carimbo
if (-not $PastaSaida) { $PastaSaida = Get-PastaDados 'relatorios' }
$D = [ordered]@{ Gerado = (Get-Date).ToString('s'); Modo = $(if ($Rapido) { 'Rápido' } else { 'Completo' }) }
$Recs = New-Object System.Collections.ArrayList

function Add-Rec {
    param(
        [string]$Categoria, [string]$Titulo, [string]$Detalhe = '', [int64]$GanhoBytes = 0, [string]$Ganho = '',
        [string]$Risco = 'Baixo', [bool]$Admin = $false, [string]$Acao = '', [int]$Prioridade = 2
    )
    if (-not $Ganho -and $GanhoBytes -gt 0) { $Ganho = Format-Tamanho $GanhoBytes }
    [void]$Recs.Add([pscustomobject]@{
            Id = ''; Prioridade = $Prioridade; Categoria = $Categoria; Titulo = $Titulo; Detalhe = $Detalhe
            GanhoBytes = $GanhoBytes; Ganho = $Ganho; Risco = $Risco; Admin = $Admin; AdminTxt = $(if ($Admin) { 'sim' } else { 'não' }); Acao = $Acao
        })
}

function Get-NomeAmigavel {
    param([string]$Pasta)
    switch ($Pasta) {
        'Desktop' { 'Área de Trabalho' } 'Documents' { 'Documentos' } 'Downloads' { 'Downloads' }
        'Pictures' { 'Imagens' } 'Videos' { 'Vídeos' } 'Music' { 'Músicas' } default { $Pasta }
    }
}

Write-Titulo 'DIAGNÓSTICO DO PC  (somente leitura - nada será alterado)'
if (-not $Rapido) { Write-Host 'A varredura completa pode levar de 1 a 5 minutos.' }

# =========================================================== 1. SISTEMA ==
Write-Etapa '[1/10] Sistema'
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$build = [int]$os.BuildNumber
$ehWin11 = ($build -ge 22000)
$notebook = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
$uptime = (Get-Date) - $os.LastBootUpTime
$ehAdmin = Test-Admin
$podeElevar = if ($ehAdmin) { $true } else { Test-PodeElevar }
$aad = $false
try { $aad = [bool](((dsregcmd /status 2>$null) -join "`n") -match 'AzureAdJoined\s*:\s*YES') } catch {}
$mdm = $false
try { $mdm = [bool](Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction Stop | Where-Object { $_.GetValue('UPN') }) } catch {}
$gerenciado = [bool]($cs.PartOfDomain -or $aad -or $mdm)
$reinicioPendente = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
$ramTotal = [int64]$os.TotalVisibleMemorySize * 1KB
$ramLivre = [int64]$os.FreePhysicalMemory * 1KB

$D.Sistema = [ordered]@{
    Computador = $env:COMPUTERNAME; Usuario = $env:USERNAME
    Windows = "$($os.Caption) (build $build)"; EhWindows11 = $ehWin11
    CPU = ([string]$cpu.Name).Trim(); RAMTotal = (Format-Tamanho $ramTotal); RAMTotalBytes = $ramTotal
    Notebook = $notebook; LigadoHaDias = [math]::Round($uptime.TotalDays, 1)
    Admin = $ehAdmin; PodeElevar = $podeElevar
    GerenciadoPorEmpresa = $gerenciado; Dominio = [bool]$cs.PartOfDomain; AzureAD = $aad; MDM = $mdm
    ReinicioPendente = $reinicioPendente
}

if ($reinicioPendente) {
    Add-Rec 'Sistema' 'Reiniciar o PC (há atualização aguardando reinício)' 'O Windows tem uma atualização pendente. Reiniciar conclui a instalação e libera memória.' -Ganho 'Conclui atualizações' -Acao 'Manual: Iniciar > Energia > Reiniciar' -Prioridade 1
} elseif ($uptime.TotalDays -ge 7) {
    Add-Rec 'Desempenho' "Reiniciar o PC (ligado há $([math]::Round($uptime.TotalDays)) dias)" 'Desligar com a Inicialização Rápida não zera a memória; só "Reiniciar" faz isso. Reinicie pelo menos uma vez por semana.' -Ganho 'Libera RAM' -Acao 'Manual: Iniciar > Energia > Reiniciar' -Prioridade 2
}

# ============================================================ 2. DISCOS ==
Write-Etapa '[2/10] Discos e estratégia de armazenamento'
$fisicos = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
$discos = @(Get-Disk -ErrorAction SilentlyContinue)
$particoes = @(Get-Partition -ErrorAction SilentlyContinue)
$letraSistema = $env:SystemDrive.Substring(0, 1)
$discoSistema = ($particoes | Where-Object { [string]$_.DriveLetter -eq $letraSistema } | Select-Object -First 1).DiskNumber

$listaDiscos = @()
foreach ($dk in $discos) {
    $pd = $fisicos | Where-Object { [string]$_.DeviceId -eq [string]$dk.Number } | Select-Object -First 1
    $tipo = 'Desconhecido'
    if ($pd) {
        switch ([string]$pd.MediaType) { 'SSD' { $tipo = 'SSD' } 'HDD' { $tipo = 'HD' } }
        if ($tipo -eq 'Desconhecido') {
            if ([string]$pd.BusType -eq 'NVMe') { $tipo = 'SSD' }
            elseif ($pd.SpindleSpeed -eq 0) { $tipo = 'SSD' }
            elseif ($pd.SpindleSpeed -gt 0 -and $pd.SpindleSpeed -lt 100000) { $tipo = 'HD' }
        }
    }
    $bus = if ($pd) { [string]$pd.BusType } else { [string]$dk.BusType }
    $letras = @($particoes | Where-Object { $_.DiskNumber -eq $dk.Number -and $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter })
    $semLetra = @($particoes | Where-Object { $_.DiskNumber -eq $dk.Number -and -not $_.DriveLetter -and $_.Size -gt 10GB -and [string]$_.Type -eq 'Basic' })
    $listaDiscos += [pscustomobject]@{
        Numero = $dk.Number; Modelo = $dk.FriendlyName; Tipo = $tipo; Barramento = $bus
        Bytes = [int64]$dk.Size; Tamanho = (Format-Tamanho $dk.Size)
        Externo = ($bus -in @('USB', 'SD', 'MMC', '1394')); Sistema = ($dk.Number -eq $discoSistema)
        Estilo = [string]$dk.PartitionStyle; Status = [string]$dk.OperationalStatus
        Saude = $(if ($pd) { [string]$pd.HealthStatus } else { '' })
        Letras = ($letras -join ', '); SemInicializar = ([string]$dk.PartitionStyle -eq 'RAW' -and $dk.Size -gt 0)
        ParticoesSemLetra = $semLetra.Count
    }
}

$listaVolumes = @()
foreach ($v in (Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue)) {
    $letra = $v.DeviceID.Substring(0, 1)
    $tipoV = switch ([int]$v.DriveType) { 2 { 'Removível' } 3 { 'Fixo' } 4 { 'Rede' } 5 { 'CD/DVD' } default { 'Outro' } }
    $nDisco = ($particoes | Where-Object { [string]$_.DriveLetter -eq $letra } | Select-Object -First 1).DiskNumber
    $discoV = $listaDiscos | Where-Object { $_.Numero -eq $nDisco } | Select-Object -First 1
    $pct = if ($v.Size) { [math]::Round(100 * $v.FreeSpace / $v.Size, 1) } else { $null }
    $listaVolumes += [pscustomobject]@{
        Letra = $letra; Rotulo = $v.VolumeName; Tipo = $tipoV; Midia = $(if ($discoV) { $discoV.Tipo } else { '' })
        Externo = $(if ($discoV) { $discoV.Externo } else { $false })
        Total = (Format-Tamanho $v.Size); Livre = (Format-Tamanho $v.FreeSpace); LivrePct = $pct
        TotalBytes = [int64]$v.Size; LivreBytes = [int64]$v.FreeSpace
    }
}

$internos = @($listaDiscos | Where-Object { -not $_.Externo -and $_.Bytes -gt 0 })
$externos = @($listaDiscos | Where-Object { $_.Externo -and $_.Bytes -gt 0 })
$sysDisk = $internos | Where-Object { $_.Sistema } | Select-Object -First 1
$hds = @($internos | Where-Object { $_.Tipo -eq 'HD' -and -not $_.Sistema })
$ssdsExtras = @($internos | Where-Object { $_.Tipo -eq 'SSD' -and -not $_.Sistema })
$tipoSys = if ($sysDisk) { $sysDisk.Tipo } else { 'Desconhecido' }

$topologia = if ($internos.Count -le 1) {
    switch ($tipoSys) { 'SSD' { 'SSD único' } 'HD' { 'HD único' } default { 'Disco único' } }
} elseif ($tipoSys -eq 'SSD' -and $hds.Count -ge 1) { 'SSD + HD' }
elseif ($tipoSys -eq 'SSD' -and $ssdsExtras.Count -ge 1) { 'Vários SSDs' }
elseif ($tipoSys -eq 'HD' -and $ssdsExtras.Count -ge 1) { 'Sistema no HD + SSD extra' }
elseif ($tipoSys -eq 'HD') { 'Vários HDs' }
else { 'Vários discos' }

$volSys = $listaVolumes | Where-Object { $_.Letra -eq $letraSistema } | Select-Object -First 1
$livrePct = [double]$volSys.LivrePct
$situacaoEspaco = if ($livrePct -lt 10) { 'CRÍTICO' } elseif ($livrePct -lt 15) { 'BAIXO' } elseif ($livrePct -lt 20) { 'ATENÇÃO' } else { 'OK' }

# Volume de dados (HD/SSD secundário) com mais espaço livre
$letrasDados = @()
foreach ($dd in @($hds + $ssdsExtras)) { $letrasDados += @($dd.Letras -split ', ' | Where-Object { $_ }) }
$volDados = $listaVolumes | Where-Object { $_.Letra -in $letrasDados -and $_.Tipo -eq 'Fixo' } | Sort-Object LivreBytes -Descending | Select-Object -First 1

$trim = $null
if (@($internos | Where-Object { $_.Tipo -eq 'SSD' }).Count -gt 0) {
    try { $ft = (fsutil behavior query DisableDeleteNotify 2>$null) -join "`n"; if ($ft -match 'DisableDeleteNotify\s*=\s*(\d)') { $trim = ($Matches[1] -eq '0') } } catch {}
}
$tarefaOtim = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction SilentlyContinue
$otimAgendada = if ($tarefaOtim) { [string]$tarefaOtim.State -ne 'Disabled' } else { $null }

$estrategia = @()
switch ($topologia) {
    'SSD + HD' {
        $ld = if ($volDados) { "$($volDados.Letra):" } else { 'HD' }
        $estrategia = @(
            "SSD ($($letraSistema):) = desempenho: Windows, programas, jogos que você joga com frequência e projetos em andamento. Mantenha 15-20% livre.",
            "HD ($ld) = capacidade: Imagens, Vídeos, Músicas, documentos de arquivo, backups, instaladores e jogos pouco jogados.",
            'Mova as bibliotecas do Windows (Imagens/Vídeos/Músicas) para o HD pelo recurso nativo "Local" - os programas continuam achando as pastas.',
            'Jogos: mova pelo próprio launcher (Steam > Armazenamento > Mover; Xbox app > Gerenciar > Mover). Nunca recorte/cole pastas de programas.',
            'Nunca coloque o arquivo de paginação (pagefile) no HD e não desfragmente o SSD (o Windows faz TRIM automaticamente).'
        )
    }
    'Vários SSDs' {
        $estrategia = @(
            "SSD do sistema ($($letraSistema):): Windows e programas. SSD secundário: jogos, projetos e bibliotecas grandes.",
            'Os jogos ganham o mesmo desempenho em qualquer SSD - use o secundário para liberar o do sistema.',
            'Mova Vídeos/Imagens para o SSD secundário se o do sistema estiver apertado.'
        )
    }
    'Sistema no HD + SSD extra' {
        $estrategia = @(
            'ATENÇÃO: o Windows está no HD e há um SSD sobrando. Esta é a configuração invertida.',
            'O maior ganho de desempenho possível é migrar (clonar) o Windows para o SSD e usar o HD para arquivos.'
        )
    }
    'HD único' {
        $estrategia = @(
            'Há apenas um HD mecânico. O upgrade para SSD é, de longe, a melhoria mais perceptível (boot e abertura de programas 3-5x mais rápidos).',
            'Enquanto isso: mantenha a desfragmentação agendada ativa, reduza programas na inicialização e mantenha 15% livre.'
        )
    }
    default {
        $estrategia = @(
            "Há um único disco interno ($tipoSys). Tudo divide o mesmo espaço, então a regra é: manter 15-20% livre no $($letraSistema):.",
            'Prioridades: limpar temporários/caches, organizar Downloads e Área de Trabalho, remover programas e jogos que não usa.',
            'Arquivos grandes e antigos (vídeos, backups, ISOs) devem ir para um disco externo ou nuvem, não ficar no SSD.',
            'Se o espaço continuar curto: reduzir a hibernação, compactar o Windows (CompactOS) e limitar pontos de restauração.'
        )
        if ($externos.Count -gt 0) { $estrategia += 'Disco externo detectado: ótimo para arquivo morto e backup (não para programas).' }
    }
}

$D.Armazenamento = [ordered]@{
    Topologia = $topologia; Estrategia = $estrategia; DiscoSistemaTipo = $tipoSys
    EspacoSistema = [ordered]@{ Letra = $letraSistema; Total = $volSys.Total; Livre = $volSys.Livre; LivrePct = $livrePct; Situacao = $situacaoEspaco }
    VolumeDados = $(if ($volDados) { "$($volDados.Letra):" } else { $null })
    TRIMAtivo = $trim; OtimizacaoAgendadaAtiva = $otimAgendada
    Discos = $listaDiscos; Volumes = $listaVolumes
}

foreach ($dk in $listaDiscos) {
    if ($dk.Bytes -le 0) { continue }
    if ($dk.Saude -and $dk.Saude -ne 'Healthy') {
        Add-Rec 'Armazenamento' "FAÇA BACKUP: disco $($dk.Modelo) com saúde '$($dk.Saude)'" 'O Windows indica problema de saúde neste disco. Copie seus arquivos importantes para outro lugar antes de qualquer outra coisa.' -Ganho 'Proteção de dados' -Risco 'Alto' -Acao 'Manual: copiar arquivos importantes para disco externo/nuvem' -Prioridade 1
    }
    if (-not $dk.Externo -and ($dk.SemInicializar -or $dk.ParticoesSemLetra -gt 0)) {
        Add-Rec 'Armazenamento' "Disco '$($dk.Modelo)' ($($dk.Tamanho)) sem letra ou não inicializado" 'Há um disco interno que o Windows não está mostrando no Explorador. Verifique no Gerenciamento de Disco (diskmgmt.msc). NÃO inicialize/formate se ele tiver dados de outro PC.' -Ganho 'Espaço extra disponível' -Risco 'Alto' -Acao 'Manual: abrir diskmgmt.msc e decidir com o usuário' -Prioridade 1
    }
}
if ($topologia -eq 'Sistema no HD + SSD extra') {
    Add-Rec 'Armazenamento' 'Migrar o Windows para o SSD' 'Clonar o sistema para o SSD (ferramenta do fabricante do SSD) e usar o HD para arquivos.' -Ganho 'Grande ganho de desempenho' -Risco 'Médio' -Acao 'Manual: guiar clonagem com ferramenta do fabricante do SSD' -Prioridade 1
}
if ($topologia -eq 'HD único') {
    Add-Rec 'Armazenamento' 'Considerar upgrade para SSD' 'Um SSD SATA ou NVMe de 500 GB custa pouco e é a melhoria de desempenho mais perceptível para este PC.' -Ganho 'Boot/apps 3-5x mais rápidos' -Acao 'Manual: orientar compra/instalação' -Prioridade 2
}
if ($trim -eq $false) {
    Add-Rec 'Desempenho' 'Reativar TRIM do SSD' 'O TRIM está desligado; o SSD fica mais lento e se desgasta mais com o tempo.' -Ganho 'Desempenho/vida útil do SSD' -Admin $true -Acao 'Otimizar-Sistema.ps1 -Acoes AtivarTRIM' -Prioridade 1
}
if ($otimAgendada -eq $false) {
    Add-Rec 'Desempenho' 'Reativar a otimização automática de unidades' 'A tarefa que faz TRIM (SSD) e desfragmentação (HD) semanal está desativada.' -Ganho 'Desempenho do disco' -Admin $true -Acao 'Otimizar-Sistema.ps1 -Acoes ReativarOtimizacaoAgendada' -Prioridade 2
}

# ============================================= 3. ESPAÇO NO DISCO DO SISTEMA ==
Write-Etapa "[3/10] Para onde vai o espaço do $($letraSistema):"
$arqSistema = @(Get-ChildItem -LiteralPath "$env:SystemDrive\" -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('hiberfil.sys', 'pagefile.sys', 'swapfile.sys') } |
    ForEach-Object { [pscustomobject]@{ Nome = $_.Name; Bytes = [int64]$_.Length; Tamanho = (Format-Tamanho $_.Length) } })
$hiberBytes = [int64](($arqSistema | Where-Object { $_.Nome -eq 'hiberfil.sys' }).Bytes)

$pastasRaiz = @()
if (-not $Rapido) {
    $ignorar = @('Windows', 'Users', '$Recycle.Bin', 'System Volume Information', 'Recovery', '$WinREAgent', 'Config.Msi', 'Documents and Settings')
    foreach ($p in (Get-ChildItem -LiteralPath "$env:SystemDrive\" -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($p.Name -in $ignorar) { continue }
        if (([int]$p.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $t = Get-TamanhoPasta $p.FullName
        if ($t.Bytes -gt 0) { $pastasRaiz += [pscustomobject]@{ Pasta = $p.FullName; Bytes = $t.Bytes; Tamanho = (Format-Tamanho $t.Bytes); Parcial = ($t.Erros -gt 0) } }
    }
    $pastasRaiz = @($pastasRaiz | Sort-Object Bytes -Descending)
}

# Perfil do usuário
$perfil = $null
$pastasPerfil = @()
$appDataTop = @()
$maioresArquivos = @()
if (-not $Rapido) {
    Write-Etapa '      varrendo o perfil do usuário...'
    $raizPerfil = $env:USERPROFILE.TrimEnd('\')
    $varredura = Invoke-VarreduraPerfil -Raiz $raizPerfil -LimiteGrande 300MB
    $porPasta = $varredura.PorPasta
    $totalPerfil = [int64]$varredura.Total
    $grandes = @($varredura.Grandes | ForEach-Object { [pscustomobject]@{ Arquivo = $_.FullName; Bytes = [int64]$_.Length; Tamanho = (Format-Tamanho $_.Length); Modificado = $_.LastWriteTime.ToString('yyyy-MM-dd') } })
    $agrup = @{}
    foreach ($k in $porPasta.Keys) {
        $topo = $k.Split('\')[0]
        if ($agrup.ContainsKey($topo)) { $agrup[$topo] += $porPasta[$k] } else { $agrup[$topo] = $porPasta[$k] }
    }
    $pastasPerfil = @($agrup.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object {
            [pscustomobject]@{ Pasta = (Get-NomeAmigavel $_.Key); Caminho = (Join-Path $raizPerfil $_.Key); Bytes = [int64]$_.Value; Tamanho = (Format-Tamanho $_.Value) } })
    $appDataTop = @($porPasta.GetEnumerator() | Where-Object { $_.Key -like 'AppData\*\*' } | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object {
            [pscustomobject]@{ Pasta = $_.Key; Bytes = [int64]$_.Value; Tamanho = (Format-Tamanho $_.Value) } })
    $maioresArquivos = @($grandes | Sort-Object Bytes -Descending | Select-Object -First 25)
    $perfil = [ordered]@{ Caminho = $raizPerfil; Bytes = $totalPerfil; Tamanho = (Format-Tamanho $totalPerfil) }
} else {
    foreach ($nome in 'Desktop', 'Documents', 'Downloads', 'Pictures', 'Videos', 'Music') {
        $c = if ($nome -eq 'Downloads') { Get-PastaDownloads } else { Join-Path $env:USERPROFILE $nome }
        $t = Get-TamanhoPasta $c
        $pastasPerfil += [pscustomobject]@{ Pasta = (Get-NomeAmigavel $nome); Caminho = $c; Bytes = $t.Bytes; Tamanho = (Format-Tamanho $t.Bytes) }
    }
}

$usadoSys = [int64]$volSys.TotalBytes - [int64]$volSys.LivreBytes
$somaConhecida = [int64](($arqSistema | Measure-Object Bytes -Sum).Sum) + [int64](($pastasRaiz | Measure-Object Bytes -Sum).Sum)
if ($perfil) { $somaConhecida += [int64]$perfil.Bytes }
$distribuicao = @()
foreach ($a in $arqSistema) { $distribuicao += [pscustomobject]@{ Item = "Arquivo de sistema: $($a.Nome)"; Bytes = $a.Bytes; Tamanho = $a.Tamanho } }
foreach ($p in ($pastasRaiz | Select-Object -First 8)) { $distribuicao += [pscustomobject]@{ Item = $p.Pasta; Bytes = $p.Bytes; Tamanho = $p.Tamanho } }
if ($perfil) { $distribuicao += [pscustomobject]@{ Item = "Seu perfil ($($perfil.Caminho))"; Bytes = $perfil.Bytes; Tamanho = $perfil.Tamanho } }
if (-not $Rapido) {
    $resto = [Math]::Max([int64]0, [int64]($usadoSys - $somaConhecida))
    $distribuicao += [pscustomobject]@{ Item = 'Windows + outros usuários + pontos de restauração (estimado)'; Bytes = $resto; Tamanho = (Format-Tamanho $resto) }
}
$distribuicao = @($distribuicao | Sort-Object Bytes -Descending)

$D.Espaco = [ordered]@{
    UsadoBytes = $usadoSys; Usado = (Format-Tamanho $usadoSys); Distribuicao = $distribuicao
    ArquivosSistema = $arqSistema; PastasRaiz = $pastasRaiz; Perfil = $perfil
    PastasPerfil = $pastasPerfil; AppDataMaiores = $appDataTop; MaioresArquivos = $maioresArquivos
}

$appDocker = $appDataTop | Where-Object { $_.Pasta -eq 'AppData\Local\Docker' } | Select-Object -First 1
if ($appDocker -and $appDocker.Bytes -ge 5GB) {
    Add-Rec 'Espaço' "Docker Desktop ocupa $($appDocker.Tamanho) - limpar imagens e containers sem uso" 'Guiado, pelo próprio Docker: "docker system df" (ver o que ocupa), "docker system prune" (containers parados, redes e imagens órfãs; acrescente -a para imagens sem uso). O disco virtual do WSL só encolhe depois de compactado (Docker Desktop > Troubleshoot > Clean/Purge data, ou Optimize-VHD com admin).' -GanhoBytes ([int64]($appDocker.Bytes * 0.5)) -Ganho "variável (até $($appDocker.Tamanho))" -Risco 'Médio' -Acao 'Manual: guiar comandos docker com o usuário (ele decide o que apagar)' -Prioridade $(if ($livrePct -lt 15) { 2 } else { 3 })
}
if ($maioresArquivos.Count -gt 0) {
    $somaGrandes = [int64](($maioresArquivos | Measure-Object Bytes -Sum).Sum)
    $prioG = if ($livrePct -lt 15) { 2 } else { 3 }
    Add-Rec 'Espaço' "Revisar $($maioresArquivos.Count) arquivos grandes (300 MB+) no seu perfil" 'Lista na seção "Maiores arquivos" do relatório. Decida um a um: apagar, mover para externo/HD ou manter.' -GanhoBytes $somaGrandes -Ganho "até $(Format-Tamanho $somaGrandes)" -Risco 'Médio' -Acao 'Manual: revisar lista com o usuário; remover com Remover-Arquivos.ps1' -Prioridade $prioG
}

# ======================================================== 4. LIMPEZA ==
Write-Etapa '[4/10] Temporários, caches e sobras'
$medicoes = @()
foreach ($item in $Script:CatalogoLimpeza) { $medicoes += Measure-ItemLimpeza -Item $item -EhAdmin $ehAdmin }
$D.Limpeza = $medicoes | ForEach-Object {
    [pscustomobject]@{ Id = $_.Id; Nome = $_.Nome; Bytes = $_.Bytes; Tamanho = (Format-Tamanho $_.Bytes); Risco = $_.Risco; RequerAdmin = $_.RequerAdmin; MedicaoCompleta = $_.MedicaoCompleta; Observacao = $_.Observacao; Alvos = $_.Alvos }
}
foreach ($m in $medicoes) {
    $item = Get-ItemLimpeza $m.Id
    $abertos = @($m.Alvos | Where-Object { $_.Estado -like 'App aberto*' } | ForEach-Object { ($_.Estado -replace '^App aberto \(|\).*$', '') } | Sort-Object -Unique)
    $det = $item.Explicacao
    if ($abertos.Count -gt 0) { $det += " Feche antes: $($abertos -join ', ')." }
    if ($m.Observacao) { $det += " $($m.Observacao)" }
    switch ($m.Tipo) {
        'DISM' {
            if ($livrePct -lt 20) { Add-Rec 'Espaço' $m.Nome $det -Ganho '0,5-5 GB (estimado)' -Admin $true -Acao "Limpeza-Sistema.ps1 -Itens $($m.Id)" -Prioridade 2 }
        }
        'CleanMgr' {
            if ($m.Bytes -gt 500MB) { Add-Rec 'Espaço' $m.Nome $det -GanhoBytes $m.Bytes -Admin $true -Acao "Limpeza-Sistema.ps1 -Itens $($m.Id)" -Prioridade 1 }
            elseif ($livrePct -lt 20) { Add-Rec 'Espaço' $m.Nome $det -Ganho 'variável (medição completa requer admin)' -Admin $true -Acao "Limpeza-Sistema.ps1 -Itens $($m.Id)" -Prioridade 2 }
        }
        'Lixeira' {
            $prioL = if ($m.Bytes -ge 1GB -and $livrePct -lt 20) { 1 } else { 2 }
            if ($m.Bytes -gt 100MB) { Add-Rec 'Espaço' $m.Nome $det -GanhoBytes $m.Bytes -Risco 'Médio' -Acao "Limpeza-Sistema.ps1 -Itens $($m.Id)" -Prioridade $prioL }
        }
        default {
            $minimo = if ($m.RequerAdmin -and -not $m.MedicaoCompleta) { 1 } else { 50MB }
            if ($m.Bytes -ge $minimo -or ($m.RequerAdmin -and -not $m.MedicaoCompleta -and $livrePct -lt 20)) {
                $prio = if ($m.Bytes -ge 1GB -or ($livrePct -lt 15 -and $m.Bytes -ge 300MB)) { 1 } elseif ($m.Bytes -ge 200MB) { 2 } else { 3 }
                $ganhoTxt = if (-not $m.MedicaoCompleta) { "$(Format-Tamanho $m.Bytes)+ (parcial)" } else { '' }
                Add-Rec 'Espaço' "Limpar: $($m.Nome)" $det -GanhoBytes $m.Bytes -Ganho $ganhoTxt -Risco $m.Risco -Admin $m.RequerAdmin -Acao "Limpeza-Sistema.ps1 -Itens $($m.Id)" -Prioridade $prio
            }
        }
    }
}

# ================================================= 5. PROGRAMAS E JOGOS ==
Write-Etapa '[5/10] Programas instalados e jogos'
$chavesUninst = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$programas = @(Get-ItemProperty $chavesUninst -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName -and $_.EstimatedSize } |
    Sort-Object DisplayName -Unique |
    ForEach-Object {
        $data = ''
        if ($_.InstallDate -match '^\d{8}$') { $data = "$($_.InstallDate.Substring(0,4))-$($_.InstallDate.Substring(4,2))-$($_.InstallDate.Substring(6,2))" }
        [pscustomobject]@{ Programa = $_.DisplayName; Editor = $_.Publisher; Bytes = [int64]$_.EstimatedSize * 1KB; Tamanho = (Format-Tamanho ([int64]$_.EstimatedSize * 1KB)); Instalado = $data }
    } | Sort-Object Bytes -Descending | Select-Object -First 20)

$jogos = @()
if (-not $Rapido) {
    $steamPath = Get-ValorRegistro 'HKCU:\Software\Valve\Steam' 'SteamPath'
    if ($steamPath) {
        $libs = @($steamPath -replace '/', '\')
        $vdf = Join-Path $libs[0] 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in (Select-String -LiteralPath $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches)) {
                foreach ($mm in $m.Matches) { $libs += ($mm.Groups[1].Value -replace '\\\\', '\') }
            }
        }
        foreach ($lib in ($libs | Sort-Object -Unique)) {
            foreach ($acf in (Get-ChildItem -LiteralPath (Join-Path $lib 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue)) {
                $txt = Get-Content -LiteralPath $acf.FullName -Raw -ErrorAction SilentlyContinue
                $nome = if ($txt -match '"name"\s+"([^"]+)"') { $Matches[1] } else { $acf.BaseName }
                $tam = if ($txt -match '"SizeOnDisk"\s+"(\d+)"') { [int64]$Matches[1] } else { 0 }
                $ult = ''
                if ($txt -match '"LastPlayed"\s+"(\d+)"' -and [int64]$Matches[1] -gt 0) { $ult = ([DateTimeOffset]::FromUnixTimeSeconds([int64]$Matches[1])).LocalDateTime.ToString('yyyy-MM-dd') }
                $jogos += [pscustomobject]@{ Plataforma = 'Steam'; Jogo = $nome; Bytes = $tam; Tamanho = (Format-Tamanho $tam); Unidade = $lib.Substring(0, 1).ToUpper(); UltimaVez = $ult }
            }
        }
    }
    $manEpic = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    foreach ($it in (Get-ChildItem -LiteralPath $manEpic -Filter '*.item' -ErrorAction SilentlyContinue)) {
        try {
            $j = Get-Content -LiteralPath $it.FullName -Raw | ConvertFrom-Json
            if ($j.DisplayName -and $j.InstallLocation) {
                $jogos += [pscustomobject]@{ Plataforma = 'Epic'; Jogo = $j.DisplayName; Bytes = [int64]$j.InstallSize; Tamanho = (Format-Tamanho ([int64]$j.InstallSize)); Unidade = ([string]$j.InstallLocation).Substring(0, 1).ToUpper(); UltimaVez = '' }
            }
        } catch {}
    }
    foreach ($vol in ($listaVolumes | Where-Object { $_.Tipo -eq 'Fixo' })) {
        $rg = "$($vol.Letra):\Riot Games"
        if (Test-Path -LiteralPath $rg) {
            foreach ($g in (Get-ChildItem -LiteralPath $rg -Directory -ErrorAction SilentlyContinue)) {
                if ($g.Name -eq 'Riot Client') { continue }
                $t = Get-TamanhoPasta $g.FullName
                if ($t.Bytes -gt 0) { $jogos += [pscustomobject]@{ Plataforma = 'Riot'; Jogo = $g.Name; Bytes = $t.Bytes; Tamanho = (Format-Tamanho $t.Bytes); Unidade = $vol.Letra; UltimaVez = '' } }
            }
        }
        $xg = "$($vol.Letra):\XboxGames"
        if (Test-Path -LiteralPath $xg) {
            foreach ($g in (Get-ChildItem -LiteralPath $xg -Directory -ErrorAction SilentlyContinue)) {
                if ($g.Name -eq 'GameSave') { continue }
                $t = Get-TamanhoPasta $g.FullName
                $jogos += [pscustomobject]@{ Plataforma = 'Xbox/Game Pass'; Jogo = $g.Name; Bytes = $t.Bytes; Tamanho = (Format-Tamanho $t.Bytes); Unidade = $vol.Letra; UltimaVez = '' }
            }
        }
    }
    $jogos = @($jogos | Sort-Object Bytes -Descending)
}
$D.Programas = [ordered]@{ MaioresProgramas = $programas; Jogos = $jogos }

$jogosNoSys = @($jogos | Where-Object { $_.Unidade -eq $letraSistema })
$bytesJogosSys = [int64](($jogosNoSys | Measure-Object Bytes -Sum).Sum)
if ($programas.Count -gt 0 -and $livrePct -lt 20) {
    $top = ($programas | Select-Object -First 5 | ForEach-Object { "$($_.Programa) ($($_.Tamanho))" }) -join '; '
    Add-Rec 'Espaço' 'Desinstalar programas grandes que você não usa' "Maiores: $top. Lista completa no relatório. A desinstalação é feita pelo próprio Windows." -Ganho 'variável' -Risco 'Baixo' -Acao 'Manual: abrir ms-settings:appsfeatures e desinstalar os que o usuário escolher' -Prioridade 2
}
if ($jogosNoSys.Count -gt 0) {
    if ($topologia -in @('SSD + HD', 'Vários SSDs') -and $volDados) {
        Add-Rec 'Armazenamento' "Mover jogos pouco jogados para $($volDados.Letra): ($($jogosNoSys.Count) jogos no $($letraSistema):)" 'Use o próprio launcher: Steam > Configurações > Armazenamento > Mover; Xbox app > Gerenciar > Arquivos > Mover. Jogos que você joga muito podem ficar no SSD.' -GanhoBytes $bytesJogosSys -Ganho "até $(Format-Tamanho $bytesJogosSys)" -Acao 'Manual: guiar movimentação pelo launcher' -Prioridade 2
    } elseif ($livrePct -lt 20) {
        Add-Rec 'Espaço' "Desinstalar jogos que você não joga mais ($($jogosNoSys.Count) jogos, $(Format-Tamanho $bytesJogosSys))" 'Seus saves geralmente ficam na nuvem do launcher. Jogos pouco jogados podem ir para um SSD/HD externo (a Steam aceita bibliotecas em disco USB).' -GanhoBytes $bytesJogosSys -Ganho "até $(Format-Tamanho $bytesJogosSys)" -Risco 'Baixo' -Acao 'Manual: desinstalar pelo launcher os jogos que o usuário escolher' -Prioridade 2
    }
}

# ========================================================= 6. MEMÓRIA ==
Write-Etapa '[6/10] Memória e processos'
$ramUsoPct = [math]::Round(100 * ($ramTotal - $ramLivre) / $ramTotal, 0)
$commitTotal = [int64]$os.TotalVirtualMemorySize * 1KB
$commitLivre = [int64]$os.FreeVirtualMemory * 1KB
$processos = @(Get-Process -ErrorAction SilentlyContinue | Group-Object ProcessName | ForEach-Object {
        $b = [int64](($_.Group | Measure-Object WorkingSet64 -Sum).Sum)
        [pscustomobject]@{ Processo = $_.Name; Instancias = $_.Count; Bytes = $b; Memoria = (Format-Tamanho $b) }
    } | Sort-Object Bytes -Descending | Select-Object -First 15)
$D.Memoria = [ordered]@{
    Total = (Format-Tamanho $ramTotal); EmUso = (Format-Tamanho ($ramTotal - $ramLivre)); UsoPct = $ramUsoPct
    CommitUsado = (Format-Tamanho ($commitTotal - $commitLivre)); CommitLimite = (Format-Tamanho $commitTotal)
    MaioresProcessos = $processos
}
if ($ramUsoPct -ge 85) {
    $top = ($processos | Select-Object -First 4 | ForEach-Object { "$($_.Processo) ($($_.Memoria))" }) -join '; '
    Add-Rec 'RAM' "Uso de memória alto agora ($ramUsoPct%)" "Maiores consumidores: $top. Feche abas/apps que não está usando; os itens de inicialização e serviços abaixo reduzem o consumo permanente." -Ganho 'RAM' -Acao 'Manual: orientar o usuário' -Prioridade 1
}
if ($ramTotal -le 8GB) {
    Add-Rec 'RAM' "Pouca RAM instalada ($(Format-Tamanho $ramTotal))" 'Com 8 GB ou menos, navegadores e jogos disputam memória. Upgrade para 16 GB é barato na maioria dos PCs.' -Ganho 'Grande (hardware)' -Acao 'Manual: orientar upgrade' -Prioridade 3
}

# ================================================== 7. INICIALIZAÇÃO ==
Write-Etapa '[7/10] Programas que iniciam com o Windows'
$inic = @(Get-ItensInicializacao)
$D.Inicializacao = @($inic | Select-Object Nome, Ativo, Classificacao, Motivo, Origem, Escopo, Admin, Comando)
$dispensaveis = @($inic | Where-Object { $_.Ativo -and $_.Classificacao -eq 'Dispensável' })
if ($dispensaveis.Count -gt 0) {
    $nomes = @($dispensaveis | ForEach-Object { $_.Nome } | Sort-Object -Unique)
    $lista = ($nomes | ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ','
    $prio = if ($dispensaveis.Count -ge 3) { 1 } else { 2 }
    $precisaAdm = [bool]($dispensaveis | Where-Object { $_.Admin })
    Add-Rec 'RAM' "Tirar $($nomes.Count) programas da inicialização: $($nomes -join ', ')" 'Eles continuam instalados e abrem normalmente quando você quiser; só não abrem sozinhos com o Windows. Reversível a qualquer momento (Gerenciador de Tarefas > Inicializar).' -Ganho 'RAM + boot mais rápido' -Admin $precisaAdm -Acao "Otimizar-Sistema.ps1 -Acoes DesativarInicializacao -Inicializacao $lista" -Prioridade $prio
}
$avaliar = @($inic | Where-Object { $_.Ativo -and $_.Classificacao -eq 'Avaliar' })
if ($avaliar.Count -gt 0) {
    Add-Rec 'RAM' "Avaliar outros $($avaliar.Count) itens de inicialização" "Itens que dependem do seu uso: $((($avaliar | ForEach-Object { $_.Nome }) | Sort-Object -Unique) -join ', '). Veja o motivo de cada um no relatório." -Ganho 'RAM' -Acao 'Manual: perguntar ao usuário quais usa; depois Otimizar-Sistema.ps1 -Acoes DesativarInicializacao -Inicializacao <nomes>' -Prioridade 3
}

# ======================================================= 8. SERVIÇOS ==
Write-Etapa '[8/10] Serviços em segundo plano'
$wmiSvcs = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)
$contPorPid = @{}
foreach ($s in $wmiSvcs) { if ($s.ProcessId -gt 0) { $k = [string]$s.ProcessId; if ($contPorPid.ContainsKey($k)) { $contPorPid[$k]++ } else { $contPorPid[$k] = 1 } } }
$impressorasReais = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'PDF|XPS|OneNote|Fax|Send To|Enviar para|Microsoft Print' })
$semImpressora = ($impressorasReais.Count -eq 0)
$semBluetooth = -not [bool](Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Bluetooth'" -ErrorAction SilentlyContinue)
$servicosAplicaveis = @()
$servicosStatus = @()
foreach ($c in $Script:CatalogoServicos) {
    $w = $wmiSvcs | Where-Object { $_.Name -eq $c.Nome } | Select-Object -First 1
    if (-not $w) { continue }
    $ram = [int64]0
    if ($w.State -eq 'Running' -and $w.ProcessId -gt 0 -and $contPorPid[[string]$w.ProcessId] -eq 1) {
        $pr = Get-Process -Id $w.ProcessId -ErrorAction SilentlyContinue
        if ($pr) { $ram = [int64]$pr.WorkingSet64 }
    }
    $precisaMudar = if ($c.Recomendado -eq 'Disabled') { $w.StartMode -ne 'Disabled' } else { $w.StartMode -eq 'Auto' }
    $condOk = $true
    if ($c.Condicao -eq 'SemImpressora' -and -not $semImpressora) { $condOk = $false }
    if ($c.Condicao -eq 'SemBluetooth' -and -not $semBluetooth) { $condOk = $false }
    $bloqueioCorp = ($gerenciado -and $c.Corporativo)
    $servicosStatus += [pscustomobject]@{ Servico = $c.Nome; Nome = $c.Exibicao; Inicio = $w.StartMode; Estado = $w.State; RAM = (Format-Tamanho $ram); Recomendado = $c.Recomendado; Aplicavel = ($precisaMudar -and $condOk -and -not $bloqueioCorp) }
    if ($precisaMudar -and $condOk -and -not $bloqueioCorp -and ($w.StartMode -eq 'Auto' -or $w.State -eq 'Running')) {
        $servicosAplicaveis += [pscustomobject]@{ Nome = $c.Nome; Exibicao = $c.Exibicao; Risco = $c.Risco; RamBytes = $ram }
    }
}
$D.Servicos = [ordered]@{ Catalogo = $servicosStatus; Manter = $Script:ServicosManter; ImpressorasFisicas = $impressorasReais.Count; Bluetooth = (-not $semBluetooth) }
if ($servicosAplicaveis.Count -gt 0) {
    $ramSvc = [int64](($servicosAplicaveis | Measure-Object RamBytes -Sum).Sum)
    $riscoSvc = if ($servicosAplicaveis | Where-Object { $_.Risco -eq 'Médio' }) { 'Médio' } else { 'Baixo' }
    $lista = ($servicosAplicaveis | ForEach-Object { "'$($_.Nome)'" }) -join ','
    $ganhoSvc = if ($ramSvc -gt 0) { "~$(Format-Tamanho $ramSvc) RAM + CPU/disco" } else { 'CPU/disco em segundo plano' }
    Add-Rec 'RAM' "Ajustar $($servicosAplicaveis.Count) serviços desnecessários: $(($servicosAplicaveis | ForEach-Object { $_.Exibicao }) -join '; ')" 'Configurados para Manual/Desativado com backup do estado anterior (reversível com Desfazer.ps1).' -Ganho $ganhoSvc -Risco $riscoSvc -Admin $true -Acao "Otimizar-Sistema.ps1 -Acoes DesativarServicos -Servicos $lista" -Prioridade 2
}

# ======================================= 9. APPS, RECURSOS E CONFIGURAÇÕES ==
Write-Etapa '[9/10] Apps pré-instalados, recursos opcionais e configurações'
$appx = @(Get-AppxPackage -ErrorAction SilentlyContinue)
$appsEncontrados = @()
foreach ($c in $Script:CatalogoApps) {
    foreach ($p in ($appx | Where-Object { $_.Name -like $c.Padrao -and -not $_.IsFramework -and -not $_.NonRemovable })) {
        if (Test-AppProtegido $p.Name) { continue }
        $appsEncontrados += [pscustomobject]@{ Pacote = $p.Name; Nome = $c.Nome; Risco = $c.Risco }
    }
}
$appsEncontrados = @($appsEncontrados | Sort-Object Pacote -Unique)
$appsBaixo = @($appsEncontrados | Where-Object { $_.Risco -eq 'Baixo' })
$appsMedio = @($appsEncontrados | Where-Object { $_.Risco -eq 'Médio' })
if ($appsBaixo.Count -gt 0) {
    $lista = ($appsBaixo | ForEach-Object { "'$($_.Pacote)'" }) -join ','
    Add-Rec 'Apps' "Remover $($appsBaixo.Count) apps pré-instalados raramente usados" "Apps: $(($appsBaixo | ForEach-Object { $_.Nome }) -join ', '). Podem ser reinstalados pela Microsoft Store." -Ganho 'Espaço + processos em segundo plano' -Acao "Otimizar-Sistema.ps1 -Acoes RemoverApps -Apps $lista" -Prioridade 3
}
if ($appsMedio.Count -gt 0) {
    Add-Rec 'Apps' "Avaliar $($appsMedio.Count) apps que muita gente usa" "Apps: $(($appsMedio | ForEach-Object { "$($_.Nome) [$($_.Pacote)]" }) -join ', '). Remova só os que você confirmar que não usa." -Ganho 'Pequeno' -Risco 'Médio' -Acao 'Manual: perguntar quais usa; depois Otimizar-Sistema.ps1 -Acoes RemoverApps -Apps <pacotes>' -Prioridade 3
}

$recursosAtivos = @()
try {
    $of = @(Get-CimInstance Win32_OptionalFeature -ErrorAction Stop)
    foreach ($c in $Script:CatalogoRecursos) {
        $f = $of | Where-Object { $_.Name -eq $c.Nome } | Select-Object -First 1
        if ($f -and [int]$f.InstallState -eq 1) { $recursosAtivos += [pscustomobject]@{ Nome = $c.Nome; Exibicao = $c.Exibicao; Risco = $c.Risco; Seguranca = $c.Seguranca; Prioridade = $c.Prioridade; Motivo = $c.Motivo } }
    }
} catch {}
foreach ($r in $recursosAtivos) {
    if ($gerenciado -and -not $r.Seguranca) { continue }
    $cat = if ($r.Seguranca) { 'Segurança' } else { 'Recursos' }
    $det = $r.Motivo + ' Requer reiniciar para concluir.'
    if ($gerenciado) { $det += ' PC gerenciado pela empresa: confirme com o TI.' }
    Add-Rec $cat "Desativar recurso: $($r.Exibicao)" $det -Ganho $(if ($r.Seguranca) { 'Segurança' } else { 'Pequeno' }) -Risco $r.Risco -Admin $true -Acao "Otimizar-Sistema.ps1 -Acoes DesativarRecursos -Recursos '$($r.Nome)'" -Prioridade $r.Prioridade
}

$cfg = [ordered]@{}
$cfg.HiberfilBytes = $hiberBytes
$cfg.Hibernacao = ($hiberBytes -gt 0)
$cfg.InicializacaoRapida = ((Get-ValorRegistro 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled') -eq 1)
$cfg.SensorArmazenamento = ((Get-ValorRegistro 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01') -eq 1)
$cfg.AppsSegundoPlanoBloqueados = ((Get-ValorRegistro 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled') -eq 1)
$cfg.Transparencia = ((Get-ValorRegistro 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency') -ne 0)
$cfg.Animacoes = ([string](Get-ValorRegistro 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate') -ne '0')
$cfg.GravacaoEmSegundoPlano = ((Get-ValorRegistro 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled') -eq 1)
$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$cfg.SugestoesEAppsAutomaticos = [bool](@('SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled') | Where-Object { (Get-ValorRegistro $cdm $_) -ne 0 })
if ($ehWin11) { $cfg.NoticiasWidgets = ((Get-ValorRegistro 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa') -ne 0) }
else { $cfg.NoticiasWidgets = ((Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds') -and ((Get-ValorRegistro 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' 'ShellFeedsTaskbarViewMode') -ne 2)) }
$pp = ((powercfg /getactivescheme) -join ' ')
$cfg.PlanoEnergia = if ($pp -match '\(([^)]+)\)\s*$') { $Matches[1] } else { '' }
$cfg.PlanoEnergiaGuid = if ($pp -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $Matches[1] } else { '' }
$co = ((compact.exe /compactos:query 2>$null) -join ' ')
$cfg.CompactOS = if ($co -match 'não está|is not') { $false } elseif ($co -match 'está no estado|is in the Compact') { $true } else { $null }
$D.Configuracoes = $cfg
$D.Apps = [ordered]@{ Removiveis = $appsEncontrados; RecursosAtivos = $recursosAtivos }

if ($hiberBytes -gt 1GB) {
    if ($notebook) {
        $ganhoRed = [int64]([Math]::Max([double]0, [double]$hiberBytes - ($ramTotal * 0.2)))
        Add-Rec 'Espaço' "Reduzir o arquivo de hibernação ($(Format-Tamanho $hiberBytes))" 'Notebook: mantém a Inicialização Rápida e reduz hiberfil.sys para ~20% da RAM. Se você nunca usa "Hibernar", pode desativar de vez (ação DesativarHibernacao).' -GanhoBytes $ganhoRed -Admin $true -Acao 'Otimizar-Sistema.ps1 -Acoes ReduzirHibernacao' -Prioridade $(if ($livrePct -lt 15) { 1 } else { 2 })
    } else {
        Add-Rec 'Espaço' "Desativar a hibernação (apaga hiberfil.sys de $(Format-Tamanho $hiberBytes))" 'Desktop raramente usa "Hibernar". Desativa também a Inicialização Rápida (imperceptível com SSD). "Suspender" continua funcionando. Reversível.' -GanhoBytes $hiberBytes -Admin $true -Acao 'Otimizar-Sistema.ps1 -Acoes DesativarHibernacao' -Prioridade $(if ($livrePct -lt 15) { 1 } else { 2 })
    }
}
if ($livrePct -lt 15 -and $cfg.CompactOS -eq $false) {
    Add-Rec 'Espaço' 'Compactar os arquivos do Windows (CompactOS)' 'Recurso oficial que comprime os binários do sistema. Custo de CPU imperceptível em PCs atuais. Leva 10-20 min. Reversível.' -Ganho '~2-4 GB' -Admin $true -Acao 'Otimizar-Sistema.ps1 -Acoes CompactarWindows' -Prioridade 2
}
if ($livrePct -lt 15) {
    Add-Rec 'Espaço' 'Limitar o espaço dos pontos de restauração a 5% do disco' 'Mantém os pontos mais recentes e libera o excesso. Medição exata requer admin.' -Ganho 'depende do uso atual' -Risco 'Médio' -Admin $true -Acao 'Otimizar-Sistema.ps1 -Acoes LimitarPontosRestauracao' -Prioridade 3
}
if (-not $cfg.SensorArmazenamento) {
    Add-Rec 'Espaço' 'Ativar o Sensor de Armazenamento (limpeza automática)' 'Limpa temporários e itens com 30+ dias na Lixeira automaticamente. A pasta Downloads NÃO é tocada.' -Ganho 'Manutenção contínua' -Acao 'Otimizar-Sistema.ps1 -Acoes AtivarSensorArmazenamento' -Prioridade 2
}
if (-not $ehWin11 -and -not $cfg.AppsSegundoPlanoBloqueados) {
    Add-Rec 'RAM' 'Impedir apps da Loja de rodarem em segundo plano' 'Apps como Clima, Notícias e Mapas param de rodar escondidos. Apps de mensagem da Loja podem atrasar notificações.' -Ganho 'RAM/CPU/bateria' -Acao 'Otimizar-Sistema.ps1 -Acoes DesativarAppsSegundoPlano' -Prioridade 2
}
if ($cfg.GravacaoEmSegundoPlano) {
    Add-Rec 'Desempenho' 'Desligar a gravação de jogos em segundo plano (Xbox Game Bar)' 'A gravação contínua dos últimos minutos custa FPS e espaço. Você ainda pode gravar manualmente (Win + Alt + R).' -Ganho 'FPS em jogos' -Acao 'Otimizar-Sistema.ps1 -Acoes DesativarGameDVR' -Prioridade 2
}
if ($cfg.SugestoesEAppsAutomaticos) {
    Add-Rec 'Apps' 'Bloquear sugestões e instalação automática de apps patrocinados' 'Impede que o Windows instale jogos/apps de propaganda (ex.: Candy Crush) e mostre sugestões no Iniciar.' -Ganho 'Evita bloatware futuro' -Acao 'Otimizar-Sistema.ps1 -Acoes DesativarSugestoes' -Prioridade 3
}
if ($cfg.NoticiasWidgets) {
    Add-Rec 'RAM' 'Desativar Notícias e Interesses / Widgets da barra de tarefas' 'Remove o painel de notícias que fica carregado em segundo plano.' -Ganho 'RAM/rede' -Acao 'Otimizar-Sistema.ps1 -Acoes DesativarNoticias' -Prioridade 3
}
if ($ramTotal -le 8GB -and ($cfg.Transparencia -or $cfg.Animacoes)) {
    Add-Rec 'Desempenho' 'Reduzir efeitos visuais (transparência e animações)' 'Deixa a interface mais ágil em PCs com pouca RAM/GPU integrada. Fontes e miniaturas continuam iguais.' -Ganho 'Pequeno' -Acao 'Otimizar-Sistema.ps1 -Acoes EfeitosVisuais' -Prioridade 3
}
if (-not $notebook -and $cfg.PlanoEnergiaGuid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a') {
    Add-Rec 'Desempenho' 'Trocar o plano de energia "Economia" por "Alto desempenho"' 'Desktop em modo economia limita a CPU sem necessidade.' -Ganho 'Desempenho de CPU' -Acao 'Otimizar-Sistema.ps1 -Acoes PlanoEnergiaDesempenho' -Prioridade 2
}

# ================================================= 10. PASTAS PESSOAIS ==
Write-Etapa '[10/10] Downloads e Área de Trabalho'
$pastasAnalisadas = @()
foreach ($alvo in @(@{ Nome = 'Downloads'; Caminho = (Get-PastaDownloads) }, @{ Nome = 'Área de Trabalho'; Caminho = [Environment]::GetFolderPath('Desktop') })) {
    if (-not (Test-Path -LiteralPath $alvo.Caminho)) { continue }
    try {
        $an = & "$PSScriptRoot\Analisar-Pasta.ps1" -Pasta $alvo.Caminho -Silencioso -SemSalvar -SemDuplicados:$Rapido
    } catch { continue }
    if (-not $an) { continue }
    $pastasAnalisadas += [pscustomobject]@{
        Pasta = $alvo.Nome; Caminho = $alvo.Caminho; Itens = $an.ItensRaiz; Arquivos = $an.TotalArquivos; Tamanho = (Format-Tamanho $an.TotalBytes); Bytes = $an.TotalBytes
        Categorias = $an.Categorias; InstaladoresAntigos = $an.Resumo.InstaladoresAntigos; Duplicados = $an.Resumo.Duplicados
        Incompletos = $an.Resumo.Incompletos; CompactadosExtraidos = $an.Resumo.CompactadosExtraidos; Antigos = $an.Resumo.Antigos
    }
    $limiteItens = if ($alvo.Nome -eq 'Downloads') { 40 } else { 25 }
    if ($an.ItensRaiz -ge $limiteItens -or $an.TotalBytes -ge 2GB) {
        $prio = if ($an.ItensRaiz -ge 100 -or $an.TotalBytes -ge 10GB) { 1 } else { 2 }
        Add-Rec 'Organização' "Organizar a pasta $($alvo.Nome) ($($an.ItensRaiz) itens soltos, $(Format-Tamanho $an.TotalBytes))" 'Os arquivos são COPIADOS para uma estrutura limpa em Documentos/Imagens/Vídeos/Músicas; os originais só são apagados se você aprovar no fim.' -Ganho 'Organização' -Acao "Planejar-Organizacao.ps1 -Origem '$($alvo.Caminho)'" -Prioridade $prio
    }
    $r = $an.Resumo
    $ganhoLixo = [int64]$r.InstaladoresAntigos.Bytes + [int64]$r.Duplicados.Bytes + [int64]$r.Incompletos.Bytes + [int64]$r.CompactadosExtraidos.Bytes
    if ($ganhoLixo -ge 100MB) {
        $partes = @()
        if ($r.InstaladoresAntigos.Quantidade) { $partes += "$($r.InstaladoresAntigos.Quantidade) instaladores antigos ($(Format-Tamanho $r.InstaladoresAntigos.Bytes))" }
        if ($r.Duplicados.Quantidade) { $partes += "$($r.Duplicados.Quantidade) cópias duplicadas ($(Format-Tamanho $r.Duplicados.Bytes))" }
        if ($r.CompactadosExtraidos.Quantidade) { $partes += "$($r.CompactadosExtraidos.Quantidade) .zip já extraídos ($(Format-Tamanho $r.CompactadosExtraidos.Bytes))" }
        if ($r.Incompletos.Quantidade) { $partes += "$($r.Incompletos.Quantidade) downloads incompletos ($(Format-Tamanho $r.Incompletos.Bytes))" }
        Add-Rec 'Espaço' "Remover sobras em $($alvo.Nome): $($partes -join '; ')" 'Rode a análise para gerar as listas (CSV) e revise antes. Vão para a Lixeira.' -GanhoBytes $ganhoLixo -Risco 'Baixo' -Acao "Analisar-Pasta.ps1 -Pasta '$($alvo.Caminho)'" -Prioridade $(if ($ganhoLixo -ge 1GB) { 1 } else { 2 })
    }
}
$D.PastasPessoais = $pastasAnalisadas

if ($topologia -in @('SSD + HD', 'Vários SSDs') -and $volDados) {
    foreach ($bib in @(@{ Id = 'Videos'; Nome = 'Vídeos'; Pasta = [Environment]::GetFolderPath('MyVideos') }, @{ Id = 'Imagens'; Nome = 'Imagens'; Pasta = [Environment]::GetFolderPath('MyPictures') }, @{ Id = 'Musicas'; Nome = 'Músicas'; Pasta = [Environment]::GetFolderPath('MyMusic') })) {
        if (-not $bib.Pasta -or $bib.Pasta.Substring(0, 1) -ne $letraSistema -or $bib.Pasta -match 'OneDrive') { continue }
        $t = Get-TamanhoPasta $bib.Pasta
        if ($t.Bytes -lt 1GB) { continue }
        $prio = if ($livrePct -lt 20) { 1 } else { 2 }
        Add-Rec 'Armazenamento' "Mover a biblioteca $($bib.Nome) ($(Format-Tamanho $t.Bytes)) para $($volDados.Letra):" 'Usa o mesmo mecanismo da aba "Local" das Propriedades da pasta: copia, verifica, aponta o Windows para o novo local. Os originais só são apagados com sua aprovação.' -GanhoBytes $t.Bytes -Risco 'Médio' -Acao "Mover-Biblioteca.ps1 -Biblioteca $($bib.Id) -Destino '$($volDados.Letra):\$($bib.Nome)'" -Prioridade $prio
    }
}

# ================================================ RECOMENDAÇÕES E RELATÓRIO ==
$ordenadas = @($Recs | Sort-Object @{ Expression = 'Prioridade'; Ascending = $true }, @{ Expression = 'GanhoBytes'; Descending = $true })
$i = 0
foreach ($r in $ordenadas) { $i++; $r.Id = ('R{0:D2}' -f $i) }
$D.Recomendacoes = $ordenadas
$ganhoTotal = [int64](($ordenadas | Where-Object { $_.Categoria -eq 'Espaço' -and $_.Titulo -notlike 'Revisar*' -and $_.Titulo -notlike 'Docker*' } | Measure-Object GanhoBytes -Sum).Sum)
$D.Resumo = [ordered]@{
    EspacoLivre = "$($volSys.Livre) de $($volSys.Total) ($livrePct%) - $situacaoEspaco"
    GanhoEspacoEstimado = (Format-Tamanho $ganhoTotal); GanhoEspacoBytes = $ganhoTotal
    UsoRAM = "$ramUsoPct% de $(Format-Tamanho $ramTotal)"; ItensInicializacaoAtivos = @($inic | Where-Object { $_.Ativo }).Count
    TotalRecomendacoes = $ordenadas.Count; DuracaoSegundos = [int]((Get-Date) - $inicio).TotalSeconds
}

$arqJson = Join-Path $PastaSaida "diagnostico-$carimbo.json"
$arqMd = Join-Path $PastaSaida "diagnostico-$carimbo.md"
Save-Json -Objeto $D -Caminho $arqJson -Profundidade 8

$md = New-Object System.Collections.Generic.List[string]
function L { param([string]$t = '') $md.Add($t) }
function T {
    param($Linhas, [string[]]$Colunas, [string[]]$Titulos)
    if (-not $Linhas -or @($Linhas).Count -eq 0) { L '_(nenhum)_'; L; return }
    L ('| ' + ($Titulos -join ' | ') + ' |')
    L ('|' + (($Titulos | ForEach-Object { '---' }) -join '|') + '|')
    foreach ($r in $Linhas) { L ('| ' + (($Colunas | ForEach-Object { ([string]$r.$_) -replace '\|', '/' -replace "`r?`n", ' ' }) -join ' | ') + ' |') }
    L
}
$sim = { param($b) if ($b) { 'sim' } else { 'não' } }

L "# Diagnóstico do PC - $env:COMPUTERNAME"
L "_Gerado em $((Get-Date).ToString('dd/MM/yyyy HH:mm')) · modo $($D.Modo) · somente leitura_"
L
L '## Resumo'
L "- **Windows:** $($D.Sistema.Windows) · **CPU:** $($D.Sistema.CPU) · **RAM:** $($D.Sistema.RAMTotal)"
L "- **Armazenamento:** $topologia · **$($letraSistema): livre:** $($D.Resumo.EspacoLivre)"
L "- **RAM em uso agora:** $($D.Resumo.UsoRAM) · **Ligado há:** $($D.Sistema.LigadoHaDias) dias"
L "- **Ganho de espaço estimado (se todas as recomendações de espaço forem aceitas):** até $($D.Resumo.GanhoEspacoEstimado)"
L "- **Administrador nesta sessão:** $(& $sim $ehAdmin) · **Pode elevar (UAC):** $(& $sim $podeElevar)$(if (-not $podeElevar) { ' - ações de admin exigirão senha do TI/administrador' })"
if ($gerenciado) { L '- **PC gerenciado por empresa** (domínio/Azure AD/MDM): ajustes de serviços e políticas podem violar regras do TI ou ser revertidos. Priorize limpeza e organização.' }
L
L '## Recomendações'
T $ordenadas @('Id', 'Prioridade', 'Categoria', 'Titulo', 'Ganho', 'Risco', 'AdminTxt') @('ID', 'Prio', 'Categoria', 'Recomendação', 'Ganho', 'Risco', 'Admin')
L '### Detalhes e comandos'
foreach ($r in $ordenadas) {
    L "- **$($r.Id) - $($r.Titulo)**  "
    L "  $($r.Detalhe)  "
    L "  Ação: ``$($r.Acao)``"
}
L
L '## Armazenamento e estratégia'
L "**Topologia detectada:** $topologia"
L
foreach ($e in $estrategia) { L "- $e" }
L
T $listaDiscos @('Numero', 'Modelo', 'Tipo', 'Barramento', 'Tamanho', 'Letras', 'Saude', 'Externo') @('Disco', 'Modelo', 'Tipo', 'Barramento', 'Tamanho', 'Letras', 'Saúde', 'Externo')
T $listaVolumes @('Letra', 'Rotulo', 'Tipo', 'Midia', 'Total', 'Livre', 'LivrePct') @('Unidade', 'Rótulo', 'Tipo', 'Mídia', 'Total', 'Livre', 'Livre %')
L "TRIM ativo: $(if ($null -eq $trim) { 'n/d' } else { & $sim $trim }) · Otimização semanal agendada: $(if ($null -eq $otimAgendada) { 'n/d' } else { & $sim $otimAgendada })"
L
L "## Para onde vai o espaço do $($letraSistema): (usado: $($D.Espaco.Usado))"
T $distribuicao @('Item', 'Tamanho') @('Item', 'Tamanho')
L '### Pastas do seu perfil'
T $pastasPerfil @('Pasta', 'Tamanho', 'Caminho') @('Pasta', 'Tamanho', 'Caminho')
if ($appDataTop.Count) { L '### Maiores pastas dentro de AppData'; T $appDataTop @('Pasta', 'Tamanho') @('Pasta', 'Tamanho') }
if ($maioresArquivos.Count) { L '### Maiores arquivos (300 MB+)'; T $maioresArquivos @('Tamanho', 'Modificado', 'Arquivo') @('Tamanho', 'Modificado', 'Arquivo') }
L '## Limpeza (medição)'
T ($D.Limpeza | Sort-Object Bytes -Descending) @('Id', 'Nome', 'Tamanho', 'Risco', 'RequerAdmin', 'Observacao') @('Id', 'Item', 'Tamanho', 'Risco', 'Admin', 'Obs.')
L '## Programas e jogos'
L '### Maiores programas instalados'
T $programas @('Programa', 'Tamanho', 'Editor', 'Instalado') @('Programa', 'Tamanho', 'Editor', 'Instalado em')
if ($jogos.Count) { L '### Jogos'; T $jogos @('Jogo', 'Plataforma', 'Tamanho', 'Unidade', 'UltimaVez') @('Jogo', 'Plataforma', 'Tamanho', 'Unidade', 'Última vez jogado') }
L '## Memória'
L "Em uso: $($D.Memoria.EmUso) de $($D.Memoria.Total) ($ramUsoPct%) · Memória comprometida: $($D.Memoria.CommitUsado) de $($D.Memoria.CommitLimite)"
L
T $processos @('Processo', 'Instancias', 'Memoria') @('Processo', 'Instâncias', 'Memória')
L '## Inicialização'
T ($D.Inicializacao | Sort-Object @{ Expression = 'Ativo'; Descending = $true }, Classificacao, Nome) @('Nome', 'Ativo', 'Classificacao', 'Motivo', 'Origem', 'Escopo') @('Nome', 'Ativo', 'Classificação', 'Motivo', 'Origem', 'Escopo')
L '## Serviços (catálogo conservador)'
T $servicosStatus @('Servico', 'Nome', 'Inicio', 'Estado', 'RAM', 'Recomendado', 'Aplicavel') @('Serviço', 'Nome', 'Início', 'Estado', 'RAM', 'Recomendado', 'Aplicável')
L '**Serviços que devem ser mantidos (apesar de guias da internet sugerirem desativar):**'
foreach ($m in $Script:ServicosManter) { L "- ``$($m.Nome)``: $($m.Motivo)" }
L
L '## Apps pré-instalados e recursos'
T $appsEncontrados @('Nome', 'Pacote', 'Risco') @('App', 'Pacote', 'Risco')
T $recursosAtivos @('Exibicao', 'Nome', 'Risco', 'Motivo') @('Recurso ativo', 'Nome técnico', 'Risco', 'Motivo')
L '## Configurações'
L "- Hibernação: $(& $sim $cfg.Hibernacao) ($(Format-Tamanho $hiberBytes)) · Inicialização Rápida: $(& $sim $cfg.InicializacaoRapida)"
L "- Sensor de Armazenamento: $(& $sim $cfg.SensorArmazenamento) · CompactOS: $(if ($null -eq $cfg.CompactOS) { 'n/d' } else { & $sim $cfg.CompactOS })"
L "- Apps em segundo plano bloqueados: $(& $sim $cfg.AppsSegundoPlanoBloqueados) · Notícias/Widgets: $(& $sim $cfg.NoticiasWidgets) · Sugestões/apps automáticos: $(& $sim $cfg.SugestoesEAppsAutomaticos)"
L "- Transparência: $(& $sim $cfg.Transparencia) · Animações: $(& $sim $cfg.Animacoes) · Gravação de jogos em 2º plano: $(& $sim $cfg.GravacaoEmSegundoPlano)"
L "- Plano de energia: $($cfg.PlanoEnergia)"
L
L '## Downloads e Área de Trabalho'
foreach ($p in $pastasAnalisadas) {
    L "### $($p.Pasta) - $($p.Itens) itens soltos, $($p.Arquivos) arquivos, $($p.Tamanho)"
    T $p.Categorias @('Categoria', 'Quantidade', 'Tamanho') @('Categoria', 'Arquivos', 'Tamanho')
    L "Instaladores antigos: $($p.InstaladoresAntigos.Quantidade) ($(Format-Tamanho $p.InstaladoresAntigos.Bytes)) · Duplicados: $($p.Duplicados.Quantidade) ($(Format-Tamanho $p.Duplicados.Bytes)) · .zip já extraídos: $($p.CompactadosExtraidos.Quantidade) · Incompletos: $($p.Incompletos.Quantidade) · Sem uso há 1 ano+: $($p.Antigos.Quantidade) ($(Format-Tamanho $p.Antigos.Bytes))"
    L
}
L '---'
L "Dados completos: ``$arqJson``"
$md | Out-File -LiteralPath $arqMd -Encoding utf8

# ------------------------------------------------------------ console ----
Write-Titulo 'RESUMO'
Write-Host "PC: $env:COMPUTERNAME | $($D.Sistema.Windows) | RAM $($D.Sistema.RAMTotal) | ligado há $($D.Sistema.LigadoHaDias) dias"
Write-Host "Armazenamento: $topologia | $($letraSistema): livre $($D.Resumo.EspacoLivre)"
Write-Host "RAM em uso agora: $($D.Resumo.UsoRAM) | Itens de inicialização ativos: $($D.Resumo.ItensInicializacaoAtivos)"
Write-Host "Admin nesta sessão: $(& $sim $ehAdmin) | Pode elevar via UAC: $(& $sim $podeElevar) | Gerenciado por empresa: $(& $sim $gerenciado)"
Write-Host "Ganho de espaço estimado (se todas as recomendações de espaço forem aceitas): até $($D.Resumo.GanhoEspacoEstimado)"
Write-Secao 'Estratégia de armazenamento'
foreach ($e in $estrategia) { Write-Host " - $e" }
Write-Secao "Recomendações ($($ordenadas.Count)) - formato: ID [prioridade | categoria | ganho | risco | admin] título  =>  comando de prévia"
foreach ($r in $ordenadas) {
    Write-Host "$($r.Id) [P$($r.Prioridade) | $($r.Categoria) | $($r.Ganho) | risco $($r.Risco) | admin $($r.AdminTxt)] $($r.Titulo)"
    Write-Host "     => $($r.Acao)"
}
Write-Host ''
Write-Host "Relatório completo: $arqMd"
Write-Host "Dados (JSON):       $arqJson"
Write-Host "Duração: $($D.Resumo.DuracaoSegundos) s"
