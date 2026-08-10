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
        [string]$AccessToken
    )

    $searchBody = @{
        partnerTag  = $Config.PartnerTag
        keywords    = $Keyword
        searchIndex = $SearchIndex
        itemCount   = 10
        resources   = $Resources
    }

    $searchJson =
        $searchBody | ConvertTo-Json -Depth 10

    $searchBytes =
        [System.Text.Encoding]::UTF8.GetBytes($searchJson)

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

    $webResponse =
        Invoke-WebRequest @searchParameters -UseBasicParsing

    $responseBytes =
        $webResponse.RawContentStream.ToArray()

    $responseText =
        [System.Text.Encoding]::UTF8.GetString(
            $responseBytes
        )

    $response =
        $responseText | ConvertFrom-Json

    return $response
}