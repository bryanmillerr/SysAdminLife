###############################################################################################################
## Bryan Miller | 2024
##
##  Notes:
##           A lot going on with this one.
##          This script is used to parse the "Unauthorized" device group, which is the default profile for all
##          Zero-Touch Enrolled Devices. This tool accomplishes three major things:
##                  1. Lists all devices that have been enrolled via the "Unauthorized" profile (default for ZTE)
##                  2. Calls Android Provisioning API to apply a different "assignment"
##                  3. Deletes (wipes) the device to allow end-users to go through the ZTE setup process
##
##          Maybe one day I'll make a gui for this, but for now- this will work. Not very comfortable with
##          this code being shared.
##
##          To-Do:
##                  1. Better token usage
##                  2. Guify
##
###############################################################################################################
## Version Number
$versionNumber = "1.2"
$patchNotes = "
- Fixed an issue where the script would error out if a device is listed in Entra ID, but not in Intune"

## Company Customization (required variables)
$customerNumber = ""      ## Google Customer Number
$clientId = "" ## Google Oauth client ID
$clientSecret = ""   ## Google Oauth Secret
$refreshToken = "" ## Google Oauth2 refresh token

## Device Groups
$unauthorizedGroup = ""   ## Group ID for devices are placed in for the unauthorized ZTE enrollment
$zeroTouchBroadGroup = ""   ## Group ID that houses all zero touch devices
$zeroTouchBroadGroupName = ""    ## Name of the group that houses all zero touch devices
$unauthorizedConfigId = ""        ## Your unauthorized devices (default) config profile in ZTE
$amrGroupName = ""    ## prefix for the AMR group

## Log location
$logLocation = "C:\ProgramData\ZeroTouchLogs"
Start-Sleep 1
###############################################################################################################
Clear-host
## Import Modules
Import-Module -Name Microsoft.Graph.DeviceManagement
Import-Module -Name Microsoft.Graph.Beta.DeviceManagement.Actions -Force
Clear-host
Write-host "Android Zero-Touch Management Tool v$versionNumber" -ForegroundColor Green
Write-Host "Patch Notes: $patchNotes"
Write-Host "Created by UFP Industries, 2024" -ForegroundColor Green
Write-Host ""
Write-host "Important: Activate PIM Role for your account before using this tool." -ForegroundColor Yellow
Write-Host ""

###############################################################################################################
## Prepare script run (cleanup previous items and make temp folder)
If (Test-Path $PSScriptRoot"\temp" ) {
    Remove-Item -path $PSScriptRoot"\temp" -Recurse -Force
}
$tempFolder = New-Item -Path "$PSScriptRoot" -Name "temp" -ItemType "directory" -Force -ErrorAction SilentlyContinue
$hideFolder = Get-Item $PSScriptRoot"\temp" -Force | foreach { $_.Attributes = $_.Attributes -bor "Hidden" }

## Prepare logs
If (Test-Path : ) {
    Remove-Item -path "$logLocation" -Recurse -Force
}
$dateFormat = Get-Date -Format "MMddyyyy-HHmmss"
$tempFolder = New-Item -Path "$logLocation" -ItemType "directory" -Force -ErrorAction SilentlyContinue
$logFile = New-Item -Path $logLocation -Name "ZeroTouch-$dateFormat.log" -Itemtype "file" -Force -ErrorAction SilentlyContinue
$startLogs = Start-Transcript -Path "$logLocation\ZeroTouch-$dateFormat.log" -Append

###############################################################################################################
function exitScript {
    $DisconnectGraph = Disconnect-MgGraph
    $DisconnectEntraID = Disconnect-AzureAD
    Remove-Item $PSScriptRoot"\temp" -Recurse -Force
    $stopLogs = $stopLogs = Stop-Transcript
    Exit 1
}

## Connect to MS graph (will prompt for creds)
try {
    Write-host "Connecting to MS Graph API..." -ForegroundColor Blue
    try {
        $ConnectGraph = Connect-MgGraph -Scopes DeviceManagementManagedDevices.PrivilegedOperations.All, DeviceManagementManagedDevices.Read.All, DeviceManagementManagedDevices.ReadWrite.All, Group.ReadWrite.All -NoWelcome
        if ((Get-Content -Path "$logLocation\ZeroTouch-$dateFormat.log") -like "*FullyQualifiedErrorId*") {
            Write-Host "Failed to connect to MS Graph API" -ForegroundColor Red
            exitScript
        }        
        Write-Host "Connected to MS Graph API" -ForeGroundColor Green
        Write-Host ""
    } catch {
        Write-Host "Failed to connect to MS Graph API" -ForegroundColor Red
        exitScript
    }
    Write-Host "Connecting to Entra ID API..." -ForeGroundColor Blue
    try {
        $ConnectEntraID = Connect-AzureAD
        Write-Host "Connected to Entra ID API" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-Host "Failed to connect to EntraID API" -ForegroundColor Red
        exitScript
    }
} catch {
    Write-Host "Failed to connect to graphAPI and Entra ID API" -ForegroundColor Red
    exitScript
}

