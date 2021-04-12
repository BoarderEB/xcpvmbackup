#!/bin/bash
#
# Fork: Boardereb
# Only tested on XCP-NG
# GPLv2+
# V: 0.01-Beta1
##############################
# Pre-Fork:
# Written By: Mr Rahul Kumar
# Created date: Jun 14, 2014
# Visit: https://tecadmin.net/backup-running-virtual-machine-in-xenserver/
##############################


### To change:

NFS_SERVER_IP="192.168.10.100"
FILE_LOCATION_ON_NFS="/remote/nfs/location"
MAXBACKUPS="2"

### For Parallel run the export
PARALEL="true"
### Limit for maximum number of parallel runs
#MAXPARALEL="2"

### Loglevel 0=only Errors
### Loglevel 1=start, exit, warn and errors
### Loglevel 2=every action

LOGLEVEL="2"
SYSLOGER="true"

### Set SysLoggerPath if not "logger"
#SYSLOGGERPATH="/usr/bin/logger"

### GPG
### make shure the you pgp-public-key is importet in the xcp-server
### gpg2 --import gpg-pub-key.asc
### if you like to test in this system import and export you neet also do import the secret-keys
### gpg2 --import gpg-secret-key.asc
### for import - export test:
### $ echo "YES GPG WORKS" | gpg2 --encrypt -a --recipient KEY-ID_or_Name --trust-model always | gpg2 --decrypt

#GPG="true"

### if you only imported 1 gpg-public-key on the system, you find the key-id with this:
### $ gpg2 --list-public-keys --keyid-format LONG | grep 'pub ' | cut -d' ' -f4 | cut -d'/' -f2
#GPGID="key-id or Name"

### Send Log-Email with mailx - make sure it is configured:
### echo "bash testmail" | mail -s "testmail from bash" "your@email.com"
#LOGMAIL="true"
#MAILADRESS="your@email.com" ### if not set send mail to $USER

### int. Variablen

XSNAME=$(echo "$HOSTNAME")
INTRANDOME=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
MOUNTPOINT=$(echo "/mnt/xcpvmbackup")-$(echo $INTRANDOME)
DATE=$(date +%d-%m-%Y)-$(echo $INTRANDOME)
MAILFILE=$(mktemp /tmp/mail.XXXXXXXXX)

### LOGGERMASSAGE function
### Var1: LOGGERMASSAGE LOGLEVEL "LOGMASSAGE"
### Var2: LOGGERMASSAGE "LOGMASSAGE" = LOGLEVEL 1 = only start and stop

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
  local TIME=$(date +'%H:%M')
  local NUMBER='^[0-9]+$'
  if [[ $1 =~ $NUMBER ]]; then
    local LOGGERMASSAGELEVEL="$1"
    local LOGGERMASSAGE="$2"
  else
    local LOGGERMASSAGELEVEL="2"
    local LOGGERMASSAGE="$1"
  fi
  if [[ $LOGGERMASSAGELEVEL -le $LOGLEVEL ]]; then
    echo $0: $LOGGERMASSAGE
    echo $TIME: $0:  $LOGGERMASSAGE >> $MAILFILE
    SYSLOGGER "$0: $LOGGERMASSAGE"
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
  REMOVEMOUNT
  SNAPREMOVE
  MAILTO
  rm $MAILFILE
  LOGGERMASSAGE 1 "$0: Xen Server VM Backup finished"
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
### $(FREESPACE VM-UUID BACKUPDIR (+ADD-size-to-VM))
### $(FREESPACE 0bb5b07c-8797-79bc-719d-0da70aa6f7d4 /mnt/nfs (12345678))
### return "true" or "false"

### $(FREESPACE -n) is there enough free space
### $(FREESPACE -n BACKUPDIR (+ADD-size-to-VM))
### $(FREESPACE -n /mnt/nfs (12345678))
### return "true" or "false"

### $(FREESPACE -s) return size(s) of DISK of VM
### $(FREESPACE -s VM-UUID (+ADD-size-to-VM))
### $(FREESPACE -s 0bb5b07c-8797-79bc-719d-0da70aa6f7d4 + 12345678)
### return "size = VM-Size (+Add-Size)" = 12345678

