###################################################################################
##
## Powershell script that checks you install scripts to make sure the files exists
## and copies over the relevant files indicated in your script from the schema
## location to the script location
##
## Version History
## 21-JAN-2020  Updated error message that can appear when branching
## 27-Jan-2020  Added check that character casing is the same and
##              cleaned up the formatting of the error messages
###################################################################################


# Gets the name of the branch that is the current focus
function GetBranchName
{
    if ($isAzureBuild -eq $true)
    {
        $branch_name = $env:BUILD_SOURCEBRANCHNAME
        $error_text = " "
    }
    else
    {
        $branch_name = git rev-parse --abbrev-ref HEAD
        $error_text = "Plus, are you really checking into master locally??"
    }

    if ($branch_name -eq "master")
    {
        Write-Host " "
        Write-Host "##############################################" -ForegroundColor Green
        Write-Host "This script uses git to determine your current branch and which folder to build." -ForegroundColor Red
        Write-Host "master branches cannot be built using this script" -ForegroundColor Red
        Write-Host $error_text -ForegroundColor Red
        Write-Host "##############################################" -ForegroundColor Green
        Write-Host " "
        exit 1
        
    }
    return $branch_name
}

# Checks the value of an environment variable only present in the azure build
# to differentiate between local and Azure build
function GetAzureBuild
{
    $returnval = $env:environmnet_isazure -eq "true"

    if ($returnval -eq $true)
    {
        Write-Host "Building on Azure"
    }
    else 
    {
        Write-Host "Building locally"
    }
    Write-Host " "

    return $returnval
}

# Checks locally for a git ignore file and creates / adds to it if needed
function CheckForGitIgnore
{
    #Check for a .gitignore.  If it isn't there add it and ignore the objects folder.  If the file exists then make sure that objects/* is  in it
    #
    # potential to have this at the root of the database folder.  Ignore all OBJECTS folders
    $path_exists = Test-Path -path "$workingDirectory\.gitignore";
    if($path_exists -eq $true)
    {
        $git_contents = Get-Content -path "$workingDirectory\.gitignore"
        $objects_ignored = $false
        $NoLocalBuild_found = $false
        foreach($gitline in $git_contents)
        {
            if($gitline.tolower() -eq "/Scripts/**/**/objects")
            {
                $objects_ignored = $true
            }
            if($gitline.tolower() -eq "nolocalbuild.txt")
            {
                $NoLocalBuild_found = $true
            }
        }

        if ($objects_ignored -eq $false)
        {
            Add-Content -path "$workingDirectory\.gitignore" -Value "/Scripts/**/**/objects"
            Write-Host "/InstallationScripts/**/objects added to the .gitignore file as it wasn't there"
        }
        if ($NoLocalBuild_found -eq $false)
        {
            Add-Content -path "$workingDirectory\.gitignore" -Value "NoLocalBuild.txt"
            Write-Host "NoLocalBuild.txt added to the .gitignore file as it wasn't there"
        }
    }
    else 
    {
        New-Item -Path "$workingDirectory\.gitignore" -ItemType "file" -Value "/Scripts/**/**/objects"
        Add-Content -path "$workingDirectory\.gitignore" -Value "NoLocalBuild.txt"
        Write-Host ".gitignore file created for you";
    }
}

# Looks for the NoLocalBuild text file and exits the script if one is found
function CheckForNoLocalBuild
{
    # Check for a NoLocalBuild.txt file
    $path_exists = Test-Path -path "$workingDirectory\NoLocalBuild.txt"
    if ($path_exists -eq $true)
    {
        Write-Host " "
        Write-Host "#######################################################################" -ForegroundColor Green
        Write-Host "NoLocalBuild.txt file found.  Aborting the build for commit to carry on"
        Write-Host "#######################################################################" -ForegroundColor Green
        Write-Host " "
        Exit 0
    }
}

# Gets the location of the Install folder
function GetInstallFolder
{
    if ($isAzureBuild -eq $true)
    {
        $install_folder =  "$env:BUILD_STAGINGDIRECTORY\$folder_name\Install"
    }
    else 
    {
        $install_folder =  "$workingDirectory\Scripts\$folder_name\Install"

        $path_exists = Test-Path -Path $install_folder
        if ($path_exists -eq $false)
        {
            Write-Host " "
            Write-Host "#######################################################################" -ForegroundColor Red
            Write-Host "ERROR - Cannot determine the folder to use for the build. Please ensure" -ForegroundColor Red 
            Write-Host "that you have followed the correct conventions" -ForegroundColor Red
            Write-Host "#######################################################################" -ForegroundColor Red
            Write-Host " "
            exit 1
        }
    }
    return $install_folder
}

