<#
.SYNOPSIS
    Otimizações do Windows com PRÉVIA, BACKUP do estado anterior e DESFAZER.
.DESCRIPTION
    SEM -Executar: mostra o estado atual e o que mudaria (nada é alterado).
    COM -Executar: aplica as ações, gravando backup em %LOCALAPPDATA%\OtimizadorPC\backups
    (reversível com Desfazer.ps1). Ações de administrador são puladas, a menos que -Elevar seja usado.
    Antes de ações de administrador, tenta criar um ponto de restauração do Windows.
.PARAMETER Acoes
    Uma ou mais ações (use -Listar). Ex.: DesativarHibernacao,DesativarInicializacao
.PARAMETER Inicializacao
    Nomes dos itens de inicialização (como aparecem no diagnóstico) para DesativarInicializacao.
.PARAMETER Servicos
    Nomes técnicos de serviços (somente do catálogo seguro) para DesativarServicos.
.PARAMETER Apps
    Nomes de pacotes Appx (aceita curinga) para RemoverApps. Pacotes protegidos são recusados.
.PARAMETER Recursos
    Recursos opcionais (somente do catálogo) para DesativarRecursos.
#>
[CmdletBinding()]
param(
    [string[]]$Acoes,
    [string[]]$Servicos,
    [string[]]$Inicializacao,
    [string[]]$Apps,
    [string[]]$Recursos,
    [switch]$Executar,
    [switch]$Elevar,
    [switch]$SomenteAdmin,
    [switch]$SemPontoRestauracao,
    [switch]$Listar
)

. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Catalogo.ps1"

$ehAdmin = Test-Admin
$Acoes = Split-Lista $Acoes; $Servicos = Split-Lista $Servicos; $Inicializacao = Split-Lista $Inicializacao
$Apps = Split-Lista $Apps; $Recursos = Split-Lista $Recursos
$osInfo = Get-CimInstance Win32_OperatingSystem
$ehWin11 = ([int]$osInfo.BuildNumber -ge 22000)
$notebook = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
$ramTotal = [int64]$osInfo.TotalVisibleMemorySize * 1KB
$rxGuid = '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'

$Definicoes = [ordered]@{
    DesativarHibernacao        = @{ Nome = 'Desativar hibernação (apaga hiberfil.sys)'; Admin = 'Sim'; Risco = 'Baixo'; Ganho = 'Espaço (~40% da RAM)' }
    ReduzirHibernacao          = @{ Nome = 'Reduzir arquivo de hibernação (~20% da RAM)'; Admin = 'Sim'; Risco = 'Baixo'; Ganho = 'Espaço' }
    CompactarWindows           = @{ Nome = 'Compactar arquivos do Windows (CompactOS)'; Admin = 'Sim'; Risco = 'Baixo'; Ganho = 'Espaço (~2-4 GB)' }
    LimitarPontosRestauracao   = @{ Nome = 'Limitar pontos de restauração a 5% do disco'; Admin = 'Sim'; Risco = 'Médio'; Ganho = 'Espaço' }
    AtivarSensorArmazenamento  = @{ Nome = 'Ativar Sensor de Armazenamento'; Admin = 'Não'; Risco = 'Baixo'; Ganho = 'Limpeza automática' }
    DesativarInicializacao     = @{ Nome = 'Tirar programas da inicialização'; Admin = 'Misto'; Risco = 'Baixo'; Ganho = 'RAM + boot' }
    DesativarServicos          = @{ Nome = 'Ajustar serviços desnecessários (catálogo seguro)'; Admin = 'Sim'; Risco = 'Baixo/Médio'; Ganho = 'RAM/CPU' }
    DesativarAppsSegundoPlano  = @{ Nome = 'Impedir apps da Loja em segundo plano (Windows 10)'; Admin = 'Não'; Risco = 'Baixo'; Ganho = 'RAM/CPU' }
    RemoverApps                = @{ Nome = 'Remover apps pré-instalados'; Admin = 'Não'; Risco = 'Baixo/Médio'; Ganho = 'Espaço + processos' }
    DesativarRecursos          = @{ Nome = 'Desativar recursos opcionais (catálogo)'; Admin = 'Sim'; Risco = 'Baixo/Médio'; Ganho = 'Segurança' }
    DesativarGameDVR           = @{ Nome = 'Desligar gravação de jogos em segundo plano'; Admin = 'Não'; Risco = 'Baixo'; Ganho = 'FPS' }
    DesativarSugestoes         = @{ Nome = 'Bloquear sugestões e apps patrocinados'; Admin = 'Não'; Risco = 'Baixo'; Ganho = 'Evita bloatware' }
    DesativarNoticias          = @{ Nome = 'Desativar Notícias e Interesses / Widgets'; Admin = 'Não'; Risco = 'Baixo'; Ganho = 'RAM/rede' }
    EfeitosVisuais             = @{ Nome = 'Reduzir transparência e animações'; Admin = 'Não'; Risco = 'Baixo'; Ganho = 'Pequeno' }
    PlanoEnergiaDesempenho     = @{ Nome = 'Plano de energia Alto desempenho'; Admin = 'Não'; Risco = 'Baixo'; Ganho = 'CPU' }
    AtivarTRIM                 = @{ Nome = 'Reativar TRIM do SSD'; Admin = 'Sim'; Risco = 'Baixo'; Ganho = 'Desempenho SSD' }
    ReativarOtimizacaoAgendada = @{ Nome = 'Reativar otimização semanal de unidades'; Admin = 'Sim'; Risco = 'Baixo'; Ganho = 'Desempenho disco' }
    OtimizarUnidades           = @{ Nome = 'Otimizar unidades agora (TRIM no SSD / desfragmentar HD)'; Admin = 'Sim'; Risco = 'Baixo'; Ganho = 'Desempenho disco' }
}

