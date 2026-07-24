$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('JellyfinVlcBridge.UiNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace JellyfinVlcBridge
{
    public static class UiNative
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetProcessDPIAware();

        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(
            IntPtr hwnd,
            int attribute,
            ref int value,
            int valueSize);
    }
}
'@
}

$script:JvbPalette = @{
    Window       = [Drawing.Color]::FromArgb(9, 15, 25)
    Header       = [Drawing.Color]::FromArgb(12, 25, 41)
    Surface      = [Drawing.Color]::FromArgb(18, 31, 49)
    SurfaceAlt   = [Drawing.Color]::FromArgb(24, 41, 62)
    Border       = [Drawing.Color]::FromArgb(43, 64, 87)
    Accent       = [Drawing.Color]::FromArgb(13, 160, 211)
    AccentHover  = [Drawing.Color]::FromArgb(30, 181, 231)
    Success      = [Drawing.Color]::FromArgb(42, 190, 125)
    SuccessHover = [Drawing.Color]::FromArgb(55, 207, 140)
    Warning      = [Drawing.Color]::FromArgb(244, 171, 63)
    Danger       = [Drawing.Color]::FromArgb(241, 91, 91)
    Text         = [Drawing.Color]::FromArgb(242, 247, 252)
    TextMuted    = [Drawing.Color]::FromArgb(161, 177, 196)
    TextFaint    = [Drawing.Color]::FromArgb(112, 133, 157)
}

$script:JvbFontFamily = if (
    [Drawing.FontFamily]::Families.Name -contains 'Segoe UI Variable Text'
) { 'Segoe UI Variable Text' } else { 'Segoe UI' }

function New-JvbFont(
    [single]$size = 9.5,
    [Drawing.FontStyle]$style = [Drawing.FontStyle]::Regular
) {
    return New-Object Drawing.Font($script:JvbFontFamily, $size, $style)
}

function Initialize-JvbWindowsIdentity {
    try { [void][JellyfinVlcBridge.UiNative]::SetProcessDPIAware() } catch { }
    try {
        [void][JellyfinVlcBridge.UiNative]::SetCurrentProcessExplicitAppUserModelID(
            'CrySer66.JellyfinVlcBridge')
    } catch { }
}

function Get-JvbApplicationIcon([string[]]$candidatePaths) {
    foreach ($candidate in $candidatePaths) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate)) {
            continue
        }
        try {
            $icon = [Drawing.Icon]::ExtractAssociatedIcon($candidate)
            if ($icon) { return $icon }
        } catch { }
    }
    return $null
}

