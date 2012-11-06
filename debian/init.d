#!/bin/bash
### BEGIN INIT INFO
# Provides:          cyrus-ugent
# Required-Start:    $all
# Required-Stop:     $all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# X-Interactive:     false
# Short-Description: Start/stop Cyrus mailstores.
### END INIT INFO
#
# cyrus-ugent	/etc/init.d/ script for cyrus IMAPd
#		This file manages the Cyrus IMAPd master process.
#
#		Copr. 2010 by Rudy Gevaert <Rudy.Gevaert@UGent.be>
#		Distributed under the GPL version 3 or later

# Make sure we get sane results on borked locales
LC_ALL=C
export LC_ALL

NAME=cyrus-ugent
DESC="UGent Cyrus mailstore"
DEFAULT_FILE=/etc/default/$NAME

test -e $DEFAULT_FILE && . $DEFAULT_FILE

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions

. /lib/cyrus-ugent/script-functions

# Function that starts all cyrus instances
# Parameters: none
# Return value: none
do_startall()
{
	do_startreplicas
	do_startmasters
}

do_startmasters()
{

	get_master_instances
	masters=$INSTANCES

	for instance in $masters

	do
		start_instance $instance
	done
}

do_startreplicas()
{

	get_replica_instances
	replicas=$INSTANCES

	for instance in $replicas

	do
		start_instance $instance
	done
}

# Function that stops all cyrus instances
# Parameters: none
# Return value: none
do_stopall()
{
	do_stopmasters
	do_stopreplicas
}

do_stopmasters()
{
	get_master_instances
	masters=$INSTANCES

	# Start first replica's
	for instance in $masters
	do
		stop_instance $instance
	done
}

do_stopreplicas()
{
	get_replica_instances
	replicas=$INSTANCES

	for instance in $replicas
	do
		stop_instance $instance
	done
}

# Function that restarts all cyrus instances
# Parameters: none
# Return value: none
do_restartall()
{
	do_restartreplicas
	do_restartmasters
}

do_restartmasters()
{
	get_master_instances
	masters=$INSTANCES
	for instance in $masters
	do
		stop_instance $instance
		start_instance $instance
	done
}

do_restartreplicas()
{
	get_replica_instances
	replicas=$INSTANCES
	for instance in $replicas
	do
		stop_instance $instance
		start_instance $instance
	done
}

# Function that reloads all cyrus instances
# Sends -HUP signal to the master process
# Parameters: none
# Return value: none
do_reloadall()
{
	do_reloadreplicas
	do_reloadmasters
}

do_reloadmasters()
{
	get_master_instances
	masters=$INSTANCES
	for instance in $masters
	do
		reload_instance $instance
	done
}

do_reloadreplicas()
{
	get_replica_instances
	replicas=$INSTANCES
	for instance in $replicas
	do
		reload_instance $instance
	done
}


# Function that starts a single cyrus master instance
# Parameters:
#       $1 = hostname of instance
# Return value:
#       0 on success (does not mean the instance started)
#       1 on failure
start_instance()
{
	INSTANCE=$1
        log_daemon_msg "Starting $DESC $INSTANCE"

	log_progress_msg "offline-check..."
	if ! output=`/usr/share/cyrus-ugent/cyrus-isoffline $INSTANCE`
	then
		r=$?
		log_failure_msg $output
		return $r
	fi

	mkdir -p /mail/$INSTANCE

	log_progress_msg "lun"
	mount_param=${INSTANCE}_mount

	if [ "${!mount_param}" != "local" ]
	then
		if ! output=`/usr/share/cyrus-ugent/cyrus-lun mount $INSTANCE ${!mount_param} force`
		then
			log_failure_msg $output
			return $?
		fi
	fi

	log_progress_msg "interface"
	if ! output=`/usr/share/cyrus-ugent/cyrus-interface up $INSTANCE force`
	then
		log_failure_msg $output
		return $?
	fi

	log_progress_msg "snmpd"
	if ! output=`/usr/share/cyrus-ugent/cyrus-snmpd start $INSTANCE force`
	then
		log_failure_msg $output
		return $?
	fi

	log_progress_msg "stunnel"
	if ! /usr/share/cyrus-ugent/cyrus-stunnel start $INSTANCE force
	then
		log_failure_msg
		return $?
	fi

	log_progress_msg "config-update"
	if ! /usr/share/cyrus-ugent/cyrus-mailstore update $INSTANCE
	then
		log_warning_msg
	fi

	log_progress_msg "master"
	if ! /usr/share/cyrus-ugent/cyrus-master start $INSTANCE force
	then
		log_failure_msg
		return $?
	fi
        # Started successfully.
	log_end_msg $?
}

