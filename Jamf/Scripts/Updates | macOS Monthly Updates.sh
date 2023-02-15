#!/bin/bash

###################################################################################
###																				###
###			This script is how push managed macOS updates to FacStf.			###
###			It queries the jamf-patch libary for the available macOS versions,	###
###			and sets the latest version to 'required' with a 30 days as time.	###
###																				###
###			Much of the configuration is done via Jamf policy variables. The	###
###			variables are defined like this:									###
###																				###
###			$4 = Simple Mode (true/false)										###
###			$5 = Allow Custom Deferral Options (true/false)						###
###			$6 = Show Deferrals (true/false)									###
###			$7 = Allowed Deferrals (specify number. Default: unlimited)			###
###			$8 = Secondary Deferral minimum (specify a number. Default: 20)		###
###			$9 = Initial Refresh Cycle (specify a number in seconds)			###
###			$10 = Approaching Refresh Cycle (specify a number in seconds)		###
###			$11 = Imminent Refresh Cycle (specify a number in seconds)			###
###																				###
###													Bryan Miller | 2023			###
###																				###
###################################################################################

###################################################################################
## Declare Variables (please make sure these are correct for your environment)
###################################################################################
json="/Library/Preferences/com.github.macadmins.Nudge.json"
launchagent="/Library/LaunchAgents/com.github.macadmins.Nudge.plist"
requiredInstallationFutureTime="T00:00:00Z" ## Specify a specific time in the day for required install
leadTimeInDays="31" ## How many days after the script is run do you want to set the required install date

## LaunchAgent config
time1Hour="8"
time1Minutes="15"
time2Hour="16"
time2Minutes="15"
randomDelay='true' ## true/false
randomDelaySeconds="600"

## Pre-run checks
nudgeApp="/Applications/Utilities/Nudge.app"
brandingLocation="/usr/local/nudge/logo_light.png" ## One of your branding assets. For pre-run checks

## Nudge branding
companyName="" ## Your department, etc. (eg: Princeton Information Technology)
mainContentText="An up-to-date device is required to ensure that IT can effectively protect your Mac.\n\n\nTo begin updating macOS, simply click on the 'Update' button above and follow the provided steps."
iconDarkPath="/usr/local/nudge/logo_dark.png"
iconLightPath="/usr/local/nudge/logo_light.png"
screenShotDarkPath="/usr/local/nudge/ss_dark.png"
screenShotLightPath="/usr/local/nudge/ss_light.png"

###################################################################################
## Define major releases. As of February 2023 | Big Sur, Ventura, Monterey
###################################################################################
function nudgeVentura {
	majorVersionName="macOS Ventura"
	majorVersionNumber="13"
	majorVersionPatchID="53E"

	defineNudgeEvent

	osVersionVentura="$nudgeEventData"
}

function nudgeMonterey {
	majorVersionName="macOS Monterey"
	majorVersionNumber="12"
	majorVersionPatchID="41F"

	defineNudgeEvent
	
	osVersionMonterey="$nudgeEventData"
}

function nudgeBigSur {
	majorVersionName="macOS Big Sur"
	majorVersionNumber="11"
	majorVersionPatchID="303"

	defineNudgeEvent

	osVersionBigSur="$nudgeEventData"
}

## Unused function. Will push the latest available macOS version. AKA Current Channel
function nudgeLatest {
	majorVersionName="macOS"
	majorVersionNumber="default"
	majorVersionPatchID="macOS"

	defineNudgeEvent

	osVersionLatest="$nudgeEventData"
}

###################################################################################
## Shared functions for each major release
###################################################################################
function setAboutUpdate {
	# Set the About Update URL for each major release
	if [[ "${majorVersionNumber}" == "11" ]] ; then 
		aboutUpdateURL="https://support.apple.com/en-us/HT211896" # What's new in the updates for macOS Big Sur
	elif [[ "${majorVersionNumber}" == "12" ]] ; then 
		aboutUpdateURL="https://support.apple.com/en-us/HT212585" # What's new in the updates for macOS Monterey
	elif [[ "${majorVersionNumber}" == "13" ]] ; then 
		aboutUpdateURL="https://support.apple.com/en-us/HT213268" # What's new in the updates for macOS Ventura
	else
		aboutUpdateURL="https://support.apple.com/en-us/HT201541" # Update macOS on Mac
	fi
	echo "Setting About Update URL for ${majorVersionName} to ${aboutUpdateURL}…"
}

function getPatchResults {
	# Get the latest release info from Jamf Patch
	jamfPatchResults=$(curl -s "https://jamf-patch.jamfcloud.com/v1/software/${majorVersionPatchID}")
}

