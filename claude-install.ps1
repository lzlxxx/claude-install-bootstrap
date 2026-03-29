Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ClaudeInstallBeginMarker = '# >>> Claude Install Bootstrap >>>'
$script:ClaudeInstallEndMarker = '# <<< Claude Install Bootstrap <<<'
$script:MinimumPowerShellVersion = '7.6.0-rc.1'
$script:RecommendedPowerShellVersion = '7.6.0'
$script:BootstrapInstallCommand = 'irm https://raw.githubusercontent.com/lzlxxx/claude-install-bootstrap/main/claude-install.ps1 | iex'
$script:PowerShellInstallCommand = @'
$msi = "$env:TEMP\PowerShell-7.6.0-win-x64.msi"
Invoke-WebRequest https://github.com/PowerShell/PowerShell/releases/download/v7.6.0/PowerShell-7.6.0-win-x64.msi -OutFile $msi
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$msi`" /passive"
'@.Trim()
$script:ClaudeCliInstallCommand = 'irm https://claude.ai/install.ps1 | iex'
$script:DefaultManagedBlockUrl = 'https://raw.githubusercontent.com/<github-user>/claude-install-bootstrap/main/claude-install.txt'

function New-ClaudeInstallUpgradeMessage {
    param([AllowNull()][object]$CurrentPowerShellVersion)

    $shellName = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'Windows PowerShell' } else { 'PowerShell' }
    $stepTwo = if ($shellName -eq 'Windows PowerShell') {
        "步骤 2：安装完成后打开 pwsh`n不要继续在当前 powershell.exe / Windows PowerShell 窗口中执行下面的命令。"
    }
    else {
        '步骤 2：安装完成后重新打开 pwsh'
    }

    return @(
        "当前是在 $shellName 中运行，版本：$CurrentPowerShellVersion。"
        '此环境不能直接继续执行安装流程，请按以下步骤操作：'
        ''
        "步骤 1：安装 PowerShell $($script:RecommendedPowerShellVersion) 或更高版本"
        '以下命令只用于安装 PowerShell，不要和后续命令一起复制：'
        $script:PowerShellInstallCommand
        ''
        $stepTwo
        ''
        '步骤 3：在 pwsh 中重新执行安装命令'
        $script:BootstrapInstallCommand
    ) -join [Environment]::NewLine
}

function New-ClaudeInstallMissingCliMessage {
    return @(
        '未检测到 claude CLI。'
        '请在 pwsh 中按以下步骤执行：'
        ''
        '步骤 1：安装 Claude CLI'
        $script:ClaudeCliInstallCommand
        ''
        '步骤 2：安装完成后，在 pwsh 中重新执行安装命令'
        $script:BootstrapInstallCommand
    ) -join [Environment]::NewLine
}

function Test-ClaudeInstallPrerequisites {
    param(
        [AllowNull()]
        [object]$CurrentPowerShellVersion = $PSVersionTable.PSVersion,
        [AllowNull()]
        [object]$ClaudeCommand = (Get-Command claude -ErrorAction SilentlyContinue)
    )

    if ((Compare-ClaudeInstallVersion -LeftVersion $CurrentPowerShellVersion -RightVersion $script:MinimumPowerShellVersion) -lt 0) {
        throw (New-ClaudeInstallUpgradeMessage -CurrentPowerShellVersion $CurrentPowerShellVersion)
    }

    if ($null -eq $ClaudeCommand) {
        throw (New-ClaudeInstallMissingCliMessage)
    }

    return [pscustomobject]@{
        PowerShellVersion = [string]$CurrentPowerShellVersion
        ClaudeCommandPath = $ClaudeCommand.Source
    }
}

function ConvertTo-ClaudeInstallVersionInfo {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Version
    )

    $versionText = if ($null -eq $Version) { '' } else { [string]$Version }
    if ([string]::IsNullOrWhiteSpace($versionText)) {
        throw '版本号不能为空。'
    }

    $match = [regex]::Match(
        $versionText.Trim(),
        '^(?<numbers>\d+(?:\.\d+)*)(?:-(?<pre>[0-9A-Za-z.-]+))?$'
    )
    if (-not $match.Success) {
        throw "无法解析版本号：$versionText"
    }

    return [pscustomobject]@{
        Numbers    = @($match.Groups['numbers'].Value.Split('.') | ForEach-Object { [long]$_ })
        PreRelease = $match.Groups['pre'].Value
    }
}

