# ==========================================
# Manga Tail Check Debug Script
# ==========================================
#
# Purpose:
# - Reuse the latest manga-series summary
# - Avoid repeating the main 1-10 page search
# - Check only volumes after the current maximum
# - Use a maximum of two additional SearchItems requests
#
# This script is for tail verification only.
# It does not modify the main application.
# ==========================================


# ==========================================
# Project paths
# ==========================================

$projectRoot =
    Split-Path $PSScriptRoot -Parent

$outputDirectory =
    Join-Path $PSScriptRoot "Output"


# ==========================================
# Load core functions
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"
. "$projectRoot\Core\Invoke-AmazonSearch.ps1"


# ==========================================
# Settings
# ==========================================

$maxTailSearchRequests =
    2


$tailResources =
    @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "itemInfo.classifications"
    )


# ==========================================
# Request counters
# ==========================================

$script:tokenRequestCount =
    0

$script:searchItemsRequestCount =
    0


# ==========================================
# Load config
# ==========================================

$configPath =
    Join-Path $projectRoot "config.json"


if (-not (Test-Path $configPath)) {

    Write-Host "config.json not found."
    exit
}


$config =
    Get-Content $configPath -Raw |
    ConvertFrom-Json


# ==========================================
# Input ASIN
# ==========================================

$seedAsin =
    Read-Host "Enter seed ASIN"

$seedAsin =
    $seedAsin.Trim()


if (
    [string]::IsNullOrWhiteSpace(
        $seedAsin
    )
) {

    Write-Host "ASIN is empty."
    exit
}


# ==========================================
# Find latest series summary
# ==========================================

$summaryPattern =
    "manga-series-{0}-*-summary.json" -f
    $seedAsin


$summaryFile =
    Get-ChildItem `
        -Path $outputDirectory `
        -Filter $summaryPattern `
        -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1


if (-not $summaryFile) {

    Write-Host ""
    Write-Host "Series summary was not found."
    Write-Host "Run debug-manga-series.ps1 first."
    exit
}


Write-Host ""
Write-Host (
    "Using summary: {0}" -f
    $summaryFile.FullName
)


$summary =
    Get-Content `
        $summaryFile.FullName `
        -Raw |
    ConvertFrom-Json


# ==========================================
# Read existing analysis
# ==========================================

$seriesTitle =
    [string]$summary.SeriesTitle


$seedLabel =
    [string]$summary.SeedLabel


$seedAuthors =
    @(
        $summary.SeedAuthors
    )


$currentMaxVolume =
    [int]$summary.MaxDetectedVolume


$isSearchTruncated =
    [bool]$summary.IsSearchTruncated


$detectedRanges =
    [string]$summary.DetectedRanges


if (
    [string]::IsNullOrWhiteSpace(
        $seriesTitle
    )
) {

    Write-Host "Series title is missing."
    exit
}


if ($currentMaxVolume -le 0) {

    Write-Host "Maximum detected volume is invalid."
    exit
}


# ==========================================
# Existing result
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " EXISTING SERIES RESULT"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "Series: {0}" -f
    $seriesTitle
)

Write-Host (
    "Detected ranges: {0}" -f
    $detectedRanges
)

Write-Host (
    "Current max volume: {0}" -f
    $currentMaxVolume
)

Write-Host (
    "Search truncated: {0}" -f
    $isSearchTruncated
)


# ==========================================
# No tail check required
# ==========================================

if (-not $isSearchTruncated) {

    Write-Host ""
    Write-Host "Search was not truncated."
    Write-Host "Tail verification is not required."
    exit
}


# ==========================================
# Authentication
# ==========================================

try {

    $script:tokenRequestCount++

    $accessToken =
        Get-AmazonAccessToken `
            -Config $config
}
catch {

    Write-Host ""
    Write-Host "Authentication failed."
    Write-Host $_.Exception.Message
    exit
}


# ==========================================
# Normalize text
# ==========================================

