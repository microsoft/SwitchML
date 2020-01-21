######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from Table import Table


class SetDstAddr(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(SetDstAddr, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('SetDstAddr')
        self.logger.info("Setting up set_dst_addr table...")
        
        # get this table
        self.table = self.bfrt_info.table_get("pipe.SwitchMLEgress.set_dst_addr.set_dst_addr")

        # set format annotations
        self.table.info.data_field_annotation_add("ip_dst_addr",  'SwitchMLEgress.set_dst_addr.set_dst_addr_for_SwitchML_UDP', "ipv4")
        self.table.info.data_field_annotation_add("eth_dst_addr", 'SwitchMLEgress.set_dst_addr.set_dst_addr_for_SwitchML_UDP', "mac")
        self.table.info.data_field_annotation_add("eth_dst_addr", 'SwitchMLEgress.set_dst_addr.set_dst_addr_for_Ignore', "mac")

        # clear and add defaults
        self.clear()
        self.add_default_entries()

        
    def add_default_entries(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # nothing to do for this table!
        pass

    # Add SwitchML UDP entry to table
    def add_udp_entry(self, worker_mac, worker_ip, worker_udp_port, worker_rid, worker_dev_port):
        self.logger.info("Adding worker {} {} {} at rid {} port {}".format(worker_mac, worker_ip, worker_udp_port, worker_rid, worker_dev_port))

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', 10),
                                  # match on packet type, egress RID and port
                                  gc.KeyTuple('eg_md.switchml_md.packet_type',
                                              0x3,  # only match on broadcast packets
                                              0x3),
                                  gc.KeyTuple('eg_intr_md.egress_rid',
                                              worker_rid, # 16 bits
                                              0xffff)])],
            [self.table.make_data([gc.DataTuple('eth_dst_addr', worker_mac),
                                   gc.DataTuple('ip_dst_addr', worker_ip),
                                   gc.DataTuple('udp_dst_port', worker_udp_port)],
                                  'SwitchMLEgress.set_dst_addr.set_dst_addr_for_SwitchML_UDP')])

        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', 10),
                                  # match on packet type, egress RID and port
                                  gc.KeyTuple('eg_md.switchml_md.packet_type',
                                              0x0,  # only match on ignored packets
                                              0x3),
                                  gc.KeyTuple('eg_intr_md.egress_rid',
                                              worker_rid, # 16 bits
                                              0xffff)])],
            [self.table.make_data([gc.DataTuple('eth_dst_addr', worker_mac)],
                                  'SwitchMLEgress.set_dst_addr.set_dst_addr_for_Ignore')])

