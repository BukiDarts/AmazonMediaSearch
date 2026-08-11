# ==========================================
# Manga Series Investigation Script
# ==========================================
#
# Purpose:
# - Start from one seed ASIN
# - Retrieve seed metadata with GetItems
# - Determine the manga series identity
# - Search only the required SearchItems pages
# - Select the best candidate for each volume
# - Use SearchItems metadata for price and KU status
# - Use GetItems only when BrowseNodeInfo is missing
# - Count API requests
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
    "images.primary.medium",
    "offersV2.listings.availability",
    "offersV2.listings.condition",
    "offersV2.listings.isBuyBoxWinner",
    "offersV2.listings.merchantInfo",
    "offersV2.listings.price",
    "offersV2.listings.type",
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
# Determine series title from seed
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
# Check whether KU metadata is available
# ==========================================

function Test-KUMetadataAvailable {

    param(
        $Item
    )


    if (-not $Item) {

        return $false
    }


    if (-not $Item.browseNodeInfo) {

        return $false
    }


    if (-not $Item.browseNodeInfo.browseNodes) {

        return $false
    }


    $browseNodes =
        @(
            $Item.browseNodeInfo.browseNodes
        )


    if ($browseNodes.Count -eq 0) {

        return $false
    }


    return $true
}


# ==========================================
# KU detector
# ==========================================