function ConvertTo-NormalizedText {

    param(
        [string]$Text
    )


    if (
        [string]::IsNullOrWhiteSpace(
            $Text
        )
    ) {

        return ""
    }


    $normalized =
        $Text.Normalize(
            [Text.NormalizationForm]::FormKC
        )


    return (
        (
            $normalized -replace '\s+', ' '
        ).Trim()
    )
}


# ==========================================
# Extract volume number
# ==========================================

function Get-MangaVolumeNumber {

    param(
        [string]$Title
    )


    $normalizedTitle =
        ConvertTo-NormalizedText `
            -Text $Title


    if (
        [string]::IsNullOrWhiteSpace(
            $normalizedTitle
        )
    ) {

        return $null
    }


    if (
        $normalizedTitle -match
        '\((\d+)\)'
    ) {

        return [int]$Matches[1]
    }


    if (
        $normalizedTitle -match
        '\u7B2C\s*(\d+)\s*\u5DFB'
    ) {

        return [int]$Matches[1]
    }


    if (
        $normalizedTitle -match
        '(\d+)\s*\u5DFB'
    ) {

        return [int]$Matches[1]
    }


    if (
        $normalizedTitle -match
        '\s(\d+)\s*$'
    ) {

        return [int]$Matches[1]
    }


    return $null
}


# ==========================================
# Extract trailing label
# ==========================================

function Get-TrailingLabel {

    param(
        [string]$Title
    )


    $normalizedTitle =
        ConvertTo-NormalizedText `
            -Text $Title


    if (
        $normalizedTitle -match
        '\(([^()]*)\)\s*$'
    ) {

        $label =
            ConvertTo-NormalizedText `
                -Text $Matches[1]


        if (
            $label -notmatch
            '^\d+$'
        ) {

            return $label
        }
    }


    return ""
}


# ==========================================
# Get author names
# ==========================================

function Get-AuthorNames {

    param(
        $Item
    )


    $names =
        @()


    if (
        $Item.itemInfo -and
        $Item.itemInfo.byLineInfo -and
        $Item.itemInfo.byLineInfo.contributors
    ) {

        foreach (
            $contributor in
            $Item.itemInfo.byLineInfo.contributors
        ) {

            if (
                $contributor.roleType -eq
                "author"
            ) {

                $names +=
                    $contributor.name
            }
        }
    }


    return @(
        $names |
        Sort-Object -Unique
    )
}


# ==========================================
# Get binding
# ==========================================

function Get-Binding {

    param(
        $Item
    )


    if (
        $Item.itemInfo -and
        $Item.itemInfo.classifications -and
        $Item.itemInfo.classifications.binding
    ) {

        return (
            $Item.itemInfo.classifications.binding.displayValue
        )
    }


    return ""
}


# ==========================================
# Check direct main-series title shape
# ==========================================

function Test-DirectVolumeTitle {

    param(
        [Parameter(Mandatory)]
        [string]$SeriesTitle,

        [Parameter(Mandatory)]
        [int]$Volume,

        [Parameter(Mandatory)]
        [string]$Title
    )


    $normalizedSeries =
        ConvertTo-NormalizedText `
            -Text $SeriesTitle


    $normalizedTitle =
        ConvertTo-NormalizedText `
            -Text $Title


    $escapedSeries =
        [regex]::Escape(
            $normalizedSeries
        )


    $patterns =
        @(
            (
                '^' +
                $escapedSeries +
                '\s*\(' +
                $Volume +
                '\)\s*(?:\([^()]*\))?\s*$'
            ),
            (
                '^' +
                $escapedSeries +
                '\s+' +
                $Volume +
                '\s*(?:\([^()]*\))?\s*$'
            ),
            (
                '^' +
                $escapedSeries +
                '\s*\u7B2C\s*' +
                $Volume +
                '\s*\u5DFB\s*(?:\([^()]*\))?\s*$'
            ),
            (
                '^' +
                $escapedSeries +
                '\s*' +
                $Volume +
                '\s*\u5DFB\s*(?:\([^()]*\))?\s*$'
            )
        )


    foreach ($pattern in $patterns) {

        if (
            $normalizedTitle -match
            $pattern
        ) {

            return $true
        }
    }


    return $false
}


# ==========================================
# Candidate validation
# ==========================================

function Test-TailCandidate {

    param(
        [Parameter(Mandatory)]
        $Item,

        [Parameter(Mandatory)]
        [string]$SeriesTitle,

        [Parameter(Mandatory)]
        [int]$ExpectedVolume,

        [string]$SeedLabel = "",

        [array]$SeedAuthors = @()
    )


    if (
        -not $Item.itemInfo -or
        -not $Item.itemInfo.title
    ) {

        return $false
    }


    $title =
        $Item.itemInfo.title.displayValue


    $volume =
        Get-MangaVolumeNumber `
            -Title $title


    if (
        $null -eq $volume -or
        $volume -ne $ExpectedVolume
    ) {

        return $false
    }


    if (
        -not (
            Test-DirectVolumeTitle `
                -SeriesTitle $SeriesTitle `
                -Volume $ExpectedVolume `
                -Title $title
        )
    ) {

        return $false
    }


    # --------------------------------------
    # Validate Kindle binding
    # --------------------------------------

    $kindleBinding =
        ([char]0x004B) +
        ([char]0x0069) +
        ([char]0x006E) +
        ([char]0x0064) +
        ([char]0x006C) +
        ([char]0x0065) +
        ([char]0x7248)


    $binding =
        Get-Binding `
            -Item $Item


    if (
        $binding -ne
        $kindleBinding
    ) {

        return $false
    }


    # --------------------------------------
    # Validate label when available
    # --------------------------------------

    if (
        -not [string]::IsNullOrWhiteSpace(
            $SeedLabel
        )
    ) {

        $candidateLabel =
            Get-TrailingLabel `
                -Title $title


        if (
            -not [string]::IsNullOrWhiteSpace(
                $candidateLabel
            ) -and
            $candidateLabel -ne
            $SeedLabel
        ) {

            return $false
        }
    }


    # --------------------------------------
    # Validate author when available
    # --------------------------------------

    if ($SeedAuthors.Count -gt 0) {

        $candidateAuthors =
            @(
                Get-AuthorNames `
                    -Item $Item
            )


        $authorMatched =
            $false


        foreach ($seedAuthor in $SeedAuthors) {

            if (
                $candidateAuthors -contains
                $seedAuthor
            ) {

                $authorMatched =
                    $true

                break
            }
        }


        if (-not $authorMatched) {

            return $false
        }
    }


    return $true
}


# ==========================================
# Search helper
# ==========================================

function Invoke-TailSearch {

    param(
        [Parameter(Mandatory)]
        [string]$Keyword
    )


    $script:searchItemsRequestCount++


    return (
        Invoke-AmazonSearch `
            -Keyword $Keyword `
            -SearchIndex "KindleStore" `
            -Resources $tailResources `
            -Config $config `
            -AccessToken $accessToken `
            -ItemCount 10 `
            -ItemPage 1
    )
}


# ==========================================
# Tail search
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " TAIL VERIFICATION"
Write-Host "========================================"
Write-Host ""


$tailChecks =
    @()


$verifiedMaxVolume =
    $currentMaxVolume


$tailStatus =
    "Unchecked"


for (
    $attempt = 1;
    $attempt -le $maxTailSearchRequests;
    $attempt++
) {

    $targetVolume =
        $verifiedMaxVolume + 1


    # --------------------------------------
    # Build focused search keyword
    # --------------------------------------

    if (
        [string]::IsNullOrWhiteSpace(
            $seedLabel
        )
    ) {

        $keyword =
            "{0} {1}" -f
            $seriesTitle,
            $targetVolume
    }
    else {

        $keyword =
            "{0} {1} {2}" -f
            $seriesTitle,
            $targetVolume,
            $seedLabel
    }


    Write-Host (
        "Tail search {0}/{1}: {2}" -f
        $attempt,
        $maxTailSearchRequests,
        $keyword
    )


    Start-Sleep `
        -Milliseconds 1100


    try {

        $response =
            Invoke-TailSearch `
                -Keyword $keyword
    }
    catch {

        Write-Host "Tail search failed."
        Write-Host $_.Exception.Message

        $tailStatus =
            "SearchError"

        break
    }


    $items =
        @()


    if (
        $response.searchResult -and
        $response.searchResult.items
    ) {

        $items =
            @(
                $response.searchResult.items
            )
    }


    $matchingItems =
        @()


    foreach ($item in $items) {

        if (
            Test-TailCandidate `
                -Item $item `
                -SeriesTitle $seriesTitle `
                -ExpectedVolume $targetVolume `
                -SeedLabel $seedLabel `
                -SeedAuthors $seedAuthors
        ) {

            $matchingItems +=
                $item
        }
    }


    $selectedMatch =
        @(
            $matchingItems |
            Sort-Object {
                $_.itemInfo.title.displayValue.Length
            }
        ) |
        Select-Object -First 1


    if ($selectedMatch) {

        $matchedTitle =
            $selectedMatch.itemInfo.title.displayValue


        $tailChecks +=
            [PSCustomObject]@{

                Attempt =
                    $attempt

                TargetVolume =
                    $targetVolume

                Keyword =
                    $keyword

                Found =
                    $true

                ASIN =
                    $selectedMatch.asin

                Title =
                    $matchedTitle

                ReturnedItemCount =
                    $items.Count
            }


        Write-Host (
            "Volume {0} found: {1}" -f
            $targetVolume,
            $matchedTitle
        )


        $verifiedMaxVolume =
            $targetVolume


        $tailStatus =
            "NextVolumeFound"


        continue
    }


    $tailChecks +=
        [PSCustomObject]@{

            Attempt =
                $attempt

            TargetVolume =
                $targetVolume

            Keyword =
                $keyword

            Found =
                $false

            ASIN =
                ""

            Title =
                ""

            ReturnedItemCount =
                $items.Count
        }


    Write-Host (
        "Volume {0} was not found." -f
        $targetVolume
    )


    $tailStatus =
        "NextVolumeNotFound"


    # --------------------------------------
    # Stop immediately after first missing
    # sequential volume.
    # --------------------------------------

    break
}


# ==========================================
# Determine confidence
# ==========================================

$tailConfidence =
    "Unknown"


$recommendedTotalVolumeStatus =
    "Probable"


if (
    $tailStatus -eq
    "NextVolumeNotFound"
) {

    $tailConfidence =
        "StrongProbable"

    $recommendedTotalVolumeStatus =
        "StrongProbable"
}
elseif (
    $tailStatus -eq
    "NextVolumeFound" -and
    $script:searchItemsRequestCount -ge
    $maxTailSearchRequests
) {

    $tailConfidence =
        "NeedsMoreTailCheck"

    $recommendedTotalVolumeStatus =
        "Probable"
}
elseif (
    $tailStatus -eq
    "SearchError"
) {

    $tailConfidence =
        "Unknown"

    $recommendedTotalVolumeStatus =
        "Probable"
}


# ==========================================
# Request summary
# ==========================================

$totalRequests =
    $script:tokenRequestCount +
    $script:searchItemsRequestCount


# ==========================================
# Result
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " TAIL CHECK RESULT"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "Original max volume: {0}" -f
    $currentMaxVolume
)

Write-Host (
    "Verified max volume: {0}" -f
    $verifiedMaxVolume
)

Write-Host (
    "Tail status: {0}" -f
    $tailStatus
)

Write-Host (
    "Tail confidence: {0}" -f
    $tailConfidence
)

Write-Host (
    "Recommended total status: {0}" -f
    $recommendedTotalVolumeStatus
)

Write-Host ""

Write-Host (
    "Token requests: {0}" -f
    $script:tokenRequestCount
)

Write-Host (
    "Tail SearchItems requests: {0}" -f
    $script:searchItemsRequestCount
)

Write-Host (
    "Total requests this check: {0}" -f
    $totalRequests
)


# ==========================================
# Output object
# ==========================================

$result =
    [PSCustomObject]@{

        SeedASIN =
            $seedAsin

        SourceSummary =
            $summaryFile.Name

        SeriesTitle =
            $seriesTitle

        OriginalDetectedRanges =
            $detectedRanges

        OriginalMaxVolume =
            $currentMaxVolume

        VerifiedMaxVolume =
            $verifiedMaxVolume

        OriginalTotalVolumeStatus =
            $summary.TotalVolumeStatus

        TailStatus =
            $tailStatus

        TailConfidence =
            $tailConfidence

        RecommendedTotalVolumeStatus =
            $recommendedTotalVolumeStatus

        TailChecks =
            @($tailChecks)

        TokenRequests =
            $script:tokenRequestCount

        SearchItemsRequests =
            $script:searchItemsRequestCount

        TotalRequests =
            $totalRequests
    }


# ==========================================
# Output files
# ==========================================

$runId =
    Get-Date -Format "yyyyMMdd-HHmmss"


$outputPrefix =
    "manga-tail-{0}-{1}" -f
    $seedAsin,
    $runId


$jsonPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix.json"


$reportPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-report.txt"


$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding `
        -ArgumentList $true


$resultJson =
    $result |
    ConvertTo-Json -Depth 10


[System.IO.File]::WriteAllText(
    $jsonPath,
    $resultJson,
    $utf8Bom
)


# ==========================================
# Text report
# ==========================================

$reportLines =
    @()


$reportLines +=
    "========================================"

$reportLines +=
    " MANGA TAIL CHECK REPORT"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "SeedASIN: $seedAsin"

$reportLines +=
    "SeriesTitle: $seriesTitle"

$reportLines +=
    "SourceSummary: $($summaryFile.Name)"

$reportLines +=
    ""

$reportLines +=
    "OriginalDetectedRanges: $detectedRanges"

$reportLines +=
    "OriginalMaxVolume: $currentMaxVolume"

$reportLines +=
    "VerifiedMaxVolume: $verifiedMaxVolume"

$reportLines +=
    ""

$reportLines +=
    "OriginalTotalVolumeStatus: $($summary.TotalVolumeStatus)"

$reportLines +=
    "TailStatus: $tailStatus"

$reportLines +=
    "TailConfidence: $tailConfidence"

$reportLines +=
    "RecommendedTotalVolumeStatus: $recommendedTotalVolumeStatus"

$reportLines +=
    ""

$reportLines +=
    "========================================"

$reportLines +=
    " TAIL SEARCHES"

$reportLines +=
    "========================================"

$reportLines +=
    ""


foreach ($check in $tailChecks) {

    $reportLines +=
        (
            "Attempt {0}: Target={1} | Found={2} | ASIN={3} | Title={4} | Keyword={5}" -f
            $check.Attempt,
            $check.TargetVolume,
            $check.Found,
            $check.ASIN,
            $check.Title,
            $check.Keyword
        )
}


$reportLines +=
    ""

$reportLines +=
    "========================================"

$reportLines +=
    " API REQUEST SUMMARY"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "TokenRequests: $($script:tokenRequestCount)"

$reportLines +=
    "SearchItemsRequests: $($script:searchItemsRequestCount)"

$reportLines +=
    "TotalRequests: $totalRequests"


[System.IO.File]::WriteAllLines(
    $reportPath,
    $reportLines,
    $utf8Bom
)


# ==========================================
# Complete
# ==========================================

Write-Host ""
Write-Host "JSON:"
Write-Host $jsonPath

Write-Host ""

Write-Host "Report:"
Write-Host $reportPath

Write-Host ""