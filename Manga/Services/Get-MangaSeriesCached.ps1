function Get-MangaSeriesCached {

    param(
        [Parameter(Mandatory)]
        [string]$SeedASIN,

        [Parameter(Mandatory)]
        $Config,

        [string]$AccessToken = "",

        [string]$CacheDirectory = "",

        [int]$CacheHours = 6,

        [switch]$ForceRefresh
    )


    $seedASIN =
        $SeedASIN.Trim()


    if (
        [string]::IsNullOrWhiteSpace(
            $seedASIN
        )
    ) {
        throw "Seed ASIN is empty."
    }


    # ======================================
    # Resolve cache directory
    # ======================================

    if (
        [string]::IsNullOrWhiteSpace(
            $CacheDirectory
        )
    ) {

        $projectRoot =
            Split-Path `
                (Split-Path $PSScriptRoot -Parent) `
                -Parent


        $CacheDirectory =
            Join-Path `
                $projectRoot `
                "Cache\Manga"
    }


    if (
        -not (
            Test-Path $CacheDirectory
        )
    ) {

        New-Item `
            -ItemType Directory `
            -Path $CacheDirectory `
            -Force |
        Out-Null
    }


    $cachePath =
        Join-Path `
            $CacheDirectory `
            (
                "{0}.json" -f
                $seedASIN
            )


    # ======================================
    # Try cache
    # ======================================

    if (
        -not $ForceRefresh -and
        (Test-Path $cachePath)
    ) {

        try {

            $cacheFile =
                Get-Item $cachePath


            $cacheAge =
                (
                    Get-Date
                ) -
                $cacheFile.LastWriteTime


            if (
                $cacheAge.TotalHours -lt
                $CacheHours
            ) {

                $cachedResult =
                    Get-Content `
                        $cachePath `
                        -Raw |
                    ConvertFrom-Json


                $cachedResult |
                    Add-Member `
                        -NotePropertyName "CacheStatus" `
                        -NotePropertyValue "Hit" `
                        -Force


                $cachedResult |
                    Add-Member `
                        -NotePropertyName "CachePath" `
                        -NotePropertyValue $cachePath `
                        -Force


                $cachedResult |
                    Add-Member `
                        -NotePropertyName "CacheAgeMinutes" `
                        -NotePropertyValue (
                            [Math]::Round(
                                $cacheAge.TotalMinutes,
                                1
                            )
                        ) `
                        -Force


                $cachedResult |
                    Add-Member `
                        -NotePropertyName "CurrentOAuthRequests" `
                        -NotePropertyValue 0 `
                        -Force


                $cachedResult |
                    Add-Member `
                        -NotePropertyName "CurrentCreatorsApiRequests" `
                        -NotePropertyValue 0 `
                        -Force


                return $cachedResult
            }
        }
        catch {

            Write-Host (
                "Failed to read manga cache: {0}" -f
                $_.Exception.Message
            )
        }
    }


    # ======================================
    # Authenticate only on cache miss
    # ======================================

    $oauthRequests =
        0


    if (
        [string]::IsNullOrWhiteSpace(
            $AccessToken
        )
    ) {

        $oauthRequests++


        $AccessToken =
            Get-AmazonAccessToken `
                -Config $Config
    }


    # ======================================
    # Get fresh manga result
    # ======================================

    $result =
        Get-MangaSeries `
            -SeedASIN $seedASIN `
            -Config $Config `
            -AccessToken $AccessToken


    # ======================================
    # Add cache metadata
    # ======================================

    $result |
        Add-Member `
            -NotePropertyName "CacheStatus" `
            -NotePropertyValue "Miss" `
            -Force


    $result |
        Add-Member `
            -NotePropertyName "CachePath" `
            -NotePropertyValue $cachePath `
            -Force


    $result |
        Add-Member `
            -NotePropertyName "CacheAgeMinutes" `
            -NotePropertyValue 0 `
            -Force


    $result |
        Add-Member `
            -NotePropertyName "CurrentOAuthRequests" `
            -NotePropertyValue $oauthRequests `
            -Force


    $result |
        Add-Member `
            -NotePropertyName "CurrentCreatorsApiRequests" `
            -NotePropertyValue $result.CreatorsApiRequests `
            -Force


    # ======================================
    # Save cache
    # ======================================

    try {

        $utf8Bom =
            New-Object `
                System.Text.UTF8Encoding `
                -ArgumentList $true


        $json =
            $result |
            ConvertTo-Json -Depth 30


        [System.IO.File]::WriteAllText(
            $cachePath,
            $json,
            $utf8Bom
        )
    }
    catch {

        Write-Host (
            "Failed to write manga cache: {0}" -f
            $_.Exception.Message
        )
    }


    return $result
}