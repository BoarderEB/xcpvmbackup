#!/bin/bash
#
# Written By: Mr Rahul Kumar
# Created date: Jun 14, 2014
# Last Updated: Mar 08, 2017
# Version: 1.2.1
# Visit: https://tecadmin.net/backup-running-virtual-machine-in-xenserver/
#
# Fork: Boardereb
# Only tested on XCP-NG

# To change:

NFS_SERVER_IP="192.168.10.100"
MOUNTPOINT=/mnt/nfs
FILE_LOCATION_ON_NFS="/remote/nfs/location"
MAXBACKUPS=2

# Loglevel 0=Only Errors
# Loglevel 1=start and exit and Errors
# Loglevel 2=every action

LOGLEVEL=1
SYSLOGER="true"
LOGMAIL="true"
#MAILADRESS="your@email.com" # if not set send mail to $USER

#SET SYSLOGGERSYSLOGGERPATH IF NOT "logger"
#SYSLOGGERPATH="/usr/bin/logger"

# int. Variablen

XSNAME=`echo $HOSTNAME`
DATE=$(date +%d-%m-%Y)-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
UUIDFILE=$(mktemp /tmp/uuids.XXXXXXXXX)
MAILFILE=$(mktemp /tmp/mail.XXXXXXXXX)

## LOGGERMASSAGE function
## Var1: LOGGERMASSAGE LOGLEVEL "LOGMASSAGE"
## Var2: LOGGERMASSAGE "LOGMASSAGE" = LOGLEVEL 1 = only start and stop

function SYSLOGGER() {
  if [[ SYSLOGER -eq "true" ]]; then
    if [ -z ${SYSLOGGERPATH} ];then
      if hash logger 2>/dev/null; then
        logger $1
      fi
    else
      if [[ -x ${SYSLOGGERPATH} ]]; then
        $SYSLOGGERPATH $1
      fi
    fi
  fi
}

function LOGGERMASSAGE() {
  if [[ $LOGLEVEL > 1 ]]; then
    if [[ $1 =~ ^[0-9]+$ ]]; then
    	echo $0: $2
      echo "$0: $2" >> $MAILFILE
	 	  SYSLOGGER "$0: $2"
    else
      echo $0: $1 $2
      echo "$0: $1 $2" >> $MAILFILE
	 	  SYSLOGGER "$0: $1 $2"
    fi
  else
    if [[ $1 -le $LOGLEVEL ]]; then
      echo $0: $2
      echo "$0: $2" >> $MAILFILE
      SYSLOGGER "$0: $2"
    fi
  fi
}

### Send Mail

function MAILTO() {
  if [[ $LOGMAIL == "true" ]]; then
    if [[ $(cat $MAILFILE) != '' ]]; then
      if [[ -z ${MAILADRESS} ]]; then
        MAILADRESS=$USER
      fi
      if [[ $(cat $MAILFILE | grep -i "error") != '' ]]; then
        SUBJECT="xcpvmbackup-error: from $XSNAME"
      else
        SUBJECT="xcpvmbackup-log: from $XSNAME"
      fi
      cat $MAILFILE | mail -s "$SUBJECT" "$MAILADRESS"
    fi
  fi
}

### commands before exit + cleans up + exit the script
### QUIT "EXITCODE"
### QUIT 0 = exit 0

function QUIT() {
  MAILTO
  rm $UUIDFILE
  rm $MAILFILE
  exit $1
}

### get a List of Backupdirs
### -c = count of Backupsdirs
### $(BACKUPDIRS -c)

function BACKUPDIRS() {
  local BACKUPPATH="$MOUNTPOINT/$XSNAME/"
  local BACKUPDIRS=$(find $BACKUPPATH  -maxdepth 1 -type d -printf "%T@ %p\n"  | sort -n -r | cut -d' ' -f2 |  grep -v "^$BACKUPPATH$" | grep -v "^.$")
  if [[ $1 = "-c" ]]; then
    local BACKUPDIRS=$(echo "$BACKUPDIRS" | wc -l)
  fi
  echo "$BACKUPDIRS"
}

### is there enough free space
### return "true" or "false"
### $(FREESPACE VM-UUID BACKUPDIR)
### $(FREESPACE 0bb5b07c-8797-79bc-719d-0da70aa6f7d4 /mnt/nfs)

function FREESPACE() {
  DISKLIST=$(xe vm-disk-list vm=$1 vdi-params=virtual-size | grep "virtual-size" | grep -oP "[0-9]+$" )
  for DISK in "$DISKLIST"; do
    DISKSPACE=$(echo $DISK $DISKSPACE | awk '{print $1 + $2}')
  done

  FREESPACE=$(df --block-size=1 $2 --output=avail | sed -e 1d)

  if [[ $DISKSPACE -lt  $FREESPACE ]]; then
    echo "true"
  else
    echo "false"
  fi
}

