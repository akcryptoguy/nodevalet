#!/bin/bash
# Silently install masternodes and insert privkeys

function setup_environment() {
# Set Variables
LOGFILE='/root/installtemp/silentinstall.log'
INSTALLDIR='/root/installtemp'

# create root/installtemp if it doesn't exist
	if [ ! -d $INSTALLDIR ]
	then mkdir $INSTALLDIR
	else :
	fi

# set hostname variable to the name planted by install script
	if [ -e $INSTALLDIR/vpshostname.info ]
	then HNAME=$(<$INSTALLDIR/vpshostname.info)
	else HNAME=`hostname`
	fi

# create or assign customssh
	if [ -s $INSTALLDIR/vpssshport.info ]
	then SSHPORT=$(<$INSTALLDIR/vpssshport.info)
	else SSHPORT='22'
	fi

# create or assign mnprefix
	if [ -s $INSTALLDIR/vpsmnprefix.info ]
	then :
	else MNPREFIX=`hostname`
	fi

# read or assign number of masternodes to install
	if [ -e $INSTALLDIR/vpsnumber.info ]
	then MNS=$(<$INSTALLDIR/vpsnumber.info)
	# create a subroutine here to check memory and size MNS appropriately
	else MNS=5
	fi
	
# read or collect masternode addresses
	if [ -e $INSTALLDIR/vpsmnaddress.info ]
	then :
	# create a subroutine here to check memory and size MNS appropriately
	else echo -e " Before we can begin, we need to collect $MNS masternode addresses."
	echo -e " This logic does not presently allow for any mistakes; be careful."
	echo -e " In your local wallet, generate the addresses and then paste them below. \n"
		for ((i=1;i<=$MNS;i++)); 
		do 
		echo -e " Please enter the masternode address for masternode #$i :"
		read -p "  --> " MNADDP
		echo "$MNADDP" >> $INSTALLDIR/vpsmnaddress.info
		# add error checking logic and repeat if necessary
		done
	fi
	
	# enable softwrap so masternode.conf file can be easily copied
	sed -i "s/# set softwrap/set softwrap/" /etc/nanorc >> $LOGFILE 2>&1	
}

function begin_log() {
# Create Log File and Begin
echo -e "---------------------------------------------------- " | tee -a "$LOGFILE"
echo -e " `date +%m.%d.%Y_%H:%M:%S` : SCRIPT STARTED SUCCESSFULLY " | tee -a "$LOGFILE"
echo -e "---------------------------------------------------- " | tee -a "$LOGFILE"
echo -e "--------- AKcryptoGUY's Code Red Script ------------ " | tee -a "$LOGFILE"
echo -e "---------------------------------------------------- \n" | tee -a "$LOGFILE"
echo -e " I am going to create $MNS masternodes and install them\n" | tee -a "$LOGFILE"

# sleep 1
}

function add_cron() {
# reboot logic for status feedback
	(crontab -l ; echo "*/1 * * * * /root/installtemp/postinstall_api.sh") | crontab -
}

function silent_harden() {
	# modify get-hard.sh to add a file when complete, and check for that instead of server-hardening.log
	if [ -e /var/log/server_hardening.log ]
	then echo -e "System seems to already be hard, skipping this part" | tee -a "$LOGFILE"
	else
	cd ~/code-red/vps-harden
	bash get-hard.sh
	fi
	apt-get -qqy -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install jq | tee -a "$LOGFILE"
	curl -s "http://api.icndb.com/jokes/random" | jq '.value.joke' | tee -a "$LOGFILE"
}

