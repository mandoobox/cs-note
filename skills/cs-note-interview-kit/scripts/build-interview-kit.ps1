[CmdletBinding()]
param(
    [Parameter()]
    [string]$Root = ".",

    [Parameter()]
    [string[]]$Topics = @(),

    [Parameter()]
    [ValidateRange(1, 10)]
    [int]$QuestionsPerSection = 3,

    [Parameter()]
    [ValidateRange(1, 50)]
    [int]$MaxSectionsPerFile = 12,

    [Parameter()]
    [string]$Output = "interview-kit.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SectionBlocks {
    param(
        [Parameter(Mandatory = $true)][string]$Content
    )

    $matches = [regex]::Matches($Content, '(?m)^##\s+(?<title>.+)$')
    $sections = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $matches.Count; $i++) {
        $current = $matches[$i]
        $start = $current.Index + $current.Length
        $end = if ($i -lt $matches.Count - 1) { $matches[$i + 1].Index } else { $Content.Length }
        $length = [Math]::Max(0, $end - $start)
        $body = if ($length -gt 0) { $Content.Substring($start, $length).Trim() } else { "" }

        $sections.Add([pscustomobject]@{
                title = $current.Groups["title"].Value.Trim()
                body  = $body
            }) | Out-Null
    }

    return $sections
}

function Get-SectionSummary {
    param(
        [Parameter(Mandatory = $true)][string]$Body
    )

    $lines = $Body -split "`r?`n"
    $clean = $lines |
    Where-Object {
        $_.Trim().Length -gt 0 -and
        $_ -notmatch '^\s*```' -and
        $_ -notmatch '^\s*\|' -and
        $_ -notmatch '^\s*[-*]\s*$'
    } |
    Select-Object -First 3

    $summary = ($clean -join " ").Trim()
    if ($summary.Length -gt 220) {
        return ($summary.Substring(0, 220) + "...")
    }
    return $summary
}

function New-QuestionTemplates {
    return @(
        @{
            type       = "concept"
            difficulty = "medium"
            prompt     = "Explain the core idea of '{0}' in {1}, then state one practical implementation constraint."
            followUp   = "If the chosen approach fails under high scale, what exact metric fails first and why?"
        },
        @{
            type       = "tradeoff"
            difficulty = "medium-hard"
            prompt     = "Compare '{0}' with its nearest alternative in {1}. Describe decision criteria with one concrete example."
            followUp   = "What hidden cost is usually missed during the first design review?"
        },
        @{
            type       = "scenario"
            difficulty = "hard"
            prompt     = "Given a production incident related to '{0}' in {1}, outline a triage-first response plan."
            followUp   = "Which observation would make you change the initial hypothesis immediately?"
        },
        @{
            type       = "recall"
            difficulty = "easy-medium"
            prompt     = "List the minimum key points an interviewer expects for '{0}' in under 60 seconds."
            followUp   = "Which one point is most frequently confused, and how do you disambiguate it quickly?"
        }
    )
}

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    try {
        return [System.IO.Path]::GetRelativePath($BasePath, $TargetPath)
    }
    catch {
        $baseResolved = (Resolve-Path -Path $BasePath).Path.TrimEnd('\') + '\'
        $targetResolved = (Resolve-Path -Path $TargetPath).Path
        $baseUri = New-Object System.Uri($baseResolved)
        $targetUri = New-Object System.Uri($targetResolved)
        return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', '\')
    }
}

$rootPath = (Resolve-Path -Path $Root).Path
$files = Get-ChildItem -Path $rootPath -Recurse -File -Filter *.md |
Where-Object {
    $_.FullName -notmatch '[\\/](skills|\.git)[\\/]' -and
    $_.Name -ne "README.md"
}

if ($Topics.Count -gt 0) {
    $topicSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($topic in $Topics) {
        if ([string]::IsNullOrWhiteSpace($topic)) {
            continue
        }

        $parts = $topic -split ","
        foreach ($part in $parts) {
            if (-not [string]::IsNullOrWhiteSpace($part)) {
                [void]$topicSet.Add($part.Trim())
            }
        }
    }
    $files = $files | Where-Object { $topicSet.Contains($_.BaseName) }
}

if (-not $files -or $files.Count -eq 0) {
    throw "No matching markdown files found."
}

$templates = New-QuestionTemplates
$packs = New-Object System.Collections.Generic.List[object]
$totalQuestions = 0

foreach ($file in ($files | Sort-Object FullName)) {
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $sections = Get-SectionBlocks -Content $content | Select-Object -First $MaxSectionsPerFile
    $relativePath = Get-RelativePathCompat -BasePath $rootPath -TargetPath $file.FullName

    foreach ($section in $sections) {
        $summary = Get-SectionSummary -Body $section.body
        if ([string]::IsNullOrWhiteSpace($summary)) {
            $summary = "Read the section directly and extract key definitions, tradeoffs, and failure modes."
        }

        $questionItems = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $QuestionsPerSection; $i++) {
            $template = $templates[$i % $templates.Count]
            $prompt = [string]::Format($template.prompt, $section.title, $file.BaseName)
            $followUp = [string]::Format($template.followUp, $section.title, $file.BaseName)

            $questionItems.Add([pscustomobject]@{
                    question_type = $template.type
                    difficulty    = $template.difficulty
                    prompt        = $prompt
                    follow_up     = $followUp
                    rubric        = @(
                        "State the correct core concept with precise terminology.",
                        "Explain tradeoffs or limits instead of listing features only.",
                        "Use one concrete example or metric to justify claims.",
                        "Communicate with short structure: claim -> reason -> example."
                    )
                }) | Out-Null
            $totalQuestions++
        }

        $packs.Add([pscustomobject]@{
                topic          = $file.BaseName
                section        = $section.title
                section_digest = $summary
                source         = $relativePath
                questions      = $questionItems
            }) | Out-Null
    }
}

$result = [pscustomobject]@{
    generated_at        = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    root                = $rootPath
    files               = ($files | ForEach-Object { Get-RelativePathCompat -BasePath $rootPath -TargetPath $_.FullName })
    questions_per_entry = $QuestionsPerSection
    total_entries       = $packs.Count
    total_questions     = $totalQuestions
    entries             = $packs
}

$jsonText = $result | ConvertTo-Json -Depth 8
$outputPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $Output))
Set-Content -Path $outputPath -Value $jsonText -Encoding UTF8

Write-Output ("Generated interview kit: {0}" -f $outputPath)
Write-Output ("Entries: {0}, Questions: {1}" -f $packs.Count, $totalQuestions)
