# ==========================================
# Recommended Manga -> Series Debug
# ==========================================
#
# Purpose:
# 1. Retrieve all recommended manga candidates
#    from the recommended manga BrowseNode.
# 2. Preserve the SearchItems return order.
# 3. Pass the JoJo Part 7 seed ASIN to the
#    existing Get-MangaSeries service.
#
# This file does not modify the main app.
# ==========================================


$projectRoot =
    Split-Path $PSScriptRoot -Parent


# ==========================================
# Load project functions
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"
. "$projectRoot\Core\Invoke-AmazonSearch.ps1"
. "$projectRoot\Core\Invoke-AmazonGetItems.ps1"

. "$projectRoot\Manga\Services\Get-MangaSeries.ps1"


# ==========================================
# Config
# ==========================================

$configPath =
    Join-Path `
        $projectRoot `
        "config.json"


if (
    -not (
        Test-Path $configPath
    )
) {
    throw "config.json not found."
}


$config =
    Get-Content `
        $configPath `
        -Raw |
    ConvertFrom-Json


# ==========================================
# Output
# ==========================================

$outputDirectory =
    Join-Path `
        $PSScriptRoot `
        "Output"


if (
    -not (
        Test-Path $outputDirectory
    )
) {
    New-Item `
        -ItemType Directory `
        -Path $outputDirectory `
        -Force |
    Out-Null
}


$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding `
        -ArgumentList $true


# ==========================================
# Settings
# ==========================================

$recommendedBrowseNodeId =
    "10473732051"


$recommendedKeyword =
    "マンガ"


$jojoSeedASIN =
    "B009PL8688"


$resources =
    @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "itemInfo.classifications",
        "images.primary.medium",
        "browseNodeInfo.browseNodes",
        "offersV2.listings.isBuyBoxWinner",
        "offersV2.listings.price"
    )


# ==========================================
# Authenticate
# ==========================================

Write-Host "Getting access token..."


$accessToken =
    Get-AmazonAccessToken `
        -Config $config


Write-Host "Access token acquired."


# ==========================================
# Debug SearchItems with BrowseNodeId
# ==========================================

function Invoke-DebugRecommendedSearch {

    param(
        [Parameter(Mandatory)]
        [string]$Keyword,

        [Parameter(Mandatory)]
        [string]$BrowseNodeId,

        [Parameter(Mandatory)]
        [array]$Resources,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [int]$ItemPage = 1,

        [int]$ItemCount = 10,

        [string]$SortBy = "Featured",

        [int]$MaxRetries = 3
    )


    $body =
        @{
            partnerTag   = $Config.PartnerTag
            marketplace  = $Config.Marketplace
            searchIndex  = "KindleStore"
            keywords     = $Keyword
            browseNodeId = $BrowseNodeId
            itemCount    = $ItemCount
            itemPage     = $ItemPage
            sortBy       = $SortBy
            resources    = $Resources
        }


    $json =
        $body |
        ConvertTo-Json -Depth 20


    $bytes =
        [System.Text.Encoding]::UTF8.GetBytes(
            $json
        )


    $headers =
        @{
            Authorization   = "Bearer $AccessToken"
            "x-marketplace" = $Config.Marketplace
        }


    $parameters =
        @{
            Uri         = $Config.SearchUrl
            Method      = "Post"
            Headers     = $headers
            ContentType = "application/json; charset=utf-8"
            Body        = $bytes
        }


    $attempt =
        0


    while ($true) {

        try {

            $webResponse =
                Invoke-WebRequest `
                    @parameters `
                    -UseBasicParsing


            break
        }
        catch {

            $attempt++


            $statusCode =
                $null


            if (
                $_.Exception.Response
            ) {

                try {

                    $statusCode =
                        [int]$_.Exception.Response.StatusCode
                }
                catch {

                    $statusCode =
                        $null
                }
            }


            if (
                $statusCode -eq 429 -and
                $attempt -le $MaxRetries
            ) {

                $waitSeconds =
                    [math]::Pow(
                        2,
                        $attempt - 1
                    )


                Write-Host (
                    "Rate limited. Retry {0}/{1} after {2} second(s)." -f
                    $attempt,
                    $MaxRetries,
                    $waitSeconds
                )


                Start-Sleep `
                    -Seconds $waitSeconds


                continue
            }


            throw
        }
    }


    $responseBytes =
        $webResponse.RawContentStream.ToArray()


    $responseText =
        [System.Text.Encoding]::UTF8.GetString(
            $responseBytes
        )


    return (
        $responseText |
        ConvertFrom-Json
    )
}


