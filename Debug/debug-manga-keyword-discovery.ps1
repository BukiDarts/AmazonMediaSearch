param(
    [string]$Keyword = "戦争",
    [int]$MaxPages = 10
)

# ==========================================
# Manga Keyword Discovery Debug
# ==========================================
#
# Purpose:
# - Search the whole KindleStore by keyword.
# - Use Amazon Featured order.
# - Retrieve up to 100 item-level results.
# - Convert item-level results into series-level candidates.
# - Preserve the first appearance order of each series.
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


function Get-DebugAuthors {

    param(
        $Item
    )


    $authors =
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
                -not [string]::IsNullOrWhiteSpace(
                    $contributor.name
                )
            ) {

                $authors +=
                    [string]$contributor.name
            }
        }
    }


    return @(
        $authors |
        Sort-Object -Unique
    )
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


    if (
        -not $Item.browseNodeInfo -or
        $null -eq $Item.browseNodeInfo.browseNodes
    ) {

        return $null
    }


    return (
        (
            Get-DebugBrowseNodeText `
                -Item $Item
        ) -match
        'Kindle Unlimited'
    )
}


function Test-DebugLimitedFree {

    param(
        $Item
    )


    if (
        -not $Item.browseNodeInfo -or
        $null -eq $Item.browseNodeInfo.browseNodes
    ) {

        return $null
    }


    return (
        (
            Get-DebugBrowseNodeText `
                -Item $Item
        ) -match
        '\u671F\u9593\u9650\u5B9A\u7121\u6599'
    )
}


# ==========================================
# Authenticate
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Manga Keyword Discovery Debug"
Write-Host "=========================================="
Write-Host ""
Write-Host (
    "Keyword: {0}" -f
    $Keyword
)
Write-Host ""


$accessToken =
    Get-AmazonAccessToken `
        -Config $config


# ==========================================
# Search KindleStore
# ==========================================

$resources =
    @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "itemInfo.classifications",
        "browseNodeInfo.browseNodes",
        "offersV2.listings.isBuyBoxWinner",
        "offersV2.listings.price"
    )


$rawRows =
    @()


$totalResultCount =
    0


$requiredPages =
    1


$requestCount =
    0


$globalRank =
    0


for (
    $page = 1;
    $page -le $MaxPages;
    $page++
) {

    if (
        $page -gt $requiredPages
    ) {

        break
    }


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
        Invoke-AmazonSearch `
            -Keyword $Keyword `
            -SearchIndex "KindleStore" `
            -Resources $resources `
            -Config $config `
            -AccessToken $accessToken `
            -ItemCount 10 `
            -ItemPage $page `
            -SortBy "Featured"


    $requestCount++


    if (
        $response.searchResult -and
        $null -ne
        $response.searchResult.totalResultCount
    ) {

        $totalResultCount =
            [int]$response.searchResult.totalResultCount


        $requiredPages =
            [math]::Ceiling(
                $totalResultCount / 10
            )


        if (
            $requiredPages -gt $MaxPages
        ) {

            $requiredPages =
                $MaxPages
        }
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


    if (
        $items.Count -eq 0
    ) {

        break
    }


    foreach (
        $item in $items
    ) {

        $globalRank++


        $title =
            Get-DebugTitle `
                -Item $item


        $volume =
            Get-MangaVolumeNumber `
                -Title $title


        $seriesTitle =
            Get-MangaSeriesTitle `
                -Title $title


        $rawRows +=
            [PSCustomObject]@{

                SearchRank =
                    $globalRank

                Page =
                    $page

                ASIN =
                    [string]$item.asin

                Title =
                    $title

                Volume =
                    $volume

                SeriesTitle =
                    $seriesTitle

                Authors =
                    @(
                        Get-DebugAuthors `
                            -Item $item
                    )

                Price =
                    (
                        Get-DebugPrice `
                            -Item $item
                    )

                IsKindleUnlimited =
                    (
                        Test-DebugKindleUnlimited `
                            -Item $item
                    )

                IsLimitedFree =
                    (
                        Test-DebugLimitedFree `
                            -Item $item
                    )

                DetailPageURL =
                    [string]$item.detailPageURL
            }
    }
}


# ==========================================
# Build series-level candidates
# ==========================================

$seriesMap =
    [ordered]@{}


