# ==========================================
# Manga ASIN Investigation Script
# ==========================================
#
# Purpose:
# - Retrieve one Amazon item directly by ASIN
# - Inspect manga item information
# - Inspect BrowseNodeInfo
# - Detect Kindle Unlimited related nodes
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
# Load authentication function
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"


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
# Input ASIN
# ==========================================

$asin =
    Read-Host "Enter ASIN"

$asin =
    $asin.Trim()


if ([string]::IsNullOrWhiteSpace($asin)) {

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


# ==========================================
# Run identifier
# ==========================================

$runId =
    Get-Date -Format "yyyyMMdd-HHmmss"


# ==========================================
# GetItems endpoint
# ==========================================

$getItemsUrl =
    "https://creatorsapi.amazon/catalog/v1/getItems"


# ==========================================
# Resources
# ==========================================

$resources = @(
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
    "offersV2.listings.type",
    "browseNodeInfo.browseNodes",
    "browseNodeInfo.browseNodes.ancestor",
    "browseNodeInfo.websiteSalesRank"
)


# ==========================================
# Build request
# ==========================================

$requestBody = @{
    itemIds     = @($asin)
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


# ==========================================
# Call GetItems
# ==========================================

Write-Host ""
Write-Host "Retrieving ASIN..."
Write-Host ""


try {

    $webResponse =
        Invoke-WebRequest `
            @requestParameters `
            -UseBasicParsing
}
catch {

    Write-Host "GetItems request failed."
    Write-Host $_.Exception.Message

    exit
}


# ==========================================
# Decode UTF-8 response
# ==========================================

$responseBytes =
    $webResponse.RawContentStream.ToArray()


$responseText =
    [System.Text.Encoding]::UTF8.GetString(
        $responseBytes
    )


$response =
    $responseText |
    ConvertFrom-Json


# ==========================================
# Get returned item
# ==========================================

$item =
    $null


if (
    $response.itemsResult -and
    $response.itemsResult.items
) {

    $item =
        @(
            $response.itemsResult.items
        ) |
        Select-Object -First 1
}


# ==========================================
# Handle missing item
# ==========================================

if (-not $item) {

    Write-Host ""
    Write-Host "Item was not returned."


    if ($response.errors) {

        Write-Host ""
        Write-Host "API errors:"


        foreach ($errorItem in $response.errors) {

            Write-Host (
                "{0}: {1}" -f
                $errorItem.code,
                $errorItem.message
            )
        }
    }


    exit
}


# ==========================================
# Kindle Unlimited detector
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
# Get title
# ==========================================

$title =
    ""


if (
    $item.itemInfo -and
    $item.itemInfo.title
) {

    $title =
        $item.itemInfo.title.displayValue
}


# ==========================================
# Get contributors
# ==========================================

$contributorText =
    "none"


if (
    $item.itemInfo -and
    $item.itemInfo.byLineInfo -and
    $item.itemInfo.byLineInfo.contributors
) {

    $contributorParts =
        @()


    foreach (
        $contributor in
        $item.itemInfo.byLineInfo.contributors
    ) {

        $contributorParts += (
            "{0} ({1})" -f
            $contributor.name,
            $contributor.roleType
        )
    }


    if ($contributorParts.Count -gt 0) {

        $contributorText =
            $contributorParts -join ", "
    }
}


# ==========================================
# Get binding
# ==========================================

$binding =
    ""


if (
    $item.itemInfo -and
    $item.itemInfo.classifications -and
    $item.itemInfo.classifications.binding
) {

    $binding =
        $item.itemInfo.classifications.binding.displayValue
}


# ==========================================
# Get product group
# ==========================================

$productGroup =
    ""


if (
    $item.itemInfo -and
    $item.itemInfo.classifications -and
    $item.itemInfo.classifications.productGroup
) {

    $productGroup =
        $item.itemInfo.classifications.productGroup.displayValue
}


# ==========================================
# Get price
# ==========================================

$price =
    ""


if (
    $item.offersV2 -and
    $item.offersV2.listings
) {

    $buyBox =
        @(
            $item.offersV2.listings |
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

        $price =
            $buyBox.price.money.displayAmount
    }


    if (
        [string]::IsNullOrWhiteSpace($price)
    ) {

        $firstListing =
            @(
                $item.offersV2.listings
            ) |
            Select-Object -First 1


        if (
            $firstListing -and
            $firstListing.price -and
            $firstListing.price.money
        ) {

            $price =
                $firstListing.price.money.displayAmount
        }
    }
}


# ==========================================
# Detect Kindle Unlimited
# ==========================================

$isKindleUnlimited =
    Test-KindleUnlimitedNode `
        -Item $item


# ==========================================
# Collect KU related browse node names
# ==========================================

$kuNodeNames =
    @()


if ($item.browseNodeInfo) {

    $browseNodeJson =
        $item.browseNodeInfo |
        ConvertTo-Json -Depth 30


    $browseNodeLines =
        $browseNodeJson -split "`r?`n"


    foreach ($line in $browseNodeLines) {

        if (
            $line -match
            'Kindle Unlimited'
        ) {

            $cleanLine =
                $line.Trim()


            if (
                -not [string]::IsNullOrWhiteSpace(
                    $cleanLine
                )
            ) {

                $kuNodeNames +=
                    $cleanLine
            }
        }
    }


    $kuNodeNames =
        @(
            $kuNodeNames |
            Sort-Object -Unique
        )
}


# ==========================================
# Build analysis object
# ==========================================

$analysisObject =
    [PSCustomObject]@{

        ASIN =
            $item.asin

        Title =
            $title

        Contributors =
            $contributorText

        Binding =
            $binding

        ProductGroup =
            $productGroup

        Price =
            $price

        IsKindleUnlimited =
            $isKindleUnlimited

        KindleUnlimitedNodeLines =
            @($kuNodeNames)

        DetailPageURL =
            $item.detailPageURL
    }


# ==========================================
# Console output
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " ASIN RESULT"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "ASIN: {0}" -f
    $analysisObject.ASIN
)

Write-Host (
    "Title: {0}" -f
    $analysisObject.Title
)

Write-Host (
    "Contributors: {0}" -f
    $analysisObject.Contributors
)

Write-Host (
    "Binding: {0}" -f
    $analysisObject.Binding
)

Write-Host (
    "ProductGroup: {0}" -f
    $analysisObject.ProductGroup
)

Write-Host (
    "Price: {0}" -f
    $analysisObject.Price
)

Write-Host (
    "KindleUnlimited: {0}" -f
    $analysisObject.IsKindleUnlimited
)

Write-Host ""


if ($kuNodeNames.Count -gt 0) {

    Write-Host "KU related BrowseNode lines:"


    foreach ($line in $kuNodeNames) {

        Write-Host (
            "  {0}" -f
            $line
        )
    }
}
else {

    Write-Host "KU related BrowseNode lines: none"
}


# ==========================================
# Output file names
# ==========================================

$safeAsin =
    $asin -replace (
        '[^A-Za-z0-9]'
    ),
    '_'


$outputPrefix =
    "manga-asin-{0}-{1}" -f
    $safeAsin,
    $runId


$rawJsonPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-raw.json"


$analysisJsonPath =
    Join-Path `
        $outputDirectory `
        "$outputPrefix-analysis.json"


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
# Save raw response
# ==========================================

[System.IO.File]::WriteAllText(
    $rawJsonPath,
    $responseText,
    $utf8Bom
)


# ==========================================
# Save analysis JSON
# ==========================================

$analysisJson =
    $analysisObject |
    ConvertTo-Json -Depth 10


[System.IO.File]::WriteAllText(
    $analysisJsonPath,
    $analysisJson,
    $utf8Bom
)


# ==========================================
# Build text report
# ==========================================

$reportLines =
    @()


$reportLines +=
    "========================================"

$reportLines +=
    " ASIN INVESTIGATION REPORT"

$reportLines +=
    "========================================"

$reportLines +=
    ""

$reportLines +=
    "RunId: $runId"

$reportLines +=
    "ASIN: $($analysisObject.ASIN)"

$reportLines +=
    "Title: $($analysisObject.Title)"

$reportLines +=
    "Contributors: $($analysisObject.Contributors)"

$reportLines +=
    "Binding: $($analysisObject.Binding)"

$reportLines +=
    "ProductGroup: $($analysisObject.ProductGroup)"

$reportLines +=
    "Price: $($analysisObject.Price)"

$reportLines +=
    "KindleUnlimited: $($analysisObject.IsKindleUnlimited)"

$reportLines +=
    "DetailPageURL: $($analysisObject.DetailPageURL)"

$reportLines +=
    ""

$reportLines +=
    "KU related BrowseNode lines:"


if ($kuNodeNames.Count -gt 0) {

    foreach ($line in $kuNodeNames) {

        $reportLines +=
            $line
    }
}
else {

    $reportLines +=
        "none"
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

Write-Host "Analysis JSON:"
Write-Host $analysisJsonPath

Write-Host ""

Write-Host "Report:"
Write-Host $reportPath

Write-Host ""

Write-Host "Raw response:"
Write-Host $rawJsonPath

Write-Host ""