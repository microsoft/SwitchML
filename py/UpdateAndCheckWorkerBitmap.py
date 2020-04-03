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
        self.clear() # don't clear entries from p4 code; just clear registers
        self.add_default_entries()

    def clear(self):
        # override base class method so we don't clear entries set by p4 code
        # just clear registers
        self.clear_registers()

    def clear_registers(self):
        self.logger.info("Clearing bitmap registers...")

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # clear all register entries
        self.register.entry_del(target)
        
        
    def add_default_entries(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # all these are set in the p4 code now
        pass
    



