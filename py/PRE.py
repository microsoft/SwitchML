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
        # get number of bytes for port_count-width bitmap
        dev_port_count = 288
        bitmap_byte_count = (dev_port_count + 7) / 8
        bitmap = [0] * bitmap_byte_count

        # get index of bit to set (convert from dev_port to contiguous)
        pipe_index    = dev_port >> 7
        index_in_pipe = dev_port & 0x7f
        index         = 72 * pipe_index + index_in_pipe

        # get byte index and index in byte to set
        byte_index = index / 8
        bit_index  = index % 8
        
        # set bit in array
        self.logger.debug("Setting bit in PRE bitmap byte {} bit {} for dev_port {}".format(byte_index, bit_index, dev_port))
        bitmap[byte_index] = bitmap[byte_index] | (1 << bit_index) & 0xff
        
        # return byte array
        return bytearray(bitmap)
        
    def add_workers(self, switchml_workers_mgid, switchml_workers, all_ports_mgid, all_workers):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # compute list of ports for the all_ports group
        all_ports = [self.ports.get_dev_port(worker.front_panel_port, worker.lane) for worker in all_workers]
        
        # first, clean up old group if they exist
        #self.mgid_table.entry_del(target) # ideally we could do this, but it's not supported.
        try:
            self.mgid_table.entry_del(
                target,
                [self.mgid_table.make_key([gc.KeyTuple('$MGID', switchml_workers_mgid)])])
        except gc.BfruntimeReadWriteRpcException as e:
            self.logger.info("Multicast group ID {} not found in switch already during delete; this is expected.".format(switchml_workers_mgid))
            
        try:
            self.mgid_table.entry_del(
                target,
                [self.mgid_table.make_key([gc.KeyTuple('$MGID', all_ports_mgid)])])
        except gc.BfruntimeReadWriteRpcException as e:
            self.logger.info("Multicast group ID {} not found in switch already during delete; this is expected.".format(all_ports_mgid))

        # and clean up old nodes if they exist
        for worker in switchml_workers:
            try:
                self.node_table.entry_del(
                    target,
                    [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', worker.rid)])])
            except gc.BfruntimeReadWriteRpcException as e:
                self.logger.info("Multicast node ID {} not found in switch already during delete; this is expected.".format(worker.rid))

        for port in all_ports:
            try:
                self.node_table.entry_del(
                    target,
                    [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', 0x8000 + port)])])
            except gc.BfruntimeReadWriteRpcException as e:
                self.logger.info("Multicast node ID {} not found in switch already during delete; this is expected.".format(port))

        # now add new nodes
        for worker in switchml_workers:
            dev_port = self.ports.get_dev_port(worker.front_panel_port, worker.lane)
            self.node_table.entry_add(
                target,
                [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', worker.rid)])],
                [self.node_table.make_data([gc.DataTuple('$MULTICAST_RID', worker.rid),
                                            gc.DataTuple('$DEV_PORT', int_arr_val=[dev_port])])])

        for port in all_ports:
            self.node_table.entry_add(
                target,
                [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', 0x8000 + port)])],
                [self.node_table.make_data([gc.DataTuple('$MULTICAST_RID', 0x8000 + port),
                                            gc.DataTuple('$DEV_PORT', int_arr_val=[port])])])

        # now that nodes are added, create multicast groups
        self.mgid_table.entry_add(
            target,
            [self.mgid_table.make_key([gc.KeyTuple('$MGID', switchml_workers_mgid)])],
            [self.mgid_table.make_data([gc.DataTuple('$MULTICAST_NODE_ID',
                                                     int_arr_val=[worker.rid for worker in switchml_workers]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID',
                                                     bool_arr_val=[True for worker in switchml_workers]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID',
                                                     int_arr_val=[worker.xid for worker in switchml_workers])])])
        self.mgid_table.entry_add(
            target,
            [self.mgid_table.make_key([gc.KeyTuple('$MGID', all_ports_mgid)])],
            [self.mgid_table.make_data([gc.DataTuple('$MULTICAST_NODE_ID',
                                                     int_arr_val=[0x8000 + port for port in all_ports]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID',
                                                     bool_arr_val=[True for port in all_ports]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID',
                                                     int_arr_val=[0x8000 + port for port in all_ports])])])
            