function Test-KindleUnlimitedNode {

    param(
        $Item
    )


    if (
        -not (
            Test-KUMetadataAvailable `
                -Item $Item
        )
    ) {

        return $null
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
# Convert volume numbers to ranges
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
                "$rangeStart"
        }
        else {

            $ranges +=
                (
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
            "$rangeStart"
    }
    else {

        $ranges +=
            (
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
# SearchItems helper
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


    if (
        $SeedAuthors.Count -gt 0
    ) {

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
# Retrieve seed ASIN
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
    Write-Host "Seed GetItems request failed."
    Write-Host $_.Exception.Message
    exit
}


if ($seedItems.Count -eq 0) {

    Write-Host ""
    Write-Host "Seed item was not returned."
    exit
}


$seedItem =
    $seedItems[0]


$seedTitle =
    $seedItem.itemInfo.title.displayValue


$seriesTitle =
    Get-SeriesTitleFromSeed `
        -Title $seedTitle


$seedVolume =
    Get-MangaVolumeNumber `
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
    "Seed volume: {0}" -f
    $seedVolume
)

Write-Host (
    "Seed label: {0}" -f
    $seedLabel
)

Write-Host (
    "Authors: {0}" -f
    ($seedAuthors -join ", ")
)


if (
    [string]::IsNullOrWhiteSpace(
        $seriesTitle
    )
) {

    Write-Host ""
    Write-Host "Series title could not be determined."
    exit
}


# ==========================================
# Step 2
# Retrieve first SearchItems page
# ==========================================

Write-Host ""
Write-Host "Step 2: Retrieving first search page..."


$searchItems =
    @()

$searchItemMap =
    @{}

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

    Write-Host ""
    Write-Host "First search request failed."
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

        $searchItemMap[$item.asin] =
            $item

        $searchItems +=
            $item
    }
}


# ==========================================
# Calculate required pages
# ==========================================

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
# Retrieve remaining pages
# ==========================================

Write-Host ""
Write-Host "Step 3: Retrieving remaining search pages..."


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


        if ($pageItems.Count -eq 0) {

            break
        }


        foreach ($item in $pageItems) {

            if (
                -not $seenAsins.ContainsKey(
                    $item.asin
                )
            ) {

                $seenAsins[$item.asin] =
                    $true

                $searchItemMap[$item.asin] =
                    $item

                $searchItems +=
                    $item
            }
        }
    }
}


Write-Host (
    "Retrieved search items: {0}" -f
    $searchItems.Count
)


# ==========================================
# Step 4
# Build candidate list
# ==========================================

Write-Host ""
Write-Host "Step 4: Building candidate list..."


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


    $kuMetadataAvailable =
        Test-KUMetadataAvailable `
            -Item $item


    $searchKU =
        Test-KindleUnlimitedNode `
            -Item $item


    $searchPrice =
        Get-BuyBoxPrice `
            -Item $item


    $candidates +=
        [PSCustomObject]@{

            Volume =
                [int]$volume

            ASIN =
                $item.asin

            Title =
                $title

            Label =
                (
                    Get-TrailingLabel `
                        -Title $title
                )

            Authors =
                @($candidateAuthors)

            Score =
                $score

            KUMetadataAvailable =
                $kuMetadataAvailable

            SearchItemsKU =
                $searchKU

            SearchItemsPrice =
                $searchPrice
        }
}


Write-Host (
    "Candidate count: {0}" -f
    $candidates.Count
)


# ==========================================
# Step 5
# Select best candidate per volume
# ==========================================

Write-Host ""
Write-Host "Step 5: Selecting best candidate per volume..."


$volumeGroups =
    @(
        $candidates |
        Group-Object Volume |
        Sort-Object {
            [int]$_.Name
        }
    )


$seriesIndex =
    @()


foreach ($group in $volumeGroups) {

    $selected =
        @(
            $group.Group |
            Sort-Object `
                @{
                    Expression = "Score"
                    Descending = $true
                },
                @{
                    Expression = "Title"
                    Descending = $false
                }
        ) |
        Select-Object -First 1


    if ($selected) {

        $seriesIndex +=
            $selected
    }
}


$seriesIndex =
    @(
        $seriesIndex |
        Sort-Object Volume
    )


Write-Host (
    "Selected volume count: {0}" -f
    $seriesIndex.Count
)


foreach ($selected in $seriesIndex) {

    Write-Host (
        "Selected volume {0}: score={1} | KU metadata={2} | {3}" -f
        $selected.Volume,
        $selected.Score,
        $selected.KUMetadataAvailable,
        $selected.Title
    )
}


# ==========================================
# Step 6
# Find items needing fallback GetItems
# ==========================================

Write-Host ""
Write-Host "Step 6: Checking metadata completeness..."


$fallbackAsins =
    @()

$fallbackReasonMap =
    @{}


foreach ($selected in $seriesIndex) {

    if (
        $selected.KUMetadataAvailable -eq
        $true
    ) {

        continue
    }


    # Reuse the seed GetItems response when possible.
    if (
        $selected.ASIN -eq
        $seedAsin
    ) {

        continue
    }


    if (
        $fallbackAsins -notcontains
        $selected.ASIN
    ) {

        $fallbackAsins +=
            $selected.ASIN

        $fallbackReasonMap[$selected.ASIN] =
            "Missing BrowseNodeInfo in SearchItems"
    }
}


Write-Host (
    "Fallback ASIN count: {0}" -f
    $fallbackAsins.Count
)


# ==========================================
# Step 7
# GetItems fallback only when required
# ==========================================

$fallbackItems =
    @()

$fallbackItemMap =
    @{}


if ($fallbackAsins.Count -gt 0) {

    Write-Host ""
    Write-Host "Step 7: Retrieving fallback metadata..."


    for (
        $offset = 0;
        $offset -lt $fallbackAsins.Count;
        $offset += 10
    ) {

        $endIndex =
            [Math]::Min(
                $offset + 9,
                $fallbackAsins.Count - 1
            )


        $batch =
            @(
                $fallbackAsins[
                    $offset..$endIndex
                ]
            )


        Write-Host (
            "Fallback GetItems batch: {0}" -f
            ($batch -join ", ")
        )


        try {

            $batchItems =
                Invoke-MangaGetItems `
                    -Asins $batch


            foreach ($item in $batchItems) {

                $fallbackItems +=
                    $item

                $fallbackItemMap[$item.asin] =
                    $item
            }
        }
        catch {

            Write-Host "Fallback GetItems batch failed."
            Write-Host $_.Exception.Message
        }


        if (
            ($offset + 10) -lt
            $fallbackAsins.Count
        ) {

            Start-Sleep `
                -Milliseconds 1100
        }
    }
}
else {

    Write-Host ""
    Write-Host "Step 7: No fallback GetItems requests required."
}


# ==========================================
# Step 8
# Build final volume data
# ==========================================

Write-Host ""
Write-Host "Step 8: Building final analysis..."


$finalVolumes =
    @()


foreach ($selected in $seriesIndex) {

    $source =
        "SearchItems"

    $isKU =
        $selected.SearchItemsKU

    $price =
        $selected.SearchItemsPrice


    # --------------------------------------
    # SearchItems metadata is complete.
    # --------------------------------------

    if (
        $selected.KUMetadataAvailable -eq
        $true
    ) {

        $source =
            "SearchItems"
    }


    # --------------------------------------
    # Seed metadata can be reused.
    # --------------------------------------

    elseif (
        $selected.ASIN -eq
        $seedAsin
    ) {

        $seedKU =
            Test-KindleUnlimitedNode `
                -Item $seedItem


        if ($null -ne $seedKU) {

            $isKU =
                $seedKU

            $source =
                "SeedGetItems"
        }
        else {

            $isKU =
                $null

            $source =
                "Unknown"
        }


        if (
            [string]::IsNullOrWhiteSpace(
                $price
            )
        ) {

            $price =
                Get-BuyBoxPrice `
                    -Item $seedItem
        }
    }


    # --------------------------------------
    # Use fallback GetItems response.
    # --------------------------------------

    elseif (
        $fallbackItemMap.ContainsKey(
            $selected.ASIN
        )
    ) {

        $fallbackItem =
            $fallbackItemMap[
                $selected.ASIN
            ]


        $fallbackKU =
            Test-KindleUnlimitedNode `
                -Item $fallbackItem


        if ($null -ne $fallbackKU) {

            $isKU =
                $fallbackKU

            $source =
                "GetItems"
        }
        else {

            $isKU =
                $null

            $source =
                "Unknown"
        }


        if (
            [string]::IsNullOrWhiteSpace(
                $price
            )
        ) {

            $price =
                Get-BuyBoxPrice `
                    -Item $fallbackItem
        }
    }


    # --------------------------------------
    # Metadata still unavailable.
    # --------------------------------------

    else {

        $isKU =
            $null

        $source =
            "Unknown"
    }


    $kuStatusText =
        "Unknown"


    if ($isKU -eq $true) {

        $kuStatusText =
            "KU"
    }
    elseif ($isKU -eq $false) {

        $kuStatusText =
            "NO"
    }


    $finalVolumes +=
        [PSCustomObject]@{

            Volume =
                $selected.Volume

            ASIN =
                $selected.ASIN

            Title =
                $selected.Title

            Label =
                $selected.Label

            CandidateScore =
                $selected.Score

            Price =
                $price

            IsKindleUnlimited =
                $isKU

            KindleUnlimitedStatus =
                $kuStatusText

            KUMetadataSource =
                $source

            DetailPageURL =
                $searchItemMap[
                    $selected.ASIN
                ].detailPageURL
        }
}


$finalVolumes =
    @(
        $finalVolumes |
        Sort-Object Volume
    )


# ==========================================
# Volume analysis
# ==========================================

$detectedVolumes =
    @(
        $finalVolumes |
        ForEach-Object {
            $_.Volume
        } |
        Sort-Object -Unique
    )


$kuVolumes =
    @(
        $finalVolumes |
        Where-Object {
            $_.IsKindleUnlimited -eq
            $true
        } |
        ForEach-Object {
            $_.Volume
        } |
        Sort-Object -Unique
    )


$nonKuVolumes =
    @(
        $finalVolumes |
        Where-Object {
            $_.IsKindleUnlimited -eq
            $false
        } |
        ForEach-Object {
            $_.Volume
        } |
        Sort-Object -Unique
    )


$unknownKuVolumes =
    @(
        $finalVolumes |
        Where-Object {
            $null -eq
            $_.IsKindleUnlimited
        } |
        ForEach-Object {
            $_.Volume
        } |
        Sort-Object -Unique
    )


$detectedRanges =
    ConvertTo-VolumeRanges `
        -Volumes $detectedVolumes


$kuRanges =
    ConvertTo-VolumeRanges `
        -Volumes $kuVolumes


$nonKuRanges =
    ConvertTo-VolumeRanges `
        -Volumes $nonKuVolumes


$unknownKuRanges =
    ConvertTo-VolumeRanges `
        -Volumes $unknownKuVolumes


# ==========================================
# Continuous range check
# ==========================================

$isContinuous =
    $false

$maxDetectedVolume =
    $null

$missingVolumes =
    @()


if ($detectedVolumes.Count -gt 0) {

    $maxDetectedVolume =
        (
            $detectedVolumes |
            Measure-Object -Maximum
        ).Maximum


    $expectedVolumes =
        @(
            1..$maxDetectedVolume
        )


    $missingVolumes =
        @(
            $expectedVolumes |
            Where-Object {
                $detectedVolumes -notcontains
                $_
            }
        )


    if ($missingVolumes.Count -eq 0) {

        $isContinuous =
            $true
    }
}


# ==========================================
# All-KU state
# ==========================================

$isAllDetectedVolumesKU =
    $null


if (
    $unknownKuVolumes.Count -eq 0 -and
    $detectedVolumes.Count -gt 0
) {

    if (
        $kuVolumes.Count -eq
        $detectedVolumes.Count
    ) {

        $isAllDetectedVolumesKU =
            $true
    }
    else {

        $isAllDetectedVolumesKU =
            $false
    }
}


# ==========================================
# Search truncation
# ==========================================

$isSearchTruncated =
    $false


if (
    $totalResultCount -gt
    $searchItems.Count
) {

    $isSearchTruncated =
        $true
}


# ==========================================
# Determine total-volume confidence
# ==========================================

$totalVolumeStatus =
    "Unknown"


if (
    -not $isSearchTruncated -and
    $isContinuous -and
    $detectedVolumes.Count -gt 0
) {

    $totalVolumeStatus =
        "Confirmed"
}
elseif (
    $isSearchTruncated -and
    $isContinuous -and
    $detectedVolumes.Count -gt 0
) {

    $totalVolumeStatus =
        "Probable"
}


# ==========================================
# Request counts
# ==========================================

$totalApiRequestCount =
    $script:tokenRequestCount +
    $script:searchItemsRequestCount +
    $script:getItemsRequestCount


$creatorsApiRequestCount =
    $script:searchItemsRequestCount +
    $script:getItemsRequestCount


# ==========================================
# Summary
# ==========================================

$summary =
    [PSCustomObject]@{

        SeedASIN =
            $seedAsin

        SeedTitle =
            $seedTitle

        SeriesTitle =
            $seriesTitle

        SeedLabel =
            $seedLabel

        SeedAuthors =
            @($seedAuthors)

        SearchTotalResultCount =
            $totalResultCount

        SearchRetrievedItems =
            $searchItems.Count

        RequiredSearchPages =
            $requiredPages

        IsSearchTruncated =
            $isSearchTruncated

        CandidateCount =
            $candidates.Count

        DetectedVolumeCount =
            $detectedVolumes.Count

        DetectedVolumes =
            @($detectedVolumes)

        DetectedRanges =
            $detectedRanges

        MaxDetectedVolume =
            $maxDetectedVolume

        TotalVolumeStatus =
            $totalVolumeStatus

        IsContinuousFromVolume1 =
            $isContinuous

        MissingVolumes =
            @($missingVolumes)

        KindleUnlimitedVolumeCount =
            $kuVolumes.Count

        KindleUnlimitedVolumes =
            @($kuVolumes)

        KindleUnlimitedRanges =
            $kuRanges

        NonKindleUnlimitedVolumeCount =
            $nonKuVolumes.Count

        NonKindleUnlimitedRanges =
            $nonKuRanges

        UnknownKindleUnlimitedVolumeCount =
            $unknownKuVolumes.Count

        UnknownKindleUnlimitedRanges =
            $unknownKuRanges

        IsAllDetectedVolumesKindleUnlimited =
            $isAllDetectedVolumesKU

        FallbackASINCount =
            $fallbackAsins.Count

        TokenRequests =
            $script:tokenRequestCount

        SearchItemsRequests =
            $script:searchItemsRequestCount

        GetItemsRequests =
            $script:getItemsRequestCount

        CreatorsApiRequests =
            $creatorsApiRequestCount

        TotalRequestsIncludingToken =
            $totalApiRequestCount
    }


# ==========================================
# Console output
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " SERIES RESULT"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "Series: {0}" -f
    $seriesTitle
)

