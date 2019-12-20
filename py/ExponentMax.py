######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from Table import Table


class ExponentMax(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(ExponentMax, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('ExponentMax')
        self.logger.info("Setting up exponent_max table...")
        
        # get this table
        self.table    = self.bfrt_info.table_get("pipe.SwitchMLIngress.exponent_max.exponent_max")
        self.register = self.bfrt_info.table_get("pipe.SwitchMLIngress.exponent_max.exponents")

        # clear and add defaults
        self.clear() # Don't clear table; it's programmed in the P4 code
        self.add_default_entries()

    def clear(self):
        # override base class method so we don't clear entries set by p4 code
        # just clear registers
        self.clear_registers()

    def clear_registers(self):
        self.logger.info("Clearing exponent registers...")

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # clear all register entries
        for i in range(self.register.info.size_get()):
            self.register.entry_add(
                target,
                [self.register.make_key([gc.KeyTuple('$REGISTER_INDEX', i)])],
                [self.register.make_data(
                    [gc.DataTuple('SwitchMLIngress.exponent_max.exponents.first', 0),
                     gc.DataTuple('SwitchMLIngress.exponent_max.exponents.second', 0)])])

        # sync?
        self.register.operations_execute(target, 'Sync')

        
    def add_default_entries(self):
        # all this is handled in the p4 code now
        pass
    
        # # target all pipes on device 0
        # target = gc.Target(device_id=0, pipe_id=0xffff)

        # # if bitmap_before is all 0's and type is CONSUME, this is the first packet for slot, so just write values and read first value
        # self.table.entry_add(
        #     target,
        #     [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 4),
        #                           # Check if bitmap_before is all zeros
        #                           gc.KeyTuple('ig_md.worker_bitmap_before',
        #                                       0x00000000,
        #                                       0xffffffff),
                                  
        #                           # Don't match on map_result bits; just use bitmap_before
        #                           gc.KeyTuple('ig_md.map_result',
        #                                       0x00000000,
        #                                       0x00000000),
                                  
        #                           # only match on packet_type_t.CONSUME
        #                           gc.KeyTuple('hdr.switchml_md.packet_type',
        #                                       0x1,
        #                                       0x3)])],
        #     [self.table.make_data([],
        #                           'SwitchMLIngress.exponent_max.exponent_write_read0_action')])

        # # if bitmap_before is nonzero, map_result is all 0's,  and type is CONSUME, compute max of values and read first value
        # self.table.entry_add(
        #     target,
        #     [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 3),
        #                           # Don't match on map_result bits; depend on previous rule missing to check if bit is set
        #                           gc.KeyTuple('ig_md.worker_bitmap_before',
        #                                       0x00000000,
        #                                       0x00000000),
                                  
        #                           # ensure map_result is all 0's
        #                           gc.KeyTuple('ig_md.map_result',
        #                                       0x00000000,
        #                                       0xffffffff),
                                  
        #                           # only match on packet_type_t.CONSUME
        #                           gc.KeyTuple('hdr.switchml_md.packet_type',
        #                                       0x1,
        #                                       0x3)])],
        #     [self.table.make_data([],
        #                           'SwitchMLIngress.exponent_max.exponent_max_read0_action')])

        # # if bitmap_before is nonzero, map_result is nonzero, and type is CONSUME, this is a retransmission, so just read first value
        # self.table.entry_add(
        #     target,
        #     [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 2),
        #                           # Don't match on map_result bits; depend on previous rules to check if bit is set
        #                           gc.KeyTuple('ig_md.worker_bitmap_before',
        #                                       0x00000000,
        #                                       0x00000000),
                                  
        #                           # Don't match on map_result bits; depend on previous rules to check if bit is set
        #                           gc.KeyTuple('ig_md.map_result',
        #                                       0x00000000,
        #                                       0x00000000),
                                  
        #                           # only match on packet_type_t.CONSUME
        #                           gc.KeyTuple('hdr.switchml_md.packet_type',
        #                                       0x1,
        #                                       0x3)])],
        #     [self.table.make_data([],
        #                           'SwitchMLIngress.exponent_max.exponent_read0_action')])

        # # if type is HARVEST, read second value
        # self.table.entry_add(
        #     target,
        #     [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 1),
        #                           # Don't match on worker_bitmap_before bits
        #                           gc.KeyTuple('ig_md.worker_bitmap_before',
        #                                       0x00000000,
        #                                       0x00000000),
                                  
        #                           # Don't match on map_result bits
        #                           gc.KeyTuple('ig_md.map_result',
        #                                       0x00000000,
        #                                       0x00000000),
                                  
        #                           # only match on packet_type_t.HARVEST
        #                           gc.KeyTuple('hdr.switchml_md.packet_type',
        #                                       0x2,
        #                                       0x3)])],
        #     [self.table.make_data([],
        #                           'SwitchMLIngress.exponent_max.exponent_read1_action')])



