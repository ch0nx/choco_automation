## IMPORTANT: Before releasing this package, remove all prestructured comments from this file.  To do it automatically,
## copy/paste the next 2 lines (without the ##) into PowerShell to remove all comments from this file.  It will remove the double hashed comments
## and will leave the single hashed comments alone:
##   $f='c:\path\to\thisFile.ps1'
##   gc $f | ? {$_ -notmatch "^\s*##"} | % {$_ -replace '(^.*?)\s*?[^``]##.*','$1'} | Out-File $f+".~" -en utf8; mv -fo $f+".~" $f

## 1. Follow the documentation below to learn how to create a package for the package type you are creating.
## 2. In Chocolatey scripts, ALWAYS use absolute paths - $toolsDir gets you to the package's tools directory.
$ErrorActionPreference = 'Stop' ## stop on all errors
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
## Internal packages (organizations) or software that has redistribution rights (community repo)
## - Use `Install-ChocolateyInstallPackage` instead of `Install-ChocolateyPackage`
##   and put the binaries directly into the tools folder (we call it embedding)
$fileName = 'NAME_OF_INSTALLER_FILE.EXE'
$fileType   = 'EXE'
## Name of the software, used for looking up the installation state and uninstall string in the registry. Accepts wildcard inputs, ex "software name*"
$softwareName = "SOFTWARE_NAME_HERE"
## Version of the software, used for installation state comparisons to determine if the package installer needs to be called or not. Should match the uninstall key in registry.
$softwareVersion = '1.2.3.4'
## ONLY USE INTERNAL URLS, EXTERNAL URLS CAN POSE DANGERS TO OUR INFRASTRUCTURE!
$file       = "" ## Use this for Embedded files: Join-Path $toolsDir $fileName
                 ## Use this for files stored on a CIFS share: "\\SHARE_LOCATION\subfolder\$fileName"
                 ## You can also use an INTERNAL web url, like: "https://totallyrealthing.domain.com/$filename"
## You can use the Get-FileHash cmdlet to get the checksums required
## e.g. Get-FileHash -Path path\to\file
$checksum      = '' ## Checksums are always required, whether the file is embedded or not.
$checksumType  = 'sha256' ##default is md5, can also be sha1, sha256 or sha512

# Version checking for name/version, if the software is already installed, this package will be marked as installed.
## If this is the case, you may need to create a chocolateyuninstall.ps1 script that locates the installed software and uninstalls it (see template).
[array]$installCheck = Get-UninstallRegistryKey -SoftwareName $softwareName -WarningAction 'SilentlyContinue'
if ($installCheck.Count -gt 1) {
  Write-Output "Multiple matches for $softwareName found:"
  $installCheck | ForEach-Object {Write-Warning "$($_.DisplayName)-$($_.DisplayVersion)"}
  foreach ($version in $installCheck.DisplayVersion) {
    if ([System.Version]$version -ge [System.Version]$softwareVersion) {
      Write-Output "Software named $softwareName is already installed with version $($version), which is equal or higher than $($softwareVersion). Nothing to do!"
      return
    }
  }
  Write-Warning "No matches for $softwareName are equal or higher than $softwareVersion, this could cause an issue with installation of this version."
} elseif ($installCheck -and [System.Version]$installCheck.DisplayVersion -ge [System.Version]$softwareVersion){
  Write-Output "Software is already installed with version $($installCheck.DisplayVersion), which is greater than or equal to $($softwareVersion), nothing to do!"
  return
} elseif ($installCheck -and [System.Version]$installCheck.DisplayVersion -lt [System.Version]$softwareVersion) {
  Write-Warning "Software named $softwareName is already installed with a lower version $($installCheck.DisplayVersion), will attempt to install in this choco package."
}

$fileArgs = @{
  packageName     = $env:ChocolateyPackageName
  fileFullPath    = Join-Path $toolsDir $fileName
  fileName        = $fileName
  url             = $file
  checksum        = $checksum
  checksumType    = $checksumType
}

$packageArgs = @{
  fileType      = $fileType
  file          = Join-Path $toolsDir $fileName
  packageName   = $env:ChocolateyPackageName
  softwareName  = $softwareName ##part or all of the Display Name as you see it in Programs and Features. It should be enough to be unique
  ## Uncomment matching EXE type (sorted by most to least common)
  ##silentArgs   = '/S'           ## NSIS
  ##silentArgs   = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' ## Inno Setup
  ##silentArgs   = '/s'           ## InstallShield
  ##silentArgs   = '/s /v"/qn"'   ## InstallShield with MSI
  ##silentArgs   = '/s'           ## Wise InstallMaster
  ##silentArgs   = '-s'           ## Squirrel
  ##silentArgs   = '-q'           ## Install4j
  ##silentArgs   = '-s'           ## Ghost
  ## Note that some installers, in addition to the silentArgs above, may also need assistance of AHK to achieve silence.
  ##silentArgs   = ''             ## none; make silent with input macro script like AutoHotKey (AHK)
                                 ##       https://community.chocolatey.org/packages/autohotkey.portable
  validExitCodes= @(0) ##please insert other valid exit codes here
}

## Get-ChocoFile is part of the 'filefetch.extension' package, and needs to be listed as a dependency for file validation if used
## It is able to be used to download and verify checksums on web, smb, and embedded files if necessary, but nearly all packages
## are being backed by azure blob storage, so we don't need the dependency by default!
## Get-ChocoFile @fileArgs

## Get-ChocolateyWebFile can be used for web and smb based file storage with the proper syntax
## https://docs.chocolatey.org/en-us/create/functions/get-chocolateywebfile
Get-ChocolateyWebFile @fileargs

## Main helper functions - these have error handling tucked into them already
## see https://docs.chocolatey.org/en-us/create/functions

## Installing the chocolatey package itself is required, add any additional checks and calls above this line.
Install-ChocolateyInstallPackage @packageArgs ## https://docs.chocolatey.org/en-us/create/functions/install-chocolateyinstallpackage