function FREESPACE() {
  if [[ "$1" == "-s" ]]; then
    local SPACE="true"
    local UUID=$2
    if [[ ! -z $3 ]]; then
     local DISKSPACE=$3
    else
        local DISKSPACE=0
    fi
  else
    local UUID=$1
    local DIR=$2
    if [[ ! -z $3 ]]; then
      local DISKSPACE=$3
    else
        local DISKSPACE=0
    fi
  fi

 if [[ "$1" == "-n" ]]; then
        local DISKLIST=0
 else
        local DISKLIST=$(xe vm-disk-list vm=$UUID vdi-params=virtual-size | grep "virtual-size" | grep -oP "[0-9]+$" )
 fi

  while IFS= read -r DISK
  do
    local DISKSPACE=$(echo $DISK $DISKSPACE | awk '{print $1 + $2}')
  done <<< "$DISKLIST"
  if [[ -z $SPACE ]]; then
    local FREESPACE=$(df --block-size=1 $DIR --output=avail | sed -e 1d)
    if [[ $DISKSPACE -lt  $FREESPACE ]]; then
      echo "true"
    else
      echo "false"
    fi
  else
    echo "$DISKSPACE"
  fi
}

### test is there a ongoing paralel run vm export
function PARALELRUN() {
  local PARALELRUNS=$(ps --forest -o pid=,tty=,stat=,time=,cmd= -g $(ps -o sid= -p $$) | grep "xe vm-export vm=" | grep -v "grep")
  if [[ -z ${PARALELRUNS} ]]; then
    if [[ $1 == "-c" ]]; then
        echo "0"
    else
        echo "false"
    fi
  else
    if [[ $1 == "-c" ]]; then
        local COUNT=$(ps --forest -o pid=,tty=,stat=,time=,cmd= -g $(ps -o sid= -p $$) | grep "xe vm-export vm=" | grep -v "grep" | wc -l)
        echo "$COUNT"
    else
    echo "true"
    fi
  fi
}

### Is there the specified GPG key?
function TESTGPG() {
  if [[ $GPG == "true" ]]; then
    if [[ ! -z $GPGID ]]; then
      gpg2 --list-public-keys "$GPGID" >> /dev/null
      if [[ $? -ne 0 ]]; then
        LOGGERMASSAGE 0 "Error: GPG-KEY-ID not found"
        echo "false"
      else
        echo "true"
      fi
    fi
  fi
}

### remove all SNAPSHOTS FROM THIS BACKUP
function SNAPREMOVE() {
  local SNAPTOREMOVE=$(xe vm-list is-control-domain=false is-a-snapshot=true | grep $INTRANDOME | sed 's/^\s*[n][a][m][e][-][l][a][b][e][l]\s*[(]\s*[R][W]\s*[)][:]\s*//g')
  if [[ ! -z $SNAPTOREMOVE ]]; then
    while IFS= read -r NAME
    do
      LOGGERMASSAGE "remove snapshoot from: $NAME"
      xe vm-uninstall vm=${NAME} force=true
      if [[ $? -ne 0 ]]; then
        LOGGERMASSAGE 0 "Error: When remove snapshoot from: $NAME - see xcp-syslog"
        PARALELEROROR="true"
      fi
    done <<< "$SNAPTOREMOVE"
  fi
}

## safe all PID FORM PARALEL xe vm-export to $PIDLIST
function VMEXPPID() {
  if [[ -z $PIDLIST ]]; then
    PIDLIST="$1"
  else
    PIDLIST="$PIDLIST,$1"
  fi
}

function REMOVEMOUNT() {
  # unmount if not befor for the script moundet
  if [[ $MOUNDET != "allrady"  ]]; then
    LOGGERMASSAGE "unmount NFS $MOUNTPOINT"
  	umount $MOUNTPOINT
    if [[ $? -eq 0 ]]; then
      if [[ ! -z MOUNTEXIST ]]; then
        LOGGERMASSAGE "delete the created mountpoint $MOUNTPOINT"
        rm -rf $MOUNTPOINT
      fi
    else
      LOGGERMASSAGE 0 "Error: could not umount $MOUNTPOINT because of that not deleted"
    fi
  fi
}

LOGGERMASSAGE 1 "start Xen Server VM Backup"

### Create mount point
LOGGERMASSAGE "create mountpoint $MOUNTPOINT if not exist"

if [[ ! -d ${MOUNTPOINT} ]]; then
  mkdir -p $MOUNTPOINT
  if [[ ! -d ${MOUNTPOINT} ]]; then
  	LOGGERMASSAGE 0 "Error: No mount point found, kindly check"
  	QUIT 1
  fi
else
  MOUNTEXIST="true"
fi

