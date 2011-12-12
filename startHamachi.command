#!/bin/bash -x
#    …/bash -x = debug

# Version: 0.1
# see README file

if [ "$1" = 'run' ]; then # run = set in launchd
	if [ -z "$HAMACHI_NETWORK" ]; then # Environment var is empty
		
		# Get directory from where this script is started (for the case where this script is started with a working directory that differs from where this file resides)
		
		SOURCE="${BASH_SOURCE[0]}"
		#while [ -h "$SOURCE" ] ; do SOURCE="$(readlink "$SOURCE")"; done # resolve all symlinks
		DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )" # detect directory where this file resides; also change working directory to source file directory
		[[ $DIR = '' ]] &&	$DIR='.'
		
		# Try to import the file containing user variables
		
		varfile="$DIR/startHamachiParams.sh"
		if [ -e $varfile ] && [ -f $varfile ] && [ -s $varfile ]; then # File does exist, is a file and that file is not empty 
			if grep -q 'HAMACHI_NETWORK=' $varfile; then # var exist
				. $varfile    # Load data file; same effect as "source data-file", but more portable.
			fi
		fi
		if [ -z "$HAMACHI_NETWORK" ]; then
			# Try to read hamachi network name from keychain		
			if security find-generic-password -l Hamachi|grep -q '    "acct"<blob>="'; then # There is a Hamachi entry, and it is not <NULL>
				HAMACHI_NETWORK=$(security find-generic-password -l Hamachi 2>&1 | grep -m 1 "acct" | cut -d \= -f 2 | cut -d \" -f 2 | sed 's|\\134|\\|g')
			fi
			
			if [ -z "$HAMACHI_NETWORK" ]; then
				echo 'Please edit "startHamachiParams.sh" to include a line like HAMACHI_NETWORK=MyHamachiNetworkName, for example with command'
				echo "\$ nano $varfile"
				echo 'or add a keychain item with Hamachi as its name and your Hamachi network name as its account name.'
				exit 3;
			else
				if [ -f $varfile ] && [ -s $varfile ] && grep -q 'HAMACHI_NETWORK=' $varfile; then
					sed 's;^\([^#].*\)HAMACHI_NETWORK=\(.*\);#\1HAMACHI_NETWORK=\2;' "$varfile" # Comment current HAMACHI_NETWORK environment vars in this file; -n = do not print finds; need to escape the parentheses that define a group
				fi
				echo "declare -r HAMACHI_NETWORK=$HAMACHI_NETWORK" >> $varfile # Append (latest line = final variable assignment)
			fi
		fi
	fi
	
	# (Re)start hamachi, login, go-online and join when applicable
	if ! ps -Ac|grep -q hamachi; then
		hamachi start
	fi
	if ! hamachi|grep -q 'status   : logged in'; then
		hamachi login
	fi
	if ! hamachi list|grep -q '* \['$HAMACHI_NETWORK; then
		if [ -n "$HAMACHI_NETWORK" ]; then # Variabele bestaat
			hamachi go-online $HAMACHI_NETWORK
		
			if ! hamachi list|grep -q '* \['$HAMACHI_NETWORK; then
		
				# Test password in keychain
				if security find-generic-password -l Hamachi|grep -q 'The specified item could not be found in the keychain.'; then
					echo "There is no password stored in your keychain with 'Hamachi' as its name."
					exit 2
				elif ! security find-generic-password -l Hamachi|grep -q 'class: "genp"'; then
					echo "There is no generic password stored in your keychain with 'Hamachi' as its name."
					exit 2	
				elif security find-generic-password -a $HAMACHI_NETWORK -l Hamachi|grep -q 'The specified item could not be found in the keychain.'; then
					echo "There is a Hamachi entry found in your keychain but its account does not match the network \"$network\" in this script."
					exit 2
				elif ! security find-generic-password -a $HAMACHI_NETWORK -l Hamachi|grep -q 'class: "genp"'; then
					echo "There is no generic password stored in your keychain with \"$network\" as its account."
					exit 2	
				fi
		
				# Get password from keychain and replace \134 with \
				password=$(security find-generic-password -a $HAMACHI_NETWORK -l Hamachi -g 2>&1 | grep -m 1 password: | cut -d \" -f 2 | sed 's|\\134|\\|g')
	
				if [ -n "$password" ]; then # Variabele bestaat
					hamachi join $HAMACHI_NETWORK $password && hamachi go-online $HAMACHI_NETWORK
				else
					echo 'Password is empty'
					exit 2
				fi
				
				if ! hamachi list|grep -q '* \['$HAMACHI_NETWORK; then
					echo 'unknown failure'
					exit 1
				fi
			fi
		fi
	fi
	if ! hamachi list|grep -q '* 5.'; then
		hamachi stop && hamachi start
	fi
elif [ "$1" = 'remove' ]; then
	#
	# Unload/remove launchd plist
	#
	varfile="/Users/$(/usr/bin/logname)/Library/LaunchAgents/nl.probackup.startHamachi.plist" # $(/usr/bin/logname) return current logged in user name
	if [ -e $varfile ] && [ -f $varfile ] && [ -s $varfile ] && grep -q "/Users/$(/usr/bin/logname)/Library/Scripts/Hamachi-for-os-x-start-up-on-login/startHamachi.command</string>" $varfile; then # File does exist, is a file and that file is not empty, and contains reference to default command file
		if [ "launchctl list|grep nl.probackup.startHamachi" ]; then
			echo 'Stop and unload launchd item'
			launchctl stop nl.probackup.startHamachi;launchctl unload -w ~/Library/LaunchAgents/nl.probackup.startHamachi.plist
			# 'launchctl remove' if the .plist is not available any more
		fi
		# Remove plist
		echo 'Remove launchd plist file'
		rm -f "$varfile"
	fi
	#
	# Remove the script file
	#
	SOURCE="${BASH_SOURCE[0]}"
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )" # detect directory where this file resides; also change working directory to source file directory
	varfile="/Users/$(/usr/bin/logname)/Library/Scripts/Hamachi-for-os-x-start-up-on-login/$( basename $SOURCE )"
	if [ "$DIR/$( basename $SOURCE )" != $varfile ]; then # This script to be removed is not this (running) script
		echo 'Remove script file'
		rm -f $varfile
	fi
else
	#
	# Install or re-install launchd plist
	#
	SOURCE="${BASH_SOURCE[0]}"
	
	echo 'Create launch plist file'
	varfile="/Users/$(/usr/bin/logname)/Library/LaunchAgents/nl.probackup.startHamachi.plist" # $(/usr/bin/logname) return current logged in user name
	cat > $varfile <<EOT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Disabled</key>
	<false/>
	<key>KeepAlive</key>
	<false/>
	<key>Label</key>
	<string>nl.probackup.startHamachi</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Users/$(/usr/bin/logname)/Library/Scripts/Hamachi-for-os-x-start-up-on-login/$( basename $SOURCE )</string>
		<string>run</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOT
	# Write plist: $ defaults write ./myPlist myKey -int $(echo $myKey_value)

	varfile="/Users/$(/usr/bin/logname)/Library/Scripts/Hamachi-for-os-x-start-up-on-login/$( basename $SOURCE )"
	if [ $SOURCE != $varfile ]; then
		if [ ! -e $varfile ] || [ ! -s $varfile ]; then # File does not exist, or that file is empty,
			echo 'Copy script file'
			if [ ! -e $(dirname $varfile) ];then 
				mkdir -p $(dirname $varfile) # Create directory
			fi
			cp -fp $SOURCE $varfile # Copy file
		fi
	fi
	if [ "launchctl list|grep nl.probackup.startHamachi" ]; then
		echo 'Stop and unload launchd item'
		launchctl stop nl.probackup.startHamachi;launchctl unload -w ~/Library/LaunchAgents/nl.probackup.startHamachi.plist	
	fi
	echo 'Load and start launchd item'
	launchctl load -w ~/Library/LaunchAgents/nl.probackup.startHamachi.plist && launchctl start nl.probackup.startHamachi
fi
exit 0