# ai-cli-statusline installer for Windows (PowerShell)
#
#   irm https://raw.githubusercontent.com/GenSSK/ai-cli-statusline/main/install.ps1 | iex
#
# Claude Code on Windows runs status line commands through Git Bash,
# so this finds Git Bash, makes sure jq is available, and runs install.sh.

$ErrorActionPreference = 'Stop'
$RepoRaw = 'https://raw.githubusercontent.com/GenSSK/ai-cli-statusline/main'

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---------- Git Bash ----------
# Do not use `bash` from PATH: on Windows it may be WSL's bash.exe.
$bash = $null
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
    $candidate = Join-Path $gitRoot 'bin\bash.exe'
    if (Test-Path $candidate) { $bash = $candidate }
}
if (-not $bash) {
    foreach ($p in @("$env:ProgramFiles\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
        if (Test-Path $p) { $bash = $p; break }
    }
}
if (-not $bash) {
    Write-Host 'Git for Windows (Git Bash) was not found.' -ForegroundColor Red
    Write-Host 'Install it first:  winget install Git.Git   (or https://git-scm.com/download/win)'
    return
}
Write-Host "==> Git Bash: $bash"

# ---------- jq ----------
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host '==> Installing jq with winget...'
        winget install --id jqlang.jq -e --accept-source-agreements --accept-package-agreements | Out-Host
        Refresh-Path
    }
    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Host 'jq is required. Install it with:  winget install jqlang.jq' -ForegroundColor Red
        Write-Host 'Then open a new terminal and run this installer again.'
        return
    }
}
Write-Host '==> jq: found'

# ---------- Run install.sh in Git Bash ----------
$tmp = Join-Path $env:TEMP 'ai-cli-statusline-install.sh'
Invoke-WebRequest -UseBasicParsing "$RepoRaw/install.sh" -OutFile $tmp
& $bash $tmp.Replace('\', '/') @args
Remove-Item $tmp -ErrorAction SilentlyContinue
