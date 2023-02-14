#!/bin/bash

###################################################################################
## Declare Variables
###################################################################################
json="/usr/local/nudge/nudge.json"
launchagent="/Library/LaunchAgents/com.github.macadmins.Nudge.plist"
requiredInstallationFutureTime="T00:00:00Z"
leadTimeInDays="31"
loggedInUser=$(stat -f%Su /dev/console)
currentDate=$(date +%Y-%m-%d)

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
}

###################################################################################
# Create a Nudge Event for each major release, and write them to nudge.json
###################################################################################
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
	scriptResult+="Updated nudge.json! "
	echo $scriptResult

	echo '	],
    "userExperience": {
        "allowGracePeriods": true,
        "allowLaterDeferralButton": true,
        "allowUserQuitDeferrals": false,
        "allowedDeferrals": 10,
        "gracePeriodInstallDelay": 23,
        "gracePeriodLaunchDelay": 1,
        "gracePeriodPath": "/private/var/db/.AppleSetupDone",
        "imminentRefreshCycle": 600,
        "imminentWindowTime": 36,
    },
    "userInterface": {
        "fallbackLanguage": "en",
        "forceFallbackLanguage": false,
        "forceScreenShotIcon": true,
        "iconDarkPath": "/usr/local/nudge/logo_dark.png",
        "iconLightPath": "/usr/local/nudge/logo_light.png",
        "screenShotDarkPath": "/usr/local/nudge/ss_dark.png",
        "screenShotLightPath": "/usr/local/nudge/ss_light.png",
        "showDeferralCount": true,
        "simpleMode": true,
        "updateElements": [
        {
            "_language": "en",
            "actionButtonText": "Update",
            "informationButtonText": "About this update",
            "mainContentHeader": "Your device will restart during this update",
            "mainContentNote": "Important Notes",
            "mainContentSubHeader": "Updates can take around 30 minutes to complete",
            "mainContentText": "An up-to-date device is required to ensure that CIT can effectively protect your Mac.\n\n\nTo begin updating macOS, simply click on the 'Update Device' button above and follow the provided steps.",
            "mainHeader": "Your device requires a macOS update",
            "subHeader": "A friendly reminder from Calvin Information Technology"
        }
        ]
    }
    }
    
    ' >> $json
}
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

## Unused function. Will push the latest available macOS version. Can be buggy for new releases
function nudgeLatest {
	majorVersionName="macOS"
	majorVersionNumber="default"
	majorVersionPatchID="macOS"

	defineNudgeEvent

	osVersionLatest="$nudgeEventData"
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
		<string>-json-url</string>
		<string>"file:///usr/local/nudge/nudge.json"</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StartCalendarInterval</key>
	<array>
		<dict>
			<key>Hour</key>
			<integer>8</integer>
			<key>Minute</key>
			<integer>15</integer>
		</dict>
		<dict>
			<key>Hour</key>
			<integer>16</integer>
			<key>Minute</key>
			<integer>45</integer>
		</dict>
	</array>
</dict>
</plist>
' > $launchagent
}

###################################################################################
## Finish Up
###################################################################################
function finishUp {
	sudo chmod 644 $launchagent
	sudo chmod 755 $json
	if who | grep -q console; then

		# get the logged in user's uid
		LOGGED_IN_UID=$(ls -ln /dev/console | awk '{ print $3 }')

		# use launchctl asuser to run launchctl in the same Mach bootstrap namespace hierachy as the Finder
		launchctl asuser "$LOGGED_IN_UID" launchctl unload $launchagent
		launchctl asuser "$LOGGED_IN_UID" launchctl load $launchagent
	fi
}

###################################################################################
## Perform functions
###################################################################################
nudgeBigSur
nudgeMonterey
nudgeVentura
#nudgeLatest | Not necessary at the current time
createNudgeFile
createLaunchAgent
finishUp

exit 0