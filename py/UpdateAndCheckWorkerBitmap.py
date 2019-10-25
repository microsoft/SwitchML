######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc


from Table import Table


class UpdateAndCheckWorkerBitmap(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(UpdateAndCheckWorkerBitmap, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('UpdateAndCheckWorkerBitmap')
        self.logger.info("Setting up update_and_check_worker_bitmap table...")
        
        # get this table
        self.table    = self.bfrt_info.table_get("pipe.SwitchMLIngress.update_and_check_worker_bitmap.update_and_check_worker_bitmap")
        self.register = self.bfrt_info.table_get("pipe.SwitchMLIngress.update_and_check_worker_bitmap.worker_bitmap")

        # clear and add defaults
        self.clear()
        self.clear_registers()
        self.add_default_entries()

    def clear_registers(self):
        self.logger.info("Clearing bitmap registers...")

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # clear all register entries
        for i in range(self.register.info.size_get()):
            self.register.entry_add(
                target,
                [self.register.make_key([gc.KeyTuple('$REGISTER_INDEX', i)])],
                [self.register.make_data(
                    [gc.DataTuple('SwitchMLIngress.update_and_check_worker_bitmap.worker_bitmap.first', 0),
                     gc.DataTuple('SwitchMLIngress.update_and_check_worker_bitmap.worker_bitmap.second', 0)])])

        # sync?
        self.register.operations_execute(target, 'Sync')
        
        
    def add_default_entries(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # update worker bitmap in correct set by adding rule for each set
        for i in [0, 1]:
            self.table.entry_add(
                target,
                [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 10),
                                      # rule for set i
                                      gc.KeyTuple('ig_md.pool_set',
                                                  i,
                                                  0x1),

                                      # only match on packet_type_t.CONSUME
                                      gc.KeyTuple('hdr.switchml_md.packet_type',
                                                  0x1,
                                                  0x3), 

                                      # # drop if random number is lower than drop probability
                                      # gc.KeyTuple('hdr.switchml_md.drop_random_value',
                                      #             low=1,
                                      #             0x000000)

                                      # verify that we're still within our allowed pool space by
                                      # matching only if sign bit is clear
                                      gc.KeyTuple('ig_md.pool_remaining',
                                                  0x0000,
                                                  0x8000)])],
            [self.table.make_data([],
                                  'SwitchMLIngress.update_and_check_worker_bitmap.update_worker_bitmap_set{}_action'.format(i))])

        # drop if packet's index extends beyond what's allowed
        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 1),
                                  # rule for set i
                                  gc.KeyTuple('ig_md.pool_set',
                                              0,
                                              0x0 ),
                                  
                                  # only match on packet_type_t.CONSUME
                                  gc.KeyTuple('hdr.switchml_md.packet_type',
                                              0x1,
                                              0x3), 
                                  
                                  # # drop if random number is lower than drop probability
                                  # gc.KeyTuple('hdr.switchml_md.drop_random_value',
                                  #             low=1,
                                  #             0x000000)
                                  
                                  # verify that we're still within our allowed pool space by
                                  # matching only if sign bit is clear
                                  gc.KeyTuple('ig_md.pool_remaining',
                                              0x8000,
                                              0x8000)])],
            [self.table.make_data([],
                                  'SwitchMLIngress.update_and_check_worker_bitmap.drop')])



