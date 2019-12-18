######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from Table import Table
from Worker import Worker


class PRE(Table):

    def __init__(self, client, bfrt_info, ports):
        # set up base class
        super(PRE, self).__init__(client, bfrt_info)

        # capture Ports class for front panel port converstion
        self.ports = ports
        
        self.logger = logging.getLogger('PRE')
        self.logger.info("Setting up multicast tables...")
        
        # get this table
        self.mgid_table    = self.bfrt_info.table_get("$pre.mgid")
        self.node_table    = self.bfrt_info.table_get("$pre.node")

        # clear and add defaults
        ###self.clear()
        ###self.add_default_entries()

    def dev_port_to_bitmap(self, dev_port):
        port_count = 288
        # get number of bytes for port_count-width bitmap
        bitmap_byte_count = (port_count + 7) / 8
        bitmap = [0] * bitmap_byte_count
        # get index of bit to set
        byte_index = dev_port / 8
        bit_index = dev_port % 8
        # set bit in array
        bitmap[byte_index] = bitmap[byte_index] | (1 << bit_index)
        # return byte array
        return bytearray(bitmap)
        
    def add_workers(self, switch_mgid, workers):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # first, clean up old group if it exists
        try:
            self.mgid_table.entry_del(
                target,
                [self.mgid_table.make_key([gc.KeyTuple('$MGID', switch_mgid)])])
        except grpc.RpcError as e:
            if e.code() != grpc.StatusCode.UNKNOWN:
                    raise e
            else:
                self.logger.info("Multicast group ID {} not found in switch already during delete; this is fine.".format(switch_mgid))

        # and clean up old nodes if they exist
        for worker in workers:
            # clean up old node if it exists
            try:
                self.node_table.entry_del(
                    target,
                    [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', worker.rid)])])
            except grpc.RpcError as e:
                if e.code() != grpc.StatusCode.UNKNOWN:
                    raise e
                self.logger.info("Multicast node ID {} not found in switch already during delete; this is expected.".format(worker.rid))

        # now add new nodes
        for worker in workers:
            dev_port = self.ports.get_dev_port(worker.front_panel_port, worker.lane)
            self.node_table.entry_add(
                target,
                [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', worker.rid)])],
                [self.node_table.make_data([gc.DataTuple('$MULTICAST_RID', worker.rid),
                                            gc.DataTuple('$MULTICAST_LAG_BITMAP', 0x0),
                                            gc.DataTuple('$MULTICAST_PORT_BITMAP', self.dev_port_to_bitmap(dev_port))])])

        # now that nodes are added, create multicast group
        self.mgid_table.entry_add(
            target,
            [self.mgid_table.make_key([gc.KeyTuple('$MGID', switch_mgid)])],
            [self.mgid_table.make_data([gc.DataTuple('$MULTICAST_NODE_ID',
                                                     int_arr_val=[worker.rid for worker in workers]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID',
                                                     bool_arr_val=[False for worker in workers]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID',
                                                     int_arr_val=[0 for worker in workers])])])
            