Write-Host (
    "Search result count: {0}" -f
    $totalResultCount
)

Write-Host (
    "Required search pages: {0}" -f
    $requiredPages
)

Write-Host (
    "Retrieved search items: {0}" -f
    $searchItems.Count
)

Write-Host (
    "Search truncated: {0}" -f
    $isSearchTruncated
)

Write-Host (
    "Detected volume count: {0}" -f
    $detectedVolumes.Count
)

Write-Host (
    "Detected ranges: {0}" -f
    $detectedRanges
)

Write-Host (
    "Total volume status: {0}" -f
    $totalVolumeStatus
)

Write-Host (
    "KU volume count: {0}" -f
    $kuVolumes.Count
)

Write-Host (
    "KU ranges: {0}" -f
    $kuRanges
)

Write-Host (
    "Non-KU ranges: {0}" -f
    $nonKuRanges
)

Write-Host (
    "Unknown KU ranges: {0}" -f
    $unknownKuRanges
)

Write-Host (
    "Fallback ASIN count: {0}" -f
    $fallbackAsins.Count
)

Write-Host ""


foreach ($volumeItem in $finalVolumes) {

    Write-Host (
        "Volume {0}: {1} | Source={2} | Score={3} | {4} | {5}" -f
        $volumeItem.Volume,
        $volumeItem.KindleUnlimitedStatus,
        $volumeItem.KUMetadataSource,
        $volumeItem.CandidateScore,
        $volumeItem.Price,
        $volumeItem.Title
    )
}


