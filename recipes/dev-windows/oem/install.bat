@echo off
REM dev-windows first-boot provisioning. dockur runs C:\OEM\install.bat once,
REM after Windows setup completes. EXPERIMENTAL — verify on a live node.
REM
REM Installs the dev toolchain entry points (mise + git) and best-effort enables
REM OpenSSH Server so VS Code Remote-SSH / rsync can reach the guest. Language
REM toolchains themselves come from each project's mise.toml on first `mise run`.
REM Your repo arrives via \\host.lan\Data (the devwin_shared volume).

echo [dev-windows] provisioning...

REM --- git + mise via winget (Windows Package Manager) -----------------------
where winget >nul 2>&1
if %ERRORLEVEL%==0 (
  echo [dev-windows] installing git + mise via winget
  winget install --id Git.Git           -e --silent --accept-source-agreements --accept-package-agreements
  winget install --id jdx.mise          -e --silent --accept-source-agreements --accept-package-agreements
) else (
  echo [dev-windows] winget not available yet — install git + mise manually, or re-run this script later
)

REM --- OpenSSH Server (best-effort) -----------------------------------------
echo [dev-windows] enabling OpenSSH Server
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue;" ^
  "Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue;" ^
  "Start-Service sshd -ErrorAction SilentlyContinue;" ^
  "if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 }"

REM --- authorize the developer's key, if delivered via the shared folder ------
REM Drop your public key at \\host.lan\Data\dev\authorized_keys (host side: the
REM devwin_shared volume) and it becomes the admin authorized_keys here.
if exist "\\host.lan\Data\dev\authorized_keys" (
  echo [dev-windows] installing administrators_authorized_keys from \\host.lan\Data\dev
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$dst = \"$env:ProgramData\ssh\administrators_authorized_keys\";" ^
    "Copy-Item -Force '\\host.lan\Data\dev\authorized_keys' $dst;" ^
    "icacls $dst /inheritance:r /grant 'Administrators:F' 'SYSTEM:F' | Out-Null"
) else (
  echo [dev-windows] no \\host.lan\Data\dev\authorized_keys — set one to enable Remote-SSH, then restart sshd
)

echo [dev-windows] done. RDP in (Docker/admin); repo goes in \\host.lan\Data; build with `mise run build`.
