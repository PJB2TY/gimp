#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if (-not $GITLAB_CI)
  {
    # Make the script work locally
    if (-not (Test-Path build\windows) -and -not (Test-Path 2_build-gimp-msys2.ps1 -Type Leaf) -or $PSScriptRoot -notlike "*build\windows*")
      {
        Write-Host '(ERROR): Script called from wrong dir. Please, read: https://developer.gimp.org/core/setup/build/windows/' -ForegroundColor Red
        exit 1
      }
    elseif (Test-Path 2_build-gimp-msys2.ps1 -Type Leaf)
      {
        Set-Location ..\..
      }

    git submodule update --init
  }


# Install the required (pre-built) packages for babl, GEGL and GIMP (again)
Invoke-Expression ((Get-Content build\windows\1_build-deps-msys2.ps1 | Select-String 'MSYS2_PREFIX =' -Context 0,15) -replace '> ','')

if ($GITLAB_CI)
  {
    Invoke-Expression ((Get-Content build\windows\1_build-deps-msys2.ps1 | Select-String 'deps_install\[' -Context 0,6) -replace '> ','')
  }


# Prepare env
if (-not $GITLAB_CI)
  {
    if (-not $GIMP_PREFIX)
      {
        #FIXME:'gimpenv' have buggy code about Windows paths. See: https://gitlab.gnome.org/GNOME/gimp/-/issues/12284
        $GIMP_PREFIX = "$PWD\..\_install".Replace('\', '/')
      }

    Invoke-Expression ((Get-Content .gitlab-ci.yml | Select-String 'win_environ\[' -Context 0,5) -replace '> ','' -replace '- ','')
  }


# Build GIMP
Write-Output "$([char]27)[0Ksection_start:$(Get-Date -UFormat %s -Millisecond 0):gimp_build[collapsed=true]$([char]13)$([char]27)[0KBuilding GIMP"
if (-not (Test-Path _build\build.ninja -Type Leaf))
  {
    #FIXME: g-ir-doc is broken. See: https://gitlab.gnome.org/GNOME/gimp/-/issues/11200
    #There is no GJS for Windows. See: https://gitlab.gnome.org/GNOME/gimp/-/issues/5891
    meson setup _build -Dprefix="$GIMP_PREFIX" -Djavascript=disabled `
                       -Ddirectx-sdk-dir="$MSYS2_PREFIX/$MSYSTEM_PREFIX" -Denable-default-bin=enabled `
                       -Dbuild-id='org.gimp.GIMP_official' $INSTALLER_OPTION $STORE_OPTION
  }
Set-Location _build
ninja
ccache --show-stats
Write-Output "$([char]27)[0Ksection_end:$(Get-Date -UFormat %s -Millisecond 0):gimp_build$([char]13)$([char]27)[0K"


# Bundle GIMP
Write-Output "$([char]27)[0Ksection_start:$(Get-Date -UFormat %s -Millisecond 0):gimp_bundle[collapsed=true]$([char]13)$([char]27)[0KCreating bundle"
ninja install | Out-File ninja_install.log
if ("$LASTEXITCODE" -gt '0' -or "$?" -eq 'False')
  {
    ## We need to manually check failures in pre-7.4 PS
    Get-Content ninja_install.log
    exit 1
  }
Remove-Item ninja_install.log
Set-Location ..
Write-Output "$([char]27)[0Ksection_end:$(Get-Date -UFormat %s -Millisecond 0):gimp_bundle$([char]13)$([char]27)[0K"