# ==========================================
# API request summary
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " API REQUEST SUMMARY"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "Token requests:             {0}" -f
    $script:tokenRequestCount
)

Write-Host (
    "SearchItems requests:       {0}" -f
    $script:searchItemsRequestCount
)

Write-Host (
    "GetItems requests:          {0}" -f
    $script:getItemsRequestCount
)

Write-Host (
    "Creators API requests:      {0}" -f
    $creatorsApiRequestCount
)

Write-Host (
    "Total including token:      {0}" -f
    $totalApiRequestCount
)


# ==========================================
# Output paths
# ==========================================

$outputPrefix =
    "manga-series-{0}-{1}" -f
    $seedAsin,
    $runId


$summaryPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-summary.json"


$volumesPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-volumes.json"


$candidatesPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-candidates.json"


$reportPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-report.txt"


# ==========================================
# UTF-8 BOM
# ==========================================

$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding `
        -ArgumentList $true


# ==========================================
# Save summary
# ==========================================

$summaryJson =
    $summary |
    ConvertTo-Json -Depth 10


[System.IO.File]::WriteAllText(
    $summaryPath,
    $summaryJson,
    $utf8Bom
)


# ==========================================
# Save volumes
# ==========================================

$volumesJson =
    $finalVolumes |
    ConvertTo-Json -Depth 10


[System.IO.File]::WriteAllText(
    $volumesPath,
    $volumesJson,
    $utf8Bom
)


# ==========================================
# Save candidates
# ==========================================

$candidatesJson =
    $candidates |
    Sort-Object `
        Volume,
        @{
            Expression = "Score"
            Descending = $true
        } |
    ConvertTo-Json -Depth 10