LOGGERMASSAGE 1 "start Xen Server VM Backup"

### Create mount point
LOGGERMASSAGE "create mountpoint $MOUNTPOINT if not exist"
mkdir -p $MOUNTPOINT
if [[ ! -d ${MOUNTPOINT} ]]; then
	LOGGERMASSAGE 0 "Error: No mount point found, kindly check"
	QUIT 1
fi

### check if nfs allrady moundet if not mount
MOUNDET=$(stat -c%d "$MOUNTPOINT")
if grep -qs "$NFS_SERVER_IP:$FILE_LOCATION_ON_NFS $MOUNTPOINT" /proc/mounts; then
  MOUNDET="allrady"
  LOGGERMASSAGE "$NFS_SERVER_IP:$FILE_LOCATION_ON_NFS $MOUNTPOINT allrady mounted"
else
  LOGGERMASSAGE "mount NFS $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS"
  mount -t nfs $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS $MOUNTPOINT
fi

if [[ `stat -c%d "$MOUNTPOINT"` -eq $MOUNDET ]]; then
  LOGGERMASSAGE 0 "Error: Coult not mount $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS $MOUNTPOINT"
  QUIT 1
fi

### creat backuppath if not exist
BACKUPPATH="$MOUNTPOINT/$XSNAME/$DATE"
LOGGERMASSAGE "create backuppath $BACKUPPATH if not exist"
mkdir -p $BACKUPPATH

if [[ ! -d ${BACKUPPATH} ]]; then
	LOGGERMASSAGE 0 "Error: No backup directory found"
	QUIT 1
fi

### Fetching list UUIDs of all VMs running on XenServer
LOGGERMASSAGE "create UuidFile ${UUIDFILE}"
xe vm-list is-control-domain=false is-a-snapshot=false | grep uuid | cut -d":" -f2 > ${UUIDFILE}
if [[ ! -f ${UUIDFILE} ]]; then
	LOGGERMASSAGE 0 "Error: Could not create UUID-file"
	QUIT 1
fi

### start snapshot and export
while read VMUUID
do
  VMNAME=`xe vm-list uuid=$VMUUID | grep name-label | cut -d":" -f2 | sed 's/^ *//g'`
  if [[ $(FREESPACE $VMUUID /mnt/nfsbackup) == "true" ]]; then
    LOGGERMASSAGE "create snapshoot from: $VMNAME"
    SNAPUUID=`xe vm-snapshot uuid=$VMUUID new-name-label="SNAPSHOT-$VMNAME-$DATE"`
  	xe template-param-set is-a-template=false ha-always-run=false uuid=${SNAPUUID}

  	LOGGERMASSAGE "export snapshoot $VMNAME to $BACKUPPATH"
  	xe vm-export vm=${SNAPUUID} filename="$BACKUPPATH/$VMNAME-$DATE.xva"

  	LOGGERMASSAGE "remove snapshoot from: $VMNAME"
  	xe vm-uninstall uuid=${SNAPUUID} force=true
  else
    LOGGERMASSAGE 0 "Error: not enough space to export $VMNAME to $MOUNTPOINT"
  fi
done < ${UUIDFILE}

## start remove old backups
BACKUPS=$(BACKUPDIRS -c)
COUNT=$(($BACKUPS-$MAXBACKUPS))
if [[ $COUNT -lt 0 ]]; then
  COUNT=0
fi
LOGGERMASSAGE "$BACKUPS backup found - remove $COUNT old backup"

if [[ $COUNT > 0 ]]; then
  COUNT=1
  for DIR in $(BACKUPDIRS);do
    if [[ $COUNT > $MAXBACKUPS ]]; then
      rm -rf $DIR
    fi
    COUNT=$(($COUNT+1))
  done

  if [[ $(BACKUPDIRS -c) == $MAXBACKUPS ]]; then
    LOGGERMASSAGE "old backups are removed"
  else
    LOGGERMASSAGE 0 "Error: not all old backups are removed"
  fi
fi

# unmount if not befor for the script moundet
if [[ $MOUNDET != "allrady"  ]]; then
  LOGGERMASSAGE "unmount NFS $MOUNTPOINT"
	umount $MOUNTPOINT
fi

### YIPPI we are finished
LOGGERMASSAGE 1 "$0: Xen Server VM Backup finished"
QUIT 1
