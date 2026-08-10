Add-Type -AssemblyName PresentationFramework

# Load config
$configPath = Join-Path $PSScriptRoot "config.json"

if (-not (Test-Path $configPath)) {
    [System.Windows.MessageBox]::Show(
        "config.json not found.",
        "Error"
    )
    exit
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json


# Get access token
$authBody = @{
    grant_type    = "client_credentials"
    client_id     = $config.CredentialId
    client_secret = $config.Secret
    scope         = "creatorsapi::default"
}

$authParameters = @{
    Uri         = $config.AuthUrl
    Method      = "Post"
    ContentType = "application/json"
    Body        = ($authBody | ConvertTo-Json)
}

try {
    $authResponse = Invoke-RestMethod @authParameters
    $accessToken = $authResponse.access_token
}
catch {
    [System.Windows.MessageBox]::Show(
        $_.Exception.Message,
        "Authentication Error"
    )
    exit
}


# Load XAML
$xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"

if (-not (Test-Path $xamlPath)) {
    [System.Windows.MessageBox]::Show(
        "MainWindow.xaml not found.",
        "Error"
    )
    exit
}

$xaml = Get-Content $xamlPath -Raw

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)


# Get controls
$searchBox = $window.FindName("SearchBox")
$searchButton = $window.FindName("SearchButton")
$resultGrid = $window.FindName("ResultGrid")
$statusText = $window.FindName("StatusText")
$categoryBox = $window.FindName("CategoryBox")


# Open Amazon product page
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
                [System.Windows.Media.VisualTreeHelper]::GetParent($button)
        }

        if ($button -and $button.Tag) {

            Start-Process $button.Tag.ToString()

            $e.Handled = $true
        }
    }
)


# Search Amazon
function Search-AmazonItem {

    $keyword = $searchBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($keyword)) {
        [System.Windows.MessageBox]::Show(
            "Please enter a keyword.",
            "Search"
        )
        return
    }


    $selectedCategory =
        $categoryBox.SelectedItem.Content.ToString()


    # Category settings
    switch ($selectedCategory) {

        "Books" {
            $searchIndex = "Books"
            $searchKeyword = $keyword
        }

        "Kindle" {
            $searchIndex = "KindleStore"
            $searchKeyword = $keyword
        }

        "Movies" {
            $searchIndex = "MoviesAndTV"
            $searchKeyword = $keyword
        }

        "Audible" {
            $searchIndex = "All"
            $searchKeyword = "$keyword Audible"
        }

        default {
            $searchIndex = "All"
            $searchKeyword = $keyword
        }
    }


    $statusText.Text = "Searching..."


    $searchBody = @{
        partnerTag  = $config.PartnerTag
        keywords    = $searchKeyword
        searchIndex = $searchIndex
        itemCount   = 10

        resources = @(
            "itemInfo.title"
            "itemInfo.byLineInfo"
            "itemInfo.contentInfo"
            "images.primary.medium"
        )
    }


    $searchJson =
        $searchBody | ConvertTo-Json -Depth 10

    $searchBytes =
        [System.Text.Encoding]::UTF8.GetBytes($searchJson)


    $headers = @{
        Authorization   = "Bearer $accessToken"
        "x-marketplace" = $config.Marketplace
    }


    $searchParameters = @{
        Uri         = $config.SearchUrl
        Method      = "Post"
        Headers     = $headers
        ContentType = "application/json; charset=utf-8"
        Body        = $searchBytes
    }


    try {

        $webResponse =
            Invoke-WebRequest @searchParameters -UseBasicParsing

        $responseBytes =
            $webResponse.RawContentStream.ToArray()

        $responseText =
            [System.Text.Encoding]::UTF8.GetString(
                $responseBytes
            )

        $response =
            $responseText | ConvertFrom-Json


        $results = @()


        foreach ($item in $response.searchResult.items) {

            $creators = @()


            if ($item.itemInfo.byLineInfo.contributors) {

                foreach (
                    $contributor in
                    $item.itemInfo.byLineInfo.contributors
                ) {

                    if (
                        $selectedCategory -eq "Books" -or
                        $selectedCategory -eq "Kindle" -or
                        $selectedCategory -eq "Audible"
                    ) {

                        if (
                            $contributor.roleType -eq "author"
                        ) {
                            $creators += $contributor.name
                        }
                    }


                    elseif ($selectedCategory -eq "Movies") {

                        if (
                            $contributor.roleType -eq "director"
                        ) {
                            $creators +=
                                "Director: $($contributor.name)"
                        }

                        elseif (
                            $contributor.roleType -eq "actor"
                        ) {
                            $creators +=
                                "Actor: $($contributor.name)"
                        }
                    }
                }
            }


            $creatorText =
                $creators -join ", "


            $releaseDate = ""

            if (
                $item.itemInfo.contentInfo.publicationDate
            ) {

                $releaseDate =
                    $item.itemInfo.contentInfo.publicationDate.displayValue
            }


            $imageUrl = ""

            if (
                $item.images.primary.medium.url
            ) {

                $imageUrl =
                    $item.images.primary.medium.url
            }


            $result = [PSCustomObject]@{

                Title =
                    $item.itemInfo.title.displayValue

                Creator =
                    $creatorText

                ReleaseDate =
                    $releaseDate

                ASIN =
                    $item.asin

                ImageURL =
                    $imageUrl

                URL =
                    $item.detailPageURL
            }


            $results += $result
        }


        $resultGrid.ItemsSource = $results

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


# Search button
$searchButton.Add_Click({
    Search-AmazonItem
})


# Enter key
$searchBox.Add_KeyDown({

    if ($_.Key -eq "Return") {
        Search-AmazonItem
    }

})


# Show window
$window.ShowDialog() | Out-Null