# Gets the location of the Backout Folder
function GetBackoutFolder
{
    if ($isAzureBuild -eq $true)
    {
        $returnval = "$env:BUILD_STAGINGDIRECTORY\$folder_name\Backout"
    }
    else 
    {
        $returnval = "$workingDirectory\Scripts\$folder_name\Backout"
    }
    return $returnval
}

function PathCharacterCasingCorrect()
{
    # Checks to ensure the character casing is correct
    # had to do it this way as Windows is case insenstive 
    # when it comes to file paths.
    $fn_line = $args[0] 
    $fn_path = $args[1]
    $fn_script_to_find = $args[2]

    $fn_path_exists = Test-Path -Path "$fn_path\$fn_script_to_find"

    if ($fn_path_exists -eq $true)
    {
       
        $fn_splitLines = $fn_line.Replace("@objects", "").Replace("@", "").Split("/")

        Write-Host " "
        $fn_builtPathFromLine = ""
        $fn_builtPathFromFile = ""
        $fn_faultFound = $false

        foreach ($fn_spLine in $fn_splitLines)
        {
            $fn_builtPathFromLine = "$fn_builtPathFromLine\$fn_spLine"
            $fn_ChildItems = Get-ChildItem -path "$fn_path\$fn_builtPathFromLine*"

            # Just incase there is a TABLE directory and a TABLESPACE, match on all
            foreach($fn_Item in $fn_ChildItems)
            {
                if ($fn_item.Name -eq $fn_spLine)
                {
                    $fn_builtPathFromFile = "$fn_builtPathFromFile\$($fn_item.Name)"
                    
                    if($fn_item.Name -cne $fn_spLine)
                    {
                        $fn_faultFound = $true
                    }
                    break
                }
            }
        }

        if ($fn_faultFound -eq $true)
        {
            Write-Host " "
            Write-Host "####################################################################" -ForegroundColor Red
            Write-Host "SCRIPT FOUND BUT CHARACTER CASING IS INCORRECT." -ForegroundColor Red
            Write-Host "$fn_line " -ForegroundColor Red 
            Write-Host "was found but the character casing does not match the path on disk" -ForegroundColor Red
            Write-Host "..$fn_builtPathFromFile" -ForegroundColor Red
            Write-Host "####################################################################" -ForegroundColor Red
            Write-Host " "
            
            return $false
        }
        
        return $true
    }

    return $false
}

Write-Host "##############################################" -ForegroundColor Green
Write-Host "Starting build of database scripts" -ForegroundColor Green
Write-Host " "

Write-Host "Checking to see if this is a local build or on Azure DevOps"
$isAzureBuild = GetAzureBuild

Write-Host "Getting Branch information"
$branch_name = GetBranchName
        
$folder_name = $branch_name -replace "-master$", "" 
$folder_name = $folder_name -replace "-dev$", ""
$folder_name = $folder_name -replace "-development$", ""

if ($isAzureBuild -eq $true)
{
    Write-Host "Setting the environment variable to pass on folder name to zip"

    ##'echo "##vso[task.setvariable variable=ScriptFolderName;isOutput=true]$folder_name"
    Write-Output "##vso[task.setvariable variable=ScriptFolderName;isOutput=true]$folder_name"
}
Write-Host " "
Write-Host "Current Branch is $branch_name"
Write-Host "Installation folder name $folder_name"
Write-Host " "        
        
$workingDirectory = Get-Location
Write-Host "Working Directory is '$workingDirectory'"

if ($isAzureBuild -eq $false)
{
    CheckForGitIgnore
    CheckForNoLocalBuild
}

#Set the path to the schema
$schema_path = "$workingDirectory\schema"

#Create variable to store the path for the objects folder
$install_folder =  GetInstallFolder
Write-Host "Install folder : $install_folder"
$object_path  = "$install_folder\objects"

