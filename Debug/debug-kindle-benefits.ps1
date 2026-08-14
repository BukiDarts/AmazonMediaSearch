param(
    [string]$Keyword = "村上龍",
    [int]$MaxPages = 3
)

# ==========================================
# Kindle Benefits Debug
# ==========================================
#
# Purpose:
# - Search KindleStore by keyword.
# - Inspect BrowseNodeInfo.
# - Infer Kindle Unlimited eligibility.
# - Infer limited-time free status.
# - Keep the current purchase price as factual data.
#
# This debug file does not modify the main app.
# ==========================================


$projectRoot =
    Split-Path $PSScriptRoot -Parent


# ==========================================
# Load project functions
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"
. "$projectRoot\Core\Invoke-AmazonSearch.ps1"


# ==========================================
# Config
# ==========================================

$configPath =
    Join-Path `
        $projectRoot `
        "config.json"


$outputDirectory =
    Join-Path `
        $PSScriptRoot `
        "Output"


if (
    -not (
        Test-Path $configPath
    )
) {

    throw "config.json not found."
}


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


$config =
    Get-Content `
        $configPath `
        -Raw |
    ConvertFrom-Json


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

        return (
            [string]$Item.itemInfo.title.displayValue
        )
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
                [string]$contributor.roleType -eq
                "author"
            ) {

                $authors +=
                    [string]$contributor.name
            }
        }
    }


    return (
        $authors -join ", "
    )
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
            @($Item.browseNodeInfo.browseNodes)
        ) {

            if (
                -not [string]::IsNullOrWhiteSpace(
                    [string]$node.displayName
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


    if (
        -not $Item.browseNodeInfo -or
        -not $Item.browseNodeInfo.browseNodes
    ) {

        return $null
    }


    foreach (
        $name in
        @(
            Get-DebugBrowseNodeNames `
                -Item $Item
        )
    ) {

        if (
            $name -match
            'Kindle\s*Unlimited'
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


    if (
        -not $Item.browseNodeInfo -or
        -not $Item.browseNodeInfo.browseNodes
    ) {

        return $null
    }


    foreach (
        $name in
        @(
            Get-DebugBrowseNodeNames `
                -Item $Item
        )
    ) {

        if (
            $name -match
            '期間限定無料'
        ) {

            return $true
        }
    }


    return $false
}


function Get-DebugPrice {

    param(
        $Item
    )


    if (
        -not $Item.offersV2
    ) {

        return ""
    }


    try {

        $listings =
            @()


        if (
            $Item.offersV2.listings
        ) {

            $listings =
                @(
                    $Item.offersV2.listings
                )
        }


        if (
            $listings.Count -eq 0
        ) {

            return ""
        }


        $listing =
            $listings[0]


        if (
            $listing.price -and
            $listing.price.money
        ) {

            $amount =
                $listing.price.money.amount


            if (
                $null -ne $amount
            ) {

                return (
                    "￥{0}" -f
                    [math]::Round(
                        [double]$amount,
                        0
                    )
                )
            }
        }
    }
    catch {

        return ""
    }


    return ""
}


function ConvertTo-DebugStatusText {

    param(
        $Value
    )


    if (
        $Value -eq $true
    ) {

        return "対象"
    }


    if (
        $Value -eq $false
    ) {

        return "対象外"
    }


    return "不明"
}


# ==========================================
# Main
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Kindle Benefits Debug"
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


$resources =
    @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "browseNodeInfo.browseNodes",
        "offersV2.listings.price"
    )


$rows =
    @()


$totalResultCount =
    0


$requiredPages =
    1


$requestCount =
    0


$rank =
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
            -ItemPage $page


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

        $rank++


        $ku =
            Test-DebugKindleUnlimited `
                -Item $item


        $limitedFree =
            Test-DebugLimitedFree `
                -Item $item


        $browseNodeNames =
            @(
                Get-DebugBrowseNodeNames `
                    -Item $item
            )


        $rows +=
            [PSCustomObject]@{

                SearchRank =
                    $rank

                ASIN =
                    [string]$item.asin

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
                    $ku

                KindleUnlimitedDisplay =
                    (
                        ConvertTo-DebugStatusText `
                            -Value $ku
                    )

                LimitedFree =
                    $limitedFree

                LimitedFreeDisplay =
                    (
                        ConvertTo-DebugStatusText `
                            -Value $limitedFree
                    )

                BrowseNodeNames =
                    $browseNodeNames

                DetailPageURL =
                    [string]$item.detailPageURL
            }
    }
}


$kuCount =
    @(
        $rows |
        Where-Object {
            $_.KindleUnlimited -eq $true
        }
    ).Count


$kuUnknownCount =
    @(
        $rows |
        Where-Object {
            $null -eq $_.KindleUnlimited
        }
    ).Count


$limitedFreeCount =
    @(
        $rows |
        Where-Object {
            $_.LimitedFree -eq $true
        }
    ).Count


$limitedFreeUnknownCount =
    @(
        $rows |
        Where-Object {
            $null -eq $_.LimitedFree
        }
    ).Count


$result =
    [PSCustomObject]@{

        Category =
            "Kindle"

        SearchIndex =
            "KindleStore"

        Keyword =
            $Keyword

        TotalResultCount =
            $totalResultCount

        RetrievedItems =
            $rows.Count

        KindleUnlimitedCount =
            $kuCount

        KindleUnlimitedUnknownCount =
            $kuUnknownCount

        LimitedFreeCount =
            $limitedFreeCount

        LimitedFreeUnknownCount =
            $limitedFreeUnknownCount

        SearchItemsRequests =
            $requestCount

        Items =
            $rows
    }


# ==========================================
# Save JSON
# ==========================================

$safeKeyword =
    $Keyword -replace
    '[\\/:*?"<>|]',
    '_'


$outputPath =
    Join-Path `
        $outputDirectory `
        (
            "kindle-benefits-{0}.json" -f
            $safeKeyword
        )


[System.IO.File]::WriteAllText(
    $outputPath,
    (
        $result |
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
    "Retrieved: {0}" -f
    $result.RetrievedItems
)

Write-Host (
    "KU: {0}" -f
    $result.KindleUnlimitedCount
)

Write-Host (
    "KU unknown: {0}" -f
    $result.KindleUnlimitedUnknownCount
)

Write-Host (
    "Limited free: {0}" -f
    $result.LimitedFreeCount
)

Write-Host (
    "Limited free unknown: {0}" -f
    $result.LimitedFreeUnknownCount
)

Write-Host (
    "Requests: {0}" -f
    $result.SearchItemsRequests
)

Write-Host ""
Write-Host "Output:"
Write-Host $outputPath
Write-Host ""
Write-Host "Done."