### check if nfs allrady moundet if not mount
MOUNDET=$(stat -c%d "$MOUNTPOINT")
MOUNT=$(grep "$NFS_SERVER_IP:$FILE_LOCATION_ON_NFS $MOUNTPOINT" /proc/mounts | grep $MOUNTPOINT)
if [[ -z $MOUNT ]]; then
    LOGGERMASSAGE "mount NFS $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS"
    mount -t nfs $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS $MOUNTPOINT
    if [[ `stat -c%d "$MOUNTPOINT"` -eq $MOUNDET ]]; then
      LOGGERMASSAGE 0 "Error: Coult not mount $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS $MOUNTPOINT"
      QUIT 1
    fi
else
  MOUNDET="allrady"
  LOGGERMASSAGE "$NFS_SERVER_IP:$FILE_LOCATION_ON_NFS $MOUNTPOINT allrady mounted"
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
VMUUIDS=$(xe vm-list is-control-domain=false is-a-snapshot=false | grep uuid | sed 's/\s*[u][u][i][d]\s*[(]\s*[R][O]\s*[)]\s*[:]\s*//g')
if [[ -z ${VMUUIDS} ]]; then
	LOGGERMASSAGE 0 "Error: NO VM found for backup"
	QUIT 1
fi

### what is the maximum size of all backups = $DISKSPACE
while IFS= read -r VMUUID
do
  DISKSPACE=$(FREESPACE -s $VMUUID $DISKSPACE)
done <<< "$VMUUIDS"

### if not enough space for all vm in maximum together do normal run
if [[ $PARALEL == "true" ]]; then
if [[ $(FREESPACE -n $MOUNTPOINT $DISKSPACE) == "false" ]]; then
  LOGGERMASSAGE 1 "Warn: Not enough space for all vm in maximum together on $MOUNTPOINT - go on in sequential run"
  PARALEL="false"
fi
fi

### start snapshot and export
while IFS= read -r VMUUID
do
  VMNAME=`xe vm-list uuid=$VMUUID | grep name-label | sed 's/^\s*[n][a][m][e][-][l][a][b][e][l]\s*[(]\s*[R][W]\s*[)][:]\s*//g'`

  if [[ $PARALEL == "true" ]]; then

    ### check if maximum number on paralel runs is reached
    if [[ ! -z $MAXPARALEL ]]; then
      while true; do
        if [[ $(PARALELRUN -c) -ge $MAXPARALEL ]]; then
          sleep 100
        else
          break
        fi
      done
    fi

    LOGGERMASSAGE "Paralel run: create snapshoot from: $VMNAME"
    SNAPUUID=$(xe vm-snapshot uuid=$VMUUID new-name-label="SNAPSHOT-$VMNAME-$DATE")
    xe template-param-set is-a-template=false ha-always-run=false uuid=$SNAPUUID
    if [[ $? -ne 0 ]]; then
      LOGGERMASSAGE 0 "Error: Paralel run - When create snapshoot from: $VMNAME  - see xcp-syslog"
      PARALELEROROR="true"
    fi

    if [[ $GPG == "true" ]]; then
        if [[ $(TESTGPG) == "true" ]]; then
          LOGGERMASSAGE "Paralel run: export snapshoot $VMNAME gpg encoded to $BACKUPPATH"
          {
            xe vm-export vm=${SNAPUUID} filename= | gpg2 --encrypt -a --recipient $GPGID --trust-model always > "$BACKUPPATH/$VMNAME-$DATE.xva.gpg"
            if [[ ${PIPESTATUS[0]} != 0 ]]; then
              GPGEXPORTERROR="true"
            fi
          } &
          VMEXPPID $(ps ax | grep "xe vm-export vm=${SNAPUUID}" | grep -v "grep" | cut -d" " -f1)
        else
          LOGGERMASSAGE 0 "Error: GPG-KEY-ID not found - do not export $VMNAME"
          EXPORTERROR="true"
        fi
    else
      LOGGERMASSAGE "Paralel run: export snapshoot $VMNAME to $BACKUPPATH"
      xe vm-export vm=${SNAPUUID} filename="$BACKUPPATH/$VMNAME-$DATE.xva" &
      VMEXPPID $!
    fi
  fi

### if ther a parralel backup error:
  if [[ ! -z ${PARALELEROROR} ]]; then
    PARALEL="false"
### wait until the last parallel run is finished
    while true; do
      if [[ $(PARALELRUN) != "true" ]]; then
        break
      fi
      sleep 100
    done