###############################################################################################################
## Gather ZTE devices from Google
## Refresh Google Oauth2 token if this fails, get a new token via the Oauth2 playground
try {
$requestUri = "https://www.googleapis.com/oauth2/v4/token"
$refreshTokenParams = @{
  client_id="$clientId";
  client_secret="$clientSecret";
  refresh_token="$refreshToken";
  grant_type="refresh_token"; # Fixed value

}
    $tokens = Invoke-RestMethod -Uri $requestUri -Method POST -Body $refreshTokenParams
    Set-Content $PSScriptRoot"\temp\accessToken.txt" $tokens.access_token
} catch {
    Write-Host "Failed to connect to Android Provisioning API" -ForegroundColor Red
    exitScript
}

## Parse devices
try {
    $AuthToken = Get-Content $PSScriptRoot"\temp\accessToken.txt"
    $requestUri = "https://androiddeviceprovisioning.googleapis.com/v1/customers/$customerNumber/configurations"
    Invoke-RestMethod -Headers @{Authorization = "Bearer $AuthToken"} -Uri "$requestUri" -Method GET -ContentType 'application/json' | ConvertTo-JSON | Out-File $PSScriptRoot"\temp\availableConfigs.json"
    $AuthToken = Get-Content $PSScriptRoot"\temp\accessToken.txt"
    $requestUri = "https://androiddeviceprovisioning.googleapis.com/v1/customers/$customerNumber/devices?pageSize=100"
    Write-Host "Gathering Zero-touch Devices. Please wait..." -ForegroundColor Blue
    $devices = Invoke-RestMethod -Headers @{Authorization = "Bearer $AuthToken"} -Uri "$requestUri" -Method GET -ContentType 'application/json' | ConvertTo-Json | Out-File $PSScriptRoot"\temp\devices.json"
    Do {
        $index++
        $nextPageToken = (Get-Content $PSScriptRoot"\temp\devices.json" | ConvertFrom-Json).nextPageToken
        $requestUri = "https://androiddeviceprovisioning.googleapis.com/v1/customers/$customerNumber/devices?pageSize=100&pageToken=$nextPageToken"
        $devices = Invoke-RestMethod -Headers @{Authorization = "Bearer $AuthToken"} -Uri "$requestUri" -Method GET -ContentType 'application/json' | ConvertTo-Json | Out-File $PSScriptRoot"\temp\devices.json"
        $parsedDevices = $devices + (Get-Content $PSScriptRoot"\temp\devices.json") | Out-File -Append $PSScriptRoot"\temp\parsedDevices.json"
    } While ($nextPageToken -notlike "")
    $parsedDevices = Get-Content $PSScriptRoot"\temp\parsedDevices.json"
    Remove-Item -Path $PSScriptRoot"\temp\devices.json"
    Write-Host "Zero-touch devices parsed" -ForegroundColor Green
} catch {
    Write-Host "Failed to get devices from Google API" -Foregroundcolor Red
    exitScript
}

###############################################################################################################
## Start the process

Write-Host "
What would you like to do:
[1] Assign a configuration to 'Unauthorized' devices 
[2] Re-assign Zero Touch Devices"
Write-Host ""
do {
    $selection = Read-Host "Please make a selection (1 or 2)"
} until (($selection -like "1") -or ($selection -like "2"))

###############################################################################################################
## Cleanup Unauthorized devices workflow