function Set-JvbRoundedRegion(
    [Windows.Forms.Control]$control,
    [int]$radius = 14
) {
    if ($control.Width -le 0 -or $control.Height -le 0) { return }
    $diameter = [Math]::Max(2, $radius * 2)
    $bounds = New-Object Drawing.Rectangle(0, 0, $control.Width, $control.Height)
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc($bounds.Left, $bounds.Top, $diameter, $diameter, 180, 90)
    $path.AddArc($bounds.Right - $diameter, $bounds.Top, $diameter, $diameter, 270, 90)
    $path.AddArc(
        $bounds.Right - $diameter,
        $bounds.Bottom - $diameter,
        $diameter,
        $diameter,
        0,
        90)
    $path.AddArc($bounds.Left, $bounds.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    $oldRegion = $control.Region
    $control.Region = New-Object Drawing.Region($path)
    if ($oldRegion) { $oldRegion.Dispose() }
    $path.Dispose()
}

function Enable-JvbRoundedControl(
    [Windows.Forms.Control]$control,
    [int]$radius = 14
) {
    Set-JvbRoundedRegion $control $radius
    $control.Add_Resize({ Set-JvbRoundedRegion $this $radius }.GetNewClosure())
}

function Enable-JvbModernWindow(
    [Windows.Forms.Form]$form,
    [Drawing.Icon]$icon = $null
) {
    $form.BackColor = $script:JvbPalette.Window
    $form.ForeColor = $script:JvbPalette.Text
    $form.Font = New-JvbFont 9.5
    $form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
    $form.ShowIcon = $true
    if ($icon) { $form.Icon = $icon }
    $form.Add_Shown({
        try {
            $enabled = 1
            $darkModeResult = [JellyfinVlcBridge.UiNative]::DwmSetWindowAttribute(
                $this.Handle, 20, [ref]$enabled, 4)
            if ($darkModeResult -ne 0) {
                [void][JellyfinVlcBridge.UiNative]::DwmSetWindowAttribute(
                    $this.Handle, 19, [ref]$enabled, 4)
            }
            $rounded = 2
            [void][JellyfinVlcBridge.UiNative]::DwmSetWindowAttribute(
                $this.Handle, 33, [ref]$rounded, 4)
        } catch { }
    })
}

function New-JvbCard(
    [Windows.Forms.Control]$parent,
    [int]$x,
    [int]$y,
    [int]$width,
    [int]$height,
    [Drawing.Color]$backColor = $script:JvbPalette.Surface,
    [int]$radius = 16
) {
    $panel = New-Object Windows.Forms.Panel
    $panel.Location = New-Object Drawing.Point($x, $y)
    $panel.Size = New-Object Drawing.Size($width, $height)
    $panel.BackColor = $backColor
    $panel.ForeColor = $script:JvbPalette.Text
    $panel.Add_Paint({
        param($sender, $eventArgs)
        $pen = New-Object Drawing.Pen($script:JvbPalette.Border, 1)
        try {
            $eventArgs.Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $eventArgs.Graphics.DrawRectangle(
                $pen, 0, 0, [Math]::Max(0, $sender.Width - 1), [Math]::Max(0, $sender.Height - 1))
        } finally {
            $pen.Dispose()
        }
    })
    Enable-JvbRoundedControl $panel $radius
    $parent.Controls.Add($panel)
    return $panel
}

function Set-JvbButtonStyle(
    [Windows.Forms.Button]$button,
    [ValidateSet('Primary', 'Success', 'Secondary', 'Danger', 'Ghost')]
    [string]$variant = 'Secondary'
) {
    $normal = $script:JvbPalette.SurfaceAlt
    $hover = [Drawing.Color]::FromArgb(34, 54, 78)
    $text = $script:JvbPalette.Text
    $border = $script:JvbPalette.Border
    switch ($variant) {
        'Primary' {
            $normal = $script:JvbPalette.Accent
            $hover = $script:JvbPalette.AccentHover
            $border = $script:JvbPalette.Accent
        }
        'Success' {
            $normal = $script:JvbPalette.Success
            $hover = $script:JvbPalette.SuccessHover
            $border = $script:JvbPalette.Success
        }
        'Danger' {
            $normal = $script:JvbPalette.Danger
            $hover = [Drawing.Color]::FromArgb(255, 111, 111)
            $border = $script:JvbPalette.Danger
        }
        'Ghost' {
            $normal = $script:JvbPalette.Surface
            $hover = $script:JvbPalette.SurfaceAlt
        }
    }
    $button.BackColor = $normal
    $button.ForeColor = $text
    $button.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = $border
    $button.FlatAppearance.MouseOverBackColor = $hover
    $button.FlatAppearance.MouseDownBackColor = $hover
    $button.Cursor = [Windows.Forms.Cursors]::Hand
    $button.Font = New-JvbFont 9.5 ([Drawing.FontStyle]::Bold)
    $button.UseVisualStyleBackColor = $false
    Enable-JvbRoundedControl $button 8
}

function Set-JvbInputStyle([Windows.Forms.TextBox]$textBox) {
    $textBox.BackColor = $script:JvbPalette.SurfaceAlt
    $textBox.ForeColor = $script:JvbPalette.Text
    $textBox.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $textBox.Font = New-JvbFont 10
}

function Set-JvbComboStyle([Windows.Forms.ComboBox]$comboBox) {
    $comboBox.BackColor = $script:JvbPalette.SurfaceAlt
    $comboBox.ForeColor = $script:JvbPalette.Text
    $comboBox.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $comboBox.Font = New-JvbFont 10
}

function New-JvbLabel(
    [Windows.Forms.Control]$parent,
    [string]$text,
    [int]$x,
    [int]$y,
    [int]$width,
    [int]$height,
    [single]$fontSize = 9.5,
    [Drawing.FontStyle]$fontStyle = [Drawing.FontStyle]::Regular,
    [Drawing.Color]$color = $script:JvbPalette.Text,
    [string]$name = ''
) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object Drawing.Point($x, $y)
    $label.Size = New-Object Drawing.Size($width, $height)
    $label.Font = New-JvbFont $fontSize $fontStyle
    $label.ForeColor = $color
    $label.BackColor = [Drawing.Color]::Transparent
    if ($name) { $label.Name = $name }
    $parent.Controls.Add($label)
    return $label
}