function install_mns() {
	if [ -e /etc/masternodes/helium_n1.conf ]
	then
	touch $INSTALLDIR/mnsexist
	echo -e "Pre-existing masternodes detected; no changes to them will be made" > $INSTALLDIR/mnsexist
	echo -e "Masternodes seem to already be installed, skipping this part" | tee -a "$LOGFILE"
	else
	cd ~/
	sudo git clone https://github.com/heliumchain/vps.git && cd vps
		# update helium.conf template the way I like it
		# this next may not be necessary
		# masternodes may not start syncing the blockchain without a privatekey
		# install the masternodes with the dummykey and replace it later on
		DUMMYKEY='masternodeprivkey=7Qwk3FNnujGCf8SjovuTNTbLhyi8rs8TMT9ou1gKNonUeQmi91Z'
		sed -i "s/^masternodeprivkey=.*/$DUMMYKEY/" config/helium/helium.conf >> $LOGFILE 2>&1
		sed -i "s/^maxconnections=256.*/maxconnections=56/" config/helium/helium.conf >> $LOGFILE 2>&1
	sudo ./install.sh -p helium -c $MNS
	activate_masternodes_helium
	sleep 3
		# check if heliumd was built correctly and started
		ps -A |  grep helium >> $INSTALLDIR/HELIUMDs
		if [ -s $INSTALLDIR/HELIUMDs ]
		then echo -e "It looks like VPS install script completed and heliumd is running... " | tee -a "$LOGFILE"
		# report back to mothership
		curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Heliumd has started..."}'
		else echo -e "It looks like VPS install script failed, heliumd is not running... " | tee -a "$LOGFILE"
		# report error, exit script maybe or see if it can self-correct
		curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Heliumd failed to build or start..."}'
		fi
	fi
}

