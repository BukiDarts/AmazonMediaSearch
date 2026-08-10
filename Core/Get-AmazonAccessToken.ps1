function Get-AmazonAccessToken {

    param(
        [Parameter(Mandatory)]
        $Config
    )

    $authBody = @{
        grant_type    = "client_credentials"
        client_id     = $Config.CredentialId
        client_secret = $Config.Secret
        scope         = "creatorsapi::default"
    }

    $authParameters = @{
        Uri         = $Config.AuthUrl
        Method      = "Post"
        ContentType = "application/json"
        Body        = ($authBody | ConvertTo-Json)
    }

    $authResponse = Invoke-RestMethod @authParameters

    return $authResponse.access_token
}