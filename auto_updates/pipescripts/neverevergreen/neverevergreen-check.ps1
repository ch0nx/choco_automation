<#=
.Synopsis
  Compares file versions from Evergreen/Nevergreen source to our current package versions
.DESCRIPTION
  Uses modules from choco-auto-packaging to convert and compare file/nuspec versions and output results
  in a way that causes ADO pipelines to register variables
.PARAMETER RootDir
  Working directory from the runner job, should contain our repository so we can import modules from it
.PARAMETER PackagePath
  Directory that contains source code for all choco packages
.PARAMETER Package
  JSON string containing package information

.EXAMPLE
neverevergreen-check.ps1 -RootDir 'C:\azp\agent\_work\9\s' -PackagePath 'C:\azp\agent\_work\9\s\packages' `
  -PackageName 'citrix-workspace' -GreenName 'CitrixWorkspaceApp' -BinaryType 'exe' `
  -BinaryArch 'x64' -BinaryStream 'LTSR'

.INPUTS
System.String

.OUTPUTS
System.String
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification='No other way to use this access token from pipeline')]
param(
  [Parameter(Mandatory = $true)][String]$RootDir,
  [Parameter(Mandatory = $true)][String]$Package,
  [Parameter(Mandatory = $true)][String]$PackagePath
)
If ($PSBoundParameters['Debug']) {
  $DebugPreference = 'Continue'
}
try {
  $PackageInfo = $Package | ConvertFrom-JSON
} catch {
  throw "##vso[task.logissue type=Error]Unable to convert Package parameter from JSON: $($_ | Out-String)"
  Write-Output "##vso[task.complete result=Failed;]"
}
if ($packageInfo.SkipDeletion) {
  $skipDeletion = [System.Convert]::ToBoolean($packageInfo.SkipDeletion)
} else {
  $skipDeletion = $false
}
try {
  $modules = @('Evergreen','Nevergreen','choco-auto-packaging')
  foreach ($module in $modules) {
    Import-Module -Name $module -Force
  }
} catch {
  Write-Output "##vso[task.logissue type=error]Unable to install/import $module module: $($_ | select-object * | Out-String)"
  Write-Output "##vso[task.complete result=Failed;]"
  return
}
# To support custom apps on internal shares, a custom query method is used here instead of the (N|)Evergreen checks
if ($PackageInfo.CustomMethod -eq 'Share') {
  try {
    if ($env:SHARE_PASS.GetType().Name -ne 'SecureString') {
      $secpass = $env:SHARE_PASS | ConvertTo-SecureString -AsPlainText -Force
    } else {
      $secpass = $env:SHARE_PASS
    }
    $creds = New-Object System.Management.Automation.PSCredential($env:SHARE_USER, $secpass)
    $packageQuery = Get-AppFromShare -SharePath $PackageInfo.CustomSharePath -FileName $PackageInfo.CustomFileName -Credential $creds
    $destinationPath = Join-Path $pwd.path $PackageInfo.CustomFileName
  } catch {
    Write-Output "##vso[task.logissue type=warning]Custom method specified but received error on query: $($_ | Out-String)"
    return
  }
} else {
  # Get-EvergreenApp returns an error if a package doesnt exist, so we can query nevergreen for it instead
  # once an error is thrown
  try {
    $packageQuery = Get-EvergreenApp $PackageInfo.GreenName -ErrorAction 'Stop'
  } catch {
    Write-Output "Evergreen check failed for $($PackageInfo.GreenName), checking Nevergreen"
    $packageQuery = Get-NevergreenApp $PackageInfo.GreenName
  }
}
if (!$packageQuery){
  Write-Output "##vso[task.logissue type=error]No package info found for $($PackageInfo.PackageName)"
  Write-Output "##vso[task.complete result=Failed;]"
  return
}
Write-Output "Packages returned for $($PackageInfo.PackageName):"
$packageQuery | Out-String
# Depending on the properties returned from the Evergreen API, different filtering options are available.
$packageMembers = $packageQuery | Get-Member -MemberType 'NoteProperty' | Select-Object -expand Name
if ($packageMembers -contains 'Type' -and $PackageInfo.BinaryType){
  Write-Output "Filtering for BinaryType"
  $packageQuery = $packageQuery | Where-Object {$_.Type -eq $PackageInfo.BinaryType}
  Write-Output "New value:"
  $packageQuery
}
if ($packageMembers -notcontains 'Type' -and $PackageInfo.BinaryType){
  Write-Output "Filtering URI for BinaryType: '.*$($PackageInfo.BinaryType)`$'"
  $packageQuery = $packageQuery | Where-Object {$_.URI -match ".*$($PackageInfo.BinaryType)`$"}
  Write-Output "New value:"
  $packageQuery
}
if ($packageMembers -contains 'Stream' -and $PackageInfo.Stream){
  Write-Output "Filtering for Stream on API property 'Stream'"
  $packageQuery = $packageQuery | Where-Object {$_.Stream -eq $PackageInfo.Stream}
  Write-Output "New value:"
  $packageQuery
}
if ($packageMembers -contains 'Channel' -and $PackageInfo.Stream){
  Write-Output "Filtering for Stream on API property 'Channel'"
  $packageQuery = $packageQuery | Where-Object {$_.Channel -eq $PackageInfo.Stream}
  Write-Output "New value:"
  $packageQuery
}
if ($packageMembers -contains 'Ring' -and $PackageInfo.Stream){
  Write-Output "Filtering for Stream on API property 'Ring'"
  $packageQuery = $packageQuery | Where-Object {$_.Ring -eq $PackageInfo.Stream}
  Write-Output "New value:"
  $packageQuery
}
if ($packageMembers -contains 'Release' -and $PackageInfo.Release){
  Write-Output "Filtering for Release"
  $packageQuery = $packageQuery | Where-Object {$_.Release -eq $PackageInfo.Release}
  Write-Output "New value:"
  $packageQuery
}
if ($packageMembers -contains 'Language' -and $PackageInfo.Language){
  Write-Output "Filtering for Language"
  $packageQuery = $packageQuery | Where-Object {$_.Language -eq $PackageInfo.Language}
  Write-Output "New value:"
  $packageQuery
}
if ($packageMembers -contains 'Architecture' -and $PackageInfo.BinaryArch){
  $queryTemp = $packageQuery
  $architectures = $PackageInfo.BinaryArch -split ','
  foreach ($arch in $architectures) {
    Write-Output "Filtering for Architecture: $arch"
    if ($arch -like '*64*' -and $architectures.Count -gt 1) {
      Write-Output "Detected multi architecture arguments - $arch results for $($PackageInfo.PackageName) below:"
      $packageQuery64 = $queryTemp | Where-Object {$_.Architecture -eq $arch}
      if ($packageQuery64.count -gt 1) {
        Write-Output "##vso[task.logissue type=error]More than one $arch result for $($PackageInfo.PackageName) using provided filters: $($packageQuery | out-string)"
        Write-Output "##vso[task.setvariable variable=QuerySucceeded]$false"
        return
      } elseif (!$packageQuery64){
        Write-Output "No $arch package info found matching filters for $($PackageInfo.PackageName)"
        Write-Output "##vso[task.setvariable variable=QuerySucceeded]$false"
        return
      }
      $packageQuery64
    } else {
      $packageQuery = $queryTemp | Where-Object {$_.Architecture -eq $arch}
    }
  }
  Write-Output "New value:"
  $packageQuery
}
if ($packageQuery.count -gt 1 -and $PackageInfo.UseLatest){
  Write-Output "There are still multiple packages using the current parameters, using the most recent version due to UseLatest being specified"
  $packageQuery = $packageQuery | Sort-Object -Descending -Property 'Version' | Select-Object -First 1
  Write-Output "New value:"
  $packageQuery
}
if ($packageQuery.count -gt 1) {
  Write-Output "##vso[task.logissue type=error]More than one result for $($PackageInfo.PackageName) using provided filters: $($packageQuery | out-string)"
  Write-Output "##vso[task.complete result=Failed;]"
  return
} elseif (!$packageQuery){
  Write-Output "##vso[task.logissue type=error]No package info found matching filters for $($PackageInfo.PackageName)"
  Write-Output "##vso[task.complete result=Failed;]"
  return
}
if ($PackageInfo.VersionTransform) {
  Write-Output "Version Transform Specified"
  try {
    $pattern = $PackageInfo.VersionTransform.split(';')[0]
    $replace = $PackageInfo.VersionTransform.split(';')[1]
    Write-Output "Pattern specified: $pattern"
    Write-Output "Replacement string specified: $replace"
    $newVersion = $packageQuery.Version -replace $pattern,$replace
    Write-Output "Original version string: $($packageQuery.Version)"
    Write-Output "New Version string: $newVersion"
    $packageQuery.Version = $newVersion
  } catch {
    Write-Output "##vso[task.logissue type=error]Error performing version transform: $($_ | Out-String)"
    Write-Output "##vso[task.complete result=Failed;]"
    return
  }
  if ($packageQuery64) {
    try {
      Write-Output "Version transform specified alongside multi-architecture queries, beginning x64 transform"
      $pattern = $PackageInfo.VersionTransform.split(';')[0]
      $replace = $PackageInfo.VersionTransform.split(';')[1]
      Write-Output "Pattern specified: $pattern"
      Write-Output "Replacement string specified: $replace"
      $newVersion64 = $packageQuery64.Version -replace $pattern,$replace
      Write-Output "Original version string: $($packageQuery64.Version)"
      Write-Output "New Version string: $newVersion64"
      $packageQuery64.Version = $newVersion64
    } catch {
      Write-Output "##vso[task.logissue type=error]Error performing version transform: $($_ | Out-String)"
      Write-Output "##vso[task.complete result=Failed;]"
      return
    }
  }
}
if ($packageQuery.uri -like '*%20*') {
  $packageQuery.uri = $packageQuery.uri -replace '%20',''
}
if ($packageQuery64 -and $packageQuery64.uri -like '*%20*') {
  $packageQuery64.uri = $packageQuery64.uri -replace '%20',''
}
if ($PackageInfo.CustomFileName) {
  $FileName = $PackageInfo.CustomFileName
  Write-Output "Setting FileName to $FileName because $($PackageInfo.CustomFileName) is not null"
} elseif ($packageQuery.LocalFileName) {
  $FileName = $packageQuery.LocalFileName
  Write-Output "Setting FileName to $FileName because $($packageQuery.LocalFileName) is not null"
  $destinationPath = $packageQuery.LocalFilePath
  Write-Output "Setting destinationPath to $destinationPath because $($packageQuery.LocalFileName) is not null"
} elseif ($packageQuery.URI) {
  $FileName = ($packageQuery.URI -split '/')[-1] -replace '\s',''
  Write-Output "Setting FileName to $FileName because $($packageQuery.URI) is not null"
  if ($packageQuery64) {
    $FileName64 = ($packageQuery64.URI -split '/')[-1] -replace '\s',''
    Write-Output "Setting FileName64 to $FileName64 because $($packageQuery64.URI) is not null"
  }
} else {
  Write-Output "##vso[task.logissue type=warning]Unable to determine filename, will not progress further"
  return
}
if (!$destinationPath) {
  $destinationPath = Join-Path $pwd.path $FileName
  Write-Output "Setting destinationPath to $destinationPath because it is not already set"
  if ($packageQuery64) {
    $destinationPath64 = Join-Path $pwd.path $FileName64
    Write-Output "Setting destinationPath64 to $destinationPath64 because it is not already set"
  }
}
# Nevergreen doesnt return hashes so we have to get them here instead
# SkipDeletion check is here because some packages require authenticated downloads and
# get downloaded during their query
if (!$skipDeletion -and (Test-Path $destinationPath)) {
  Write-Output "File found at $destinationPath and should have been cleaned up, removing before proceeding."
  Remove-Item $destinationPath -force -confirm:$false
}
if (!$packageQuery.Hash) {
  Write-Output "Missing filehash for $($PackageInfo.PackageName), attempting to download file from '$($packageQuery.URI)' and obtain that way"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
  try {
    Invoke-WebRequest -Uri $packageQuery.URI -OutFile $destinationPath -TimeoutSec 120
  } catch {
    Write-Output "Timeout occurred downloading file for $($PackageInfo.PackageName) from $($packageQuery.URI), attempting alternate method"
    [System.Reflection.Assembly]::LoadWithPartialName('System.Net.Http') | Out-Null
    $httpClient = New-Object System.Net.Http.HttpClient
    $response = $httpClient.GetAsync($packageQuery.URI).Result
    if ($response.IsSuccessStatusCode) {
      $stream = $response.Content.ReadAsStreamAsync().Result
      $fileStream = New-Object System.IO.FileStream($destinationPath, [System.IO.FileMode]::Create)
      $stream.CopyTo($fileStream)
      $fileStream.Dispose()
      $stream.Dispose()
      Write-Output "File downloaded successfully"
    } else {
      Write-Output "##vso[task.logissue type=error]Failed to download file: $($response.ReasonPhrase)"
      Write-Output "##vso[task.complete result=Failed;]"
      return
    }
  }
  if (!(Test-Path $destinationPath)) {
    Write-Output "##vso[task.logissue type=error]File was not able to be downloaded for $($PackageInfo.PackageName)"
    Write-Output "##vso[task.complete result=Failed;]"
    return
  }
  Write-Output "File for $($PackageInfo.PackageName) downloaded to $destinationPath"
  $FileHash = Get-FileHash $destinationPath | Select-Object -Expand Hash
  $packageQuery | Add-Member -MemberType NoteProperty -Name Hash -Value $FileHash
  if ($packageQuery64) {
    Write-Output "Getting x64 filehash for $($PackageInfo.PackageName), attempting to download file and obtain that way"
    try {
      Invoke-WebRequest -Uri $packageQuery64.URI -OutFile $destinationPath64 -TimeoutSec 120
    } catch {
      Write-Output "Timeout occurred downloading x64 file for $($PackageInfo.PackageName) from $($packageQuery.URI), attempting alternate method"
      [System.Reflection.Assembly]::LoadWithPartialName('System.Net.Http') | Out-Null
      $httpClient = New-Object System.Net.Http.HttpClient
      $response = $httpClient.GetAsync($packageQuery64.URI).Result
      if ($response.IsSuccessStatusCode) {
        $stream = $response.Content.ReadAsStreamAsync().Result
        $fileStream = New-Object System.IO.FileStream($destinationPath64, [System.IO.FileMode]::Create)
        $stream.CopyTo($fileStream)
        $fileStream.Dispose()
        $stream.Dispose()
        Write-Output "File downloaded successfully"
      } else {
        Write-Output "##vso[task.logissue type=error]Failed to download x64 file: $($response.ReasonPhrase)"
        Write-Output "##vso[task.complete result=Failed;]"
        return
      }
    }
    if (!(Test-Path $destinationPath64)) {
      Write-Output "##vso[task.logissue type=error]x64 File was not able to be downloaded for $($PackageInfo.PackageName)"
      Write-Output "##vso[task.complete result=Failed;]"
      return
    }
    $FileHash64 = Get-FileHash $destinationPath64 | Select-Object -Expand Hash
    $packageQuery64 | Add-Member -MemberType NoteProperty -Name Hash -Value $FileHash64
  }
}
Write-Output $("Comparing version using:`nPackagePath: $packagePath`nChocoPackageName: $($PackageInfo.PackageName)`nFileVersion: $($packageQuery.Version)" +
  "`nFileHash: $($packageQuery.Hash)`nCustomZip: $PackageInfo.CustomZip")
