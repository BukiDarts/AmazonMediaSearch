param(
    [string]$AuthorKeyword = "村上龍",
    [int]$MaxPages = 3
)

$projectRoot = Split-Path $PSScriptRoot -Parent

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"
. "$projectRoot\Core\Invoke-AmazonSearch.ps1"

$configPath = Join-Path $projectRoot "config.json"
$outputDirectory = Join-Path $PSScriptRoot "Output"

if (-not (Test-Path $configPath)) {
    throw "config.json not found."
}

if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true

function ConvertTo-AuthorNormalizedText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $value = $Text.Normalize([Text.NormalizationForm]::FormKC)
    $value = $value -replace '[\u3000\s]+', ''

    return $value.Trim().ToLowerInvariant()
}

function Get-DebugTitle {
    param($Item)

    if ($Item.itemInfo -and $Item.itemInfo.title) {
        return [string]$Item.itemInfo.title.displayValue
    }

    return ""
}

function Get-DebugContributors {
    param($Item)

    $rows = @()

    if (
        $Item.itemInfo -and
        $Item.itemInfo.byLineInfo -and
        $Item.itemInfo.byLineInfo.contributors
    ) {
        foreach ($contributor in $Item.itemInfo.byLineInfo.contributors) {
            $rows += [PSCustomObject]@{
                Name = [string]$contributor.name
                Role = [string]$contributor.role
                RoleType = [string]$contributor.roleType
            }
        }
    }

    return @($rows)
}

function Test-AuthorMatch {
    param(
        [array]$Contributors,
        [string]$AuthorKeyword
    )

    $keyword =
        ConvertTo-AuthorNormalizedText `
            -Text $AuthorKeyword

    foreach ($contributor in @($Contributors)) {
        $name =
            ConvertTo-AuthorNormalizedText `
                -Text ([string]$contributor.Name)

        $role =
            ConvertTo-AuthorNormalizedText `
                -Text ([string]$contributor.Role)

        $roleType =
            ConvertTo-AuthorNormalizedText `
                -Text ([string]$contributor.RoleType)

        $isAuthorRole =
            (
                $roleType -eq "author" -or
                $role -eq "author" -or
                $role -match "著"
            )

        if (
            $isAuthorRole -and
            -not [string]::IsNullOrWhiteSpace($name) -and
            (
                $name.Contains($keyword) -or
                $keyword.Contains($name)
            )
        ) {
            return $true
        }
    }

    return $false
}

function Invoke-AuthorDebugSearch {
    param(
        [string]$Label,
        [string]$SearchIndex,
        [string]$Keyword,
        $Config,
        [string]$AccessToken,
        [int]$MaxPages
    )

    $resources = @(
        "itemInfo.title",
        "itemInfo.byLineInfo"
    )

    $rows = @()
    $totalResultCount = 0
    $requiredPages = 1
    $requestCount = 0
    $rank = 0

    for ($page = 1; $page -le $MaxPages; $page++) {
        if ($page -gt $requiredPages) {
            break
        }

        if ($page -gt 1) {
            Start-Sleep -Milliseconds 1100
        }

        Write-Host (
            "[{0}] Requesting page {1}..." -f
            $Label,
            $page
        )

        $response =
            Invoke-AmazonSearch `
                -Keyword $Keyword `
                -SearchIndex $SearchIndex `
                -Resources $resources `
                -Config $Config `
                -AccessToken $AccessToken `
                -ItemCount 10 `
                -ItemPage $page

        $requestCount++

        if (
            $response.searchResult -and
            $null -ne $response.searchResult.totalResultCount
        ) {
            $totalResultCount =
                [int]$response.searchResult.totalResultCount

            $requiredPages =
                [math]::Ceiling(
                    $totalResultCount / 10
                )

            if ($requiredPages -gt $MaxPages) {
                $requiredPages = $MaxPages
            }
        }

        $items = @()

        if (
            $response.searchResult -and
            $response.searchResult.items
        ) {
            $items =
                @(
                    $response.searchResult.items
                )
        }

        if ($items.Count -eq 0) {
            break
        }

        foreach ($item in $items) {
            $rank++

            $contributors =
                @(
                    Get-DebugContributors `
                        -Item $item
                )

            $isMatch =
                Test-AuthorMatch `
                    -Contributors $contributors `
                    -AuthorKeyword $Keyword

            $rows +=
                [PSCustomObject]@{
                    Category = $Label
                    SearchIndex = $SearchIndex
                    SearchRank = $rank
                    ASIN = [string]$item.asin
                    Title = Get-DebugTitle -Item $item
                    AuthorMatch = $isMatch
                    Contributors = $contributors
                    DetailPageURL = [string]$item.detailPageURL
                }
        }
    }

    $matchedRows =
        @(
            $rows |
            Where-Object {
                $_.AuthorMatch -eq $true
            }
        )

    $excludedRows =
        @(
            $rows |
            Where-Object {
                $_.AuthorMatch -ne $true
            }
        )

    return [PSCustomObject]@{
        Category = $Label
        SearchIndex = $SearchIndex
        Keyword = $Keyword
        TotalResultCount = $totalResultCount
        RetrievedItems = $rows.Count
        MatchedItems = $matchedRows.Count
        ExcludedItems = $excludedRows.Count
        SearchItemsRequests = $requestCount
        Matched = $matchedRows
        Excluded = $excludedRows
        AllItems = $rows
    }
}

Write-Host ""
Write-Host "=========================================="
Write-Host "Author Search Debug"
Write-Host "=========================================="
Write-Host ("Author keyword: {0}" -f $AuthorKeyword)
Write-Host ""

$accessToken =
    Get-AmazonAccessToken `
        -Config $config

$targets = @(
    [PSCustomObject]@{
        Label = "Books"
        SearchIndex = "Books"
    },
    [PSCustomObject]@{
        Label = "Kindle"
        SearchIndex = "KindleStore"
    },
    [PSCustomObject]@{
        Label = "Audible"
        SearchIndex = "Audible"
    }
)

$results = @()

foreach ($target in $targets) {
    try {
        $result =
            Invoke-AuthorDebugSearch `
                -Label $target.Label `
                -SearchIndex $target.SearchIndex `
                -Keyword $AuthorKeyword `
                -Config $config `
                -AccessToken $accessToken `
                -MaxPages $MaxPages

        $results += $result

        Write-Host (
            "[{0}] Retrieved: {1} / Matched: {2} / Excluded: {3}" -f
            $result.Category,
            $result.RetrievedItems,
            $result.MatchedItems,
            $result.ExcludedItems
        )
    }
    catch {
        Write-Host (
            "[{0}] FAILED: {1}" -f
            $target.Label,
            $_.Exception.Message
        )
    }

    Write-Host ""
}

$safeKeyword =
    $AuthorKeyword -replace
    '[\\/:*?"<>|]',
    '_'

$outputPath =
    Join-Path `
        $outputDirectory `
        (
            "author-search-{0}.json" -f
            $safeKeyword
        )

[System.IO.File]::WriteAllText(
    $outputPath,
    (
        $results |
        ConvertTo-Json -Depth 30
    ),
    $utf8Bom
)

Write-Host "=========================================="
Write-Host "Summary"
Write-Host "=========================================="

foreach ($result in $results) {
    Write-Host (
        "{0}: Retrieved={1}, Matched={2}, Excluded={3}, Requests={4}" -f
        $result.Category,
        $result.RetrievedItems,
        $result.MatchedItems,
        $result.ExcludedItems,
        $result.SearchItemsRequests
    )
}

Write-Host ""
Write-Host "Output:"
Write-Host $outputPath
Write-Host ""
Write-Host "Done."
