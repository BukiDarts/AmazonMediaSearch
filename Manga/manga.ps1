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


$imageCacheDirectory =
    Join-Path `
        $projectRoot `
        "Cache\Manga\Images"


# ==========================================
# Load functions
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"

. "$projectRoot\Core\Invoke-AmazonSearch.ps1"

. "$projectRoot\Core\Invoke-AmazonGetItems.ps1"

. "$projectRoot\Manga\Services\Get-MangaSeries.ps1"

. "$projectRoot\Manga\Services\Get-MangaSeriesCached.ps1"


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
# Create image cache directory
# ==========================================

if (
    -not (
        Test-Path $imageCacheDirectory
    )
) {

    New-Item `
        -ItemType Directory `
        -Path $imageCacheDirectory `
        -Force |
    Out-Null
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


$refreshButton =
    $window.FindName(
        "RefreshButton"
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


$kuCountText =
    $window.FindName(
        "KUCountText"
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


$coverImage =
    $window.FindName(
        "CoverImage"
    )


# ==========================================
# Resolve ASIN
# ==========================================

function Resolve-AmazonASIN {

    param(
        [string]$InputText
    )


    if (
        [string]::IsNullOrWhiteSpace(
            $InputText
        )
    ) {

        return ""
    }


    $text =
        $InputText.Trim()


    if (
        $text -match
        '^[A-Za-z0-9]{10}$'
    ) {

        return $Matches[0].ToUpper()
    }


    if (
        $text -match
        '(?i)/(?:dp|gp/product|gp/aw/d)/([A-Z0-9]{10})(?:[/?]|$)'
    ) {

        return $Matches[1].ToUpper()
    }


    if (
        $text -match
        '(?i)\b([A-Z0-9]{10})\b'
    ) {

        return $Matches[1].ToUpper()
    }


    return ""
}


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
# Load bitmap from local file
# ==========================================

function Get-MangaBitmapFromFile {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )


    if (
        -not (
            Test-Path $Path
        )
    ) {

        return $null
    }


    try {

        $bytes =
            [System.IO.File]::ReadAllBytes(
                $Path
            )


        $memoryStream =
            New-Object `
                System.IO.MemoryStream `
                -ArgumentList @(,$bytes)


        try {

            $bitmap =
                New-Object `
                    System.Windows.Media.Imaging.BitmapImage


            $bitmap.BeginInit()


            $bitmap.CacheOption =
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad


            $bitmap.StreamSource =
                $memoryStream


            $bitmap.EndInit()


            $bitmap.Freeze()


            return $bitmap
        }
        finally {

            $memoryStream.Dispose()
        }
    }
    catch {

        return $null
    }
}


# ==========================================
# Set cover image
# ==========================================

function Set-MangaCoverImage {

    param(
        [string]$ASIN,

        [string]$ImageUrl
    )


    $coverImage.Source =
        $null


    if (
        [string]::IsNullOrWhiteSpace(
            $ASIN
        )
    ) {

        return
    }


    $imageCachePath =
        Join-Path `
            $imageCacheDirectory `
            (
                "{0}.jpg" -f
                $ASIN
            )


    # ======================================
    # Use local image cache first
    # ======================================

    if (
        Test-Path $imageCachePath
    ) {

        $cachedBitmap =
            Get-MangaBitmapFromFile `
                -Path $imageCachePath


        if ($cachedBitmap) {

            $coverImage.Source =
                $cachedBitmap

            return
        }


        Remove-Item `
            $imageCachePath `
            -Force `
            -ErrorAction SilentlyContinue
    }


    # ======================================
    # Download only when local image missing
    # ======================================

    if (
        [string]::IsNullOrWhiteSpace(
            $ImageUrl
        )
    ) {

        return
    }


    $webClient =
        $null


    try {

        $webClient =
            New-Object `
                System.Net.WebClient


        $webClient.Headers.Add(
            "User-Agent",
            "Mozilla/5.0"
        )


        $imageBytes =
            $webClient.DownloadData(
                $ImageUrl
            )


        if (
            $null -eq $imageBytes -or
            $imageBytes.Length -eq 0
        ) {

            return
        }


        try {

            [System.IO.File]::WriteAllBytes(
                $imageCachePath,
                $imageBytes
            )
        }
        catch {

            Write-Host (
                "Failed to cache cover image: {0}" -f
                $_.Exception.Message
            )
        }


        $memoryStream =
            New-Object `
                System.IO.MemoryStream `
                -ArgumentList @(,$imageBytes)


        try {

            $bitmap =
                New-Object `
                    System.Windows.Media.Imaging.BitmapImage


            $bitmap.BeginInit()


            $bitmap.CacheOption =
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad


            $bitmap.StreamSource =
                $memoryStream


            $bitmap.EndInit()


            $bitmap.Freeze()


            $coverImage.Source =
                $bitmap
        }
        finally {

            $memoryStream.Dispose()
        }
    }
    catch {

        $coverImage.Source =
            $null


        Write-Host (
            "Failed to load cover image: {0}" -f
            $_.Exception.Message
        )
    }
    finally {

        if ($webClient) {

            $webClient.Dispose()
        }
    }
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


    $kuCountText.Text =
        ""


    $unknownSummaryText.Text =
        ""


    $requestSummaryText.Text =
        ""


    $volumesGrid.ItemsSource =
        $null


    $coverImage.Source =
        $null
}