function getLatestVersionNumber {
	# Get the latest version's version number, based on the Jamf Patch information
	latestVersionNumber=$( echo "$jamfPatchResults" | grep currentVersion | tr -d '"' | awk '{ print $2 }')
	
	echo "Latest version of ${majorVersionName} is ${latestVersionNumber}…"
}

function setRequiredInstallationDate {
	currentDate=$(date +%Y-%m-%d)
	# Get the latest version's release date, based on the Jamf Patch information
	latestVersionReleaseDate=$( echo "$jamfPatchResults" | grep lastModified | tr -d '"' | awk '{ print $2 }' | cut -c1-10)

	# Calculate the required installation date in the future, based upon the release date
	# …for macOS
	requiredInstallationFutureDate=$(date -j -v +${leadTimeInDays}d -f "%Y-%m-%d" "$currentDate" +%Y-%m-%d)

	# …for Linux
	# requiredInstallationFutureDate=$(date -d "+$leadTimeInDays days" -I)

	# Combine the date with the time for required installation
	requiredInstallationDate="$requiredInstallationFutureDate$requiredInstallationFutureTime"
	
	echo "Latest release date for ${majorVersionName} is ${latestVersionReleaseDate}, setting required installation date to ${requiredInstallationFutureDate}…"
	echo "" #Make the Jamf log look good :)
}

function defineNudgeEvent {
	setAboutUpdate
	getPatchResults
	getLatestVersionNumber
	setRequiredInstallationDate
	nudgeEventData="
		{
			\"aboutUpdateURL\": \"$aboutUpdateURL\",
			\"requiredInstallationDate\": \"$requiredInstallationDate\",
			\"requiredMinimumOSVersion\": \"$latestVersionNumber\",
			\"targetedOSVersionsRule\": \"$majorVersionNumber\"
		}"
}

###################################################################################
## Pre-run checks
###################################################################################
function preRunCheck {
	## Does Nudge.app exist?
	if [ ! -e $nudgeApp ]; then
		echo ""
		echo "Nudge.app not detected. Installing..."
		sudo jamf policy -event "nudgeframework"
		if [ -e $nudgeApp ]; then
			echo "Nudge successfully installed. Continuing..."
		else
			echo "Nudge.app failed to install! Exiting..."
			exit 1
		fi
	fi

	## Is the branding there?
	if [ ! -e $brandingLocation ]; then
		echo ""
		echo "Company branding not detected. Installing..."
		sudo jamf policy -event "nudgeframework"
		if [ -e $brandingLocation ]; then
			echo "Company branding successfully installed. Continuing..."
		else
			echo "Company branding failed to install! Exiting..."
			exit 1
		fi
	fi

}

#####################
## Jamf variables
#####################
if [[ $4 != 'false' ]]; then ## Simple mode
	simpleMode='true'
else
	simpleMode='false'
fi

if [[ $5 != 'false' ]]; then ## Allow custom deferral times? (other than Later)
	allowCustomDeferral='true'
else
	allowCustomDeferral='false'
fi

if [[ $6 != 'false' ]]; then ## Show deferral count
	showDeferrals='true'
else
	showDeferrals='false'
fi

if [[ $7 != '' ]]; then ## Allowed deferrals
	allowedDeferrals="$7"
	echo "Jamf policy specified $allowedDeferrals deferrals allowed."
else
	allowedDeferrals="100000"
	echo "No deferral amount specified. Defaulting to unlimited."
fi

if [[ $8 != '' ]]; then ## How many deferrals before "I understand" option before selecting "Later"
	secondaryDeferral="$8"
	echo "Jamf policy specified $secondaryDeferral deferrals allowed until "I understand" prompt starts."
else
	secondaryDeferral="20"
	echo "No deferral amount specified. Defaulting to 20."
fi

echo "" #Make the Jamf log look good :)

if [[ $9 != '' ]]; then ## Initial refresh cycle
	initialRefreshCycle="$9"
	echo "Setting initial refresh cycle to: $initialRefreshCycle"
else
	initialRefreshCycle='18000'
	echo "No initial refresh cycle setting specified. Defaulting to 18000 seconds."
fi

if [[ ${10} != '' ]]; then ## Approaching Refresh cycle (72 hours prior)
	approachingRefreshCycle="${10}"
	echo "Setting approaching refresh cycle to: $approachingRefreshCycle"
else
	approachingRefreshCycle='6000'
	echo "No approaching refresh cycle setting specified. Defaulting to 6000 seconds."
fi

if [[ ${11} != '' ]]; then ## Imminent Refresh cycle (36 hours prior)
	imminentRefreshCycle="${11}"
	echo "Setting imminent refresh cycle to: $imminentRefreshCycle"
else
	imminentRefreshCycle='6000'
	echo "No imminent refresh cycle setting specified. Defaulting to 600 seconds."
fi

