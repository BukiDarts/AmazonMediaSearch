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
$resultGrid = $window.FindName("ResultGrid")


# ==========================================
# Amazon検索関数
# ==========================================
function Search-AmazonItem {

    # --------------------------------------
    # 検索ワード取得
    # --------------------------------------
    $keyword = $searchBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($keyword)) {

        [System.Windows.MessageBox]::Show(
            "Please enter a keyword.",
            "Search"
        )

        return
    }


    # --------------------------------------
    # Amazonへ送信する検索条件
    # --------------------------------------
    $searchBody = @{
        partnerTag  = $config.PartnerTag
        keywords    = $keyword
        searchIndex = "Books"
        itemCount   = 10

        resources = @(
            "itemInfo.title"
            "itemInfo.byLineInfo"
            "itemInfo.contentInfo"
            "images.primary.medium"
        )
    }


    # --------------------------------------
    # JSONへ変換
    # --------------------------------------
    $searchJson = $searchBody | ConvertTo-Json -Depth 10


    # --------------------------------------
    # UTF-8のバイト列へ変換
    # PowerShell 5.1の日本語送信対策
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
    # Invoke-WebRequest用パラメータ
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

        # PowerShell 5.1で日本語レスポンスが
        # 文字化けしないように生データで受信
        $webResponse = Invoke-WebRequest @searchParameters

        $responseBytes = $webResponse.RawContentStream.ToArray()

        $responseText =
            [System.Text.Encoding]::UTF8.GetString($responseBytes)

        $response = $responseText | ConvertFrom-Json


        # ----------------------------------
        # DataGrid用データ作成
        # ----------------------------------
        $results = @()

        foreach ($item in $response.searchResult.items) {

            # 著者
            $authors = @()

            foreach ($contributor in $item.itemInfo.byLineInfo.contributors) {

                if ($contributor.roleType -eq "author") {
                    $authors += $contributor.name
                }
            }

            $authorText = $authors -join ", "

            # 出版日
            $publicationDate =
                $item.itemInfo.contentInfo.publicationDate.displayValue

            # 表紙画像URL
            $imageUrl =
                $item.images.primary.medium.url

            $result = [PSCustomObject]@{
                Title           = $item.itemInfo.title.displayValue
                Author          = $authorText
                PublicationDate = $publicationDate
                ASIN            = $item.asin
                ImageURL        = $imageUrl
                URL             = $item.detailPageURL
            }

            $results += $result
        }


        # ----------------------------------
        # DataGridへ表示
        # ----------------------------------
        $resultGrid.ItemsSource = $results

    }
    catch {

        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            "Search Error"
        )
    }
}


# ==========================================
# 検索ボタン
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