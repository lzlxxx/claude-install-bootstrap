Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ClaudeInstallBeginMarker = '# >>> Claude Install Bootstrap >>>'
$script:ClaudeInstallEndMarker = '# <<< Claude Install Bootstrap <<<'
$script:MinimumPowerShellVersion = [System.Management.Automation.SemanticVersion]'7.6.0-rc.1'
$script:PowerShellInstallCommand = 'winget install --id Microsoft.PowerShell.Preview --source winget'
$script:ClaudeCliInstallCommand = 'irm https://claude.ai/install.ps1 | iex'
$script:DefaultManagedBlockUrl = 'https://raw.githubusercontent.com/lzlxxx/claude-install-bootstrap/main/claude-install.txt'

function Test-ClaudeInstallPrerequisites {
    param(
        [System.Management.Automation.SemanticVersion]$CurrentPowerShellVersion = $PSVersionTable.PSVersion,
        [AllowNull()]
        [object]$ClaudeCommand = (Get-Command claude -ErrorAction SilentlyContinue)
    )

    if ($CurrentPowerShellVersion -lt $script:MinimumPowerShellVersion) {
        throw "需要 PowerShell 7.6.0-rc.1 或更高版本。当前版本：$CurrentPowerShellVersion。请先执行：$($script:PowerShellInstallCommand)"
    }

    if ($null -eq $ClaudeCommand) {
        throw "未检测到 claude CLI。请先安装后重试：$($script:ClaudeCliInstallCommand)"
    }

    return [pscustomobject]@{
        PowerShellVersion = $CurrentPowerShellVersion
        ClaudeCommandPath = $ClaudeCommand.Source
    }
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
        [System.Management.Automation.SemanticVersion]$CurrentPowerShellVersion = $PSVersionTable.PSVersion,
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
