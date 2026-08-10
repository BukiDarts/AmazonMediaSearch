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
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "itemInfo.classifications",
        "itemInfo.contentInfo",
        "itemInfo.technicalInfo",
        "images.primary.medium"
    )

    $searchKeyword = "$Keyword Audible"

    $searchParams = @{
        Keyword     = $searchKeyword
        SearchIndex = "All"
        Resources   = $resources
        Config      = $Config
        AccessToken = $AccessToken
    }

    $response = Invoke-AmazonSearch @searchParams

    $results = @()

    foreach ($item in $response.searchResult.items) {

        $productGroup = ""

        if ($item.itemInfo.classifications.productGroup) {

            $productGroup =
                $item.itemInfo.classifications.productGroup.displayValue
        }

        if ($productGroup -ne "Audible") {
            continue
        }

        $authors = @()
        $narrators = @()
        $publishers = @()

        if ($item.itemInfo.byLineInfo.contributors) {

            foreach ($contributor in $item.itemInfo.byLineInfo.contributors) {

                switch ($contributor.roleType) {

                    "author" {
                        $authors += $contributor.name
                    }

                    "narrator" {
                        $narrators += $contributor.name
                    }

                    "publisher" {
                        $publishers += $contributor.name
                    }
                }
            }
        }

        $authorText =
            $authors -join ", "

        $narratorText =
            $narrators -join ", "

        $publisherText =
            $publishers -join ", "

        $formatText = ""

        if ($item.itemInfo.technicalInfo.formats.displayValues) {

            $formatText =
                $item.itemInfo.technicalInfo.formats.displayValues -join ", "
        }

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

        $result = [PSCustomObject]@{
            Title       = $item.itemInfo.title.displayValue
            Author      = $authorText
            Narrator    = $narratorText
            Publisher   = $publisherText
            Format      = $formatText
            ReleaseDate = $releaseDate
            ASIN        = $item.asin
            ImageURL    = $imageUrl
            URL         = $item.detailPageURL
        }

        $results += $result
    }

    return $results
}