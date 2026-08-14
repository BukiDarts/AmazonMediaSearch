Add-Type -AssemblyName PresentationFramework

# ==========================================
# Load modules
# ==========================================

. "$PSScriptRoot\Core\Get-AmazonAccessToken.ps1"
. "$PSScriptRoot\Core\Invoke-AmazonSearch.ps1"
. "$PSScriptRoot\Core\Test-AmazonAuthorMatch.ps1"

. "$PSScriptRoot\Categories\Books.ps1"
. "$PSScriptRoot\Categories\Kindle.ps1"
. "$PSScriptRoot\Categories\Movies.ps1"
. "$PSScriptRoot\Categories\Audible.ps1"


# ==========================================
# Runtime data
# ==========================================

$script:booksAllResults = @()
$script:booksTotalResultCount = 0

$script:kindleAllResults = @()
$script:kindleTotalResultCount = 0

$script:moviesAllResults = @()
$script:moviesTotalResultCount = 0

$script:audibleAllResults = @()


# ==========================================
# Load config
# ==========================================

$configPath =
    Join-Path $PSScriptRoot "config.json"

if (-not (Test-Path $configPath)) {

    [System.Windows.MessageBox]::Show(
        "config.json not found.",
        "Error"
    )

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

    [System.Windows.MessageBox]::Show(
        $_.Exception.Message,
        "Authentication Error"
    )

    exit
}


# ==========================================
# Load XAML
# ==========================================

$xamlPath =
    Join-Path $PSScriptRoot "MainWindow.xaml"

$xaml =
    Get-Content $xamlPath -Raw

$reader =
    New-Object System.Xml.XmlNodeReader ([xml]$xaml)

$window =
    [Windows.Markup.XamlReader]::Load($reader)


# ==========================================
# Controls
# ==========================================

$searchBox =
    $window.FindName("SearchBox")

$searchButton =
    $window.FindName("SearchButton")

$booksGrid =
    $window.FindName("BooksGrid")

$kindleGrid =
    $window.FindName("KindleGrid")

$moviesGrid =
    $window.FindName("MoviesGrid")

$audibleGrid =
    $window.FindName("AudibleGrid")


$booksGridBorder =
    $window.FindName("BooksGridBorder")

$kindleGridBorder =
    $window.FindName("KindleGridBorder")

$moviesGridBorder =
    $window.FindName("MoviesGridBorder")

$audibleGridBorder =
    $window.FindName("AudibleGridBorder")


$statusText =
    $window.FindName("StatusText")

$categoryBox =
    $window.FindName("CategoryBox")

$searchModeBox =
    $window.FindName("SearchModeBox")

$sortBox =
    $window.FindName("SortBox")

$filterBox =
    $window.FindName("FilterBox")

$includedFilterItem =
    $window.FindName("IncludedFilterItem")

$kuFilterItem =
    $window.FindName("KUFilterItem")

$limitedFreeFilterItem =
    $window.FindName("LimitedFreeFilterItem")


# ==========================================
# Amazon buttons
# ==========================================

function Add-AmazonButtonHandler {

    param(
        [Parameter(Mandatory)]
        $Grid
    )

    $Grid.AddHandler(
        [System.Windows.Controls.Button]::ClickEvent,
        [System.Windows.RoutedEventHandler]{

            param($sender, $e)

            $button =
                $e.OriginalSource

            while (
                $button -and
                -not ($button -is [System.Windows.Controls.Button])
            ) {

                $button =
                    [System.Windows.Media.VisualTreeHelper]::GetParent(
                        $button
                    )
            }

            if ($button -and $button.Tag) {

                Start-Process $button.Tag.ToString()

                $e.Handled =
                    $true
            }
        }
    )
}


Add-AmazonButtonHandler -Grid $booksGrid
Add-AmazonButtonHandler -Grid $kindleGrid
Add-AmazonButtonHandler -Grid $moviesGrid
Add-AmazonButtonHandler -Grid $audibleGrid


# ==========================================
# UI mode
# ==========================================

