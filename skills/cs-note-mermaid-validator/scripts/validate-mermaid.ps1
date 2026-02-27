[CmdletBinding()]
param(
    [Parameter()]
    [string]$Root = ".",

    [Parameter()]
    [switch]$AutoFix,

    [Parameter()]
    [string]$JsonOut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$issues = New-Object System.Collections.Generic.List[object]
$knownStarters = @(
    "flowchart", "graph", "sequenceDiagram", "classDiagram", "stateDiagram",
    "stateDiagram-v2", "erDiagram", "journey", "gantt", "pie", "mindmap",
    "timeline", "quadrantChart", "requirementDiagram", "gitGraph",
    "C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment",
    "sankey-beta", "xychart-beta", "block-beta", "packet-beta"
)

function Add-Issue {
    param(
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Rule,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$BlockStart,
        [Parameter(Mandatory = $true)][int]$Line,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $issues.Add([pscustomobject]@{
            severity   = $Severity
            rule       = $Rule
            path       = $Path
            blockStart = $BlockStart
            line       = $Line
            message    = $Message
        }) | Out-Null
}

function Get-BracketImbalance {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][char]$OpenChar,
        [Parameter(Mandatory = $true)][char]$CloseChar
    )

    $balance = 0
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq $OpenChar) {
            $balance++
            continue
        }
        if ($ch -eq $CloseChar) {
            $balance--
        }
    }
    return $balance
}

function Validate-MermaidBlock {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$BlockLines,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][int]$BlockStartLine
    )

    $fixedLines = [System.Collections.Generic.List[string]]::new()
    $changed = $false

    foreach ($line in $BlockLines) {
        $newLine = $line
        if ($newLine -match "`t") {
            Add-Issue -Severity "WARN" -Rule "mermaid.tab" -Path $FilePath -BlockStart $BlockStartLine -Line ($BlockStartLine + $fixedLines.Count + 1) -Message "Tab character found in Mermaid block."
            if ($AutoFix) {
                $newLine = $newLine -replace "`t", "  "
            }
        }

        $trimmedRight = $newLine.TrimEnd()
        if ($trimmedRight.Length -ne $newLine.Length) {
            if ($AutoFix) {
                $newLine = $trimmedRight
            }
            else {
                Add-Issue -Severity "INFO" -Rule "mermaid.trailing-space" -Path $FilePath -BlockStart $BlockStartLine -Line ($BlockStartLine + $fixedLines.Count + 1) -Message "Trailing whitespace found."
            }
        }

        if ($newLine -ne $line) {
            $changed = $true
        }

        $fixedLines.Add($newLine) | Out-Null
    }

    $firstNonEmptyIndex = -1
    for ($i = 0; $i -lt $fixedLines.Count; $i++) {
        if ($fixedLines[$i].Trim().Length -gt 0) {
            $firstNonEmptyIndex = $i
            break
        }
    }

    if ($firstNonEmptyIndex -lt 0) {
        Add-Issue -Severity "ERROR" -Rule "mermaid.empty" -Path $FilePath -BlockStart $BlockStartLine -Line $BlockStartLine -Message "Empty Mermaid block."
        return @{
            lines   = $fixedLines
            changed = $changed
        }
    }

    $firstLine = $fixedLines[$firstNonEmptyIndex].Trim()
    $firstToken = ($firstLine -split '\s+')[0]
    if ($knownStarters -notcontains $firstToken) {
        Add-Issue -Severity "ERROR" -Rule "mermaid.starter" -Path $FilePath -BlockStart $BlockStartLine -Line ($BlockStartLine + $firstNonEmptyIndex + 1) -Message "Unknown Mermaid starter token '$firstToken'."
    }

    $fullText = ($fixedLines -join "`n")
    if ((Get-BracketImbalance -Text $fullText -OpenChar '(' -CloseChar ')') -ne 0) {
        Add-Issue -Severity "WARN" -Rule "mermaid.bracket-round" -Path $FilePath -BlockStart $BlockStartLine -Line $BlockStartLine -Message "Possible imbalance in round brackets."
    }
    if ((Get-BracketImbalance -Text $fullText -OpenChar '[' -CloseChar ']') -ne 0) {
        Add-Issue -Severity "WARN" -Rule "mermaid.bracket-square" -Path $FilePath -BlockStart $BlockStartLine -Line $BlockStartLine -Message "Possible imbalance in square brackets."
    }
    if ((Get-BracketImbalance -Text $fullText -OpenChar '{' -CloseChar '}') -ne 0) {
        Add-Issue -Severity "WARN" -Rule "mermaid.bracket-curly" -Path $FilePath -BlockStart $BlockStartLine -Line $BlockStartLine -Message "Possible imbalance in curly braces."
    }

    $quoteCount = ([regex]::Matches($fullText, '(?<!\\)"')).Count
    if (($quoteCount % 2) -ne 0) {
        Add-Issue -Severity "WARN" -Rule "mermaid.quote" -Path $FilePath -BlockStart $BlockStartLine -Line $BlockStartLine -Message "Odd count of unescaped double quotes."
    }

    $subgraphCount = ([regex]::Matches($fullText, '(?m)^\s*subgraph\b')).Count
    $endCount = ([regex]::Matches($fullText, '(?m)^\s*end\s*$')).Count
    if ($subgraphCount -ne $endCount) {
        Add-Issue -Severity "WARN" -Rule "mermaid.subgraph-balance" -Path $FilePath -BlockStart $BlockStartLine -Line $BlockStartLine -Message "subgraph count ($subgraphCount) does not match end count ($endCount)."
    }

    return @{
        lines   = $fixedLines
        changed = $changed
    }
}

