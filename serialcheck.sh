#!/bin/bash
### ####################################################################### ###
###
###  Author:		Jonathan DUPRE
###  GitHub:		duprej
###  Commands :  	udevadm / stty
###  Created at :  	09/30/2020 - 1 - Initial
###
### ####################################################################### ###
SVERSION=1
echo -e "Welcome to CCC autochanger serial checker script v${SVERSION} for Linux.\n"
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
echo "This tiny script is interactive and will ask you some questions."
echo -n "Listing serial ports... "
ports=`ls /dev/ | grep -e 'tty[AUS]'`
nbrPorts=`ls -l /dev/ | grep -e 'tty[AUS]' | wc -l`
if [ $nbrPorts == "0" ]
then
	echo -e "\nSorry no serial port found. Check machine. Exit."
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
if [ $model = "CAC-V180M" ]
then
	# This model only use 4800bps, no need to ask the speed.
	speedsAllowed="4800"
	nbrSpeeds=1
	echo "Speed set to 4800bps."
else
	speedsAllowed="9600 4800"
	nbrSpeeds=2
	echo "Multiple speed testing mode."
fi
# Test part
doTest=1
success=0
while [ $doTest -eq 1 ]
do
	for speed in $speedsAllowed
	do
		echo -n "Applying stty settings for ${speed}bps... "
		stty -F /dev/${device} $speed cs8 -cstopb -parenb icrnl
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
			command='1PS?X'
		fi
		echo -n "Trying to communicate with the autochanger... "
		echo -e "$command\\r" > /dev/${device}
		echo "Command '$command' send, waiting for reply..."
		read -t 1 reply < /dev/${device}
		reply=${reply//$'\r'/}
		if [ -z $reply ]
		then
			echo ":-( The autochanger did not replied at ${speed}bps."
		else
			if [[ $reply = *[![:ascii:]]* ]]
			then
				echo ":-( Autochanger replied but with fuzzy chars at ${speed}bps."
			else
				echo ":-) The autochanger replied correctly with '$reply' at ${speed}bps."
				success=1
				doTest=0
				break
			fi
		fi
	done
	if [ $success -eq 0 ]
	then
		echo "Try again ? Y(es) or N(o)"
		read -s -n 1 choice
		if [[ $choice =~ ^[Nn]$ ]]
		then
			echo "Goodbye."
			exit 0
		fi
	fi
done
#REPL part
echo "Do you want to send custom commands (manual mode) now? Y(es) or N(o)"
read -s -n 1 choice
if [[ $choice =~ ^[Nn]$ ]]
then
	echo "Goodbye."
	exit 0
fi	
echo "Manual mode entered. Type your command and press Enter (for each one).
Warning: All chars will be sent as is! There is no verification.
Type 'exit' to terminate this program."
while true
do
	read -p "Command: " command
	if [ ! -z $command ]; then
		if [ $command == 'exit' ]
		then
			echo "Manual mode exited."
			break
		fi
		echo -e "$command\\r" > /dev/${device}
		read -t5 reply < /dev/${device}
		reply=${reply//$'\r'/}
		echo $reply
	fi
done
echo "Goodbye."
exit 0