$versionComp = Compare-EvergreenVersion -PackagePath $PackagePath `
  -ChocoPackageName $PackageInfo.PackageName `
  -FileVersion $packageQuery.Version `
  -FileHash $packageQuery.Hash `
  -CustomZip $PackageInfo.CustomZip
if (!$versionComp.Result) {
  Write-Output "Choco package version $($versionComp.nuspecVersion) is not older than converted version: $($versionComp.ConvertedVersion)"
  # Remove the file here if we dont need to keep it for the blob upload step
  if ((Test-Path $destinationPath) -and !$skipDeletion){
    Remove-Item $destinationPath -force
  }
  if ($destinationPath64 -and (Test-Path $destinationPath64) -and !$skipDeletion){
    Remove-Item $destinationPath64 -force
  }
  return
}
Write-Output "Choco package version $($versionComp.nuspecVersion) is older than converted version: $($versionComp.ConvertedVersion), new package required!"

Write-Output "##vso[task.setvariable variable=FileURI]$($packageQuery.URI)"
Write-Output "##vso[task.setvariable variable=FileName]$($FileName)"
Write-Output "##vso[task.setvariable variable=FileVersion]$($versionComp.ConvertedVersion)"
Write-Output "##vso[task.setvariable variable=FileHash]$($packageQuery.Hash)"
Write-Output "##vso[task.setvariable variable=FilePath]$($destinationPath)"
Write-Output "##vso[task.setvariable variable=ChocoPackagePath]$($versionComp.ChocoPackagePath)"
if ($packageQuery64) {
  Write-Output "##vso[task.setvariable variable=FileURI64]$($packageQuery64.URI)"
  Write-Output "##vso[task.setvariable variable=FileName64]$($FileName64)"
  Write-Output "##vso[task.setvariable variable=FileHash64]$($packageQuery64.Hash)"
  Write-Output "##vso[task.setvariable variable=FilePath64]$($destinationPath64)"
}