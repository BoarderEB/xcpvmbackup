#!/bin/bash


LOGMAIL="true"
#MAILADRESS="your@email.com" # if not set send mail to $USER

# Loglevel 0=Only Errors
# Loglevel 1=start and exit and Errors
# Loglevel 2=every action

LOGLEVEL=2
SYSLOGER="true"

MAILFILE=$(mktemp /tmp/mail.XXXXXXXXX)

#SET SYSLOGGERSYSLOGGERPATH IF NOT "logger"
#SYSLOGGERPATH="/usr/bin/logger"

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
      echo $0: $2 >> $MAILFILE
	 	  SYSLOGGER "$0: $2"
    else
      echo $0: $1 $2
      echo $0: $1 $2 >> $MAILFILE
	 	  SYSLOGGER "$0: $1 $2"
    fi
  else
    if [[ $1 -le $LOGLEVEL ]]; then
      echo $0: $2
      echo $0: $2 >> $MAILFILE
      SYSLOGGER "$0: $2"
    fi
  fi
}

function QUIT() {
  if [[ $LOGMAIL == "true" ]]; then
    if [[ $(cat $MAILFILE) != '' ]]; then

      if [[ -z ${MAILADRESS} ]]; then
        MAILADRESS=$USER
      fi

      if [[ $(cat $MAILFILE | grep -i "error") != '' ]]; then
        SUBJECT="xcpvmbackup-error: from xcp.server"
      else
        SUBJECT="xcpvmbackup-log: from xcp.server"
      fi

      cat $MAILFILE | mail -s "$SUBJECT" "$MAILADRESS"
    fi
  fi
  rm $UUIDFILE
  rm $MAILFILE
  exit $1
}

LOGGERMASSAGE "Error: importend error!
LOGGERMASSAGE "some more?"
LOGGERMASSAGE "yup!"

QUIT 0