if ($isAzureBuild -eq $true)
{
    $path_exists = Test-Path -Path "$workingDirectory\Scripts\$folder_name"
    if ($path_exists -eq $true) 
    {
        Write-Host "Copy folder to azure temp space"
        Copy-Item -path "$workingDirectory\Scripts\$folder_name" -Destination $env:BUILD_STAGINGDIRECTORY\$folder_name -recurse    
    }
    else 
    {
        Write-Host " "
        Write-Host "######################################################"    
        Write-Host "ERROR CANNOT FIND THE FOLLOWING PATH IN AZURE DEVOPS"
        Write-Host "$workingDirectory\Scripts\$folder_name"
        Write-Host " "
        Write-Host "This is probably due to the branch just being created"
        write-host "and the folder $folder_name doesn't yet exist as you "
        Write-Host "haven't completed any development yet."
        Write-Host " "
        Write-Host "If this is the case, then you can ignore this failed"
        Write-host "build.  If it isn't you have some investigation to do!"
        Write-Host "######################################################"
        Write-Host " "
        Exit 1
    }
    
}

Write-Host "Objects Folder Path - $object_path"

$path_exists = Test-Path -Path $object_path
if ($path_exists -eq $true)
{
    Remove-Item $object_path -Recurse -Force
}

New-Item -path $object_path -ItemType Directory

$install_scripts = get-childitem -path $install_folder -filter "install*.sql"
$script_has_failed = $false