# ==========================================
# Helpers
# ==========================================

function Get-DebugTitle {

    param(
        $Item
    )


    if (
        $Item.itemInfo -and
        $Item.itemInfo.title
    ) {

        return [string]$Item.itemInfo.title.displayValue
    }


    return ""
}


function Get-DebugPrice {

    param(
        $Item
    )


    if (
        -not $Item.offersV2 -or
        -not $Item.offersV2.listings
    ) {

        return ""
    }


    $listing =
        @(
            $Item.offersV2.listings |
            Where-Object {
                $_.isBuyBoxWinner -eq $true
            }
        ) |
        Select-Object -First 1


    if (-not $listing) {

        $listing =
            @(
                $Item.offersV2.listings
            ) |
            Select-Object -First 1
    }


    if (
        $listing -and
        $listing.price -and
        $listing.price.money
    ) {

        return [string]$listing.price.money.displayAmount
    }


    return ""
}


function Get-DebugBrowseNodeText {

    param(
        $Item
    )


    if (
        -not $Item.browseNodeInfo -or
        -not $Item.browseNodeInfo.browseNodes
    ) {

        return ""
    }


    $names =
        @()


    foreach (
        $node in
        $Item.browseNodeInfo.browseNodes
    ) {

        if (
            -not [string]::IsNullOrWhiteSpace(
                $node.contextFreeName
            )
        ) {

            $names +=
                [string]$node.contextFreeName
        }


        if (
            -not [string]::IsNullOrWhiteSpace(
                $node.displayName
            )
        ) {

            $names +=
                [string]$node.displayName
        }
    }


    return (
        @(
            $names |
            Sort-Object -Unique
        ) -join " | "
    )
}


function Test-DebugKindleUnlimited {

    param(
        $Item
    )


    $text =
        Get-DebugBrowseNodeText `
            -Item $Item


    if (
        [string]::IsNullOrWhiteSpace(
            $text
        )
    ) {

        return $null
    }


    return (
        $text -match
        'Kindle Unlimited'
    )
}


function Test-DebugLimitedFree {

    param(
        $Item
    )


    $text =
        Get-DebugBrowseNodeText `
            -Item $Item


    if (
        [string]::IsNullOrWhiteSpace(
            $text
        )
    ) {

        return $null
    }


    return (
        $text -match
        '\u671F\u9593\u9650\u5B9A\u7121\u6599'
    )
}


# ==========================================
# Retrieve all recommended manga
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Recommended Manga"
Write-Host "=========================================="


$recommendedItems =
    @()


$totalResultCount =
    0


$page =
    1


$order =
    0