$rootPath = (Resolve-Path -Path $Root).Path
$files = Get-ChildItem -Path $rootPath -Recurse -File -Filter *.md |
Where-Object { $_.FullName -notmatch '[\\/](skills|\.git)[\\/]' }

foreach ($file in $files) {
    $raw = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $lineEnding = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n", -1

    $outputLines = [System.Collections.Generic.List[string]]::new()
    $inMermaid = $false
    $blockLines = [System.Collections.Generic.List[string]]::new()
    $blockStartLine = 0
    $changedFile = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNumber = $i + 1

        if (-not $inMermaid) {
            if ($line -match '^\s*```mermaid\s*$') {
                $inMermaid = $true
                $blockStartLine = $lineNumber
                $blockLines.Clear()
                $outputLines.Add($line) | Out-Null
            }
            else {
                $outputLines.Add($line) | Out-Null
            }
            continue
        }

        if ($line -match '^\s*```\s*$') {
            $validation = Validate-MermaidBlock -BlockLines $blockLines.ToArray() -FilePath $file.FullName -BlockStartLine $blockStartLine
            foreach ($validatedLine in $validation.lines) {
                $outputLines.Add($validatedLine) | Out-Null
            }
            $outputLines.Add($line) | Out-Null
            if ($validation.changed) {
                $changedFile = $true
            }
            $inMermaid = $false
            continue
        }

        $blockLines.Add($line) | Out-Null
    }

    if ($inMermaid) {
        Add-Issue -Severity "ERROR" -Rule "mermaid.fence-unclosed" -Path $file.FullName -BlockStart $blockStartLine -Line $blockStartLine -Message "Mermaid fence is not closed."
        foreach ($remaining in $blockLines) {
            $outputLines.Add($remaining) | Out-Null
        }
    }

    if ($AutoFix -and $changedFile) {
        $newContent = [string]::Join($lineEnding, $outputLines)
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
    }, path, blockStart, line

foreach ($issue in $orderedIssues) {
    Write-Output ("[{0}] {1} {2}:{3}:{4} - {5}" -f $issue.severity, $issue.rule, $issue.path, $issue.blockStart, $issue.line, $issue.message)
}

$errorCount = @($issues | Where-Object { $_.severity -eq "ERROR" }).Count
$warnCount = @($issues | Where-Object { $_.severity -eq "WARN" }).Count
$infoCount = @($issues | Where-Object { $_.severity -eq "INFO" }).Count
Write-Output ("Summary: ERROR={0}, WARN={1}, INFO={2}" -f $errorCount, $warnCount, $infoCount)

if ($JsonOut) {
    $jsonPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $JsonOut))
    $orderedIssues | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-Output "JSON report: $jsonPath"
}

if ($errorCount -gt 0) {
    exit 2
}

if ($issues.Count -gt 0) {
    exit 1
}

Write-Output "No Mermaid issues found."
exit 0
