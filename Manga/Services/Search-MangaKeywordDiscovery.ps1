function ConvertTo-MangaDiscoveryNormalizedText {

    param(
        [string]$Text
    )


    if (
        [string]::IsNullOrWhiteSpace(
            $Text
        )
    ) {

        return ""
    }


    $value =
        $Text.Normalize(
            [Text.NormalizationForm]::FormKC
        )


    $value =
        $value -replace
        '[\u3000\s]+',
        ' '


    return $value.Trim()
}


function Remove-MangaDiscoveryTrailingLabels {

    param(
        [string]$Text
    )


    $value =
        ConvertTo-MangaDiscoveryNormalizedText `
            -Text $Text


    while (
        $value -match
        '^(.*)\s+\([^()]*\)\s*$'
    ) {

        $candidate =
            $Matches[1].Trim()


        if (
            [string]::IsNullOrWhiteSpace(
                $candidate
            )
        ) {

            break
        }


        $value =
            $candidate
    }


    return $value
}


function Get-MangaDiscoverySeriesTitle {

    param(
        [string]$Title
    )


    $normalized =
        ConvertTo-MangaDiscoveryNormalizedText `
            -Text $Title


    if (
        [string]::IsNullOrWhiteSpace(
            $normalized
        )
    ) {

        return ""
    }


    # Use the stable parser first.
    $stable =
        Get-MangaSeriesTitle `
            -Title $Title


    $stableNormalized =
        ConvertTo-MangaDiscoveryNormalizedText `
            -Text $stable


    if (
        -not [string]::IsNullOrWhiteSpace(
            $stableNormalized
        ) -and
        $stableNormalized -ne
        $normalized
    ) {

        return (
            $stableNormalized.
                TrimEnd(':').
                Trim()
        )
    }


    $value =
        $normalized


    # Example:
    # Series 8 (Label)
    # Series11 (Label)
    # Series 12巻 (Label)
    if (
        $value -match
        '^(.*?)\s*(?<!\d)(\d{1,3})\s*(?:巻)?\s+(?:\([^()]*\)\s*)+$'
    ) {

        return (
            $Matches[1].
                Trim().
                TrimEnd(':').
                Trim()
        )
    }


    # Example:
    # Series: 2【bonus】 (Label)
    # Series 2【bonus】
    if (
        $value -match
        '^(.*?)\s*:?\s*(?<!\d)(\d{1,3})\s*(?:巻)?\s*(?:【[^】]*】\s*)+(?:\([^()]*\)\s*)*$'
    ) {

        return (
            $Matches[1].
                Trim().
                TrimEnd(':').
                Trim()
        )
    }


    # Example:
    # Series (Label) 6【bonus】
    # Series (Label) 7
    if (
        $value -match
        '^(.*?)\s*(?:\([^()]*\)\s*)+\s*(?<!\d)(\d{1,3})\s*(?:巻)?\s*(?:【[^】]*】\s*)*$'
    ) {

        return (
            $Matches[1].
                Trim().
                TrimEnd(':').
                Trim()
        )
    }


    $withoutLabels =
        Remove-MangaDiscoveryTrailingLabels `
            -Text $value


    if (
        $withoutLabels -match
        '^(.*?)\s*:?\s*(?<!\d)(\d{1,3})\s*(?:巻)?\s*$'
    ) {

        return (
            $Matches[1].
                Trim().
                TrimEnd(':').
                Trim()
        )
    }


    return (
        $stableNormalized.
            TrimEnd(':').
            Trim()
    )
}


function Get-MangaDiscoveryAuthors {

    param(
        $Item
    )


    $authors =
        @()


    if (
        $Item.itemInfo -and
        $Item.itemInfo.byLineInfo -and
        $Item.itemInfo.byLineInfo.contributors
    ) {

        foreach (
            $contributor in
            $Item.itemInfo.byLineInfo.contributors
        ) {

            if (
                -not [string]::IsNullOrWhiteSpace(
                    $contributor.name
                )
            ) {

                $authors +=
                    [string]$contributor.name
            }
        }
    }


    return @(
        $authors |
        Sort-Object -Unique
    )
}


function Get-MangaDiscoveryAuthorKey {

    param(
        [array]$Authors
    )


    if (
        -not $Authors -or
        $Authors.Count -eq 0
    ) {

        return ""
    }


    return (
        @(
            $Authors |
            ForEach-Object {

                ConvertTo-MangaDiscoveryNormalizedText `
                    -Text ([string]$_)
            } |
            Where-Object {

                -not [string]::IsNullOrWhiteSpace(
                    $_
                )
            } |
            Sort-Object -Unique
        ) -join "|"
    )
}


