# XCP-ng Server VM Backup

This is a solid handcraft bash script to backup running virtual machines on XCP-ng Servers. This script takes backup of all virtual machine and exports them on NFS Server. You can specify how many backups are keep.

## How to Use Script

Download this script and modify some parameters as per your network and directory structure.

- NFS_SERVER_IP="192.168.10.100"   ## IP of your NFS server.
- FILE_LOCATION_ON_NFS="/remote/nfs/location"  ## Location to store backups on NFS server.

If you like to keep more or less then 2 backups than change this:

- MAXBACKUPS=2

Now execute the script from command line

> $ ./xcpvmbackup.sh

### Cron-Backup

For an automatic backup copy the script to one of this:
/etc/cron.daily or /etc/cron.weekly or /etc/cron.monthly

If you want to have more than one backup loop. Then modify in the scriptcopys in /etc/cron.* :

* XSNAME=$(echo $HOSTNAME) to like this:

- XSNAME=$(echo $HOSTNAME-daily)
- XSNAME=$(echo $HOSTNAME-weekly)
- XSNAME=$(echo $HOSTNAME-monthly)

## Good to know:

### There are 3 loglevel

* Loglevel 0=Only Errors
* Loglevel 1=start and exit and Errors
* Loglevel 2=every action

This will change it:

- LOGLEVEL="1"

### GPG encoding

Make shure the you pgp-public-key is importet in the xcp-server
> gpg2 --import gpg-pub-key.asc

If you like to export the vm encoding with GPG you must set this:
  - GPG="true"

Also you must set the GPG-Key-ID or the Name of the key to be used for encryption.
  - GPGID="key-id or Name"

if you only imported 1 gpg-public-key on the system, you find the key-id with this:
> gpg2 --list-public-keys --keyid-format LONG | grep 'pub ' | cut -d' ' -f4 | cut -d'/' -f2

### E-Mail notification

You can send the Log to your Email with mailx - make sure it is configured, test it befor with:
> echo "bash testmail" | mail -s "testmail from bash" "your@email.com"

- LOGMAIL="true"
- MAILADRESS="your@email.com" ### if not set send mail to $USER

### User rights

The user of the script needs the rights to:

* to run '$ xe vm-snapshot'
* to run '$ xe vm-export'
* to run '$ xe vm-uninstall'
* create directories under /mnt/

### Backupspace

The script tests before the backup if there is enough space on the nfs server. Because the size of the backup is not known before the backups, the maximum size of every VM is tested.

## Restore Backup:

Create mountpoint:
> mkdir /mnt/nfs

Mount nfs server:
> mount -t nfs 192.168.10.100:/remote/nfs/location /mnt/nfs

Import with xe vm-import:
> xe vm-import force=true preserve=true filename=/mnt/nfs/old-server-name/backupdate/vm-name.xva

### Was GPG used:

you must extra import the secred-key on the new system:
> gpg2 --import gpg-secred-key.asc

after this you import with gpg and xe vm-import
> gpg2 --decrypt /mnt/nfs/old-server-name/backupdate/vm-name.xva.gpg | xe vm-import force=true preserve=true filename=/dev/stdin
