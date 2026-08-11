# ==========================================
# Manga Investigation Script
# ==========================================
#
# This script investigates manga-related data
# from Books, KindleStore, and MoviesAndTV.
#
# Features:
# - Retrieve Books results
# - Retrieve up to 100 Kindle results
# - Retrieve MoviesAndTV results
# - Extract manga volume numbers
# - Group Kindle items by series
# - Detect Kindle Unlimited browse nodes
# - Detect total volume count from Books titles
# - Compare Books total volumes with Kindle volumes
# - Detect missing Kindle volumes
# - Convert volume lists into ranges
#
# This is a debug/research tool.
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
# Load common functions
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"
. "$projectRoot\Core\Invoke-AmazonSearch.ps1"


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
# Authentication
# ==========================================

try {

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
# Input manga title
# ==========================================

$keyword =
    Read-Host "Enter manga title"

if ([string]::IsNullOrWhiteSpace($keyword)) {

    Write-Host "Keyword is empty."
    exit
}


# ==========================================
# Prepare output directory
# ==========================================

if (-not (Test-Path $outputDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $outputDirectory |
        Out-Null
}


# ==========================================
# Run identifier
# ==========================================

$runId =
    Get-Date -Format "yyyyMMdd-HHmmss"


# ==========================================
# API resources
# ==========================================

$commonResources = @(
    "itemInfo.title",
    "itemInfo.byLineInfo",
    "itemInfo.classifications",
    "itemInfo.contentInfo",
    "itemInfo.externalIds",
    "itemInfo.features",
    "itemInfo.productInfo",
    "itemInfo.technicalInfo",
    "images.primary.medium",
    "offersV2.listings.availability",
    "offersV2.listings.condition",
    "offersV2.listings.isBuyBoxWinner",
    "offersV2.listings.merchantInfo",
    "offersV2.listings.price",
    "offersV2.listings.type"
)


$kindleResources =
    @($commonResources) + @(
        "browseNodeInfo.browseNodes",
        "browseNodeInfo.browseNodes.ancestor",
        "browseNodeInfo.websiteSalesRank"
    )


# ==========================================
# Normalize text
# ==========================================

function ConvertTo-NormalizedText {

    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {

        return ""
    }


    $normalized =
        $Text.Normalize(
            [System.Text.NormalizationForm]::FormKC
        )


    $normalized =
        $normalized -replace '\s+', ' '


    return $normalized.Trim()
}


# ==========================================
# Extract manga volume number
# ==========================================

function Get-MangaVolumeNumber {

    param(
        [Parameter(Mandatory)]
        [string]$Title
    )


    $normalizedTitle =
        ConvertTo-NormalizedText `
            -Text $Title


    # Complete edition + number.
    #
    # U+5B8C U+5168 U+7248
    $completeEditionPattern =
        '\u5B8C\u5168\u7248\s*(\d+)'


    if (
        $normalizedTitle -match
        $completeEditionPattern
    ) {

        return [int]$matches[1]
    }


    # Parenthesized volume number.
    #
    # FormKC converts full-width parentheses
    # and numbers before this check.

    if (
        $normalizedTitle -match
        '\((\d+)\)'
    ) {

        return [int]$matches[1]
    }


    # Ordinal volume notation.
    #
    # U+7B2C = ordinal prefix
    # U+5DFB = volume character

    $ordinalVolumePattern =
        '\u7B2C\s*(\d+)\s*\u5DFB'


    if (
        $normalizedTitle -match
        $ordinalVolumePattern
    ) {

        return [int]$matches[1]
    }


    # Number followed by volume character.

    $numberVolumePattern =
        '(\d+)\s*\u5DFB'


    if (
        $normalizedTitle -match
        $numberVolumePattern
    ) {

        return [int]$matches[1]
    }


    return $null
}


# ==========================================
# Detect manga series name
# ==========================================

function Get-MangaSeriesName {

    param(
        [Parameter(Mandatory)]
        [string]$Title
    )


    $seriesName =
        ConvertTo-NormalizedText `
            -Text $Title


    # Remove complete-edition volume number.

    $seriesName =
        $seriesName -replace (
            '\s*\u5B8C\u5168\u7248\s*\d+.*$'
        ),
        ''


    # Remove parenthesized numeric volume.

    $seriesName =
        $seriesName -replace (
            '\s*\(\d+\).*$'
        ),
        ''


    # Remove ordinal volume notation.

    $seriesName =
        $seriesName -replace (
            '\s*\u7B2C\s*\d+\s*\u5DFB.*$'
        ),
        ''


    # Remove number + volume notation.

    $seriesName =
        $seriesName -replace (
            '\s*\d+\s*\u5DFB.*$'
        ),
        ''


    $seriesName =
        $seriesName -replace '\s+', ' '


    return $seriesName.Trim()
}


# ==========================================
# Detect total volume count from Books title
# ==========================================

function Get-BooksTotalVolumeNumber {

    param(
        [Parameter(Mandatory)]
        [string]$Title
    )


    $normalizedTitle =
        ConvertTo-NormalizedText `
            -Text $Title


    # U+5168 = total/all
    # U+5DFB = volume character
    #
    # Example after normalization:
    #
    # Title (all 34 volumes)

    $pattern =
        '\u5168\s*(\d+)\s*\u5DFB'


    if (
        $normalizedTitle -match
        $pattern
    ) {

        return [int]$matches[1]
    }


    return $null
}


# ==========================================
# Detect Kindle Unlimited
# ==========================================

function Test-KindleUnlimitedNode {

    param(
        [Parameter(Mandatory)]
        $Item
    )


    if (-not $Item.browseNodeInfo) {

        return $false
    }


    $browseNodeJson =
        $Item.browseNodeInfo |
        ConvertTo-Json -Depth 30


    if (
        $browseNodeJson -match
        'Kindle Unlimited'
    ) {

        return $true
    }


    return $false
}


# ==========================================
# Get Buy Box price
# ==========================================

function Get-BuyBoxPrice {

    param(
        [Parameter(Mandatory)]
        $Item
    )


    if (-not $Item.offersV2.listings) {

        return $null
    }


    $buyBox =
        @(
            $Item.offersV2.listings |
            Where-Object {
                $_.isBuyBoxWinner -eq $true
            }
        ) |
        Select-Object -First 1


    if (
        $buyBox -and
        $buyBox.price -and
        $buyBox.price.money
    ) {

        return $buyBox.price.money.displayAmount
    }


    $firstListing =
        @(
            $Item.offersV2.listings
        ) |
        Select-Object -First 1


    if (
        $firstListing -and
        $firstListing.price -and
        $firstListing.price.money
    ) {

        return $firstListing.price.money.displayAmount
    }


    return $null
}


# ==========================================
# Convert volumes into ranges
# ==========================================

function ConvertTo-VolumeRanges {

    param(
        [array]$Volumes
    )


    $numbers =
        @(
            $Volumes |
            Where-Object {
                $null -ne $_
            } |
            ForEach-Object {
                [int]$_
            } |
            Sort-Object -Unique
        )


    if ($numbers.Count -eq 0) {

        return "none"
    }


    $ranges =
        @()


    $rangeStart =
        $numbers[0]

    $previous =
        $numbers[0]


    for (
        $i = 1;
        $i -lt $numbers.Count;
        $i++
    ) {

        $current =
            $numbers[$i]


        if (
            $current -eq
            ($previous + 1)
        ) {

            $previous =
                $current

            continue
        }


        if (
            $rangeStart -eq
            $previous
        ) {

            $ranges +=
                [string]$rangeStart
        }
        else {

            $ranges += (
                "{0}-{1}" -f
                $rangeStart,
                $previous
            )
        }


        $rangeStart =
            $current

        $previous =
            $current
    }


    if (
        $rangeStart -eq
        $previous
    ) {

        $ranges +=
            [string]$rangeStart
    }
    else {

        $ranges += (
            "{0}-{1}" -f
            $rangeStart,
            $previous
        )
    }


    return (
        $ranges -join ", "
    )
}


# ==========================================
# Detect missing volumes
# ==========================================

function Get-MissingVolumes {

    param(
        [int]$TotalVolumes,

        [array]$DetectedVolumes
    )


    if ($TotalVolumes -le 0) {

        return @()
    }


    $lookup =
        @{}


    foreach (
        $volume in
        $DetectedVolumes
    ) {

        if ($null -ne $volume) {

            $lookup[[int]$volume] =
                $true
        }
    }


    $missing =
        @()


    for (
        $volume = 1;
        $volume -le $TotalVolumes;
        $volume++
    ) {

        if (
            -not $lookup.ContainsKey(
                $volume
            )
        ) {

            $missing +=
                $volume
        }
    }


    return $missing
}


# ==========================================
# Single-page debug search
# ==========================================

function Invoke-DebugSearch {

    param(
        [Parameter(Mandatory)]
        [string]$SearchIndex,

        [Parameter(Mandatory)]
        [array]$Resources
    )


    $searchParams = @{
        Keyword     = $keyword
        SearchIndex = $SearchIndex
        Resources   = $Resources
        Config      = $config
        AccessToken = $accessToken
        ItemCount   = 10
        ItemPage    = 1
    }


    try {

        $response =
            Invoke-AmazonSearch @searchParams

        return $response
    }
    catch {

        Write-Host ""
        Write-Host (
            "Search failed: {0}" -f
            $SearchIndex
        )

        Write-Host $_.Exception.Message

        return $null
    }
}


# ==========================================
# Kindle multi-page search
# ==========================================

function Invoke-KindleDebugSearch {

    $allItems =
        @()

    $totalResultCount =
        0


    for (
        $page = 1;
        $page -le 10;
        $page++
    ) {

        Write-Host (
            "Searching Kindle page {0}..." -f
            $page
        )


        $searchParams = @{
            Keyword     = $keyword
            SearchIndex = "KindleStore"
            Resources   = $kindleResources
            Config      = $config
            AccessToken = $accessToken
            ItemCount   = 10
            ItemPage    = $page
        }


        try {

            $response =
                Invoke-AmazonSearch @searchParams
        }
        catch {

            Write-Host ""
            Write-Host (
                "Kindle search failed on page {0}." -f
                $page
            )

            Write-Host $_.Exception.Message

            break
        }


        if (-not $response) {

            break
        }


        if ($page -eq 1) {

            $totalResultCount =
                $response.searchResult.totalResultCount
        }


        $pageItems =
            @(
                $response.searchResult.items
            )


        if ($pageItems.Count -eq 0) {

            break
        }


        $allItems +=
            $pageItems


        if (
            $totalResultCount -gt 0 -and
            $allItems.Count -ge
            $totalResultCount
        ) {

            break
        }


        if ($page -lt 10) {

            Start-Sleep `
                -Milliseconds 1100
        }
    }


    $uniqueItems =
        @(
            $allItems |
            Group-Object asin |
            ForEach-Object {
                $_.Group[0]
            }
        )


    return [PSCustomObject]@{
        Items            = $uniqueItems
        TotalResultCount = $totalResultCount
    }
}