function Get-MangaDiscoveryGroupKey {

    param(
        [string]$SeriesTitle,

        [array]$Authors
    )


    $titleKey =
        (
            ConvertTo-MangaDiscoveryNormalizedText `
                -Text $SeriesTitle
        ).ToLowerInvariant()


    $authorKey =
        (
            Get-MangaDiscoveryAuthorKey `
                -Authors $Authors
        ).ToLowerInvariant()


    return (
        "{0}||{1}" -f
        $titleKey,
        $authorKey
    )
}


function Get-MangaDiscoveryTitle {

    param(
        $Item
    )


    if (
        $Item.itemInfo -and
        $Item.itemInfo.title
    ) {

        return (
            [string]$Item.itemInfo.title.displayValue
        )
    }


    return ""
}


function Get-MangaDiscoveryPrice {

    param(
        $Item
    )


    if (
        -not $Item.offersV2 -or
        -not $Item.offersV2.listings
    ) {

        return ""
    }


    $listing =
        @(
            $Item.offersV2.listings |
            Where-Object {

                $_.isBuyBoxWinner -eq
                $true
            }
        ) |
        Select-Object -First 1


    if (-not $listing) {

        $listing =
            @(
                $Item.offersV2.listings
            ) |
            Select-Object -First 1
    }


    if (
        $listing -and
        $listing.price
    ) {

        if (
            $listing.price.money -and
            $listing.price.money.displayAmount
        ) {

            return (
                [string]$listing.price.money.displayAmount
            )
        }


        if (
            $listing.price.displayAmount
        ) {

            return (
                [string]$listing.price.displayAmount
            )
        }
    }


    return ""
}


function Test-MangaDiscoveryKindleUnlimited {

    param(
        $Item
    )


    if (
        -not $Item.browseNodeInfo -or
        $null -eq
        $Item.browseNodeInfo.browseNodes
    ) {

        return $null
    }


    $browseJson =
        $Item.browseNodeInfo |
        ConvertTo-Json -Depth 30


    return (
        $browseJson -match
        'Kindle Unlimited'
    )
}


function Test-MangaDiscoveryLimitedFree {

    param(
        $Item
    )


    if (
        -not $Item.browseNodeInfo -or
        $null -eq
        $Item.browseNodeInfo.browseNodes
    ) {

        return $null
    }


    $browseJson =
        $Item.browseNodeInfo |
        ConvertTo-Json -Depth 30


    return (
        $browseJson -match
        '\u671F\u9593\u9650\u5B9A\u7121\u6599'
    )
}


