######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import os
import sys
import random

from pprint import pprint

from scapy.all import *

class SwitchML(Packet):
    name = "SwitchML"
    fields_desc=[
        IntField(         "tsi", 0),
        ShortField("pool_index", 2),
    ]

class SwitchMLExponent(Packet):
    name = "SwitchMLExponent"
    fields_desc=[
        ShortField("e0", random.randint(0, 255))
    ]

class SwitchMLData(Packet):
    name = "SwitchMLData"
    fields_desc=[
        IntField("d0", 0),
        IntField("d1", 1),
        IntField("d2", 2),
        IntField("d3", 3),
        IntField("d4", 4),
        IntField("d5", 5),
        IntField("d6", 6),
        IntField("d7", 7),
        IntField("d8", 8),
        IntField("d9", 9),
        IntField("d10", 10),
        IntField("d11", 11),
        IntField("d12", 12),
        IntField("d13", 13),
        IntField("d14", 14),
        IntField("d15", 15),
        IntField("d16", 16),
        IntField("d17", 17),
        IntField("d18", 18),
        IntField("d19", 19),
        IntField("d20", 20),
        IntField("d21", 21),
        IntField("d22", 22),
        IntField("d23", 23),
        IntField("d24", 24),
        IntField("d25", 25),
        IntField("d26", 26),
        IntField("d27", 27),
        IntField("d28", 28),
        IntField("d29", 29),
        IntField("d30", 30),
        IntField("d31", 31),
    ]


def make_switchml_udp(src_mac, src_ip, dst_mac, dst_ip, src_port, dst_port, pool_index,
                      value_multiplier=1, checksum=None):
    p = (Ether(dst=dst_mac, src=src_mac) /
         IP(dst=dst_ip, src=src_ip)/
         UDP(sport=src_port, dport=dst_port)/
         SwitchML(pool_index=pool_index) /
         SwitchMLExponent() /
         SwitchMLData() /
         SwitchMLData())

    # initialize data
    for i in range(32):
        setattr(p.getlayer('SwitchMLData', 1), 'd{}'.format(i), value_multiplier * i)
        setattr(p.getlayer('SwitchMLData', 2), 'd{}'.format(i), value_multiplier * (i+32))

    if checksum is not None:
        p['UDP'].chksum = checksum
        
    return p

if __name__ == '__main__':
    p = make_switchml_udp(src_mac="b8:83:03:73:a6:a0", src_ip="198.19.200.49", dst_mac="06:00:00:00:00:01", dst_ip="198.19.200.200", src_port=1234, dst_port=0xbee0, pool_index=0)
    pprint(p)
    