function Compare-ClaudeInstallPreRelease {
    param(
        [string]$LeftPreRelease,
        [string]$RightPreRelease
    )

    if ([string]::IsNullOrWhiteSpace($LeftPreRelease) -and [string]::IsNullOrWhiteSpace($RightPreRelease)) { return 0 }
    if ([string]::IsNullOrWhiteSpace($LeftPreRelease)) { return 1 }
    if ([string]::IsNullOrWhiteSpace($RightPreRelease)) { return -1 }

    $leftParts = $LeftPreRelease.Split('.')
    $rightParts = $RightPreRelease.Split('.')
    for ($index = 0; $index -lt [Math]::Max($leftParts.Count, $rightParts.Count); $index++) {
        if ($index -ge $leftParts.Count) { return -1 }
        if ($index -ge $rightParts.Count) { return 1 }
        $leftPart = $leftParts[$index]
        $rightPart = $rightParts[$index]
        $leftIsNumber = $leftPart -match '^\d+$'
        $rightIsNumber = $rightPart -match '^\d+$'
        if ($leftIsNumber -and $rightIsNumber) {
            if ([long]$leftPart -lt [long]$rightPart) { return -1 }
            if ([long]$leftPart -gt [long]$rightPart) { return 1 }
            continue
        }
        if ($leftIsNumber) { return -1 }
        if ($rightIsNumber) { return 1 }
        $comparison = [string]::CompareOrdinal($leftPart, $rightPart)
        if ($comparison -lt 0) { return -1 }
        if ($comparison -gt 0) { return 1 }
    }

    return 0
}

function Compare-ClaudeInstallVersion {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$LeftVersion,
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$RightVersion
    )

    $leftInfo = ConvertTo-ClaudeInstallVersionInfo -Version $LeftVersion
    $rightInfo = ConvertTo-ClaudeInstallVersionInfo -Version $RightVersion
    for ($index = 0; $index -lt [Math]::Max($leftInfo.Numbers.Count, $rightInfo.Numbers.Count); $index++) {
        $leftNumber = if ($index -lt $leftInfo.Numbers.Count) { $leftInfo.Numbers[$index] } else { 0 }
        $rightNumber = if ($index -lt $rightInfo.Numbers.Count) { $rightInfo.Numbers[$index] } else { 0 }
        if ($leftNumber -lt $rightNumber) { return -1 }
        if ($leftNumber -gt $rightNumber) { return 1 }
    }

    return Compare-ClaudeInstallPreRelease -LeftPreRelease $leftInfo.PreRelease -RightPreRelease $rightInfo.PreRelease
}

function Get-ClaudeInstallManagedBlockContent {
    param(
        [AllowEmptyString()]
        [string]$ManagedBlockContent,
        [string]$ManagedBlockPath,
        [string]$ManagedBlockUrl = $script:DefaultManagedBlockUrl
    )

    if (-not [string]::IsNullOrWhiteSpace($ManagedBlockContent)) {
        return $ManagedBlockContent.Trim()
    }

    $candidatePaths = @()
    if (-not [string]::IsNullOrWhiteSpace($ManagedBlockPath)) {
        $candidatePaths += $ManagedBlockPath
    }

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $candidatePaths += (Join-Path $PSScriptRoot 'claude-install.txt')
        $candidatePaths += (Join-Path $PSScriptRoot 'cladue-install.txt')
        $candidatePaths += (Join-Path $PSScriptRoot 'xxx.txt')
    }

    foreach ($path in $candidatePaths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            return (Get-Content -Path $path -Raw -Encoding UTF8).Trim()
        }
    }

    return ((Invoke-RestMethod -Uri $ManagedBlockUrl -ErrorAction Stop) | Out-String).Trim()
}

