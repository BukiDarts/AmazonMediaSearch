# ==========================================
# Manga Title Regression Debug
# ==========================================
#
# Purpose:
# - Test manga volume-number parsing
# - Test manga series-title extraction
# - Verify that new title formats do not break
#   previously supported formats
#
# This file does not modify the main app.
# ==========================================


$projectRoot =
    Split-Path $PSScriptRoot -Parent


# ==========================================
# Load manga service
# ==========================================

. "$projectRoot\Manga\Services\Get-MangaSeries.ps1"


# ==========================================
# Test cases
# ==========================================

$testCases =
    @(

        [PSCustomObject]@{
            Name = "JoJo Part 7"
            Title = "ジョジョの奇妙な冒険 第7部 スティール・ボール・ラン 1 (ジャンプコミックスDIGITAL)"
            ExpectedVolume = 1
            ExpectedSeries = "ジョジョの奇妙な冒険 第7部 スティール・ボール・ラン"
        },

        [PSCustomObject]@{
            Name = "Kingdom"
            Title = "キングダム 1 (ヤングジャンプコミックスDIGITAL)"
            ExpectedVolume = 1
            ExpectedSeries = "キングダム"
        },

        [PSCustomObject]@{
            Name = "Attack on Titan"
            Title = "進撃の巨人（1）"
            ExpectedVolume = 1
            ExpectedSeries = "進撃の巨人"
        },

        [PSCustomObject]@{
            Name = "Black Jack"
            Title = "ブラックジャックによろしく 完全版1"
            ExpectedVolume = 1
            ExpectedSeries = "ブラックジャックによろしく 完全版"
        },

        [PSCustomObject]@{
            Name = "Record of Ragnarok"
            Title = "終末のワルキューレ 1巻 (ゼノンコミックス)"
            ExpectedVolume = 1
            ExpectedSeries = "終末のワルキューレ"
        },

        [PSCustomObject]@{
            Name = "Mystery to Iunakare"
            Title = "ミステリと言う勿れ（１） (フラワーコミックスα)"
            ExpectedVolume = 1
            ExpectedSeries = "ミステリと言う勿れ"
        },

        [PSCustomObject]@{
            Name = "Classroom Friend"
            Title = "クラスで２番目に可愛い女の子と友だちになった　１ (アライブ＋)"
            ExpectedVolume = 1
            ExpectedSeries = "クラスで２番目に可愛い女の子と友だちになった"
        },

        [PSCustomObject]@{
            Name = "Silent Witch Roman Numeral"
            Title = "サイレント・ウィッチ　沈黙の魔女の隠しごと　Ｉ (B's-LOG COMICS)"
            ExpectedVolume = $null
            ExpectedSeries = "サイレント・ウィッチ　沈黙の魔女の隠しごと　Ｉ"
        },

        [PSCustomObject]@{
            Name = "JoJo Series Number Only"
            Title = "ジョジョの奇妙な冒険 第7部 スティール・ボール・ラン"
            ExpectedVolume = $null
            ExpectedSeries = "ジョジョの奇妙な冒険 第7部 スティール・ボール・ラン"
        },

        [PSCustomObject]@{
            Name = "Magazine Year Guard"
            Title = "キングダム magazine 2026 (ヤングジャンプコミックスDIGITAL)"
            ExpectedVolume = 2026
            ExpectedSeries = "キングダム magazine"
        }

    )


# ==========================================
# Helper
# ==========================================

function ConvertTo-DisplayValue {

    param(
        $Value
    )


    if (
        $null -eq $Value
    ) {

        return "<null>"
    }


    return [string]$Value
}


# ==========================================
# Run tests
# ==========================================

$results =
    @()


foreach (
    $testCase in $testCases
) {

    $actualVolume =
        Get-MangaVolumeNumber `
            -Title $testCase.Title


    $actualSeries =
        Get-MangaSeriesTitle `
            -Title $testCase.Title


    $volumePass =
        $false


    if (
        $null -eq $testCase.ExpectedVolume -and
        $null -eq $actualVolume
    ) {

        $volumePass =
            $true
    }
    elseif (
        $null -ne $testCase.ExpectedVolume -and
        $null -ne $actualVolume
    ) {

        $volumePass =
            (
                [int]$testCase.ExpectedVolume -eq
                [int]$actualVolume
            )
    }


    $seriesPass =
        (
            [string]$testCase.ExpectedSeries -eq
            [string]$actualSeries
        )


    $overallPass =
        (
            $volumePass -and
            $seriesPass
        )


    $results +=
        [PSCustomObject]@{

            Name =
                $testCase.Name

            Title =
                $testCase.Title

            ExpectedVolume =
                (
                    ConvertTo-DisplayValue `
                        -Value $testCase.ExpectedVolume
                )

            ActualVolume =
                (
                    ConvertTo-DisplayValue `
                        -Value $actualVolume
                )

            ExpectedSeries =
                $testCase.ExpectedSeries

            ActualSeries =
                $actualSeries

            VolumePass =
                $volumePass

            SeriesPass =
                $seriesPass

            OverallPass =
                $overallPass
        }
}


# ==========================================
# Console output
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Manga Title Regression Test"
Write-Host "=========================================="
Write-Host ""


foreach (
    $result in $results
) {

    Write-Host "------------------------------------------"

    Write-Host (
        "Name: {0}" -f
        $result.Name
    )

    Write-Host (
        "Title: {0}" -f
        $result.Title
    )

    Write-Host ""

    Write-Host (
        "Expected Volume: {0}" -f
        $result.ExpectedVolume
    )

    Write-Host (
        "Actual Volume:   {0}" -f
        $result.ActualVolume
    )

    Write-Host (
        "Volume Pass:     {0}" -f
        $result.VolumePass
    )

    Write-Host ""

    Write-Host (
        "Expected Series: {0}" -f
        $result.ExpectedSeries
    )

    Write-Host (
        "Actual Series:   {0}" -f
        $result.ActualSeries
    )

    Write-Host (
        "Series Pass:     {0}" -f
        $result.SeriesPass
    )

    Write-Host ""

    Write-Host (
        "Overall Pass:    {0}" -f
        $result.OverallPass
    )

    Write-Host ""
}


# ==========================================
# Summary
# ==========================================

$passedCount =
    @(
        $results |
        Where-Object {
            $_.OverallPass -eq
            $true
        }
    ).Count


$failedCount =
    @(
        $results |
        Where-Object {
            $_.OverallPass -eq
            $false
        }
    ).Count


Write-Host "=========================================="

Write-Host (
    "Passed: {0}" -f
    $passedCount
)

Write-Host (
    "Failed: {0}" -f
    $failedCount
)

Write-Host "=========================================="


# ==========================================
# Save JSON
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


$outputPath =
    Join-Path `
        $outputDirectory `
        "manga-title-regression.json"


$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding `
        -ArgumentList $true


[System.IO.File]::WriteAllText(
    $outputPath,
    (
        $results |
        ConvertTo-Json -Depth 20
    ),
    $utf8Bom
)


Write-Host ""
Write-Host "Output:"
Write-Host $outputPath
Write-Host ""
Write-Host "Done."