### and remove all snapshots from parallel run
    SNAPTOREMOVE=$(xe vm-list is-control-domain=false is-a-snapshot=true | grep $INTRANDOME | sed 's/^\s*[n][a][m][e][-][l][a][b][e][l]\s*[(]\s*[R][W]\s*[)][:]\s*//g')
    while IFS= read -r NAME
    do
      xe vm-uninstall vm=${NAME} force=true
    done <<< "$SNAPTOREMOVE"
  fi
  ### now go on in normal run
  if [[ $PARALEL != "true" ]]; then
    if [[ $(FREESPACE $VMUUID $MOUNTPOINT) != "true" ]]; then
      LOGGERMASSAGE "create snapshoot from: $VMNAME"
      SNAPUUID=`xe vm-snapshot uuid=$VMUUID new-name-label="SNAPSHOT-$VMNAME-$DATE"`
      xe template-param-set is-a-template=false ha-always-run=false uuid=${SNAPUUID}
      if [[ $? -ne 0 ]]; then
        LOGGERMASSAGE 0 "Error: When create snapshoot from: $VMNAME  - see xcp-syslog"
        EXPORTERROR="true"
      fi

      if [[ $GPG == "true" ]]; then
          if [[ $(TESTGPG) == "true" ]]; then
            LOGGERMASSAGE "export snapshoot $VMNAME gpg encoded to $BACKUPPATH"
            xe vm-export vm=${SNAPUUID} filename= | gpg2 --encrypt -a --recipient $GPGID --trust-model always > "$BACKUPPATH/$VMNAME-$DATE.xva.gpg"
            if [[ ${PIPESTATUS[0]} != 0 ]]; then
              GPGEXPORTERROR="true"
            fi
          else
            LOGGERMASSAGE 0 "Error: GPG-KEY-ID not found - do not export $VMNAME"
            EXPORTERROR="true"
          fi
      else
        LOGGERMASSAGE "export snapshoot $VMNAME to $BACKUPPATH"
        xe vm-export vm=${SNAPUUID} filename="$BACKUPPATH/$VMNAME-$DATE.xva"
      fi
      if [[ $? -ne 0 ]]; then
        LOGGERMASSAGE 0 "Error: When export snapshoot $VMNAME to $BACKUPPATH  - see xcp-syslog"
        EXPORTERROR="true"
      fi

      LOGGERMASSAGE "remove snapshoot from: $VMNAME"
    	xe vm-uninstall uuid=${SNAPUUID} force=true
      if [[ $? -ne 0 ]]; then
        LOGGERMASSAGE 0 "Error: When remove snapshoot from: $VMNAME - see xcp-syslog"
      fi
    else
      EXPORTERROR="true"
      LOGGERMASSAGE 0 "Error: not enough space to export $VMNAME to $MOUNTPOINT"
    fi
  fi
done <<< "$VMUUIDS"

### Wait for all backups to be exported
while true; do
  if [[ $(PARALELRUN) != "true" ]]; then
    break
  fi
  sleep 100
done

### Test if there a xe vm-export error
if [[ ! -z $PIDLIST ]]; then
  IFS=,
  for PID in $PIDLIST;
  do
    while true; do
      PSPID=$(ps aux | grep "$PID" | grep -v "grep")
      if [[ -z $PSPID ]]; then
        break
      fi
      sleep 3
    done
    wait $PID
    if [[ $? -ne 0 ]]; then
      LOGGERMASSAGE 0 "Error: Paralel run: When export snapshoot - see xcp-syslog"
      EXPORTERROR="true"
    else
      PARALELEXIT="OK"
    fi
  done
fi

if [[ ! -z $GPGEXPORTERROR ]]; then
      LOGGERMASSAGE 0 "Error: Paralel run: When export snapshoot gpg encodet - see xcp-syslog"
      EXPORTERROR="true"
fi

if [[ $PARALELEXIT == "OK" ]]; then
  if [[ -z $EXPORTERROR ]]; then
    LOGGERMASSAGE "Paralel run: Export of vm successfully"
  fi
fi


### Remove old Backups
if [[ -z "$EXPORTERROR" ]]; then
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
else
  LOGGERMASSAGE 0 "Error: Do not remove old Backups becouse a error in the new backup"
fi


### YIPPI we are finished

if [[ ! -z "$EXPORTERROR" ]]; then
  QUIT 1
fi

QUIT 0
