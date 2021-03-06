#!/bin/bash
# Stop and disable a particular masternode

# exit with error if not run as root/sudo
if [ "$(id -u)" != "0" ]
then echo -e "\n Please re-run as root or sudo.\n"
    exit 1
fi

# Set common variables
. /var/tmp/nodevalet/maintenance/vars.sh

# read first argument to string
i=$1

# if no argument was given, give instructions and ask for one

if [ -z "$i" ]
then clear
    echo -e "\n This scriptlet will stop and disable a particular masternode."
    echo -e " Which masternode would you like to disable? \n"
fi

while :; do
    if [ -z "$i" ] ; then read -p " --> " i ; fi
    [[ $i =~ ^[0-9]+$ ]] || { printf "${lightred}";echo -e "\n --> I only recognize numbers; enter  enter a number between 1 and $MNS...${nocolor}\n"; i=""; continue; }
    if (($i >= 1 && $i <= $MNS))
    then break
    else echo -e "${lightred}\n --> I don't have a masternode $i; enter a number between 1 and $MNS.${nocolor}\n"
        i=""
    fi
done

echo -e "\n"

# only log and set updating flag if this is not run during a smartstart
if [ ! -e "$INSTALLDIR/temp/smartstart" ]
then echo -e " $(date +%m.%d.%Y_%H:%M:%S) : Running mnstop.sh" | tee -a "$LOGFILE"
touch $INSTALLDIR/temp/updating
fi

echo -e -n " Disabling ${PROJECT}_n${i} now...  "
sudo systemctl disable "${PROJECT}"_n${i} > /dev/null 2>&1
# sudo /usr/local/bin/"${MNODE_DAEMON::-1}"-cli -conf=/etc/masternodes/"${PROJECT}"_n${i}.conf stop
systemctl stop "${PROJECT}"_n${i}
sleep .5

if [ ! -e "$INSTALLDIR/temp/smartstart" ]
then echo -e "${lightred} User has manually disabled Masternode ${PROJECT}_n${i}.${nocolor}\n"  | tee -a "$LOGFILE"
rm -f $INSTALLDIR/temp/updating
fi
