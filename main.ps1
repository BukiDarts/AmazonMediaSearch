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
# Load config
# ==========================================
$configPath = Join-Path $PSScriptRoot "config.json"

if (-not (Test-Path $configPath)) {

    [System.Windows.MessageBox]::Show(
        "config.json not found.",
        "Error"
    )

    exit
}

$config = Get-Content $configPath -Raw |
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

$xaml = Get-Content $xamlPath -Raw

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

$statusText =
    $window.FindName("StatusText")

$categoryBox =
    $window.FindName("CategoryBox")


# ==========================================
# Open Amazon product page
# ==========================================
$resultGrid.AddHandler(
    [System.Windows.Controls.Button]::ClickEvent,
    [System.Windows.RoutedEventHandler]{

        param($sender, $e)

        $button = $e.OriginalSource

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

            $e.Handled = $true
        }
    }
)


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


    $statusText.Text = "Searching..."


    try {

        switch ($selectedCategory) {

            "Books" {

                $results =
                    Search-Books `
                        -Keyword $keyword `
                        -Config $config `
                        -AccessToken $accessToken
            }


            "Kindle" {

                $results =
                    Search-Kindle `
                        -Keyword $keyword `
                        -Config $config `
                        -AccessToken $accessToken
            }


            "Movies" {

                $results =
                    Search-Movies `
                        -Keyword $keyword `
                        -Config $config `
                        -AccessToken $accessToken
            }


            "Audible" {

                $results =
                    Search-Audible `
                        -Keyword $keyword `
                        -Config $config `
                        -AccessToken $accessToken
            }


            default {

                $results = @()
            }
        }


        $resultGrid.ItemsSource =
            $results


        $statusText.Text =
            "$selectedCategory / $($results.Count) results"

    }
    catch {

        $statusText.Text = "Error"

        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            "Search Error"
        )
    }
}


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
# Show window
# ==========================================
$window.ShowDialog() | Out-Null