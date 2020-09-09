#!/bin/bash

# which device do we want counters for?
if [ $# -lt 1 ]
then
    echo "Usage: $0 <device name> <command>"
    exit 1
else
    if [[ $1 == mlx* ]]
    then
        DEVICE="$1"
        shift
    else
        DEVICE=mlx5_0
    fi
fi

# get ethernet device for Mellanox device
ETHDEVICE="$(ibdev2netdev | grep mlx5_0 | awk '{print $5}')"


# capture RoCE counters into associative array
declare -A counters
for i in /sys/class/infiniband/$DEVICE/ports/1/*counters/*
do
    counter_name=${i##*/}
    counters[$counter_name]=$(cat $i)
done

declare -A ethtool
for str in $(ethtool -S $ETHDEVICE | tail -n+2 | awk '{print $1 $2}')
do
    name=${str%:*}
    value=${str##*:}
    ethtool[$name]=$value
done
             
# run command
$@

echo "Changed RDMA counters for device $DEVICE:"

# compare captured counters with those after running
for i in /sys/class/infiniband/$DEVICE/ports/1/*counters/*
do
    counter_name=${i##*/}
    new_value=$(cat $i)
    difference=$(( $new_value - ${counters[$counter_name]} ))
    if [ $difference -ne 0 ]
    then
        printf "%35s: %d\n" "$counter_name" $difference
    fi
done

echo "-----"
echo "Changed ethtool counters for device $ETHDEVICE:"

for str in $(ethtool -S $ETHDEVICE | tail -n+2 | awk '{print $1 $2}')
do
    name=${str%:*}
    new_value=${str##*:}
    difference=$(( $new_value - ethtool[$name] ))
    if [ $difference -ne 0 ]
    then
        printf "%35s: %d\n" "$name" $difference
    fi
done
