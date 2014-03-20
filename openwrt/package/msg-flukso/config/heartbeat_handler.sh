#!/bin/sh

echo 'timer' > /sys/class/leds/globe/trigger
/usr/bin/heartbeat 0
res=$?
echo 'none' > /sys/class/leds/globe/trigger

if [ $res -eq 0 ];
then
	echo 255 > /sys/class/leds/globe/brightness
else
	echo 0 > /sys/class/leds/globe/brightness
fi
