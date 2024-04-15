<#
.Synopsis
  Verifies values in chocolateyinstall.ps1 files
.DESCRIPTION
  By default, this will scan all chocolateyinstall.ps1 files in the current directory and subdirectories
	A list of chocolateyinstall.ps1 files can also be passed manually in order to target specific files.
	Or the GitChangedOnly switch can be used to target only files changed between the current branch and the main branch
	In order to pass parameters to a Pester test you have to define a container and then pass it to the Invoke-Pester command.
.EXAMPLE
	Testing specific file paths:
	$testPaths = @(
	'C:\Repos\Chocolatey\tests\public\chocolateyinstall.acceptance.tests.ps1',
	'C:\Repos\Chocolatey\tests\public\choco-naming.acceptance.tests.ps1'
	)
	$filePaths = @(
		'C:\Repos\Chocolatey\packages\core\google-chrome-stable\tools\chocolateyinstall.ps1',
		'C:\Repos\Chocolatey\packages\core\google-chrome-stable\google-chrome-stable.nuspec'
	)
	$container = New-PesterContainer -Path $testPaths -Data @{ FilePaths=$filePaths }
	$config = New-PesterConfiguration
	$config.output.StackTraceVerbosity = 'None'
	$config.Run.Container = $container
	Invoke-Pester -Configuration $config

	Testing only changed files identified by git:
	$testPaths = @(
	'C:\Repos\Chocolatey\tests\public\chocolateyinstall.acceptance.tests.ps1',
	'C:\Repos\Chocolatey\tests\public\choco-naming.acceptance.tests.ps1'
	)
	$container = New-PesterContainer -Path $testPaths -Data @{ GitChangedOnly = $true }
	$config = New-PesterConfiguration
	$config.output.StackTraceVerbosity = 'None'
	$config.Run.Container = $container
	Invoke-Pester -Configuration $config

	Test all files in current directory and subdirectories:
	$config = New-PesterConfiguration
	$config.run.path = 'C:\Repos\Chocolatey\tests\public'
	$config.output.StackTraceVerbosity = 'None'
	Invoke-Pester -Configuration $config

	Get standard output from a test run:
	$config = New-PesterConfiguration
	$config.run.path = 'C:\Repos\Chocolatey\tests\public'
	$config.run.passthru = $true
	$config.output.StackTraceVerbosity = 'None'
	$test = Invoke-Pester -Configuration $config
	$test.tests.StandardOutput
#>
param(
	[Parameter(Mandatory=$false)]
  [ValidateScript({
		foreach ($path in $_){
			if (!(Test-Path $path -PathType 'leaf')){
				throw "No file exists at $path"
				$false
			}
		}
		$true
  })]
  [string[]]$FilePaths,
	[Parameter(Mandatory=$false)][switch]$GitChangedOnly
)

BeforeDiscovery {
	# Depending on parameters supplied, we either need to identify changes made in this branch,
	# or we scan all files, or we scan the supplied specific files to test
	if ($GitChangedOnly -and !$FilePaths) {
		try {
			$mainBranch = (git remote show origin | Select-String 'HEAD branch').ToString().Split(' ')[-1]
			if (-not $?) { throw }
			$gitRoot = (git rev-parse --show-toplevel)
			if (-not $?) { throw }
			$changedFiles = (git diff --diff-filter=d --name-only origin/${mainBranch}...)
			if (-not $?) { throw }
		} catch {
			Write-Error "Error running git commands to detect changed files: `n$($_ | Select-Object * | Out-String)"
			return
		}
		$filesToTest = foreach ($file in ($changedFiles | Where-Object {$_ -like '*chocolateyinstall.ps1'})) {
			$testFile = Join-Path $gitRoot $file
			if (Test-Path $testFile) {
				@{
					FullPath = $testFile
					RelativePath = $file
				}
			} else {
				throw "Error testing path at $($testfile), this should not happen"
			}
		}
	} elseif (!$FilePaths) {
		$filesToTest = (Get-ChildItem $PWD -filter '*chocolateyinstall.ps1' -Recurse) | ForEach-Object {
			@{
				FullPath = $_.FullName
				RelativePath = $_.FullName.Substring($_.FullName.IndexOf('packages'))
			}
		}
	} else {
		$filesToTest = $FilePaths | Where-Object {$_ -like '*chocolateyinstall.ps1'} | ForEach-Object {
			@{
				FullPath = $_
				RelativePath = $_.Substring($_.IndexOf('packages'))
			}
		}
	}
	$filesToTest = $filesToTest | Where-Object {$_['FullPath'] -notlike '*templates*' -and $_ -notlike '*test-*'}
	# Variables to be tested and the patterns that they should match
	$PSVariables = @(
		@{
			VariableName =  'checksum'
			Pattern = '^\S{64}$'
		},
		@{
			VariableName =  'checksumType'
			Pattern = '^sha256$'
		},
		@{
			VariableName =  'fileName'
			Pattern = '^(?i).+\.(exe|zip|msi|cab|msp|msix)$'
		},
		@{
			VariableName =  'file'
			Pattern = '(^(?i)\\\\[^\.]+(\.[^\.\$]+)+\\$fileName)|(^(?i)Join-Path \$toolsDir \$fileName$)|((?i)^https:\/\/\S+\.\S+\.\S+\/)'
		},
		@{
			VariableName =  'fileType'
			Pattern = '^(?i)MSI|EXE|MSU$'
		}
	)
}

