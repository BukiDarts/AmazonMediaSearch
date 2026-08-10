# credentials.json を読み込む
$credentials = Get-Content ".\credentials.json" -Raw |
    ConvertFrom-Json

# Amazonに送るデータを作る
$body = @{
    grant_type    = "client_credentials"
    client_id     = $credentials.CredentialId
    client_secret = $credentials.Secret
    scope         = "creatorsapi::default"
}

# PowerShellのオブジェクトをJSONに変換
$jsonBody = $body | ConvertTo-Json

# 認証APIを呼び出す
$response = Invoke-RestMethod `
    -Uri "https://api.amazon.co.jp/auth/o2/token" `
    -Method Post `
    -ContentType "application/json" `
    -Body $jsonBody

# レスポンスを表示
$response