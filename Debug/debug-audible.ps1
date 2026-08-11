# ==========================================
# Audible Offers Debug Script
# ==========================================


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

    Write-Host ""
    Write-Host "Authentication Error"
    Write-Host $_.Exception.Message

    exit
}


# ==========================================
# Input keyword
# ==========================================

$keyword =
    Read-Host "Enter Audible search keyword"

if ([string]::IsNullOrWhiteSpace($keyword)) {

    Write-Host "Keyword is empty."

    exit
}


# ==========================================
# Search settings
# ==========================================

$resources = @(
    "itemInfo.title",
    "itemInfo.byLineInfo",
    "itemInfo.classifications",
    "itemInfo.contentInfo",
    "itemInfo.technicalInfo",
    "images.primary.medium",
    "offersV2.listings.price",
    "offersV2.listings.type",
    "offersV2.listings.availability",
    "offersV2.listings.dealDetails",
    "offersV2.listings.isBuyBoxWinner",
    "offersV2.listings.merchantInfo"
)


$searchKeyword =
    "$keyword Audible"


$searchParams = @{
    Keyword     = $searchKeyword
    SearchIndex = "All"
    Resources   = $resources
    Config      = $config
    AccessToken = $accessToken
}


# ==========================================
# Search
# ==========================================

try {

    $response =
        Invoke-AmazonSearch @searchParams
}
catch {

    Write-Host ""
    Write-Host "Search Error"
    Write-Host $_.Exception.Message

    exit
}


# ==========================================
# Check result
# ==========================================

if (
    -not $response.searchResult.items -or
    $response.searchResult.items.Count -eq 0
) {

    Write-Host ""
    Write-Host "No items found."

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
# Filter Audible items
# ==========================================

$audibleItems =
    @(
        $response.searchResult.items |
        Where-Object {

            $_.itemInfo.classifications.productGroup.displayValue `
                -eq "Audible"
        }
    )


if ($audibleItems.Count -eq 0) {

    Write-Host ""
    Write-Host "No Audible items found."

    exit
}


# ==========================================
# Show Audible items
# ==========================================

for ($i = 0; $i -lt $audibleItems.Count; $i++) {

    $item =
        $audibleItems[$i]

    Write-Host ""
    Write-Host "----------------------------------------"
    Write-Host "[$($i + 1)]"

    Write-Host "Title:" `
        $item.itemInfo.title.displayValue

    Write-Host "ASIN:" `
        $item.asin
}


# ==========================================
# Select item
# ==========================================

Write-Host ""

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
    $itemNumber -gt $audibleItems.Count
) {

    Write-Host "Item number out of range."

    exit
}


$selectedItem =
    $audibleItems[$itemNumber - 1]

$asin =
    $selectedItem.asin


# ==========================================
# Complete JSON
# ==========================================

$json =
    $selectedItem |
    ConvertTo-Json -Depth 30


# ==========================================
# Keyword checks
# ==========================================

$keywords = @(
    "price",
    "amount",
    "currency",
    "displayAmount",
    "offer",
    "subscription",
    "membership",
    "included",
    "unlimited",
    "audible"
)


$keywordLines =
    @()

foreach ($searchWord in $keywords) {

    $found =
        $json |
        Select-String `
            -Pattern $searchWord `
            -CaseSensitive:$false


    if ($found) {

        $keywordLines +=
            "$searchWord : FOUND"
    }
    else {

        $keywordLines +=
            "$searchWord : NOT FOUND"
    }
}


# ==========================================
# Save JSON
# ==========================================

$jsonOutputPath =
    Join-Path `
        $outputDirectory `
        "audible-$asin.json"


[System.IO.File]::WriteAllText(
    $jsonOutputPath,
    $json,
    [System.Text.UTF8Encoding]::new($true)
)


# ==========================================
# Build text report
# ==========================================

$offersJson = ""

if ($selectedItem.offersV2) {

    $offersJson =
        $selectedItem.offersV2 |
        ConvertTo-Json -Depth 30
}


$reportLines =
    @()

$reportLines += "========================================"
$reportLines += " AUDIBLE DEBUG REPORT"
$reportLines += "========================================"
$reportLines += ""

$reportLines += "Keyword: $keyword"
$reportLines += "Title: $($selectedItem.itemInfo.title.displayValue)"
$reportLines += "ASIN: $asin"
$reportLines += "URL: $($selectedItem.detailPageURL)"
$reportLines += ""

$reportLines += "========================================"
$reportLines += " KEYWORD CHECK"
$reportLines += "========================================"
$reportLines += ""

$reportLines += $keywordLines
$reportLines += ""

$reportLines += "========================================"
$reportLines += " OFFERS V2"
$reportLines += "========================================"
$reportLines += ""

$reportLines += $offersJson
$reportLines += ""

$reportLines += "========================================"
$reportLines += " FULL ITEM JSON"
$reportLines += "========================================"
$reportLines += ""

$reportLines += $json
$reportLines += ""


$textOutputPath =
    Join-Path `
        $outputDirectory `
        "audible-$asin.txt"


[System.IO.File]::WriteAllLines(
    $textOutputPath,
    $reportLines,
    [System.Text.UTF8Encoding]::new($true)
)


# ==========================================
# Display summary
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

Write-Host "KEYWORD CHECK:"

foreach ($line in $keywordLines) {

    Write-Host $line
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