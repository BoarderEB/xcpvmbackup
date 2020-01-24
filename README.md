## XCP-ng Server VM Backup

This is a simple bash/shell script to backup running virtual machines on XCP-ng Servers. This script takes backup of virtual machine and store backup on NFS server.

## How to Use Script

Download this script and modify some parameters as per your network and directory structure.

LOGLEVEL=0
SYSLOGER="true"

- MOUNTPOINT=/mnt/nfs   ## change this with your system mount point
- NFS_SERVER_IP="192.168.10.100"   ## IP of your NFS server.
- FILE_LOCATION_ON_NFS="/remote/nfs/location"  ## Location to store backups on NFS server.
- MAXBACKUPS=2 ## Deletes old backups
- LOGLEVEL=0 ## 0=only start and exit / 1=every action
- SYSLOGER="true" ## If "true" also writes in the system logs

Now execute the script from command line

> $ ./xcpvmbackup.sh

You may also schedule this with crontab to run as per backup frequency.

> 0 2 * * * /bin/sh xcpvmbackup.sh