# ==========================================
# Search action
# ==========================================

function Invoke-MangaWindowSearch {

    param(
        [switch]$ForceRefresh
    )


    $inputText =
        $asinBox.Text.Trim()


    if (
        [string]::IsNullOrWhiteSpace(
            $inputText
        )
    ) {

        $statusText.Text =
            "ASINまたはAmazon商品URLを入力してください。"

        return
    }


    $asin =
        Resolve-AmazonASIN `
            -InputText $inputText


    if (
        [string]::IsNullOrWhiteSpace(
            $asin
        )
    ) {

        $statusText.Text =
            "ASINを判定できませんでした。"

        return
    }


    $asinBox.Text =
        $asin


    Reset-MangaDisplay


    $searchButton.IsEnabled =
        $false


    $refreshButton.IsEnabled =
        $false


    $asinBox.IsEnabled =
        $false


    if ($ForceRefresh) {

        $statusText.Text =
            "最新情報を再取得しています..."
    }
    else {

        $statusText.Text =
            "検索中です..."
    }


    $window.Cursor =
        [System.Windows.Input.Cursors]::Wait


    try {

        if ($ForceRefresh) {

            $result =
                Get-MangaSeriesCached `
                    -SeedASIN $asin `
                    -Config $config `
                    -CacheHours 6 `
                    -ForceRefresh
        }
        else {

            $result =
                Get-MangaSeriesCached `
                    -SeedASIN $asin `
                    -Config $config `
                    -CacheHours 6
        }


        # ==================================
        # Cover image
        # ==================================

        Set-MangaCoverImage `
            -ASIN $asin `
            -ImageUrl $result.SeedImageURL


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


        $kuCountText.Text =
            (
                "KU対象：{0} / {1}巻" -f
                $result.KindleUnlimitedVolumeCount,
                $result.DetectedVolumeCount
            )


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

                    ImageURL =
                        $volume.ImageURL

                    DetailPageURL =
                        $volume.DetailPageURL
                }
        }


        $volumesGrid.ItemsSource =
            @($rows)


        # ==================================
        # Request summary
        # ==================================

        if (
            $result.CacheStatus -eq
            "Hit"
        ) {

            $requestSummaryText.Text =
                (
                    "Cache: Hit / OAuth: 0 / Creators API: 0 / 通信なし"
                )
        }
        else {

            $requestSummaryText.Text =
                (
                    "Cache: Miss / OAuth: {0} / SearchItems: {1} / GetItems: {2} / Creators API: {3}" -f
                    $result.CurrentOAuthRequests,
                    $result.SearchItemsRequests,
                    $result.GetItemsRequests,
                    $result.CurrentCreatorsApiRequests
                )
        }


        # ==================================
        # Status
        # ==================================

        if (
            $result.CacheStatus -eq
            "Hit"
        ) {

            $statusText.Text =
                (
                    "{0}巻をローカルキャッシュから読み込みました。" -f
                    $result.DetectedVolumeCount
                )
        }
        elseif ($ForceRefresh) {

            $statusText.Text =
                (
                    "{0}巻の最新情報を取得しました。" -f
                    $result.DetectedVolumeCount
                )
        }
        else {

            $statusText.Text =
                (
                    "{0}巻を取得しました。" -f
                    $result.DetectedVolumeCount
                )
        }
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


        $refreshButton.IsEnabled =
            $true


        $asinBox.IsEnabled =
            $true


        $asinBox.Focus()
    }
}


# ==========================================
# Search button
# ==========================================

$searchButton.Add_Click({

    Invoke-MangaWindowSearch
})


# ==========================================
# Refresh button
# ==========================================

$refreshButton.Add_Click({

    Invoke-MangaWindowSearch `
        -ForceRefresh
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
# Open selected Amazon page
# ==========================================

$volumesGrid.Add_MouseDoubleClick({

    $selectedItem =
        $volumesGrid.SelectedItem


    if (-not $selectedItem) {

        return
    }


    $url =
        [string]$selectedItem.DetailPageURL


    if (
        [string]::IsNullOrWhiteSpace(
            $url
        )
    ) {

        return
    }


    try {

        Start-Process $url
    }
    catch {

        [System.Windows.MessageBox]::Show(
            "Failed to open the product page."
        )
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