# ==========================================
# Manga Window
# ==========================================


Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase


# ==========================================
# Project paths
# ==========================================

$projectRoot =
    Split-Path $PSScriptRoot -Parent


$configPath =
    Join-Path $projectRoot "config.json"


$xamlPath =
    Join-Path $PSScriptRoot "MangaWindow.xaml"


# ==========================================
# Load functions
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"

. "$projectRoot\Core\Invoke-AmazonSearch.ps1"

. "$projectRoot\Core\Invoke-AmazonGetItems.ps1"

. "$projectRoot\Manga\Services\Get-MangaSeries.ps1"


# ==========================================
# Validate files
# ==========================================

if (-not (Test-Path $configPath)) {

    [System.Windows.MessageBox]::Show(
        "config.json not found."
    )

    exit
}


if (-not (Test-Path $xamlPath)) {

    [System.Windows.MessageBox]::Show(
        "MangaWindow.xaml not found."
    )

    exit
}


# ==========================================
# Load config
# ==========================================

try {

    $config =
        Get-Content `
            $configPath `
            -Raw |
        ConvertFrom-Json
}
catch {

    [System.Windows.MessageBox]::Show(
        "Failed to load config.json."
    )

    exit
}


# ==========================================
# Authenticate once
# ==========================================

try {

    $accessToken =
        Get-AmazonAccessToken `
            -Config $config
}
catch {

    [System.Windows.MessageBox]::Show(
        "Authentication failed."
    )

    exit
}


# ==========================================
# Load XAML
# ==========================================

try {

    [xml]$xaml =
        Get-Content `
            $xamlPath `
            -Raw


    $reader =
        New-Object `
            System.Xml.XmlNodeReader `
            $xaml


    $window =
        [Windows.Markup.XamlReader]::Load(
            $reader
        )
}
catch {

    [System.Windows.MessageBox]::Show(
        "Failed to load MangaWindow.xaml."
    )

    exit
}


# ==========================================
# Controls
# ==========================================

$asinBox =
    $window.FindName(
        "AsinBox"
    )


$searchButton =
    $window.FindName(
        "SearchButton"
    )


$seriesTitleText =
    $window.FindName(
        "SeriesTitleText"
    )


$volumeSummaryText =
    $window.FindName(
        "VolumeSummaryText"
    )


$kuSummaryText =
    $window.FindName(
        "KUSummaryText"
    )


$unknownSummaryText =
    $window.FindName(
        "UnknownSummaryText"
    )


$statusText =
    $window.FindName(
        "StatusText"
    )


$volumesGrid =
    $window.FindName(
        "VolumesGrid"
    )


$requestSummaryText =
    $window.FindName(
        "RequestSummaryText"
    )


# ==========================================
# Format range text
# ==========================================

function ConvertTo-DisplayRange {

    param(
        [string]$Range
    )


    if (
        [string]::IsNullOrWhiteSpace(
            $Range
        ) -or
        $Range -eq "none"
    ) {

        return ""
    }


    $display =
        $Range.Replace(
            "-",
            [string][char]0x301C
        )


    $display =
        $display.Replace(
            ", ",
            [string][char]0x3001
        )


    return $display
}


# ==========================================
# Create total volume display
# ==========================================

function Get-VolumeSummaryText {

    param(
        $Result
    )


    $maxVolume =
        $Result.MaxDetectedVolume


    if ($null -eq $maxVolume) {

        return "巻数：不明"
    }


    switch (
        $Result.TotalVolumeStatus
    ) {

        "Confirmed" {

            return (
                "全{0}巻" -f
                $maxVolume
            )
        }


        "StrongProbable" {

            return (
                "全{0}巻（推定）" -f
                $maxVolume
            )
        }


        "Probable" {

            return (
                "{0}巻まで検出（推定）" -f
                $maxVolume
            )
        }


        default {

            return (
                "{0}巻まで検出" -f
                $maxVolume
            )
        }
    }
}


# ==========================================
# Create KU summary display
# ==========================================

function Get-KUSummaryText {

    param(
        $Result
    )


    if (
        $Result.KindleUnlimitedVolumeCount -eq
        0
    ) {

        return "Kindle Unlimited：対象なし"
    }


    $range =
        ConvertTo-DisplayRange `
            -Range $Result.KindleUnlimitedRanges


    if (
        $Result.IsAllDetectedVolumesKindleUnlimited -eq
        $true
    ) {

        return (
            "Kindle Unlimited：{0}巻（全巻）" -f
            $range
        )
    }


    return (
        "Kindle Unlimited：{0}巻" -f
        $range
    )
}


