# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

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
        self.logger.info("Setting up drop simulator...")
        
        # get this table
        self.table = self.bfrt_info.table_get("pipe.IngressParser.$PORT_METADATA")

        # clear and add defaults
        self.clear()
        #self.add_default_entries()

    def set_drop_probabilities(self, ingress_drop_probability, egress_drop_probability):
        ingress_drop_value = int(0xffff * ingress_drop_probability)
        ingress_drop_actual_value = float(ingress_drop_value) / 0xffff

        egress_drop_value = int(0xffff * egress_drop_probability)
        egress_drop_actual_value = float(egress_drop_value) / 0xffff

        self.logger.info("Setting ingress drop probability to {} (actually 0x{:0x}, or {}).".format(ingress_drop_probability,
                                                                                                    ingress_drop_value,
                                                                                                    ingress_drop_actual_value))
        self.logger.info("Setting egress drop probability to {} (actually 0x{:0x}, or {}).".format(egress_drop_probability,
                                                                                                   egress_drop_value,
                                                                                                   egress_drop_actual_value))

        if ingress_drop_value == 0 and egress_drop_value == 0:
            self.table.entry_del(self.target)
        else:
            # set in all ports
            num_ports = 288
            self.table.entry_add(
                self.target,
                [self.table.make_key([gc.KeyTuple('ig_intr_md.ingress_port', p)])
                 for p in range(num_ports)],
                [self.table.make_data([
                    gc.DataTuple('ingress_drop_probability', ingress_drop_value),
                    gc.DataTuple('egress_drop_probability', egress_drop_value)])] * num_ports)
        



