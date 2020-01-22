#!/bin/bash
#
# Written By: Mr Rahul Kumar
# Created date: Jun 14, 2014
# Last Updated: Mar 08, 2017
# Version: 1.2.1
# Visit: https://tecadmin.net/backup-running-virtual-machine-in-xenserver/
#
# Fork: Boardereb

# To change:


NFS_SERVER_IP="192.168.10.100"
MOUNTPOINT=/xenmnt
FILE_LOCATION_ON_NFS="/backup/citrix/vms"
MAXBACKUPS=2

# Loglevel 0=only start and exit
# Loglevel 1=every action

LOGLEVEL=0

# int. Variablen

XSNAME=`echo $HOSTNAME`
DATE=$(date +%d-%m-%Y)-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
UUIDFILE=$(mktemp /tmp/xen-uuids.XXXXXXXXX)


echo "start Xen Server VM Backup"
logger "$0: start Xen Server VM Backup"

### Create mount point

if [[ $LOGLEVEL != 0 ]]; then
	LOGGERMASSAGE="$0: create mountpoint $MOUNTPOINT if not exist"
	echo $LOGGERMASSAGE
 	logger $LOGGERMASSAGE
fi

mkdir -p ${MOUNTPOINT}

### Mounting remote nfs share backup drive

if [[ ! -d ${MOUNTPOINT} ]]; then
	LOGGERMASSAGE="Error: $0: No mount point found, kindly check"
	echo $LOGGERMASSAGE
	logger $LOGGERMASSAGE
	exit 1
fi

if [[ $LOGLEVEL != 0 ]]; then
	LOGGERMASSAGE="$0: mount NFS $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS"
	echo $LOGGERMASSAGE
	logger $LOGGERMASSAGE
fi

mount -t nfs ${NFS_SERVER_IP}:${FILE_LOCATION_ON_NFS} ${MOUNTPOINT}

BACKUPPATH=${MOUNTPOINT}/${XSNAME}/${DATE}

if [[ $LOGLEVEL != 0 ]]; then
	LOGGERMASSAGE="$0: create backuppath $BACKUPPATH if not exist"
	echo $LOGGERMASSAGE
	logger $LOGGERMASSAGE
fi

mkdir -p ${BACKUPPATH}

if [[ ! -d ${BACKUPPATH} ]]; then
	LOGGERMASSAGE="Error: $0: No backup directory found"
	echo $LOGGERMASSAGE
	logger LOGGERMASSAGE
	exit 1
fi

# Fetching list UUIDs of all VMs running on XenServer

if [[ $LOGLEVEL != 0 ]]; then
	LOGGERMASSAGE="$0: create UuidFile ${UUIDFILE}"
	echo $LOGGERMASSAGE
	logger $LOGGERMASSAGE
fi

xe vm-list is-control-domain=false is-a-snapshot=false | grep uuid | cut -d":" -f2 > ${UUIDFILE}

if [[ ! -f ${UUIDFILE} ]]; then
			LOGGERMASSAGE="Error: $0: No UUID list file found"
       echo $LOGGERMASSAGE
       logger $LOGGERMASSAGE
       exit 1
fi

while read VMUUID
do
    VMNAME=`xe vm-list uuid=$VMUUID | grep name-label | cut -d":" -f2 | sed 's/^ *//g'`

    if [[ $LOGLEVEL != 0 ]]; then
			LOGGERMASSAGE="$0: create snapshoot from: $VMNAME"
	    echo $LOGGERMASSAGE
	    logger $LOGGERMASSAGE
    fi

    SNAPUUID=`xe vm-snapshot uuid=$VMUUID new-name-label="SNAPSHOT-$VMNAME-$DATE"`

    xe template-param-set is-a-template=false ha-always-run=false uuid=${SNAPUUID}

    if [[ $LOGLEVEL != 0 ]]; then
			LOGGERMASSAGE="$0: export snapshoot $VMNAME to $BACKUPPATH"
			echo $LOGGERMASSAGE
			logger $LOGGERMASSAGE
    fi

    xe vm-export vm=${SNAPUUID} filename="$BACKUPPATH/$VMNAME-$DATE.xva"

    if [[ $LOGLEVEL != 0 ]]; then
			LOGGERMASSAGE="$0: remove snapshoot from: $VMNAME"
	    echo $LOGGERMASSAGE
	    logger $LOGGERMASSAGE
    fi

    xe vm-uninstall uuid=${SNAPUUID} force=true

done < ${UUIDFILE}

BACKUPPATH=${MOUNTPOINT}/${XSNAME}/
BACKUPDIRS=$(find $BACKUPPATH  -maxdepth 1 -type d -printf "%T@ %p\n"  | sort -n -r | cut -d' ' -f2 |  grep -v "^$BACKUPPATH$" | grep -v "^.$")

if [[ $LOGLEVEL != 0 ]]; then
	BACKUPS=$(echo $BACKUPDIRS | wc -l)
	COUNT=$(($BACKUPS-$MAXBACKUPS))

	if [[ $COUNT -lt 0 ]]; then
		COUNT=0
	fi

  LOGGERMASSAGE="$0: $BACKUPS backup found - remove $COUNT old backup"
	echo $LOGGERMASSAGE
	logger $LOGGERMASSAGE
fi

COUNT=1
for BDIR in $BACKUPDIRS;do
	if [[ $COUNT > $MAXBACKUPS ]]; then
		rm -rf $BDIR
	fi
	COUNT=$(($COUNT+1))
done

BACKUPS=$(echo "$BACKUPDIRS" | wc -l)

if [[ $BACKUPS != $MAXBACKUPS ]]; then
	LOGGERMASSAGE="$0: Error: not all old backups are removed"
	echo $LOGGERMASSAGE
	logger $LOGGERMASSAGE
else
	if [[ $LOGLEVEL != 0 ]]; then
		LOGGERMASSAGE="$0: old backups are removed"
		echo $LOGGERMASSAGE
		logger $LOGGERMASSAGE
	fi
fi

if [[ $LOGLEVEL != 0 ]]; then
	LOGGERMASSAGE="$0: unmount NFS $MOUNTPOINT"
	echo $LOGGERMASSAGE
	logger $LOGGERMASSAGE
fi

umount ${MOUNTPOINT}

LOGGERMASSAGE="$0: Xen Server VM Backup finished"
echo $LOGGERMASSAGE
logger $LOGGERMASSAGE

exit 0
