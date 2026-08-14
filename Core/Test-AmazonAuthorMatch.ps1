function ConvertTo-AmazonAuthorNormalizedText {

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


function Get-AmazonAuthorNameCandidates {

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
        ConvertTo-AmazonAuthorNormalizedText `
            -Text $Name


    if (
        -not [string]::IsNullOrWhiteSpace(
            $normalized
        )
    ) {

        $candidates +=
            $normalized
    }


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
            ConvertTo-AmazonAuthorNormalizedText `
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


function Test-AmazonAuthorMatch {

    param(
        [array]$Contributors,

        [string]$AuthorKeyword
    )


    $keywordCandidates =
        @(
            Get-AmazonAuthorNameCandidates `
                -Name $AuthorKeyword
        )


    foreach (
        $contributor in
        @($Contributors)
    ) {

        $roleType =
            ConvertTo-AmazonAuthorNormalizedText `
                -Text ([string]$contributor.roleType)


        $role =
            ConvertTo-AmazonAuthorNormalizedText `
                -Text ([string]$contributor.role)


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
                Get-AmazonAuthorNameCandidates `
                    -Name ([string]$contributor.name)
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
