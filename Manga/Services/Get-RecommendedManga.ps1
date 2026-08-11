# ==========================================
# Recommended Manga Service
# ==========================================


function Get-RecommendedMangaBrowseNodeText {

    param(
        $Item
    )


    if (
        -not $Item.browseNodeInfo -or
        -not $Item.browseNodeInfo.browseNodes
    ) {

        return ""
    }


    $names =
        @()


    foreach (
        $node in
        $Item.browseNodeInfo.browseNodes
    ) {

        if (
            -not [string]::IsNullOrWhiteSpace(
                $node.contextFreeName
            )
        ) {

            $names +=
                [string]$node.contextFreeName
        }


        if (
            -not [string]::IsNullOrWhiteSpace(
                $node.displayName
            )
        ) {

            $names +=
                [string]$node.displayName
        }
    }


    return (
        @(
            $names |
            Sort-Object -Unique
        ) -join " | "
    )
}


function Test-RecommendedMangaKUMetadataAvailable {

    param(
        $Item
    )


    return (
        $Item.browseNodeInfo -and
        $null -ne
        $Item.browseNodeInfo.browseNodes
    )
}


function Test-RecommendedMangaKU {

    param(
        $Item
    )


    if (
        -not (
            Test-RecommendedMangaKUMetadataAvailable `
                -Item $Item
        )
    ) {

        return $null
    }


    $text =
        Get-RecommendedMangaBrowseNodeText `
            -Item $Item


    return (
        $text -match
        'Kindle Unlimited'
    )
}


function Test-RecommendedMangaLimitedFree {

    param(
        $Item
    )


    if (
        -not (
            Test-RecommendedMangaKUMetadataAvailable `
                -Item $Item
        )
    ) {

        return $null
    }


    $text =
        Get-RecommendedMangaBrowseNodeText `
            -Item $Item


    return (
        $text -match
        '\u671F\u9593\u9650\u5B9A\u7121\u6599'
    )
}


function Get-RecommendedMangaPrice {

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
                $_.isBuyBoxWinner -eq $true
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
        $listing.price -and
        $listing.price.money
    ) {

        return [string]$listing.price.money.displayAmount
    }


    return ""
}


function Get-RecommendedMangaImageUrl {

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


function Invoke-RecommendedMangaSearch {

    param(
        [Parameter(Mandatory)]
        [string]$Keyword,

        [Parameter(Mandatory)]
        [string]$BrowseNodeId,

        [Parameter(Mandatory)]
        [array]$Resources,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [int]$ItemPage = 1,

        [int]$ItemCount = 10,

        [string]$SortBy = "Featured",

        [int]$MaxRetries = 3
    )


    $body =
        @{
            partnerTag   = $Config.PartnerTag
            marketplace  = $Config.Marketplace
            searchIndex  = "KindleStore"
            keywords     = $Keyword
            browseNodeId = $BrowseNodeId
            itemCount    = $ItemCount
            itemPage     = $ItemPage
            sortBy       = $SortBy
            resources    = $Resources
        }


    $json =
        $body |
        ConvertTo-Json -Depth 20


    $bytes =
        [System.Text.Encoding]::UTF8.GetBytes(
            $json
        )


    $headers =
        @{
            Authorization   = "Bearer $AccessToken"
            "x-marketplace" = $Config.Marketplace
        }


    $parameters =
        @{
            Uri         = $Config.SearchUrl
            Method      = "Post"
            Headers     = $headers
            ContentType = "application/json; charset=utf-8"
            Body        = $bytes
        }


    $attempt =
        0


    while ($true) {

        try {

            $webResponse =
                Invoke-WebRequest `
                    @parameters `
                    -UseBasicParsing


            break
        }
        catch {

            $attempt++


            $statusCode =
                $null


            if (
                $_.Exception.Response
            ) {

                try {

                    $statusCode =
                        [int]$_.Exception.Response.StatusCode
                }
                catch {

                    $statusCode =
                        $null
                }
            }


            if (
                $statusCode -eq 429 -and
                $attempt -le $MaxRetries
            ) {

                $waitSeconds =
                    [math]::Pow(
                        2,
                        $attempt - 1
                    )


                Write-Host (
                    "Rate limited. Retry {0}/{1} after {2} second(s)." -f
                    $attempt,
                    $MaxRetries,
                    $waitSeconds
                )


                Start-Sleep `
                    -Seconds $waitSeconds


                continue
            }


            throw
        }
    }


    $responseBytes =
        $webResponse.RawContentStream.ToArray()


    $responseText =
        [System.Text.Encoding]::UTF8.GetString(
            $responseBytes
        )


    return (
        $responseText |
        ConvertFrom-Json
    )
}


function Get-RecommendedManga {

    param(
        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [string]$Keyword = "マンガ",

        [string]$BrowseNodeId = "10473732051",

        [int]$RequestDelayMilliseconds = 1100
    )


    $resources =
        @(
            "itemInfo.title",
            "itemInfo.byLineInfo",
            "itemInfo.classifications",
            "images.primary.medium",
            "browseNodeInfo.browseNodes",
            "offersV2.listings.isBuyBoxWinner",
            "offersV2.listings.price"
        )


    $allItems =
        @()


    $totalResultCount =
        0


    $page =
        1


    $requestCount =
        0


    while ($true) {

        if (
            $page -gt 1
        ) {

            Start-Sleep `
                -Milliseconds $RequestDelayMilliseconds
        }


        $response =
            Invoke-RecommendedMangaSearch `
                -Keyword $Keyword `
                -BrowseNodeId $BrowseNodeId `
                -Resources $resources `
                -Config $Config `
                -AccessToken $AccessToken `
                -ItemPage $page `
                -ItemCount 10 `
                -SortBy "Featured"


        $requestCount++


        if (
            $response.searchResult -and
            $null -ne
            $response.searchResult.totalResultCount
        ) {

            $totalResultCount =
                [int]$response.searchResult.totalResultCount
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


        $allItems +=
            $items


        if (
            $allItems.Count -ge
            $totalResultCount
        ) {

            break
        }


        if (
            $page -ge 10 -or
            $items.Count -eq 0
        ) {

            break
        }


        $page++
    }


    $seenAsins =
        @{}


    $rows =
        @()


    $order =
        0


    foreach (
        $item in $allItems
    ) {

        $asin =
            [string]$item.asin


        if (
            [string]::IsNullOrWhiteSpace(
                $asin
            )
        ) {

            continue
        }


        if (
            $seenAsins.ContainsKey(
                $asin
            )
        ) {

            continue
        }


        $seenAsins[$asin] =
            $true


        $order++


        $title =
            ""


        if (
            $item.itemInfo -and
            $item.itemInfo.title
        ) {

            $title =
                [string]$item.itemInfo.title.displayValue
        }


        $rows +=
            [PSCustomObject]@{

                Order =
                    $order

                ASIN =
                    $asin

                Title =
                    $title

                Price =
                    (
                        Get-RecommendedMangaPrice `
                            -Item $item
                    )

                IsKindleUnlimited =
                    (
                        Test-RecommendedMangaKU `
                            -Item $item
                    )

                IsLimitedFree =
                    (
                        Test-RecommendedMangaLimitedFree `
                            -Item $item
                    )

                ImageURL =
                    (
                        Get-RecommendedMangaImageUrl `
                            -Item $item
                    )

                DetailPageURL =
                    [string]$item.detailPageURL
            }
    }


    return [PSCustomObject]@{

        BrowseNodeId =
            $BrowseNodeId

        Keyword =
            $Keyword

        TotalResultCount =
            $totalResultCount

        RetrievedItemCount =
            $allItems.Count

        UniqueItemCount =
            $rows.Count

        SearchItemsRequests =
            $requestCount

        CreatorsApiRequests =
            $requestCount

        Items =
            @($rows)
    }
}


function Get-RecommendedMangaCached {

    param(
        [Parameter(Mandatory)]
        $Config,

        [string]$AccessToken = "",

        [string]$CacheDirectory = "",

        [int]$CacheHours = 6,

        [switch]$ForceRefresh
    )


    if (
        [string]::IsNullOrWhiteSpace(
            $CacheDirectory
        )
    ) {

        $projectRoot =
            Split-Path `
                (Split-Path $PSScriptRoot -Parent) `
                -Parent


        $CacheDirectory =
            Join-Path `
                $projectRoot `
                "Cache\Manga\Recommended"
    }


    if (
        -not (
            Test-Path $CacheDirectory
        )
    ) {

        New-Item `
            -ItemType Directory `
            -Path $CacheDirectory `
            -Force |
        Out-Null
    }


    $cachePath =
        Join-Path `
            $CacheDirectory `
            "recommended.json"


    if (
        -not $ForceRefresh -and
        (Test-Path $cachePath)
    ) {

        try {

            $cacheFile =
                Get-Item $cachePath


            $age =
                (Get-Date) -
                $cacheFile.LastWriteTime


            if (
                $age.TotalHours -lt
                $CacheHours
            ) {

                $cached =
                    Get-Content `
                        $cachePath `
                        -Raw |
                    ConvertFrom-Json


                $cached |
                    Add-Member `
                        -NotePropertyName CacheStatus `
                        -NotePropertyValue "Hit" `
                        -Force


                $cached |
                    Add-Member `
                        -NotePropertyName CachePath `
                        -NotePropertyValue $cachePath `
                        -Force


                $cached |
                    Add-Member `
                        -NotePropertyName CacheAgeMinutes `
                        -NotePropertyValue ([math]::Round($age.TotalMinutes, 1)) `
                        -Force


                $cached |
                    Add-Member `
                        -NotePropertyName CurrentOAuthRequests `
                        -NotePropertyValue 0 `
                        -Force


                $cached |
                    Add-Member `
                        -NotePropertyName CurrentCreatorsApiRequests `
                        -NotePropertyValue 0 `
                        -Force


                return $cached
            }
        }
        catch {

            Write-Host (
                "Failed to read recommended manga cache: {0}" -f
                $_.Exception.Message
            )
        }
    }


    $oauthRequests =
        0


    if (
        [string]::IsNullOrWhiteSpace(
            $AccessToken
        )
    ) {

        $AccessToken =
            Get-AmazonAccessToken `
                -Config $Config


        $oauthRequests =
            1
    }


    $result =
        Get-RecommendedManga `
            -Config $Config `
            -AccessToken $AccessToken


    $result |
        Add-Member `
            -NotePropertyName CacheStatus `
            -NotePropertyValue "Miss" `
            -Force


    $result |
        Add-Member `
            -NotePropertyName CachePath `
            -NotePropertyValue $cachePath `
            -Force


    $result |
        Add-Member `
            -NotePropertyName CacheAgeMinutes `
            -NotePropertyValue 0 `
            -Force


    $result |
        Add-Member `
            -NotePropertyName CurrentOAuthRequests `
            -NotePropertyValue $oauthRequests `
            -Force


    $result |
        Add-Member `
            -NotePropertyName CurrentCreatorsApiRequests `
            -NotePropertyValue $result.CreatorsApiRequests `
            -Force


    try {

        $utf8Bom =
            New-Object `
                System.Text.UTF8Encoding `
                -ArgumentList $true


        [System.IO.File]::WriteAllText(
            $cachePath,
            (
                $result |
                ConvertTo-Json -Depth 30
            ),
            $utf8Bom
        )
    }
    catch {

        Write-Host (
            "Failed to write recommended manga cache: {0}" -f
            $_.Exception.Message
        )
    }


    return $result
}
