# ==========================================
# Manga Limited-Free Debug
# ==========================================
#
# Purpose:
# - Inspect price and deal metadata for manga volumes
# - Check whether limited-time free information can be
#   detected from Creators API responses
#
# Test seed:
#   B093MHC6WY
#
# This file does not modify the main application.
# ==========================================


$projectRoot =
    Split-Path $PSScriptRoot -Parent


# ==========================================
# Load core functions
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"

. "$projectRoot\Core\Invoke-AmazonSearch.ps1"

. "$projectRoot\Core\Invoke-AmazonGetItems.ps1"


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
# Test settings
# ==========================================

$seedASIN =
    "B093MHC6WY"


$searchKeyword =
    "闇金ウシジマくん"


$resources =
    @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "itemInfo.classifications",
        "images.primary.medium",
        "offersV2.listings.availability",
        "offersV2.listings.condition",
        "offersV2.listings.isBuyBoxWinner",
        "offersV2.listings.merchantInfo",
        "offersV2.listings.price",
        "offersV2.listings.type",
        "offersV2.listings.dealDetails",
        "browseNodeInfo.browseNodes"
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
# Seed GetItems
# ==========================================

Write-Host ""
Write-Host "Getting seed item..."


$seedItems =
    @(
        Invoke-AmazonGetItems `
            -Asins @($seedASIN) `
            -Resources $resources `
            -Config $config `
            -AccessToken $accessToken
    )


if (
    $seedItems.Count -eq 0
) {
    throw "Seed item was not returned."
}


$seedItem =
    $seedItems[0]


# ==========================================
# Search first pages
# ==========================================

Write-Host ""
Write-Host "Searching manga volumes..."


$searchItems =
    @()


for (
    $page = 1;
    $page -le 5;
    $page++
) {

    if (
        $page -gt 1
    ) {
        Start-Sleep `
            -Milliseconds 1100
    }


    Write-Host (
        "SearchItems page {0}..." -f
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
            -ItemPage $page


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


    if (
        $pageItems.Count -eq 0
    ) {
        break
    }


    $searchItems +=
        $pageItems
}


# ==========================================
# Helper: title
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


# ==========================================
# Helper: listing
# ==========================================

function Get-DebugListing {

    param(
        $Item
    )


    if (
        -not $Item.offersV2 -or
        -not $Item.offersV2.listings
    ) {
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


    if ($buyBox) {
        return $buyBox
    }


    return (
        @(
            $Item.offersV2.listings
        ) |
        Select-Object -First 1
    )
}


# ==========================================
# Helper: display amount
# ==========================================

function Get-DebugDisplayAmount {

    param(
        $MoneyObject
    )


    if (
        $null -eq $MoneyObject
    ) {
        return ""
    }


    if (
        $MoneyObject.displayAmount
    ) {
        return [string]$MoneyObject.displayAmount
    }


    if (
        $null -ne $MoneyObject.amount
    ) {
        return [string]$MoneyObject.amount
    }


    return ""
}


# ==========================================
# Build summary
# ==========================================

$summary =
    @()


foreach (
    $item in $searchItems
) {

    $title =
        Get-DebugTitle `
            -Item $item


    if (
        [string]::IsNullOrWhiteSpace(
            $title
        )
    ) {
        continue
    }


    if (
        $title -notmatch
        "^闇金ウシジマくん"
    ) {
        continue
    }


    $listing =
        Get-DebugListing `
            -Item $item


    $price =
        ""


    $savingBasis =
        ""


    $savingsAmount =
        ""


    $savingsPercent =
        ""


    $dealJson =
        ""


    $listingJson =
        ""


    if ($listing) {

        if (
            $listing.price -and
            $listing.price.money
        ) {
            $price =
                Get-DebugDisplayAmount `
                    -MoneyObject $listing.price.money
        }


        if (
            $listing.savingBasis -and
            $listing.savingBasis.money
        ) {
            $savingBasis =
                Get-DebugDisplayAmount `
                    -MoneyObject $listing.savingBasis.money
        }


        if (
            $listing.savings
        ) {

            if (
                $listing.savings.money
            ) {
                $savingsAmount =
                    Get-DebugDisplayAmount `
                        -MoneyObject $listing.savings.money
            }


            if (
                $null -ne
                $listing.savings.percentage
            ) {
                $savingsPercent =
                    [string]$listing.savings.percentage
            }
        }


        if (
            $listing.dealDetails
        ) {
            $dealJson =
                $listing.dealDetails |
                ConvertTo-Json -Depth 20 -Compress
        }


        $listingJson =
            $listing |
            ConvertTo-Json -Depth 30 -Compress
    }


    $summary +=
        [PSCustomObject]@{

            ASIN =
                $item.asin

            Title =
                $title

            Price =
                $price

            SavingBasis =
                $savingBasis

            SavingsAmount =
                $savingsAmount

            SavingsPercent =
                $savingsPercent

            HasDealDetails =
                (
                    $null -ne
                    $listing.dealDetails
                )

            DealDetails =
                $dealJson

            ListingJson =
                $listingJson
        }
}


# ==========================================
# Save raw data
# ==========================================

$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding `
        -ArgumentList $true


$seedOutputPath =
    Join-Path `
        $outputDirectory `
        "manga-free-seed.json"


$searchOutputPath =
    Join-Path `
        $outputDirectory `
        "manga-free-search.json"


$summaryOutputPath =
    Join-Path `
        $outputDirectory `
        "manga-free-summary.json"


[System.IO.File]::WriteAllText(
    $seedOutputPath,
    (
        $seedItem |
        ConvertTo-Json -Depth 50
    ),
    $utf8Bom
)


[System.IO.File]::WriteAllText(
    $searchOutputPath,
    (
        $searchItems |
        ConvertTo-Json -Depth 50
    ),
    $utf8Bom
)


[System.IO.File]::WriteAllText(
    $summaryOutputPath,
    (
        $summary |
        ConvertTo-Json -Depth 30
    ),
    $utf8Bom
)


# ==========================================
# Console output
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Limited-Free Debug Summary"
Write-Host "=========================================="
Write-Host ""


$summary |
    Select-Object `
        ASIN,
        Title,
        Price,
        SavingBasis,
        SavingsAmount,
        SavingsPercent,
        HasDealDetails |
    Format-Table `
        -AutoSize `
        -Wrap


Write-Host ""
Write-Host "Output files:"
Write-Host $seedOutputPath
Write-Host $searchOutputPath
Write-Host $summaryOutputPath
Write-Host ""
Write-Host "Done."