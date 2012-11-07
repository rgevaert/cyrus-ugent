#
# Regular cron jobs for the cyrus-ugent package
#
0 4	* * *	root	[ -x /usr/bin/cyrus-ugent_maintenance ] && /usr/bin/cyrus-ugent_maintenance
