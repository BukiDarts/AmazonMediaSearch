function Search-Movies {

    param(
        [Parameter(Mandatory)]
        [string]$Keyword,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken
    )

    $resources = @(
        "itemInfo.title"
        "itemInfo.byLineInfo"
        "itemInfo.contentInfo"
        "images.primary.medium"
    )

    $response = Invoke-AmazonSearch `
        -Keyword $Keyword `
        -SearchIndex "MoviesAndTV" `
        -Resources $resources `
        -Config $Config `
        -AccessToken $AccessToken

    $results = @()

    foreach ($item in $response.searchResult.items) {

        $creators = @()

        if ($item.itemInfo.byLineInfo.contributors) {

            foreach (
                $contributor in
                $item.itemInfo.byLineInfo.contributors
            ) {

                if ($contributor.roleType -eq "director") {

                    $creators +=
                        "Director: $($contributor.name)"
                }

                elseif ($contributor.roleType -eq "actor") {

                    $creators +=
                        "Actor: $($contributor.name)"
                }
            }
        }

        $creatorText = $creators -join ", "


        $releaseDate = ""

        if ($item.itemInfo.contentInfo.publicationDate) {
            $releaseDate =
                $item.itemInfo.contentInfo.publicationDate.displayValue
        }


        $imageUrl = ""

        if ($item.images.primary.medium.url) {
            $imageUrl =
                $item.images.primary.medium.url
        }


        $results += [PSCustomObject]@{
            Title       = $item.itemInfo.title.displayValue
            Creator     = $creatorText
            ReleaseDate = $releaseDate
            ASIN        = $item.asin
            ImageURL    = $imageUrl
            URL         = $item.detailPageURL
        }
    }

    return $results
}