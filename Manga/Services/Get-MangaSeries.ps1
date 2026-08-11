# ==========================================
# Manga Series Service
# ==========================================
#
# Purpose:
# - Start from one seed ASIN
# - Resolve manga series identity
# - Retrieve only required SearchItems pages
# - Select main-series volumes
# - Detect KU status from SearchItems metadata
# - Use GetItems only when KU metadata is missing
# - Perform a low-cost tail check when search is truncated
#
# Authentication is handled by the caller.
# ==========================================


function ConvertTo-MangaNormalizedText {

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

    $normalized =
        $Text.Normalize(
            [Text.NormalizationForm]::FormKC
        )

    return (
        (
            $normalized -replace '\s+', ' '
        ).Trim()
    )
}


function Get-MangaVolumeNumber {

    param(
        [string]$Title
    )

    $normalizedTitle =
        ConvertTo-MangaNormalizedText `
            -Text $Title

    if (
        [string]::IsNullOrWhiteSpace(
            $normalizedTitle
        )
    ) {
        return $null
    }

    if (
        $normalizedTitle -match
        '\((\d+)\)'
    ) {
        return [int]$Matches[1]
    }

    if (
        $normalizedTitle -match
        '\u7B2C\s*(\d+)\s*\u5DFB'
    ) {
        return [int]$Matches[1]
    }

    if (
        $normalizedTitle -match
        '(\d+)\s*\u5DFB'
    ) {
        return [int]$Matches[1]
    }

    # Support titles where the volume number appears before
    # one or more trailing labels, such as "Series 1 (Label)".
    if (
        $normalizedTitle -match
        '(?<!\d)(\d+)\s*(?:\([^()]*\)\s*)+$'
    ) {
        return [int]$Matches[1]
    }

    if (
        $normalizedTitle -match
        '\s(\d+)\s*$'
    ) {
        return [int]$Matches[1]
    }

    # Support titles where the volume number is directly
    # attached to the series title, such as "Complete Edition1".
    if (
        $normalizedTitle -match
        '(?<!\d)(\d+)\s*$'
    ) {
        return [int]$Matches[1]
    }

    return $null
}


function Get-MangaSeriesTitle {

    param(
        [string]$Title
    )

    $normalizedTitle =
        ConvertTo-MangaNormalizedText `
            -Text $Title

    if (
        [string]::IsNullOrWhiteSpace(
            $normalizedTitle
        )
    ) {
        return ""
    }

    if (
        $normalizedTitle -match
        '^(.*?)\s*\((\d+)\)\s*(?:\([^()]*\))*\s*$'
    ) {
        return (
            ConvertTo-MangaNormalizedText `
                -Text $Matches[1]
        )
    }

    if (
        $normalizedTitle -match
        '^(.*?)\s*\u7B2C\s*\d+\s*\u5DFB(?:\s*\([^()]*\))*\s*$'
    ) {
        return (
            ConvertTo-MangaNormalizedText `
                -Text $Matches[1]
        )
    }

    if (
        $normalizedTitle -match
        '^(.*?)\s*\d+\s*\u5DFB(?:\s*\([^()]*\))*\s*$'
    ) {
        return (
            ConvertTo-MangaNormalizedText `
                -Text $Matches[1]
        )
    }

    if (
        $normalizedTitle -match
        '^(.*?)\s+(\d+)\s*$'
    ) {
        return (
            ConvertTo-MangaNormalizedText `
                -Text $Matches[1]
        )
    }

    # Support titles where the volume number is directly
    # attached to the series title.
    if (
        $normalizedTitle -match
        '^(.*?\D)(\d+)\s*$'
    ) {
        return (
            ConvertTo-MangaNormalizedText `
                -Text $Matches[1]
        )
    }

    return $normalizedTitle
}


function Get-MangaTrailingLabel {

    param(
        [string]$Title
    )

    $normalizedTitle =
        ConvertTo-MangaNormalizedText `
            -Text $Title

    if (
        $normalizedTitle -match
        '\(([^()]*)\)\s*$'
    ) {
        $label =
            ConvertTo-MangaNormalizedText `
                -Text $Matches[1]

        if (
            $label -notmatch
            '^\d+$'
        ) {
            return $label
        }
    }

    return ""
}


function Get-MangaAuthorNames {

    param(
        $Item
    )

    $names =
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
                $contributor.roleType -eq
                "author"
            ) {
                $names +=
                    $contributor.name
            }
        }
    }

    return @(
        $names |
        Sort-Object -Unique
    )
}


function Get-MangaBinding {

    param(
        $Item
    )

    if (
        $Item.itemInfo -and
        $Item.itemInfo.classifications -and
        $Item.itemInfo.classifications.binding
    ) {
        return (
            $Item.itemInfo.classifications.binding.displayValue
        )
    }

    return ""
}


function Get-MangaPrice {

    param(
        $Item
    )

    if (
        -not $Item.offersV2 -or
        -not $Item.offersV2.listings
    ) {
        return ""
    }

    $buyBox =
        @(
            $Item.offersV2.listings |
            Where-Object {
                $_.isBuyBoxWinner -eq $true
            }
        ) |
        Select-Object -First 1

    if (
        $buyBox -and
        $buyBox.price -and
        $buyBox.price.money
    ) {
        return (
            $buyBox.price.money.displayAmount
        )
    }

    $firstListing =
        @(
            $Item.offersV2.listings
        ) |
        Select-Object -First 1

    if (
        $firstListing -and
        $firstListing.price -and
        $firstListing.price.money
    ) {
        return (
            $firstListing.price.money.displayAmount
        )
    }

    return ""
}


function Get-MangaImageUrl {

    param(
        $Item
    )

    if (
        $Item.images -and
        $Item.images.primary -and
        $Item.images.primary.medium -and
        $Item.images.primary.medium.url
    ) {
        return [string]$Item.images.primary.medium.url
    }

    return ""
}


function Test-MangaKUMetadataAvailable {

    param(
        $Item
    )

    if (-not $Item) {
        return $false
    }

    if (-not $Item.browseNodeInfo) {
        return $false
    }

    if (-not $Item.browseNodeInfo.browseNodes) {
        return $false
    }

    $nodes =
        @(
            $Item.browseNodeInfo.browseNodes
        )

    return (
        $nodes.Count -gt 0
    )
}


function Test-MangaKindleUnlimited {

    param(
        $Item
    )

    if (
        -not (
            Test-MangaKUMetadataAvailable `
                -Item $Item
        )
    ) {
        return $null
    }

    $browseNodeJson =
        $Item.browseNodeInfo |
        ConvertTo-Json -Depth 30

    if (
        $browseNodeJson -match
        'Kindle Unlimited'
    ) {
        return $true
    }

    return $false
}



function Test-MangaLimitedFree {

    param(
        $Item
    )

    if (
        -not (
            Test-MangaKUMetadataAvailable `
                -Item $Item
        )
    ) {
        return $null
    }

    $browseNodeJson =
        $Item.browseNodeInfo |
        ConvertTo-Json -Depth 30

    if (
        $browseNodeJson -match
        '\u671F\u9593\u9650\u5B9A\u7121\u6599'
    ) {
        return $true
    }

    return $false
}


function ConvertTo-MangaVolumeRanges {

    param(
        [array]$Volumes
    )

    $numbers =
        @(
            $Volumes |
            Where-Object {
                $null -ne $_
            } |
            ForEach-Object {
                [int]$_
            } |
            Sort-Object -Unique
        )

    if ($numbers.Count -eq 0) {
        return "none"
    }

    $ranges =
        @()

    $rangeStart =
        $numbers[0]

    $previous =
        $numbers[0]

    for (
        $i = 1;
        $i -lt $numbers.Count;
        $i++
    ) {
        $current =
            $numbers[$i]

        if (
            $current -eq
            ($previous + 1)
        ) {
            $previous =
                $current

            continue
        }

        if (
            $rangeStart -eq
            $previous
        ) {
            $ranges +=
                "$rangeStart"
        }
        else {
            $ranges +=
                (
                    "{0}-{1}" -f
                    $rangeStart,
                    $previous
                )
        }

        $rangeStart =
            $current

        $previous =
            $current
    }

    if (
        $rangeStart -eq
        $previous
    ) {
        $ranges +=
            "$rangeStart"
    }
    else {
        $ranges +=
            (
                "{0}-{1}" -f
                $rangeStart,
                $previous
            )
    }

    return (
        $ranges -join ", "
    )
}


function Test-MangaDirectVolumeTitle {

    param(
        [Parameter(Mandatory)]
        [string]$SeriesTitle,

        [Parameter(Mandatory)]
        [int]$Volume,

        [Parameter(Mandatory)]
        [string]$Title
    )

    $normalizedSeries =
        ConvertTo-MangaNormalizedText `
            -Text $SeriesTitle

    $normalizedTitle =
        ConvertTo-MangaNormalizedText `
            -Text $Title

    $escapedSeries =
        [regex]::Escape(
            $normalizedSeries
        )

    $patterns =
        @(
            (
                '^' +
                $escapedSeries +
                '\s*\(' +
                $Volume +
                '\)\s*(?:\([^()]*\))*\s*$'
            ),
            (
                '^' +
                $escapedSeries +
                '\s+' +
                $Volume +
                '\s*(?:\([^()]*\))*\s*$'
            ),
            (
                '^' +
                $escapedSeries +
                '\s*\u7B2C\s*' +
                $Volume +
                '\s*\u5DFB\s*(?:\([^()]*\))*\s*$'
            ),
            (
                '^' +
                $escapedSeries +
                '\s*' +
                $Volume +
                '\s*\u5DFB\s*(?:\([^()]*\))*\s*$'
            ),
            (
                '^' +
                $escapedSeries +
                $Volume +
                '\s*(?:\([^()]*\))*\s*$'
            )
        )

    foreach ($pattern in $patterns) {
        if (
            $normalizedTitle -match
            $pattern
        ) {
            return $true
        }
    }

    return $false
}


function Get-MangaCandidateScore {

    param(
        [Parameter(Mandatory)]
        [string]$SeriesTitle,

        [Parameter(Mandatory)]
        [int]$Volume,

        [Parameter(Mandatory)]
        [string]$Title,

        [string]$SeedLabel = "",

        [array]$SeedAuthors = @(),

        [array]$CandidateAuthors = @()
    )

    $score =
        0

    if (
        Test-MangaDirectVolumeTitle `
            -SeriesTitle $SeriesTitle `
            -Volume $Volume `
            -Title $Title
    ) {
        $score +=
            1000
    }

    $candidateLabel =
        Get-MangaTrailingLabel `
            -Title $Title

    if (
        -not [string]::IsNullOrWhiteSpace(
            $SeedLabel
        ) -and
        $candidateLabel -eq
        $SeedLabel
    ) {
        $score +=
            300
    }

    foreach ($seedAuthor in $SeedAuthors) {
        if (
            $CandidateAuthors -contains
            $seedAuthor
        ) {
            $score +=
                100

            break
        }
    }

    $normalizedSeries =
        ConvertTo-MangaNormalizedText `
            -Text $SeriesTitle

    $normalizedTitle =
        ConvertTo-MangaNormalizedText `
            -Text $Title

    $escapedSeries =
        [regex]::Escape(
            $normalizedSeries
        )

    if (
        $normalizedTitle -match
        (
            '^' +
            $escapedSeries +
            '\s+.+\(' +
            $Volume +
            '\)'
        )
    ) {
        $score -=
            500
    }

    return $score
}


function Test-MangaTailCandidate {

    param(
        [Parameter(Mandatory)]
        $Item,

        [Parameter(Mandatory)]
        [string]$SeriesTitle,

        [Parameter(Mandatory)]
        [int]$ExpectedVolume,

        [string]$SeedLabel = "",

        [array]$SeedAuthors = @()
    )

    if (
        -not $Item.itemInfo -or
        -not $Item.itemInfo.title
    ) {
        return $false
    }

    $title =
        $Item.itemInfo.title.displayValue

    $volume =
        Get-MangaVolumeNumber `
            -Title $title

    if (
        $null -eq $volume -or
        $volume -ne $ExpectedVolume
    ) {
        return $false
    }

    if (
        -not (
            Test-MangaDirectVolumeTitle `
                -SeriesTitle $SeriesTitle `
                -Volume $ExpectedVolume `
                -Title $title
        )
    ) {
        return $false
    }

    $kindleBinding =
        ([char]0x004B) +
        ([char]0x0069) +
        ([char]0x006E) +
        ([char]0x0064) +
        ([char]0x006C) +
        ([char]0x0065) +
        ([char]0x7248)

    $binding =
        Get-MangaBinding `
            -Item $Item

    if (
        $binding -ne
        $kindleBinding
    ) {
        return $false
    }

    if (
        -not [string]::IsNullOrWhiteSpace(
            $SeedLabel
        )
    ) {
        $candidateLabel =
            Get-MangaTrailingLabel `
                -Title $title

        if (
            -not [string]::IsNullOrWhiteSpace(
                $candidateLabel
            ) -and
            $candidateLabel -ne
            $SeedLabel
        ) {
            return $false
        }
    }

    if ($SeedAuthors.Count -gt 0) {
        $candidateAuthors =
            @(
                Get-MangaAuthorNames `
                    -Item $Item
            )

        $authorMatched =
            $false

        foreach ($seedAuthor in $SeedAuthors) {
            if (
                $candidateAuthors -contains
                $seedAuthor
            ) {
                $authorMatched =
                    $true

                break
            }
        }

        if (-not $authorMatched) {
            return $false
        }
    }

    return $true
}


function Get-MangaSeries {

    param(
        [Parameter(Mandatory)]
        [string]$SeedASIN,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [int]$MaxSearchPages = 10,

        [int]$MaxTailSearchRequests = 2,

        [int]$RequestDelayMilliseconds = 1100
    )

    $seedASIN =
        $SeedASIN.Trim()

    if (
        [string]::IsNullOrWhiteSpace(
            $seedASIN
        )
    ) {
        throw "Seed ASIN is empty."
    }

    $resources =
        @(
            "itemInfo.title",
            "itemInfo.byLineInfo",
            "itemInfo.classifications",
            "itemInfo.contentInfo",
            "itemInfo.productInfo",
            "itemInfo.technicalInfo",
            "images.primary.medium",
            "offersV2.listings.availability",
            "offersV2.listings.condition",
            "offersV2.listings.isBuyBoxWinner",
            "offersV2.listings.merchantInfo",
            "offersV2.listings.price",
            "offersV2.listings.type",
            "browseNodeInfo.browseNodes",
            "browseNodeInfo.browseNodes.ancestor"
        )

    $searchRequestCount =
        0

    $getItemsRequestCount =
        0

    # ======================================
    # Seed GetItems
    # ======================================

    $getItemsRequestCount++

    $seedItems =
        @(
            Invoke-AmazonGetItems `
                -Asins @($seedASIN) `
                -Resources $resources `
                -Config $Config `
                -AccessToken $AccessToken
        )

    if ($seedItems.Count -eq 0) {
        throw "Seed item was not returned."
    }

    $seedItem =
        $seedItems[0]

    if (
        -not $seedItem.itemInfo -or
        -not $seedItem.itemInfo.title
    ) {
        throw "Seed title was not returned."
    }

    $seedTitle =
        $seedItem.itemInfo.title.displayValue

    $seriesTitle =
        Get-MangaSeriesTitle `
            -Title $seedTitle

    if (
        [string]::IsNullOrWhiteSpace(
            $seriesTitle
        )
    ) {
        throw "Series title could not be determined."
    }

    $seedVolume =
        Get-MangaVolumeNumber `
            -Title $seedTitle

    $seedLabel =
        Get-MangaTrailingLabel `
            -Title $seedTitle

    $seedAuthors =
        @(
            Get-MangaAuthorNames `
                -Item $seedItem
        )

    $seedImageUrl =
        Get-MangaImageUrl `
            -Item $seedItem

    # ======================================
    # Search first page
    # ======================================

    $searchRequestCount++

    $firstResponse =
        Invoke-AmazonSearch `
            -Keyword $seriesTitle `
            -SearchIndex "KindleStore" `
            -Resources $resources `
            -Config $Config `
            -AccessToken $AccessToken `
            -ItemCount 10 `
            -ItemPage 1

    $totalResultCount =
        0

    if (
        $firstResponse.searchResult -and
        $null -ne
        $firstResponse.searchResult.totalResultCount
    ) {
        $totalResultCount =
            [int]$firstResponse.searchResult.totalResultCount
    }

    $requiredPages =
        1

    if ($totalResultCount -gt 0) {
        $requiredPages =
            [int][Math]::Ceiling(
                $totalResultCount / 10.0
            )

        if (
            $requiredPages -gt
            $MaxSearchPages
        ) {
            $requiredPages =
                $MaxSearchPages
        }
    }

    $searchItems =
        @()

    $searchItemMap =
        @{}

    $seenAsins =
        @{}

    $firstPageItems =
        @()

    if (
        $firstResponse.searchResult -and
        $firstResponse.searchResult.items
    ) {
        $firstPageItems =
            @(
                $firstResponse.searchResult.items
            )
    }

    foreach ($item in $firstPageItems) {
        if (
            -not $seenAsins.ContainsKey(
                $item.asin
            )
        ) {
            $seenAsins[$item.asin] =
                $true

            $searchItemMap[$item.asin] =
                $item

            $searchItems +=
                $item
        }
    }

    # ======================================
    # Remaining required pages
    # ======================================

    if ($requiredPages -gt 1) {
        for (
            $page = 2;
            $page -le $requiredPages;
            $page++
        ) {
            Start-Sleep `
                -Milliseconds $RequestDelayMilliseconds

            $searchRequestCount++

            $response =
                Invoke-AmazonSearch `
                    -Keyword $seriesTitle `
                    -SearchIndex "KindleStore" `
                    -Resources $resources `
                    -Config $Config `
                    -AccessToken $AccessToken `
                    -ItemCount 10 `
                    -ItemPage $page

            $pageItems =
                @()

            if (
                $response.searchResult -and
                $response.searchResult.items
            ) {
                $pageItems =
                    @(
                        $response.searchResult.items
                    )
            }

            if ($pageItems.Count -eq 0) {
                break
            }

            foreach ($item in $pageItems) {
                if (
                    -not $seenAsins.ContainsKey(
                        $item.asin
                    )
                ) {
                    $seenAsins[$item.asin] =
                        $true

                    $searchItemMap[$item.asin] =
                        $item

                    $searchItems +=
                        $item
                }
            }
        }
    }

    # ======================================
    # Build candidate list
    # ======================================

    $normalizedSeriesTitle =
        ConvertTo-MangaNormalizedText `
            -Text $seriesTitle

    $escapedSeriesTitle =
        [regex]::Escape(
            $normalizedSeriesTitle
        )

    $kindleBinding =
        ([char]0x004B) +
        ([char]0x0069) +
        ([char]0x006E) +
        ([char]0x0064) +
        ([char]0x006C) +
        ([char]0x0065) +
        ([char]0x7248)

    $candidates =
        @()

    foreach ($item in $searchItems) {
        if (
            -not $item.itemInfo -or
            -not $item.itemInfo.title
        ) {
            continue
        }

        $title =
            $item.itemInfo.title.displayValue

        $normalizedTitle =
            ConvertTo-MangaNormalizedText `
                -Text $title

        if (
            $normalizedTitle -notmatch
            ("^" + $escapedSeriesTitle)
        ) {
            continue
        }

        $volume =
            Get-MangaVolumeNumber `
                -Title $title

        if ($null -eq $volume) {
            continue
        }

        $binding =
            Get-MangaBinding `
                -Item $item

        if (
            $binding -ne
            $kindleBinding
        ) {
            continue
        }

        $candidateAuthors =
            @(
                Get-MangaAuthorNames `
                    -Item $item
            )

        $score =
            Get-MangaCandidateScore `
                -SeriesTitle $seriesTitle `
                -Volume $volume `
                -Title $title `
                -SeedLabel $seedLabel `
                -SeedAuthors $seedAuthors `
                -CandidateAuthors $candidateAuthors

        $candidates +=
            [PSCustomObject]@{
                Volume =
                    [int]$volume

                ASIN =
                    $item.asin

                Title =
                    $title

                Label =
                    (
                        Get-MangaTrailingLabel `
                            -Title $title
                    )

                Authors =
                    @($candidateAuthors)

                Score =
                    $score

                KUMetadataAvailable =
                    (
                        Test-MangaKUMetadataAvailable `
                            -Item $item
                    )

                SearchItemsKU =
                    (
                        Test-MangaKindleUnlimited `
                            -Item $item
                    )

                SearchItemsLimitedFree =
                    (
                        Test-MangaLimitedFree `
                            -Item $item
                    )

                SearchItemsPrice =
                    (
                        Get-MangaPrice `
                            -Item $item
                    )

                ImageURL =
                    (
                        Get-MangaImageUrl `
                            -Item $item
                    )
            }
    }

    # ======================================
    # Select best candidate per volume
    # ======================================

    $seriesIndex =
        @()

    $volumeGroups =
        @(
            $candidates |
            Group-Object Volume |
            Sort-Object {
                [int]$_.Name
            }
        )

    foreach ($group in $volumeGroups) {
        $selected =
            @(
                $group.Group |
                Sort-Object `
                    @{
                        Expression = "Score"
                        Descending = $true
                    },
                    @{
                        Expression = "Title"
                        Descending = $false
                    }
            ) |
            Select-Object -First 1

        if ($selected) {
            $seriesIndex +=
                $selected
        }
    }

    $seriesIndex =
        @(
            $seriesIndex |
            Sort-Object Volume
        )

    # Keep only direct series-volume titles before tail verification.
    # This removes unrelated items such as magazines with years in the title.
    $seriesIndex =
        @(
            $seriesIndex |
            Where-Object {
                Test-MangaDirectVolumeTitle `
                    -SeriesTitle $seriesTitle `
                    -Volume $_.Volume `
                    -Title $_.Title
            }
        )

    # ======================================
    # Determine initial search truncation
    # ======================================

    $isSearchTruncated =
        $false

    if (
        $totalResultCount -gt
        $searchItems.Count
    ) {
        $isSearchTruncated =
            $true
    }

    # ======================================
    # Tail verification
    # ======================================

    $tailChecks =
        @()

    $tailStatus =
        "NotRequired"

    if (
        $isSearchTruncated -and
        $seriesIndex.Count -gt 0 -and
        $MaxTailSearchRequests -gt 0
    ) {
        $tailStatus =
            "Unchecked"

        $currentMaxVolume =
            (
                $seriesIndex.Volume |
                Measure-Object -Maximum
            ).Maximum

        for (
            $tailAttempt = 1;
            $tailAttempt -le $MaxTailSearchRequests;
            $tailAttempt++
        ) {
            $targetVolume =
                [int]$currentMaxVolume + 1

            if (
                [string]::IsNullOrWhiteSpace(
                    $seedLabel
                )
            ) {
                $tailKeyword =
                    "{0} {1}" -f
                    $seriesTitle,
                    $targetVolume
            }
            else {
                $tailKeyword =
                    "{0} {1} {2}" -f
                    $seriesTitle,
                    $targetVolume,
                    $seedLabel
            }

            Start-Sleep `
                -Milliseconds $RequestDelayMilliseconds

            $searchRequestCount++

            $tailResponse =
                Invoke-AmazonSearch `
                    -Keyword $tailKeyword `
                    -SearchIndex "KindleStore" `
                    -Resources $resources `
                    -Config $Config `
                    -AccessToken $AccessToken `
                    -ItemCount 10 `
                    -ItemPage 1

            $tailItems =
                @()

            if (
                $tailResponse.searchResult -and
                $tailResponse.searchResult.items
            ) {
                $tailItems =
                    @(
                        $tailResponse.searchResult.items
                    )
            }

            $matchingItems =
                @()

            foreach ($tailItem in $tailItems) {
                if (
                    Test-MangaTailCandidate `
                        -Item $tailItem `
                        -SeriesTitle $seriesTitle `
                        -ExpectedVolume $targetVolume `
                        -SeedLabel $seedLabel `
                        -SeedAuthors $seedAuthors
                ) {
                    $matchingItems +=
                        $tailItem
                }
            }

            $selectedTail =
                @(
                    $matchingItems |
                    Sort-Object {
                        $_.itemInfo.title.displayValue.Length
                    }
                ) |
                Select-Object -First 1

            if (-not $selectedTail) {
                $tailChecks +=
                    [PSCustomObject]@{
                        TargetVolume =
                            $targetVolume

                        Keyword =
                            $tailKeyword

                        Found =
                            $false

                        ReturnedItemCount =
                            $tailItems.Count

                        ASIN =
                            ""

                        Title =
                            ""
                    }

                $tailStatus =
                    "NextVolumeNotFound"

                break
            }

            $tailTitle =
                $selectedTail.itemInfo.title.displayValue

            $tailAuthors =
                @(
                    Get-MangaAuthorNames `
                        -Item $selectedTail
                )

            $tailScore =
                Get-MangaCandidateScore `
                    -SeriesTitle $seriesTitle `
                    -Volume $targetVolume `
                    -Title $tailTitle `
                    -SeedLabel $seedLabel `
                    -SeedAuthors $seedAuthors `
                    -CandidateAuthors $tailAuthors

            $tailCandidate =
                [PSCustomObject]@{
                    Volume =
                        [int]$targetVolume

                    ASIN =
                        $selectedTail.asin

                    Title =
                        $tailTitle

                    Label =
                        (
                            Get-MangaTrailingLabel `
                                -Title $tailTitle
                        )

                    Authors =
                        @($tailAuthors)

                    Score =
                        $tailScore

                    KUMetadataAvailable =
                        (
                            Test-MangaKUMetadataAvailable `
                                -Item $selectedTail
                        )

                    SearchItemsKU =
                        (
                            Test-MangaKindleUnlimited `
                                -Item $selectedTail
                        )

                    SearchItemsLimitedFree =
                        (
                            Test-MangaLimitedFree `
                                -Item $selectedTail
                        )

                    SearchItemsPrice =
                        (
                            Get-MangaPrice `
                                -Item $selectedTail
                        )

                    ImageURL =
                        (
                            Get-MangaImageUrl `
                                -Item $selectedTail
                        )
                }

            $seriesIndex +=
                $tailCandidate

            $searchItemMap[$selectedTail.asin] =
                $selectedTail

            $tailChecks +=
                [PSCustomObject]@{
                    TargetVolume =
                        $targetVolume

                    Keyword =
                        $tailKeyword

                    Found =
                        $true

                    ReturnedItemCount =
                        $tailItems.Count

                    ASIN =
                        $selectedTail.asin

                    Title =
                        $tailTitle
                }

            $currentMaxVolume =
                $targetVolume

            $tailStatus =
                "NextVolumeFound"
        }
    }

    $seriesIndex =
        @(
            $seriesIndex |
            Sort-Object Volume
        )
    # ======================================
    # Find missing KU metadata
    # ======================================

    $fallbackAsins =
        @()

    foreach ($selected in $seriesIndex) {
        if (
            $selected.KUMetadataAvailable -eq
            $true
        ) {
            continue
        }

        if (
            $selected.ASIN -eq
            $seedASIN
        ) {
            continue
        }

        if (
            $fallbackAsins -notcontains
            $selected.ASIN
        ) {
            $fallbackAsins +=
                $selected.ASIN
        }
    }

    # ======================================
    # Fallback GetItems
    # ======================================

    $fallbackItemMap =
        @{}

    for (
        $offset = 0;
        $offset -lt $fallbackAsins.Count;
        $offset += 10
    ) {
        $endIndex =
            [Math]::Min(
                $offset + 9,
                $fallbackAsins.Count - 1
            )

        $batch =
            @(
                $fallbackAsins[
                    $offset..$endIndex
                ]
            )

        if ($offset -gt 0) {
            Start-Sleep `
                -Milliseconds $RequestDelayMilliseconds
        }

        $getItemsRequestCount++

        $batchItems =
            @(
                Invoke-AmazonGetItems `
                    -Asins $batch `
                    -Resources $resources `
                    -Config $Config `
                    -AccessToken $AccessToken
            )

        foreach ($item in $batchItems) {
            $fallbackItemMap[$item.asin] =
                $item
        }
    }

    # ======================================
    # Build final volume objects
    # ======================================

    $finalVolumes =
        @()

    foreach ($selected in $seriesIndex) {
        $isKU =
            $selected.SearchItemsKU

        $isLimitedFree =
            $selected.SearchItemsLimitedFree

        $limitedFreeMetadataSource =
            "SearchItems"

        $price =
            $selected.SearchItemsPrice

        $imageUrl =
            $selected.ImageURL

        $metadataSource =
            "SearchItems"

        if (
            $selected.KUMetadataAvailable -eq
            $true
        ) {
            $metadataSource =
                "SearchItems"
        }
        elseif (
            $selected.ASIN -eq
            $seedASIN
        ) {
            $seedKU =
                Test-MangaKindleUnlimited `
                    -Item $seedItem

            if ($null -ne $seedKU) {
                $isKU =
                    $seedKU

                $metadataSource =
                    "SeedGetItems"
            }
            else {
                $isKU =
                    $null

                $metadataSource =
                    "Unknown"
            }

            $seedLimitedFree =
                Test-MangaLimitedFree `
                    -Item $seedItem

            $isLimitedFree =
                $seedLimitedFree

            if ($null -ne $seedLimitedFree) {
                $limitedFreeMetadataSource =
                    "SeedGetItems"
            }
            else {
                $limitedFreeMetadataSource =
                    "Unknown"
            }

            if (
                [string]::IsNullOrWhiteSpace(
                    $price
                )
            ) {
                $price =
                    Get-MangaPrice `
                        -Item $seedItem
            }

            if (
                [string]::IsNullOrWhiteSpace(
                    $imageUrl
                )
            ) {
                $imageUrl =
                    Get-MangaImageUrl `
                        -Item $seedItem
            }
        }
        elseif (
            $fallbackItemMap.ContainsKey(
                $selected.ASIN
            )
        ) {
            $fallbackItem =
                $fallbackItemMap[
                    $selected.ASIN
                ]

            $fallbackKU =
                Test-MangaKindleUnlimited `
                    -Item $fallbackItem

            if ($null -ne $fallbackKU) {
                $isKU =
                    $fallbackKU

                $metadataSource =
                    "GetItems"
            }
            else {
                $isKU =
                    $null

                $metadataSource =
                    "Unknown"
            }

            $fallbackLimitedFree =
                Test-MangaLimitedFree `
                    -Item $fallbackItem

            $isLimitedFree =
                $fallbackLimitedFree

            if ($null -ne $fallbackLimitedFree) {
                $limitedFreeMetadataSource =
                    "GetItems"
            }
            else {
                $limitedFreeMetadataSource =
                    "Unknown"
            }

            if (
                [string]::IsNullOrWhiteSpace(
                    $price
                )
            ) {
                $price =
                    Get-MangaPrice `
                        -Item $fallbackItem
            }

            if (
                [string]::IsNullOrWhiteSpace(
                    $imageUrl
                )
            ) {
                $imageUrl =
                    Get-MangaImageUrl `
                        -Item $fallbackItem
            }
        }
        else {
            $isKU =
                $null

            $metadataSource =
                "Unknown"

            $isLimitedFree =
                $null

            $limitedFreeMetadataSource =
                "Unknown"
        }

        $kuStatus =
            "Unknown"

        if ($isKU -eq $true) {
            $kuStatus =
                "KU"
        }
        elseif ($isKU -eq $false) {
            $kuStatus =
                "NO"
        }

        $detailPageURL =
            ""

        if (
            $searchItemMap.ContainsKey(
                $selected.ASIN
            )
        ) {
            $detailPageURL =
                $searchItemMap[
                    $selected.ASIN
                ].detailPageURL
        }

        $finalVolumes +=
            [PSCustomObject]@{
                Volume =
                    [int]$selected.Volume

                ASIN =
                    $selected.ASIN

                Title =
                    $selected.Title

                Price =
                    $price

                ImageURL =
                    $imageUrl

                IsKindleUnlimited =
                    $isKU

                KindleUnlimitedStatus =
                    $kuStatus

                KUMetadataSource =
                    $metadataSource

                IsLimitedFree =
                    $isLimitedFree

                LimitedFreeMetadataSource =
                    $limitedFreeMetadataSource

                CandidateScore =
                    $selected.Score

                DetailPageURL =
                    $detailPageURL
            }
    }

    $finalVolumes =
        @(
            $finalVolumes |
            Sort-Object Volume
        )

    # ======================================
    # Final volume analysis
    # ======================================

    $detectedVolumes =
        @(
            $finalVolumes |
            ForEach-Object {
                $_.Volume
            } |
            Sort-Object -Unique
        )

    $maxDetectedVolume =
        $null

    $missingVolumes =
        @()

    $isContinuous =
        $false

    if ($detectedVolumes.Count -gt 0) {
        $maxDetectedVolume =
            (
                $detectedVolumes |
                Measure-Object -Maximum
            ).Maximum

        $expectedVolumes =
            @(
                1..$maxDetectedVolume
            )

        $missingVolumes =
            @(
                $expectedVolumes |
                Where-Object {
                    $detectedVolumes -notcontains
                    $_
                }
            )

        if ($missingVolumes.Count -eq 0) {
            $isContinuous =
                $true
        }
    }

    $kuVolumes =
        @(
            $finalVolumes |
            Where-Object {
                $_.IsKindleUnlimited -eq
                $true
            } |
            ForEach-Object {
                $_.Volume
            } |
            Sort-Object -Unique
        )

    $nonKUVolumes =
        @(
            $finalVolumes |
            Where-Object {
                $_.IsKindleUnlimited -eq
                $false
            } |
            ForEach-Object {
                $_.Volume
            } |
            Sort-Object -Unique
        )

    $unknownKUVolumes =
        @(
            $finalVolumes |
            Where-Object {
                $null -eq
                $_.IsKindleUnlimited
            } |
            ForEach-Object {
                $_.Volume
            } |
            Sort-Object -Unique
        )

    $limitedFreeVolumes =
        @(
            $finalVolumes |
            Where-Object {
                $_.IsLimitedFree -eq
                $true
            } |
            ForEach-Object {
                $_.Volume
            } |
            Sort-Object -Unique
        )

    $unknownLimitedFreeVolumes =
        @(
            $finalVolumes |
            Where-Object {
                $null -eq
                $_.IsLimitedFree
            } |
            ForEach-Object {
                $_.Volume
            } |
            Sort-Object -Unique
        )

    $totalVolumeStatus =
        "Unknown"

    if (
        -not $isSearchTruncated -and
        $isContinuous -and
        $detectedVolumes.Count -gt 0
    ) {
        $totalVolumeStatus =
            "Confirmed"
    }
    elseif (
        $isSearchTruncated -and
        $isContinuous -and
        $tailStatus -eq
        "NextVolumeNotFound"
    ) {
        $totalVolumeStatus =
            "StrongProbable"
    }
    elseif (
        $isSearchTruncated -and
        $isContinuous
    ) {
        $totalVolumeStatus =
            "Probable"
    }

    $isAllDetectedVolumesKU =
        $null

    if (
        $unknownKUVolumes.Count -eq 0 -and
        $detectedVolumes.Count -gt 0
    ) {
        $isAllDetectedVolumesKU =
            (
                $kuVolumes.Count -eq
                $detectedVolumes.Count
            )
    }

    $creatorsApiRequests =
        $searchRequestCount +
        $getItemsRequestCount

    return [PSCustomObject]@{
        SeedASIN =
            $seedASIN

        SeedTitle =
            $seedTitle

        SeedVolume =
            $seedVolume

        SeedImageURL =
            $seedImageUrl

        SeriesTitle =
            $seriesTitle

        SeedLabel =
            $seedLabel

        SeedAuthors =
            @($seedAuthors)

        SearchTotalResultCount =
            $totalResultCount

        SearchRetrievedItemCount =
            $searchItems.Count

        RequiredSearchPages =
            $requiredPages

        IsSearchTruncated =
            $isSearchTruncated

        TotalVolumeStatus =
            $totalVolumeStatus

        DetectedVolumeCount =
            $detectedVolumes.Count

        DetectedVolumes =
            @($detectedVolumes)

        DetectedRanges =
            (
                ConvertTo-MangaVolumeRanges `
                    -Volumes $detectedVolumes
            )

        MaxDetectedVolume =
            $maxDetectedVolume

        IsContinuousFromVolume1 =
            $isContinuous

        MissingVolumes =
            @($missingVolumes)

        KindleUnlimitedVolumeCount =
            $kuVolumes.Count

        KindleUnlimitedVolumes =
            @($kuVolumes)

        KindleUnlimitedRanges =
            (
                ConvertTo-MangaVolumeRanges `
                    -Volumes $kuVolumes
            )

        NonKindleUnlimitedVolumes =
            @($nonKUVolumes)

        NonKindleUnlimitedRanges =
            (
                ConvertTo-MangaVolumeRanges `
                    -Volumes $nonKUVolumes
            )

        UnknownKindleUnlimitedVolumes =
            @($unknownKUVolumes)

        UnknownKindleUnlimitedRanges =
            (
                ConvertTo-MangaVolumeRanges `
                    -Volumes $unknownKUVolumes
            )

        IsAllDetectedVolumesKindleUnlimited =
            $isAllDetectedVolumesKU

        LimitedFreeVolumeCount =
            $limitedFreeVolumes.Count

        LimitedFreeVolumes =
            @($limitedFreeVolumes)

        LimitedFreeRanges =
            (
                ConvertTo-MangaVolumeRanges `
                    -Volumes $limitedFreeVolumes
            )

        UnknownLimitedFreeVolumes =
            @($unknownLimitedFreeVolumes)

        UnknownLimitedFreeRanges =
            (
                ConvertTo-MangaVolumeRanges `
                    -Volumes $unknownLimitedFreeVolumes
            )

        TailStatus =
            $tailStatus

        TailChecks =
            @($tailChecks)

        FallbackASINCount =
            $fallbackAsins.Count

        SearchItemsRequests =
            $searchRequestCount

        GetItemsRequests =
            $getItemsRequestCount

        CreatorsApiRequests =
            $creatorsApiRequests

        Volumes =
            @($finalVolumes)

        Candidates =
            @($candidates)
    }
}