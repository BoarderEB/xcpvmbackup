#!/bin/bash
#
# Written By: Mr Rahul Kumar
# Created date: Jun 14, 2014
# Last Updated: Mar 08, 2017
# Version: 1.2.1
# Visit: https://tecadmin.net/backup-running-virtual-machine-in-xenserver/
#

DATE=`date +%d%b%Y`
XSNAME=`echo $HOSTNAME`
UUIDFILE=/tmp/xen-uuids.txt
NFS_SERVER_IP="192.168.10.100"
MOUNTPOINT=/xenmnt
FILE_LOCATION_ON_NFS="/backup/citrix/vms"
MAXBACKUPS=2

# Loglevel 0=only start and exit
# Loglevel 1=every action

LOGLEVEL=0

echo "start Xen Server VM Backup"
logger "$0: start Xen Server VM Backup"

### Create mount point

if [ $LOGLEVEL -ne 0 ]
then
	echo "create mountpoint $MOUNTPOINT if not exist"
 	logger "$0: create mountpoint $MOUNTPOINT if not exist"
fi

mkdir -p ${MOUNTPOINT}

### Mounting remote nfs share backup drive

if [ ! -d ${MOUNTPOINT} ]
then
	echo "No mount point found, kindly check" 
	logger "$0: No mount point found, kindly check" 
	exit 1
fi

if [ $LOGLEVEL -ne 0 ]
then
	echo "mount NFS $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS"
	logger "$0: mount NFS $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS"
fi

mount -t nfs ${NFS_SERVER_IP}:${FILE_LOCATION_ON_NFS} ${MOUNTPOINT}

BACKUPPATH=${MOUNTPOINT}/${XSNAME}/${DATE}

if [ $LOGLEVEL -ne 0 ]
then
	echo "create backuppath $BACKUPPATH if not exist"
	logger "$0: create backuppath $BACKUPPATH if not exist"
fi

mkdir -p ${BACKUPPATH}

if [ ! -d ${BACKUPPATH} ]
then
	echo "No backup directory found"
	logger "$0: No backup directory found"
	exit 1
fi


# Fetching list UUIDs of all VMs running on XenServer

if [ $LOGLEVEL -ne 0 ]
then
	echo "create UuidFile $UUIDFILE"
	logger "$0: create UuidFile ${UUIDFILE}"
fi

xe vm-list is-control-domain=false is-a-snapshot=false | grep uuid | cut -d":" -f2 > ${UUIDFILE}

if [ ! -f ${UUIDFILE} ]
then
       echo "No UUID list file found"
       logger "$0: No UUID list file found"
       exit 1
fi

while read VMUUID
do
    VMNAME=`xe vm-list uuid=$VMUUID | grep name-label | cut -d":" -f2 | sed 's/^ *//g'`

    SNAPUUID=`xe vm-snapshot uuid=$VMUUID new-name-label="SNAPSHOT-$VMUUID-$DATE"`

    if [ $LOGLEVEL -ne 0 ]
    then
	    echo "create snapshoot from: $VMNAME"
	    logger "$0: create snapshoot from: $VMNAME"
    fi

    xe template-param-set is-a-template=false ha-always-run=false uuid=${SNAPUUID}

    if [ $LOGLEVEL -ne 0 ]
    then
	   echo "export snapshoot $VMNAME to $BACKUPPATH"
	   logger "$0: export snapshoot $VMNAME to $BACKUPPATH"
    fi
    
    xe vm-export vm=${SNAPUUID} filename="$BACKUPPATH/$VMNAME-$DATE.xva"

    if [ $LOGLEVEL -ne 0 ]
    then
	    echo "remove snapshoot from: $VMNAME"
	    logger "$0: remove snapshoot from: $VMNAME"
    fi

    xe vm-uninstall uuid=${SNAPUUID} force=true

done < ${UUIDFILE}

BACKUPPATH=${MOUNTPOINT}/${XSNAME}/
BACKUPDIRS=$(find $BACKUPPATH  -maxdepth 1 -type d -printf "%T@ %Tc %p\n"  | sort -n -r | cut -d' ' -f8 |  grep -v "^$BACKUPPATH$")

    if [ $LOGLEVEL -ne 0 ]
    then
	BACKUPS=$(find $BACKUPPATH  -maxdepth 1 -type d -printf "%T@ %Tc %p\n"  | sort -n -r | cut -d' ' -f8 |  grep -v "^$BACKUPPATH$" | wc -l)
	COUNT=$BACKUPS-$MAXBACKUPS
	echo "$BACKUPS found - remove $COUNT"
	logger "$0: $BACKUPS found - remove $COUNT"
    fi    

COUNT=0
for BDIR in $BACKUPDIRS;do
	if [ COUNT –gt $MAXBACKUPS ]
	then
		rm -rf $BDIR	
	fi
	COUNT=$COUNT+1
done

        BACKUPS=$(find $BACKUPPATH  -maxdepth 1 -type d -printf "%T@ %Tc %p\n"  | sort -n -r | cut -d' ' -f8 |  grep -v "^$BACKUPPATH$" | wc -l)
        COUNT=$BACKUPS-$MAXBACKUPS

   if [ $BACKUPS != $COUNT ]
   then
	   echo "Error: not all old backups are removed"
	   logger: "$0: Error: not all old backups are removed"
   else
	   if [ $LOGLEVEL -ne 0 ]
	   then
		   echo "old backups are removed"
		   logger "$0: old backups are removed"
	   fi
   fi	   

if [ $LOGLEVEL -ne 0 ]
then
	    echo "unmount NFS $MOUNTPOINT" 
	    logger "$0: unmount NFS $MOUNTPOINT"
fi

umount ${MOUNTPOINT}

echo "Xen Server VM Backup finished"
logger "$0: Xen Server VM Backup finished"

exit 0 
