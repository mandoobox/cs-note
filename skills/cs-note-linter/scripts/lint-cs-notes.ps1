[CmdletBinding()]
param(
    [Parameter()]
    [string]$Root = ".",

    [Parameter()]
    [switch]$Fix,

    [Parameter()]
    [string]$JsonOut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$issues = New-Object System.Collections.Generic.List[object]

function Add-Issue {
    param(
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Rule,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$Line,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $issues.Add([pscustomobject]@{
            severity = $Severity
            rule     = $Rule
            path     = $Path
            line     = $Line
            message  = $Message
        }) | Out-Null
}

function Get-LineNumberFromIndex {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$Index
    )

    if ($Index -le 0) {
        return 1
    }

    return ([regex]::Matches($Content.Substring(0, $Index), "`n")).Count + 1
}

function Resolve-LocalLink {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$LinkTarget
    )

    $target = $LinkTarget.Split("#")[0].Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
        return $null
    }

    if ($target -match '^(https?:|mailto:|obsidian:|#)') {
        return $null
    }

    $baseDir = Split-Path -Parent $FilePath
    return [System.IO.Path]::GetFullPath((Join-Path $baseDir $target))
}

$rootPath = (Resolve-Path -Path $Root).Path
$files = Get-ChildItem -Path $rootPath -Recurse -File -Filter *.md |
Where-Object { $_.FullName -notmatch '[\\/](skills|\.git)[\\/]' }

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $lineEnding = if ($content -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $content -split "`r?`n", -1
    $changed = $false

    $hasFrontMatter = $lines.Count -gt 0 -and $lines[0].Trim() -eq "---"
    $frontMatterEnd = -1

    if ($hasFrontMatter) {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq "---") {
                $frontMatterEnd = $i
                break
            }
        }

        if ($frontMatterEnd -lt 0) {
            Add-Issue -Severity "ERROR" -Rule "frontmatter.unclosed" -Path $file.FullName -Line 1 -Message "Frontmatter starts but does not close with '---'."
        }
        else {
            $frontMatterLines = @()
            if ($frontMatterEnd -gt 1) {
                $frontMatterLines = $lines[1..($frontMatterEnd - 1)]
            }

            foreach ($requiredField in @("title", "date", "category", "tags")) {
                $requiredPattern = '^\s*' + [regex]::Escape($requiredField) + '\s*:'
                $hasField = $false
                foreach ($fmLine in $frontMatterLines) {
                    if ($fmLine -match $requiredPattern) {
                        $hasField = $true
                        break
                    }
                }
                if (-not $hasField) {
                    Add-Issue -Severity "WARN" -Rule "frontmatter.required" -Path $file.FullName -Line 1 -Message "Missing '$requiredField' in frontmatter."
                }
            }

            for ($i = 1; $i -lt $frontMatterEnd; $i++) {
                if ($lines[$i] -match '^\s*tags\s*:\s*\[(?<tags>.+)\]\s*$') {
                    if ($Matches.tags -match '\bdatsstructure\b') {
                        Add-Issue -Severity "WARN" -Rule "tags.typo" -Path $file.FullName -Line ($i + 1) -Message "Found 'datsstructure'. Replace with 'datastructure'."
                        if ($Fix) {
                            $newTagLine = $lines[$i] -replace '\bdatsstructure\b', 'datastructure'
                            if ($newTagLine -ne $lines[$i]) {
                                $lines[$i] = $newTagLine
                                $changed = $true
                            }
                        }
                    }
                }
            }
        }
    }
    elseif ($file.Name -ne "README.md") {
        Add-Issue -Severity "WARN" -Rule "frontmatter.missing" -Path $file.FullName -Line 1 -Message "Missing frontmatter block."
    }

    $linkPattern = '\[[^\]]+\]\((?<target>[^)]+)\)'
    $linkMatches = [regex]::Matches($content, $linkPattern)
    foreach ($linkMatch in $linkMatches) {
        $target = $linkMatch.Groups["target"].Value.Trim()
        if ($target -match '^(https?:|mailto:|obsidian:|#)') {
            continue
        }

        $resolvedTarget = Resolve-LocalLink -FilePath $file.FullName -LinkTarget $target
        if ($null -eq $resolvedTarget) {
            continue
        }

        if (-not (Test-Path -LiteralPath $resolvedTarget)) {
            $lineNumber = Get-LineNumberFromIndex -Content $content -Index $linkMatch.Index
            Add-Issue -Severity "WARN" -Rule "link.missing" -Path $file.FullName -Line $lineNumber -Message "Missing local target: $target"
        }
    }

    $h2Numbered = [regex]::Matches($content, '(?m)^##\s+(?<num>\d+)\.')
    if ($h2Numbered.Count -gt 0) {
        for ($i = 0; $i -lt $h2Numbered.Count; $i++) {
            $expected = $i + 1
            $actual = [int]$h2Numbered[$i].Groups["num"].Value
            if ($actual -ne $expected) {
                $lineNumber = Get-LineNumberFromIndex -Content $content -Index $h2Numbered[$i].Index
                Add-Issue -Severity "WARN" -Rule "heading.h2-numbering" -Path $file.FullName -Line $lineNumber -Message "Expected section number $expected but found $actual."
                break
            }
        }
    }

    if ($content.Contains([char]0xFFFD)) {
        $badIndex = $content.IndexOf([char]0xFFFD)
        $lineNumber = Get-LineNumberFromIndex -Content $content -Index $badIndex
        Add-Issue -Severity "WARN" -Rule "text.mojibake" -Path $file.FullName -Line $lineNumber -Message "Found replacement character U+FFFD."
    }

    if ($content -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') {
        Add-Issue -Severity "ERROR" -Rule "text.control-char" -Path $file.FullName -Line 1 -Message "Found non-whitespace control character."
    }

    if ($Fix -and $changed) {
        $newContent = [string]::Join($lineEnding, $lines)
        Set-Content -Path $file.FullName -Value $newContent -Encoding UTF8
    }
}

$orderedIssues = $issues | Sort-Object @{
        Expression = {
            switch ($_.severity) {
                "ERROR" { 0 }
                "WARN" { 1 }
                default { 2 }
            }
        }
    }, path, line

foreach ($issue in $orderedIssues) {
    Write-Output ("[{0}] {1} {2}:{3} - {4}" -f $issue.severity, $issue.rule, $issue.path, $issue.line, $issue.message)
}

$errorCount = @($issues | Where-Object { $_.severity -eq "ERROR" }).Count
$warnCount = @($issues | Where-Object { $_.severity -eq "WARN" }).Count
$infoCount = @($issues | Where-Object { $_.severity -eq "INFO" }).Count
Write-Output ("Summary: ERROR={0}, WARN={1}, INFO={2}" -f $errorCount, $warnCount, $infoCount)

if ($JsonOut) {
    $jsonPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $JsonOut))
    $orderedIssues | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-Output "JSON report: $jsonPath"
}

if ($errorCount -gt 0) {
    exit 2
}

if ($issues.Count -gt 0) {
    exit 1
}

Write-Output "No issues found."
exit 0