# ==========================================
# Search Books
# ==========================================

Write-Host ""
Write-Host "Searching Books..."


$booksResponse =
    Invoke-DebugSearch `
        -SearchIndex "Books" `
        -Resources $commonResources


Start-Sleep `
    -Milliseconds 1100


# ==========================================
# Search Kindle
# ==========================================

Write-Host ""
Write-Host "Searching Kindle..."


$kindleSearchResult =
    Invoke-KindleDebugSearch


Start-Sleep `
    -Milliseconds 1100


# ==========================================
# Search Movies
# ==========================================

Write-Host ""
Write-Host "Searching Movies..."


$moviesResponse =
    Invoke-DebugSearch `
        -SearchIndex "MoviesAndTV" `
        -Resources $commonResources


# ==========================================
# Build result arrays
# ==========================================

$booksItems =
    @()

if ($booksResponse) {

    $booksItems =
        @(
            $booksResponse.searchResult.items
        )
}


$kindleItems =
    @()

if ($kindleSearchResult) {

    $kindleItems =
        @(
            $kindleSearchResult.Items
        )
}


$moviesItems =
    @()

if ($moviesResponse) {

    $moviesItems =
        @(
            $moviesResponse.searchResult.items
        )
}


# ==========================================
# Search result counts
# ==========================================

