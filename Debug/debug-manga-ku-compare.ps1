# ==========================================
# Manga KU Comparison Debug Script
# ==========================================
#
# Purpose:
# - Start from one seed ASIN
# - Determine the manga series
# - Search Kindle using only required pages
# - Select the best candidate for each volume
# - Detect KU status from SearchItems data
# - Re-fetch selected ASINs with GetItems
# - Detect KU status again
# - Compare SearchItems KU vs GetItems KU
#
# This script is for verification only.
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
# Request counters
# ==========================================

$script:tokenRequestCount =
    0

$script:searchItemsRequestCount =
    0

$script:getItemsRequestCount =
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
# Authenticate
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
# Input seed ASIN
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
# Prepare output directory
# ==========================================

if (-not (Test-Path $outputDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $outputDirectory |
        Out-Null
}


$runId =
    Get-Date -Format "yyyyMMdd-HHmmss"


# ==========================================
# API settings
# ==========================================

$getItemsUrl =
    "https://creatorsapi.amazon/catalog/v1/getItems"


$resources = @(
    "itemInfo.title",
    "itemInfo.byLineInfo",
    "itemInfo.classifications",
    "itemInfo.contentInfo",
    "itemInfo.productInfo",
    "itemInfo.technicalInfo",
    "offersV2.listings.availability",
    "offersV2.listings.isBuyBoxWinner",
    "offersV2.listings.price",
    "browseNodeInfo.browseNodes",
    "browseNodeInfo.browseNodes.ancestor"
)


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
# Determine series title
# ==========================================

function Get-SeriesTitleFromSeed {

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

        return ""
    }


    if (
        $normalizedTitle -match
        '^(.*?)\s*\((\d+)\)\s*(?:\([^()]*\))?\s*$'
    ) {

        return (
            ConvertTo-NormalizedText `
                -Text $Matches[1]
        )
    }


    if (
        $normalizedTitle -match
        '^(.*?)\s*\u7B2C\s*\d+\s*\u5DFB(?:\s*\([^()]*\))?\s*$'
    ) {

        return (
            ConvertTo-NormalizedText `
                -Text $Matches[1]
        )
    }


    if (
        $normalizedTitle -match
        '^(.*?)\s*\d+\s*\u5DFB(?:\s*\([^()]*\))?\s*$'
    ) {

        return (
            ConvertTo-NormalizedText `
                -Text $Matches[1]
        )
    }


    if (
        $normalizedTitle -match
        '^(.*?)\s+(\d+)\s*$'
    ) {

        return (
            ConvertTo-NormalizedText `
                -Text $Matches[1]
        )
    }


    return $normalizedTitle
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
# Get authors
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
# Get price
# ==========================================

function Get-BuyBoxPrice {

    param(
        $Item
    )


    if (
        -not $Item.offersV2 -or
        -not $Item.offersV2.listings
    ) {

        return ""
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

        return (
            $buyBox.price.money.displayAmount
        )
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

        return (
            $firstListing.price.money.displayAmount
        )
    }


    return ""
}


# ==========================================
# KU detector
# ==========================================

function Test-KindleUnlimitedNode {

    param(
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
# GetItems helper
# ==========================================

function Invoke-MangaGetItems {

    param(
        [Parameter(Mandatory)]
        [array]$Asins
    )


    if ($Asins.Count -eq 0) {

        return @()
    }


    $script:getItemsRequestCount++


    $requestBody = @{
        itemIds     = @($Asins)
        itemIdType  = "ASIN"
        partnerTag  = $config.PartnerTag
        marketplace = $config.Marketplace
        resources   = $resources
    }


    $requestJson =
        $requestBody |
        ConvertTo-Json -Depth 10


    $requestBytes =
        [System.Text.Encoding]::UTF8.GetBytes(
            $requestJson
        )


    $headers = @{
        Authorization   = "Bearer $accessToken"
        "x-marketplace" = $config.Marketplace
    }


    $requestParameters = @{
        Uri         = $getItemsUrl
        Method      = "Post"
        Headers     = $headers
        ContentType = "application/json; charset=utf-8"
        Body        = $requestBytes
    }


    $webResponse =
        Invoke-WebRequest `
            @requestParameters `
            -UseBasicParsing


    $responseBytes =
        $webResponse.RawContentStream.ToArray()


    $responseText =
        [System.Text.Encoding]::UTF8.GetString(
            $responseBytes
        )


    $response =
        $responseText |
        ConvertFrom-Json


    if (
        $response.itemsResult -and
        $response.itemsResult.items
    ) {

        return @(
            $response.itemsResult.items
        )
    }


    return @()
}


# ==========================================
# Search wrapper
# ==========================================

function Invoke-MangaSearch {

    param(
        [Parameter(Mandatory)]
        [string]$Keyword,

        [Parameter(Mandatory)]
        [int]$Page
    )


    $script:searchItemsRequestCount++


    return (
        Invoke-AmazonSearch `
            -Keyword $Keyword `
            -SearchIndex "KindleStore" `
            -Resources $resources `
            -Config $config `
            -AccessToken $accessToken `
            -ItemCount 10 `
            -ItemPage $Page
    )
}


# ==========================================
# Candidate score
# ==========================================

function Get-CandidateScore {

    param(
        [Parameter(Mandatory)]
        [string]$SeriesTitle,

        [Parameter(Mandatory)]
        [int]$Volume,

        [Parameter(Mandatory)]
        [string]$Title,

        [string]$SeedLabel = "",

        [array]$SeedAuthors = @(),

        [array]$CandidateAuthors = @()
    )


    $score =
        0


    $normalizedSeries =
        ConvertTo-NormalizedText `
            -Text $SeriesTitle


    $normalizedTitle =
        ConvertTo-NormalizedText `
            -Text $Title


    $candidateLabel =
        Get-TrailingLabel `
            -Title $normalizedTitle


    $escapedSeries =
        [regex]::Escape(
            $normalizedSeries
        )


    $directPatterns =
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


    foreach ($pattern in $directPatterns) {

        if (
            $normalizedTitle -match
            $pattern
        ) {

            $score +=
                1000

            break
        }
    }


    if (
        -not [string]::IsNullOrWhiteSpace(
            $SeedLabel
        ) -and
        $candidateLabel -eq
        $SeedLabel
    ) {

        $score +=
            300
    }


    foreach ($seedAuthor in $SeedAuthors) {

        if (
            $CandidateAuthors -contains
            $seedAuthor
        ) {

            $score +=
                100

            break
        }
    }


    if (
        $normalizedTitle -match
        (
            '^' +
            $escapedSeries +
            '\s+.+\(' +
            $Volume +
            '\)'
        )
    ) {

        $score -=
            500
    }


    return $score
}


# ==========================================
# Step 1
# Retrieve seed
# ==========================================

Write-Host ""
Write-Host "Step 1: Retrieving seed ASIN..."


try {

    $seedItems =
        Invoke-MangaGetItems `
            -Asins @($seedAsin)
}
catch {

    Write-Host ""
    Write-Host "Seed GetItems failed."
    Write-Host $_.Exception.Message
    exit
}


if ($seedItems.Count -eq 0) {

    Write-Host "Seed item not found."
    exit
}


$seedItem =
    $seedItems[0]


$seedTitle =
    $seedItem.itemInfo.title.displayValue


$seriesTitle =
    Get-SeriesTitleFromSeed `
        -Title $seedTitle


$seedAuthors =
    @(
        Get-AuthorNames `
            -Item $seedItem
    )


$seedLabel =
    Get-TrailingLabel `
        -Title $seedTitle


Write-Host (
    "Seed title: {0}" -f
    $seedTitle
)

Write-Host (
    "Series title: {0}" -f
    $seriesTitle
)

Write-Host (
    "Seed label: {0}" -f
    $seedLabel
)


# ==========================================
# Step 2
# First SearchItems page
# ==========================================

Write-Host ""
Write-Host "Step 2: Retrieving first search page..."


$searchItems =
    @()

$seenAsins =
    @{}

$totalResultCount =
    0

$requiredPages =
    1

$maxSearchPages =
    10


try {

    $firstResponse =
        Invoke-MangaSearch `
            -Keyword $seriesTitle `
            -Page 1
}
catch {

    Write-Host "Search failed."
    Write-Host $_.Exception.Message
    exit
}


if (
    $firstResponse.searchResult -and
    $null -ne
    $firstResponse.searchResult.totalResultCount
) {

    $totalResultCount =
        [int]$firstResponse.searchResult.totalResultCount
}


$firstPageItems =
    @()


if (
    $firstResponse.searchResult -and
    $firstResponse.searchResult.items
) {

    $firstPageItems =
        @(
            $firstResponse.searchResult.items
        )
}


foreach ($item in $firstPageItems) {

    if (
        -not $seenAsins.ContainsKey(
            $item.asin
        )
    ) {

        $seenAsins[$item.asin] =
            $true

        $searchItems +=
            $item
    }
}


if ($totalResultCount -gt 0) {

    $requiredPages =
        [int][Math]::Ceiling(
            $totalResultCount / 10.0
        )


    if (
        $requiredPages -gt
        $maxSearchPages
    ) {

        $requiredPages =
            $maxSearchPages
    }
}


Write-Host (
    "Search total result count: {0}" -f
    $totalResultCount
)

Write-Host (
    "Required search pages: {0}" -f
    $requiredPages
)


# ==========================================
# Step 3
# Remaining SearchItems pages
# ==========================================

if ($requiredPages -gt 1) {

    for (
        $page = 2;
        $page -le $requiredPages;
        $page++
    ) {

        Start-Sleep `
            -Milliseconds 1100


        Write-Host (
            "Search page {0} of {1}..." -f
            $page,
            $requiredPages
        )


        try {

            $response =
                Invoke-MangaSearch `
                    -Keyword $seriesTitle `
                    -Page $page
        }
        catch {

            Write-Host (
                "Search page {0} failed." -f
                $page
            )

            Write-Host $_.Exception.Message
            break
        }


        $pageItems =
            @()


        if (
            $response.searchResult -and
            $response.searchResult.items
        ) {

            $pageItems =
                @(
                    $response.searchResult.items
                )
        }


        foreach ($item in $pageItems) {

            if (
                -not $seenAsins.ContainsKey(
                    $item.asin
                )
            ) {

                $seenAsins[$item.asin] =
                    $true

                $searchItems +=
                    $item
            }
        }
    }
}


# ==========================================
# Step 4
# Build candidates
# ==========================================

Write-Host ""
Write-Host "Step 4: Building candidates..."


$normalizedSeriesTitle =
    ConvertTo-NormalizedText `
        -Text $seriesTitle


$escapedSeriesTitle =
    [regex]::Escape(
        $normalizedSeriesTitle
    )


$kindleBinding =
    ([char]0x004B) +
    ([char]0x0069) +
    ([char]0x006E) +
    ([char]0x0064) +
    ([char]0x006C) +
    ([char]0x0065) +
    ([char]0x7248)


$candidates =
    @()


foreach ($item in $searchItems) {

    if (
        -not $item.itemInfo -or
        -not $item.itemInfo.title
    ) {

        continue
    }


    $title =
        $item.itemInfo.title.displayValue


    $normalizedTitle =
        ConvertTo-NormalizedText `
            -Text $title


    if (
        $normalizedTitle -notmatch
        ("^" + $escapedSeriesTitle)
    ) {

        continue
    }


    $volume =
        Get-MangaVolumeNumber `
            -Title $title


    if ($null -eq $volume) {

        continue
    }


    $binding =
        Get-Binding `
            -Item $item


    if (
        $binding -ne
        $kindleBinding
    ) {

        continue
    }


    $candidateAuthors =
        @(
            Get-AuthorNames `
                -Item $item
        )


    $score =
        Get-CandidateScore `
            -SeriesTitle $seriesTitle `
            -Volume $volume `
            -Title $title `
            -SeedLabel $seedLabel `
            -SeedAuthors $seedAuthors `
            -CandidateAuthors $candidateAuthors


    $searchKU =
        Test-KindleUnlimitedNode `
            -Item $item


    $candidates +=
        [PSCustomObject]@{

            Volume =
                [int]$volume

            ASIN =
                $item.asin

            Title =
                $title

            Score =
                $score

            SearchItemsKU =
                $searchKU

            SearchItemsPrice =
                (
                    Get-BuyBoxPrice `
                        -Item $item
                )
        }
}


# ==========================================
# Step 5
# Select best candidate per volume
# ==========================================

$volumeGroups =
    @(
        $candidates |
        Group-Object Volume |
        Sort-Object {
            [int]$_.Name
        }
    )


$selectedVolumes =
    @()


foreach ($group in $volumeGroups) {

    $selected =
        @(
            $group.Group |
            Sort-Object `
                @{ Expression = "Score"; Descending = $true },
                @{ Expression = "Title"; Descending = $false }
        ) |
        Select-Object -First 1


    if ($selected) {

        $selectedVolumes +=
            $selected
    }
}


$selectedVolumes =
    @(
        $selectedVolumes |
        Sort-Object Volume
    )


Write-Host (
    "Selected volume count: {0}" -f
    $selectedVolumes.Count
)


# ==========================================
# Step 6
# Re-fetch all selected ASINs with GetItems
# ==========================================

Write-Host ""
Write-Host "Step 6: Re-fetching selected ASINs..."


$selectedAsins =
    @(
        $selectedVolumes |
        ForEach-Object {
            $_.ASIN
        }
    )


$getItemsResults =
    @()


for (
    $offset = 0;
    $offset -lt $selectedAsins.Count;
    $offset += 10
) {

    $endIndex =
        [Math]::Min(
            $offset + 9,
            $selectedAsins.Count - 1
        )


    $batch =
        @(
            $selectedAsins[
                $offset..$endIndex
            ]
        )


    Write-Host (
        "GetItems batch: {0}" -f
        ($batch -join ", ")
    )


    try {

        $batchItems =
            Invoke-MangaGetItems `
                -Asins $batch


        $getItemsResults +=
            @($batchItems)
    }
    catch {

        Write-Host "GetItems batch failed."
        Write-Host $_.Exception.Message
    }


    if (
        ($offset + 10) -lt
        $selectedAsins.Count
    ) {

        Start-Sleep `
            -Milliseconds 1100
    }
}


# ==========================================
# Step 7
# Compare SearchItems and GetItems
# ==========================================

Write-Host ""
Write-Host "Step 7: Comparing KU status..."


$comparison =
    @()


foreach ($selected in $selectedVolumes) {

    $getItem =
        @(
            $getItemsResults |
            Where-Object {
                $_.asin -eq
                $selected.ASIN
            }
        ) |
        Select-Object -First 1


    if ($getItem) {

        $getItemsKU =
            Test-KindleUnlimitedNode `
                -Item $getItem


        $getItemsPrice =
            Get-BuyBoxPrice `
                -Item $getItem


        $isMatch =
            (
                $selected.SearchItemsKU -eq
                $getItemsKU
            )


        $comparison +=
            [PSCustomObject]@{

                Volume =
                    $selected.Volume

                ASIN =
                    $selected.ASIN

                Title =
                    $selected.Title

                SearchItemsKU =
                    $selected.SearchItemsKU

                GetItemsKU =
                    $getItemsKU

                KUMatch =
                    $isMatch

                SearchItemsPrice =
                    $selected.SearchItemsPrice

                GetItemsPrice =
                    $getItemsPrice
            }
    }
    else {

        $comparison +=
            [PSCustomObject]@{

                Volume =
                    $selected.Volume

                ASIN =
                    $selected.ASIN

                Title =
                    $selected.Title

                SearchItemsKU =
                    $selected.SearchItemsKU

                GetItemsKU =
                    $null

                KUMatch =
                    $false

                SearchItemsPrice =
                    $selected.SearchItemsPrice

                GetItemsPrice =
                    ""
            }
    }
}


# ==========================================
# Comparison summary
# ==========================================

$matchedCount =
    @(
        $comparison |
        Where-Object {
            $_.KUMatch -eq $true
        }
    ).Count


$mismatchCount =
    @(
        $comparison |
        Where-Object {
            $_.KUMatch -ne $true
        }
    ).Count


$allMatch =
    $false


if (
    $comparison.Count -gt 0 -and
    $matchedCount -eq
    $comparison.Count
) {

    $allMatch =
        $true
}


$totalRequestCount =
    $script:tokenRequestCount +
    $script:searchItemsRequestCount +
    $script:getItemsRequestCount


# ==========================================
# Console output
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " KU COMPARISON RESULT"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "Series: {0}" -f
    $seriesTitle
)

Write-Host (
    "Search total result count: {0}" -f
    $totalResultCount
)

Write-Host (
    "Required search pages: {0}" -f
    $requiredPages
)

Write-Host (
    "Compared volumes: {0}" -f
    $comparison.Count
)

Write-Host (
    "KU matches: {0}" -f
    $matchedCount
)

Write-Host (
    "KU mismatches: {0}" -f
    $mismatchCount
)

Write-Host (
    "All KU results match: {0}" -f
    $allMatch
)

Write-Host ""


foreach ($item in $comparison) {

    Write-Host (
        "Volume {0}: SearchItems={1} | GetItems={2} | Match={3} | {4}" -f
        $item.Volume,
        $item.SearchItemsKU,
        $item.GetItemsKU,
        $item.KUMatch,
        $item.Title
    )
}


Write-Host ""
Write-Host "========================================"
Write-Host " API REQUEST SUMMARY"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "Token requests:       {0}" -f
    $script:tokenRequestCount
)

Write-Host (
    "SearchItems requests: {0}" -f
    $script:searchItemsRequestCount
)

Write-Host (
    "GetItems requests:    {0}" -f
    $script:getItemsRequestCount
)

Write-Host (
    "Total API requests:   {0}" -f
    $totalRequestCount
)


# ==========================================
# Summary object
# ==========================================

$summary =
    [PSCustomObject]@{

        SeedASIN =
            $seedAsin

        SeedTitle =
            $seedTitle

        SeriesTitle =
            $seriesTitle

        SearchTotalResultCount =
            $totalResultCount

        RequiredSearchPages =
            $requiredPages

        ComparedVolumeCount =
            $comparison.Count

        KUMatchCount =
            $matchedCount

        KUMismatchCount =
            $mismatchCount

        AllKUMatch =
            $allMatch

        TokenRequests =
            $script:tokenRequestCount

        SearchItemsRequests =
            $script:searchItemsRequestCount

        GetItemsRequests =
            $script:getItemsRequestCount

        TotalApiRequests =
            $totalRequestCount
    }


# ==========================================
# Output paths
# ==========================================

$outputPrefix =
    "manga-ku-compare-{0}-{1}" -f
    $seedAsin,
    $runId


$summaryPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-summary.json"


$comparisonPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-comparison.json"


$reportPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-report.txt"


# ==========================================
# UTF-8 BOM
# ==========================================

$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding($true)


# ==========================================
# Save JSON files
# ==========================================

$summaryJson =
    $summary |
    ConvertTo-Json -Depth 10


[System.IO.File]::WriteAllText(
    $summaryPath,
    $summaryJson,
    $utf8Bom
)


$comparisonJson =
    $comparison |
    ConvertTo-Json -Depth 10


[System.IO.File]::WriteAllText(
    $comparisonPath,
    $comparisonJson,
    $utf8Bom
)


# ==========================================
# Build report
# ==========================================

$reportLines =
    @()


$reportLines +=
    "========================================"

$reportLines +=
    " MANGA KU COMPARISON REPORT"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "SeedASIN: $seedAsin"

$reportLines +=
    "SeedTitle: $seedTitle"

$reportLines +=
    "SeriesTitle: $seriesTitle"

$reportLines +=
    ""

$reportLines +=
    "SearchTotalResultCount: $totalResultCount"

$reportLines +=
    "RequiredSearchPages: $requiredPages"

$reportLines +=
    ""

$reportLines +=
    "ComparedVolumeCount: $($comparison.Count)"

$reportLines +=
    "KUMatchCount: $matchedCount"

$reportLines +=
    "KUMismatchCount: $mismatchCount"

$reportLines +=
    "AllKUMatch: $allMatch"

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
    "GetItemsRequests: $($script:getItemsRequestCount)"

$reportLines +=
    "TotalApiRequests: $totalRequestCount"

$reportLines +=
    ""

$reportLines +=
    "========================================"

$reportLines +=
    " KU COMPARISON"

$reportLines +=
    "========================================"

$reportLines +=
    ""


foreach ($item in $comparison) {

    $reportLines +=
        (
            "Volume {0}: SearchItems={1} | GetItems={2} | Match={3} | {4}" -f
            $item.Volume,
            $item.SearchItemsKU,
            $item.GetItemsKU,
            $item.KUMatch,
            $item.Title
        )
}


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
Write-Host " Comparison complete"
Write-Host "========================================"
Write-Host ""

Write-Host "Summary:"
Write-Host $summaryPath

Write-Host ""

Write-Host "Comparison:"
Write-Host $comparisonPath

Write-Host ""

Write-Host "Report:"
Write-Host $reportPath

Write-Host ""