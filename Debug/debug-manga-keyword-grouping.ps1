param(
    [string]$Keyword = "戦争",
    [int]$MaxPages = 10
)

# ==========================================
# Manga Keyword Discovery Grouping Debug
# ==========================================
#
# Purpose:
# - Search KindleStore with "マンガ + user keyword".
# - Preserve Amazon Featured order.
# - Keep broad/interesting result variation.
# - Group only duplicate volumes/editions that appear to be
#   the same work for discovery purposes.
#
# IMPORTANT:
# - This file does NOT modify the stable manga detail parser.
# - Discovery-specific grouping is isolated in this debug file.
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


function ConvertTo-DiscoveryNormalizedText {

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


    $value =
        $Text.Normalize(
            [Text.NormalizationForm]::FormKC
        )


    $value =
        $value -replace
        '[\u3000\s]+',
        ' '


    $value =
        $value.Trim()


    return $value
}


function Remove-DiscoveryTrailingLabels {

    param(
        [string]$Text
    )


    $value =
        ConvertTo-DiscoveryNormalizedText `
            -Text $Text


    # Remove common trailing publisher/series labels.
    # This is intentionally limited to trailing parenthetical labels.
    while (
        $value -match
        '^(.*)\s+\([^()]*\)\s*$'
    ) {

        $candidate =
            $Matches[1].Trim()


        if (
            [string]::IsNullOrWhiteSpace(
                $candidate
            )
        ) {

            break
        }


        $value =
            $candidate
    }


    return $value
}


function Get-DiscoverySeriesTitle {

    param(
        [string]$Title
    )


    $normalized =
        ConvertTo-DiscoveryNormalizedText `
            -Text $Title


    if (
        [string]::IsNullOrWhiteSpace(
            $normalized
        )
    ) {

        return ""
    }


    # First use the stable parser as-is.
    $stable =
        Get-MangaSeriesTitle `
            -Title $Title


    $stableNormalized =
        ConvertTo-DiscoveryNormalizedText `
            -Text $stable


    # If the stable parser clearly removed the volume, use it.
    if (
        -not [string]::IsNullOrWhiteSpace(
            $stableNormalized
        ) -and
        $stableNormalized -ne
        $normalized
    ) {

        return $stableNormalized.TrimEnd(':').Trim()
    }


    $value =
        $normalized


    # ------------------------------------------
    # Discovery-only fallback 1
    #
    # Examples:
    # "Series 8 (Label)"
    # "Series11 (Label)"
    # "Series 12巻 (Label)"
    # ------------------------------------------

    if (
        $value -match
        '^(.*?)\s*(?<!\d)(\d{1,3})\s*(?:巻)?\s+(?:\([^()]*\)\s*)+$'
    ) {

        return $Matches[1].Trim().TrimEnd(':').Trim()
    }


    # ------------------------------------------
    # Discovery-only fallback 2
    #
    # Examples:
    # "Series: 2【bonus】 (Label)"
    # "Series 2【bonus】"
    # ------------------------------------------

    if (
        $value -match
        '^(.*?)\s*:?\s*(?<!\d)(\d{1,3})\s*(?:巻)?\s*(?:【[^】]*】\s*)+(?:\([^()]*\)\s*)*$'
    ) {

        return $Matches[1].Trim().TrimEnd(':').Trim()
    }


    # ------------------------------------------
    # Discovery-only fallback 3
    #
    # Examples:
    # "Series (Label) 6【bonus】"
    # "Series (Label) 7"
    # ------------------------------------------

    if (
        $value -match
        '^(.*?)\s*(?:\([^()]*\)\s*)+\s*(?<!\d)(\d{1,3})\s*(?:巻)?\s*(?:【[^】]*】\s*)*$'
    ) {

        $base =
            $Matches[1].Trim()


        return $base.TrimEnd(':').Trim()
    }


    # ------------------------------------------
    # Discovery-only fallback 4
    #
    # Remove trailing label first, then retry
    # a plain terminal volume number.
    # ------------------------------------------

    $withoutLabels =
        Remove-DiscoveryTrailingLabels `
            -Text $value


    if (
        $withoutLabels -match
        '^(.*?)\s*:?\s*(?<!\d)(\d{1,3})\s*(?:巻)?\s*$'
    ) {

        return $Matches[1].Trim().TrimEnd(':').Trim()
    }


    return $stableNormalized.TrimEnd(':').Trim()
}


function Get-DiscoveryAuthorKey {

    param(
        [array]$Authors
    )


    if (
        -not $Authors -or
        $Authors.Count -eq 0
    ) {

        return ""
    }


    return (
        @(
            $Authors |
            ForEach-Object {
                ConvertTo-DiscoveryNormalizedText `
                    -Text ([string]$_)
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace(
                    $_
                )
            } |
            Sort-Object -Unique
        ) -join "|"
    )
}