$booksTotalResultCount =
    0

if ($booksResponse) {

    $booksTotalResultCount =
        $booksResponse.searchResult.totalResultCount
}


$kindleTotalResultCount =
    0

if ($kindleSearchResult) {

    $kindleTotalResultCount =
        $kindleSearchResult.TotalResultCount
}


$moviesTotalResultCount =
    0

if ($moviesResponse) {

    $moviesTotalResultCount =
        $moviesResponse.searchResult.totalResultCount
}


# ==========================================
# Analyze Books total-volume candidates
# ==========================================

$normalizedKeyword =
    ConvertTo-NormalizedText `
        -Text $keyword


$booksTotalCandidates =
    @()


foreach ($item in $booksItems) {

    if (
        -not $item.itemInfo -or
        -not $item.itemInfo.title
    ) {

        continue
    }


    $title =
        $item.itemInfo.title.displayValue


    if (
        [string]::IsNullOrWhiteSpace(
            $title
        )
    ) {

        continue
    }


    $normalizedTitle =
        ConvertTo-NormalizedText `
            -Text $title


    $totalVolumes =
        Get-BooksTotalVolumeNumber `
            -Title $title


    if ($null -eq $totalVolumes) {

        continue
    }


    $keywordPosition =
        $normalizedTitle.IndexOf(
            $normalizedKeyword,
            [System.StringComparison]::OrdinalIgnoreCase
        )


    if ($keywordPosition -lt 0) {

        continue
    }


    $booksTotalCandidates +=
        [PSCustomObject]@{
            Title        = $title
            ASIN         = $item.asin
            TotalVolumes = $totalVolumes
        }
}


$uniqueBooksTotals =
    @(
        $booksTotalCandidates |
        Select-Object `
            -ExpandProperty TotalVolumes `
            -Unique |
        Sort-Object
    )


$booksTotalVolumes =
    $null


if ($uniqueBooksTotals.Count -eq 1) {

    $booksTotalVolumes =
        [int]$uniqueBooksTotals[0]
}


# ==========================================
# Analyze Kindle items
# ==========================================

$analyzedKindleItems =
    @()


foreach ($item in $kindleItems) {

    if (
        -not $item.itemInfo -or
        -not $item.itemInfo.title
    ) {

        continue
    }


    $title =
        $item.itemInfo.title.displayValue


    if (
        [string]::IsNullOrWhiteSpace(
            $title
        )
    ) {

        continue
    }


    $volume =
        Get-MangaVolumeNumber `
            -Title $title


    $seriesName =
        Get-MangaSeriesName `
            -Title $title


    $isKindleUnlimited =
        Test-KindleUnlimitedNode `
            -Item $item


    $price =
        Get-BuyBoxPrice `
            -Item $item


    $analyzedKindleItems +=
        [PSCustomObject]@{
            SeriesName        = $seriesName
            Volume            = $volume
            Title             = $title
            ASIN              = $item.asin
            Price             = $price
            IsKindleUnlimited = $isKindleUnlimited
        }
}


# ==========================================
# Build Kindle series groups
# ==========================================

$seriesGroups =
    @(
        $analyzedKindleItems |
        Where-Object {
            $null -ne $_.Volume
        } |
        Group-Object SeriesName |
        Sort-Object Name
    )


# ==========================================
# Find primary Kindle series
# ==========================================

$primarySeriesGroup =
    $null


foreach ($group in $seriesGroups) {

    $normalizedGroupName =
        ConvertTo-NormalizedText `
            -Text $group.Name


    if (
        $normalizedGroupName -eq
        $normalizedKeyword
    ) {

        $primarySeriesGroup =
            $group

        break
    }
}