[System.IO.File]::WriteAllText(
    $candidatesPath,
    $candidatesJson,
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
    " MANGA SERIES REPORT"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "RunId: $runId"

$reportLines +=
    "SeedASIN: $seedAsin"

$reportLines +=
    "SeedTitle: $seedTitle"

$reportLines +=
    "SeriesTitle: $seriesTitle"

$reportLines +=
    "SeedLabel: $seedLabel"

$reportLines +=
    "Authors: $($seedAuthors -join ', ')"

$reportLines +=
    ""

$reportLines +=
    "SearchTotalResultCount: $totalResultCount"

$reportLines +=
    "RequiredSearchPages: $requiredPages"

$reportLines +=
    "SearchRetrievedItems: $($searchItems.Count)"

$reportLines +=
    "SearchTruncated: $isSearchTruncated"

$reportLines +=
    "CandidateCount: $($candidates.Count)"

$reportLines +=
    ""

$reportLines +=
    "DetectedVolumeCount: $($detectedVolumes.Count)"

$reportLines +=
    "DetectedRanges: $detectedRanges"

$reportLines +=
    "MaxDetectedVolume: $maxDetectedVolume"

$reportLines +=
    "TotalVolumeStatus: $totalVolumeStatus"

$reportLines +=
    "ContinuousFromVolume1: $isContinuous"

$reportLines +=
    "MissingVolumes: $($missingVolumes -join ', ')"

$reportLines +=
    ""

$reportLines +=
    "KindleUnlimitedVolumeCount: $($kuVolumes.Count)"

$reportLines +=
    "KindleUnlimitedRanges: $kuRanges"

$reportLines +=
    "NonKindleUnlimitedRanges: $nonKuRanges"

$reportLines +=
    "UnknownKindleUnlimitedVolumeCount: $($unknownKuVolumes.Count)"

$reportLines +=
    "UnknownKindleUnlimitedRanges: $unknownKuRanges"

$reportLines +=
    "AllDetectedVolumesKU: $isAllDetectedVolumesKU"

$reportLines +=
    ""

$reportLines +=
    "FallbackASINCount: $($fallbackAsins.Count)"

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
    "CreatorsApiRequests: $creatorsApiRequestCount"

$reportLines +=
    "TotalRequestsIncludingToken: $totalApiRequestCount"

$reportLines +=
    ""

$reportLines +=
    "========================================"

$reportLines +=
    " SELECTED VOLUMES"

$reportLines +=
    "========================================"

$reportLines +=
    ""


foreach ($volumeItem in $finalVolumes) {

    $reportLines +=
        (
            "Volume {0}: {1} | Source={2} | Score={3} | {4} | {5} | {6}" -f
            $volumeItem.Volume,
            $volumeItem.KindleUnlimitedStatus,
            $volumeItem.KUMetadataSource,
            $volumeItem.CandidateScore,
            $volumeItem.Price,
            $volumeItem.Title,
            $volumeItem.ASIN
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
Write-Host " Investigation complete"
Write-Host "========================================"
Write-Host ""

Write-Host "Summary:"
Write-Host $summaryPath

Write-Host ""

Write-Host "Volumes:"
Write-Host $volumesPath

Write-Host ""

Write-Host "Candidates:"
Write-Host $candidatesPath

Write-Host ""

Write-Host "Report:"
Write-Host $reportPath

Write-Host ""