function get_genkeys() {
# Iteratively create all masternode variables for masternode.conf
# Do not break any pre-existing masternodes
if [ -s $INSTALLDIR/mnsexist ]
then echo -e "Skipping get_genkeys function due to presence of $INSTALLDIR/mnsexist" | tee -a "$LOGFILE"
else
   		# Create a file containing all masternode genkeys
   		echo -e "Saving genkey(s) to $INSTALLDIR/genkeys \n"  | tee -a "$LOGFILE"
   		rm $INSTALLDIR/genkeys --force
   		touch $INSTALLDIR/genkeys  | tee -a "$LOGFILE"

# create initial masternode.conf file and populate with notes
touch $INSTALLDIR/masternode.conf

cat <<EOT >> $INSTALLDIR/masternode.conf
#######################################################
# Masternode.conf settings to paste into Local Wallet #
#######################################################
EOT

for ((i=1;i<=$MNS;i++)); 
do

	# get or iterate mnprefixes
	if [ -s $INSTALLDIR/mnprefix.info ] ; then
		echo -e "$(sed -n ${i}p $INSTALLDIR/vpsmnprefix.info)" >> $INSTALLDIR/mnaliases
	else echo -e "${MNPREFIX}-MN$i" >> $INSTALLDIR/mnaliases
	fi
	
	# create masternode prefix files
	echo -e "$(sed -n ${i}p $INSTALLDIR/mnaliases)" >> $INSTALLDIR/MNALIAS$i

	# create masternode address files
	echo -e "$(sed -n ${i}p $INSTALLDIR/vpsmnaddress.info)" > $INSTALLDIR/MNADD$i

	# create masternode genkeys
	/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf masternode genkey >> $INSTALLDIR/genkeys   | tee -a "$LOGFILE"
	echo -e "$(sed -n ${i}p $INSTALLDIR/genkeys)" >> $INSTALLDIR/GENKEY$i
	echo "masternodeprivkey=" > $INSTALLDIR/MNPRIV1
	
	# append "masternodeprivkey="
	paste $INSTALLDIR/MNPRIV1 $INSTALLDIR/GENKEY$i > $INSTALLDIR/GENKEY${i}FIN
	tr -d '[:blank:]' < $INSTALLDIR/GENKEY${i}FIN > $INSTALLDIR/MNPRIVKEY$i
	
	# assign GENKEYVAR to the full line masternodeprivkey=xxxxxxxxxx
	GENKEYVAR=`cat $INSTALLDIR/MNPRIVKEY$i`
	# this is an alternative text that also works GENKEYVAR=$(</root/installtemp/MNPRIVKEY$i)

	# insert new genkey into project_n$i.conf files
	sed -i "s/^masternodeprivkey=.*/$GENKEYVAR/" /etc/masternodes/helium_n$i.conf >> $LOGFILE 2>&1

	# create file with IP addresses
	sed -n -e '/^bind/p' /etc/masternodes/helium_n$i.conf >> $INSTALLDIR/mnipaddresses
	
	# remove "bind=" from mnipaddresses
	sed -i "s/bind=//" $INSTALLDIR/mnipaddresses >> log 2>&1
	
	# the next line produces the IP addresses for this masternode
	echo -e "$(sed -n ${i}p $INSTALLDIR/mnipaddresses)" > $INSTALLDIR/IPADDR$i
	
	# obtain txid
	# curl -s "https://www.heliumchain.info/api/address/ACTUALHELIUMADDRESS" | jq '.["utxo"][0]["txId","n"]' | tr -d '["]'`
	curl -s "https://www.heliumchain.info/api/address/`cat $INSTALLDIR/MNADD$i`" | jq '.["utxo"][0]["txId","n"]' | tr -d '["]' > $INSTALLDIR/TXID$i
	TX=`echo $(cat $INSTALLDIR/TXID$i)`
	echo -e $TX >> $INSTALLDIR/txid
	echo -e $TX > $INSTALLDIR/TXID$i
	
	# merge all vars into masternode.conf
	# this is the output to return to MNO
	echo "|" > $INSTALLDIR/DELIMETER
	paste -d '|' $INSTALLDIR/DELIMETER $INSTALLDIR/MNALIAS$i $INSTALLDIR/IPADDR$i $INSTALLDIR/GENKEY$i $INSTALLDIR/TXID$i >> $INSTALLDIR/masternode.all
			
	# this is the output to return to consumer
	paste -d ' ' $INSTALLDIR/MNALIAS$i $INSTALLDIR/IPADDR$i $INSTALLDIR/GENKEY$i $INSTALLDIR/TXID$i >> $INSTALLDIR/masternode.conf

# declutter ; take out trash
rm $INSTALLDIR/GENKEY${i}FIN ; rm $INSTALLDIR/GENKEY$i ; rm $INSTALLDIR/IPADDR$i ; rm $INSTALLDIR/MNADD$i
rm $INSTALLDIR/MNALIAS$i ; rm $INSTALLDIR/MNPRIV*$i ; rm $INSTALLDIR/TXID$i ; rm $INSTALLDIR/MNPRIV1

# slow it down to not upset the blockchain API
sleep 2
echo -e "Completed masternode $i loop, moving on...\n"
done
	
	# convert it to one delineated line separated using | and ||
	echo "complete" > $INSTALLDIR/complete
	
# replace spaces with + temporarily	
sed -i 's/ /+/g' $INSTALLDIR/masternode.all

# merge "complete" line with masternode.all file and remove \n
paste -s $INSTALLDIR/complete $INSTALLDIR/masternode.all |  tr -d '[\n]' > $INSTALLDIR/masternode.1
tr -d '[:blank:]' < $INSTALLDIR/masternode.1 > $INSTALLDIR/masternode.return
sed -i 's/+/ /g' $INSTALLDIR/masternode.return
# read masternode data into string for curl
MASTERNODERETURN=$(<$INSTALLDIR/masternode.return)
	
# paste -s $INSTALLDIR/complete $INSTALLDIR/masternode.all >> $INSTALLDIR/masternode.return
# tr -d '[:blank:]' < $INSTALLDIR/masternode.return > $INSTALLDIR/masternode.return2

# round 2: cleanup and declutter
rm $INSTALLDIR/complete --force
rm $INSTALLDIR/masternode.all --force
rm $INSTALLDIR/masternode.1 --force


# report back all critial masternode.conf information
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "'"$MASTERNODERETURN"'"}'




#	echo -e "This is the contents of your file $INSTALLDIR/genkeys:"
#	cat $INSTALLDIR/genkeys
#	echo -e "\n"
	
