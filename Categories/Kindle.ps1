function Search-Kindle {

    param(
        [Parameter(Mandatory)]
        [string]$Keyword,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [string]$SortBy = "Relevance",

        [ValidateSet("Keyword", "Author")]
        [string]$SearchMode = "Keyword"
    )

    $resources = @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "itemInfo.classifications",
        "itemInfo.contentInfo",
        "browseNodeInfo.browseNodes",
        "images.primary.medium",
        "offersV2.listings.price",
        "offersV2.listings.availability",
        "offersV2.listings.isBuyBoxWinner"
    )

    $results = @()
    $foundAsins = @()

    $foundAsins = @{}
    $totalResultCount = 0


    # Get up to 10 pages
    for ($page = 1; $page -le 10; $page++) {

        $searchParams = @{
            Keyword     = $Keyword
            SearchIndex = "KindleStore"
            Resources   = $resources
            Config      = $Config
            AccessToken = $AccessToken
            ItemCount   = 10
            ItemPage    = $page
            SortBy      = $SortBy
        }

        $response =
            Invoke-AmazonSearch @searchParams


        # Save total result count from the first response
        if ($page -eq 1) {

            if (
                $null -ne
                $response.searchResult.totalResultCount
            ) {

                $totalResultCount =
                    [int]$response.searchResult.totalResultCount
            }
        }


        $pageItems =
            @($response.searchResult.items)

        if ($pageItems.Count -eq 0) {
            break
        }


        foreach ($item in $pageItems) {

            # Duplicate check
            if ($foundAsins.ContainsKey($item.asin)) {
                continue
            }

            $foundAsins[$item.asin] = $true


            # Contributors
            $authors = @()
            $publishers = @()

            if ($item.itemInfo.byLineInfo.contributors) {

                foreach (
                    $contributor in
                    $item.itemInfo.byLineInfo.contributors
                ) {

                    switch ($contributor.roleType) {

                        "author" {

                            $authors +=
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

            $publisherText =
                $publishers -join ", "


            # Author search filter
            if (
                $SearchMode -eq "Author" -and
                -not (
                    Test-AmazonAuthorMatch `
                        -Contributors @($item.itemInfo.byLineInfo.contributors) `
                        -AuthorKeyword $Keyword
                )
            ) {

                continue
            }


            # Format / binding
            $formatText = ""

            if (
                $item.itemInfo.classifications.binding
            ) {

                $formatText =
                    $item.itemInfo.classifications.binding.displayValue
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

                    $availabilityType =
                        $buyBoxListing.availability.type


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

            if ($item.images.primary.medium.url) {

                $imageUrl =
                    $item.images.primary.medium.url
            }




            # Kindle Unlimited / limited-free status
            $kindleUnlimited =
                $null

            $limitedFree =
                $null


            if (
                $item.browseNodeInfo -and
                $item.browseNodeInfo.browseNodes
            ) {

                $kindleUnlimited =
                    $false

                $limitedFree =
                    $false


                foreach (
                    $browseNode in
                    @($item.browseNodeInfo.browseNodes)
                ) {

                    $browseNodeName =
                        [string]$browseNode.displayName


                    if (
                        $browseNodeName -match
                        'Kindle\s*Unlimited'
                    ) {

                        $kindleUnlimited =
                            $true
                    }


                    if (
                        $browseNodeName -match
                        '期間限定無料'
                    ) {

                        $limitedFree =
                            $true
                    }
                }
            }


            $kindleUnlimitedDisplay =
                "不明"

            if (
                $kindleUnlimited -eq $true
            ) {

                $kindleUnlimitedDisplay =
                    "KU対象"
            }
            elseif (
                $kindleUnlimited -eq $false
            ) {

                $kindleUnlimitedDisplay =
                    "KU対象外"
            }


            $limitedFreeDisplay =
                "不明"

            if (
                $limitedFree -eq $true
            ) {

                $limitedFreeDisplay =
                    "期間無料"
            }
            elseif (
                $limitedFree -eq $false
            ) {

                $limitedFreeDisplay =
                    "期間無料なし"
            }


            # Result
            $result = [PSCustomObject]@{

                Title =
                    $item.itemInfo.title.displayValue

                Author =
                    $authorText

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

                KindleUnlimited =
                    $kindleUnlimited

                KindleUnlimitedDisplay =
                    $kindleUnlimitedDisplay

                LimitedFree =
                    $limitedFree

                LimitedFreeDisplay =
                    $limitedFreeDisplay

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


        # Avoid sending page requests too quickly
        Start-Sleep -Milliseconds 1100
    }


    # Fallback
    if ($totalResultCount -le 0) {

        $totalResultCount =
            $results.Count
    }


    return [PSCustomObject]@{

        Items =
            @($results)

        TotalResultCount =
            $totalResultCount
    }
}