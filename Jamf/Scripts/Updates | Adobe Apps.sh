#!/bin/bash
###################################################################################
###                                                                             ###
###         This script runs every week on the weekend (Saturdays @ 12am).      ###
###                                                                             ###
###         It updates all available Adobe apps on the device.                  ###
###                                                                             ###
###         Jamf policy variable $4 defines whether you want to "install" or    ###
###         "download the updates."                                             ###
###                                                                             ###
###                                                                             ###
###													                            @bryanmillerr | 2023		###
###																				                                      ###
###################################################################################


###################################################################################
## Declare functions
###################################################################################
function declareVariables {
  adobeRUM="/usr/local/bin/RemoteUpdateManager"
  adobeCC="/Applications/Adobe Creative Cloud/Adobe Creative Cloud"
  date=$(date)
  log="/var/log/AdobeUpdates.log"

  # Jamf Variable
  if [[ $4 == 'install' ]]; then
    action="--action=install"
  elif [[ $4 == 'download' ]]; then
    action="--action=download"
  else
    echo "No action specified. Exiting..."
    exit 1
  fi

  ## Make the Jamf log look pretty <3
	sudo touch $log
	sudo chmod 755 $log
  echo ""
	echo "###################################################################################"
	echo ""
	echo "Execution time: $date"
}

function preRunCheck {
  ## Check for Adobe installation
  if [[ -f $adobeCC ]]; then
    echo "Adobe CC installation verified. Continuing..."
  else
    echo "Adobe CC not installed! Exiting..."
		## Send logs to Jamf
		jamfLog=$(sed -ne "/$date/,$ p" $log)
		echo "$jamfLog" 1>&3
		exit 1
  fi

  ## Check for Adobe RUM installation
  if [[ -f $adobeRUM ]]; then
    echo "Starting Adobe RemoteUpdateManger..."
  else
    echo "Adobe RemoteUpdateManager not found."
		## Send logs to Jamf
		jamfLog=$(sed -ne "/$date/,$ p" $log)
		echo "$jamfLog" 1>&3
		exit 1
  fi
}

function updateAdobeApps {
  $adobeRUM $action
  exitCode="0"
}

###################################################################################
## Finish Up
###################################################################################
##	Write to log
exec 3>&1 1>>$log 2>&1

## Do the functions
declareVariables
preRunCheck
updateAdobeApps

## Send Jamf some logs
jamfLog=$(sed -ne "/$date/,$ p" $log)
echo "$jamfLog" 1>&3

exit $exitCode