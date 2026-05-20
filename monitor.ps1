# monitor.ps1 - Auditoria de Processos (Eventos Reais + Histórico)
$logFile = "execution_log.txt"

function Log-Message {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] $Message"
    Write-Host $entry -ForegroundColor Cyan
    $entry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Write-Host "--- MONITOR DE SISTEMA GLOBAL (POWERED BY WMI) ---" -ForegroundColor Green
Write-Host "Logando em: $(Get-Item $logFile).FullName"
Write-Host "Pressione CTRL+C para encerrar.`n"

# PASSO 1: Pegar o passado recente (Últimos 2 minutos do Log de Eventos se disponível)
Write-Host "[*] Verificando histórico recente no Agendador de Tarefas..." -ForegroundColor Yellow
try {
    $events = Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -MaxEvents 10 -ErrorAction SilentlyContinue | Where-Object { $_.TimeCreated -gt (Get-Date).AddMinutes(-2) }
    foreach ($e in $events) {
        Log-Message "HISTÓRICO: Evento $($e.Id) às $($e.TimeCreated): $($e.Message)"
    }
}
catch {
    Write-Host "[!] Não foi possível ler logs históricos (requer privilégios extras)."
}

# PASSO 2: Monitoramento em Tempo Real (Eventos CIM)
Write-Host "`n[*] Monitoramento em tempo real iniciado. Aguardando execuções..." -ForegroundColor Yellow
Log-Message "Iniciando captura de eventos de sistema."

# Usamos um loop de alta frequência com detecção de novos processos para garantir captura de curta duração
$seen = @{}
Get-CimInstance Win32_Process | ForEach-Object { if ($_.ProcessId) { $seen[$_.ProcessId] = $true } }

while ($true) {
    # Intervalo de 200ms para pegar processos extremamente rápidos
    Start-Sleep -Milliseconds 200
    
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        $id = $p.ProcessId
        if (-not $id) { continue }
        
        if (-not $seen.ContainsKey($id)) {
            $seen[$id] = $true
            
            $ppid = $p.ParentProcessId
            $parent = $procs | Where-Object { $_.ProcessId -eq $ppid }
            $parentName = if ($parent) { if ($parent.Count -gt 1) { $parent[0].Name } else { $parent.Name } } else { "Desconhecido/Encerrado" }
            
            $cmd = if ($p.CommandLine) { $p.CommandLine } else { "N/A (Executável sem argumentos)" }
            
            Log-Message "NOVO PROCESSO: $($p.Name) (PID: $id) | PAI: $parentName (PPID: $ppid)"
            Log-Message "   CMD: $cmd"
            Write-Host ("-" * 60)
        }
    }
}