if ($Listar -or $Acoes.Count -eq 0) {
    Write-Titulo 'AÇÕES DE OTIMIZAÇÃO DISPONÍVEIS'
    Write-Tabela ($Definicoes.Keys | ForEach-Object { [pscustomobject]@{ Acao = $_; Descricao = $Definicoes[$_].Nome; Admin = $Definicoes[$_].Admin; Risco = $Definicoes[$_].Risco; Ganho = $Definicoes[$_].Ganho } }) @('Acao', 'Descricao', 'Admin', 'Risco', 'Ganho')
    Write-Host ''
    Write-Host 'Uso: Otimizar-Sistema.ps1 -Acoes A,B [-Inicializacao ...] [-Servicos ...] [-Apps ...] [-Recursos ...] [-Executar] [-Elevar]'
    exit 0
}

$sel = @()
foreach ($a in $Acoes) {
    $k = $Definicoes.Keys | Where-Object { $_ -ieq $a } | Select-Object -First 1
    if (-not $k) { Write-Host "Ação desconhecida: '$a'. Use -Listar."; exit 1 }
    $sel += $k
}

# ================================================================ ESPAÇO ==
function Get-Hiberfil { return (Get-ChildItem -LiteralPath "$env:SystemDrive\" -Force -File -Filter 'hiberfil.sys' -ErrorAction SilentlyContinue | Select-Object -First 1) }

function Previa-DesativarHibernacao {
    $h = Get-Hiberfil
    if (-not $h) { return @('A hibernação já está desativada (hiberfil.sys não existe). Nada a fazer.') }
    $l = @("hiberfil.sys atual: $(Format-Tamanho $h.Length) -> será removido.", 'Efeito colateral: desativa a Inicialização Rápida e a opção "Hibernar". "Suspender" continua funcionando.')
    if ($notebook) { $l += 'Notebook: considere ReduzirHibernacao se você usa "Hibernar" ou se a bateria acaba com o PC fechado.' }
    return $l + 'Desfazer: powercfg /hibernate on'
}
function Aplicar-DesativarHibernacao { param($Bk)
    if (-not (Get-Hiberfil)) { Write-Host '   Já estava desativada.'; return }
    Add-BackupEntrada $Bk @{ Tipo = 'Comando'; Descricao = 'Reativar hibernação'; Desfazer = 'powercfg /hibernate on'; Admin = $true }
    $o = & powercfg.exe /hibernate off 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg: $o" }
    Write-Host '   OK: hibernação desativada (hiberfil.sys removido).'
}

function Previa-ReduzirHibernacao {
    $h = Get-Hiberfil
    if (-not $h) { return @('A hibernação está desativada; não há arquivo para reduzir. Nada a fazer.') }
    return @("hiberfil.sys atual: $(Format-Tamanho $h.Length) -> ~$(Format-Tamanho ($ramTotal * 0.2)) (tipo reduzido).", 'Mantém a Inicialização Rápida; remove a opção "Hibernar" do menu.', 'Desfazer: powercfg /hibernate /type full')
}
function Aplicar-ReduzirHibernacao { param($Bk)
    if (-not (Get-Hiberfil)) { Write-Host '   Hibernação desativada - nada a reduzir.'; return }
    Add-BackupEntrada $Bk @{ Tipo = 'Comando'; Descricao = 'Hibernação tamanho completo'; Desfazer = 'powercfg /hibernate /type full'; Admin = $true }
    $o = & powercfg.exe /hibernate /type reduced 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg: $o" }
    Write-Host '   OK: arquivo de hibernação reduzido.'
}

function Previa-CompactarWindows {
    $q = ((compact.exe /compactos:query 2>$null) -join ' ')
    if ($q -match 'está no estado Compacto\.|is in the Compact state\.') { return @('O Windows já está compactado. Nada a fazer.') }
    return @("Estado atual: $q", 'Comprime os arquivos do sistema com o recurso oficial CompactOS. Ganho típico: 2-4 GB.', 'Leva 10-20 minutos; o PC pode ficar lento durante o processo. Custo de CPU depois: imperceptível.', 'Desfazer: compact.exe /CompactOS:never')
}
function Aplicar-CompactarWindows { param($Bk)
    Add-BackupEntrada $Bk @{ Tipo = 'Comando'; Descricao = 'Descompactar Windows'; Desfazer = 'compact.exe /CompactOS:never'; Admin = $true }
    Write-Host '   Compactando (10-20 min)...'
    $antes = (Get-InfoUnidade $env:SystemDrive).Livre
    $o = & compact.exe /CompactOS:always 2>&1
    $o | Select-Object -Last 3 | ForEach-Object { Write-Host "   $_" }
    Write-Host "   Espaço liberado: $(Format-Tamanho ([Math]::Max([int64]0, [int64]((Get-InfoUnidade $env:SystemDrive).Livre - $antes))))"
}

function Get-ShadowStorageSistema {
    try {
        $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$($env:SystemDrive)'" -ErrorAction Stop
        return (Get-CimInstance Win32_ShadowStorage -ErrorAction Stop | Where-Object { $_.Volume.DeviceID -eq $vol.DeviceID } | Select-Object -First 1)
    } catch { return $null }
}
function Previa-LimitarPontosRestauracao {
    if (-not $ehAdmin) { return @('O uso atual dos pontos de restauração só pode ser lido como administrador.', 'A ação define o máximo em 5% do disco; os pontos mais antigos acima disso são descartados pelo Windows.') }
    $ss = Get-ShadowStorageSistema
    if (-not $ss) { return @('Proteção do sistema desativada ou sem pontos de restauração neste disco. Nada a fazer.') }
    $max = if ([uint64]$ss.MaxSpace -ge ([uint64]::MaxValue - 1)) { 'ilimitado' } else { Format-Tamanho ([double]$ss.MaxSpace) }
    return @("Usado agora: $(Format-Tamanho ([double]$ss.UsedSpace)) | Máximo atual: $max", 'Novo máximo: 5% do disco. Os pontos mais antigos acima do limite são removidos.')
}
function Aplicar-LimitarPontosRestauracao { param($Bk)
    $ss = Get-ShadowStorageSistema
    if (-not $ss) { Write-Host '   Sem armazenamento de sombra neste disco - nada a fazer.'; return }
    $prev = if ([uint64]$ss.MaxSpace -ge ([uint64]::MaxValue - 1)) { 'UNBOUNDED' } else { "$([math]::Floor([double]$ss.MaxSpace / 1MB))MB" }
    $sd = $env:SystemDrive
    Add-BackupEntrada $Bk @{ Tipo = 'Comando'; Descricao = 'Limite anterior dos pontos de restauração'; Desfazer = "vssadmin resize shadowstorage /for=$sd /on=$sd /maxsize=$prev"; Admin = $true }
    $o = & vssadmin.exe resize shadowstorage "/for=$sd" "/on=$sd" '/maxsize=5%' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "vssadmin: $($o -join ' ')" }
    Write-Host '   OK: limite definido em 5%.'
}

function Previa-AtivarSensorArmazenamento {
    return @('Liga a limpeza automática do Windows com regras conservadoras:',
        ' - executa quando o espaço estiver baixo; apaga temporários que os apps não usam',
        ' - apaga itens que estão na Lixeira há mais de 30 dias (isso é exclusão definitiva automática)',
        ' - a pasta Downloads NUNCA é tocada')
}
function Aplicar-AtivarSensorArmazenamento { param($Bk)
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
    $valores = [ordered]@{ '01' = 1; '2048' = 0; '04' = 1; '08' = 1; '256' = 30; '32' = 0; '512' = 0 }
    foreach ($n in $valores.Keys) { Set-RegistroComBackup -Backup $Bk -Chave $k -Nome $n -Valor $valores[$n] -Tipo DWord -Descricao 'Sensor de Armazenamento' }
    Write-Host '   OK: Sensor de Armazenamento ativado (Downloads excluída).'
}

# ================================================================ RAM/CPU ==
function Get-AlvosInicializacao {
    $todos = @(Get-ItensInicializacao)
    $sel = @(); $naoEncontrados = @()
    foreach ($n in $Inicializacao) {
        $m = @($todos | Where-Object { $_.Ativo -and ($_.Nome -eq $n -or $_.Nome -like $n) })
        if ($m.Count -eq 0) { $naoEncontrados += $n } else { $sel += $m }
    }
    return [pscustomobject]@{ Itens = @($sel | Sort-Object Origem, Nome, Comando -Unique); NaoEncontrados = $naoEncontrados }
}
function Previa-DesativarInicializacao {
    if ($Inicializacao.Count -eq 0) { return @('Informe os itens: -Inicializacao "Nome1","Nome2" (nomes da seção Inicialização do diagnóstico).') }
    $r = Get-AlvosInicializacao
    $l = @()
    foreach ($a in $r.Itens) {
        $aviso = if ($a.Classificacao -eq 'Essencial') { '   <-- ESSENCIAL: será IGNORADO (segurança/driver)' } else { '' }
        $adm = if ($a.Admin) { ', requer admin' } else { '' }
        $l += "$($a.Nome) [$($a.Origem), $($a.Escopo)$adm] - $($a.Classificacao): $($a.Motivo)$aviso"
    }
    foreach ($n in $r.NaoEncontrados) { $l += "Não encontrado ou já desativado: $n" }
    return $l + 'Os programas continuam instalados; só deixam de abrir sozinhos. Reversível (Gerenciador de Tarefas > Inicializar, ou Desfazer.ps1).'
}
function Aplicar-DesativarInicializacao { param($Bk)
    $pend = New-Object System.Collections.Generic.List[string]
    foreach ($a in (Get-AlvosInicializacao).Itens) {
        if ($a.Classificacao -eq 'Essencial') { Write-Host "   RECUSADO (essencial: $($a.Motivo)): $($a.Nome)"; continue }
        if ($a.Admin -and -not $ehAdmin) { $pend.Add($a.Nome); Write-Host "   (requer admin, pendente) $($a.Nome)"; continue }
        if ($SomenteAdmin -and -not $a.Admin) { continue }
        try {
            switch ($a.Origem) {
                'App da Loja' { Set-RegistroComBackup -Backup $Bk -Chave $a.ChaveApp -Nome 'State' -Valor 1 -Tipo DWord -Descricao "Inicialização: $($a.Nome)" }
                'Tarefa agendada' {
                    Disable-ScheduledTask -TaskPath $a.TarefaCaminho -TaskName $a.Nome -ErrorAction Stop | Out-Null
                    Add-BackupEntrada $Bk @{ Tipo = 'Tarefa'; Descricao = "Inicialização: $($a.Nome)"; Caminho = $a.TarefaCaminho; Nome = $a.Nome; Admin = [bool]$a.Admin }
                }
                default {
                    $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime())
                    $val = [byte[]](@([byte]3, [byte]0, [byte]0, [byte]0) + $ft)
                    Set-RegistroComBackup -Backup $Bk -Chave $a.ChaveAprov -Nome $a.NomeAprov -Valor $val -Tipo Binary -Descricao "Inicialização: $($a.Nome)"
                }
            }
            Write-Host "   OK: $($a.Nome) não abrirá mais com o Windows."
        } catch { Write-Host "   ERRO em $($a.Nome): $($_.Exception.Message)" }
    }
    return , $pend.ToArray()
}

