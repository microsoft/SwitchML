# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

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
        self.table    = self.bfrt_info.table_get("pipe.Ingress.exponent_max.exponent_max")
        self.register = self.bfrt_info.table_get("pipe.Ingress.exponent_max.exponents")

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
        self.register.entry_del(target)
        
        
    def add_default_entries(self):
        # all this is handled in the p4 code now
        pass
    
