INTRANDOME=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)

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
  if [[ $1 -eq "-n" ]]; then
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

UUIDS=$(xe vm-list is-control-domain=false is-a-snapshot=false | grep uuid | cut -d":" -f2)

while IFS= read -r VMUUID
do
        DISKSPACE=$(FREESPACE -s $VMUUID $DISKSPACE)
done <<< "$UUIDS"
# echo "$DISKSPACE"


## take snapshoot
while IFS= read -r VMUUID
do
VMNAME=`xe vm-list uuid=$VMUUID | grep name-label | cut -d":" -f2 | sed 's/^ *//g'`
if [[ $(FREESPACE -n $MOUNTPOINT $DISKSPACE) == "true" ]] && if [[ $PARALEL == "true" ]]; then

  SNAPUUID=$(xe vm-snapshot uuid=$VMUUID new-name-label="SNAPSHOT-$VMNAME-$DATE")
  xe template-param-set is-a-template=false ha-always-run=false uuid=$SNAPUUID
  if [[ $? -ne 0 ]]; then
    LOGGERMASSAGE 0 "Error: When create snapshoot from: $VMNAME  - see xcp-syslog"
    PARALELEROROR="true"
  fi

  if [[ -z $EXPORTERRORPARLEL ]]; then
    xe vm-export vm=${SNAPUUID} filename="$BACKUPPATH/$VMNAME-$DATE.xva" &
  fi

fi

### if ther a parralel backup error:
### wait until the last parallel run is finished
if [[ ! -z ${PARALELEROROR} ]]; then
    PARALEL="false"
    while true; do
    PARALELRUN=$(ps aux | grep "xe vm-export vm=" | grep -v "grep")
    if [[ -z ${PARALELRUN} ]]; then
      break
    fi
    sleep 10
  done
### and remove all snapshots from parallel run
  SNAPTOREMOVE=$(xe vm-list is-control-domain=false is-a-snapshot=true | grep cTezWBgsox | cut -d":" -f2)
  while IFS= read -r NAME
  do
    xe vm-uninstall vm=${NAME} force=true
  done <<< "$SNAPTOREMOVE"
fi
### now go on in normal run
if [[ $PARALEL -ne "true" ]]; then
  if [[ $(FREESPACE $VMUUID $MOUNTPOINT) == "true" ]]; then
    LOGGERMASSAGE "create snapshoot from: $VMNAME"
    SNAPUUID=`xe vm-snapshot uuid=$VMUUID new-name-label="SNAPSHOT-$VMNAME-$DATE"`
    xe template-param-set is-a-template=false ha-always-run=false uuid=${SNAPUUID}
    if [[ $? -ne 0 ]]; then
      LOGGERMASSAGE 0 "Error: When create snapshoot from: $VMNAME  - see xcp-syslog"
      EXPORTERROR="true"
    fi

    if [[ $GPG -eq "true" ]]; then
        if [[ $(TESTGPG) == "true" ]]; then
          LOGGERMASSAGE "export snapshoot $VMNAME gpg encoded to $BACKUPPATH"
          xe vm-export vm=${SNAPUUID} filename= | gpg2 --encrypt -a --recipient $GPGID --trust-model always > "$BACKUPPATH/$VMNAME-$DATE.xva.gpg"
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

done <<< "$UUIDS"

### remove all SNAPSHOTS FROM THIS BACKUP
SNAPTOREMOVE=$(xe vm-list is-control-domain=false is-a-snapshot=true | grep cTezWBgsox | cut -d":" -f2)
while IFS= read -r NAME
do
  xe vm-uninstall vm=${NAME} force=true
done <<< "$SNAPTOREMOVE"
