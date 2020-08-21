#!/bin/bash


#DEV="$1"
#REGS="0x5363c.12:1 0x5367c.12:1 0x53634.29:1 0x53674.29:1"

# # cx4
# DEV=mlx5_1
# REGS="0x5363c.12:1 0x5367c.12:1 0x53634.29:1 0x53674.29:1"

#cx5
DEV=mlx5_0
REGS="0x5361c.12:1 0x5363c.12:1 0x53614.29:1 0x53634.29:1"

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
    
# printf "sudo mcra $DEV 0x5361c.12:1 => "
# sudo mcra $DEV 0x5361c.12:1
# printf "sudo mcra $DEV 0x5363c.12:1 => "
# sudo mcra $DEV 0x5363c.12:1
# printf "sudo mcra $DEV 0x53614.29:1 => "
# sudo mcra $DEV 0x53614.29:1
# printf "sudo mcra $DEV 0x53634.29:1 => "
# sudo mcra $DEV 0x53634.29:1

# echo Setting registers to 0...
# printf "sudo mcra $DEV 0x5361c.12:1 0x0\n"
# sudo mcra $DEV 0x5361c.12:1 0x0
# printf "sudo mcra $DEV 0x5363c.12:1 0x0\n"
# sudo mcra $DEV 0x5363c.12:1 0x0
# printf "sudo mcra $DEV 0x53614.29:1 0x0\n"
# sudo mcra $DEV 0x53614.29:1 0x0
# printf "sudo mcra $DEV 0x53634.29:1 0x0\n"
# sudo mcra $DEV 0x53634.29:1 0x0

# echo After:
# printf "sudo mcra $DEV 0x5361c.12:1 => "
# sudo mcra $DEV 0x5361c.12:1
# printf "sudo mcra $DEV 0x5363c.12:1 => "
# sudo mcra $DEV 0x5363c.12:1
# printf "sudo mcra $DEV 0x53614.29:1 => "
# sudo mcra $DEV 0x53614.29:1
# printf "sudo mcra $DEV 0x53634.29:1 => "
# sudo mcra $DEV 0x53634.29:1
