param(
    [string]$Keyword = "戦争",
    [int]$MaxPages = 10
)

# ==========================================
# Manga Keyword Classification Debug
# ==========================================
#
# Purpose:
# - Search the whole KindleStore by keyword.
# - Preserve Amazon Featured order.
# - Inspect classification and browse-node metadata.
# - Estimate whether each result is manga/comic content.
# - Keep the current series-title parser unchanged.
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


function Get-DebugBinding {

    param(
        $Item
    )


    if (
        $Item.itemInfo -and
        $Item.itemInfo.classifications -and
        $Item.itemInfo.classifications.binding
    ) {

        return [string]$Item.itemInfo.classifications.binding.displayValue
    }


    return ""
}


function Get-DebugProductGroup {

    param(
        $Item
    )


    if (
        $Item.itemInfo -and
        $Item.itemInfo.classifications -and
        $Item.itemInfo.classifications.productGroup
    ) {

        return [string]$Item.itemInfo.classifications.productGroup.displayValue
    }


    return ""
}


function Get-DebugBrowseNodeNames {

    param(
        $Item
    )


    $names =
        @()


    if (
        $Item.browseNodeInfo -and
        $Item.browseNodeInfo.browseNodes
    ) {

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
    }


    return @(
        $names |
        Sort-Object -Unique
    )
}


function Test-DebugMangaCandidate {

    param(
        [string]$Binding,

        [string]$ProductGroup,

        [array]$BrowseNodeNames,

        [string]$Title
    )


    $combined =
        (
            @(
                $Binding,
                $ProductGroup,
                $Title
            ) +
            @($BrowseNodeNames)
        ) -join " | "


    $positivePatterns =
        @(
            '\u30b3\u30df\u30c3\u30af',
            '\u30de\u30f3\u30ac',
            '\u6f2b\u753b',
            'COMIC',
            'Comics',
            '\u30e4\u30f3\u30b0\u30b8\u30e3\u30f3\u30d7\u30b3\u30df\u30c3\u30af\u30b9',
            '\u30e2\u30fc\u30cb\u30f3\u30b0\u30b3\u30df\u30c3\u30af\u30b9',
            '\u89d2\u5ddd\u30b3\u30df\u30c3\u30af\u30b9',
            '\u30d3\u30c3\u30b0\u30b3\u30df\u30c3\u30af\u30b9',
            '\u30b8\u30e3\u30f3\u30d7\u30b3\u30df\u30c3\u30af\u30b9',
            '\u30ac\u30f3\u30ac\u30f3\u30b3\u30df\u30c3\u30af\u30b9',
            '\u30e9\u30a4\u30c9\u30b3\u30df\u30c3\u30af\u30b9'
        )


    foreach (
        $pattern in $positivePatterns
    ) {

        if (
            $combined -match
            $pattern
        ) {

            return $true
        }
    }


    return $false
}


# ==========================================
# Authenticate
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Manga Keyword Classification Debug"
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
        "browseNodeInfo.browseNodes"
    )


$rows =
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


        $binding =
            Get-DebugBinding `
                -Item $item


        $productGroup =
            Get-DebugProductGroup `
                -Item $item


        $browseNodeNames =
            @(
                Get-DebugBrowseNodeNames `
                    -Item $item
            )


        $isMangaCandidate =
            Test-DebugMangaCandidate `
                -Binding $binding `
                -ProductGroup $productGroup `
                -BrowseNodeNames $browseNodeNames `
                -Title $title


        $rows +=
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
                    (
                        Get-MangaVolumeNumber `
                            -Title $title
                    )

                SeriesTitle =
                    (
                        Get-MangaSeriesTitle `
                            -Title $title
                    )

                Binding =
                    $binding

                ProductGroup =
                    $productGroup

                BrowseNodeNames =
                    @($browseNodeNames)

                IsMangaCandidate =
                    $isMangaCandidate
            }
    }
}


# ==========================================
# Manga-only series grouping
# ==========================================

$mangaRows =
    @(
        $rows |
        Where-Object {
            $_.IsMangaCandidate -eq
            $true
        }
    )


$seriesMap =
    [ordered]@{}


foreach (
    $row in $mangaRows
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

                MatchedItemCount =
                    1

                MatchedVolumes =
                    @(
                        $row.Volume
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


$metadataPath =
    Join-Path `
        $outputDirectory `
        (
            "manga-keyword-{0}-metadata.json" -f
            $safeKeyword
        )


$mangaOnlyPath =
    Join-Path `
        $outputDirectory `
        (
            "manga-keyword-{0}-manga-only.json" -f
            $safeKeyword
        )


$summaryPath =
    Join-Path `
        $outputDirectory `
        (
            "manga-keyword-{0}-classification-summary.json" -f
            $safeKeyword
        )


[System.IO.File]::WriteAllText(
    $metadataPath,
    (
        $rows |
        ConvertTo-Json -Depth 40
    ),
    $utf8Bom
)


[System.IO.File]::WriteAllText(
    $mangaOnlyPath,
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
            $rows.Count

        MangaCandidateItems =
            $mangaRows.Count

        MangaCandidateSeries =
            $seriesRows.Count

        SearchItemsRequests =
            $requestCount

        TopMangaSeries =
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
    $rows.Count
)

Write-Host (
    "Manga candidate items: {0}" -f
    $mangaRows.Count
)

Write-Host (
    "Manga candidate series: {0}" -f
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
        MatchedItemCount,
        MatchedVolumes |
    Format-Table `
        -AutoSize `
        -Wrap


Write-Host ""
Write-Host "Output files:"
Write-Host $metadataPath
Write-Host $mangaOnlyPath
Write-Host $summaryPath
Write-Host ""
Write-Host "Done."