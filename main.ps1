Add-Type -AssemblyName PresentationFramework

# ==========================================
# Load modules
# ==========================================

. "$PSScriptRoot\Core\Get-AmazonAccessToken.ps1"
. "$PSScriptRoot\Core\Invoke-AmazonSearch.ps1"

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

if (-not (Test-Path $xamlPath)) {

    [System.Windows.MessageBox]::Show(
        "MainWindow.xaml not found.",
        "Error"
    )

    exit
}

$xaml =
    Get-Content $xamlPath -Raw

$reader =
    New-Object System.Xml.XmlNodeReader ([xml]$xaml)

$window =
    [Windows.Markup.XamlReader]::Load($reader)


# ==========================================
# Get controls
# ==========================================

$searchBox =
    $window.FindName("SearchBox")

$searchButton =
    $window.FindName("SearchButton")

$booksGrid =
    $window.FindName("BooksGrid")

$kindleGrid =
    $window.FindName("KindleGrid")

$resultGrid =
    $window.FindName("ResultGrid")

$audibleGrid =
    $window.FindName("AudibleGrid")


$booksGridBorder =
    $window.FindName("BooksGridBorder")

$kindleGridBorder =
    $window.FindName("KindleGridBorder")

$resultGridBorder =
    $window.FindName("ResultGridBorder")

$audibleGridBorder =
    $window.FindName("AudibleGridBorder")


$statusText =
    $window.FindName("StatusText")

$categoryBox =
    $window.FindName("CategoryBox")

$sortBox =
    $window.FindName("SortBox")

$filterBox =
    $window.FindName("FilterBox")

$includedFilterItem =
    $window.FindName("IncludedFilterItem")


# ==========================================
# Open Amazon product page
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
Add-AmazonButtonHandler -Grid $resultGrid
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

    $resultGridBorder.Visibility =
        [System.Windows.Visibility]::Collapsed

    $audibleGridBorder.Visibility =
        [System.Windows.Visibility]::Collapsed

    $sortBox.Visibility =
        [System.Windows.Visibility]::Collapsed

    $filterBox.Visibility =
        [System.Windows.Visibility]::Collapsed

    $includedFilterItem.Visibility =
        [System.Windows.Visibility]::Collapsed


    switch ($Category) {

        "Books" {

            $booksGridBorder.Visibility =
                [System.Windows.Visibility]::Visible

            $sortBox.Visibility =
                [System.Windows.Visibility]::Visible

            $filterBox.Visibility =
                [System.Windows.Visibility]::Visible
        }


        "Kindle" {

            $kindleGridBorder.Visibility =
                [System.Windows.Visibility]::Visible

            $sortBox.Visibility =
                [System.Windows.Visibility]::Visible

            $filterBox.Visibility =
                [System.Windows.Visibility]::Visible
        }


        "Movies" {

            $resultGridBorder.Visibility =
                [System.Windows.Visibility]::Visible
        }


        "Audible" {

            $audibleGridBorder.Visibility =
                [System.Windows.Visibility]::Visible

            $sortBox.Visibility =
                [System.Windows.Visibility]::Visible

            $filterBox.Visibility =
                [System.Windows.Visibility]::Visible

            $includedFilterItem.Visibility =
                [System.Windows.Visibility]::Visible
        }
    }
}


# ==========================================
# Books filter
# ==========================================

function Apply-BooksFilter {

    $allResults =
        @($script:booksAllResults)

    $totalResultCount =
        $script:booksTotalResultCount


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


    $booksGrid.ItemsSource =
        $filteredResults


    if ($filter -eq "All") {

        if ($totalResultCount -gt $allResults.Count) {

            $statusText.Text =
                "Books / $($allResults.Count) of $totalResultCount results"
        }
        else {

            $statusText.Text =
                "Books / $($allResults.Count) results"
        }
    }
    else {

        if ($totalResultCount -gt $allResults.Count) {

            $statusText.Text =
                "Books / $($filteredResults.Count) filtered / $($allResults.Count) of $totalResultCount retrieved"
        }
        else {

            $statusText.Text =
                "Books / $($filteredResults.Count) of $($allResults.Count) results"
        }
    }
}


# ==========================================
# Kindle filter
# ==========================================

