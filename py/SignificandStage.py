# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from timeit import default_timer as timer

from Table import Table


class SignificandStage(Table):

    def __init__(self, client, bfrt_info, aa, bb, cc, dd):
        # set up base class
        super(SignificandStage, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('SignificandStage')
        self.logger.info("Setting up significand sum stage for indices {}, {}, {}, and {}...".format(aa, bb, cc, dd))

        # store control name for future register accesses
        self.control_name = "Ingress.significands_{:02d}_{:02d}_{:02d}_{:02d}".format(aa, bb, cc, dd)

        # get registers
        self.registers = []
        # for each register in stage
        for index in [0, 1, 2, 3]:
            # clear all entries in this register
            register_name = self.control_name + ".sum{}.significands".format(index)
            register = self.bfrt_info.table_get(register_name)
            self.registers.append(register)
        
        # no table entries to clear or set defaults for
        ###self.clear() # Don't clear table; it's programmed in the P4 code, and self.table is not set.
        self.add_default_entries()
        
        # clear registers
        self.clear()
        
    def clear(self):
        # override base class method so we don't clear entries set by p4 code
        # just clear registers
        self.clear_registers()

    def clear_registers(self):
        self.logger.info("Clearing significand registers...")

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # for each register in stage
        start = timer()
        for register in self.registers:
            register.entry_del(target)
        end = timer()
        self.logger.info("Cleared four registers in {} seconds per register...".format((end-start)/4))
        
        
    def add_default_entries(self):
        # all this is handled in the p4 code
        pass
