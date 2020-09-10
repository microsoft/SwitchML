#!/bin/bash
## Copyright (c) Microsoft Corporation.
## Licensed under the MIT License.

# # cx4
# DEV=mlx5_1
# REGS="0x5363c.12:1 0x5367c.12:1 0x53634.29:1 0x53674.29:1"

#cx5
DEV=mlx5_0
REGS="0x5361c.12:1 0x5363c.12:1 0x53614.29:1 0x53634.29:1"
echo "WARNING: this script assumes you're using a ConnectX-5 NIC. If you're using something different, restore the register values and modify the script."

echo ibv_devinfo -d $DEV
ibv_devinfo -d $DEV

echo Before:
for i in $REGS
do
    CMD="sudo mstmcra $DEV $i"
    printf "$CMD => "
    $CMD
done    

echo Modifying:
for i in $REGS
do
    CMD="sudo mstmcra $DEV $i 0x0"
    echo "$CMD"
    $CMD
done    

echo After:
for i in $REGS
do
    CMD="sudo mstmcra $DEV $i"
    printf "$CMD => "
    $CMD
done    
