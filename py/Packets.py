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
        FieldListField("significands", [], SignedIntField("", 0), count_from=lambda pkt: 64)
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


#
# RoCE headers
#

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
        X3BytesField("psn", 0),
    ]

    # could do this with bind_layers, but given that we have to use
    # guess_payload_class for the RETH->IMM transition later, we'll
    # just do it all the same way.
    def guess_payload_class(self, payload):
        # is this an RDMA packet? if so, next is IB_RETH
        if 'RDMA' in roce_opcode_n2s[self.opcode]:
            return IB_RETH
        # is this an immediate packet that's not RDMA? if so, next is IB_IMM
        elif 'IMMEDIATE' in roce_opcode_n2s[self.opcode]:
            return IB_IMM
        # otherwise, do the normal thing.
        else:
            return Packet.guess_payload_class(self, payload)

class IB_RETH(Packet):
    name = "IB_RETH"

    fields_desc = [
        XLongField("addr", 0),
        XIntField("rkey", 0),
        XIntField("len", 0),
    ]

    def guess_payload_class(self, payload):
        if 'IMMEDIATE' in roce_opcode_n2s[self.underlayer.opcode]:
            return IB_IMM
        else:
            return Packet.guess_payload_class(self, payload)

class IB_IMM(Packet):
    name = "IB_IMM"
    fields_desc = [
        XIntField("imm", 0)
    ]
    
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

class IB_ICRC(Packet):
    name = "IB_ICRC"
    fields_desc = [
        XIntField("icrc", None)
    ]

class IB_Payload(Packet):
    name = "IB_Payload"
    fields_desc = [
        FieldListField('data', None, SignedIntField('', 0),
                       length_from=lambda pkt: len(pkt.payload) - 4)
    ]

# Connect the RoCE headers to UDP
bind_layers(UDP, IB_BTH, dport=4791)

# Connect all the IB headers to the payload fields
bind_layers(IB_BTH, IB_Payload)
bind_layers(IB_BTH, IB_RETH)
bind_layers(IB_BTH, IB_IMM)
bind_layers(IB_RETH, IB_Payload)
bind_layers(IB_RETH, IB_IMM)
bind_layers(IB_IMM, IB_Payload)
bind_layers(IB_Payload, IB_ICRC)



# bind_layers(IB_BTH, IB_IMM, opcode="UC_SEND_LAST_IMMEDIATE")
# bind_layers(IB_BTH, IB_IMM, opcode="UC_SEND_ONLY_IMMEDIATE")
# bind_layers(IB_BTH, SwitchMLData, opcode="UC_SEND_FIRST")
# bind_layers(IB_BTH, SwitchMLData, opcode="UC_SEND_MIDDLE")
# bind_layers(IB_BTH, SwitchMLData, opcode="UC_SEND_LAST")
# bind_layers(IB_BTH, SwitchMLData, opcode="UC_SEND_ONLY")

# # bind_layers(IB_BTH, SwitchMLData, opcode="UC_RDMA_WRITE_FIRST")
# # bind_layers(IB_BTH, SwitchMLData, opcode="UC_RDMA_WRITE_MIDDLE")
# # bind_layers(IB_BTH, SwitchMLData, opcode="UC_RDMA_WRITE_LAST")
# # bind_layers(IB_BTH, SwitchMLData, opcode="UC_RDMA_WRITE_ONLY")
# # bind_layers(IB_BTH, IB_IMM, opcode="UC_RDMA_WRITE_LAST_IMMEDIATE")
# # bind_layers(IB_BTH, IB_IMM, opcode="UC_RDMA_WRITE_ONLY_IMMEDIATE")

# bind_layers(IB_BTH, IB_RETH, opcode=roce_opcode_s2n["UC_RDMA_WRITE_FIRST"])
# bind_layers(IB_BTH, SwitchMLData64, opcode=roce_opcode_s2n["UC_RDMA_WRITE_MIDDLE"])
# bind_layers(IB_BTH, SwitchMLData64, opcode=roce_opcode_s2n["UC_RDMA_WRITE_LAST"])
# bind_layers(IB_BTH, IB_RETH, opcode=roce_opcode_s2n["UC_RDMA_WRITE_ONLY"])
# bind_layers(IB_BTH, IB_IMM, opcode=roce_opcode_s2n["UC_RDMA_WRITE_LAST_IMMEDIATE"])

# # TODO: need to parse an immediate header here too
# #bind_layers(IB_BTH, (IB_RETH, IB_IMM), opcode=roce_opcode_s2n["UC_RDMA_WRITE_ONLY_IMMEDIATE"])
# bind_layers(IB_BTH, IB_RETH, opcode=roce_opcode_s2n["UC_RDMA_WRITE_ONLY_IMMEDIATE"])

# #bind_layers(IB_RETH, IB_IMM, lambda pkt: pkt.underlayer)
# #bind_layers(IB_RETH, SwitchMLData64)
# #bind_layers(IB_RETH, IB_Payload)

# bind_layers(IB_IMM, SwitchMLData64)
# #bind_layers(IB_IMM, IB_Payload)

# bind_layers(SwitchMLData64, SwitchMLData64)





# SwitchML debug tunnel protocol header
class SwitchMLDebug(Packet):
    name = "SwitchMLDebug"
    fields_desc = [
        XShortField("worker_id", 0),
        XShortField("pool_index", 0),
        XByteField("first_last_flag", 0)
    ]

bind_layers(Ether, SwitchMLDebug, type=0x88b6)
bind_layers(SwitchMLDebug, Ether)





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
    if len(sys.argv) <= 1:
        print("Usage: {} <PCAP fiale>".format(sys.argv[0]))
        sys.exit(1)
    else:
        print("{} reading packets from {}...".format(sys.argv[0], sys.argv[1]))
        
        conf.color_theme = BrightTheme()
        conf.debug_dissector = True
        
        for i, pkt in enumerate(PcapReader(sys.argv[1])):
            print("Packet {}:".format(i))
            pkt.show()

        # sys.exit(0)
        
        # for i, pkt in enumerate(PcapReader('/u/jacob/c50a.pcap')):
        #     #print("Packet {}:".format(i))
        #     #pkt.show()

        #     dst_ip = pkt[IP].dst
        #     src_port = pkt[UDP].sport
        #     opcode = roce_opcode_n2s[pkt[IB_BTH].opcode]
        #     qp     = pkt[IB_BTH].dst_qp
        #     psn    = pkt[IB_BTH].psn
        #     if IB_RETH in pkt:
        #         addr   = pkt[IB_RETH].addr
        #     else:
        #         addr   = 0
            
        #     print("{:>2}: {:>15} {:>5} {:>30} 0x{:x} 0x{:x} 0x{:x}".format(i, dst_ip, src_port, opcode, qp, psn, addr))

