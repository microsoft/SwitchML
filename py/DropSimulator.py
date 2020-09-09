######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc


from Table import Table


class DropSimulator(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(DropSimulator, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('DropSimulator')
        self.logger.info("Setting up drop simulators...")
        
        # get this table
        self.table    = self.bfrt_info.table_get("pipe.Egress.drop_sim.probability_store")

        # clear and add defaults
        self.clear()
        #self.add_default_entries()

    def set_egress_drop_probability(self, probability):
        value = int(0xffff * probability)
        actual_value = float(value) / 0xffff
        self.logger.info("Setting egress drop probability to {} (actually 0x{:0x}, or {}).".format(probability, value, actual_value))
        self.table.default_entry_set(
            self.target,
            self.table.make_data([gc.DataTuple('probability', value)],
                                  'Egress.drop_sim.set_drop_probability'))
        



