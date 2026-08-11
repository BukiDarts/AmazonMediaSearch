Add-Type -AssemblyName PresentationFramework

# ==========================================
# Project paths
# ==========================================

$projectRoot =
    Split-Path $PSScriptRoot -Parent

$outputDirectory =
    Join-Path $PSScriptRoot "Output"


# ==========================================
# Load common functions
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"
. "$projectRoot\Core\Invoke-AmazonSearch.ps1"


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
        Get-AmazonAccessToken -Config $config
}
catch {

    Write-Host "Authentication failed."
    Write-Host $_.Exception.Message

    exit
}


# ==========================================
# Search keyword
# ==========================================

$keyword =
    Read-Host "Enter Kindle search keyword"

if ([string]::IsNullOrWhiteSpace($keyword)) {

    Write-Host "Keyword is empty."

    exit
}


# ==========================================
# Resources for investigation
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
    "offersV2.listings.dealDetails",
    "offersV2.listings.isBuyBoxWinner",
    "offersV2.listings.merchantInfo",
    "offersV2.listings.price",
    "offersV2.listings.type",

    "browseNodeInfo.browseNodes",
    "browseNodeInfo.browseNodes.ancestor",
    "browseNodeInfo.websiteSalesRank"
)


# ==========================================
# Search
# ==========================================

$searchParams = @{
    Keyword     = $keyword
    SearchIndex = "KindleStore"
    Resources   = $resources
    Config      = $config
    AccessToken = $accessToken
    ItemCount   = 10
    ItemPage    = 1
}

try {

    $response =
        Invoke-AmazonSearch @searchParams
}
catch {

    Write-Host ""
    Write-Host "Search failed."
    Write-Host $_.Exception.Message

    exit
}


# ==========================================
# Output summary
# ==========================================

$items =
    @($response.searchResult.items)

Write-Host ""
Write-Host "========================================"
Write-Host " Kindle debug results"
Write-Host "========================================"
Write-Host ""

Write-Host "TotalResultCount:" `
    $response.searchResult.totalResultCount

Write-Host "Returned items:" `
    $items.Count

Write-Host ""


for ($i = 0; $i -lt $items.Count; $i++) {

    $item =
        $items[$i]

    Write-Host "----------------------------------------"
    Write-Host "[$($i + 1)]"

    Write-Host "Title:" `
        $item.itemInfo.title.displayValue

    Write-Host "ASIN:" `
        $item.asin

    Write-Host "URL:" `
        $item.detailPageURL

    Write-Host ""
}


# ==========================================
# Select item
# ==========================================

$selection =
    Read-Host "Enter item number to inspect"

$itemNumber = 0

if (
    -not [int]::TryParse(
        $selection,
        [ref]$itemNumber
    )
) {

    Write-Host "Invalid number."

    exit
}


if (
    $itemNumber -lt 1 -or
    $itemNumber -gt $items.Count
) {

    Write-Host "Item number out of range."

    exit
}


$selectedItem =
    $items[$itemNumber - 1]


# ==========================================
# Prepare output directory
# ==========================================

if (-not (Test-Path $outputDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $outputDirectory |
        Out-Null
}


$asin =
    $selectedItem.asin


# ==========================================
# Save complete JSON
# ==========================================

$jsonOutputPath =
    Join-Path `
        $outputDirectory `
        "kindle-$asin.json"


$fullJson =
    $selectedItem |
    ConvertTo-Json -Depth 30


[System.IO.File]::WriteAllText(
    $jsonOutputPath,
    $fullJson,
    [System.Text.UTF8Encoding]::new($true)
)


# ==========================================
# Build text report
# ==========================================

$itemInfoJson =
    $selectedItem.itemInfo |
    ConvertTo-Json -Depth 20


$offersJson =
    $selectedItem.offersV2 |
    ConvertTo-Json -Depth 20


$browseNodeJson =
    $selectedItem.browseNodeInfo |
    ConvertTo-Json -Depth 20


$unlimitedNodes =
    @(
        $selectedItem.browseNodeInfo.browseNodes |
        Where-Object {

            $_.displayName -like "*Kindle Unlimited*" -or
            $_.contextFreeName -like "*Kindle Unlimited*"
        }
    )


$reportLines = @()

$reportLines += "========================================"
$reportLines += " KINDLE DEBUG REPORT"
$reportLines += "========================================"
$reportLines += ""

$reportLines += "Keyword: $keyword"
$reportLines += "Title: $($selectedItem.itemInfo.title.displayValue)"
$reportLines += "ASIN: $asin"
$reportLines += "URL: $($selectedItem.detailPageURL)"
$reportLines += ""

$reportLines += "TotalResultCount: $($response.searchResult.totalResultCount)"
$reportLines += "ReturnedItems: $($items.Count)"
$reportLines += ""

$reportLines += "========================================"
$reportLines += " KINDLE UNLIMITED CHECK"
$reportLines += "========================================"
$reportLines += ""

if ($unlimitedNodes.Count -gt 0) {

    $reportLines += "Kindle Unlimited related nodes: FOUND"
    $reportLines += ""

    foreach ($node in $unlimitedNodes) {

        $reportLines += "DisplayName: $($node.displayName)"
        $reportLines += "ContextFreeName: $($node.contextFreeName)"
        $reportLines += "NodeId: $($node.id)"
        $reportLines += ""
    }
}
else {

    $reportLines += "Kindle Unlimited related nodes: NOT FOUND"
    $reportLines += ""
}


$reportLines += "========================================"
$reportLines += " ITEM INFO"
$reportLines += "========================================"
$reportLines += ""
$reportLines += $itemInfoJson
$reportLines += ""

$reportLines += "========================================"
$reportLines += " OFFERS V2"
$reportLines += "========================================"
$reportLines += ""
$reportLines += $offersJson
$reportLines += ""

$reportLines += "========================================"
$reportLines += " BROWSE NODE INFO"
$reportLines += "========================================"
$reportLines += ""
$reportLines += $browseNodeJson
$reportLines += ""


$textOutputPath =
    Join-Path `
        $outputDirectory `
        "kindle-$asin.txt"


[System.IO.File]::WriteAllLines(
    $textOutputPath,
    $reportLines,
    [System.Text.UTF8Encoding]::new($true)
)


# ==========================================
# Display report
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " SELECTED ITEM"
Write-Host "========================================"
Write-Host ""

Write-Host "Title:"
Write-Host $selectedItem.itemInfo.title.displayValue

Write-Host ""

Write-Host "ASIN:"
Write-Host $asin

Write-Host ""

Write-Host "Kindle Unlimited related nodes:"

if ($unlimitedNodes.Count -gt 0) {

    foreach ($node in $unlimitedNodes) {

        Write-Host "- $($node.displayName)"
    }
}
else {

    Write-Host "(none)"
}


Write-Host ""
Write-Host "========================================"
Write-Host " Saved debug files"
Write-Host "========================================"
Write-Host ""

Write-Host "JSON:"
Write-Host $jsonOutputPath

Write-Host ""

Write-Host "Text report:"
Write-Host $textOutputPath

Write-Host ""