while ($true) {

    if (
        $page -gt 1
    ) {

        Start-Sleep `
            -Milliseconds 1100
    }


    Write-Host (
        "Requesting page {0}..." -f
        $page
    )


    $response =
        Invoke-DebugRecommendedSearch `
            -Keyword $recommendedKeyword `
            -BrowseNodeId $recommendedBrowseNodeId `
            -Resources $resources `
            -Config $config `
            -AccessToken $accessToken `
            -ItemPage $page `
            -ItemCount 10 `
            -SortBy "Featured"


    if (
        $response.searchResult -and
        $null -ne
        $response.searchResult.totalResultCount
    ) {

        $totalResultCount =
            [int]$response.searchResult.totalResultCount
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


    foreach (
        $item in $items
    ) {

        $order++


        $recommendedItems +=
            [PSCustomObject]@{

                Order =
                    $order

                Page =
                    $page

                ASIN =
                    [string]$item.asin

                Title =
                    (
                        Get-DebugTitle `
                            -Item $item
                    )

                Price =
                    (
                        Get-DebugPrice `
                            -Item $item
                    )

                KindleUnlimited =
                    (
                        Test-DebugKindleUnlimited `
                            -Item $item
                    )

                LimitedFree =
                    (
                        Test-DebugLimitedFree `
                            -Item $item
                    )

                DetailPageURL =
                    [string]$item.detailPageURL
            }
    }


    if (
        $recommendedItems.Count -ge
        $totalResultCount
    ) {

        break
    }


    if (
        $page -ge 10
    ) {

        break
    }


    if (
        $items.Count -eq 0
    ) {

        break
    }


    $page++
}


# ==========================================
# Deduplicate while preserving first order
# ==========================================

$seenAsins =
    @{}


$uniqueRecommendedItems =
    @()


foreach (
    $item in $recommendedItems
) {

    if (
        [string]::IsNullOrWhiteSpace(
            $item.ASIN
        )
    ) {

        continue
    }


    if (
        $seenAsins.ContainsKey(
            $item.ASIN
        )
    ) {

        continue
    }


    $seenAsins[$item.ASIN] =
        $true


    $uniqueRecommendedItems +=
        $item
}


# ==========================================
# Save recommended list
# ==========================================

$recommendedPath =
    Join-Path `
        $outputDirectory `
        "manga-recommended-full.json"


[System.IO.File]::WriteAllText(
    $recommendedPath,
    (
        $uniqueRecommendedItems |
        ConvertTo-Json -Depth 30
    ),
    $utf8Bom
)


# ==========================================
# Console recommended summary
# ==========================================

Write-Host ""
Write-Host (
    "TotalResultCount: {0}" -f
    $totalResultCount
)

Write-Host (
    "Retrieved items: {0}" -f
    $recommendedItems.Count
)

Write-Host (
    "Unique ASINs: {0}" -f
    $uniqueRecommendedItems.Count
)

Write-Host ""


$uniqueRecommendedItems |
    Select-Object `
        Order,
        ASIN,
        Title,
        Price,
        KindleUnlimited,
        LimitedFree |
    Format-Table `
        -AutoSize `
        -Wrap


# ==========================================
# Find JoJo in recommended list
# ==========================================

$jojoRecommendedItem =
    @(
        $uniqueRecommendedItems |
        Where-Object {
            $_.ASIN -eq
            $jojoSeedASIN
        }
    ) |
    Select-Object -First 1


Write-Host ""
Write-Host "=========================================="
Write-Host "JoJo Recommended Candidate"
Write-Host "=========================================="


if (
    $jojoRecommendedItem
) {

    $jojoRecommendedItem |
        Format-List
}
else {

    Write-Host "JoJo seed ASIN was not found in the current recommended list."
}


# ==========================================
# Existing manga series analysis
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "JoJo Series Analysis"
Write-Host "=========================================="


Write-Host (
    "Seed ASIN: {0}" -f
    $jojoSeedASIN
)


$jojoSeries =
    Get-MangaSeries `
        -SeedASIN $jojoSeedASIN `
        -Config $config `
        -AccessToken $accessToken


# ==========================================
# Save JoJo result
# ==========================================

$jojoSeriesPath =
    Join-Path `
        $outputDirectory `
        "manga-recommended-jojo-series.json"


[System.IO.File]::WriteAllText(
    $jojoSeriesPath,
    (
        $jojoSeries |
        ConvertTo-Json -Depth 50
    ),
    $utf8Bom
)


# ==========================================
# JoJo summary
# ==========================================

Write-Host ""

Write-Host (
    "Series title: {0}" -f
    $jojoSeries.SeriesTitle
)

Write-Host (
    "Volume count: {0}" -f
    $jojoSeries.VolumeCount
)

Write-Host (
    "Total status: {0}" -f
    $jojoSeries.TotalVolumeStatus
)

Write-Host (
    "KU volume count: {0}" -f
    $jojoSeries.KUVolumeCount
)

Write-Host (
    "KU ranges: {0}" -f
    (
        $jojoSeries.KURanges -join ", "
    )
)

Write-Host (
    "Limited-free volume count: {0}" -f
    $jojoSeries.LimitedFreeVolumeCount
)

Write-Host (
    "Limited-free ranges: {0}" -f
    (
        $jojoSeries.LimitedFreeRanges -join ", "
    )
)

Write-Host ""

Write-Host (
    "Creators API requests: {0}" -f
    $jojoSeries.CreatorsApiRequests
)

Write-Host ""


# ==========================================
# JoJo volume table
# ==========================================

$jojoSeries.Volumes |
    Select-Object `
        VolumeNumber,
        ASIN,
        Title,
        Price,
        IsKindleUnlimited,
        IsLimitedFree |
    Format-Table `
        -AutoSize `
        -Wrap


# ==========================================
# Done
# ==========================================

Write-Host ""
Write-Host "Output files:"
Write-Host $recommendedPath
Write-Host $jojoSeriesPath
Write-Host ""
Write-Host "Done."