function Search-MangaKeywordDiscovery {

    param(
        [Parameter(Mandatory)]
        [string]$Keyword,

        [Parameter(Mandatory)]
        $Config,

        [string]$AccessToken = "",

        [int]$MaxPages = 10,

        [int]$RequestDelayMilliseconds = 1100
    )


    $userKeyword =
        $Keyword.Trim()


    if (
        [string]::IsNullOrWhiteSpace(
            $userKeyword
        )
    ) {

        throw "Keyword is required."
    }


    if (
        [string]::IsNullOrWhiteSpace(
            $AccessToken
        )
    ) {

        $AccessToken =
            Get-AmazonAccessToken `
                -Config $Config
    }


    $amazonKeyword =
        (
            "マンガ {0}" -f
            $userKeyword
        ).Trim()


    $resources =
        @(
            "itemInfo.title",
            "itemInfo.byLineInfo",
            "browseNodeInfo.browseNodes",
            "offersV2.listings.isBuyBoxWinner",
            "offersV2.listings.price"
        )


    $rows =
        @()


    $totalResultCount =
        0


    $requiredPages =
        1


    $requestCount =
        0


    $globalRank =
        0


    for (
        $page = 1;
        $page -le $MaxPages;
        $page++
    ) {

        if (
            $page -gt $requiredPages
        ) {

            break
        }


        if (
            $page -gt 1
        ) {

            Start-Sleep `
                -Milliseconds $RequestDelayMilliseconds
        }


        $response =
            Invoke-AmazonSearch `
                -Keyword $amazonKeyword `
                -SearchIndex "KindleStore" `
                -Resources $resources `
                -Config $Config `
                -AccessToken $AccessToken `
                -ItemCount 10 `
                -ItemPage $page `
                -SortBy "Featured"


        $requestCount++


        if (
            $response.searchResult -and
            $null -ne
            $response.searchResult.totalResultCount
        ) {

            $totalResultCount =
                [int]$response.searchResult.totalResultCount


            $requiredPages =
                [math]::Ceiling(
                    $totalResultCount / 10
                )


            if (
                $requiredPages -gt $MaxPages
            ) {

                $requiredPages =
                    $MaxPages
            }
        }


        $items =
            @()


        if (
            $response.searchResult -and
            $response.searchResult.items
        ) {

            $items =
                @(
                    $response.searchResult.items
                )
        }


        if (
            $items.Count -eq 0
        ) {

            break
        }


        foreach (
            $item in $items
        ) {

            $globalRank++


            $title =
                Get-MangaDiscoveryTitle `
                    -Item $item


            $authors =
                @(
                    Get-MangaDiscoveryAuthors `
                        -Item $item
                )


            $seriesTitle =
                Get-MangaDiscoverySeriesTitle `
                    -Title $title


            $rows +=
                [PSCustomObject]@{

                    SearchRank =
                        $globalRank

                    ASIN =
                        [string]$item.asin

                    Title =
                        $title

                    SeriesTitle =
                        $seriesTitle

                    Authors =
                        $authors

                    Price =
                        (
                            Get-MangaDiscoveryPrice `
                                -Item $item
                        )

                    IsKindleUnlimited =
                        (
                            Test-MangaDiscoveryKindleUnlimited `
                                -Item $item
                        )

                    IsLimitedFree =
                        (
                            Test-MangaDiscoveryLimitedFree `
                                -Item $item
                        )

                    DetailPageURL =
                        [string]$item.detailPageURL

                    GroupKey =
                        (
                            Get-MangaDiscoveryGroupKey `
                                -SeriesTitle $seriesTitle `
                                -Authors $authors
                        )
                }
        }
    }


    $seriesMap =
        [ordered]@{}


    foreach (
        $row in $rows
    ) {

        $key =
            [string]$row.GroupKey


        if (
            -not $seriesMap.Contains(
                $key
            )
        ) {

            $seriesMap[$key] =
                [PSCustomObject]@{

                    Rank =
                        $seriesMap.Count + 1

                    FirstSearchRank =
                        $row.SearchRank

                    SeriesTitle =
                        $row.SeriesTitle

                    SeedASIN =
                        $row.ASIN

                    SeedTitle =
                        $row.Title

                    Authors =
                        @($row.Authors)

                    Price =
                        $row.Price

                    KindleUnlimited =
                        $row.IsKindleUnlimited

                    LimitedFree =
                        $row.IsLimitedFree

                    MatchedItemCount =
                        1
                }
        }
        else {

            $series =
                $seriesMap[$key]


            $series.MatchedItemCount =
                [int]$series.MatchedItemCount + 1


            if (
                $series.KindleUnlimited -ne $true -and
                $row.IsKindleUnlimited -eq $true
            ) {

                $series.KindleUnlimited =
                    $true
            }


            if (
                $series.LimitedFree -ne $true -and
                $row.IsLimitedFree -eq $true
            ) {

                $series.LimitedFree =
                    $true
            }
        }
    }


    return (
        [PSCustomObject]@{

            UserKeyword =
                $userKeyword

            AmazonKeyword =
                $amazonKeyword

            TotalResultCount =
                $totalResultCount

            RetrievedItems =
                $rows.Count

            UniqueSeries =
                $seriesMap.Count

            SearchItemsRequests =
                $requestCount

            Series =
                @(
                    $seriesMap.Values
                )
        }
    )
}