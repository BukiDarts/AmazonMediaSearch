param(
    [string]$AuthorKeyword = "村上龍",
    [int]$MaxPages = 3
)

# ==========================================
# Audible Author Search Debug
# ==========================================
#
# Purpose:
# - Search with SearchIndex = All.
# - Use "<author> Audible" as the keyword.
# - Keep only Audible items.
# - Then keep only items whose author matches.
#
# This file does not modify the main app.
# ==========================================


$projectRoot =
    Split-Path $PSScriptRoot -Parent


# ==========================================
# Load project functions
# ==========================================

. "$projectRoot\Core\Get-AmazonAccessToken.ps1"
. "$projectRoot\Core\Invoke-AmazonSearch.ps1"


# ==========================================
# Config
# ==========================================

$configPath =
    Join-Path `
        $projectRoot `
        "config.json"


$outputDirectory =
    Join-Path `
        $PSScriptRoot `
        "Output"


if (
    -not (
        Test-Path $configPath
    )
) {

    throw "config.json not found."
}


if (
    -not (
        Test-Path $outputDirectory
    )
) {

    New-Item `
        -ItemType Directory `
        -Path $outputDirectory `
        -Force |
    Out-Null
}


$config =
    Get-Content `
        $configPath `
        -Raw |
    ConvertFrom-Json


$utf8Bom =
    New-Object `
        System.Text.UTF8Encoding `
        -ArgumentList $true


# ==========================================
# Helpers
# ==========================================

function ConvertTo-AuthorNormalizedText {

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


    $value =
        $Text.Normalize(
            [Text.NormalizationForm]::FormKC
        )


    $value =
        $value -replace
        '[\u3000\s]+',
        ''


    $value =
        $value -replace
        '[,，、]',
        ''


    return (
        $value.
            Trim().
            ToLowerInvariant()
    )
}


function Get-AuthorNameCandidates {

    param(
        [string]$Name
    )


    $candidates =
        @()


    if (
        [string]::IsNullOrWhiteSpace(
            $Name
        )
    ) {

        return @()
    }


    $normalized =
        ConvertTo-AuthorNormalizedText `
            -Text $Name


    if (
        -not [string]::IsNullOrWhiteSpace(
            $normalized
        )
    ) {

        $candidates +=
            $normalized
    }


    # Handle "Given, Family" style names such as "龍, 村上".
    if (
        $Name -match
        '^\s*([^,，]+)\s*[,，]\s*([^,，]+)\s*$'
    ) {

        $reversed =
            (
                "{0}{1}" -f
                $Matches[2],
                $Matches[1]
            )


        $reversedNormalized =
            ConvertTo-AuthorNormalizedText `
                -Text $reversed


        if (
            -not [string]::IsNullOrWhiteSpace(
                $reversedNormalized
            )
        ) {

            $candidates +=
                $reversedNormalized
        }
    }


    return @(
        $candidates |
        Sort-Object -Unique
    )
}


function Get-DebugTitle {

    param(
        $Item
    )


    if (
        $Item.itemInfo -and
        $Item.itemInfo.title
    ) {

        return (
            [string]$Item.itemInfo.title.displayValue
        )
    }


    return ""
}


function Get-DebugContributors {

    param(
        $Item
    )


    $rows =
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

            $rows +=
                [PSCustomObject]@{

                    Name =
                        [string]$contributor.name

                    Role =
                        [string]$contributor.role

                    RoleType =
                        [string]$contributor.roleType
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


    $keywordCandidates =
        @(
            Get-AuthorNameCandidates `
                -Name $AuthorKeyword
        )


    foreach (
        $contributor in
        @($Contributors)
    ) {

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


        if (-not $isAuthorRole) {

            continue
        }


        $nameCandidates =
            @(
                Get-AuthorNameCandidates `
                    -Name ([string]$contributor.Name)
            )


        foreach (
            $keywordCandidate in
            $keywordCandidates
        ) {

            foreach (
                $nameCandidate in
                $nameCandidates
            ) {

                if (
                    $nameCandidate -eq
                    $keywordCandidate
                ) {

                    return $true
                }
            }
        }
    }


    return $false
}


function Test-IsAudibleItem {

    param(
        $Item
    )


    if (
        -not $Item.itemInfo
    ) {

        return $false
    }


    $binding =
        ""


    $productGroup =
        ""


    if (
        $Item.itemInfo.classifications
    ) {

        if (
            $Item.itemInfo.classifications.binding
        ) {

            $binding =
                [string]$Item.itemInfo.classifications.binding.displayValue
        }


        if (
            $Item.itemInfo.classifications.productGroup
        ) {

            $productGroup =
                [string]$Item.itemInfo.classifications.productGroup.displayValue
        }
    }


    $bindingNormalized =
        ConvertTo-AuthorNormalizedText `
            -Text $binding


    $productGroupNormalized =
        ConvertTo-AuthorNormalizedText `
            -Text $productGroup


    return (
        $productGroupNormalized -eq "audible" -or
        $bindingNormalized -match "audible"
    )
}


# ==========================================
# Main
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Audible Author Search Debug"
Write-Host "=========================================="
Write-Host ""


$searchKeyword =
    (
        "{0} Audible" -f
        $AuthorKeyword
    ).Trim()


Write-Host (
    "Author keyword: {0}" -f
    $AuthorKeyword
)


Write-Host (
    "Amazon keyword: {0}" -f
    $searchKeyword
)


Write-Host ""


$accessToken =
    Get-AmazonAccessToken `
        -Config $config


$resources =
    @(
        "itemInfo.title",
        "itemInfo.byLineInfo",
        "itemInfo.classifications",
        "itemInfo.contentInfo",
        "itemInfo.technicalInfo"
    )


$rows =
    @()


$totalResultCount =
    0


$requiredPages =
    1


$requestCount =
    0


$rank =
    0


for (
    $page = 1;
    $page -le $MaxPages;
    $page++
) {

    if (
        $page -gt $requiredPages
    ) {

        break
    }


    if (
        $page -gt 1
    ) {

        Start-Sleep `
            -Milliseconds 1100
    }


    Write-Host (
        "Requesting page {0}..." -f
        $page
    )


    $response =
        Invoke-AmazonSearch `
            -Keyword $searchKeyword `
            -SearchIndex "All" `
            -Resources $resources `
            -Config $config `
            -AccessToken $accessToken `
            -ItemCount 10 `
            -ItemPage $page


    $requestCount++


    if (
        $response.searchResult -and
        $null -ne
        $response.searchResult.totalResultCount
    ) {

        $totalResultCount =
            [int]$response.searchResult.totalResultCount


        $requiredPages =
            [math]::Ceiling(
                $totalResultCount / 10
            )


        if (
            $requiredPages -gt $MaxPages
        ) {

            $requiredPages =
                $MaxPages
        }
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


    if (
        $items.Count -eq 0
    ) {

        break
    }


    foreach (
        $item in $items
    ) {

        $rank++


        $contributors =
            @(
                Get-DebugContributors `
                    -Item $item
            )


        $isAudible =
            Test-IsAudibleItem `
                -Item $item


        $authorMatch =
            $false


        if ($isAudible) {

            $authorMatch =
                Test-AuthorMatch `
                    -Contributors $contributors `
                    -AuthorKeyword $AuthorKeyword
        }


        $binding =
            ""


        $productGroup =
            ""


        if (
            $item.itemInfo -and
            $item.itemInfo.classifications
        ) {

            if (
                $item.itemInfo.classifications.binding
            ) {

                $binding =
                    [string]$item.itemInfo.classifications.binding.displayValue
            }


            if (
                $item.itemInfo.classifications.productGroup
            ) {

                $productGroup =
                    [string]$item.itemInfo.classifications.productGroup.displayValue
            }
        }


        $rows +=
            [PSCustomObject]@{

                SearchRank =
                    $rank

                ASIN =
                    [string]$item.asin

                Title =
                    (
                        Get-DebugTitle `
                            -Item $item
                    )

                IsAudible =
                    $isAudible

                AuthorMatch =
                    $authorMatch

                Binding =
                    $binding

                ProductGroup =
                    $productGroup

                Contributors =
                    $contributors

                DetailPageURL =
                    [string]$item.detailPageURL
            }
    }
}


$audibleRows =
    @(
        $rows |
        Where-Object {
            $_.IsAudible -eq $true
        }
    )


$matchedRows =
    @(
        $audibleRows |
        Where-Object {
            $_.AuthorMatch -eq $true
        }
    )


$excludedAudibleRows =
    @(
        $audibleRows |
        Where-Object {
            $_.AuthorMatch -ne $true
        }
    )


$nonAudibleRows =
    @(
        $rows |
        Where-Object {
            $_.IsAudible -ne $true
        }
    )


$result =
    [PSCustomObject]@{

        Category =
            "Audible"

        SearchIndex =
            "All"

        AuthorKeyword =
            $AuthorKeyword

        AmazonKeyword =
            $searchKeyword

        TotalResultCount =
            $totalResultCount

        RetrievedItems =
            $rows.Count

        AudibleItems =
            $audibleRows.Count

        MatchedItems =
            $matchedRows.Count

        ExcludedAudibleItems =
            $excludedAudibleRows.Count

        NonAudibleItems =
            $nonAudibleRows.Count

        SearchItemsRequests =
            $requestCount

        Matched =
            $matchedRows

        ExcludedAudible =
            $excludedAudibleRows

        NonAudible =
            $nonAudibleRows

        AllItems =
            $rows
    }


# ==========================================
# Save JSON
# ==========================================

$safeKeyword =
    $AuthorKeyword -replace
    '[\\/:*?"<>|]',
    '_'


$outputPath =
    Join-Path `
        $outputDirectory `
        (
            "author-search-audible-{0}.json" -f
            $safeKeyword
        )


[System.IO.File]::WriteAllText(
    $outputPath,
    (
        $result |
        ConvertTo-Json -Depth 30
    ),
    $utf8Bom
)


# ==========================================
# Console summary
# ==========================================

Write-Host ""
Write-Host "=========================================="
Write-Host "Summary"
Write-Host "=========================================="

Write-Host (
    "Retrieved: {0}" -f
    $result.RetrievedItems
)

Write-Host (
    "Audible items: {0}" -f
    $result.AudibleItems
)

Write-Host (
    "Author matched: {0}" -f
    $result.MatchedItems
)

Write-Host (
    "Audible but author excluded: {0}" -f
    $result.ExcludedAudibleItems
)

Write-Host (
    "Non-Audible excluded: {0}" -f
    $result.NonAudibleItems
)

Write-Host (
    "Requests: {0}" -f
    $result.SearchItemsRequests
)

Write-Host ""
Write-Host "Output:"
Write-Host $outputPath
Write-Host ""
Write-Host "Done."