function Set-CategoryUI {

    param(
        [Parameter(Mandatory)]
        [string]$Category
    )


    $booksGridBorder.Visibility =
        [System.Windows.Visibility]::Collapsed

    $kindleGridBorder.Visibility =
        [System.Windows.Visibility]::Collapsed

    $moviesGridBorder.Visibility =
        [System.Windows.Visibility]::Collapsed

    $audibleGridBorder.Visibility =
        [System.Windows.Visibility]::Collapsed


    $sortBox.Visibility =
        [System.Windows.Visibility]::Visible

    $filterBox.Visibility =
        [System.Windows.Visibility]::Visible

    $includedFilterItem.Visibility =
        [System.Windows.Visibility]::Collapsed

    $kuFilterItem.Visibility =
        [System.Windows.Visibility]::Collapsed

    $limitedFreeFilterItem.Visibility =
        [System.Windows.Visibility]::Collapsed


    $searchModeBox.IsEnabled =
        $true


    switch ($Category) {

        "Books" {

            $booksGridBorder.Visibility =
                [System.Windows.Visibility]::Visible
        }


        "Kindle" {

            $kindleGridBorder.Visibility =
                [System.Windows.Visibility]::Visible

            $kuFilterItem.Visibility =
                [System.Windows.Visibility]::Visible

            $limitedFreeFilterItem.Visibility =
                [System.Windows.Visibility]::Visible
        }


        "Movies" {

            $moviesGridBorder.Visibility =
                [System.Windows.Visibility]::Visible


            $searchModeBox.SelectedIndex =
                0


            $searchModeBox.IsEnabled =
                $false
        }


        "Audible" {

            $audibleGridBorder.Visibility =
                [System.Windows.Visibility]::Visible

            $includedFilterItem.Visibility =
                [System.Windows.Visibility]::Visible
        }
    }
}


# ==========================================
# Common status helper
# ==========================================

function Set-ResultStatus {

    param(
        [string]$Category,
        [array]$AllResults,
        [array]$FilteredResults,
        [int]$TotalResultCount,
        [string]$Filter
    )


    if ($Filter -eq "All") {

        if ($TotalResultCount -gt $AllResults.Count) {

            $statusText.Text =
                "$Category / $($AllResults.Count) of $TotalResultCount results"
        }
        else {

            $statusText.Text =
                "$Category / $($AllResults.Count) results"
        }
    }
    else {

        if ($TotalResultCount -gt $AllResults.Count) {

            $statusText.Text =
                "$Category / $($FilteredResults.Count) filtered / $($AllResults.Count) of $TotalResultCount retrieved"
        }
        else {

            $statusText.Text =
                "$Category / $($FilteredResults.Count) of $($AllResults.Count) results"
        }
    }
}


# ==========================================
# Books filter
# ==========================================

function Apply-BooksFilter {

    $allResults =
        @($script:booksAllResults)

    $filter =
        $filterBox.SelectedItem.Tag.ToString()


    switch ($filter) {

        "Released" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.AvailabilityType -eq "IN_STOCK"
                    }
                )
        }

        "Preorder" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.AvailabilityType -eq "PREORDER"
                    }
                )
        }

        "KindleUnlimited" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.KindleUnlimited -eq $true
                    }
                )
        }

        "LimitedFree" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.LimitedFree -eq $true
                    }
                )
        }

        default {

            $filteredResults =
                $allResults
        }
    }


    $booksGrid.ItemsSource =
        $filteredResults


    Set-ResultStatus `
        -Category "Books" `
        -AllResults $allResults `
        -FilteredResults $filteredResults `
        -TotalResultCount $script:booksTotalResultCount `
        -Filter $filter
}


# ==========================================
# Kindle filter
# ==========================================

function Apply-KindleFilter {

    $allResults =
        @($script:kindleAllResults)

    $filter =
        $filterBox.SelectedItem.Tag.ToString()


    switch ($filter) {

        "Released" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.AvailabilityType -eq "IN_STOCK"
                    }
                )
        }

        "Preorder" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.AvailabilityType -eq "PREORDER"
                    }
                )
        }

        default {

            $filteredResults =
                $allResults
        }
    }


    $kindleGrid.ItemsSource =
        $filteredResults


    Set-ResultStatus `
        -Category "Kindle" `
        -AllResults $allResults `
        -FilteredResults $filteredResults `
        -TotalResultCount $script:kindleTotalResultCount `
        -Filter $filter
}


# ==========================================
# Movies filter
# ==========================================

