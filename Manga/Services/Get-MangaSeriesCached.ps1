# ==========================================
# Manga Series Cache Wrapper
# ==========================================
#
# Purpose:
# - Cache Get-MangaSeries results by seed ASIN
# - Avoid repeated Creators API requests
# - Refresh cache after TTL expires
# - Allow forced refresh when required
#
# The underlying Get-MangaSeries service is not modified.
# ==========================================


function Get-MangaSeriesCached {

    param(
        [Parameter(Mandatory)]
        [string]$SeedASIN,

        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$AccessToken,

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


    # ======================================
    # Cache file path
    # ======================================

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
                (Get-Date) -
                $cacheFile.LastWriteTime


            if (
                $cacheAge.TotalHours -lt
                $CacheHours
            ) {

                $cachedObject =
                    Get-Content `
                        $cachePath `
                        -Raw |
                    ConvertFrom-Json


                if ($cachedObject) {

                    $cachedObject |
                        Add-Member `
                            -NotePropertyName CacheStatus `
                            -NotePropertyValue "Hit" `
                            -Force


                    $cachedObject |
                        Add-Member `
                            -NotePropertyName CachePath `
                            -NotePropertyValue $cachePath `
                            -Force


                    $cachedObject |
                        Add-Member `
                            -NotePropertyName CacheAgeMinutes `
                            -NotePropertyValue (
                                [Math]::Round(
                                    $cacheAge.TotalMinutes,
                                    1
                                )
                            ) `
                            -Force


                    return $cachedObject
                }
            }
        }
        catch {

            Write-Host "Cache read failed. Refreshing from API."
        }
    }


    # ======================================
    # Call original service
    # ======================================

    $result =
        Get-MangaSeries `
            -SeedASIN $seedASIN `
            -Config $Config `
            -AccessToken $AccessToken


    if (-not $result) {

        throw "Manga service returned no result."
    }


    # ======================================
    # Add cache metadata
    # ======================================

    $result |
        Add-Member `
            -NotePropertyName CacheStatus `
            -NotePropertyValue "Miss" `
            -Force


    $result |
        Add-Member `
            -NotePropertyName CachePath `
            -NotePropertyValue $cachePath `
            -Force


    $result |
        Add-Member `
            -NotePropertyName CacheAgeMinutes `
            -NotePropertyValue 0 `
            -Force


    # ======================================
    # Save cache
    # ======================================

    try {

        $utf8Bom =
            New-Object `
                System.Text.UTF8Encoding `
                -ArgumentList $true


        $cacheJson =
            $result |
            ConvertTo-Json -Depth 30


        [System.IO.File]::WriteAllText(
            $cachePath,
            $cacheJson,
            $utf8Bom
        )
    }
    catch {

        Write-Host "Cache write failed."
    }


    return $result
}