function Get-AlvosServicos {
    $out = @()
    foreach ($n in $Servicos) {
        $c = $Script:CatalogoServicos | Where-Object { $_.Nome -ieq $n } | Select-Object -First 1
        if (-not $c) { $out += [pscustomobject]@{ Nome = $n; Erro = 'Fora do catálogo seguro - não será alterado' }; continue }
        $s = Get-CimInstance Win32_Service -Filter "Name='$($c.Nome)'" -ErrorAction SilentlyContinue
        if (-not $s) { $out += [pscustomobject]@{ Nome = $n; Erro = 'Serviço não existe neste PC' }; continue }
        $out += [pscustomobject]@{ Nome = $c.Nome; Exibicao = $c.Exibicao; Atual = $s.StartMode; Estado = $s.State; Recomendado = $c.Recomendado; Risco = $c.Risco; Motivo = $c.Motivo; Erro = '' }
    }
    return $out
}
function Previa-DesativarServicos {
    if ($Servicos.Count -eq 0) { return @('Informe os serviços: -Servicos "DiagTrack","MapsBroker" (somente os do catálogo, conforme o diagnóstico).') }
    $l = @()
    foreach ($a in (Get-AlvosServicos)) {
        if ($a.Erro) { $l += "$($a.Nome): $($a.Erro)"; continue }
        $novo = if ($a.Recomendado -eq 'Disabled') { 'Desativado' } else { 'Manual (inicia só quando necessário)' }
        $l += "$($a.Exibicao) [$($a.Nome)]: $($a.Atual)/$($a.Estado) -> $novo | risco $($a.Risco) | $($a.Motivo)"
    }
    return $l + 'Backup do tipo de inicialização anterior é gravado (Desfazer.ps1 restaura).'
}
function Aplicar-DesativarServicos { param($Bk)
    foreach ($a in (Get-AlvosServicos)) {
        if ($a.Erro) { Write-Host "   Ignorado $($a.Nome): $($a.Erro)"; continue }
        try {
            $chave = "HKLM:\SYSTEM\CurrentControlSet\Services\$($a.Nome)"
            Add-BackupEntrada $Bk @{ Tipo = 'Servico'; Descricao = "Serviço $($a.Exibicao)"; Nome = $a.Nome; Start = (Get-ValorRegistro $chave 'Start'); Delayed = (Get-ValorRegistro $chave 'DelayedAutostart'); Admin = $true }
            $modo = if ($a.Recomendado -eq 'Disabled') { 'disabled' } else { 'demand' }
            $o = & sc.exe config $a.Nome 'start=' $modo 2>&1
            if ($LASTEXITCODE -ne 0) { throw "sc.exe: $($o -join ' ')" }
            if ($a.Recomendado -eq 'Disabled' -and $a.Estado -eq 'Running') { Stop-Service -Name $a.Nome -Force -ErrorAction SilentlyContinue }
            Write-Host "   OK: $($a.Exibicao) -> $modo"
        } catch { Write-Host "   ERRO em $($a.Nome): $($_.Exception.Message)" }
    }
}

