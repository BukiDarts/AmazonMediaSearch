# ==========================================
# Manga Limited-Free BrowseNode Debug
# ==========================================
#
# Purpose:
# - Inspect volumes 1 to 10 of one manga series
# - Detect limited-time free metadata from BrowseNodeInfo
# - Compare each volume side by side
#
# Test series:
#   Yamikin Ushijima-kun
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

$seriesTitle =
    "闇金ウシジマくん"


$resources =
    @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "itemInfo.classifications",
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
# Helper: normalize text
# ==========================================

function ConvertTo-DebugNormalizedText {

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


    return (
        (
            $Text.Normalize(
                [Text.NormalizationForm]::FormKC
            ) -replace '\s+', ' '
        ).Trim()
    )
}


# ==========================================
# Helper: volume number
# ==========================================

function Get-DebugVolumeNumber {

    param(
        [string]$Title
    )


    $normalizedTitle =
        ConvertTo-DebugNormalizedText `
            -Text $Title


    if (
        [string]::IsNullOrWhiteSpace(
            $normalizedTitle
        )
    ) {
        return $null
    }


    # Example:
    # Series（1）
    # Series(1)
    if (
        $normalizedTitle -match
        '[\(（]\s*(\d+)\s*[\)）]'
    ) {
        return [int]$Matches[1]
    }


    # Example:
    # Series 第1巻
    if (
        $normalizedTitle -match
        '\u7B2C\s*(\d+)\s*\u5DFB'
    ) {
        return [int]$Matches[1]
    }


    # Example:
    # Series 1巻
    if (
        $normalizedTitle -match
        '(\d+)\s*\u5DFB'
    ) {
        return [int]$Matches[1]
    }


    # Example:
    # Series 1 (Label)
    if (
        $normalizedTitle -match
        '(?<!\d)(\d+)\s*(?:\([^()]*\)\s*)+$'
    ) {
        return [int]$Matches[1]
    }


    return $null
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
# Helper: current price
# ==========================================

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


# ==========================================
# Helper: BrowseNode names
# ==========================================

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


# ==========================================
# Helper: limited-free detection
# ==========================================

function Test-DebugLimitedFree {

    param(
        $Item
    )


    $nodeNames =
        @(
            Get-DebugBrowseNodeNames `
                -Item $Item
        )


    foreach ($nodeName in $nodeNames) {

        if (
            $nodeName -match
            '期間限定無料'
        ) {
            return $true
        }
    }


    return $false
}


# ==========================================
# Search pages
# ==========================================

$allItems =
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
            -Keyword $seriesTitle `
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


    $allItems +=
        $pageItems
}


# ==========================================
# Select main series volumes 1 to 10
# ==========================================

$results =
    @()


foreach ($item in $allItems) {

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


    $normalizedTitle =
        ConvertTo-DebugNormalizedText `
            -Text $title


    if (
        $normalizedTitle -notmatch
        '^闇金ウシジマくん'
    ) {
        continue
    }


    # Exclude spin-offs and split editions.
    if (
        $normalizedTitle -match
        '外伝|分冊版'
    ) {
        continue
    }


    $volume =
        Get-DebugVolumeNumber `
            -Title $title


    if (
        $null -eq $volume
    ) {
        continue
    }


    if (
        $volume -lt 1 -or
        $volume -gt 10
    ) {
        continue
    }


    $nodeNames =
        @(
            Get-DebugBrowseNodeNames `
                -Item $item
        )


    $limitedFreeNodes =
        @(
            $nodeNames |
            Where-Object {
                $_ -match
                '期間限定無料'
            }
        )


    $results +=
        [PSCustomObject]@{

            Volume =
                [int]$volume

            ASIN =
                $item.asin

            Title =
                $title

            Price =
                (
                    Get-DebugPrice `
                        -Item $item
                )

            IsLimitedFree =
                (
                    Test-DebugLimitedFree `
                        -Item $item
                )

            LimitedFreeNodes =
                (
                    $limitedFreeNodes -join " | "
                )

            AllBrowseNodes =
                (
                    $nodeNames -join " | "
                )
        }
}


# ==========================================
# Keep one item per volume
# ==========================================

$finalResults =
    @()


for (
    $volume = 1;
    $volume -le 10;
    $volume++
) {

    $match =
        @(
            $results |
            Where-Object {
                $_.Volume -eq $volume
            } |
            Sort-Object Title
        ) |
        Select-Object -First 1


    if ($match) {

        $finalResults +=
            $match
    }
    else {

        $finalResults +=
            [PSCustomObject]@{

                Volume =
                    $volume

                ASIN =
                    ""

                Title =
                    ""

                Price =
                    ""

                IsLimitedFree =
                    $null

                LimitedFreeNodes =
                    ""

                AllBrowseNodes =
                    ""
            }
    }
}


# ==========================================
# Save output
# ==========================================

$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding `
        -ArgumentList $true


$outputPath =
    Join-Path `
        $outputDirectory `
        "manga-limited-free-1-10.json"


$json =
    $finalResults |
    ConvertTo-Json -Depth 30


[System.IO.File]::WriteAllText(
    $outputPath,
    $json,
    $utf8Bom
)


# ==========================================
# Console output
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Limited-Free BrowseNode Test"
Write-Host "=========================================="
Write-Host ""


$finalResults |
    Select-Object `
        Volume,
        ASIN,
        Price,
        IsLimitedFree,
        LimitedFreeNodes |
    Format-Table `
        -AutoSize `
        -Wrap


Write-Host ""
Write-Host "Output:"
Write-Host $outputPath
Write-Host ""
Write-Host "Done."