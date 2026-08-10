Add-Type -AssemblyName PresentationFramework

# ==========================================
# 設定ファイル読み込み
# ==========================================
$configPath = Join-Path $PSScriptRoot "config.json"

if (-not (Test-Path $configPath)) {
    [System.Windows.MessageBox]::Show(
        "config.json not found.",
        "Error"
    )
    exit
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json


# ==========================================
# アクセストークン取得
# ==========================================
$authBody = @{
    grant_type    = "client_credentials"
    client_id     = $config.CredentialId
    client_secret = $config.Secret
    scope         = "creatorsapi::default"
}

$authParameters = @{
    Uri         = $config.AuthUrl
    Method      = "Post"
    ContentType = "application/json"
    Body        = ($authBody | ConvertTo-Json)
}

try {

    $authResponse = Invoke-RestMethod @authParameters
    $accessToken = $authResponse.access_token

}
catch {

    [System.Windows.MessageBox]::Show(
        $_.Exception.Message,
        "Authentication Error"
    )

    exit
}


# ==========================================
# XAML読み込み
# ==========================================
$xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"

if (-not (Test-Path $xamlPath)) {
    [System.Windows.MessageBox]::Show(
        "MainWindow.xaml not found.",
        "Error"
    )
    exit
}

$xaml = Get-Content $xamlPath -Raw

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)

$window = [Windows.Markup.XamlReader]::Load($reader)


# ==========================================
# WPFコントロール取得
# ==========================================
$searchBox = $window.FindName("SearchBox")
$searchButton = $window.FindName("SearchButton")
$resultBox = $window.FindName("ResultBox")


# ==========================================
# Amazon検索関数
# ==========================================
function Search-AmazonItem {

    # --------------------------------------
    # 検索ワード取得
    # --------------------------------------
    $keyword = $searchBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($keyword)) {

        $resultBox.Text = "Please enter a keyword."

        return
    }

    $resultBox.Text = "Searching..."


    # --------------------------------------
    # Amazonへ送信する検索条件
    # --------------------------------------
    $searchBody = @{
        partnerTag  = $config.PartnerTag
        keywords    = $keyword
        searchIndex = "Books"
        itemCount   = 10
    }


    # --------------------------------------
    # JSONへ変換
    # --------------------------------------
    $searchJson = $searchBody | ConvertTo-Json -Depth 10


    # --------------------------------------
    # UTF-8のバイト列へ変換
    # PowerShell 5.1の日本語文字化け対策
    # --------------------------------------
    $searchBytes = [System.Text.Encoding]::UTF8.GetBytes($searchJson)


    # --------------------------------------
    # HTTPヘッダー
    # --------------------------------------
    $headers = @{
        Authorization   = "Bearer $accessToken"
        "x-marketplace" = $config.Marketplace
    }


    # --------------------------------------
    # Invoke-RestMethod用パラメータ
    # --------------------------------------
    $searchParameters = @{
        Uri         = $config.SearchUrl
        Method      = "Post"
        Headers     = $headers
        ContentType = "application/json; charset=utf-8"
        Body        = $searchBytes
    }


    # --------------------------------------
    # Creators APIへリクエスト
    # --------------------------------------
    try {

    $webResponse = Invoke-WebRequest @searchParameters

    $responseBytes = $webResponse.RawContentStream.ToArray()

    $responseText = [System.Text.Encoding]::UTF8.GetString($responseBytes)

    $response = $responseText | ConvertFrom-Json

    $resultBox.Text = $response |
        ConvertTo-Json -Depth 20
    }
    catch {

        $errorMessage = $_.Exception.Message

        $resultBox.Text =
            "Search error:`r`n`r`n" +
            $errorMessage +
            "`r`n`r`n" +
            "Request JSON:`r`n" +
            $searchJson
    }
}


# ==========================================
# 検索ボタンをクリック
# ==========================================
$searchButton.Add_Click({

    Search-AmazonItem

})


# ==========================================
# Enterキーでも検索
# ==========================================
$searchBox.Add_KeyDown({

    if ($_.Key -eq "Return") {

        Search-AmazonItem

    }

})


# ==========================================
# WPF表示
# ==========================================
$window.ShowDialog() | Out-Null