if ($selection -like "1" ){
    Write-Host "Preparing to reassign devices in the Google Zero Touch portal" -ForeGroundColor Cyan
## Retrieve Unauthorized Device Group Members
try {
    $devicesInGroup = Get-MgGroupMember -GroupId "$unauthorizedGroup" | Select-Object -Property ID
    $formattedDevicesInGroup = $devicesInGroup.Id

    ## Check if any devices are in the group (just looks for a hyphen because all devices have them in their ID)
    if ($formattedDevicesInGroup -notlike "*-*") {
        write-host ""
        write-host "There are no devices currently unauthorized!" -ForegroundColor Green
        write-host ""
        exitScript
    }

    ## Prepare array
    $deviceNumber = 0
    $objectNumber = 0

    ## Let's see what we have
    Write-Host "--------------------------------------------------------------------------------------------------------------------" -ForeGroundColor DarkGray
    write-host "Unauthorized devices:" -ForeGroundColor Yellow
} catch {
    Write-Host "Failed to obtain device group members" -ForegroundColor Red
    exitScript
}

## Show each item in group
try {
    foreach ($device in $($formattedDevicesInGroup -split "`r`n")) {
        write-host ""
        $deviceObjectID = Get-AzureADDevice -ObjectId "$device" | Select-Object -Property DeviceId
        $formattedObjectID = $deviceObjectID.DeviceId
        $deviceObject = Get-MgDeviceManagementManagedDevice -Filter "contains(AzureAdDeviceId,'$formattedObjectId')"
        $objectNumber +=1
        $deviceNumber +=1
        $deviceSerial = $deviceObject.SerialNumber
        $deviceManufacturer = $deviceObject.Manufacturer
        $deviceModel = $deviceObject.Model
        $deviceImei = $deviceObject.IMEI
        New-Variable -Name "deviceObjectID$objectNumber" -Value "$formattedObjectID"
        New-Variable -Name "deviceEntraID$objectNumber" -Value "$device"
        New-Variable -Name "deviceSerial$objectNumber" -Value "$deviceSerial"
        New-Variable -Name "deviceModel$objectNumber" -Value "$deviceModel"
        New-Variable -Name "deviceManufacturer$objectNumber" -Value "$deviceManufacturer"
        New-Variable -Name "deviceIMEI$objectNumber" -Value "$deviceIMEI"
        Write-Host "--------------------------------------------------------------------------------------------------------------------" -ForeGroundColor DarkGray
        write-host "Device $deviceNumber" -ForegroundColor Green
        $displayObject = $deviceObject | Format-Table SerialNumber, EnrolledDateTime, LastSyncDateTime, ComplianceState -Autosize | Out-String
        write-host "$displayObject" -ForegroundColor Cyan
        if (($parsedDevices -like "*$deviceSerial*") -or ($parsedDevices -like "*$deviceIMEI*")) {
            if ($deviceIMEI -notlike $NULL) {
                $deviceInfo = select-string -path $PSScriptRoot"\temp\parsedDevices.json" -pattern "$deviceIMEI" -Context 3 | Out-File $PSScriptRoot"\temp\tempDevice.json"
            } else {
                $deviceInfo = select-string -path $PSScriptRoot"\temp\parsedDevices.json" -pattern "$deviceSerial" -Context 3 | Out-File $PSScriptRoot"\temp\tempDevice.json"
            }
            $configurationName = Get-Content $PSScriptRoot"\temp\tempDevice.json" -tail 3 | Out-String
            $configurationName = $configurationName -replace '(^\s+|\s+$)','' -replace '\s+',' '
            $configurationName = $configurationName.substring($configurationName.length - 15)
            $configurationName = $configurationName -replace "[^0-9]" , ''
            $configNumber = 0
            $parsedConfigs = Get-Content -Path $PSScriptRoot"\temp\availableConfigs.json" | ConvertFrom-Json
            do {
                $configName = $parsedConfigs.configurations[$configNumber] | Select-Object -ExpandProperty configurationName
                $configNumber++
            } While ($configName -notlike "")
            $finalCount = $configNumber - 1
            $configNumber = 0
            1..$finalCount | ForEach-Object {
                $configName = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationName
                $tempName = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationName
                $configId = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationId
                $shortenedConfigName = $shortenedConfigName -replace '(^\s+|\s+$)','' -replace '\s+',' '
                $configName = $configName -replace '(^\s+|\s+$)','' -replace '\s+',' '
                New-Variable "configurationNumberTemp$configNumber" -Value @($configName, $configId)
                $configArrayTemp = Get-Variable -Name "configurationNumberTemp$configNumber" -ValueOnly
                $configNumber++
                $allConfigs = (Get-Variable -Name "configurationNumberTemp*" -ValueOnly) | Out-File $PSScriptRoot"\temp\allConfigsTemp.json" -Append
                Remove-Variable -Name "configurationNumberTemp*"
            }
            $finalCount = $finalCount - 1
            $allConfigs = Get-Content -Path $PSScriptRoot"\temp\allConfigsTemp.json"
            if ("$allConfigs" -like "*$configurationName*") {
                $matchingConfig = ($allConfigs | Select-String -Pattern "$configurationName"-Context 1,0 ) | Out-File $PSScriptRoot"\temp\tempConfig.json"
                $matchingConfig = Get-Content $PSScriptRoot"\temp\tempConfig.json" -first 2 | Out-String
                $matchingConfig = $matchingConfig -replace '(^\s+|\s+$)','' -replace '\s+',' '
                if ($matchingConfig -like "*Unauthorized*") {
                    $deviceZTEStatus = "Unauthorized"
                    Write-Host "Zero-touch Configuration: $matchingConfig" -ForeGroundColor Green
                    $deviceZTEStatus = "Unauthorized"
                } elseif ($matchingConfig -like "*AMR*") {
                    Write-Host "Zero-touch Configuration: $matchingConfig" -ForeGroundColor Red
                    $deviceZTEStatus = "Yes"
                    $fleetMgmt = "Yes"
                } else {
                    Write-Host "Zero-touch Configuration: $matchingConfig" -ForeGroundColor Red
                    $deviceZTEStatus = "Yes"
                }
            } else {
                write-host "Zero-touch Configuration: Enterprise Default" -ForeGroundColor Yellow
                $deviceZTEStatus = "Yes"
            }
        } else {
            Write-Host "Device is not in Google ZTE portal" -ForegroundColor Red
            $deviceZTEStatus = "False" 
        }
        New-Variable -Name "deviceZTEStatusPrep$objectNumber" -Value "$deviceZTEStatus"
        Write-Host "--------------------------------------------------------------------------------------------------------------------" -ForeGroundColor DarkGray
    }
} catch {
    Write-Host "Failed to parse device groups" -ForegroundColor Red
    exitScript
}

## My cat, Nova, says meeeww
## Gather device serial number
$input = Read-Host "Please input a device number (Example: '1')"
$input = $input -replace '(^\s+|\s+$)','' -replace '\s+',' '
if ($input -like ""){
    Write-Host "Invalid input"
    exitScript
}
Write-Host ""
Write-host "Looking for matching device objects..." -ForegroundColor Yellow
## Prepare Variables
try {
    $deviceObjectIDFinal = Get-Variable "deviceObjectID$input" -ValueOnly
    $deviceSerialFinal = Get-Variable "deviceSerial$input" -ValueOnly
    $deviceEntraIDFinal = Get-Variable "deviceEntraID$input" -ValueOnly
    $deviceManufacturerFinal = Get-Variable "deviceManufacturer$input" -ValueOnly
    $deviceModelFinal = Get-Variable "deviceModel$input" -ValueOnly
    $deviceModelFinal = $deviceModelFinal.ToLower()
    $deviceIMEIFinal = Get-Variable "deviceIMEI$input" -ValueOnly
    $deviceZTEStatusFinal = Get-Variable "deviceZTEStatusPrep$input" -ValueOnly
} catch {
    Write-Host "Failed to parse device information" -ForegroundColor Red
    exitScript
}

## If device is not in ZTE Portal, error out
if ($deviceZTEStatusFinal -like "*False*"){
    Write-Host "Device is not in Google ZTE portal. Cannot reassign Zero touch configuration." -ForeGroundColor Red
    exitScript
}

## Parse configs
try { ## Retrieve Configs
    $AuthToken = Get-Content $PSScriptRoot"\temp\accessToken.txt"
    $requestUri = "https://androiddeviceprovisioning.googleapis.com/v1/customers/$customerNumber/configurations"
    Invoke-RestMethod -Headers @{Authorization = "Bearer $AuthToken"} -Uri "$requestUri" -Method GET -ContentType 'application/json' | ConvertTo-JSON | Out-File $PSScriptRoot"\temp\availableConfigs.json"
    $parsedConfigs = Get-Content -Path $PSScriptRoot"\temp\availableConfigs.json" | ConvertFrom-Json
    $configNumber = 0
    do {
        $configName = $parsedConfigs.configurations[$configNumber] | Select-Object -ExpandProperty configurationName
        $configNumber++
    } While ($configName -notlike "")
    $finalCount = $configNumber - 1
    Write-Host "There are $finalCount configurations available:"
    $configNumber = 0
    1..$finalCount | % {
        $configName = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationName
        $tempName = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationName
        $tempName = "$tempName".Split(".")
        $shortenedConfigName = "$tempName".split()[0]
        $shortenedConfigName = "$shortenedConfigName".ToLower()
        $configId = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationId
        $shortenedConfigName = $shortenedConfigName -replace '(^\s+|\s+$)','' -replace '\s+',' '
        $configName = $configName -replace '(^\s+|\s+$)','' -replace '\s+',' '
        New-Variable "configurationNumber$configNumber" -Value @("[$configNumber]", $shortenedConfigName, $configName, $configId)
        $configArray = Get-Variable -Name "configurationNumber$configNumber" -ValueOnly
        if ($configArray -like "*Unauthorized*"){
            Write-Host $configArray[0,2] -ForegroundColor Red
        } else {
            Write-Host $configArray[0,2] -ForegroundColor Yellow
        }
        $configNumber++
    }
    $finalCount = $finalCount - 1
    $selectedConfig = Read-Host "Select a configuration (0 - $finalCount)"
    $configSelected = Get-Variable -Include "configurationNumber$selectedConfig" -ValueOnly
    write-host "Selected configuration:"$configSelected[2]""
    $updatedConfig = $configSelected[3]
} catch {
    Write-Host "Failed to parse Zero touch configurations" -ForegroundColor Red
    exitScript
}

## My cat, Simon, says mew

## Re-assign device workflow
try {
    $AuthToken = Get-Content $PSScriptRoot"\temp\accessToken.txt"
    $requestUri = "https://androiddeviceprovisioning.googleapis.com/v1/customers/$customerNumber/devices:applyConfiguration"
    if ("$deviceIMEIFinal" -like $NULL ) {
        Write-Host "Device is WiFi-only. Using device identifiers" -ForegroundColor Yellow
$jsonBody = @"
{
  "device": {
      "deviceIdentifier": {
        "model": "$deviceModelFinal", 
        "serialNumber": "$deviceSerialFinal", 
        "deviceType": "DEVICE_TYPE_ANDROID", 
        "manufacturer": "$deviceManufacturerFinal"
      } 
  },
  "configuration": "customers/$customerNumber/configurations/$updatedConfig"
}
"@
} elseif ("$deviceIMEIFinal" -notlike $NULL ) {
$jsonBody = @"
{
  "device": {
      "deviceIdentifier": { 
        "imei": "$deviceIMEIFinal", 
        "deviceType": "DEVICE_TYPE_ANDROID"
      } 
  },
  "configuration": "customers/$customerNumber/configurations/$updatedConfig"
}
"@   
}
    Invoke-RestMethod -Headers @{Authorization = "Bearer $AuthToken"} -Uri "$requestUri" -Method POST -Body "$jsonBody" -ContentType 'application/json'
    Write-Host "Successfully applied the "$configSelected[2]" zero-touch configuration to: $deviceSerialFinal" -Foreground Green
    Write-Host ""
} catch {
    Write-Host "Failed to send POST to Google API. This device may not be in the Google ZTE portal. Please verify" -ForegroundColor Red
    exitScript
}

## Wipe Device Workflow
Write-host "Preparing to send remote wipe command to device: $deviceSerialFinal" -ForegroundColor Yellow
do {
    $remoteWipe = Read-Host "Would you like to delete (wipe) this device from Intune? (Y/N)"
} until (($remoteWipe -like "*Y*") -or ($remoteWipe -like "*N*"))
if ($remoteWipe -like "*Y*") {
    write-host "Are you ready to wipe device $deviceSerialFinal" -ForegroundColor Red
    do {
        write-host ""
        $confirm = read-host "Type 'delete' to remove this device ($deviceObjectIDFinal) from Intune"
    } Until ($confirm -like "*delete*")
    Write-Host ""
    try {   ## Remove Device from Intune
        Remove-MgDeviceManagementManagedDevice -ManagedDeviceId "$deviceObjectIDFinal"
        Write-Host "Device ($deviceObjectIDFinal) deleted from Intune (this will wipe the device during it's next sync cycle)" -ForegroundColor Yellow
    } catch {

        Write-Host "Failed to delete device from Intune. Device was not deleted from Entra ID" -ForegroundColor Red
    }
    try {   ## Delete AAD Object
        Remove-AzureADDevice -ObjectId "$deviceEntraIDFinal"
        Write-Host "Device ($deviceEntraIDFinal) deleted from Entra ID" -ForegroundColor Yellow
    } catch {
        Write-Host "Failed to delete device from Entra ID. Device was deleted from Intune (typically, Intune deletes the AAD record)" -ForegroundColor Red
    }
} else {
    Write-Host "Please note: this device is a locked down state. Tablet will have no functionality for the end users."
    }
Write-Host ""


###############################################################################################################
} elseif ($selection -like "2"){
    Write-Host "Preparing to 'reassign' devices" -ForeGroundColor Gray
## Retrieve Unauthorized Device Group Members
try {
    $devicesInGroup = Get-MgGroupMember -GroupId "$zeroTouchBroadGroup" | Select-Object -Property ID
    $formattedDevicesInGroup = $devicesInGroup.Id

    ## Check if any devices are in the group (just looks for a hyphen because all devices have them in their ID)
    if ($formattedDevicesInGroup -notlike "*-*") {
        write-host ""
        write-host "There are no Zero-touch devices enrolled in Intune!" -ForegroundColor Green
        write-host ""
        $DisconnectGraph = Disconnect-MgGraph
        $DisconnectEntraID = Disconnect-AzureAD
        Remove-Item $PSScriptRoot"\temp" -Recurse -Force
        exit 0
    }

    ## Prepare array
    $deviceNumber = 0
    $objectNumber = 0

    ## Let's see what we have
    Write-Host "--------------------------------------------------------------------------------------------------------------------" -ForeGroundColor DarkGray
    write-host "Devices in $zeroTouchBroadGroupName :" -ForeGroundColor Yellow
} catch {
    Write-Host "Failed to obtain device group members" -ForegroundColor Red
    exitScript
}


# Parse the available configs again
$parsedConfigs = Get-Content -Path $PSScriptRoot"\temp\availableConfigs.json" | ConvertFrom-Json

## Show each item in group
try {
    foreach ($device in $($formattedDevicesInGroup -split "`r`n")) {
        write-host ""
        $deviceObjectID = Get-AzureADDevice -ObjectId "$device" | Select-Object -Property DeviceId
        $formattedObjectID = $deviceObjectID.DeviceId
        $deviceObject = Get-MgDeviceManagementManagedDevice -Filter "contains(AzureAdDeviceId,'$formattedObjectId')"
        $objectNumber +=1
        $deviceNumber +=1
        $deviceSerial = $deviceObject.SerialNumber
        $deviceManufacturer = $deviceObject.Manufacturer
        $deviceModel = $deviceObject.Model
        $deviceImei = $deviceObject.IMEI
        New-Variable -Name "deviceObjectID$objectNumber" -Value "$formattedObjectID"
        New-Variable -Name "deviceEntraID$objectNumber" -Value "$device"
        New-Variable -Name "deviceSerial$objectNumber" -Value "$deviceSerial"
        New-Variable -Name "deviceModel$objectNumber" -Value "$deviceModel"
        New-Variable -Name "deviceManufacturer$objectNumber" -Value "$deviceManufacturer"
        New-Variable -Name "deviceIMEI$objectNumber" -Value "$deviceIMEI"
        Write-Host "--------------------------------------------------------------------------------------------------------------------" -ForeGroundColor DarkGray
        write-host "Device $deviceNumber" -ForegroundColor Green
        $displayObject = $deviceObject | Format-Table SerialNumber, EnrolledDateTime, LastSyncDateTime, ComplianceState -Autosize | Out-String
        write-host "$displayObject" -ForegroundColor Cyan
        if (($parsedDevices -like "*$deviceSerial*") -or ($parsedDevices -like "*$deviceIMEI*")) {
            if ($deviceIMEI -notlike $NULL) {
                $deviceInfo = select-string -path $PSScriptRoot"\temp\parsedDevices.json" -pattern "$deviceIMEI" -Context 3 | Out-File $PSScriptRoot"\temp\tempDevice.json"
            } else {
                $deviceInfo = select-string -path $PSScriptRoot"\temp\parsedDevices.json" -pattern "$deviceSerial" -Context 3 | Out-File $PSScriptRoot"\temp\tempDevice.json"
            }
            $configurationName = Get-Content $PSScriptRoot"\temp\tempDevice.json" -tail 4 | Out-String
            if ($configurationName -notlike "*customers/*" ){
                $configurationName = "Unknown"
            } else {
                $configurationName = $configurationName -replace '(^\s+|\s+$)','' -replace '\s+',' '
                $configurationName = $configurationName.substring($configurationName.length - 15)
                $configurationName = $configurationName -replace "[^0-9]" , ''
            }
            $configNumber = 0
            $parsedConfigs = Get-Content -Path $PSScriptRoot"\temp\availableConfigs.json" | ConvertFrom-Json
            do {
                $configName = $parsedConfigs.configurations[$configNumber] | Select-Object -ExpandProperty configurationName
                $configNumber++
            } While ($configName -notlike "")
            $finalCount = $configNumber - 1
            $configNumber = 0
            1..$finalCount | % {
                $configName = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationName
                $tempName = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationName
                $configId = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationId
                $shortenedConfigName = $shortenedConfigName -replace '(^\s+|\s+$)','' -replace '\s+',' '
                $configName = $configName -replace '(^\s+|\s+$)','' -replace '\s+',' '
                New-Variable "configurationNumberTemp$configNumber" -Value @($configName, $configId)
                $configArrayTemp = Get-Variable -Name "configurationNumberTemp$configNumber" -ValueOnly
                $configNumber++
                $allConfigs = (Get-Variable -Name "configurationNumberTemp*" -ValueOnly) | Out-File $PSScriptRoot"\temp\allConfigsTemp.json" -Append
                Remove-Variable -Name "configurationNumberTemp*"
            }
            $finalCount = $finalCount - 1
            $allConfigs = Get-Content -Path $PSScriptRoot"\temp\allConfigsTemp.json"
            if ("$allConfigs" -like "*$configurationName*") {
                $matchingConfig = ($allConfigs | Select-String -Pattern "$configurationName"-Context 1,0 ) | Out-File $PSScriptRoot"\temp\tempConfig.json"
                $matchingConfig = Get-Content $PSScriptRoot"\temp\tempConfig.json" -first 2 | Out-String
                $matchingConfig = $matchingConfig -replace '(^\s+|\s+$)','' -replace '\s+',' '
                if ($matchingConfig -like "*Unauthorized*") {
                    $deviceZTEStatus = "Unauthorized"
                    Write-Host "Zero-touch Configuration: $matchingConfig" -ForeGroundColor Green
                    $deviceZTEStatus = "Unauthorized"
                } elseif ($matchingConfig -like "*AMR*") {
                    Write-Host "Zero-touch Configuration: $matchingConfig" -ForeGroundColor Red
                    $deviceZTEStatus = "Yes"
                    $fleetMgmt = "Yes"
                } else {
                    Write-Host "Zero-touch Configuration: $matchingConfig" -ForeGroundColor Red
                    $deviceZTEStatus = "Yes"
                }
            } else {
                write-host "Zero-touch Configuration: Enterprise Default" -ForeGroundColor Yellow
                $deviceZTEStatus = "Yes"
            }
        } else {
            Write-Host "Device is not in Google ZTE portal" -ForegroundColor Red
            $deviceZTEStatus = "False" 
        }
        New-Variable -Name "deviceZTEStatusPrep$objectNumber" -Value "$deviceZTEStatus"
        New-Variable -Name "matchingConfig$objectNumber" -Value "$matchingConfig"
        Write-Host "--------------------------------------------------------------------------------------------------------------------" -ForeGroundColor DarkGray
    }
} catch {
   Write-Host "Failed to parse device groups" -ForegroundColor Red
   exitScript
}

## Gather device serial number
$input = Read-Host "Please input a device number (Example: '1')"
$input = $input -replace '(^\s+|\s+$)','' -replace '\s+',' '
if ($input -like ""){
    Write-Host "Invalid input"
    exitScript
}
Write-Host ""

## Prepare Variables
try {
    $deviceObjectIDFinal = Get-Variable "deviceObjectID$input" -ValueOnly
    $deviceSerialFinal = Get-Variable "deviceSerial$input" -ValueOnly
    $deviceEntraIDFinal = Get-Variable "deviceEntraID$input" -ValueOnly
    $deviceManufacturerFinal = Get-Variable "deviceManufacturer$input" -ValueOnly
    $deviceModelFinal = Get-Variable "deviceModel$input" -ValueOnly
    $deviceModelFinal = $deviceModelFinal.ToLower()
    $deviceIMEIFinal = Get-Variable "deviceIMEI$input" -ValueOnly
    $deviceZTEStatusFinal = Get-Variable "deviceZTEStatusPrep$input" -ValueOnly
    if ($deviceZTEStatusFinal -notlike "*False*" ){
        $matchingConfigFinal = Get-Variable "matchingConfig$input" -ValueOnly
    }
} catch {
    Write-Host "Failed to parse device information" -ForegroundColor Red
    exitScript
}

## If device is not in ZTE Portal, error out
if ($deviceZTEStatusFinal -like "*False*"){
    Write-Host "Device is not in Google ZTE portal. Cannot reassign Zero touch configuration." -ForeGroundColor Red
    exitScript
} elseif ( ($deviceZTEStatusFinal -like "*Unauthorized*") -or ($deviceZTEStatusFinal -like "*Yes*") ){
    Write-Host "Device is already assigned to the $matchingConfigFinal zero touch configuration." -ForeGroundColor Red
    do {
        $reassignDevice = Read-Host "Would you like to re-assign this device ($deviceSerialFinal) to another configuration? (Y/N)"
    } until (($reassignDevice -like "*Y*") -or ($reassignDevice -like "*N*"))
    if ($reassignDevice -like "*Y*") {
        try { ## Retrieve Configs
            $reassignedDevice = "True"
            $AuthToken = Get-Content $PSScriptRoot"\temp\accessToken.txt"
            $requestUri = "https://androiddeviceprovisioning.googleapis.com/v1/customers/$customerNumber/configurations"
            Invoke-RestMethod -Headers @{Authorization = "Bearer $AuthToken"} -Uri "$requestUri" -Method GET -ContentType 'application/json' | ConvertTo-JSON | Out-File $PSScriptRoot"\temp\availableConfigs.json"
            $parsedConfigs = Get-Content -Path $PSScriptRoot"\temp\availableConfigs.json" | ConvertFrom-Json
            $configNumber = 0
            do {
                $configName = $parsedConfigs.configurations[$configNumber] | Select-Object -ExpandProperty configurationName
                $configNumber++
            } While ($configName -notlike "")
            $finalCount = $configNumber - 1
            Write-Host "There are $finalCount configurations available:"
            $configNumber = 0
            1..$finalCount | % {
                $configName = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationName
                $tempName = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationName
                $tempName = "$tempName".Split(".")
                $shortenedConfigName = "$tempName".split()[0]
                $shortenedConfigName = "$shortenedConfigName".ToLower()
                $configId = $parsedConfigs.configurations["$configNumber"] | Select-Object -ExpandProperty configurationId
                $shortenedConfigName = $shortenedConfigName -replace '(^\s+|\s+$)','' -replace '\s+',' '
                $configName = $configName -replace '(^\s+|\s+$)','' -replace '\s+',' '
                New-Variable "configurationNumber$configNumber" -Value @("[$configNumber]", $shortenedConfigName, $configName, $configId)
                $configArray = Get-Variable -Name "configurationNumber$configNumber" -ValueOnly
                if ($configArray -like "*Unauthorized*"){
                    Write-Host $configArray[0,2] -ForegroundColor Green
                } else {
                    Write-Host $configArray[0,2] -ForegroundColor Yellow
                }
                $configNumber++
            }
            $finalCount = $finalCount - 1
            $selectedConfig = Read-Host "Select a configuration (0 - $finalCount )"
            $configSelected = Get-Variable -Include "configurationNumber$selectedConfig" -ValueOnly
            write-host "Selected configuration:"$configSelected[2]""
            $updatedConfig = $configSelected[3]
        } catch {
            Write-Host "Failed to reassign device: $deviceSerialFinal" -ForegroundColor Red
            exitScript
        }
    } else {
        if ($reassignedDevice -like "True") {
            $updatedConfig = $configSelected[3]
            $selectedName = $configSelected[2]
        } else {
            $updatedConfig = "$unauthorizedConfigId"
            $selectedName = "Unauthorized"
        }
        exitScript
    }
}
## Re-assign device workflow
try {
    $AuthToken = Get-Content $PSScriptRoot"\temp\accessToken.txt"
    $requestUri = "https://androiddeviceprovisioning.googleapis.com/v1/customers/$customerNumber/devices:applyConfiguration"
    if ("$deviceIMEIFinal" -like $NULL ) {
        Write-Host "Device is WiFi-only. Using device identifiers" -ForegroundColor Yellow
$jsonBody = @"
{
  "device": {
      "deviceIdentifier": {
        "model": "$deviceModelFinal", 
        "serialNumber": "$deviceSerialFinal", 
        "deviceType": "DEVICE_TYPE_ANDROID", 
        "manufacturer": "$deviceManufacturerFinal"
      } 
  },
  "configuration": "customers/$customerNumber/configurations/$updatedConfig"
}
"@
} elseif ("$deviceIMEIFinal" -notlike $NULL ) {
    Write-Host "Device is cellular. Using IMEI" -ForegroundColor Yellow
$jsonBody = @"
{
  "device": {
      "deviceIdentifier": { 
        "imei": "$deviceIMEIFinal", 
        "deviceType": "DEVICE_TYPE_ANDROID"
      } 
  },
  "configuration": "customers/$customerNumber/configurations/$updatedConfig"
}
"@
}
    Invoke-RestMethod -Headers @{Authorization = "Bearer $AuthToken"} -Uri "$requestUri" -Method POST -Body "$jsonBody" -ContentType 'application/json'
    Write-Host "Successfully assigned the "$configSelected[2]" configuration to: $deviceSerialFinal" -Foreground Green
    Write-Host ""

## If it is fleet mgmt, assign it to a BA
if ($fleetMgmt -notlike $NULL) {
    do {
        $fleetManage = Read-Host "This device is assigned to AMR fleet management. Would you like to assign it to a plant? (Y/N)"
    } until (($fleetManage -like "*Y*") -or ($fleetManage -like "*N*"))
    if ( $fleetManage -like "*Y*" ) {
        $plantNumber = Read-Host "Please enter a plant number"
        try {
            # Get Group
            $groupInfo = Get-AADGroup -Filter "displayname eq '$amrGroupName-$plantNumber'"
            $groupId = $groupInfo.GroupId
        } catch {
            write-host "Failed to enumerate plant group"
            exitScript
        }

        try {
            ## Get device info
            write-host "Device is: $deviceEntraIDFinal"
            $device = Get-AzureADDevice -ObjectId $deviceEntraIDFinal
        } catch {
            Write-Host "Failed to retreive device Id"
            exitScript
        }

        try {
            Add-AzureADGroupMember -ObjectId $groupInfo.GroupId -RefObjectId $device.ObjectId
        } catch {
            write-host "Failed to add device ($deviceEntraIDFinal) to group $groupInfo.GroupId"
            exitScript
        }
    } else {
        Write-Host "Note: This device will need to be assigned to a plant number before it is useable." -ForegroundColor Red
    }
}

    do {
        $renameDevice = Read-Host "Would you like to rename this device ($deviceSerialFinal) (Y/N)?"
    } until (($renameDevice -like "*Y*") -or ($renameDevice -like "*N*"))
    if ($renameDevice -like "*Y*"){
        $deviceObject = Get-MgDeviceManagementManagedDevice -Filter "contains(serialNumber,'$deviceSerialFinal')" | Sort-Object -Property EnrolledDateTime -Descending | Sort-Object -Property SerialNumber -Unique
    try {
        Write-host ""

        ## New Device Name
        $newName = Read-Host "Please enter the new device name"
        Write-host ""
        Write-host "Renaming device to: $newName" -ForegroundColor Yellow
        Set-MgBetaDeviceManagementManagedDeviceName -ManagedDeviceId $deviceObject.Id -DeviceName "$newName"
        Write-host "Renamed device to '$newName'" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-host "Failed to find matching device object."
        exitScript
    }
    }
} catch {
    Write-Host "Failed to send POST to Google API" -ForegroundColor Red
    exitScript
}

do {
    $deleteDevice = Read-Host "Would you like to wipe/factory reset this device ($deviceSerialFinal) (Y/N)?"
} until (($deleteDevice -like "*Y*") -or ($deleteDevice -like "*N*"))
if ( $deleteDevice -like "*Y*" ) {
    write-host "Are you ready to wipe device $deviceSerialFinal" -ForegroundColor Red
    do {
        write-host ""
        $confirm = read-host "Type 'delete' to remove this device ($deviceObjectIDFinal) from Intune"
    } Until ($confirm -like "*delete*")
    try {
        Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $deviceObjectIDFinal
        Write-Host "Device ($deviceObjectIDFinal) deleted from Intune (this will wipe the device during the next sync cycle)" -ForegroundColor Yellow
    } catch {
        Write-Host "Failed to delete device from Intune. Device was not deleted from Entra ID" -ForegroundColor Red
    }
    try {
        Remove-AzureADDevice -ObjectId $deviceEntraIDFinal
        Write-Host "Device ($deviceEntraIDFinal) deleted from Entra ID" -ForegroundColor Yellow
    } catch {
        Write-Host "Failed to delete device from Entra ID. Device was deleted from Intune (typically, Intune deletes the AAD record)" -ForegroundColor Red
    }
}
} else {
    Write-Host "Improper selection" -ForeGroundColor Red
    exitScript
}
###############################################################################################################

## Put the show on the road.
Write-Host ""
Write-Host "Please contact End User Computing ASAP if you believe you have misused this tool" -ForeGroundColor Yellow
Write-Host ""
Write-Host ""
Write-Host ""
Read-Host "Press any key to exit"

## Remove Files
exitScript
