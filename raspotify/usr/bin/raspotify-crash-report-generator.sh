#!/bin/bash

crash_report="/etc/raspotify/crash_report"
rm -f $crash_report

echo -e "-- System Info --\n" > $crash_report

uname -a >> $crash_report

echo -e "\n-- Logs --\n" >> $crash_report

journalctl -u raspotify --since "1min ago" -q >> $crash_report

systemctl reset-failed raspotify

echo -e "\n-- Config --\n" >> $crash_report

config="/etc/raspotify/conf"

# We don't want user names or passwords in the crash report.
username="LIBRESPOT_USERNAME"
password="LIBRESPOT_PASSWORD"

librespot="LIBRESPOT_"
tmp_dir="TMPDIR"

while read -r line; do
if { [[ $line = $librespot* ]] && [[ $line != $username* ]] && [[ $line != $password* ]]; } || [[ $line = $tmp_dir* ]]
then
	echo "$line" >> $crash_report
fi
done < $config

echo -e "\n-- Ouput of aplay -l --\n" >> $crash_report

aplay -l >> $crash_report

echo -e "\n-- Ouput of aplay -L --\n" >> $crash_report

aplay -L >> $crash_report

echo -e "\n-- Ouput of librespot -d ? --" >> $crash_report

librespot -d ? >> $crash_report 2> /dev/null