function New-JvbDot(
    [Windows.Forms.Control]$parent,
    [int]$x,
    [int]$y,
    [Drawing.Color]$color
) {
    $dot = New-Object Windows.Forms.Panel
    $dot.Location = New-Object Drawing.Point($x, $y)
    $dot.Size = New-Object Drawing.Size(10, 10)
    $dot.BackColor = $color
    Enable-JvbRoundedControl $dot 5
    $parent.Controls.Add($dot)
    return $dot
}

function Show-JvbMessageDialog(
    [string]$title,
    [string]$message,
    [ValidateSet('Info', 'Success', 'Warning', 'Error')]
    [string]$kind = 'Info',
    [Drawing.Icon]$applicationIcon = $null,
    [string]$closeText = 'OK'
) {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $title
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object Drawing.Size(560, 320)
    $dialog.FormBorderStyle = 'FixedSingle'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    Enable-JvbModernWindow $dialog $applicationIcon

    $statusColor = switch ($kind) {
        'Success' { $script:JvbPalette.Success }
        'Warning' { $script:JvbPalette.Warning }
        'Error' { $script:JvbPalette.Danger }
        default { $script:JvbPalette.Accent }
    }
    $card = New-JvbCard $dialog 28 28 504 206
    [void](New-JvbDot $card 24 27 $statusColor)
    [void](New-JvbLabel $card $title 50 15 422 36 15 ([Drawing.FontStyle]::Bold))
    [void](New-JvbLabel $card $message 24 67 456 116 10 `
        ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted)

    $closeButton = New-Object Windows.Forms.Button
    $closeButton.Text = $closeText
    $closeButton.Location = New-Object Drawing.Point(372, 254)
    $closeButton.Size = New-Object Drawing.Size(160, 42)
    Set-JvbButtonStyle $closeButton $(if ($kind -eq 'Error') { 'Danger' } else { 'Primary' })
    $closeButton.Add_Click({ $dialog.Close() })
    $dialog.Controls.Add($closeButton)
    [void]$dialog.ShowDialog()
}

function Show-JvbConfirmDialog(
    [string]$title,
    [string]$message,
    [Drawing.Icon]$applicationIcon = $null,
    [string]$confirmText = 'Continue',
    [string]$cancelText = 'Cancel'
) {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $title
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object Drawing.Size(580, 330)
    $dialog.FormBorderStyle = 'FixedSingle'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    Enable-JvbModernWindow $dialog $applicationIcon

    $card = New-JvbCard $dialog 28 28 524 210
    [void](New-JvbDot $card 24 27 $script:JvbPalette.Warning)
    [void](New-JvbLabel $card $title 50 15 444 36 15 ([Drawing.FontStyle]::Bold))
    [void](New-JvbLabel $card $message 24 67 476 120 10 `
        ([Drawing.FontStyle]::Regular) $script:JvbPalette.TextMuted)

    $cancelButton = New-Object Windows.Forms.Button
    $cancelButton.Text = $cancelText
    $cancelButton.Location = New-Object Drawing.Point(222, 258)
    $cancelButton.Size = New-Object Drawing.Size(150, 42)
    Set-JvbButtonStyle $cancelButton 'Secondary'
    $dialog.Controls.Add($cancelButton)

    $confirmButton = New-Object Windows.Forms.Button
    $confirmButton.Text = $confirmText
    $confirmButton.Location = New-Object Drawing.Point(386, 258)
    $confirmButton.Size = New-Object Drawing.Size(166, 42)
    Set-JvbButtonStyle $confirmButton 'Primary'
    $dialog.Controls.Add($confirmButton)

    $script:JvbDialogConfirmed = $false
    $cancelButton.Add_Click({ $dialog.Close() })
    $confirmButton.Add_Click({
        $script:JvbDialogConfirmed = $true
        $dialog.Close()
    })
    [void]$dialog.ShowDialog()
    return $script:JvbDialogConfirmed
}

Initialize-JvbWindowsIdentity
