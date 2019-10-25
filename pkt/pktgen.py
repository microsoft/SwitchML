#!/usr/bin/python
######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import os
import sys

if os.getuid() !=0:
    print """
ERROR: This script requires root privileges. 
       Use 'sudo' to run it.
"""
    quit()

from scapy.all import *


class SwitchML(Packet):
    name = "SwitchML"
    fields_desc=[
        IntField(         "tsi", 0),
        ShortField("pool_index", 0),
    ]

class SwitchMLExponent(Packet):
    name = "SwitchMLExponent"
    fields_desc=[
        ShortField("e0", 0),
    ]

class SwitchMLData(Packet):
    name = "SwitchMLData"
    fields_desc=[
        IntField("d0", 0),
        IntField("d1", 0),
        IntField("d2", 0),
        IntField("d3", 0),
        IntField("d4", 0),
        IntField("d5", 0),
        IntField("d6", 0),
        IntField("d7", 0),
        IntField("d8", 0),
        IntField("d9", 0),
        IntField("d10", 0),
        IntField("d11", 0),
        IntField("d12", 0),
        IntField("d13", 0),
        IntField("d14", 0),
        IntField("d15", 0),
        IntField("d16", 0),
        IntField("d17", 0),
        IntField("d18", 0),
        IntField("d19", 0),
        IntField("d20", 0),
        IntField("d21", 0),
        IntField("d22", 0),
        IntField("d23", 0),
        IntField("d24", 0),
        IntField("d25", 0),
        IntField("d26", 0),
        IntField("d27", 0),
        IntField("d28", 0),
        IntField("d29", 0),
        IntField("d30", 0),
        IntField("d31", 0),
    ]


def send_udp(src_mac, src_ip):
    p = (Ether(dst="06:00:00:00:00:01", src=src_mac) /
         IP(dst="198.19.200.200", src=src_ip)/
         UDP(dport=0xBEE0)/
         SwitchML() /
         SwitchMLExponent() /
         SwitchMLData() /
         SwitchMLData())
         
    sendp(p, iface="veth1", count = 1) 

         
send_udp("b8:83:03:74:01:8c", "198.19.200.50")
#send_udp("b8:83:03:73:a6:a0", "198.19.200.49")