function Previa-DesativarAppsSegundoPlano {
    if ($ehWin11) { return @('No Windows 11 não existe chave global: ajuste por app em Configurações > Aplicativos > (app) > Opções avançadas. Nada a fazer aqui.') }
    return @('Impede apps da Microsoft Store (Clima, Notícias, Mapas...) de rodarem escondidos.', 'Apps de mensagem da Loja podem atrasar notificações. Programas tradicionais (Chrome, Discord...) não são afetados.')
}
function Aplicar-DesativarAppsSegundoPlano { param($Bk)
    if ($ehWin11) { Write-Host '   Windows 11: ajuste manual por app.'; return }
    Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Nome 'GlobalUserDisabled' -Valor 1 -Descricao 'Apps em segundo plano'
    Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Nome 'BackgroundAppGlobalToggle' -Valor 0 -Descricao 'Apps em segundo plano'
    Write-Host '   OK: apps da Loja não rodam mais em segundo plano.'
}

# ============================================================ APPS/RECURSOS ==
function Get-AlvosApps {
    $instalados = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    $out = @()
    foreach ($n in $Apps) {
        $m = @($instalados | Where-Object { $_.Name -like $n })
        if ($m.Count -eq 0) { $out += [pscustomobject]@{ Pacote = $n; Nome = ''; Completo = ''; Risco = ''; Erro = 'Não instalado' }; continue }
        foreach ($p in $m) {
            if ((Test-AppProtegido $p.Name) -or $p.NonRemovable -or $p.IsFramework) {
                $out += [pscustomobject]@{ Pacote = $p.Name; Nome = ''; Completo = ''; Risco = ''; Erro = 'Protegido (sistema/Loja/codec/framework) - não será removido' }; continue
            }
            $cat = $Script:CatalogoApps | Where-Object { $p.Name -like $_.Padrao } | Select-Object -First 1
            $out += [pscustomobject]@{ Pacote = $p.Name; Nome = $(if ($cat) { $cat.Nome } else { $p.Name }); Completo = $p.PackageFullName; Risco = $(if ($cat) { $cat.Risco } else { 'Avaliar' }); Erro = '' }
        }
    }
    return @($out | Sort-Object Pacote, Completo -Unique)
}
function Previa-RemoverApps {
    if ($Apps.Count -eq 0) { return @('Informe os pacotes: -Apps "Microsoft.BingNews","Microsoft.GetHelp" (nomes do diagnóstico).') }
    $l = @()
    foreach ($a in (Get-AlvosApps)) {
        if ($a.Erro) { $l += "$($a.Pacote): $($a.Erro)" } else { $l += "$($a.Nome) [$($a.Pacote)] - risco $($a.Risco)" }
    }
    return $l + 'Remoção só para o seu usuário. Reinstalável pela Microsoft Store.'
}
function Aplicar-RemoverApps { param($Bk)
    foreach ($a in (Get-AlvosApps)) {
        if ($a.Erro) { Write-Host "   Ignorado $($a.Pacote): $($a.Erro)"; continue }
        try {
            Remove-AppxPackage -Package $a.Completo -ErrorAction Stop
            Add-BackupEntrada $Bk @{ Tipo = 'Appx'; Descricao = "App removido: $($a.Nome)"; Nome = $a.Pacote; Admin = $false }
            Write-Host "   OK: removido $($a.Nome)"
        } catch { Write-Host "   ERRO em $($a.Pacote): $($_.Exception.Message)" }
    }
}