#	echo -e "This is the contents of your file $INSTALLDIR/mnipaddresses:"
#	cat $INSTALLDIR/mnipaddresses
#	echo -e "\n"

	# lists the garbage leftover after installation
	ls $INSTALLDIR
fi
 }

function get_blocks() {
# echo "grep "blocks" $INSTALLDIR/getinfo_n1" 
BLOCKS=$(grep "blocks" $INSTALLDIR/getinfo_n1 | tr -dc '0-9')
echo -e "Masternode 1 is currently synced through block $BLOCKS.\n"
}

function check_blocksync() {
# set SECONDS+XXXXX to however long is reasonable to let the initial
# chain sync continue before reporting an error back to the user
end=$((SECONDS+7200))

while [ $SECONDS -lt $end ]; do
    echo -e "Time $SECONDS"
    
	rm -rf $INSTALLDIR/getinfo_n1
	touch $INSTALLDIR/getinfo_n1
	/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf getinfo  | tee -a $INSTALLDIR/getinfo_n1
	clear
    
    # if  masternode not running, echo masternode not running and break
    BLOCKS=$(grep "blocks" $INSTALLDIR/getinfo_n1 | tr -dc '0-9')
    echo -e "$BLOCKS is the current number of blocks"
    
    if (($BLOCKS <= 1 )) ; then echo "Masternode is not syncing" ; break
    else sync_check
    fi
    
    if [ "$SYNCED" = "yes" ]; then printf "${lightcyan}" ; echo "Masternode synced" ; printf "${nocolor}" ; break
    else echo -e "Blockchain not synced; will check again in 5 seconds\n"
    sleep 5
    fi
done

    if [ "$SYNCED" = "no" ]; then printf "${lightred}" ; echo "Masternode did not sync in allowed time" ; printf "${nocolor}"
    # radio home that blockchain sync was unsuccessful
    # add curl here
    else : ; fi

echo -e "All done."
}

function sync_check() {
CNT=`/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf getblockcount`
# echo -e "CNT is set to $CNT"
HASH=`/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf getblockhash ${CNT}`
#echo -e "HASH is set to $HASH"
TIMELINE1=`/usr/local/bin/helium-cli -conf=/etc/masternodes/helium_n1.conf getblock ${HASH} | grep '"time"'`
TIMELINE=$(echo $TIMELINE1 | tr -dc '0-9')
BLOCKS=$(grep "blocks" $INSTALLDIR/getinfo_n1 | tr -dc '0-9')
# echo -e "TIMELINE is set to $TIMELINE"
LTRIMTIME=${TIMELINE#*time\" : }
# echo -e "LTRIMTIME is set to $LTRIMTIME"
NEWEST=${LTRIMTIME%%,*}
# echo -e "NEWEST is set to $NEWEST"
TIMEDIF=$(echo -e "$((`date +%s`-$NEWEST))")
echo -e "This masternode is $TIMEDIF seconds behind the latest block." 
   #check if current
   if (($TIMEDIF <= 60 && $TIMEDIF >= -60))
	then echo -e "The blockchain is almost certainly synced.\n"
	SYNCED="yes"
	else echo -e "That's the same as $(((`date +%s`-$NEWEST)/3600)) hours or $(((`date +%s`-$NEWEST)/86400)) days behind.\n"
	SYNCED="no"
   fi	
}

function restart_server() {
:
echo -e "Going to restart server in 30 seconds. . . "
sleep 30
shutdown -r now
}

# This is where the script actually starts

setup_environment
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Beginning Install Script..."}'

begin_log
add_cron

curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Updating and Hardening Server..."}'
silent_harden
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Building Helium Wallet..."}'
install_mns
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Configuring Masternodes..."}'
get_genkeys
curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Masternodes Configured..."}'
# need to add a line to broadcast the masternode.conf file back to MNO

curl -X POST https://www.heliumstats.online/code-red/status.php -H 'Content-Type: application/json-rpc' -d '{"hostname":"'"$HNAME"'","message": "Restarting Server..."}'
restart_server

# check_blocksync
# sync_check

echo -e "Log of events saved to: $LOGFILE \n"
