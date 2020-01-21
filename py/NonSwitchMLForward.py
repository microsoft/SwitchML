######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from Table import Table


class NonSwitchMLForward(Table):

    def __init__(self, client, bfrt_info, ports):
        # set up base class
        super(NonSwitchMLForward, self).__init__(client, bfrt_info)

        # capture Ports class for front panel port converstion
        self.ports = ports

        self.logger = logging.getLogger('NonSwitchMLForward')
        self.logger.info("Setting up forward table...")
        
        # get this table
        self.table = self.bfrt_info.table_get("pipe.SwitchMLIngress.non_switchml_forward.forward")

        # set format annotations
        self.table.info.key_field_annotation_add("hdr.ethernet.dst_addr", "mac")

        # clear and add defaults
        self.clear()
        self.add_default_entries()

        
    def add_default_entries(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # nothing to do for this table!
        pass

    def add_workers(self, switch_mgid, workers):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # add broadcast entry
        self.table.entry_add(
            target,
            [self.table.make_key([# match on egress RID and port
                                  gc.KeyTuple('ig_md.switchml_md.packet_type',
                                                  0x0), # packet_type_t.IGNORE
                                  gc.KeyTuple('hdr.ethernet.dst_addr',
                                              "ff:ff:ff:ff:ff:ff")])],
                [self.table.make_data([gc.DataTuple('flood_mgid', switch_mgid)],
                                      'SwitchMLIngress.non_switchml_forward.flood')])
        
        for worker in workers:
            dev_port = self.ports.get_dev_port(worker.front_panel_port, worker.lane)
            self.table.entry_add(
                target,
                [self.table.make_key([# match on egress RID and port
                                      gc.KeyTuple('ig_md.switchml_md.packet_type',
                                                  0x0), # packet_type_t.IGNORE
                                      gc.KeyTuple('hdr.ethernet.dst_addr',
                                                  worker.mac)])],
                [self.table.make_data([gc.DataTuple('egress_port', dev_port)],
                                      'SwitchMLIngress.non_switchml_forward.set_egress_port')])