foreach (
    $row in $rawRows
) {

    $seriesKey =
        [string]$row.SeriesTitle


    if (
        [string]::IsNullOrWhiteSpace(
            $seriesKey
        )
    ) {

        $seriesKey =
            [string]$row.Title
    }


    if (
        -not $seriesMap.Contains(
            $seriesKey
        )
    ) {

        $seriesMap[$seriesKey] =
            [PSCustomObject]@{

                SeriesRank =
                    $seriesMap.Count + 1

                FirstSearchRank =
                    $row.SearchRank

                SeriesTitle =
                    $seriesKey

                SeedASIN =
                    $row.ASIN

                SeedTitle =
                    $row.Title

                SeedVolume =
                    $row.Volume

                SeedPrice =
                    $row.Price

                SeedKindleUnlimited =
                    $row.IsKindleUnlimited

                SeedLimitedFree =
                    $row.IsLimitedFree

                Authors =
                    @($row.Authors)

                MatchedItemCount =
                    1

                MatchedVolumes =
                    @(
                        $row.Volume
                    )

                MatchedASINs =
                    @(
                        $row.ASIN
                    )
            }
    }
    else {

        $series =
            $seriesMap[$seriesKey]


        $series.MatchedItemCount =
            [int]$series.MatchedItemCount + 1


        $series.MatchedVolumes =
            @(
                @($series.MatchedVolumes) +
                @($row.Volume) |
                Where-Object {
                    $null -ne $_
                } |
                Sort-Object -Unique
            )


        $series.MatchedASINs =
            @(
                @($series.MatchedASINs) +
                @($row.ASIN) |
                Sort-Object -Unique
            )
    }
}


$seriesRows =
    @(
        $seriesMap.Values
    )


# ==========================================
# Save outputs
# ==========================================

$safeKeyword =
    $Keyword -replace
    '[\\/:*?"<>|]',
    '_'


$rawPath =
    Join-Path `
        $outputDirectory `
        (
            "manga-keyword-{0}-raw.json" -f
            $safeKeyword
        )


$seriesPath =
    Join-Path `
        $outputDirectory `
        (
            "manga-keyword-{0}-series.json" -f
            $safeKeyword
        )


$summaryPath =
    Join-Path `
        $outputDirectory `
        (
            "manga-keyword-{0}-summary.json" -f
            $safeKeyword
        )


[System.IO.File]::WriteAllText(
    $rawPath,
    (
        $rawRows |
        ConvertTo-Json -Depth 30
    ),
    $utf8Bom
)


[System.IO.File]::WriteAllText(
    $seriesPath,
    (
        $seriesRows |
        ConvertTo-Json -Depth 30
    ),
    $utf8Bom
)


$summary =
    [PSCustomObject]@{

        Keyword =
            $Keyword

        TotalResultCount =
            $totalResultCount

        RetrievedItems =
            $rawRows.Count

        UniqueSeries =
            $seriesRows.Count

        SearchItemsRequests =
            $requestCount

        MaxPages =
            $MaxPages

        CompressionRatio =
            if ($rawRows.Count -gt 0) {
                [math]::Round(
                    (
                        $seriesRows.Count /
                        $rawRows.Count
                    ),
                    3
                )
            }
            else {
                0
            }

        TopSeries =
            @(
                $seriesRows |
                Select-Object -First 30
            )
    }


[System.IO.File]::WriteAllText(
    $summaryPath,
    (
        $summary |
        ConvertTo-Json -Depth 30
    ),
    $utf8Bom
)


# ==========================================
# Console summary
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Summary"
Write-Host "=========================================="

Write-Host (
    "TotalResultCount: {0}" -f
    $totalResultCount
)

Write-Host (
    "Retrieved items: {0}" -f
    $rawRows.Count
)

Write-Host (
    "Unique series: {0}" -f
    $seriesRows.Count
)

Write-Host (
    "SearchItems requests: {0}" -f
    $requestCount
)

Write-Host ""


$seriesRows |
    Select-Object `
        SeriesRank,
        FirstSearchRank,
        SeriesTitle,
        SeedVolume,
        MatchedItemCount,
        MatchedVolumes |
    Format-Table `
        -AutoSize `
        -Wrap


Write-Host ""
Write-Host "Output files:"
Write-Host $rawPath
Write-Host $seriesPath
Write-Host $summaryPath
Write-Host ""
Write-Host "Done."