# Variable names and the patterns that they should match (if defined)
Describe "Chocolatey Install Tests" -ForEach $filesToTest {
	BeforeDiscovery {
		$filePath     = $_.FullPath
		$psVarList    = $NULL
		# Create dynamic regex to retrieve the current hard values of variables from the script file we are analyzing
		# Negative lookbehind for '#' to exclude comments, then any amount of whitespaces, then a $ to denote the beginning of a variable
		# then any of the retrieved variable names from the step above, and then optional spaces before/after the '='. Any variable with a
		# $NULL value is excluded from population using a negative lookahead.
		# $varPattern = '(?i)^(?<!#)(\s+|)(\$(' + ($psVar.VariableName) + ')(\s+|)=(\s+|))(?<!\$NULL).*$'
		# Get matches based on our dynamic regex and create a string output, in PS7 there is the -Raw argument for Select-String,
		# But not enough stuff is standardized onto PS7 yet so we've got this jank.
		# $lineMatches = Get-Content $filePath | select-string -Pattern $varPattern
		$psVarList = foreach ($psVar in $PSVariables) {
			#$varPattern = '(?i)^(?<!#)(\s+|)(\$(' + ($psVar.VariableName) + ')(\s+|)=(\s+|))(?<!\$NULL).*$'
			$varPattern = '^(?i)(?<!#)\s*\$' + $psVar.VariableName + '\s*=\s*(?!.*\$NULL).*$'
			$lineMatch = Get-Content $filePath | Select-String -Pattern $varPattern
			if (!$lineMatch -or $lineMatch.count -ne 1) { continue }
			@{
				variableName = $psVar.VariableName
				filepath = $filePath
				relativePath = $_.RelativePath
				pattern = $psVar.Pattern
				line = $lineMatch.Line.trim()
				lineNumber = $lineMatch.LineNumber
			}
		}
	}
	Context "Variables" -ForEach $psVarList {
		BeforeEach {
			Set-Variable -Name $_.variableName -Value $NULL
			try {
				# Have to put non-strings into string format so this doesnt try to reference variables that dont exist outside of the choco
				# context
				$psVarImport = $NULL
				$temp = $NULL
				$temp = $_.line.split('=') | ForEach-Object {$_.trim()}
				$psVarImport = if ($temp[1][0] -notmatch "`"|'"){
						"$($temp[0].trim()) = '$($temp[1].trim())'"
					} else {
						"$($temp[0].trim()) = $($temp[1].trim())"
				}
				# Convert the string to a script block, then dot source it to import the current variable values
				$psVarImport = [Scriptblock]::Create($psVarImport)
				.$psVarImport
			} catch {
				throw "Unable to convert the file content at $filePath to a parseable script block. Attempted to import: '$psVarImport' from pattern '$varPattern' Exception: $($_)"
			}
		}
		# Colons added to the end of assertion names to make published summaries look better
		It "Value of '<variableName>' should match pattern when defined: (<relativePath>:<lineNumber>)" {
			$varTest = $NULL
			$varTest = Get-Variable $_['variableName']
			$vartest.Value | Should -match $_.pattern
		}
	}
}