function Previa-DesativarRecursos {
    if ($Recursos.Count -eq 0) { return @('Informe os recursos: -Recursos "SMB1Protocol" (nomes do diagnóstico).') }
    $of = @(Get-CimInstance Win32_OptionalFeature -ErrorAction SilentlyContinue)
    $l = @()
    foreach ($n in $Recursos) {
        $c = $Script:CatalogoRecursos | Where-Object { $_.Nome -ieq $n } | Select-Object -First 1
        if (-not $c) { $l += "${n}: fora do catálogo - não será alterado"; continue }
        $f = $of | Where-Object { $_.Name -eq $c.Nome } | Select-Object -First 1
        $estado = if ($f -and [int]$f.InstallState -eq 1) { 'ATIVO' } else { 'já desativado' }
        $l += "$($c.Exibicao) [$($c.Nome)]: $estado | risco $($c.Risco) | $($c.Motivo)"
    }
    return $l + 'Requer reiniciar o PC para concluir. Desfazer: Enable-WindowsOptionalFeature.'
}
function Aplicar-DesativarRecursos { param($Bk)
    foreach ($n in $Recursos) {
        $c = $Script:CatalogoRecursos | Where-Object { $_.Nome -ieq $n } | Select-Object -First 1
        if (-not $c) { Write-Host "   Ignorado ${n}: fora do catálogo"; continue }
        try {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $c.Nome -ErrorAction Stop
            if ([string]$f.State -ne 'Enabled') { Write-Host "   $($c.Exibicao): já desativado."; continue }
            Add-BackupEntrada $Bk @{ Tipo = 'Recurso'; Descricao = "Recurso $($c.Exibicao)"; Nome = $c.Nome; Admin = $true }
            Disable-WindowsOptionalFeature -Online -FeatureName $c.Nome -NoRestart -ErrorAction Stop | Out-Null
            Write-Host "   OK: $($c.Exibicao) desativado (reinicie para concluir)."
        } catch { Write-Host "   ERRO em $($c.Nome): $($_.Exception.Message)" }
    }
}