function Apply-MoviesFilter {

    $allResults =
        @($script:moviesAllResults)

    $filter =
        $filterBox.SelectedItem.Tag.ToString()


    switch ($filter) {

        "Released" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.AvailabilityType -eq "IN_STOCK"
                    }
                )
        }

        "Preorder" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.AvailabilityType -eq "PREORDER"
                    }
                )
        }

        default {

            $filteredResults =
                $allResults
        }
    }


    $moviesGrid.ItemsSource =
        $filteredResults


    Set-ResultStatus `
        -Category "Movies" `
        -AllResults $allResults `
        -FilteredResults $filteredResults `
        -TotalResultCount $script:moviesTotalResultCount `
        -Filter $filter
}


# ==========================================
# Audible filter
# ==========================================

function Apply-AudibleFilter {

    $allResults =
        @($script:audibleAllResults)

    $filter =
        $filterBox.SelectedItem.Tag.ToString()


    switch ($filter) {

        "Released" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.AvailabilityType -eq "IN_STOCK"
                    }
                )
        }

        "Preorder" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.AvailabilityType -eq "PREORDER"
                    }
                )
        }

        "Included" {

            $filteredResults =
                @(
                    $allResults |
                    Where-Object {
                        $_.IsAdditionalChargeFree -eq $true
                    }
                )
        }

        default {

            $filteredResults =
                $allResults
        }
    }


    $audibleGrid.ItemsSource =
        $filteredResults


    if ($filter -eq "All") {

        $statusText.Text =
            "Audible / $($allResults.Count) results"
    }
    else {

        $statusText.Text =
            "Audible / $($filteredResults.Count) of $($allResults.Count) results"
    }
}


# ==========================================
# Search
# ==========================================

function Start-AmazonSearch {

    $keyword =
        $searchBox.Text.Trim()


    if ([string]::IsNullOrWhiteSpace($keyword)) {

        [System.Windows.MessageBox]::Show(
            "Please enter a keyword.",
            "Search"
        )

        return
    }


    $category =
        $categoryBox.SelectedItem.Content.ToString()

    $sortBy =
        $sortBox.SelectedItem.Tag.ToString()


    $searchMode =
        $searchModeBox.SelectedItem.Tag.ToString()


    Set-CategoryUI -Category $category

    $statusText.Text =
        "Searching..."


    try {

        switch ($category) {


            "Books" {

                $result =
                    Search-Books `
                        -Keyword $keyword `
                        -Config $config `
                        -AccessToken $accessToken `
                        -SortBy $sortBy `
                        -SearchMode $searchMode

                $script:booksAllResults =
                    @($result.Items)

                $script:booksTotalResultCount =
                    [int]$result.TotalResultCount

                Apply-BooksFilter
            }


            "Kindle" {

                $result =
                    Search-Kindle `
                        -Keyword $keyword `
                        -Config $config `
                        -AccessToken $accessToken `
                        -SortBy $sortBy `
                        -SearchMode $searchMode

                $script:kindleAllResults =
                    @($result.Items)

                $script:kindleTotalResultCount =
                    [int]$result.TotalResultCount

                Apply-KindleFilter
            }


            "Movies" {

                $result =
                    Search-Movies `
                        -Keyword $keyword `
                        -Config $config `
                        -AccessToken $accessToken `
                        -SortBy $sortBy

                $script:moviesAllResults =
                    @($result.Items)

                $script:moviesTotalResultCount =
                    [int]$result.TotalResultCount

                Apply-MoviesFilter
            }


            "Audible" {

                $results =
                    Search-Audible `
                        -Keyword $keyword `
                        -Config $config `
                        -AccessToken $accessToken `
                        -SortBy $sortBy `
                        -SearchMode $searchMode

                $script:audibleAllResults =
                    @($results)

                Apply-AudibleFilter
            }
        }
    }
    catch {

        $statusText.Text =
            "Error"

        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            "Search Error"
        )
    }
}


# ==========================================
# Category change
# ==========================================

$categoryBox.Add_SelectionChanged({

    if ($categoryBox.SelectedItem) {

        $filterBox.SelectedIndex =
            0

        $category =
            $categoryBox.SelectedItem.Content.ToString()

        Set-CategoryUI -Category $category
    }
})


# ==========================================
# Filter change
# ==========================================

$filterBox.Add_SelectionChanged({

    if (-not $categoryBox.SelectedItem) {
        return
    }


    $category =
        $categoryBox.SelectedItem.Content.ToString()


    switch ($category) {

        "Books" {

            Apply-BooksFilter
        }

        "Kindle" {

            Apply-KindleFilter
        }

        "Movies" {

            Apply-MoviesFilter
        }

        "Audible" {

            Apply-AudibleFilter
        }
    }
})


# ==========================================
# Search
# ==========================================

$searchButton.Add_Click({

    Start-AmazonSearch
})


$searchBox.Add_KeyDown({

    if ($_.Key -eq "Return") {

        Start-AmazonSearch
    }
})


# ==========================================
# Initial display
# ==========================================

Set-CategoryUI -Category "Books"


# ==========================================
# Show
# ==========================================

$window.ShowDialog() |
    Out-Null