function Search-Audible {

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

    $searchKeyword = "$Keyword Audible"

    $response = Invoke-AmazonSearch `
        -Keyword $searchKeyword `
        -SearchIndex "All" `
        -Resources $resources `
        -Config $Config `
        -AccessToken $AccessToken

    $results = @()

    foreach ($item in $response.searchResult.items) {

        $authors = @()

        if ($item.itemInfo.byLineInfo.contributors) {

            foreach (
                $contributor in
                $item.itemInfo.byLineInfo.contributors
            ) {

                if ($contributor.roleType -eq "author") {
                    $authors += $contributor.name
                }
            }
        }

        $creatorText = $authors -join ", "


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