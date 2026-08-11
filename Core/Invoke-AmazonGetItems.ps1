function Invoke-AmazonGetItems {

    param(
        [Parameter(Mandatory)]
        [array]$Asins,

        [Parameter(Mandatory)]
        [array]$Resources,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [int]$MaxRetries = 3
    )


    if ($Asins.Count -eq 0) {

        return @()
    }


    if ($Asins.Count -gt 10) {

        throw "GetItems accepts a maximum of 10 ASINs per request."
    }


    $getItemsUrl =
        "https://creatorsapi.amazon/catalog/v1/getItems"


    $requestBody = @{
        itemIds     = @($Asins)
        itemIdType  = "ASIN"
        partnerTag  = $Config.PartnerTag
        marketplace = $Config.Marketplace
        resources   = $Resources
    }


    $requestJson =
        $requestBody |
        ConvertTo-Json -Depth 10


    $requestBytes =
        [System.Text.Encoding]::UTF8.GetBytes(
            $requestJson
        )


    $headers = @{
        Authorization   = "Bearer $AccessToken"
        "x-marketplace" = $Config.Marketplace
    }


    $requestParameters = @{
        Uri         = $getItemsUrl
        Method      = "Post"
        Headers     = $headers
        ContentType = "application/json; charset=utf-8"
        Body        = $requestBytes
    }


    $attempt =
        0


    while ($true) {

        try {

            $webResponse =
                Invoke-WebRequest `
                    @requestParameters `
                    -UseBasicParsing

            break
        }
        catch {

            $attempt++


            $statusCode =
                $null


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


    $response =
        $responseText |
        ConvertFrom-Json


    if (
        $response.itemsResult -and
        $response.itemsResult.items
    ) {

        return @(
            $response.itemsResult.items
        )
    }


    return @()
}