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
        XBitField(     "msgType", 0, 4),
        XBitField(      "unused", 0, 12),
        XIntField(         "tsi", 0),
        XShortField("pool_index", 2),
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

class SwitchMLData64(Packet):
    name = "SwitchMLData64"
    fields_desc=[
        FieldListField("significands", [], IntField("", 0), count_from=lambda pkt: 64)
    ]
    

def make_switchml_udp(src_mac, src_ip, dst_mac, dst_ip, src_port, dst_port, pool_index,
                      value_multiplier=1, checksum=None):
    p = (Ether(dst=dst_mac, src=src_mac) /
         IP(dst=dst_ip, src=src_ip)/
         UDP(sport=src_port, dport=dst_port)/
         SwitchML(pool_index=pool_index) /
         SwitchMLData() /
         SwitchMLData() /
         SwitchMLExponent())  # TODO: move exponents before data once daiet code supports it

    # initialize data
    for i in range(32):
        setattr(p.getlayer('SwitchMLData', 1), 'd{}'.format(i), value_multiplier * i)
        setattr(p.getlayer('SwitchMLData', 2), 'd{}'.format(i), value_multiplier * (i+32))

    if checksum is not None:
        p['UDP'].chksum = checksum
        
    return p


class IB_GRH(Packet):
    name = "IB_GRH"
    fields_desc = [
        XBitField("ipver", 6, 4),
        XBitField("tclass", 2, 8),
        XBitField("flowlabel", 0, 20),
        XShortField("paylen", 0),
        XByteField("nxthdr", 27),
        XByteField("hoplmt", 64),
        IP6Field("sgid", "::1"),
        IP6Field("dgid", "::1")
        ]


roce_opcode_n2s = {0b00100000: "UC_SEND_FIRST",
                   0b00100001: "UC_SEND_MIDDLE",
                   0b00100010: "UC_SEND_LAST",
                   0b00100011: "UC_SEND_LAST_IMMEDIATE",
                   0b00100100: "UC_SEND_ONLY",
                   0b00100101: "UC_SEND_ONLY_IMMEDIATE",
                   0b00100110: "UC_RDMA_WRITE_FIRST",
                   0b00100111: "UC_RDMA_WRITE_MIDDLE",
                   0b00101000: "UC_RDMA_WRITE_LAST",
                   0b00101001: "UC_RDMA_WRITE_LAST_IMMEDIATE",
                   0b00101010: "UC_RDMA_WRITE_ONLY",
                   0b00101011: "UC_RDMA_WRITE_ONLY_IMMEDIATE"}

roce_opcode_s2n = {"UC_SEND_FIRST": 0b00100000,
                   "UC_SEND_MIDDLE": 0b00100001,
                   "UC_SEND_LAST": 0b00100010,
                   "UC_SEND_LAST_IMMEDIATE": 0b00100011,
                   "UC_SEND_ONLY": 0b00100100,
                   "UC_SEND_ONLY_IMMEDIATE": 0b00100101,
                   "UC_RDMA_WRITE_FIRST": 0b00100110,
                   "UC_RDMA_WRITE_MIDDLE": 0b00100111,
                   "UC_RDMA_WRITE_LAST": 0b00101000,
                   "UC_RDMA_WRITE_LAST_IMMEDIATE": 0b00101001,
                   "UC_RDMA_WRITE_ONLY": 0b00101010,
                   "UC_RDMA_WRITE_ONLY_IMMEDIATE": 0b00101011}
                   
