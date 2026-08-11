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

$resultGrid =
    $window.FindName("ResultGrid")

$audibleGrid =
    $window.FindName("AudibleGrid")

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


# ==========================================
# Open Amazon product page
# ==========================================

$resultGrid.AddHandler(
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


$audibleGrid.AddHandler(
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


# ==========================================
# UI mode
# ==========================================

function Set-CategoryUI {

    param(
        [Parameter(Mandatory)]
        [string]$Category
    )

    if ($Category -eq "Audible") {

        $resultGridBorder.Visibility =
            [System.Windows.Visibility]::Collapsed

        $audibleGridBorder.Visibility =
            [System.Windows.Visibility]::Visible

        $sortBox.Visibility =
            [System.Windows.Visibility]::Visible

        $filterBox.Visibility =
            [System.Windows.Visibility]::Visible
    }
    else {

        $resultGridBorder.Visibility =
            [System.Windows.Visibility]::Visible

        $audibleGridBorder.Visibility =
            [System.Windows.Visibility]::Collapsed

        $sortBox.Visibility =
            [System.Windows.Visibility]::Collapsed

        $filterBox.Visibility =
            [System.Windows.Visibility]::Collapsed
    }
}


# ==========================================
# Audible filter
# ==========================================

function Apply-AudibleFilter {

    $allResults =
        @($script:audibleAllResults)

    if (-not $filterBox.SelectedItem) {

        $audibleGrid.ItemsSource =
            $allResults

        return
    }

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
            "Audible / $($filteredResults.Count) results"
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

            "Books" {

                $searchParams = @{
                    Keyword     = $keyword
                    Config      = $config
                    AccessToken = $accessToken
                }

                $results =
                    Search-Books @searchParams

                $resultGrid.ItemsSource =
                    $results

                $audibleGrid.ItemsSource =
                    $null

                $script:audibleAllResults =
                    @()

                $statusText.Text =
                    "Books / $($results.Count) results"
            }


            "Kindle" {

                $searchParams = @{
                    Keyword     = $keyword
                    Config      = $config
                    AccessToken = $accessToken
                }

                $results =
                    Search-Kindle @searchParams

                $resultGrid.ItemsSource =
                    $results

                $audibleGrid.ItemsSource =
                    $null

                $script:audibleAllResults =
                    @()

                $statusText.Text =
                    "Kindle / $($results.Count) results"
            }


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

                $audibleGrid.ItemsSource =
                    $null

                $script:audibleAllResults =
                    @()

                $statusText.Text =
                    "Movies / $($results.Count) results"
            }


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

                $resultGrid.ItemsSource =
                    $null

                Apply-AudibleFilter
            }


            default {

                $results =
                    @()

                $statusText.Text =
                    "0 results"
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

        Set-CategoryUI `
            -Category $selectedCategory
    }
})


# ==========================================
# Filter change
# ==========================================

$filterBox.Add_SelectionChanged({

    if (
        $categoryBox.SelectedItem -and
        $categoryBox.SelectedItem.Content.ToString() -eq "Audible"
    ) {

        Apply-AudibleFilter
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