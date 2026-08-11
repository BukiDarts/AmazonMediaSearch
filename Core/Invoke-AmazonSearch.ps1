function Invoke-AmazonSearch {

    param(
        [Parameter(Mandatory)]
        [string]$Keyword,

        [Parameter(Mandatory)]
        [string]$SearchIndex,

        [Parameter(Mandatory)]
        [array]$Resources,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [int]$ItemCount = 10,

        [int]$ItemPage = 1,

        [string]$SortBy = "",

        [int]$MaxRetries = 3
    )

    $searchBody = @{
        partnerTag  = $Config.PartnerTag
        keywords    = $Keyword
        searchIndex = $SearchIndex
        itemCount   = $ItemCount
        itemPage    = $ItemPage
        resources   = $Resources
    }

    if (-not [string]::IsNullOrWhiteSpace($SortBy)) {
        $searchBody.sortBy = $SortBy
    }

    $searchJson =
        $searchBody |
        ConvertTo-Json -Depth 10

    $searchBytes =
        [System.Text.Encoding]::UTF8.GetBytes(
            $searchJson
        )

    $headers = @{
        Authorization   = "Bearer $AccessToken"
        "x-marketplace" = $Config.Marketplace
    }

    $searchParameters = @{
        Uri         = $Config.SearchUrl
        Method      = "Post"
        Headers     = $headers
        ContentType = "application/json; charset=utf-8"
        Body        = $searchBytes
    }


    # ======================================
    # Request with retry
    # ======================================
    $attempt = 0

    while ($true) {

        try {

            $webResponse =
                Invoke-WebRequest `
                    @searchParameters `
                    -UseBasicParsing

            break
        }
        catch {

            $attempt++

            $statusCode = $null

            if ($_.Exception.Response) {

                try {

                    $statusCode =
                        [int]$_.Exception.Response.StatusCode

                }
                catch {

                    $statusCode =
                        $null
                }
            }


            # Retry only for rate limiting
            if (
                $statusCode -eq 429 -and
                $attempt -le $MaxRetries
            ) {

                # Exponential backoff:
                # 1 sec, 2 sec, 4 sec
                $waitSeconds =
                    [math]::Pow(2, $attempt - 1)

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


    # ======================================
    # Decode response
    # ======================================
    $responseBytes =
        $webResponse.RawContentStream.ToArray()

    $responseText =
        [System.Text.Encoding]::UTF8.GetString(
            $responseBytes
        )

    $response =
        $responseText |
        ConvertFrom-Json

    return $response
}