# ============================================================ CONFIGURAÇÕES ==
function Previa-DesativarGameDVR { return @('Desliga a gravação contínua em segundo plano do Xbox Game Bar.', 'A Game Bar continua abrindo (Win + G) e você ainda pode gravar manualmente (Win + Alt + R).') }
function Aplicar-DesativarGameDVR { param($Bk)
    Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Nome 'HistoricalCaptureEnabled' -Valor 0 -Descricao 'Gravação em segundo plano'
    Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\System\GameConfigStore' -Nome 'GameDVR_Enabled' -Valor 0 -Descricao 'Game DVR'
    Write-Host '   OK: gravação em segundo plano desligada.'
}

$Script:ChavesSugestoes = @('SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'SubscribedContent-338388Enabled',
    'SubscribedContent-338389Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SubscribedContent-310093Enabled',
    'SubscribedContent-338393Enabled', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled')
function Previa-DesativarSugestoes { return @('Impede o Windows de instalar apps patrocinados sozinho (ex.: Candy Crush) e remove sugestões/dicas no Iniciar e nas Configurações.') }
function Aplicar-DesativarSugestoes { param($Bk)
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in $Script:ChavesSugestoes) { Set-RegistroComBackup -Backup $Bk -Chave $k -Nome $n -Valor 0 -Descricao 'Sugestões/apps patrocinados' }
    Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' -Nome 'ScoobeSystemSettingEnabled' -Valor 0 -Descricao 'Tela "vamos terminar de configurar"'
    Write-Host '   OK: sugestões e instalações automáticas bloqueadas.'
}

function Previa-DesativarNoticias {
    if ($ehWin11) { return @('Esconde o botão de Widgets da barra de tarefas (o painel deixa de carregar notícias).') }
    return @('Desativa "Notícias e Interesses" da barra de tarefas (deixa de carregar notícias/clima em segundo plano).')
}
function Aplicar-DesativarNoticias { param($Bk)
    if ($ehWin11) {
        try { Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Nome 'TaskbarDa' -Valor 0 -Descricao 'Widgets' }
        catch { throw 'O Windows bloqueou a alteração. Desative manualmente: Configurações > Personalização > Barra de tarefas > Widgets.' }
    } else {
        Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' -Nome 'ShellFeedsTaskbarViewMode' -Valor 2 -Descricao 'Notícias e Interesses'
    }
    Write-Host '   OK (aparece após reiniciar o Explorador ou sair e entrar na conta).'
}

function Previa-EfeitosVisuais { return @('Desliga transparência e animações de janelas/barra de tarefas. Fontes suaves e miniaturas continuam iguais.', 'Vale após sair e entrar na conta.') }
function Aplicar-EfeitosVisuais { param($Bk)
    Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Nome 'EnableTransparency' -Valor 0 -Descricao 'Transparência'
    Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Control Panel\Desktop\WindowMetrics' -Nome 'MinAnimate' -Valor '0' -Tipo String -Descricao 'Animação de janelas'
    Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Nome 'TaskbarAnimations' -Valor 0 -Descricao 'Animação da barra'
    Set-RegistroComBackup -Backup $Bk -Chave 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Nome 'VisualFXSetting' -Valor 3 -Descricao 'Efeitos personalizados'
    Write-Host '   OK: saia e entre na conta para ver o efeito.'
}

