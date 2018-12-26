#!/bin/bash
# to be added to crontab to updatebinaries using any means necessary
cd /var/tmp/nodevalet/temp
LOGFILE='/var/tmp/nodevalet/logs/autoupdate.log'
INSTALLDIR='/var/tmp/nodevalet'
INFODIR='/var/tmp/nvtemp'
PROJECT=`cat $INFODIR/vpscoin.info`
PROJECTl=${PROJECT,,}
PROJECTt=${PROJECTl~}

#Pull GITAPI_URL from $PROJECT.env
GIT_API=`grep ^GITAPI_URL $INSTALLDIR/nodemaster/config/${PROJECT}/${PROJECT}.env`
echo "$GIT_API" > $INSTALLDIR/temp/GIT_API
sed -i "s/GITAPI_URL=//" $INSTALLDIR/temp/GIT_API
GITAPI_URL=$(<$INSTALLDIR/temp/GIT_API)

function update_binaries() {
#check for updates and install binaries if necessary
echo -e " `date +%m.%d.%Y_%H:%M:%S` : Running update_binaries function"  | tee -a "$LOGFILE"
echo -e " `date +%m.%d.%Y_%H:%M:%S` : Autoupdate is looking for new $PROJECTt tags." | tee -a "$LOGFILE"
cd $INSTALLDIR/temp
CURVERSION=`cat $INSTALLDIR/temp/currentversion`
NEWVERSION="$(curl -s $GITAPI_URL | grep tag_name)"

if [ "$CURVERSION" != "$NEWVERSION" ]
then echo -e " Installed version is : $CURVERSION" | tee -a "$LOGFILE"
     echo -e " New version detected : $NEWVERSION" | tee -a "$LOGFILE"
     echo -e " Attempting to install new $PROJECTt binaries" | tee -a "$LOGFILE"
		touch $INSTALLDIR/temp/updating
		systemctl stop $PROJECT*
		mkdir /usr/local/bin/backup
		echo -e " Backing up existing binaries to /usr/local/bin/backup" | tee -a "$LOGFILE"
		cp /usr/local/bin/${PROJECT}* /usr/local/bin/backup
		| curl -s $GITAPI_URL \
		| grep browser_download_url \
  		| grep x86_64-linux-gnu.tar.gz \
  		| cut -d '"' -f 4 \
  		| wget -qi -
	TARBALL="$(find . -name "*x86_64-linux-gnu.tar.gz")"
	EXTRACTDIR=${TARBALL%-x86_64-linux-gnu.tar.gz}
		tar -xzf $TARBALL
		cp -r $EXTRACTDIR/bin/. /usr/local/bin/
		rm -r $EXTRACTDIR
		rm -f $TARBALL
		echo -e " Restarting masternodes after installation of new ${PROJECTt} binaries\n" >> "$LOGFILE"
		activate_masternodes_$PROJECT echo -e | tee -a "$LOGFILE"
		sleep 2
		check_project
else echo -e " No new version is detected \n" | tee -a "$LOGFILE"
exit
fi
}

