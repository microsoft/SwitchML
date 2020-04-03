######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc


from Table import Table
from Worker import Worker

class ARPandICMP(Table):

    def __init__(self, client, bfrt_info, switch_mac, switch_ip):
        # set up base class
        super(ARPandICMP, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('ARPandICMP')
        self.logger.info("Setting up arp_and_icmp table...")
        
        self.switch_mac = switch_mac
        self.switch_ip = switch_ip
        
        # get this table
        self.table = self.bfrt_info.table_get("pipe.SwitchMLIngress.arp_and_icmp.arp_and_icmp")

        # add annotations
        self.table.info.key_field_annotation_add("hdr.ipv4.dst_addr", "ipv4")
        self.table.info.key_field_annotation_add("hdr.arp_ipv4.dst_proto_addr", "ipv4")
        self.table.info.data_field_annotation_add("switch_mac", 'SwitchMLIngress.arp_and_icmp.send_arp_reply', "mac")
        self.table.info.data_field_annotation_add("switch_ip",  'SwitchMLIngress.arp_and_icmp.send_arp_reply', "ipv4")
        self.table.info.data_field_annotation_add("switch_mac", 'SwitchMLIngress.arp_and_icmp.send_icmp_echo_reply', "mac")
        self.table.info.data_field_annotation_add("switch_ip",  'SwitchMLIngress.arp_and_icmp.send_icmp_echo_reply', "ipv4")

        # clear and add defaults
        self.clear()
        self.add_default_entries()

        
        
    def add_default_entries(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # add entry to reply to arp requests
        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 2),
                                  gc.KeyTuple('hdr.arp_ipv4.$valid', # 1 bit
                                              0x1),
                                  gc.KeyTuple('hdr.icmp.$valid', # 1 bit
                                              0x0),
                                  gc.KeyTuple('hdr.arp.opcode', # 16 bits
                                              0x0001, # arp request
                                              0xffff),
                                  gc.KeyTuple('hdr.arp_ipv4.dst_proto_addr', # arp who-has IP
                                              self.switch_ip,
                                              0xffffffff),
                                  gc.KeyTuple('hdr.icmp.msg_type', # 8 bits
                                              0x00, # ignore for arp requests
                                              0x00),
                                  gc.KeyTuple('hdr.ipv4.dst_addr', # ICMP dest addr
                                              self.switch_ip,
                                              0x00000000)])],
            [self.table.make_data([gc.DataTuple('switch_mac', self.switch_mac),
                                   gc.DataTuple('switch_ip',  self.switch_ip)],
                                  'SwitchMLIngress.arp_and_icmp.send_arp_reply')])

        # add entry to reply to icmp echo requests
        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 1),
                                  gc.KeyTuple('hdr.arp_ipv4.$valid', # 1 bit
                                              0x0),
                                  gc.KeyTuple('hdr.icmp.$valid', # 1 bit
                                              0x1),
                                  gc.KeyTuple('hdr.arp.opcode', # 16 bits
                                              0x0000, # ignore for icmp requests
                                              0x0000),
                                  gc.KeyTuple('hdr.arp_ipv4.dst_proto_addr', # arp who-has IP
                                              self.switch_ip,
                                              0x00000000),
                                  gc.KeyTuple('hdr.icmp.msg_type', # 8 bits
                                              0x08, # icmp echo requet
                                              0xff),
                                  gc.KeyTuple('hdr.ipv4.dst_addr', # ICMP dest addr
                                              self.switch_ip,
                                              0xffffffff)])],
            [self.table.make_data([gc.DataTuple('switch_mac', self.switch_mac),
                                   gc.DataTuple('switch_ip',  self.switch_ip)],
                                  'SwitchMLIngress.arp_and_icmp.send_icmp_echo_reply')])


        
