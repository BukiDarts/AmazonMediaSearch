function Search-Audible {

    param(
        [Parameter(Mandatory)]
        [string]$Keyword,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [string]$SortBy = "Relevance"
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

    $searchKeyword =
        "$Keyword Audible"

    $results = @()

    $foundAsins = @{}


    # Get up to 10 pages
    for ($page = 1; $page -le 10; $page++) {

        $searchParams = @{
            Keyword     = $searchKeyword
            SearchIndex = "All"
            Resources   = $resources
            Config      = $Config
            AccessToken = $AccessToken
            ItemCount   = 10
            ItemPage    = $page
            SortBy      = $SortBy
        }

        $response =
            Invoke-AmazonSearch @searchParams

        $pageItems =
            @($response.searchResult.items)

        if ($pageItems.Count -eq 0) {
            break
        }


        foreach ($item in $pageItems) {

            # Product group
            $productGroup = ""

            if (
                $item.itemInfo.classifications.productGroup
            ) {

                $productGroup =
                    $item.itemInfo.classifications.productGroup.displayValue
            }

            if ($productGroup -ne "Audible") {
                continue
            }


            # Duplicate check
            if ($foundAsins.ContainsKey($item.asin)) {
                continue
            }

            $foundAsins[$item.asin] = $true


            # Contributors
            $authors = @()
            $narrators = @()
            $publishers = @()

            if (
                $item.itemInfo.byLineInfo.contributors
            ) {

                foreach (
                    $contributor in
                    $item.itemInfo.byLineInfo.contributors
                ) {

                    switch ($contributor.roleType) {

                        "author" {

                            $authors +=
                                $contributor.name
                        }

                        "narrator" {

                            $narrators +=
                                $contributor.name
                        }

                        "publisher" {

                            $publishers +=
                                $contributor.name
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

            if (
                $item.itemInfo.technicalInfo.formats.displayValues
            ) {

                $formatText =
                    $item.itemInfo.technicalInfo.formats.displayValues `
                    -join ", "
            }


            # Release date
            $releaseDate = ""

            if (
                $item.itemInfo.contentInfo.publicationDate
            ) {

                $rawReleaseDate =
                    $item.itemInfo.contentInfo.publicationDate.displayValue

                try {

                    $releaseDate =
                        ([datetime]$rawReleaseDate).ToString(
                            "yyyy/MM/dd"
                        )

                }
                catch {

                    $releaseDate =
                        $rawReleaseDate
                }
            }


            # Price and availability
            $priceText = ""
            $priceStatus = ""
            $availabilityType = ""
            $isAdditionalChargeFree = $false

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


                    # Preorder
                    if (
                        $availabilityType -eq "PREORDER"
                    ) {

                        $priceStatus =
                            "予約"

                        if ($currentPrice) {

                            $priceText =
                                $currentPrice
                        }
                    }


                    # Zero-price offer
                    elseif (
                        $currentAmount -eq 0
                    ) {

                        $isAdditionalChargeFree =
                            $true

                        $priceStatus =
                            "追加料金なし"

                        $normalPrice = ""

                        if (
                            $buyBoxListing.price.savingBasis.money.displayAmount
                        ) {

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


                    # Normal price
                    else {

                        if ($currentPrice) {

                            $priceStatus =
                                "価格"

                            $priceText =
                                $currentPrice
                        }
                    }
                }
            }


            # Image URL
            $imageUrl = ""

            if (
                $item.images.primary.medium.url
            ) {

                $imageUrl =
                    $item.images.primary.medium.url
            }


            # Result
            $result = [PSCustomObject]@{

                Title =
                    $item.itemInfo.title.displayValue

                Author =
                    $authorText

                Narrator =
                    $narratorText

                Publisher =
                    $publisherText

                Format =
                    $formatText

                ReleaseDate =
                    $releaseDate

                PriceStatus =
                    $priceStatus

                Price =
                    $priceText

                AvailabilityType =
                    $availabilityType

                IsAdditionalChargeFree =
                    $isAdditionalChargeFree

                ASIN =
                    $item.asin

                ImageURL =
                    $imageUrl

                URL =
                    $item.detailPageURL
            }

            $results +=
                $result
        }


        if ($pageItems.Count -lt 10) {
            break
        }
    }


    return $results
}