function Apply-KindleFilter {

    $allResults =
        @($script:kindleAllResults)

    $totalResultCount =
        $script:kindleTotalResultCount


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


    if ($filter -eq "All") {

        if ($totalResultCount -gt $allResults.Count) {

            $statusText.Text =
                "Kindle / $($allResults.Count) of $totalResultCount results"
        }
        else {

            $statusText.Text =
                "Kindle / $($allResults.Count) results"
        }
    }
    else {

        if ($totalResultCount -gt $allResults.Count) {

            $statusText.Text =
                "Kindle / $($filteredResults.Count) filtered / $($allResults.Count) of $totalResultCount retrieved"
        }
        else {

            $statusText.Text =
                "Kindle / $($filteredResults.Count) of $($allResults.Count) results"
        }
    }
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


    $selectedCategory =
        $categoryBox.SelectedItem.Content.ToString()


    Set-CategoryUI `
        -Category $selectedCategory


    $statusText.Text =
        "Searching..."


    try {

        switch ($selectedCategory) {


            # Books
            "Books" {

                $sortBy =
                    $sortBox.SelectedItem.Tag.ToString()

                $searchParams = @{
                    Keyword     = $keyword
                    Config      = $config
                    AccessToken = $accessToken
                    SortBy      = $sortBy
                }

                $searchResult =
                    Search-Books @searchParams


                $script:booksAllResults =
                    @($searchResult.Items)

                $script:booksTotalResultCount =
                    [int]$searchResult.TotalResultCount


                $kindleGrid.ItemsSource =
                    $null

                $resultGrid.ItemsSource =
                    $null

                $audibleGrid.ItemsSource =
                    $null


                Apply-BooksFilter
            }


            # Kindle
            "Kindle" {

                $sortBy =
                    $sortBox.SelectedItem.Tag.ToString()

                $searchParams = @{
                    Keyword     = $keyword
                    Config      = $config
                    AccessToken = $accessToken
                    SortBy      = $sortBy
                }

                $searchResult =
                    Search-Kindle @searchParams


                $script:kindleAllResults =
                    @($searchResult.Items)

                $script:kindleTotalResultCount =
                    [int]$searchResult.TotalResultCount


                $booksGrid.ItemsSource =
                    $null

                $resultGrid.ItemsSource =
                    $null

                $audibleGrid.ItemsSource =
                    $null


                Apply-KindleFilter
            }


            # Movies
            "Movies" {

                $searchParams = @{
                    Keyword     = $keyword
                    Config      = $config
                    AccessToken = $accessToken
                }

                $results =
                    Search-Movies @searchParams


                $resultGrid.ItemsSource =
                    $results

                $booksGrid.ItemsSource =
                    $null

                $kindleGrid.ItemsSource =
                    $null

                $audibleGrid.ItemsSource =
                    $null


                $statusText.Text =
                    "Movies / $($results.Count) results"
            }


            # Audible
            "Audible" {

                $sortBy =
                    $sortBox.SelectedItem.Tag.ToString()

                $searchParams = @{
                    Keyword     = $keyword
                    Config      = $config
                    AccessToken = $accessToken
                    SortBy      = $sortBy
                }


                $results =
                    Search-Audible @searchParams


                $script:audibleAllResults =
                    @($results)


                $booksGrid.ItemsSource =
                    $null

                $kindleGrid.ItemsSource =
                    $null

                $resultGrid.ItemsSource =
                    $null


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

        $selectedCategory =
            $categoryBox.SelectedItem.Content.ToString()


        $filterBox.SelectedIndex =
            0


        Set-CategoryUI `
            -Category $selectedCategory
    }
})


# ==========================================
# Filter change
# ==========================================

$filterBox.Add_SelectionChanged({

    if (-not $categoryBox.SelectedItem) {
        return
    }


    $selectedCategory =
        $categoryBox.SelectedItem.Content.ToString()


    switch ($selectedCategory) {

        "Books" {

            Apply-BooksFilter
        }


        "Kindle" {

            Apply-KindleFilter
        }


        "Audible" {

            Apply-AudibleFilter
        }
    }
})


# ==========================================
# Search button
# ==========================================

$searchButton.Add_Click({

    Start-AmazonSearch
})


# ==========================================
# Enter key
# ==========================================

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
# Show window
# ==========================================

$window.ShowDialog() |
    Out-Null