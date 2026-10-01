<#
Verificação REAL (Win32) da política de tamanho da janela do InvTec
Windows. Testes de widget não enxergam a restrição do runner
(`windows/runner/main.cpp` + WM_GETMINMAXINFO em `win32_window.cpp`); este
script abre o executável de verdade e a exercita. Só lê/redimensiona a
janela: nenhuma escrita em banco, nenhum login.

Uso (depois de `flutter build windows --debug`):
  powershell -ExecutionPolicy Bypass -File tool\verificar_janela_windows.ps1
Sai com código 1 se qualquer verificação falhar.
#>
param(
  [string]$Exe = "build\windows\x64\runner\Debug\invtec.exe",
  [int]$MinLargura = 1280,   # área cliente mínima, pixels lógicos
  [int]$MinAltura = 720,
  [int]$InicialLargura = 1440,
  [int]$InicialAltura = 810
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
}
"@

$exePath = Resolve-Path $Exe
$p = Start-Process $exePath -PassThru
$falhas = @()
try {
  $h = [IntPtr]::Zero
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500; $p.Refresh()
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break }
  }
  if ($h -eq [IntPtr]::Zero) { throw "A janela do InvTec não apareceu." }
  Start-Sleep -Seconds 2

  function Cliente {
    $r = New-Object W+RECT; [void][W]::GetClientRect($h, [ref]$r)
    $dpi = [W]::GetDpiForWindow($h)
    if ($dpi -eq 0) { $dpi = 96 }
    $escala = $dpi / 96.0
    Write-Verbose "raw R=$($r.R) B=$($r.B) dpi=$dpi"
    return ,@([int][math]::Round($r.R / $escala), [int][math]::Round($r.B / $escala))
  }
  function Verifica($nome, $ok, $detalhe) {
    $marca = if ($ok) { "OK  " } else { "FALHA" }
    Write-Output ("[{0}] {1} — {2}" -f $marca, $nome, $detalhe)
    if (-not $ok) { $script:falhas += $nome }
  }

  $c = Cliente
  Verifica "tamanho inicial" ($c[0] -ge $MinLargura -and $c[1] -ge $MinAltura) "cliente $($c[0])x$($c[1]) (esperado ${InicialLargura}x${InicialAltura}, limitado à área útil do monitor)"

  [void][W]::SetWindowPos($h, [IntPtr]::Zero, 50, 50, 400, 300, 0x0004); Start-Sleep -Milliseconds 800
  $c = Cliente
  Verifica "reduzir abaixo do mínimo (400x300)" ($c[0] -ge $MinLargura -and $c[1] -ge $MinAltura) "cliente $($c[0])x$($c[1]) (mínimo ${MinLargura}x${MinAltura})"

  [void][W]::SetWindowPos($h, [IntPtr]::Zero, 50, 50, 1600, 950, 0x0004); Start-Sleep -Milliseconds 800
  $c = Cliente
  Verifica "ampliar livremente" ($c[0] -gt $MinLargura -and $c[1] -gt $MinAltura) "cliente $($c[0])x$($c[1])"

  [void][W]::ShowWindow($h, 3); Start-Sleep -Milliseconds 800
  Verifica "maximizar (não é fullscreen)" ([W]::IsZoomed($h)) "IsZoomed=$([W]::IsZoomed($h)) cliente $((Cliente) -join 'x')"

  [void][W]::ShowWindow($h, 9); Start-Sleep -Milliseconds 800
  $c = Cliente
  Verifica "restaurar" (-not [W]::IsZoomed($h) -and $c[0] -ge $MinLargura) "IsZoomed=$([W]::IsZoomed($h)) cliente $($c[0])x$($c[1])"

  [void][W]::SetWindowPos($h, [IntPtr]::Zero, 50, 50, 300, 200, 0x0004); Start-Sleep -Milliseconds 800
  $c = Cliente
  Verifica "reduzir de novo após restaurar (300x200)" ($c[0] -ge $MinLargura -and $c[1] -ge $MinAltura) "cliente $($c[0])x$($c[1])"
}
finally {
  if (-not $p.HasExited) { Stop-Process $p -Force }
}
if ($falhas.Count -gt 0) { Write-Output "FALHAS: $($falhas -join '; ')"; exit 1 }
Write-Output "Todas as verificações passaram."