function Previa-PlanoEnergiaDesempenho {
    $atual = ((powercfg /getactivescheme) -join ' ')
    $l = @("Plano atual: $atual", 'Novo plano: Alto desempenho.')
    if ($notebook) { $l += 'ATENÇÃO: notebook - a bateria vai durar menos. Prefira usar só na tomada.' }
    return $l
}
function Aplicar-PlanoEnergiaDesempenho { param($Bk)
    $atual = ((powercfg /getactivescheme) -join ' ')
    $guidAtual = if ($atual -match $rxGuid) { $Matches[1] } else { '381b4222-f694-41f0-9685-ff5bb260df2e' }
    $alto = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    if (((powercfg /list) -join "`n") -notmatch $alto) {
        $dup = ((powercfg -duplicatescheme $alto) -join ' ')
        if ($dup -match $rxGuid) { $alto = $Matches[1] } else { throw 'Plano Alto desempenho indisponível neste PC (Modern Standby).' }
    }
    Add-BackupEntrada $Bk @{ Tipo = 'Comando'; Descricao = 'Plano de energia anterior'; Desfazer = "powercfg /setactive $guidAtual"; Admin = $false }
    & powercfg.exe /setactive $alto
    Write-Host '   OK: plano Alto desempenho ativo.'
}

# ================================================================ DISCOS ==
function Previa-AtivarTRIM {
    $t = ((fsutil behavior query DisableDeleteNotify 2>$null) -join ' ')
    return @("Estado atual: $t", 'Define DisableDeleteNotify = 0 (TRIM ligado), o padrão do Windows para SSD.')
}
function Aplicar-AtivarTRIM { param($Bk)
    Add-BackupEntrada $Bk @{ Tipo = 'Comando'; Descricao = 'TRIM anterior'; Desfazer = 'fsutil behavior set DisableDeleteNotify 1'; Admin = $true }
    $o = & fsutil.exe behavior set DisableDeleteNotify 0 2>&1
    if ($LASTEXITCODE -ne 0) { throw "fsutil: $o" }
    Write-Host '   OK: TRIM ativado.'
}

function Previa-ReativarOtimizacaoAgendada {
    $t = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction SilentlyContinue
    return @("Tarefa ScheduledDefrag: $(if ($t) { $t.State } else { 'não encontrada' })", 'Reativa a otimização semanal (TRIM em SSD, desfragmentação em HD).')
}
function Aplicar-ReativarOtimizacaoAgendada { param($Bk)
    Enable-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction Stop | Out-Null
    Add-BackupEntrada $Bk @{ Tipo = 'Comando'; Descricao = 'Otimização agendada'; Desfazer = 'schtasks /Change /TN "\Microsoft\Windows\Defrag\ScheduledDefrag" /Disable'; Admin = $true }
    Write-Host '   OK: otimização semanal reativada.'
}

function Get-VolumesParaOtimizar {
    $out = @()
    foreach ($p in (Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })) {
        $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { [string]$_.DeviceId -eq [string]$p.DiskNumber } | Select-Object -First 1
        if (-not $pd -or [string]$pd.BusType -in @('USB', 'SD', 'MMC')) { continue }
        $tipo = switch ([string]$pd.MediaType) { 'SSD' { 'SSD' } 'HDD' { 'HD' } default { if ([string]$pd.BusType -eq 'NVMe') { 'SSD' } else { 'Desconhecido' } } }
        $out += [pscustomobject]@{ Letra = [string]$p.DriveLetter; Tipo = $tipo }
    }
    return $out
}
function Previa-OtimizarUnidades {
    $l = @()
    foreach ($v in (Get-VolumesParaOtimizar)) { $l += "$($v.Letra): ($($v.Tipo)) -> $(if ($v.Tipo -eq 'HD') { 'desfragmentar (pode levar bastante tempo)' } else { 'TRIM (rápido)' })" }
    return $l + 'Nunca desfragmenta SSD. O Windows já faz isso semanalmente se a tarefa estiver ativa.'
}
function Aplicar-OtimizarUnidades { param($Bk)
    foreach ($v in (Get-VolumesParaOtimizar)) {
        try {
            if ($v.Tipo -eq 'HD') { Optimize-Volume -DriveLetter $v.Letra -Defrag -ErrorAction Stop } else { Optimize-Volume -DriveLetter $v.Letra -ReTrim -ErrorAction Stop }
            Write-Host "   OK: $($v.Letra): otimizada."
        } catch { Write-Host "   ERRO em $($v.Letra): $($_.Exception.Message)" }
    }
}

