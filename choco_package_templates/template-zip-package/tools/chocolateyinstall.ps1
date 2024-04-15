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
$fileName = 'NAME_OF_ZIP_FILE.ZIP' ## .7z works here too
$file       = "" ## Use this for Embedded files: Join-Path $toolsDir $fileName
                 ## Use this for files stored on a CIFS share: "\\SHARE_LOCATION\subfolder\$fileName"
                 ## You can also use an INTERNAL web url, like: "https://totallyrealthing.domain.com/$filename"
## You can use the Get-FileHash cmdlet to get the checksums required
## e.g. Get-FileHash -Path path\to\file
$checksum      = '' ## Checksums are always required, whether the file is embedded or not.
$checksumType  = 'sha256' ##default is md5, can also be sha1, sha256 or sha512
$unzipLocation = "$($ENV:SYSTEMDRIVE)\tools\unzippedstuff"

$fileArgs = @{
  packageName     = $env:ChocolateyPackageName
  fileFullPath    = Join-Path $toolsDir $fileName
  fileName        = $fileName
  url             = $file
  checksum        = $checksum
  checksumType    = $checksumType
}

$packageArgs = @{
  packageName     = $env:ChocolateyPackageName
  FileFullPath    = "$toolsDir\\$fileName"
  Destination     = $unzipLocation
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
Get-ChocolateyUnzip @packageArgs ## https://docs.chocolatey.org/en-us/create/functions/install-chocolateyinstallpackage


