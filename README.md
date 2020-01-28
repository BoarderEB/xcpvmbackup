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

### E-Mail notification

You can send the Log to your Email with mailx - make sure it is configured, test it befor with:
> echo "bash testmail" | mail -s "testmail from bash" "your@email.com"

- LOGMAIL="true"
- MAILADRESS="your@email.com" ### if not set send mail to $USER

### Backupspace

The script tests before the backup if there is enough space on the nfs server. Because the size of the backup is not known before the backups, the maximum size of every VM is tested.
