#!/bin/bash
### ##########################################################################
###
###  Author:        Jonathan DUPRE
###  GitHub:        https://github.com/duprej/ccc
###  Commands:      udevadm / stty
###  Usage:         Can be interactive (ask questions) or not (-h for usage)
###  Created at:    09/30/2020 - 1.0 - Initial
###  Revised on:    10/11/2020 - 1.1 - Does not work, now it's ok :)
###                                  - More hints and helps (user-friendly)
###                                  - Better tolerance to question answers
###                                  - Adaptive wait time in manual mode
###                                    (CM3 vs CM7).
###                 10/12/2020 - 1.2 - Various optimisations
###                 10/25/2020 - 1.3 - Add grep -v to serial port listing for
###                                    avoid counting redirected ports (->)
###                 12/27/2020 - 1.4 - Fix 'long' commands not executed correctly by
###                                    changer in manual mode (ex : 1PSSATR24SEPL)
###									 - Add command-line options + testonly mode
###									   for batch/script processing.
###
### ##########################################################################
SVERSION=1.4
echo -n -e "Welcome to CAC Control Center serial checker script v${SVERSION} for Linux.\n"
if ! command -v udevadm &> /dev/null
then
	echo "udevadm command not found."
	exit 1
fi
if ! command -v stty &> /dev/null
then
	echo "stty command not found."
	exit 2
fi
if [ -z "$1" ]
then
	echo "No argument supplied."
	echo "This tiny script is interactive and will ask you some questions."
	echo -n "Listing serial ports... "
	ports=`ls /dev/ | grep -e 'tty[AUS]'`
	nbrPorts=`ls -l /dev/ | grep -e 'tty[AUS]' | grep -v '>' | wc -l`
	if [ $nbrPorts == "0" ]
	then
		echo -e "\nSorry no serial port found. Check machine."
		exit 3
	else
		echo -e "$nbrPorts found."
	fi
	# Print physical ports 
	echo ""
	printf "%-10s | %-70s\n" "Device" "Physical port"
	printf "%-10s | %-70s\n" "------" "-------------"
	for i in $ports
	do 
		udev=`udevadm info -a -n /dev/${i} | grep "looking at device" | head -1 | cut -d' ' -f6`
		udev=`echo ${udev:1:-2}`
		printf "%-10s | %-70s\n" "$i" "$udev"
	done
	if [ $nbrPorts == "1" ]
	then
		# Auto-select the only one available
		device=$ports
	else
		# Ask
		echo -e "\nPlease select a serial port:"
		select device in `echo ${ports}`
		do
			if [ -z $device ]
			then
				echo "Bad choice. Try again."
			else
				echo "You have chosen $device."
				break
			fi
		done
	fi
else
	if [ $1 == "-h" ]
	then
		# Print usage
		echo -e "Usage:"
		echo -e "$0 [Serial port device name] [Pioneer changer model] [Left player ID for 3000/3200/5000] [testonly]\n"
		echo -e "All parameters are optional."
		echo -e "Examples:"
		echo -e "\t$0 ttyUSB0"
		echo -e "\t$0 ttyUSB0 CAC-V180M"
		echo -e "\t$0 ttyUSB0 CAC-V5000 1"
		echo -e "\t$0 ttyUSB1 CAC-V3000 3 testonly "
		echo -e "\t$0 ttyUSB0 CAC-V180M 0 testonly" 
		exit 0
	fi
	device=$1
	if [ ! -e "/dev/$device" ]
	then
		echo -e "\nSorry the device was not found."
		exit 5
	fi
	echo "Device /dev/$device selected by command-line parameter."
fi
if [ -z "$2" ]
then
	echo "Please select an autochanger model:"
	select model in CAC-V180M CAC-V3000/V3200/V5000
	do
		if [ -z $model ]
		then
			echo "Bad choice. Try again."
		else
			echo "You have chosen $model."
			break
		fi
	done
else
	model=$2
	echo "Model $model selected by command-line parameter."
fi
if [ $model == "CAC-V180M" ]
then
	# This model only use 4800bps.
	speedsAllowed="4800"
	waitTimeoutCommand=16
	echo "Speed set to 4800 bps."