function Get-DiscoveryGroupKey {

    param(
        [string]$SeriesTitle,

        [array]$Authors
    )


    $titleKey =
        (
            ConvertTo-DiscoveryNormalizedText `
                -Text $SeriesTitle
        ).ToLowerInvariant()


    $authorKey =
        (
            Get-DiscoveryAuthorKey `
                -Authors $Authors
        ).ToLowerInvariant()


    # Author information helps avoid accidental merges of unrelated works
    # that happen to share a short/similar title.
    return (
        "{0}||{1}" -f
        $titleKey,
        $authorKey
    )
}


# ==========================================
# Search
# ==========================================

$searchKeyword =
    (
        "マンガ {0}" -f
        $Keyword
    ).Trim()


Write-Host ""
Write-Host "=========================================="
Write-Host "Manga Keyword Discovery Grouping Debug"
Write-Host "=========================================="
Write-Host ""
Write-Host (
    "User keyword: {0}" -f
    $Keyword
)
Write-Host (
    "Amazon keyword: {0}" -f
    $searchKeyword
)
Write-Host ""


$accessToken =
    Get-AmazonAccessToken `
        -Config $config


$resources =
    @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
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
            -Keyword $searchKeyword `
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


        $authors =
            @(
                Get-DebugAuthors `
                    -Item $item
            )


        $stableSeriesTitle =
            Get-MangaSeriesTitle `
                -Title $title


        $discoverySeriesTitle =
            Get-DiscoverySeriesTitle `
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
                    (
                        Get-MangaVolumeNumber `
                            -Title $title
                    )

                StableSeriesTitle =
                    $stableSeriesTitle

                DiscoverySeriesTitle =
                    $discoverySeriesTitle

                Authors =
                    $authors

                GroupKey =
                    (
                        Get-DiscoveryGroupKey `
                            -SeriesTitle $discoverySeriesTitle `
                            -Authors $authors
                    )
            }
    }
}


# ==========================================
# Group
# ==========================================

$seriesMap =
    [ordered]@{}


foreach (
    $row in $rawRows
) {

    $key =
        [string]$row.GroupKey


    if (
        -not $seriesMap.Contains(
            $key
        )
    ) {

        $seriesMap[$key] =
            [PSCustomObject]@{

                SeriesRank =
                    $seriesMap.Count + 1

                FirstSearchRank =
                    $row.SearchRank

                SeriesTitle =
                    $row.DiscoverySeriesTitle

                SeedASIN =
                    $row.ASIN

                SeedTitle =
                    $row.Title

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
            $seriesMap[$key]


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
            "manga-keyword-{0}-grouping-raw.json" -f
            $safeKeyword
        )


$seriesPath =
    Join-Path `
        $outputDirectory `
        (
            "manga-keyword-{0}-grouping-series.json" -f
            $safeKeyword
        )


$summaryPath =
    Join-Path `
        $outputDirectory `
        (
            "manga-keyword-{0}-grouping-summary.json" -f
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

        UserKeyword =
            $Keyword

        AmazonKeyword =
            $searchKeyword

        TotalResultCount =
            $totalResultCount

        RetrievedItems =
            $rawRows.Count

        UniqueSeries =
            $seriesRows.Count

        SearchItemsRequests =
            $requestCount

        TopSeries =
            @(
                $seriesRows |
                Select-Object -First 40
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
# Console
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Summary"
Write-Host "=========================================="

Write-Host (
    "Retrieved items: {0}" -f
    $rawRows.Count
)

Write-Host (
    "Unique series: {0}" -f
    $seriesRows.Count
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
Write-Host $rawPath
Write-Host $seriesPath
Write-Host $summaryPath
Write-Host ""
Write-Host "Done."