# ==========================================
# Analyze primary series
# ==========================================

$primarySeriesName =
    $null

$detectedVolumes =
    @()

$kindleUnlimitedVolumes =
    @()

$missingVolumes =
    @()

$volumeMatch =
    $null

$isAllKindleUnlimited =
    $false

$detectedVolumeRanges =
    "none"

$kindleUnlimitedRanges =
    "none"

$missingVolumeRanges =
    "none"


if ($primarySeriesGroup) {

    $primarySeriesName =
        $primarySeriesGroup.Name


    $detectedVolumes =
        @(
            $primarySeriesGroup.Group |
            Where-Object {
                $null -ne $_.Volume
            } |
            Select-Object `
                -ExpandProperty Volume `
                -Unique |
            Sort-Object
        )


    $kindleUnlimitedVolumes =
        @(
            $primarySeriesGroup.Group |
            Where-Object {
                $_.IsKindleUnlimited -eq $true -and
                $null -ne $_.Volume
            } |
            Select-Object `
                -ExpandProperty Volume `
                -Unique |
            Sort-Object
        )


    $detectedVolumeRanges =
        ConvertTo-VolumeRanges `
            -Volumes $detectedVolumes


    $kindleUnlimitedRanges =
        ConvertTo-VolumeRanges `
            -Volumes $kindleUnlimitedVolumes


    if ($null -ne $booksTotalVolumes) {

        $missingVolumes =
            @(
                Get-MissingVolumes `
                    -TotalVolumes $booksTotalVolumes `
                    -DetectedVolumes $detectedVolumes
            )


        $missingVolumeRanges =
            ConvertTo-VolumeRanges `
                -Volumes $missingVolumes


        if (
            $missingVolumes.Count -eq 0 -and
            $detectedVolumes.Count -eq
            $booksTotalVolumes
        ) {

            $volumeMatch =
                $true
        }
        else {

            $volumeMatch =
                $false
        }


        if (
            $volumeMatch -eq $true -and
            $kindleUnlimitedVolumes.Count -eq
            $booksTotalVolumes
        ) {

            $isAllKindleUnlimited =
                $true
        }
    }
}


# ==========================================
# Prepare human-readable text values
# ==========================================

$booksTotalVolumesText =
    "unknown"

if ($null -ne $booksTotalVolumes) {

    $booksTotalVolumesText =
        [string]$booksTotalVolumes
}


$volumeMatchText =
    "unknown"

if ($volumeMatch -eq $true) {

    $volumeMatchText =
        "True"
}
elseif ($volumeMatch -eq $false) {

    $volumeMatchText =
        "False"
}


$detectedVolumesText =
    "none"

if ($detectedVolumes.Count -gt 0) {

    $detectedVolumesText =
        $detectedVolumes -join ", "
}


$missingVolumesText =
    "none"

if ($missingVolumes.Count -gt 0) {

    $missingVolumesText =
        $missingVolumes -join ", "
}


$kindleUnlimitedVolumesText =
    "none"

if ($kindleUnlimitedVolumes.Count -gt 0) {

    $kindleUnlimitedVolumesText =
        $kindleUnlimitedVolumes -join ", "
}


# ==========================================
# Build summary object
# ==========================================

$summaryObject =
    [PSCustomObject]@{

        Keyword =
            $keyword

        PrimarySeries =
            $primarySeriesName

        BooksTotalVolumeCandidates =
            @($uniqueBooksTotals)

        BooksTotalVolumes =
            $booksTotalVolumes

        KindleDetectedVolumeCount =
            $detectedVolumes.Count

        KindleDetectedVolumes =
            @($detectedVolumes)

        KindleDetectedRanges =
            $detectedVolumeRanges

        MissingVolumeCount =
            $missingVolumes.Count

        MissingVolumes =
            @($missingVolumes)

        MissingVolumeRanges =
            $missingVolumeRanges

        VolumeMatch =
            $volumeMatch

        KindleUnlimitedVolumeCount =
            $kindleUnlimitedVolumes.Count

        KindleUnlimitedVolumes =
            @($kindleUnlimitedVolumes)

        KindleUnlimitedRanges =
            $kindleUnlimitedRanges

        IsAllKindleUnlimited =
            $isAllKindleUnlimited

        BooksSearchTotalResultCount =
            $booksTotalResultCount

        KindleSearchTotalResultCount =
            $kindleTotalResultCount

        KindleRetrievedItems =
            $kindleItems.Count

        MoviesSearchTotalResultCount =
            $moviesTotalResultCount

        MoviesReturnedItems =
            $moviesItems.Count
    }


# ==========================================
# Console summary
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " MANGA SUMMARY"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "Keyword: {0}" -f
    $keyword
)

Write-Host (
    "PrimarySeries: {0}" -f
    $primarySeriesName
)

Write-Host ""


if ($booksTotalCandidates.Count -gt 0) {

    Write-Host "Books total-volume candidates:"

    foreach (
        $candidate in
        $booksTotalCandidates
    ) {

        Write-Host (
            "  {0} | Total={1}" -f
            $candidate.Title,
            $candidate.TotalVolumes
        )
    }

    Write-Host ""
}


Write-Host (
    "BooksTotalVolumes: {0}" -f
    $booksTotalVolumesText
)

Write-Host (
    "KindleDetectedVolumeCount: {0}" -f
    $detectedVolumes.Count
)

Write-Host (
    "KindleDetectedRanges: {0}" -f
    $detectedVolumeRanges
)

Write-Host (
    "MissingVolumeCount: {0}" -f
    $missingVolumes.Count
)

Write-Host (
    "MissingVolumeRanges: {0}" -f
    $missingVolumeRanges
)

Write-Host (
    "VolumeMatch: {0}" -f
    $volumeMatchText
)

Write-Host (
    "KindleUnlimitedVolumeCount: {0}" -f
    $kindleUnlimitedVolumes.Count
)

Write-Host (
    "KindleUnlimitedRanges: {0}" -f
    $kindleUnlimitedRanges
)

Write-Host (
    "IsAllKindleUnlimited: {0}" -f
    $isAllKindleUnlimited
)


# ==========================================
# Build text report
# ==========================================

$reportLines =
    @()


$reportLines +=
    "========================================"

$reportLines +=
    " MANGA INVESTIGATION REPORT"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "RunId: $runId"

$reportLines +=
    "Keyword: $keyword"

$reportLines +=
    ""


# ==========================================
# Manga summary report
# ==========================================

$reportLines +=
    "========================================"

$reportLines +=
    " MANGA SUMMARY"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "PrimarySeries: $primarySeriesName"

$reportLines +=
    "BooksTotalVolumeCandidateCount: $($booksTotalCandidates.Count)"


foreach (
    $candidate in
    $booksTotalCandidates
) {

    $reportLines += (
        "BooksCandidate: {0} | TotalVolumes={1} | ASIN={2}" -f
        $candidate.Title,
        $candidate.TotalVolumes,
        $candidate.ASIN
    )
}


$reportLines +=
    ""

$reportLines +=
    "BooksTotalVolumes: $booksTotalVolumesText"

$reportLines +=
    "KindleDetectedVolumeCount: $($detectedVolumes.Count)"

$reportLines +=
    "KindleDetectedVolumes: $detectedVolumesText"

$reportLines +=
    "KindleDetectedRanges: $detectedVolumeRanges"

$reportLines +=
    "MissingVolumeCount: $($missingVolumes.Count)"

$reportLines +=
    "MissingVolumes: $missingVolumesText"

$reportLines +=
    "MissingVolumeRanges: $missingVolumeRanges"

$reportLines +=
    "VolumeMatch: $volumeMatchText"

$reportLines +=
    ""

$reportLines +=
    "KindleUnlimitedVolumeCount: $($kindleUnlimitedVolumes.Count)"

$reportLines +=
    "KindleUnlimitedVolumes: $kindleUnlimitedVolumesText"

$reportLines +=
    "KindleUnlimitedRanges: $kindleUnlimitedRanges"

$reportLines +=
    "IsAllKindleUnlimited: $isAllKindleUnlimited"

$reportLines +=
    ""


# ==========================================
# Books report
# ==========================================

$reportLines +=
    "========================================"

$reportLines +=
    " BOOKS"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "TotalResultCount: $booksTotalResultCount"

$reportLines +=
    "ReturnedItems: $($booksItems.Count)"

$reportLines +=
    ""


for (
    $i = 0;
    $i -lt $booksItems.Count;
    $i++
) {

    $item =
        $booksItems[$i]


    $title =
        $item.itemInfo.title.displayValue


    $detectedBookTotal =
        Get-BooksTotalVolumeNumber `
            -Title $title


    $reportLines +=
        "----------------------------------------"

    $reportLines +=
        "Item: $($i + 1)"

    $reportLines +=
        "Title: $title"

    $reportLines +=
        "ASIN: $($item.asin)"

    $reportLines +=
        "URL: $($item.detailPageURL)"

    $reportLines +=
        "DetectedTotalVolumes: $detectedBookTotal"


    if (
        $item.itemInfo.byLineInfo.contributors
    ) {

        foreach (
            $contributor in
            $item.itemInfo.byLineInfo.contributors
        ) {

            $reportLines += (
                "Contributor: {0} / {1}" -f
                $contributor.name,
                $contributor.roleType
            )
        }
    }


    $reportLines += (
        "Binding: {0}" -f
        $item.itemInfo.classifications.binding.displayValue
    )


    $reportLines += (
        "ProductGroup: {0}" -f
        $item.itemInfo.classifications.productGroup.displayValue
    )


    $reportLines += (
        "PublicationDate: {0}" -f
        $item.itemInfo.contentInfo.publicationDate.displayValue
    )


    $reportLines += (
        "ReleaseDate: {0}" -f
        $item.itemInfo.productInfo.releaseDate.displayValue
    )


    if ($item.offersV2.listings) {

        foreach (
            $listing in
            $item.offersV2.listings
        ) {

            $reportLines += (
                "Price: {0}" -f
                $listing.price.money.displayAmount
            )

            $reportLines += (
                "Availability: {0}" -f
                $listing.availability.type
            )
        }
    }


    $reportLines +=
        ""
}


# ==========================================
# Kindle raw results report
# ==========================================

$reportLines +=
    "========================================"

$reportLines +=
    " KINDLE RAW RESULTS"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "TotalResultCount: $kindleTotalResultCount"

$reportLines +=
    "RetrievedItems: $($kindleItems.Count)"

$reportLines +=
    ""


foreach (
    $item in
    $analyzedKindleItems
) {

    $reportLines +=
        "----------------------------------------"

    $reportLines +=
        "Title: $($item.Title)"

    $reportLines +=
        "SeriesName: $($item.SeriesName)"

    $reportLines +=
        "Volume: $($item.Volume)"

    $reportLines +=
        "ASIN: $($item.ASIN)"

    $reportLines +=
        "Price: $($item.Price)"

    $reportLines +=
        "KindleUnlimited: $($item.IsKindleUnlimited)"

    $reportLines +=
        ""
}


# ==========================================
# Kindle series analysis report
# ==========================================

$reportLines +=
    "========================================"

$reportLines +=
    " KINDLE SERIES ANALYSIS"

$reportLines +=
    "========================================"

$reportLines +=
    ""


foreach ($group in $seriesGroups) {

    $sortedVolumes =
        @(
            $group.Group |
            Sort-Object Volume
        )


    $uniqueVolumes =
        @(
            $sortedVolumes |
            Select-Object `
                -ExpandProperty Volume `
                -Unique |
            Sort-Object
        )


    $kuVolumes =
        @(
            $sortedVolumes |
            Where-Object {
                $_.IsKindleUnlimited -eq $true
            } |
            Select-Object `
                -ExpandProperty Volume `
                -Unique |
            Sort-Object
        )


    $groupDetectedRanges =
        ConvertTo-VolumeRanges `
            -Volumes $uniqueVolumes


    $groupKuRanges =
        ConvertTo-VolumeRanges `
            -Volumes $kuVolumes


    $groupDetectedVolumesText =
        "none"

    if ($uniqueVolumes.Count -gt 0) {

        $groupDetectedVolumesText =
            $uniqueVolumes -join ", "
    }


    $groupKuVolumesText =
        "none"

    if ($kuVolumes.Count -gt 0) {

        $groupKuVolumesText =
            $kuVolumes -join ", "
    }


    $reportLines +=
        "----------------------------------------"

    $reportLines +=
        "Series: $($group.Name)"

    $reportLines +=
        ""

    $reportLines +=
        "DetectedVolumeCount: $($uniqueVolumes.Count)"

    $reportLines +=
        "DetectedVolumes: $groupDetectedVolumesText"

    $reportLines +=
        "DetectedRanges: $groupDetectedRanges"

    $reportLines +=
        "KindleUnlimitedVolumeCount: $($kuVolumes.Count)"

    $reportLines +=
        "KindleUnlimitedVolumes: $groupKuVolumesText"

    $reportLines +=
        "KindleUnlimitedRanges: $groupKuRanges"

    $reportLines +=
        ""


    foreach (
        $volumeItem in
        $sortedVolumes
    ) {

        $kuLabel =
            "-"


        if (
            $volumeItem.IsKindleUnlimited -eq
            $true
        ) {

            $kuLabel =
                "KU"
        }


        $reportLines += (
            "Volume {0}: {1} | {2} | {3}" -f
            $volumeItem.Volume,
            $kuLabel,
            $volumeItem.Title,
            $volumeItem.ASIN
        )
    }


    $reportLines +=
        ""
}


# ==========================================
# Movies report
# ==========================================

$reportLines +=
    "========================================"

$reportLines +=
    " MOVIES"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "TotalResultCount: $moviesTotalResultCount"

$reportLines +=
    "ReturnedItems: $($moviesItems.Count)"

$reportLines +=
    ""


for (
    $i = 0;
    $i -lt $moviesItems.Count;
    $i++
) {

    $item =
        $moviesItems[$i]


    $reportLines +=
        "----------------------------------------"

    $reportLines +=
        "Item: $($i + 1)"

    $reportLines +=
        "Title: $($item.itemInfo.title.displayValue)"

    $reportLines +=
        "ASIN: $($item.asin)"

    $reportLines +=
        "URL: $($item.detailPageURL)"


    if (
        $item.itemInfo.byLineInfo.contributors
    ) {

        foreach (
            $contributor in
            $item.itemInfo.byLineInfo.contributors
        ) {

            $reportLines += (
                "Contributor: {0} / {1}" -f
                $contributor.name,
                $contributor.roleType
            )
        }
    }


    $reportLines += (
        "Binding: {0}" -f
        $item.itemInfo.classifications.binding.displayValue
    )


    $reportLines += (
        "ProductGroup: {0}" -f
        $item.itemInfo.classifications.productGroup.displayValue
    )


    $reportLines += (
        "PublicationDate: {0}" -f
        $item.itemInfo.contentInfo.publicationDate.displayValue
    )


    $reportLines += (
        "ReleaseDate: {0}" -f
        $item.itemInfo.productInfo.releaseDate.displayValue
    )


    if ($item.offersV2.listings) {

        foreach (
            $listing in
            $item.offersV2.listings
        ) {

            $reportLines += (
                "Price: {0}" -f
                $listing.price.money.displayAmount
            )

            $reportLines += (
                "Availability: {0}" -f
                $listing.availability.type
            )
        }
    }


    $reportLines +=
        ""
}


# ==========================================
# Safe file name
# ==========================================

$safeKeyword =
    $keyword -replace (
        '[\\/:*?"<>|]'
    ),
    '_'


$outputPrefix =
    "manga-{0}-compare-{1}" -f
    $safeKeyword,
    $runId


# ==========================================
# Output paths
# ==========================================

$reportPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-report.txt"


$summaryJsonPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-summary.json"


$booksJsonPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-books.json"


$kindleJsonPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-kindle.json"


$kindleAnalysisJsonPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-kindle-analysis.json"


$moviesJsonPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-movies.json"


# ==========================================
# UTF-8 BOM encoding
# ==========================================

$utf8Bom =
    [System.Text.UTF8Encoding]::new(
        $true
    )


# ==========================================
# Save summary JSON
# ==========================================

$summaryJson =
    $summaryObject |
    ConvertTo-Json -Depth 10


[System.IO.File]::WriteAllText(
    $summaryJsonPath,
    $summaryJson,
    $utf8Bom
)


# ==========================================
# Save Books raw JSON
# ==========================================

if ($booksResponse) {

    $booksJson =
        $booksResponse |
        ConvertTo-Json -Depth 30


    [System.IO.File]::WriteAllText(
        $booksJsonPath,
        $booksJson,
        $utf8Bom
    )
}


# ==========================================
# Save Kindle raw JSON
# ==========================================

if ($kindleItems.Count -gt 0) {

    $kindleJson =
        $kindleItems |
        ConvertTo-Json -Depth 30


    [System.IO.File]::WriteAllText(
        $kindleJsonPath,
        $kindleJson,
        $utf8Bom
    )
}


# ==========================================
# Save Kindle analysis JSON
# ==========================================

if ($analyzedKindleItems.Count -gt 0) {

    $kindleAnalysisJson =
        $analyzedKindleItems |
        ConvertTo-Json -Depth 10


    [System.IO.File]::WriteAllText(
        $kindleAnalysisJsonPath,
        $kindleAnalysisJson,
        $utf8Bom
    )
}


# ==========================================
# Save Movies raw JSON
# ==========================================

if ($moviesResponse) {

    $moviesJson =
        $moviesResponse |
        ConvertTo-Json -Depth 30


    [System.IO.File]::WriteAllText(
        $moviesJsonPath,
        $moviesJson,
        $utf8Bom
    )
}


# ==========================================
# Save report
# ==========================================

[System.IO.File]::WriteAllLines(
    $reportPath,
    $reportLines,
    $utf8Bom
)


# ==========================================
# Complete
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " Investigation complete"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "RunId: {0}" -f
    $runId
)

Write-Host ""

Write-Host "Report:"
Write-Host $reportPath

Write-Host ""

Write-Host "Summary JSON:"
Write-Host $summaryJsonPath

Write-Host ""

Write-Host "Output directory:"
Write-Host $outputDirectory

Write-Host ""