######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc


from Table import Table
from Worker import Worker, WorkerType
from Packets import roce_opcode_s2n

class RoCEReceiver(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(RoCEReceiver, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('RoCEReceiver')
        self.logger.info("Setting up receive_roce table...")
        

        # get this table
        self.table = self.bfrt_info.table_get("pipe.SwitchMLIngress.roce_receiver.receive_roce")

        # set format annotations
        self.table.info.key_field_annotation_add("hdr.ipv4.dst_addr", "ipv4")
        self.table.info.key_field_annotation_add("hdr.ipv4.src_addr", "ipv4")

        # clear and add defaults
        self.clear()

        # only const defaults
        #self.add_default_entries()

        
    # Add SwitchML RoCE v2 entry to table
    def add_entry(self, switch_mac, switch_ip, switch_udp_port, switch_udp_mask,
                  worker, worker_bitmap, num_workers,
                  switch_mgid):
        self.logger.info("Adding RoCE worker {}".format(worker.ip))

        # doesn't matter
        match_priority = 10
        
        # add entry for each opcode for each worker
        for opcode, action in [
                (roce_opcode_s2n['UC_SEND_FIRST'],  'SwitchMLIngress.roce_receiver.first_packet'),
                (roce_opcode_s2n['UC_SEND_MIDDLE'], 'SwitchMLIngress.roce_receiver.middle_packet'),
                (roce_opcode_s2n['UC_SEND_LAST'],   'SwitchMLIngress.roce_receiver.last_packet'),
                (roce_opcode_s2n['UC_SEND_ONLY'],   'SwitchMLIngress.roce_receiver.only_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_FIRST'],  'SwitchMLIngress.roce_receiver.first_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_MIDDLE'], 'SwitchMLIngress.roce_receiver.middle_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_LAST'],   'SwitchMLIngress.roce_receiver.last_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_ONLY'],   'SwitchMLIngress.roce_receiver.only_packet')]:
            self.table.entry_add(
                self.target,
                [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', match_priority),
                                      # match on Ethernet addrs, IPs and port
                                      gc.KeyTuple('hdr.ipv4.src_addr',
                                                  worker.ip),
                                      gc.KeyTuple('hdr.ipv4.dst_addr',
                                                  switch_ip),
                                      gc.KeyTuple('hdr.ib_bth.partition_key',
                                                  worker.roce_partition_key),
                                      gc.KeyTuple('hdr.ib_bth.opcode',
                                                  opcode)])],
                [self.table.make_data([gc.DataTuple('mgid', switch_mgid),
                                       gc.DataTuple('worker_type', worker.worker_type.value),
                                       gc.DataTuple('worker_id', worker.rid),
                                       gc.DataTuple('num_workers', num_workers),
                                       gc.DataTuple('worker_bitmap', worker_bitmap)],
                                      action)])

