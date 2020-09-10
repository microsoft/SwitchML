# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from Table import Table
from Worker import Worker


class Mirror(Table):

    # mirror constants for Tofino 1
    normal_base = 1
    normal_max = 1015
    coalesced_base = 1016
    coalesced_max = 1023
    
    def __init__(self, client, bfrt_info, mirror_port):
        # set up base class
        super(Mirror, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('Mirror')
        self.logger.info("Setting up mirror sessions...")
        
        # get this table
        self.table = self.bfrt_info.table_get("$mirror.cfg")

        self.mirror_port = mirror_port
        self.sessions = []
        
        # clear and add defaults
        self.clear()
        self.add_default_entries()

        
    def clear(self):
        # not yet supported
        #self.table.entry_del(self.target)

        # delete each session we created
        while len(self.sessions):
            sid = self.sessions.pop(0)
            self.table.entry_del(
                self.target,
                [self.table.make_key([gc.KeyTuple('$sid', sid)])])

        
    def add_default_entries(self):
        sid = self.normal_base
        self.table.entry_add(
            self.target,
            [self.table.make_key([gc.KeyTuple('$sid', sid)])],
            [self.table.make_data([gc.DataTuple('$direction', str_val="INGRESS"),
                              gc.DataTuple('$ucast_egress_port', self.mirror_port),
                              gc.DataTuple('$ucast_egress_port_valid', bool_val=True),
                              gc.DataTuple('$session_enable', bool_val=True)],
                             '$normal')])



