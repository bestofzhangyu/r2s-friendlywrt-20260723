' WSL2 + Ubuntu Installer for NanoPi R2S Build Environment
' Double-click to run - will auto-request admin privileges via UAC

Set objShell = CreateObject("Shell.Application")
objShell.ShellExecute "cmd.exe", _
    "/c " & _
    "echo ============================================ && " & _
    "echo  Installing WSL2 + Ubuntu for R2S Build && " & _
    "echo ============================================ && " & _
    "echo. && " & _
    "echo [1/2] Installing WSL2 platform and kernel... && " & _
    "wsl --install --no-distribution && " & _
    "echo. && " & _
    "echo [2/2] Installing Ubuntu distro (no-launch)... && " & _
    "wsl --install -d Ubuntu --no-launch && " & _
    "echo. && " & _
    "echo ============================================ && " & _
    "echo  Done! If reboot is needed, reboot now. && " & _
    "echo  Then open Ubuntu from Start Menu, set username. && " & _
    "echo  Come back to WorkBuddy when ready. && " & _
    "echo ============================================ && " & _
    "echo. && " & _
    "pause", _
    "", "runas", 1