class IB_BTH(Packet):
    name = "IB_BTH"
    fields_desc = [
        ByteEnumField("opcode", 0b0,
                      {0b00100000: "UC_SEND_FIRST",
                       0b00100001: "UC_SEND_MIDDLE",
                       0b00100010: "UC_SEND_LAST",
                       0b00100011: "UC_SEND_LAST_IMMEDIATE",
                       0b00100100: "UC_SEND_ONLY",
                       0b00100101: "UC_SEND_ONLY_IMMEDIATE",
                       0b00100110: "UC_RDMA_WRITE_FIRST",
                       0b00100111: "UC_RDMA_WRITE_MIDDLE",
                       0b00101000: "UC_RDMA_WRITE_LAST",
                       0b00101001: "UC_RDMA_WRITE_LAST_IMMEDIATE",
                       0b00101010: "UC_RDMA_WRITE_ONLY",
                       0b00101011: "UC_RDMA_WRITE_ONLY_IMMEDIATE",
        }),
        XBitField("se", 0, 1),
        XBitField("migration_req", 1, 1), # ???
        XBitField("pad_count", 0, 2),
        XBitField("transport_version", 0, 4),
        XShortField("partition_key", 0xffff),
        XBitField("f_res1", 0, 1),
        XBitField("b_res1", 0, 1),
        XBitField("reserved", 0, 6),
        X3BytesField("dst_qp", 0),
        XBitField("ack_req", 0, 1),
        XBitField("reserved2", 0, 7),
        X3BytesField("psn", 0)
        ]

class IB_IMM(Packet):
    name = "IB_Immediate"
    fields_desc = [
        XIntField("imm", 0)
    ]
    
bind_layers(UDP, IB_BTH, dport=4791)
bind_layers(IB_BTH, IB_IMM, opcode="UC_SEND_LAST_IMMEDIATE")
bind_layers(IB_BTH, IB_IMM, opcode="UC_SEND_ONLY_IMMEDIATE")
bind_layers(IB_BTH, IB_IMM, opcode="UC_RDMA_WRITE_LAST_IMMEDIATE")
bind_layers(IB_BTH, IB_IMM, opcode="UC_RDMA_WRITE_ONLY_IMMEDIATE")
bind_layers(IB_BTH, SwitchMLData, opcode="UC_SEND_FIRST")
bind_layers(IB_BTH, SwitchMLData, opcode="UC_SEND_MIDDLE")
bind_layers(IB_BTH, SwitchMLData, opcode="UC_SEND_LAST")
bind_layers(IB_BTH, SwitchMLData, opcode="UC_SEND_ONLY")
bind_layers(IB_BTH, SwitchMLData, opcode="UC_RDMA_WRITE_FIRST")
bind_layers(IB_BTH, SwitchMLData, opcode="UC_RDMA_WRITE_MIDDLE")
bind_layers(IB_BTH, SwitchMLData, opcode="UC_RDMA_WRITE_LAST")
bind_layers(IB_BTH, SwitchMLData, opcode="UC_RDMA_WRITE_ONLY")

class IB_ICRC(Packet):
    name = "IB_ICRC"
    fields_desc = [
        XIntField("icrc", None)
    ]


def make_switchml_rdma(src_mac, src_ip, dst_mac, dst_ip, src_port, dst_qp, opcode="UC_SEND_ONLY", psn=0, icrc=None, value_multiplier=1):
    p = (Ether(dst=dst_mac, src=src_mac) /
         IP(dst=dst_ip, src=src_ip, tos=2, flags="DF") /
         UDP(dport=4791, sport=src_port, chksum=0) /
         IB_BTH(opcode=opcode, dst_qp=dst_qp, psn=psn) /
         SwitchMLData() /
         SwitchMLData() /
         IB_ICRC(icrc=icrc))
    
    # initialize data
    for i in range(32):
        setattr(p.getlayer('SwitchMLData', 1), 'd{}'.format(i), value_multiplier * i)
        setattr(p.getlayer('SwitchMLData', 2), 'd{}'.format(i), value_multiplier * (i+32))

    if icrc is not None:
        p['IB_ICRC'].icrc = icrc
        
    return p

if __name__ == '__main__':
    p = make_switchml_udp(src_mac="b8:83:03:73:a6:a0", src_ip="198.19.200.49", dst_mac="06:00:00:00:00:01", dst_ip="198.19.200.200", src_port=1234, dst_port=0xbee0, pool_index=0)
    pprint(p)
    
