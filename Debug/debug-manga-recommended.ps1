# ==========================================
# Amazon Recommended Manga Debug
# ==========================================
#
# Purpose:
# - Test the Amazon recommended manga BrowseNode
# - Compare several broad search keywords
# - Inspect ASIN, title, price, KU metadata,
#   limited-free metadata and sales rank
#
# Recommended manga BrowseNode:
#   10473732051
#
# This file does not modify the main application.
# ==========================================


$projectRoot =
    Split-Path $PSScriptRoot -Parent


# ==========================================
# Load core authentication
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"


# ==========================================
# Load config
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
# Output directory
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


# ==========================================
# Settings
# ==========================================

$recommendedBrowseNodeId =
    "10473732051"


# SearchItems requires at least one search term.
# These are intentionally broad so that we can
# compare which query works best inside the node.

$testKeywords =
    @(
        "1",
        "マンガ",
        "コミック"
    )


$resources =
    @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "itemInfo.classifications",
        "images.primary.medium",
        "browseNodeInfo.browseNodes",
        "browseNodeInfo.browseNodes.salesRank",
        "browseNodeInfo.websiteSalesRank",
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
# Debug-only SearchItems
# Supports BrowseNodeId without modifying Core.
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


    return (
        @(
            $authors |
            Sort-Object -Unique
        ) -join ", "
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


function Test-DebugKindleUnlimited {

    param(
        $Item
    )


    $names =
        @(
            Get-DebugBrowseNodeNames `
                -Item $Item
        )


    foreach ($name in $names) {

        if (
            $name -match
            'Kindle Unlimited'
        ) {

            return $true
        }
    }


    return $false
}


function Test-DebugLimitedFree {

    param(
        $Item
    )


    $names =
        @(
            Get-DebugBrowseNodeNames `
                -Item $Item
        )


    foreach ($name in $names) {

        if (
            $name -match
            '期間限定無料'
        ) {

            return $true
        }
    }


    return $false
}


function Get-DebugRecommendedNodeRank {

    param(
        $Item,

        [string]$BrowseNodeId
    )


    if (
        -not $Item.browseNodeInfo -or
        -not $Item.browseNodeInfo.browseNodes
    ) {

        return $null
    }


    $node =
        @(
            $Item.browseNodeInfo.browseNodes |
            Where-Object {
                [string]$_.id -eq
                $BrowseNodeId
            }
        ) |
        Select-Object -First 1


    if (
        $node -and
        $null -ne $node.salesRank
    ) {

        return [int]$node.salesRank
    }


    return $null
}


function Get-DebugWebsiteSalesRank {

    param(
        $Item
    )


    if (
        $Item.browseNodeInfo -and
        $Item.browseNodeInfo.websiteSalesRank -and
        $null -ne
        $Item.browseNodeInfo.websiteSalesRank.salesRank
    ) {

        return [int]$Item.browseNodeInfo.websiteSalesRank.salesRank
    }


    return $null
}


# ==========================================
# Run test searches
# ==========================================

$allResults =
    @()


$rawResponses =
    @()


foreach (
    $keyword in $testKeywords
) {

    Write-Host ""
    Write-Host (
        "Testing keyword: {0}" -f
        $keyword
    )


    # Two pages per keyword are enough for the
    # first diagnostic pass.

    for (
        $page = 1;
        $page -le 2;
        $page++
    ) {

        if (
            $page -gt 1
        ) {

            Start-Sleep `
                -Milliseconds 1100
        }


        Write-Host (
            "  Page {0}..." -f
            $page
        )


        $response =
            Invoke-DebugRecommendedSearch `
                -Keyword $keyword `
                -BrowseNodeId $recommendedBrowseNodeId `
                -Resources $resources `
                -Config $config `
                -AccessToken $accessToken `
                -ItemPage $page `
                -ItemCount 10 `
                -SortBy "Featured"


        $rawResponses +=
            [PSCustomObject]@{

                Keyword =
                    $keyword

                Page =
                    $page

                Response =
                    $response
            }


        $totalResultCount =
            $null


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

            $browseNodeNames =
                @(
                    Get-DebugBrowseNodeNames `
                        -Item $item
                )


            $hasRecommendedNode =
                $false


            if (
                $item.browseNodeInfo -and
                $item.browseNodeInfo.browseNodes
            ) {

                $hasRecommendedNode =
                    (
                        @(
                            $item.browseNodeInfo.browseNodes |
                            Where-Object {
                                [string]$_.id -eq
                                $recommendedBrowseNodeId
                            }
                        ).Count -gt 0
                    )
            }


            $allResults +=
                [PSCustomObject]@{

                    Keyword =
                        $keyword

                    Page =
                        $page

                    TotalResultCount =
                        $totalResultCount

                    ASIN =
                        $item.asin

                    Title =
                        (
                            Get-DebugTitle `
                                -Item $item
                        )

                    Authors =
                        (
                            Get-DebugAuthors `
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

                    HasRecommendedNode =
                        $hasRecommendedNode

                    RecommendedNodeRank =
                        (
                            Get-DebugRecommendedNodeRank `
                                -Item $item `
                                -BrowseNodeId $recommendedBrowseNodeId
                        )

                    WebsiteSalesRank =
                        (
                            Get-DebugWebsiteSalesRank `
                                -Item $item
                        )

                    BrowseNodes =
                        (
                            $browseNodeNames -join " | "
                        )

                    DetailPageURL =
                        $item.detailPageURL
                }
        }
    }


    Start-Sleep `
        -Milliseconds 1100
}


# ==========================================
# Deduplicate ASINs for discovery summary
# ==========================================

$uniqueResults =
    @(
        $allResults |
        Sort-Object `
            ASIN,
            Keyword |
        Group-Object ASIN |
        ForEach-Object {

            $first =
                $_.Group |
                Select-Object -First 1


            $keywords =
                @(
                    $_.Group.Keyword |
                    Sort-Object -Unique
                )


            [PSCustomObject]@{

                ASIN =
                    $first.ASIN

                Title =
                    $first.Title

                Authors =
                    $first.Authors

                Price =
                    $first.Price

                KindleUnlimited =
                    $first.KindleUnlimited

                LimitedFree =
                    $first.LimitedFree

                HasRecommendedNode =
                    $first.HasRecommendedNode

                RecommendedNodeRank =
                    $first.RecommendedNodeRank

                WebsiteSalesRank =
                    $first.WebsiteSalesRank

                MatchedKeywords =
                    (
                        $keywords -join ", "
                    )

                DetailPageURL =
                    $first.DetailPageURL
            }
        }
    )


# ==========================================
# Keyword comparison summary
# ==========================================

$keywordSummary =
    @()


foreach (
    $keyword in $testKeywords
) {

    $keywordRows =
        @(
            $allResults |
            Where-Object {
                $_.Keyword -eq
                $keyword
            }
        )


    $uniqueAsins =
        @(
            $keywordRows.ASIN |
            Sort-Object -Unique
        )


    $totalResultCount =
        $null


    if (
        $keywordRows.Count -gt 0
    ) {

        $totalResultCount =
            $keywordRows[0].TotalResultCount
    }


    $keywordSummary +=
        [PSCustomObject]@{

            Keyword =
                $keyword

            TotalResultCount =
                $totalResultCount

            RetrievedUniqueASINs =
                $uniqueAsins.Count

            KUCount =
                @(
                    $keywordRows |
                    Where-Object {
                        $_.KindleUnlimited -eq
                        $true
                    } |
                    Select-Object -ExpandProperty ASIN -Unique
                ).Count

            LimitedFreeCount =
                @(
                    $keywordRows |
                    Where-Object {
                        $_.LimitedFree -eq
                        $true
                    } |
                    Select-Object -ExpandProperty ASIN -Unique
                ).Count
        }
}


# ==========================================
# Save files
# ==========================================

$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding `
        -ArgumentList $true


$rawPath =
    Join-Path `
        $outputDirectory `
        "manga-recommended-raw.json"


$resultsPath =
    Join-Path `
        $outputDirectory `
        "manga-recommended-results.json"


$uniquePath =
    Join-Path `
        $outputDirectory `
        "manga-recommended-unique.json"


$keywordSummaryPath =
    Join-Path `
        $outputDirectory `
        "manga-recommended-keywords.json"


[System.IO.File]::WriteAllText(
    $rawPath,
    (
        $rawResponses |
        ConvertTo-Json -Depth 50
    ),
    $utf8Bom
)


[System.IO.File]::WriteAllText(
    $resultsPath,
    (
        $allResults |
        ConvertTo-Json -Depth 30
    ),
    $utf8Bom
)


[System.IO.File]::WriteAllText(
    $uniquePath,
    (
        $uniqueResults |
        ConvertTo-Json -Depth 30
    ),
    $utf8Bom
)


[System.IO.File]::WriteAllText(
    $keywordSummaryPath,
    (
        $keywordSummary |
        ConvertTo-Json -Depth 20
    ),
    $utf8Bom
)


# ==========================================
# Console output
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Recommended Manga Keyword Test"
Write-Host "=========================================="
Write-Host ""


$keywordSummary |
    Format-Table `
        -AutoSize


Write-Host ""
Write-Host "=========================================="
Write-Host "Unique Recommended Manga Candidates"
Write-Host "=========================================="
Write-Host ""


$uniqueResults |
    Select-Object `
        ASIN,
        Title,
        Price,
        KindleUnlimited,
        LimitedFree,
        MatchedKeywords |
    Format-Table `
        -AutoSize `
        -Wrap


Write-Host ""
Write-Host "Unique ASIN count: $($uniqueResults.Count)"
Write-Host ""

Write-Host "Output files:"
Write-Host $keywordSummaryPath
Write-Host $uniquePath
Write-Host $resultsPath
Write-Host $rawPath
Write-Host ""
Write-Host "Done."