foreach ($install_script in $install_scripts)
{
    Write-Host "Working on the contents of $install_script"
    
    #Get the content of the Script
    #
    $script = Get-Content -Path $install_script.FullName
    $script_log_found = $false
    #Go through line by line (foreach)
    #
    foreach ($line in $script)
    {
        #If the line starts with @objects/ get the rest of the path (Schema/ObjectType/ObjectName.pkb) and check for the file
        if($line.startswith("@objects") -eq $true)
        {
            $script_to_find = $line.Replace("@objects/", "").Replace("/", "\")
            Write-Host "Script to find : $script_to_find"
            $path_exists = Test-Path -Path "$schema_path\$script_to_find"

            #If the file exists, and the character casing is correct, copy it over to the objects location.  Overwrite any file that is already there
            if ($path_exists -eq $true)
            {

                if (PathCharacterCasingCorrect "$line" "$schema_path" "$script_to_find" -eq $true)
                {
                    Write-Host "Script found in schema location";
                    # check for destination folders
                    if(!(Split-Path -path "$object_path\$script_to_find" | Test-Path)) 
                    {
                        New-Item -path (Split-Path -path "$object_path\$script_to_find") -ItemType Directory
                    }   

                    Copy-Item -Path "$schema_path\$script_to_find" -Destination "$object_path\$script_to_find" -Force
                }
                else
                {
                    $script_has_failed = $true
                }
            }
            else 
            {
                #If the file does not exist, report that back to the user
                Write-Host " "
                Write-Host "###########################################################" -ForegroundColor Red
                Write-Host "SCRIPT NOT FOUND.  $line not found in the schema location" -ForegroundColor Red
                Write-Host "Please check your spelling and the character casing" -ForegroundColor Red
                Write-Host "###########################################################" -ForegroundColor Red
                Write-Host " "
                $script_has_failed = $true
            }

        }
        else
        {
            #If the line doesn't start with @objects/, check that the file specified exists and report back to the user
            if($line.startswith("@") -eq $true)
            {
                $script_to_find = $line.Replace("@", "").Replace("/", "\")
                $path_exists = Test-Path -Path "$install_folder\$script_to_find*"

                if ($path_exists -eq $true)
                {
                    if (PathCharacterCasingCorrect "$line" "$install_folder" "$script_to_find" -eq $true)
                    {
                        Write-Host "Found script $line"
                    }
                    else 
                    {
                        $script_has_failed = $true
                    }
                }
                else
                {
                    Write-Host " "
                    Write-Host "#########################################################" -ForegroundColor Red
                    Write-Host "SCRIPT NOT FOUND.  $line could not be found in the " -ForegroundColor Red
                    Write-Host "installation directory.  Please check your spelling etc" -ForegroundColor Red
                    Write-Host "#########################################################" -ForegroundColor Red
                    Write-Host " "
                    $script_has_failed = $true
                }
            }
        }
        if ($line.tolower().contains("script_log"))
        {
            $script_log_found = $true
        }
    }

    if ($script_log_found -eq $false)
    {
        Write-Host " "
        Write-Host "#########################################################" -ForegroundColor Red
        Write-Host "REFERENCE TO STDMGR.SCRIPT_LOG TABLE NOT FOUND in installation script $install_script. " -ForegroundColor Red
        Write-Host "If for some reason your installation script does not need to insert into this table" -ForegroundColor Red
        Write-Host "Please put a note in a comment in the script saying why e.g --script_log not required because" -ForegroundColor Red
        Write-Host "#########################################################" -ForegroundColor Red
        Write-Host " "
        $script_has_failed = $true
    }
}

Write-Host "Installation Scripts Finished.  Starting Backout Scripts"

Write-Host "Checking backout folder"

$backout_folder =  GetBackoutFolder 
Write-Host "Backout folder : $backout_folder"

$path_exists = Test-Path -Path $backout_folder

if ($path_exists -eq $false)
{
    Write-Host " "
    Write-Host "#################################################" -ForegroundColor Red
    Write-Host "BACKOUT FOLDER NOT FOUND" -ForegroundColor Red
    Write-Host "Please include a backout script for your solution" -ForegroundColor Red
    Write-Host "#################################################" -ForegroundColor Red
    Exit 1
}

Write-Host "Checking backout scripts for completeness"
$backout_scripts = Get-ChildItem -Path $backout_folder -Filter "backout*.sql"    

foreach ($backout_script in $backout_scripts)
{
    Write-Host "Checking backout script $backout_script"

    $script = Get-Content -Path $backout_script.FullName
    $script_log_found = $false

    foreach ($line in $script)
    {
        if ($line.startswith("@") -eq $true)
        {
            $script_to_find = $line.Replace("@", "").Replace("/", "\")
            $path_exists = Test-Path -Path "$backout_folder\$script_to_find"

            if ($path_exists -eq $true)
            {
                if (PathCharacterCasingCorrect "$line" "$backout_folder" "$script_to_find" -eq $true)
                {
                    Write-Host "Found script $line"
                }
                else
                {
                    $script_has_failed = $true
                }
                
            }
            else 
            {
                Write-Host " "
                Write-Host "#################################################################" -ForegroundColor Red   
                Write-Host "SCRIPT NOT FOUND.  $line could not be found in the backout script"  -ForegroundColor Red  
                Write-Host "#################################################################" -ForegroundColor Red   
                Write-Host " "
                $script_has_failed = $true
            }
        }
        if ($line.tolower().contains("script_log"))
        {
            $script_log_found = $true
        }
    }
    
    if ($script_log_found -eq $false)
    {
        Write-Host " "
        Write-Host "#########################################################" -ForegroundColor Red
        Write-Host "REFERENCE TO STDMGR.SCRIPT_LOG TABLE NOT FOUND in backout script $install_script. " -ForegroundColor Red
        Write-Host "If for some reason your installation script does not need to insert into this table"
        Write-Host "Please put a note in a comment in the script saying why e.g --script_log not required because"
        Write-Host "#########################################################" -ForegroundColor Red
        Write-Host " "
        $script_has_failed = $true
    }

}

if ($script_has_failed -eq $true)
{
    Write-Host " "    
    Write-Host "NO      NO" -ForegroundColor Red
    Write-Host " NO    NO" -ForegroundColor Red
    Write-Host "  NO  NO" -ForegroundColor Red
    Write-Host "   NONO" -ForegroundColor Red
    Write-Host "  NO  NO" -ForegroundColor Red
    Write-Host " NO    NO" -ForegroundColor Red
    Write-Host "NO      NO" -ForegroundColor Red
    Write-Host " "
    Write-Host "Database Build Failed!" -ForegroundColor Red
    Write-Host "Error Messages will be in capitals and red if your cmd window supports it"  
    Write-Host "Please check and try again "
    Write-Host "################################################################" -ForegroundColor Red
    Exit 1
}
else 
{
    Write-Host " "
    Write-Host "              YES" -ForegroundColor Green
    Write-Host "            YES" -ForegroundColor Green
    Write-Host "          YES  " -ForegroundColor Green
    Write-Host "YES     YES" -ForegroundColor Green
    Write-Host "  YES YES" -ForegroundColor Green
    Write-Host "    YES    " -ForegroundColor Green
    Write-Host " "
    Write-Host "Database Build Complete!" -ForegroundColor Green
    Write-Host " "
    Write-Host "##############################################" -ForegroundColor Green  
}
