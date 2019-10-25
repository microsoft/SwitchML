######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from Table import Table


class MantissaStage(Table):

    def __init__(self, client, bfrt_info, aa, bb, cc, dd):
        # set up base class
        super(MantissaStage, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('MantissaStage')
        self.logger.info("Setting up mantissa sum stage for indices {}, {}, {}, and {}...".format(aa, bb, cc, dd))

        # store control name for future register accesses
        self.control_name = "SwitchMLIngress.mantissas_{:02d}_{:02d}_{:02d}_{:02d}".format(aa, bb, cc, dd)

        # no table entries to clear or set defaults for
        self.clear()
        self.add_default_entries()
        
        # clear registers
        self.clear_registers()
        
    def clear_registers(self):
        self.logger.info("Clearing mantissa registers...")

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # for each register in stage
        for index in [0, 1, 2, 3]:
            # clear all entries in this register
            register_name = self.control_name + ".sum{}.mantissas".format(index)
            self.logger.info("Clearing mantissa register {}...".format(register_name))
            register = self.bfrt_info.table_get(register_name)
            for i in range(register.info.size_get()):
                register.entry_add(
                    target,
                    [register.make_key([gc.KeyTuple('$REGISTER_INDEX', i)])],
                    [register.make_data(
                        [gc.DataTuple(register_name + '.first', 0),
                         gc.DataTuple(register_name + '.second', 0)])])

            # sync?
            register.operations_execute(target, 'Sync')

        
    def add_default_entries(self):
        # all this is handled in the p4 code
        pass
