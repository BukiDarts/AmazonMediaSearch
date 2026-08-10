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
        "images.primary.medium",
        "offersV2.listings.price",
        "offersV2.listings.availability",
        "offersV2.listings.isBuyBoxWinner"
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

        # Check product group
        $productGroup = ""

        if ($item.itemInfo.classifications.productGroup) {

            $productGroup =
                $item.itemInfo.classifications.productGroup.displayValue
        }

        # Skip non-Audible products
        if ($productGroup -ne "Audible") {
            continue
        }


        # Contributors
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


        # Format
        $formatText = ""

        if ($item.itemInfo.technicalInfo.formats.displayValues) {

            $formatText =
                $item.itemInfo.technicalInfo.formats.displayValues -join ", "
        }


        # Release date
        $releaseDate = ""

        if ($item.itemInfo.contentInfo.publicationDate) {

            $rawReleaseDate =
                $item.itemInfo.contentInfo.publicationDate.displayValue

            try {

                $releaseDate =
                    ([datetime]$rawReleaseDate).ToString("yyyy/MM/dd")

            }
            catch {

                $releaseDate =
                    $rawReleaseDate
            }
        }


        # Price
        $priceText = ""
        $priceStatus = ""

        if ($item.offersV2.listings) {

            $buyBoxListing =
                $item.offersV2.listings |
                Where-Object {
                    $_.isBuyBoxWinner -eq $true
                } |
                Select-Object -First 1

            if (-not $buyBoxListing) {

                $buyBoxListing =
                    $item.offersV2.listings |
                    Select-Object -First 1
            }

            if ($buyBoxListing) {

                $currentPrice =
                    $buyBoxListing.price.money.displayAmount

                $currentAmount =
                    $buyBoxListing.price.money.amount

                $availabilityType =
                    $buyBoxListing.availability.type

                if ($availabilityType -eq "PREORDER") {

                    $priceStatus = "予約"

                    if ($currentPrice) {
                        $priceText = $currentPrice
                    }
                }
                elseif ($currentAmount -eq 0) {

                    $priceStatus = "追加料金なし"

                    $normalPrice = ""

                    if ($buyBoxListing.price.savingBasis.money.displayAmount) {

                        $normalPrice =
                            $buyBoxListing.price.savingBasis.money.displayAmount
                    }
                    else {

                        $normalListing =
                            $item.offersV2.listings |
                            Where-Object {
                                $_.price.money.amount -gt 0
                            } |
                            Select-Object -First 1

                        if ($normalListing) {

                            $normalPrice =
                                $normalListing.price.money.displayAmount
                        }
                    }

                    if ($normalPrice) {

                        $priceText =
                            "通常 $normalPrice"
                    }
                    else {

                        $priceText =
                            "￥0"
                    }
                }
                else {

                    if ($currentPrice) {

                        $priceStatus = "価格"
                        $priceText = $currentPrice
                    }
                }
            }
        }


        # Image URL
        $imageUrl = ""

        if ($item.images.primary.medium.url) {

            $imageUrl =
                $item.images.primary.medium.url
        }


        # Result
        $result = [PSCustomObject]@{
            Title       = $item.itemInfo.title.displayValue
            Author      = $authorText
            Narrator    = $narratorText
            Publisher   = $publisherText
            Format      = $formatText
            ReleaseDate = $releaseDate
            PriceStatus = $priceStatus
            Price       = $priceText
            ASIN        = $item.asin
            ImageURL    = $imageUrl
            URL         = $item.detailPageURL
        }

        $results += $result
    }

    return $results
}