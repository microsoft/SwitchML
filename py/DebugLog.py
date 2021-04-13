# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from enum import IntEnum
import os
import yaml
import ctypes
from itertools import chain

from Table import Table
from Worker import Worker

class PacketType(IntEnum):
    MIRROR     = 0x0
    BROADCAST  = 0x1
    RETRANSMIT = 0x2
    IGNORE     = 0x3
    CONSUME0   = 0x4
    CONSUME1   = 0x5
    CONSUME2   = 0x6
    CONSUME3   = 0x7
    HARVEST0   = 0x8
    HARVEST1   = 0x9
    HARVEST2   = 0xa
    HARVEST3   = 0xb
    HARVEST4   = 0xc
    HARVEST5   = 0xd
    HARVEST6   = 0xe
    HARVEST7   = 0xf

class DebugLog(Table):

    # mirror constants for Tofino 1
    normal_base = 1
    normal_max = 1015
    coalesced_base = 1016
    coalesced_max = 1023
    
    def __init__(self, client, bfrt_info):
        # set up base class
        super(DebugLog, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('DebugLog')
        self.logger.info("Setting up debug log...")
        
        # get this table
        #self.table = self.bfrt_info.table_get("pipe.Ingress.debug_log.debug_log")
        self.packet_id  = self.bfrt_info.table_get("pipe.Ingress.debug_packet_id.counter")
        self.log        = self.bfrt_info.table_get("pipe.Ingress.debug_log.log")
        self.egress_log = self.bfrt_info.table_get("pipe.Egress.debug_log.log")

        # clear and add defaults
        self.clear()
        self.add_default_entries()

        
    def clear(self):
        #self.table.entry_del(self.target)
        #self.clear_registers()
        pass

    def clear_registers(self):
        #self.log.entry_del(self.target)
        pass
        
    def clear_log(self):
        self.packet_id.operations_execute(self.target, 'Sync')
        self.packet_id.entry_del(self.target) #, flags={'from_hw': True})
        self.packet_id.operations_execute(self.target, 'Sync')
        self.packet_id.entry_del(self.target) #, flags={'from_hw': True})
        self.packet_id.operations_execute(self.target, 'Sync')
        
        # self.packet_id.entry_mod(
        #     self.target,
        #     [self.packet_id.make_key([gc.KeyTuple('$REGISTER_INDEX', 0)])],
        #     [self.packet_id.make_data([gc.DataTuple("Ingress.debug_packet_id.counter.f1", 0)])])
        
        self.log.operations_execute(self.target, 'Sync')
        self.log.entry_del(self.target)
        self.log.operations_execute(self.target, 'Sync')
        self.log.entry_del(self.target)
        self.log.operations_execute(self.target, 'Sync')
        
        self.egress_log.operations_execute(self.target, 'Sync')
        self.egress_log.entry_del(self.target)
        self.egress_log.operations_execute(self.target, 'Sync')
        self.egress_log.entry_del(self.target)
        self.egress_log.operations_execute(self.target, 'Sync')
        
    def add_default_entries(self):
        # no defaults for now
        pass

    def parse_log_entry(self, index, capture_pipe, entry):
        return {
            "index"                   : index,
            "capture_pipe"            : capture_pipe,
            "address_bits"            : 0xff & (entry >> 43),
            "packet_id"               : 0x7ff & (entry >> 32),
            "ingress_pipe"            : 0x3 & (entry >> 30),
            "worker_id"               : 0x1f & (entry >> 25),
            "first_packet_of_message" : 1 == (1 & (entry >> 24)),
            "last_packet_of_message"  : 1 == (1 & (entry >> 23)),
            "nonzero_bitmap_before"   : 1 == (1 & (entry >> 22)),
            "nonzero_map_result"      : 1 == (1 & (entry >> 21)),
            "first_worker_for_slot"   : 1 == (1 & (entry >> 20)),
            "last_worker_for_slot"    : 1 == (1 & (entry >> 19)),
            "packet_type"             : PacketType(0xf & (entry >> 15)),
            "pool_index"              : 0x3fff & (entry >> 1),
            "set"                     : 1 & entry}

    def format_log_entry(self, index = None, capture_pipe = None, entry = None):
        fields = [('Index', '{index:5}'),
                  ('Ingress Pipe', '{ingress_pipe:12}'),
                  ('Capture Pipe', '{capture_pipe:12}'),
                  ('Address Bits', '{address_bits:12}'),
                  ('Packet ID', '{packet_id:8} '),
                  ('Worker ID', '{worker_id:8} '),
                  ('Pool Index', '{pool_index:9} '),
                  ('Set', '{set:2} '),
                  ('Packet Type', '{packet_type:10} '),
                  ('Bitmap Before Nonzero', '        {nonzero_bitmap_before:12} '),
                  ('Map Result Nonzero', '        {nonzero_map_result:9} '),
                  ('First Worker', '{first_worker_for_slot:11} '),
                  ('Last Worker', '{last_worker_for_slot:10} '),
                  ('First Packet of Message', '{first_packet_of_message:22} '),
                  ('Last Packet of Message', '{last_packet_of_message:21} ')]
        if index is None or capture_pipe is None or entry is None:
            header = '|'.join([first for first, second in fields])
            return header
        else:
            entry = self.parse_log_entry(index, capture_pipe, entry)
            fields = '|'.join([second for first, second in fields])
            data = fields.format(**entry)
            return data

    def get_log(self):
        print("Getting packet log entries....")
        
        # get all log entries
        resp = self.log.entry_get(
            self.target,
            flags={"from_hw": True})

        values = {}
        
        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()

            ##pprint((k,v))
            # format looks like this:
            # ({u'$REGISTER_INDEX': {'value': 22521}},
            #  {u'Ingress.debug_log.log.addr': [0, 0, 0, 0],
            #   u'Ingress.debug_log.log.data': [0, 0, 0, 0],
            #   'action_name': None,
            #   'is_default_entry': False})
            index = k['$REGISTER_INDEX']['value']
            addr0, addr1, addr2, addr3 = tuple(v['Ingress.debug_log.log.addr'])
            pipe0, pipe1, pipe2, pipe3 = tuple(v['Ingress.debug_log.log.data'])
            value0 = addr0 << 32 | pipe0
            value1 = addr1 << 32 | pipe1
            value2 = addr2 << 32 | pipe2
            value3 = addr3 << 32 | pipe3
            if value0 != 0 or value1 != 0 or value2 != 0 or value3 != 0:
                values[index] = value0, value1, value2, value3

        # get all log entries
        egress_resp = self.egress_log.entry_get(
            self.target,
            flags={"from_hw": True})

        egress_values = {}
        
        for v, k in egress_resp:
            v = v.to_dict()
            k = k.to_dict()

            ##pprint((k,v))
            # format looks like this:
            # ({u'$REGISTER_INDEX': {'value': 22521}},
            #  {u'Ingress.debug_log.log.addr': [0, 0, 0, 0],
            #   u'Ingress.debug_log.log.data': [0, 0, 0, 0],
            #   'action_name': None,
            #   'is_default_entry': False})
            index = k['$REGISTER_INDEX']['value']
            addr0, addr1, addr2, addr3 = tuple(v['Egress.debug_log.log.addr'])
            pipe0, pipe1, pipe2, pipe3 = tuple(v['Egress.debug_log.log.data'])
            value0 = addr0 << 32 | pipe0
            value1 = addr1 << 32 | pipe1
            value2 = addr2 << 32 | pipe2
            value3 = addr3 << 32 | pipe3
            if value0 != 0 or value1 != 0 or value2 != 0 or value3 != 0:
                egress_values[index] = value0, value1, value2, value3
                
        return {"Ingress": values, "Egress": egress_values}
    
    def save_log(self, filename='log.yaml'):
        print("Saving packet log to {}".format(filename))
        values = self.get_log()
        print(len(values['Ingress']) + len(values['Egress']))
        with open(filename, 'w') as f:
            yaml.dump(values, f)
        
    def print_log(self, start=0, end=0):
        values = self.get_log()
        
        #print("Index     Pipe 0     Pipe 2     Pipe 2     Pipe 3")
        #print("-------------------------------------------------")
        #print("{:5} {:10} {:10} {:10} {:10}".format(i, p0, p1, p2, p3))
        
        # print("Index | {} | {} | {} | {}".format(self.print_log_entry(),
        #                                          self.print_log_entry(),
        #                                          self.print_log_entry(),
        #                                          self.print_log_entry()))
        print(self.format_log_entry())

        print("Ingress:")        
        for i, (p0, p1, p2, p3) in values['Ingress'].items():
            if p0 != 0:
                print(self.format_log_entry(i, 0, p0))
            if p1 != 0:
                print(self.format_log_entry(i, 1, p1))
            if p2 != 0:
                print(self.format_log_entry(i, 2, p2))
            if p3 != 0:
                print(self.format_log_entry(i, 3, p3))

        print("Egress:")
        for i, (p0, p1, p2, p3) in values['Egress'].items():
            if p0 != 0:
                print(self.format_log_entry(i, 0, p0))
            if p1 != 0:
                print(self.format_log_entry(i, 1, p1))
            if p2 != 0:
                print(self.format_log_entry(i, 2, p2))
            if p3 != 0:
                print(self.format_log_entry(i, 3, p3))
                
            # if p0 != 0 or p1 != 0 or p2 != 0 or p3 != 0:
            #     print("{:5} | {} | {} | {} | {}".format(i,
            #                                             self.print_log_entry(0, p0),
            #                                             self.print_log_entry(1, p1),
            #                                             self.print_log_entry(2, p2),
            #                                             self.print_log_entry(3, p3)))
                
