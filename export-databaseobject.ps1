function Export-DatabaseObject {
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Instance = $null,
        [Parameter(Mandatory = $false)]
        [string]$Port,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = $null,
        [Parameter(Mandatory = $false)]
        [string]$DBList = 'ALL',
        [Parameter(Mandatory = $false)]
        [bool]$IncludeTables = $true,
        [Parameter(Mandatory = $false)]
        [bool]$IncludeViews = $true,
        [Parameter(Mandatory = $false)]
        [bool]$IncludeSP = $true,
        [Parameter(Mandatory = $false)]
        [bool]$IncludeUDF = $true,
        [Parameter(Mandatory = $false)]
        [bool]$ScriptAsSingleFile = $true
    )
    #-----------------------------
    #This script contains a modifications of http://www.sqlstad.nl/powershell/script-database-objects-using-powershell/ and http://patlau.blogspot.co.uk/2012/09/generate-sqlserver-scripts-with.html
    #-----------------------------
    #Load the assembly
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null

    # Create the server object and retrieve the information
    try {
        # Set the destination
        if ($Instance.Contains(".\")) {
            $Instance = $Instance.Replace(".\", $($env:COMPUTERNAME + "\"))
        }
        $destination = "$OutputPath\$Instance"
        if ((Test-Path $destination) -eq $false) {
            # Create the directory
            New-Item -ItemType Directory -Path "$destination" | Out-Null
        }
        # Make a connection to the database
        if (($Port -eq $null) -or ($Port -eq "")) {
            $ConnectionString = $Instance
        }
        else {
            $ConnectionString = "$Instance,$Port" 
        }
        $server = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $ConnectionString
        $databases = @{}
        # Check if a selective list must be used
        if ($DBList -eq 'ALL') {
            # Get the user databases, the system databases are excluded
            $databases = $server.Databases | Select-Object Name | Where-Object {$_.Name -notmatch 'master|model|msdb|tempdb' }
        }
        else {
            $databases = @()
            #clean up the data
            $DBList = $DBList.Replace(' ', '')
            # Split the string
            $values = $DBList.Split(',') 
            foreach ($value in $values) {
                $db = New-Object psobject
                $db | Add-Member -membertype noteproperty -name "Name" -Value $value
                $databases += $db
            }
        }
        # Check if there are any databases
        if ($databases.Count -ge 1) {
            # Loop through
            foreach ($database in $databases) {
                 Write-Verbose "Starting Database Export: $($database.Name)"
                # Set the desitnation
                $outputDestination = "$destination\" + $database.Name
                # Removing old exported scripts
                if (Test-Path -Path $outputDestination) {
                    Get-Childitem $outputDestination -include *.sql -recurse | ForEach-Object ($_) {Remove-Item $_.fullname}
                }
                # Create the variable for holding all the database objects
                $objects = $null
                # Check if the tables need to be included
                if ($IncludeTables) {
                    Write-Verbose "Retrieving Tables"
                    # Get the tables
                    $objects += $server.Databases[$database.Name].Tables | Where-Object {!($_.IsSystemObject)}
                }
                # Check if the views need to be included
                if ($IncludeViews) {
                    Write-Verbose "Retrieving Views"
                    # Get the views
                    $objects += $server.Databases[$database.Name].Views | Where-Object {!($_.IsSystemObject)}
                }
                # Check if the stored procedures need to be included
                if ($IncludeSP) {
                    Write-Verbose "Retrieving Stored Procedures"
                    # Get the stored procedures
                    $objects += $server.Databases[$database.Name].StoredProcedures | Where-Object {!($_.IsSystemObject)}
                }
                # Check if the user defined functions need to be included
                if ($IncludeUDF) {
                    Write-Verbose "Retrieving User Defined Functions"
                    # Get the stored procedures
                    $objects += $server.Databases[$database.Name].UserDefinedFunctions | Where-Object {!($_.IsSystemObject)}
                }
                Write-Verbose "$($objects.Length) objects found to export."
                # Check if there any objects to export
                if ($objects.Length -ge 1) {
                    # Create the scripter object
                    $scripter = New-Object ("Microsoft.SqlServer.Management.Smo.Scripter") $server
                    # Set general options
                    $scripter.Options.AppendToFile = $ScriptAsSingleFile
                    $scripter.Options.AllowSystemObjects = $false
                    $scripter.Options.ClusteredIndexes = $true
                    $scripter.Options.DriAll = $true
                    $scripter.Options.ScriptDrops = $false
                    $scripter.Options.IncludeHeaders = $true
                    $scripter.Options.ToFileOnly = $true
                    $scripter.Options.Indexes = $true
                    $scripter.Options.WithDependencies = $false
                    $Scripter.Options.NoCollation= $True
                    $dependencyTree = $scripter.DiscoverDependencies($objects, $true)
                    $dependencyCollection = $scripter.WalkDependencies($dependencyTree);
                    $urnCollection = New-Object Microsoft.SqlServer.Management.Smo.UrnCollection;
                    [System.Collections.ArrayList]$urnCollectionDone = @()
                    foreach ($dependency in $dependencyCollection) { 
                        $urnCollection.add($dependency.Urn)
                    }
                    $onlyOne = New-Object Microsoft.SqlServer.Management.Smo.UrnCollection;
                    foreach ($urn in $urnCollection) {
                        $onlyOne.clear()
                        $item = $server.GetSmoObject($urn)
                        if (-not $urnCollectionDone.Contains($item.Urn)) {
                            # Get the type of object
                            $typeDir = $item.GetType().Name
                            $onlyOne.add($item.Urn)
                            #Setup the output file for the item
                            $filename = $item -replace "\[|\]"
                            if ($ScriptAsSingleFile) {
                                $filename = "$outputDestination\$($database.name).sql"
                                # Check if output directory exists
                                if ((Test-Path "$outputDestination") -eq $false) {
                                    New-Item -ItemType Directory -Path "$outputDestination" | Out-Null
                                }
                            }
                            else {
                                # Check if the directory for the item type exists
                                if ((Test-Path "$outputDestination\$typeDir") -eq $false) {
                                    New-Item -ItemType Directory -Name "$typeDir" -Path "$outputDestination" | Out-Null
                                }
                                $filename = "$outputDestination\$typeDir\$filename.sql"
                            }
                            # Script out the object 
                            $scripter.Options.FileName = $filename
                            Write-Verbose "Scripting $typeDir $item to $filename"
                            $scripter.Script($onlyOne)
                            $urnCollectionDone.add($item.Urn) | Out-Null
                        }
                    }
                }
            }
        }
        else {
            Write-Warning "No databases found."
        }
    }
    catch [Exception] {
        $errorMessage = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        $script_name = $_.InvocationInfo.ScriptName
        Write-Error "Error: Occurred on line $line in script $script_name."
        Write-Error "Error: $ErrorMessage"
    }
}