function update_from_source() {
#check for updates and build from source if installing binaries failed. 

echo -e " `date +%m.%d.%Y_%H:%M:%S` : Running update_from_source function" | tee -a "$LOGFILE"
cd $INSTALLDIR/temp

CURVERSION=`cat $INSTALLDIR/temp/currentversion`
NEWVERSION="$(curl -s $GITAPI_URL | grep tag_name)"
if [ "$CURVERSION" != "$NEWVERSION" ]
then 	echo -e " I couldn't download the new binaries, so I am now" | tee -a "$LOGFILE"
	echo -e " attempting to build new wallet version from source" | tee -a "$LOGFILE"
	add-apt-repository -yu ppa:bitcoin/bitcoin
	apt-get -qq -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true update
	apt-get -qqy -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install build-essential \
	libcurl4-gnutls-dev protobuf-compiler libboost-all-dev autotools-dev automake \
	libboost-all-dev libssl-dev make autoconf libtool git apt-utils g++ \
	libprotobuf-dev pkg-config libudev-dev libqrencode-dev bsdmainutils \
	pkg-config libgmp3-dev libevent-dev jp2a pv virtualenv libdb4.8-dev libdb4.8++-dev
	systemctl stop ${PROJECT}*
	git clone $GIT_URL
	cd $PROJECT
	./autogen.sh
	./configure --disable-dependency-tracking --enable-tests=no --without-gui --without-miniupnpc --with-incompatible-bdb CFLAGS="-march=native" LIBS="-lcurl -lssl -lcrypto -lz"
	make
	make install
	cd /usr/local/bin && rm -f !"("activate_masternodes_"$PROJECT"")"
	cp $INSTALLDIR/$PROJECT/src/{"$PROJECT"-cli,"$PROJECT"d,"$PROJECT"-tx} /usr/local/bin/
	rm -rf $INSTALLDIR/$PROJECT
	cd $INSTALLDIR/temp
	echo -e " Restarting masternodes after building ${PROJECTt} from source\n" >> "$LOGFILE"
	activate_masternodes_$PROJECT
	sleep 2
	check_project
	echo -e " It looks like we couldn't rebuild ${PROJECTt} from source, either." >> "$LOGFILE"
	echo -e " Restoring original binaries from /usr/local/bin/backup" | tee -a "$LOGFILE"
	cp /usr/local/bin/backup/${PROJECT}* /usr/local/bin/
	activate_masternodes_$PROJECT
	sleep 2
	check_restore
	exit
fi
}

function check_project() {
	# check if $PROJECTd is running
	ps -A | grep $PROJECT >> $INSTALLDIR/temp/${PROJECT}Ds
	if [ -s $INSTALLDIR/temp/${PROJECT}Ds ]
	then echo -e " `date +%m.%d.%Y_%H:%M:%S` : ${PROJECTt}d is running..." | tee -a "$LOGFILE"
		echo -e " Your ${PROJECTt}d was successfully updated \n" | tee -a "$LOGFILE"
	curl -s $GITAPI_URL | grep tag_name > $INSTALLDIR/temp/currentversion
	rm -f $INSTALLDIR/temp/${PROJECT}Ds
	rm -f $INSTALLDIR/temp/updating
	exit
	else echo -e " `date +%m.%d.%Y_%H:%M:%S` : ${PROJECTt}d is not running..." | tee -a "$LOGFILE"
	echo -e "This update step failed, trying to autocorrect ... " | tee -a "$LOGFILE"
	rm -f $INSTALLDIR/temp/${PROJECT}Ds
	fi
}

function check_restore() {
	# check if $PROJECTd is running
	ps -A | grep $PROJECT >> $INSTALLDIR/temp/${PROJECT}Ds
	if [ -s $INSTALLDIR/temp/${PROJECT}Ds ]
	then echo -e " ${PROJECTt}d is up and running...original binaries were restored" | tee -a "$LOGFILE"
	then echo -e " We will try this update again later. \n" | tee -a "$LOGFILE"
	rm -f $INSTALLDIR/temp/${PROJECT}Ds
	rm -f $INSTALLDIR/temp/updating
	exit
	else echo -e " It looks like restoring the binaries failed, ${PROJECTt}d is not running... " | tee -a "$LOGFILE"
	else echo -e " I'm all out of options; your VPS may need service. \n " | tee -a "$LOGFILE"
	rm -f $INSTALLDIR/temp/${PROJECT}Ds
	rm -f $INSTALLDIR/temp/updating
	reboot
	fi
}

# this is where the current update sequence begins
update_binaries
update_from_source

exit

# original update sequence
bash $INSTALLDIR/autoupdate/updatebinaries.sh || bash $INSTALLDIR/autoupdate/updatefromsource.sh || rm -f $INSTALLDIR/temp/updating | /usr/local/bin/activate_masternodes_"$PROJECT" \
| rm -r -f $PROJECT* | echo -e "It looks like something went wrong while updating. Restarting daemon and pretending nothing happened." | tee -a "$LOGFILE"