# ==========================================
# Reset display
# ==========================================

function Reset-MangaDisplay {

    $seriesTitleText.Text =
        "作品名"


    $volumeSummaryText.Text =
        "巻数：-"


    $kuSummaryText.Text =
        "Kindle Unlimited：-"


    $unknownSummaryText.Text =
        ""


    $requestSummaryText.Text =
        ""


    $volumesGrid.ItemsSource =
        $null
}


# ==========================================
# Search action
# ==========================================

function Invoke-MangaWindowSearch {

    $asin =
        $asinBox.Text.Trim()


    if (
        [string]::IsNullOrWhiteSpace(
            $asin
        )
    ) {

        $statusText.Text =
            "ASINを入力してください。"

        return
    }


    Reset-MangaDisplay


    $searchButton.IsEnabled =
        $false


    $asinBox.IsEnabled =
        $false


    $statusText.Text =
        "検索中です..."


    $window.Cursor =
        [System.Windows.Input.Cursors]::Wait


    try {

        $result =
            Get-MangaSeries `
                -SeedASIN $asin `
                -Config $config `
                -AccessToken $accessToken


        # ==================================
        # Series summary
        # ==================================

        $seriesTitleText.Text =
            $result.SeriesTitle


        $volumeSummaryText.Text =
            Get-VolumeSummaryText `
                -Result $result


        $kuSummaryText.Text =
            Get-KUSummaryText `
                -Result $result


        # ==================================
        # Unknown KU summary
        # ==================================

        if (
            $result.UnknownKindleUnlimitedVolumes.Count -gt
            0
        ) {

            $unknownRange =
                ConvertTo-DisplayRange `
                    -Range $result.UnknownKindleUnlimitedRanges


            $unknownSummaryText.Text =
                (
                    "KU判定不明：{0}巻" -f
                    $unknownRange
                )
        }
        else {

            $unknownSummaryText.Text =
                ""
        }


        # ==================================
        # Volume rows
        # ==================================

        $rows =
            @()


        foreach ($volume in $result.Volumes) {

            $kuDisplay =
                "対象外"


            if (
                $volume.IsKindleUnlimited -eq
                $true
            ) {

                $kuDisplay =
                    "対象"
            }
            elseif (
                $null -eq
                $volume.IsKindleUnlimited
            ) {

                $kuDisplay =
                    "不明"
            }


            $rows +=
                [PSCustomObject]@{

                    Volume =
                        $volume.Volume

                    KUDisplay =
                        $kuDisplay

                    Price =
                        $volume.Price

                    Title =
                        $volume.Title

                    ASIN =
                        $volume.ASIN

                    DetailPageURL =
                        $volume.DetailPageURL
                }
        }


        $volumesGrid.ItemsSource =
            @($rows)


        # ==================================
        # Request summary
        # ==================================

        $requestSummaryText.Text =
            (
                "SearchItems: {0} / GetItems: {1} / API合計: {2}" -f
                $result.SearchItemsRequests,
                $result.GetItemsRequests,
                $result.CreatorsApiRequests
            )


        $statusText.Text =
            (
                "{0}巻を取得しました。" -f
                $result.DetectedVolumeCount
            )
    }
    catch {

        Reset-MangaDisplay


        $statusText.Text =
            "検索に失敗しました。"


        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            "Manga Search Error"
        )
    }
    finally {

        $window.Cursor =
            [System.Windows.Input.Cursors]::Arrow


        $searchButton.IsEnabled =
            $true


        $asinBox.IsEnabled =
            $true


        $asinBox.Focus()
    }
}


# ==========================================
# Button event
# ==========================================

$searchButton.Add_Click({

    Invoke-MangaWindowSearch
})


# ==========================================
# Enter key search
# ==========================================

$asinBox.Add_KeyDown({

    param(
        $sender,
        $eventArgs
    )


    if (
        $eventArgs.Key -eq
        [System.Windows.Input.Key]::Enter
    ) {

        Invoke-MangaWindowSearch
    }
})


# ==========================================
# Initial focus
# ==========================================

$window.Add_ContentRendered({

    $asinBox.Focus()
})


# ==========================================
# Show window
# ==========================================

$window.ShowDialog() |
    Out-Null