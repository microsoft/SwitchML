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
        self.add_default_entries()

    def clear(self):
        # override base class method so we don't clear entries set by p4 code
        # just clear registers
        self.clear_registers()

    def clear_registers(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # clear all register entries
        self.register.entry_del(target)
        
        
    def add_default_entries(self):
        self.logger.info("Clearing worker count register...")

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # all handled in the p4 code
        pass



