#!/bin/sh

	# Decide MCS, guard interval, FEC, bit-rate, gop size and power based on the range [1000,2000] from radio
	# Need > wfb_tx v24 (with -C 8000 added to /usr/bin/wifibroadcast) and wfb_tx_cmd v24
	# Need msposd (tipoman9) to update local OSD

if [ -e /etc/txprofile ]; then
	. /etc/txprofile
fi

oldProfile=$vidRadioProfile
newTimeStamp=$(date +%s)
oldTimeStamp=$prevTimeStamp
secondsSinceLastChange=$((newTimeStamp-oldTimeStamp))


	if [ $2 -lt 1015 ] ;then
				
		setGI=long
		setMCS=0
		setFecK=12
		setFecN=15
		setBitrate=3300
		setGop=1.0
		wfbPower=60
		ROIqp="0,0,0,0"		
		newProfile=1
		
	elif [ $2 -lt 1300 ];then
		
		setGI=long
		setMCS=1
		setFecK=12
		setFecN=15
		setBitrate=6700
		setGop=1.0
		wfbPower=59
		ROIqp="12,6,6,12"
		newProfile=2

	elif [ $2 -lt 1700 ];then

		setGI=long
		setMCS=2
		setFecK=12
		setFecN=15
		setBitrate=10000
		setGop=1.0
		wfbPower=58
		ROIqp="12,6,6,12"
		newProfile=3


	elif [ $2 -lt 1850 ];then
						
		setGI=long
		setMCS=3
		setFecK=12
		setFecN=15
		setBitrate=12500
		setGop=1.0
		wfbPower=56
		ROIqp="12,6,6,12"
		newProfile=4

	elif [ $2 -lt 1986 ];then

		setGI=short
		setMCS=3
		setFecK=12
		setFecN=15
		setBitrate=14000
		setGop=1.0
		wfbPower=56
		ROIqp="12,6,6,12"
		newProfile=5
	
	elif [ $2 -gt 1985 ];then

		setGI=short
		setMCS=3
		setFecK=13
		setFecN=15
		setBitrate=15000
		setGop=1.0
		wfbPower=56
		ROIqp="12,6,6,12"
		newProfile=6
					
	fi	

#Decide if it is worth changing or not
profileDifference=$((newProfile - oldProfile))

if [ $profileDifference -eq 1 ] && [ $secondsSinceLastChange -lt 2 ] ; then
	exit 1
elif [ $newProfile -eq $oldProfile ] ;then
	exit 1
fi


# Calculate driver power
setPower=$((wfbPower * 50))


#Decide what order to exectute commands
if [ $newProfile -gt $oldProfile ]; then
###########################################################################	
	# Lower power first
	if [ $prevSetPower -ne $setPower ]; then
		iw dev wlan0 set txpower fixed $setPower
		sleep 0.05
	fi
	
	# Set gopSize
	if [[ "$prevGop" != "$setGop" ]]; then
		curl localhost/api/v1/set?video0.gopSize=$setGop
		sleep 0.05
	fi
	
	# Raise MCS
	if [ $prevMCS -ne $setMCS ]; then
		wfb_tx_cmd 8000 set_radio -B 20 -G $setGI -S 1 -L 1 -M $setMCS
		sleep 0.05
	fi
	
	# Change FEC
	if [ $prevFecK -ne $setFecK ] || [ $prevFecN -ne $setFecN ]; then
		wfb_tx_cmd 8000 set_fec -k $setFecK -n $setFecN
		sleep 0.05
	fi	
	# Increase bit-rate
	if [ $prevBitrate -ne $setBitrate ]; then
		curl -s "http://localhost/api/v1/set?video0.bitrate=$setBitrate"
		#echo IDR 0 | nc localhost 4000

	fi
	
	# Change ROIqp
	if [[ "$prevROIqp" != "$ROIqp" ]]; then
		sleep 0.05
		curl localhost/api/v1/set?fpv.qp=$ROIqp
	fi
	
elif [ $newProfile -lt $oldProfile ]; then
###############################################################################	
	# Decrease bit-rate first
	if [ $prevBitrate -ne $setBitrate ]; then
		curl -s "http://localhost/api/v1/set?video0.bitrate=$setBitrate"
		#echo IDR 0 | nc localhost 4000

	fi
	
# Set gopSize
	if [[ "$prevGop" != "$setGop" ]]; then
		sleep 0.05
		curl localhost/api/v1/set?video0.gopSize=$setGop 
	fi
	
	# Lower MCS
	if [ $prevMCS -ne $setMCS ]; then
		sleep 0.05
		wfb_tx_cmd 8000 set_radio -B 20 -G $setGI -S 1 -L 1 -M $setMCS
	fi

	#change FEC
	if [ $prevFecK -ne $setFecK ] || [ $prevFecN -ne $setFecN ]; then
		sleep 0.05
		wfb_tx_cmd 8000 set_fec -k $setFecK -n $setFecN
	fi
	
	# Increase power
	if [ $prevSetPower -ne $setPower ]; then
		sleep 0.1
		iw dev wlan0 set txpower fixed $setPower
	fi
	
	# Change ROIqp
	if [[ "$prevROIqp" != "$ROIqp" ]]; then
		sleep 0.05
		curl localhost/api/v1/set?fpv.qp=$ROIqp
	fi
fi
#############################################################################

# Display stats on msposd
echo "$secondsSinceLastChange s Mode:$setBitrate M:$setMCS $setGI F:$setFecK/$setFecN P:$wfbPower G:$setGop&L31&F28 CPU:&C &Tc" >/tmp/MSPOSD.msg

#Update all profile variables in file
echo -e "vidRadioProfile=$newProfile\nprevGI=$setGI\nprevMCS=$setMCS\nprevFecK=$setFecK\nprevFecN=$setFecN\nprevBitrate=$setBitrate\nprevGop=$setGop\nprevSetPower=$setPower\nprevROIqp=$ROIqp\nprevTimeStamp=$newTimeStamp" >/etc/txprofile

exit 1