# ================================================================ EXECUÇÃO ==
$titulo = if ($Executar) { 'OTIMIZAÇÃO - EXECUÇÃO' } else { 'OTIMIZAÇÃO - PRÉVIA (nada será alterado)' }
if ($SomenteAdmin) { $titulo += ' [janela de administrador]' }
Write-Titulo $titulo
Write-Host "Administrador: $(if ($ehAdmin) { 'sim' } else { 'não' }) | Windows $(if ($ehWin11) { '11' } else { '10' }) | $(if ($notebook) { 'notebook' } else { 'desktop' })"

foreach ($id in $sel) {
    $def = $Definicoes[$id]
    Write-Secao "$($def.Nome)  [$id | risco $($def.Risco) | admin: $($def.Admin)]"
    try { foreach ($linha in (& "Previa-$id")) { Write-Host " $linha" } } catch { Write-Host " (prévia indisponível: $($_.Exception.Message))" }
}

if (-not $Executar) {
    Write-Host ''
    $adm = @($sel | Where-Object { $Definicoes[$_].Admin -ne 'Não' })
    if ($adm.Count -and -not $ehAdmin) { Write-Host "Ações que pedem administrador: $($adm -join ', ') -> na execução, use -Elevar (abre o UAC)." }
    Write-Host 'Para executar após aprovação do usuário, repita com -Executar.'
    exit 0
}

$bk = New-Backup $(if ($SomenteAdmin) { 'otimizacao-admin' } else { 'otimizacao' })
$pendAcoes = @(); $pendInic = @(); $resultados = @()

$temAdminAgora = $ehAdmin -and [bool]($sel | Where-Object { $Definicoes[$_].Admin -ne 'Não' })
if ($temAdminAgora -and -not $SemPontoRestauracao) {
    try {
        # O Windows só permite 1 ponto a cada 24 h e avisa por WARNING (não erro) - capturar para relatar a verdade.
        $avisosRP = $null
        Checkpoint-Computer -Description 'OtimizadorPC - antes das otimizacoes' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable avisosRP
        if ($avisosRP) { Write-Host 'Ponto de restauração NÃO criado: o Windows só permite um a cada 24 h e já existe um recente (ele continua valendo). O backup próprio da skill também foi gravado.' }
        else { Write-Host 'Ponto de restauração do Windows criado.' }
    } catch { Write-Host "Aviso: ponto de restauração não criado ($($_.Exception.Message)). O backup próprio da skill continua valendo." }
}

foreach ($id in $sel) {
    $def = $Definicoes[$id]
    if ($def.Admin -eq 'Sim' -and -not $ehAdmin) { $pendAcoes += $id; $resultados += [pscustomobject]@{ Acao = $id; Resultado = 'Pendente (requer admin)' }; continue }
    if ($SomenteAdmin -and $def.Admin -eq 'Não') { continue }
    Write-Secao "Aplicando: $($def.Nome)"
    try {
        $ret = & "Aplicar-$id" -Bk $bk
        $res = 'OK'
        if ($id -eq 'DesativarInicializacao' -and @($ret).Count -gt 0 -and -not $ehAdmin) { $pendInic += @($ret); $pendAcoes += $id; $res = "OK (parcial: $(@($ret).Count) item(ns) pedem admin)" }
        $resultados += [pscustomobject]@{ Acao = $id; Resultado = $res }
    } catch {
        Write-Host "   ERRO: $($_.Exception.Message)"
        $resultados += [pscustomobject]@{ Acao = $id; Resultado = "Erro: $($_.Exception.Message)" }
    }
}

Write-Secao 'Resumo'
Write-Tabela $resultados @('Acao', 'Resultado')
if (Test-Path -LiteralPath $bk.Arquivo) {
    Write-Host "Backup do estado anterior: $($bk.Arquivo)"
    Write-Host "Para desfazer: Desfazer.ps1 -Backup '$($bk.Arquivo)'"
}
$reiniciar = @($sel | Where-Object { $_ -in @('DesativarRecursos', 'DesativarServicos', 'EfeitosVisuais', 'DesativarNoticias') })
if ($reiniciar.Count) { Write-Host 'Algumas mudanças só valem totalmente após reiniciar o PC (ou sair e entrar na conta).' }

$pendAcoes = @($pendAcoes | Sort-Object -Unique)
if ($pendAcoes.Count -and -not $ehAdmin) {
    if ($Elevar) {
        $params = @{ Acoes = $pendAcoes; Executar = $true; SomenteAdmin = $true; SemPontoRestauracao = [bool]$SemPontoRestauracao }
        if ($Servicos.Count) { $params.Servicos = $Servicos }
        if ($pendInic.Count) { $params.Inicializacao = $pendInic }
        if ($Recursos.Count) { $params.Recursos = $Recursos }
        $null = Invoke-ComoAdmin -Script $PSCommandPath -Parametros $params
    } else {
        Write-Host ''
        Write-Host "Pendentes por exigir administrador: $($pendAcoes -join ', ')"
        Write-Host 'Para concluí-las (com aprovação do usuário), repita o mesmo comando com -Elevar.'
    }
}
