<#
.Synopsis
  Builds and synchronizes chocolatey packages in the repository
.DESCRIPTION
  Compares 'choco list' output for the specified repository with the current versions of the nuspec files
  currently listed in the 'packages' folder.  Any nuspecs with higher versions than that of the most recent
  version available in the list output will be built and pushed to the nuget feed.
.EXAMPLE
  TODO
#>

param(
    [Parameter(Mandatory = $true)][String]$PackagePath,
    [Parameter(Mandatory = $true)][String]$PackageList,
    [Parameter(Mandatory = $true)][int]$RetainCount,
    [Parameter(Mandatory = $true)][int]$RetainMonths,
    [Parameter(Mandatory = $true)][String]$ArtifactoryToken,
    [Parameter(Mandatory = $false)][String]$Exclusions,
    [Parameter(Mandatory = $true)][String]$OutputPath,
    [Parameter(Mandatory = $true)][String]$BlobURIBase,
    [Parameter(Mandatory = $true)][String]$TenantID,
    [Parameter(Mandatory = $true)][String]$AppID,
    [Parameter(Mandatory = $true)][String]$SubscriptionName,
    [Parameter(Mandatory = $true)][String]$StorageAcctName,
    [Parameter(Mandatory = $true)][String]$StorageContainer
)
try {
  Import-Module 'choco-auto-packaging' -Force
} catch {
  Write-Output "##vso[task.logissue type=Error]Unable to import modules: $($_ | Out-String)"
  Write-Output "##vso[task.complete result=Failed;]"
  return
}
$chocoPath = 'C:\ProgramData\chocolatey\choco.exe'
if (!(test-path $PackagePath)) {
  throw "Package code repo path: $PackagePath is not accessible, aborting"
  return
} elseif (!(test-path $chocoPath)) {
  throw "Chocolatey executable not available at $chocoPath"
  return
}
if ($retainCount -lt 1) {
  throw "Invalid value for retainCount, must be 1 or more."
  return
}
if ($RetainMonths -lt 1) {
  throw "Invalid value for retainMonths, must be 1 or more"
  return
}
# Create the output directory for the built packages
if (test-path $OutputPath){
  Remove-Item $OutputPath -recurse -force
}
try {
  New-Item -Path $OutputPath -ItemType Directory | out-null
} catch {
  throw "Unable to create directory at $OutputPath"
  return
}

$packageObject = [pscustomobject]@{
  PackageName = $NULL
  VersionString = $NULL
  VersionDict = $NULL
}
# Create array of objects that includes the original package name and version string, as well as the
# converted version dictionary object
$packageArr = foreach ($package in $PackageList -split ';') {
  try {
    Write-Debug "Converting version to semver for $package"
    $tmpObj = $packageObject | Select-Object *
    $tmpObj.packageName = ($package -split ' ')[0]
    $tmpObj.VersionString = ($package -split ' ')[1]
    $tmpObj.VersionDict = $tmpObj.VersionString | Convert-VersionToDict
  } catch {
    throw "Error checking $($package): $($_ | Out-String)"
    return
  }
  $tmpObj
}
$pkgExclusions = $exclusions -split ','
$packageNames = $packageArr.PackageName | Where-Object {$pkgExclusions -notcontains $_} | Sort-Object -Unique -CaseSensitive
$allSorted = foreach ($packageName in $packageNames) {
  Write-Debug "Checking $packageName"
  # According to semver documentation, build metadata should not be used when
  # determining precedence.
  $tmpList = $packageArr | Where-Object {$_.PackageName -ceq $packageName}
  $tmpSorted = New-Object System.Collections.ArrayList
  $tmpSorted.Add($tmpList[0]) | Out-Null
  if ($tmpList.Count -eq 1) {
    Write-Debug "Only one item for $packagename"
    $tmpSorted
    continue
  }
  foreach ($pkg in $tmpList[1..($tmplist.Count - 1)]) {
    $indexFound = $FALSE
    for ($i=0;$i -lt $tmpSorted.Count; $i++) {
      Write-Debug "Comparing for $($packageName): $($pkg.VersionString)`n$($tmpSorted[$i].VersionString)"
      if (Compare-Version $pkg.VersionDict $tmpSorted[$i].VersionDict) {
        Write-Debug "Adding $($pkg | out-string) at index $i"
        $tmpSorted.Insert($i, $pkg) | Out-Null
        $indexFound = $TRUE
        break
      }
    }
    if (!$indexFound) {
      Write-Debug "Adding $($pkg | out-string) to end of list"
      $tmpSorted.Add($pkg) | Out-Null
    }
  }
  $tmpSorted
}
# Get the most recent version of all packages in list since Artifactory cannot be trusted to provide the most recent version only
$currentPackageArr = foreach ($packageName in $packageNames) {
  $allSorted | Where-Object {$_.PackageName -ceq $packageName} | Select-Object -first 1
}