function New-ClaudeInstallManagedSection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManagedBlockContent
    )

    $newline = [Environment]::NewLine
    return $script:ClaudeInstallBeginMarker + $newline +
        $ManagedBlockContent.Trim() + $newline +
        $script:ClaudeInstallEndMarker + $newline
}

function Update-ClaudeInstallProfileBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath,
        [Parameter(Mandatory = $true)]
        [string]$ManagedBlockContent
    )

    $profileDir = Split-Path -Path $ProfilePath -Parent
    if (-not [string]::IsNullOrWhiteSpace($profileDir) -and -not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    $existingContent = if (Test-Path $ProfilePath) {
        Get-Content -Path $ProfilePath -Raw -Encoding UTF8
    }
    else {
        ""
    }

    $managedSection = New-ClaudeInstallManagedSection -ManagedBlockContent $ManagedBlockContent
    $pattern = '(?s)' +
        [regex]::Escape($script:ClaudeInstallBeginMarker) +
        '.*?' +
        [regex]::Escape($script:ClaudeInstallEndMarker) +
        '(\r?\n)?'

    if ($existingContent -match $pattern) {
        $updatedContent = [regex]::Replace($existingContent, $pattern, $managedSection, 1)
    }
    else {
        $separator = if ([string]::IsNullOrWhiteSpace($existingContent)) {
            ''
        }
        elseif ($existingContent.EndsWith("`r`n")) {
            "`r`n"
        }
        elseif ($existingContent.EndsWith("`n")) {
            "`n"
        }
        else {
            [Environment]::NewLine + [Environment]::NewLine
        }
        $updatedContent = $existingContent + $separator + $managedSection
    }

    [System.IO.File]::WriteAllText(
        $ProfilePath,
        $updatedContent,
        [System.Text.UTF8Encoding]::new($false)
    )

    return $updatedContent
}

function Import-ClaudeInstallManagedBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManagedBlockContent
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $ManagedBlockContent,
        [ref]$tokens,
        [ref]$errors
    )

    if (@($errors).Count -gt 0) {
        throw "托管命令块解析失败：$($errors[0].Message)"
    }

    $functions = $ast.FindAll(
        { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    )

    foreach ($functionAst in $functions) {
        $definition = $functionAst.Extent.Text -replace '^function\s+', 'function global:'
        Invoke-Expression $definition
    }
}

function Invoke-ClaudeInstallBootstrap {
    param(
        [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost,
        [AllowEmptyString()]
        [string]$ManagedBlockContent,
        [string]$ManagedBlockPath,
        [string]$ManagedBlockUrl = $script:DefaultManagedBlockUrl,
        [AllowNull()]
        [object]$CurrentPowerShellVersion = $PSVersionTable.PSVersion,
        [AllowNull()]
        [object]$ClaudeCommand = (Get-Command claude -ErrorAction SilentlyContinue)
    )

    $null = Test-ClaudeInstallPrerequisites `
        -CurrentPowerShellVersion $CurrentPowerShellVersion `
        -ClaudeCommand $ClaudeCommand

    $resolvedManagedBlockContent = Get-ClaudeInstallManagedBlockContent `
        -ManagedBlockContent $ManagedBlockContent `
        -ManagedBlockPath $ManagedBlockPath `
        -ManagedBlockUrl $ManagedBlockUrl

    $null = Update-ClaudeInstallProfileBlock `
        -ProfilePath $ProfilePath `
        -ManagedBlockContent $resolvedManagedBlockContent

    Import-ClaudeInstallManagedBlock -ManagedBlockContent $resolvedManagedBlockContent
    Write-Host "✓ 已更新 PowerShell profile：$ProfilePath" -ForegroundColor Green

    $settingsFiles = Get-ChildItem "$HOME\.claude\settings-*.json" -ErrorAction SilentlyContinue
    if ($settingsFiles) {
        claude-sync
    }
    else {
        Write-Host "未检测到 ~/.claude/settings-*.json，已仅安装管理命令；后续同步配置后运行 claude-sync。" -ForegroundColor Yellow
    }
}

if ($env:CLAUDE_INSTALL_BOOTSTRAP_NO_AUTO_RUN -ne '1') {
    Invoke-ClaudeInstallBootstrap
}
