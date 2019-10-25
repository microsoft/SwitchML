######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc


from Table import Table


class CountWorkers(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(CountWorkers, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('CountWorkers')
        self.logger.info("Setting up count_workers table...")
        
        # get this table
        self.table    = self.bfrt_info.table_get("pipe.SwitchMLIngress.count_workers.count_workers")
        self.register = self.bfrt_info.table_get("pipe.SwitchMLIngress.count_workers.worker_count")

        # clear and add defaults
        self.clear()
        self.clear_registers()
        self.add_default_entries()

    def clear_registers(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # clear all register entries
        for i in range(self.register.info.size_get()):
            self.register.entry_add(
                target,
                [self.register.make_key([gc.KeyTuple('$REGISTER_INDEX', i)])],
                [self.register.make_data(
                    [gc.DataTuple('SwitchMLIngress.count_workers.worker_count.first', 0),
                     gc.DataTuple('SwitchMLIngress.count_workers.worker_count.second', 0)])])

        # sync?
        self.register.operations_execute(target, 'Sync')
        
        
    def add_default_entries(self):
        self.logger.info("Clearing worker count register...")

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # if no bits are set in map_result, this is the first time we've seen this packet, so decrement worker count
        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 2),
                                  # Don't match on map_result bits; depend on previous rule missing to check if bit is set
                                  gc.KeyTuple('ig_md.map_result',
                                              0x00000000,
                                              0xffffffff),
                                  
                                  # only match on packet_type_t.CONSUME
                                  gc.KeyTuple('hdr.switchml_md.packet_type',
                                              0x1,
                                              0x3)])],
            [self.table.make_data([],
                                  'SwitchMLIngress.count_workers.count_workers_action')])

        # if the last rule missed and the packet type is CONSUME, some bit must have been set in the
        # map_result, and this is a retransmission. Just read worker count.
        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 1),
                                  # Don't match on map_result bits; depend on previous rule missing to check if bit is set
                                  gc.KeyTuple('ig_md.map_result',
                                              0x00000000,
                                              0x00000000),
                                  
                                  # only match on packet_type_t.CONSUME
                                  gc.KeyTuple('hdr.switchml_md.packet_type',
                                              0x1,
                                              0x3)])],
            [self.table.make_data([],
                                  'SwitchMLIngress.count_workers.read_count_workers_action')])



