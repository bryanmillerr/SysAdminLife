#!/bin/bash
###################################################################################
###                                                                             ###
###         This script runs every week on the weekend (Saturdays @ 12am).      ###
###                                                                             ###
###         It updates all available Adobe apps on the device.                  ###
###                                                                             ###
###         The two Jamf policy variables are the following:                    ###
###             $4 - Action (install/download)                                  ###
###             $5 - Applications (seperated by comma). Use "all" to update all ###
###                                                                             ###
###                                                                             ###
###							@bryanmillerr | 2023	###
###                                                                             ###
###################################################################################

## Customization \ refer to https://helpx.adobe.com/enterprise/kb/apps-deployed-without-base-versions.html
log="/var/log/AdobeUpdates.log" ## Customize debug log location

###################################################################################
function startLogging {
  exec 3>&1 1>>$log 2>&1 ##	Write to log
  sudo touch $log
  sudo chmod 755 $log
  echo ""
  echo "###################################################################################"
  echo ""
  echo "Execution time: $date"
}

###################################################################################
## Variables
###################################################################################
function declareVariables {
  adobeRUM="/usr/local/bin/RemoteUpdateManager"
  adobeCC="/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Desktop App.app"
  date=$(date)
  if [[ $4 == 'install' ]]; then ## Jamf variable to install
    action="--action=install"
  else
    action="--action=download"
  fi

  if [[ $5 == 'all' ]]; then ## Jamf variable for apps
    selectedApps=""
  else
    selectedApps="$5"
  fi

  if [[ $selectedApps == "" ]]; then ## Logic for selectedApps
    installArgument="$action"
  else
    installArgument="$action $selectedApps"
  fi
  
}

###################################################################################
## Pre-requisite check
###################################################################################
function preRunCheck {
  if [[ -e $adobeCC ]]; then   ## Check for Adobe installation
    echo "Adobe CC installation verified. Continuing..." 1>&3
  else
    echo "Adobe CC not installed! Exiting..." 1>&3
		## Send logs to Jamf
		jamfLog=$(sed -ne "/$date/,$ p" $log)
		echo "$jamfLog" 1>&3
		exit 1
  fi

  if [[ -f $adobeRUM ]]; then   ## Check for Adobe RUM installation
    echo "Starting Adobe RemoteUpdateManger..." 1>&3
  else
    echo "Adobe RemoteUpdateManager not found." 1>&3
		## Send logs to Jamf
		jamfLog=$(sed -ne "/$date/,$ p" $log)
		echo "$jamfLog" 1>&3
		exit 1
  fi
}

###################################################################################
function updateAdobeApps {
  $adobeRUM $arguments
}

function finishUp {
  jamfLog=$(sed -ne "/$date/,$ p" $log) ## Send Jamf some logs
  echo "$jamfLog" 1>&3
}

###################################################################################
startLogging
declareVariables
preRunCheck
updateAdobeApps
finishUp

exit 0