echo "" #Make the Jamf log look good :)

###################################################################################
## Create JSON configuration. Edit below as needed.
###################################################################################
function createNudgeFile {
	cat <<-EOF > $json
    {
    "optionalFeatures": {
        "acceptableApplicationBundleIDs": [],
        "acceptableAssertionUsage": false,
        "acceptableCameraUsage": false,
        "acceptableScreenSharingUsage": false,
        "aggressiveUserExperience": true,
        "aggressiveUserFullScreenExperience": true,
        "asynchronousSoftwareUpdate": true,
        "attemptToBlockApplicationLaunches": false,
        "attemptToFetchMajorUpgrade": false,
        "blockedApplicationBundleIDs": [],
        "enforceMinorUpdates": true,
        "terminateApplicationsOnLaunch": false
    },
	EOF

echo '	"osVersionRequirements": [' >> $json
echo "${osVersionVentura},${osVersionMonterey},${osVersionBigSur}" >> $json
	scriptResult+="Updated $json "
	echo $scriptResult

	echo '	],
	"userExperience": {
		"allowGracePeriods": true,
		"allowLaterDeferralButton": true,
		"allowUserQuitDeferrals": '"$allowCustomDeferral"',
		"allowedDeferrals": '"$allowedDeferrals"',
		"allowedDeferralsUntilForcedSecondaryQuitButton": '"$secondaryDeferral"',
		"approachingRefreshCycle": '"$approachingRefreshCycle"',
		"approachingWindowTime": 72,
		"elapsedRefreshCycle": 300,
		"gracePeriodInstallDelay": 23,
		"gracePeriodLaunchDelay": 1,
		"gracePeriodPath": "/private/var/db/.AppleSetupDone",
		"imminentRefreshCycle": '"$imminentRefreshCycle"',
		"imminentWindowTime": 36,
		"initialRefreshCycle": '"$initialRefreshCycle"',
		"maxRandomDelayInSeconds": '$randomDelaySeconds',
		"noTimers": false,
		"nudgeRefreshCycle": 60,
		"randomDelay": '$randomDelay'
    },
    "userInterface": {
        "fallbackLanguage": "en",
        "forceFallbackLanguage": false,
        "forceScreenShotIcon": true,
        "iconDarkPath": "'$iconDarkPath'",
        "iconLightPath": "'$iconLightPath'",
        "screenShotDarkPath": "'$screenShotDarkPath'",
        "screenShotLightPath": "'$screenShotLightPath'",
        "showDeferralCount": '"$showDeferrals"',
        "simpleMode": '"$simpleMode"',
        "updateElements": [
        {
            "_language": "en",
            "actionButtonText": "Update",
            "informationButtonText": "About this update",
            "mainContentHeader": "Your device will restart during this update",
            "customDeferralDropdownText": "Dismiss",
            "mainContentNote": "Important Notes",
            "mainContentSubHeader": "Updates can take around 30 minutes to complete",
            "mainContentText": "'$mainContentText'",
            "mainHeader": "Your device requires a macOS update",
            "subHeader": "A friendly reminder from '$companyName'"
        }
        ]
    }
}
    
    ' >> $json
}

###################################################################################
## Write to LaunchAgent
###################################################################################
function createLaunchAgent {
echo '
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.github.macadmins.Nudge</string>
	<key>LimitLoadToSessionType</key>
	<array>
		<string>Aqua</string>
	</array>
	<key>ProgramArguments</key>
	<array>
		<string>/Applications/Utilities/Nudge.app/Contents/MacOS/Nudge</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StartCalendarInterval</key>
	<array>
		<dict>
			<key>Hour</key>
			<integer>'$time1Hour'</integer>
			<key>Minute</key>
			<integer>'$time1Minutes'</integer>
		</dict>
		<dict>
			<key>Hour</key>
			<integer>'$time2Hour'</integer>
			<key>Minute</key>
			<integer>'$time2Minutes'</integer>
		</dict>
	</array>
</dict>
</plist>
' > $launchagent

echo "Updated $launchagent"
}

###################################################################################
## Finish Up
###################################################################################
function finishUp {
	sudo chmod 644 $launchagent
	sudo chmod 755 $json
	if who | grep -q console; then
		## Retrieve the logged in user's UID
		LOGGED_IN_UID=$(ls -ln /dev/console | awk '{ print $3 }')
		launchctl asuser "$LOGGED_IN_UID" launchctl unload $launchagent
		launchctl asuser "$LOGGED_IN_UID" launchctl load $launchagent
	fi
}

###################################################################################
## Perform functions
###################################################################################
preRunCheck
nudgeBigSur
nudgeMonterey
nudgeVentura
#nudgeLatest | Not necessary at the current time
createNudgeFile
createLaunchAgent
finishUp

exit 0