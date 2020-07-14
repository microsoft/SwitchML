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

    def __init__(self, client, bfrt_info, ports, switchml_mgid, all_mgid, cpu_port):
        # set up base class
        super(PRE, self).__init__(client, bfrt_info)

        # capture Ports class for front panel port converstion
        self.ports = ports

        self.switchml_mgid = switchml_mgid
        self.all_mgid = all_mgid
        self.cpu_port = cpu_port
        
        self.logger = logging.getLogger('PRE')
        self.logger.info("Setting up multicast tables...")
        
        # get this table
        self.mgid_table  = self.bfrt_info.table_get("$pre.mgid")
        self.node_table  = self.bfrt_info.table_get("$pre.node")
        self.ecmp_table  = self.bfrt_info.table_get("$pre.ecmp")
        self.lag_table   = self.bfrt_info.table_get("$pre.lag")
        self.prune_table = self.bfrt_info.table_get("$pre.prune")
        self.port_table  = self.bfrt_info.table_get("$pre.port")

        # keep port to rid mapping
        self.rid_counter = 0x80000
        self.rids = {}
        self.rids[self.switchml_mgid] = {}
        self.rids[self.all_mgid] = {}
        
        # clear and add defaults
        self.clear()
        self.add_default_entries()


    def clear(self):
        # first, clean up old group if they exist
        #self.mgid_table.entry_del(self.target) # ideally we could do this, but it's not supported.
        try:
            self.mgid_table.entry_del(
                self.target,
                [self.mgid_table.make_key([gc.KeyTuple('$MGID', self.switchml_mgid)])])
        except gc.BfruntimeReadWriteRpcException as e:
            self.logger.info("Multicast group ID {} not found in switch already during delete; this is expected.".format(self.switchml_mgid))
            
        try:
            self.mgid_table.entry_del(
                self.target,
                [self.mgid_table.make_key([gc.KeyTuple('$MGID', self.all_mgid)])])
        except gc.BfruntimeReadWriteRpcException as e:
            self.logger.info("Multicast group ID {} not found in switch already during delete; this is expected.".format(self.all_mgid))

        ## now, clean up old nodes.
        #self.node_table.entry_del(self.target)
        
        # try:
        #     self.node_table.entry_del(
        #         target,
        #         [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', worker.rid)])])
        # except gc.BfruntimeReadWriteRpcException as e:
        #     self.logger.info("Multicast node ID {} not found in switch already during delete; this is expected.".format(worker.rid))

        # # Set -1 as CopyToCPU port
        # print("Setting port", port, "as CopyToCPU port")
        # self.port_table.entry_add(
        #     self.target,
        #             [self.port_table.make_key([
        #                 client.KeyTuple('$DEV_PORT', port)])],
        #             [self.port_table.make_data([
        #                 client.DataTuple('$COPY_TO_CPU_PORT_ENABLE', bool_val=True)])]
        #         )

        # set CPU port
        print("Setting port", self.cpu_port, "as CopyToCPU port")
        self.port_table.entry_add(
            self.target,
            [self.port_table.make_key([
                gc.KeyTuple('$DEV_PORT', self.cpu_port)])],
            [self.port_table.make_data([
                gc.DataTuple('$COPY_TO_CPU_PORT_ENABLE', bool_val=True)])]
        )

            
        
    def add_default_entries(self):
        # create empty multicast group for switchml
        self.mgid_table.entry_add(
            self.target,
            [self.mgid_table.make_key([gc.KeyTuple('$MGID', self.switchml_mgid)])],
            [self.mgid_table.make_data([gc.DataTuple('$MULTICAST_NODE_ID',
                                                     int_arr_val=[]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID',
                                                     bool_arr_val=[]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID',
                                                     int_arr_val=[])])])

        # create empty multicast group for all ports
        self.mgid_table.entry_add(
            self.target,
            [self.mgid_table.make_key([gc.KeyTuple('$MGID', self.all_mgid)])],
            [self.mgid_table.make_data([gc.DataTuple('$MULTICAST_NODE_ID',
                                                     int_arr_val=[]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID',
                                                     bool_arr_val=[]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID',
                                                     int_arr_val=[])])])


    def worker_add(self, mgid, rid, port, lane):
        # get dev port for this worker
        dev_port = self.ports.get_dev_port(port, lane)

        if rid in self.rids[mgid]:
            print("Port {}/{} already added to multicast group {}; skipping.".format(port, lane, mgid))
            return

        # add to rid table for this group
        self.rids[mgid][dev_port] = rid

        # erase any existing entry
        try:
            self.node_table.entry_del(
                self.target,
                [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', rid)])])
        except gc.BfruntimeReadWriteRpcException as e:
            self.logger.info("Multicast node ID {} not found in switch already during delete; this is expected.".format(rid))

        # add to node table
        self.node_table.entry_add(
            self.target,
            [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', rid)])],
            [self.node_table.make_data([gc.DataTuple('$MULTICAST_RID', rid),
                                        gc.DataTuple('$DEV_PORT', int_arr_val=[dev_port])])])

        # now that node is added, extend multicast group
        self.mgid_table.entry_mod_inc(
            self.target,
            [self.mgid_table.make_key([gc.KeyTuple('$MGID', mgid)])],
            [self.mgid_table.make_data([gc.DataTuple('$MULTICAST_NODE_ID',
                                                     int_arr_val=[rid]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID',
                                                     bool_arr_val=[True]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID',
                                                     int_arr_val=[rid])])],
            bfruntime_pb2.TableModIncFlag.MOD_INC_ADD)



    def worker_del(self, mgid, rid):
        # remove group entry
        self.mgid_table.entry_mod_inc(
            self.target,
            [self.mgid_table.make_key([gc.KeyTuple('$MGID', mgid)])],
            [self.mgid_table.make_data([gc.DataTuple('$MULTICAST_NODE_ID', int_arr_val=[rid]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID',
                                                     bool_arr_val=[False]),
                                        gc.DataTuple('$MULTICAST_NODE_L1_XID', int_arr_val=[0])])],
            bfruntime_pb2.TableModIncFlag.MOD_INC_DELETE)

        # remove node entry
        self.node_table.entry_del(
            self.target,
            [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', rid)])])

        # delete from rid table
        dev_port = self.ports.get_dev_port(port, lane)
        del self.rids[mgid][dev_port]

        
    def worker_clear_all(self, mgid):
        for dev_port, rid in self.rids[mgid].items():
            try:
                # remove group entry
                self.mgid_table.entry_mod_inc(
                    self.target,
                    [self.mgid_table.make_key([gc.KeyTuple('$MGID', mgid)])],
                    [self.mgid_table.make_data([gc.DataTuple('$MULTICAST_NODE_ID', int_arr_val=[rid]),
                                                gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID',
                                                             bool_arr_val=[False]),
                                                gc.DataTuple('$MULTICAST_NODE_L1_XID', int_arr_val=[0])])],
                    bfruntime_pb2.TableModIncFlag.MOD_INC_DELETE)
            except gc.BfruntimeReadWriteRpcException as e:
                self.logger.info("Multicast node ID {} remove from group {} failed; maybe it's already deleted?".format(rid, mgid))


            try:
                # remove node entry
                self.node_table.entry_del(
                    self.target,
                    [self.node_table.make_key([gc.KeyTuple('$MULTICAST_NODE_ID', rid)])])
            except gc.BfruntimeReadWriteRpcException as e:
                self.logger.info("Multicast node ID {} delete failed; maybe it's already deleted?".format(rid))

            del self.rids[mgid][dev_port]
        
    
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
            