else
	speedsAllowed="9600 4800"
	waitTimeoutCommand=1
	echo "Multiple speed testing mode."
	lpid='1'
	if [ ! -z "$3" ]
	then
		if ! [[ "$3" =~ ^[0-9]+$ ]]
		then
			echo "Left player ID must be a number!"
			exit 6
		else
			lpid="$3";
	  	fi
	fi
fi
# Test part
doTest=1
success=0
while [ $doTest -eq 1 ]
do
	for speed in $speedsAllowed
	do
		exec 6<&0
		echo -n "Applying stty settings for ${speed} bps..."
		stty -F /dev/${device} $speed cs8 -cstopb -parenb ignpar -inlcr icrnl -ixon -ixoff
		if [ "$?" -ne "0" ]
		then
			echo "KO. Problem with stty command."
			echo "Please be sure you have permissions to use serial ports."
			echo "Hint : on some Linux systems you have to be in the 'dialout' group."
			echo "1 : sudo usermod -aG dialout `whoami`"
			echo "2 : re-login (restart terminal/session)"
			echo "3 : try again execute $0"
			exit 4
		else
			echo "done."
		fi
		if [ $model = "CAC-V180M" ]
		then
			command='?X'
		else
			command="${lpid}PS?X"
		fi
		echo -n "Trying to communicate with the autochanger... "
		exec <> /dev/${device}
		echo -n -e "$command\r" > /dev/${device}
		echo "Command '$command' send, waiting for reply..."
		read -t 1 reply < /dev/${device} 
		exec 0<&6 6<&-
		reply=${reply//$'\r'/}
		if [ -z $reply ]
		then
			echo ":-( The autochanger did not replied at ${speed} bps."
		else
			if [[ $reply = *[![:ascii:]]* ]]
			then
				echo ":-( Autochanger replied but with fuzzy chars at ${speed} bps."
			else
				echo ":-) The autochanger replied correctly with '$reply' at ${speed} bps."
				success=1
				doTest=0
				break
			fi
		fi
	done
	if [ $success -eq 0 ]
	then
		echo "Dialogue with Pioneer autochanger FAILED!"
		echo "Verification hints and troubleshooting:"
		echo -e "\t- Check autochanger power."
		echo -e "\t- Check serial cable connection."
		echo -e "\t- For V3000 & V3200 models : "
		echo -e "\t\t- Be sure the first player address is ${lpid} (see manual page 14)."
		echo -e "\t\t- Be sure the back CONFIG. slider selector is on RS-232C position (= up)."
		if [ "$4" == "testonly" ]; then exit 0;	fi
		echo ""
		echo "Try again ? Y(es) or any other key for no."
		read -s -n 1 choice
		if [[ ! $choice =~ ^[Yy]$ ]]
		then
			echo "Goodbye."
			exit 0
		else
			echo "Trying again..."
		fi
	fi
done
echo "Dialogue with Pioneer autochanger SUCCEEDED!"
#If third parameter is testonly, no interactive mode.
if [ "$4" == "testonly" ]
then
	exit 0
fi
echo "Do you want to send custom commands (manual mode) now? Y(es) or any other key for no."
read -s -n 1 choice
if [[ ! $choice =~ ^[Yy]$ ]]
then
	echo "Goodbye."
	exit 0
fi	
#REPL part
echo "Manual mode entered. Type your autochanger command and press Enter (for each one).
Warning: All chars will be sent as is! There is no verification.
Type 'exit' to terminate this program. Timeout for a command reply is set to $waitTimeoutCommand second(s)."
while true
do
	exec 6<&0
	read -p "Command: " command
	command=$(echo "${command// /}")
	if [ ! -z $command ]; then
		if [ $command == 'exit' ]
		then
			break
		fi
		exec <> /dev/${device}
		# No new line, No \r (included in $command)
		echo -n -e "$command\r" > /dev/${device}
		read -t${waitTimeoutCommand} reply < /dev/${device}
		reply=${reply//$'\r'/}
		exec 0<&6 6<&-
		echo $reply
	fi
done
echo "Goodbye."
exit 0