# Function that starts a single saslauthd instance
# Parameters:
#       $1 = hostname of instance
# Return value:
#       0 on success (daemon was stopped)
#       1 if the daemon was already stopped
#       2 if the daemon could not be stopped
stop_instance()
{
	INSTANCE=$1
        log_daemon_msg "Stopping $DESC $INSTANCE"

	log_progress_msg "master"
	/usr/share/cyrus-ugent/cyrus-master stop $INSTANCE force
	if [ $? != 0 ]; then
		log_failure_msg $?
	fi

	log_progress_msg "stunnel"
	/usr/share/cyrus-ugent/cyrus-stunnel stop $INSTANCE force
	if [ $? != 0 ]; then
		log_failure_msg $?
	fi

	log_progress_msg "snmpd"
	/usr/share/cyrus-ugent/cyrus-snmpd stop $INSTANCE force
	if [ $? != 0 ]; then
		log_failure_msg $?
	fi

	log_progress_msg "interface"
	/usr/share/cyrus-ugent/cyrus-interface down $INSTANCE force
	if [ $? != 0 ]; then
		log_failure_msg $?
	fi

	log_progress_msg "kill-procs"
	/usr/share/cyrus-ugent/cyrus-lsof -i $INSTANCE -k

	log_progress_msg "lun"
	mount_param=${INSTANCE}_mount
	if [ "${!mount_param}" != "local" ]
	then
		/usr/share/cyrus-ugent/cyrus-lun unmount $INSTANCE ${!mount_param} force
		if [ $? != 0 ]; then
			log_failure_msg $?
			return $?
		fi
	fi

        # Stopped successfully.
	log_end_msg $?
}



# Function that reloads a mailstore instance
# Parameters:
#       $1 = hostname of instance
# Return value:
#       0 on success
#       1 on failure
reload_instance()
{
	INSTANCE=$1
        log_daemon_msg "Reloading $DESC $INSTANCE"

	/usr/share/cyrus-ugent/cyrus-master reload $INSTANCE force
	log_end_msg $?
}


# Function that outputs the status of our cyrus instances
do_statusall()
{
	get_instances
	for instance in $INSTANCES
	do
		status_instance $instance
	done
}

# Function that gives the status of a cyrus instance
# Parameters:
#       $1 = hostname of instance
status_instance()
{
	INSTANCE=$1
#	set -x


	r=0
#        log_daemon_msg "Status of $DESC $INSTANCE" "network" 

#	log_progress_msg "network..."
#	if ! output=`/usr/share/cyrus-ugent/cyrus-isoffline $INSTANCE`
#	then
#		r=$?
#		log_failure_msg $output
#		return $r
#	fi

        log_daemon_msg "Status of $DESC $INSTANCE"
	echo ""
	log_progress_msg "lun "
	mount_param=${INSTANCE}_mount

	if [ "${!mount_param}" != "local" ]
	then
		if ! output=`/usr/share/cyrus-ugent/cyrus-lun status $INSTANCE ${!mount_param} force`
		then
			r=$?
			log_failure_msg "$output"
		else
			echo "ok"
		fi
	fi
		
	log_progress_msg "interface "
	if ! /usr/share/cyrus-ugent/cyrus-interface status $INSTANCE force
	then
		echo "down"
	else
		echo "up"
	fi

	log_progress_msg "snmpd"
	if ! /usr/share/cyrus-ugent/cyrus-snmpd status $INSTANCE force
	then
		r=$?
		echo " down"
	else
		echo " running"
	fi

	log_progress_msg "stunnel"
	if ! /usr/share/cyrus-ugent/cyrus-stunnel status $INSTANCE force
	then
		r=$?
		echo " down"
	else
		echo " running"
	fi

	log_progress_msg "master"
	if ! /usr/share/cyrus-ugent/cyrus-master status $INSTANCE force
	then
		r=$?
		echo " down"
	else
		echo " running"
	fi

	if [ $r -eq 0 ]
	then
		log_end_msg
		return $r
	else
		return $r
	fi
}

function usage
{
                USAGE="Usage: $0 {start|stop|restart|reload|status}
		    $0 {start-masters|stop-masters}
		    $0 {start-replicas|stop-replicas}
		    $0 {restart-masters|restart-replicas} 
		    $0 {reload-masters|reload-replicas} 
                    $0 {start-instance|stop-instance|restart-instance|reload-instance} <instance name>"
                error_exit "$USAGE"
}

function do_nothing
{
  echo "/etc/cyrus-ugent/init.lock exists, not running init"
  exit 0
}

[ -e /etc/cyrus-ugent/init.lock ] && do_nothing

case "$1" in
        start)
                do_startall
                ;;
        start-masters)
                do_startmasters
                ;;
        start-replicas)
                do_startreplicas
                ;;
        stop)
                do_stopall
                ;;
        stop-masters)
                do_stopmasters
                ;;
        stop-replicas)
                do_stopreplicas
                ;;
        restart)
                do_restartall
                ;;
        restart-masters)
                do_restartmasters
                ;;
        restart-replicas)
                do_restartreplicas
                ;;
	status)
		do_statusall
		;;
        reload)
	        do_reloadall
		;;
        reload-masters)
	        do_reloadmasters
		;;
        reload-replicas)
	        do_reloadreplicas
		;;
        start-instance)
		[ -z $2 ]  && usage
		start_instance $2
                ;;
        stop-instance)
		[ -z $2 ]  && usage
		stop_instance $2
                ;;
        restart-instance)
		[ -z $2 ]  && usage
		stop_instance $2
		start_instance $2
                ;;
        reload-instance)
		[ -z $2 ]  && usage
		reload_instance $2
                ;;
        status-instance)
		[ -z $2 ]  && usage
		status_instance $2
                ;;
        *)
		usage
                ;;
esac