# Parse current set of nuspec files and then build and add to push directory
$nuspecList = Get-ChildItem $PackagePath -File -Recurse -include *.nuspec -exclude *template*
Write-Output "$($nuspecList.count) nuspecs in list"
foreach ($nuspec in $nuspecList) {
  $buildRequired = $FALSE
  $nuspecData = New-Object -TypeName XML
  $nuspecData.Load($nuspec.FullName)
  $currentPackage = $currentPackageArr | Where-Object{$_.PackageName -ceq $nuspecData.package.metadata.id}
  Write-Debug "currentPackage:
  Name: $($currentpackage.PackageName)
  Version: $($currentpackage.VersionString)"
  Write-Debug "nuspec version: $($nuspecData.package.metadata.version)"
  if (!$currentPackage){
    $buildrequired = $TRUE
  } else {
    Write-Debug "Comparing $($currentPackage.VersionString) to $($nuspecData.package.metadata.version) for $($nuspec.name)"
    $currentPkgVer = $currentPackage.VersionString | Convert-VersionToDict
    $nuspecVer = $nuspecData.package.metadata.version | Convert-VersionToDict
    try {
      if (Compare-Version $nuspecVer $currentPkgVer){
        $buildRequired = $TRUE
      }
    } catch {
      Write-Output "##vso[task.logissue type=warning]Error comparing:
      CurrentPackage:
      $($currentPackage | Out-String)
      Nuspec Name:
      $($nuspec.name)
      Nuspec Data:
      $($nuspecData.package.metadata.version)
      Error:
      $($_ | Out-String)
      "
      Write-Output "##vso[task.complete result=SucceededWithIssues;]"
      continue
    }
  }
  if ($buildRequired) {
    Write-Output "Packing $($nuspec.FullName) to $OutputPath"
    Write-Output "currentPackage Value: $($currentPackage | Out-String)"
    Write-Output "Current pkg version: $($currentPackage.VersionString)"
    Write-Output "Nuspec pkg version: $($nuspecData.package.metadata.version)"
    &$chocoPath pack $nuspec.fullname --outputDirectory $OutputPath --limitoutput
  }
}

$headers = @{
  'Authorization' = "Bearer $ArtifactoryToken"
  'Content-Type' = 'application/json'
}
$pkgsRemoved = @()
$pkgsFailed = @()
$blobsRemoved = @()
$blobsFailed = @()
$removeStrings = @()
# Identify packages slated for removal based on provided parameters
foreach ($packageName in $packageNames) {
  $pkgTest = $allSorted | Where-Object {$_.PackageName -eq $packageName}
  Write-Debug "($($pkgTest.Count)) entries found for $packageName"
  if ($pkgTest.count -gt $RetainCount) {
    foreach ($pkgRemove in $pkgTest[($RetainCount)..($pkgTest.Count - 1)]) {
      Write-Debug "$($packagename):Total packages: $($pkgTest.count)"
      Write-Debug "$($packagename):Removal packages: $(($pkgTest[($RetainCount)..($pkgTest.Count - 1)]).count)"
      $artifactoryString = "$($pkgRemove.PackageName).$($pkgRemove.VersionString)"
      $removeStrings += $artifactoryString
    }
  }
  # Find packages that exist in the feed but not in the source
  if ($nuspeclist.BaseName -notcontains $packageName) {
    foreach ($version in $pkgTest.VersionString) {
      $artifactoryString = "$($packageName).$($version)"
      Write-Output "$($packageName): Adding $artifactoryString to removal strings due to not existing in repo"
      $removeStrings += $artifactoryString
    }
  }
}

# Remove from Artifactory
$dateCompare = (Get-Date).AddMonths(-$RetainMonths)
$artifactoryURIBase = 'https://<artifactory-cloud-uri-here>/artifactory'
$feedName = '<name-of-chocolatey-feed>'
foreach ($removeString in $removeStrings) {
  $blobRemovalStatus = $FALSE
  $removalStatus = $FALSE
  $afRemoveSplat = @{
    RemoveString       = $removeString
    ArtifactoryURIBase = $artifactoryURIBase
    FeedName            = $feedName
    DeletionDate       = $dateCompare
    Headers            = $headers
    BlobURIBase        = $BlobURIBase
    TenantID           = $TenantID
    AppID              = $AppID
    SubscriptionName   = $SubscriptionName
    StorageAcctName    = $StorageAcctName
    StorageContainer   = $StorageContainer
  }
  Write-Output "Removing $removeString"
  $removalStatus = Remove-ArtifactoryPackage @afRemoveSplat
  if ($removalStatus.BlobRemoved) {
    $blobsRemoved += $removalStatus.BlobURI
  } else {
    $blobsFailed += $removalStatus.BlobURI
  }
  if ($removalStatus.ArtifactoryRemoved) {
    $pkgsRemoved += $removeString
  } else {
    $pkgsFailed += $removeString
  }
}

if ($pkgsRemoved) {
  Write-Output "Packages removed:"
  $pkgsRemoved
}
if ($pkgsFailed) {
  Write-Output "Packages failed to remove:"
  $pkgsFailed
}
if ($blobsRemoved) {
  Write-Output "Blobs removed:"
  $blobsRemoved
}
if ($blobsFailed) {
  Write-Output "Blobs failed to remove:"
  $blobsFailed
}