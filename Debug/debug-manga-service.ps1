# ==========================================
# Manga Service Debug Runner
# ==========================================


$projectRoot =
    Split-Path $PSScriptRoot -Parent


$outputDirectory =
    Join-Path $PSScriptRoot "Output"


# ==========================================
# Load core and manga service
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"

. "$projectRoot\Core\Invoke-AmazonSearch.ps1"

. "$projectRoot\Core\Invoke-AmazonGetItems.ps1"

. "$projectRoot\Manga\Services\Get-MangaSeries.ps1"


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
    Get-Content `
        $configPath `
        -Raw |
    ConvertFrom-Json


# ==========================================
# Authenticate
# ==========================================

try {

    $accessToken =
        Get-AmazonAccessToken `
            -Config $config
}
catch {

    Write-Host "Authentication failed."
    Write-Host $_.Exception.Message
    exit
}


# ==========================================
# Input
# ==========================================

$seedASIN =
    Read-Host "Enter seed ASIN"


# ==========================================
# Execute service
# ==========================================

try {

    $result =
        Get-MangaSeries `
            -SeedASIN $seedASIN `
            -Config $config `
            -AccessToken $accessToken
}
catch {

    Write-Host ""
    Write-Host "Manga service failed."
    Write-Host $_.Exception.Message
    exit
}


# ==========================================
# Console summary
# ==========================================

Write-Host ""
Write-Host "========================================"
Write-Host " MANGA SERVICE RESULT"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "Series: {0}" -f
    $result.SeriesTitle
)

Write-Host (
    "Detected ranges: {0}" -f
    $result.DetectedRanges
)

Write-Host (
    "Total volume status: {0}" -f
    $result.TotalVolumeStatus
)

Write-Host (
    "KU ranges: {0}" -f
    $result.KindleUnlimitedRanges
)

Write-Host (
    "Non-KU ranges: {0}" -f
    $result.NonKindleUnlimitedRanges
)

Write-Host (
    "Unknown KU ranges: {0}" -f
    $result.UnknownKindleUnlimitedRanges
)

Write-Host (
    "Tail status: {0}" -f
    $result.TailStatus
)

Write-Host (
    "Fallback ASIN count: {0}" -f
    $result.FallbackASINCount
)

Write-Host ""
Write-Host "========================================"
Write-Host " API REQUEST SUMMARY"
Write-Host "========================================"
Write-Host ""

Write-Host (
    "SearchItems requests: {0}" -f
    $result.SearchItemsRequests
)

Write-Host (
    "GetItems requests: {0}" -f
    $result.GetItemsRequests
)

Write-Host (
    "Creators API requests: {0}" -f
    $result.CreatorsApiRequests
)

Write-Host ""


foreach ($volume in $result.Volumes) {

    Write-Host (
        "Volume {0}: {1} | {2} | {3}" -f
        $volume.Volume,
        $volume.KindleUnlimitedStatus,
        $volume.Price,
        $volume.Title
    )
}


# ==========================================
# Save result
# ==========================================

if (-not (Test-Path $outputDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $outputDirectory |
        Out-Null
}


$runId =
    Get-Date -Format "yyyyMMdd-HHmmss"


$outputPath =
    Join-Path `
        $outputDirectory `
        (
            "manga-service-{0}-{1}.json" -f
            $seedASIN,
            $runId
        )


$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding `
        -ArgumentList $true


$resultJson =
    $result |
    ConvertTo-Json -Depth 20


[System.IO.File]::WriteAllText(
    $outputPath,
    $resultJson,
    $utf8Bom
)


Write-Host ""
Write-Host "Output:"
Write-Host $outputPath
Write-Host ""