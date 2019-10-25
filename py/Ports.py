######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

class Ports(object):

    # get dev port
    def get_dev_port(self, front_panel_port, lane):        
        # target all pipes on device 0
        target = self.gc.Target(device_id=0, pipe_id=0xffff)
        
        port_hdl_info_table = self.bfrt_info.table_get("$PORT_HDL_INFO")
        
        # convert front-panel port to dev port
        resp = port_hdl_info_table.entry_get(
            target,
            [port_hdl_info_table.make_key([gc.KeyTuple('$CONN_ID', front_panel_port),
                                           gc.KeyTuple('$CHNL_ID', lane)])],
            {"from_hw": False})
        dev_port = next(resp)[0].to_dict()["$DEV_PORT"]
        self.logger.info("Got dev port {} for front panel port {}/{}".format(dev_port, front_panel_port, lane))

        return dev_port


    # add ports
    #
    # port list is a list of tuples: (front panel port, lane, speed, FEC string)
    # speed is one of {10, 25, 40, 50, 100}
    # FEC string is one of {'none', 'fc', 'rs'}
    # Look in $SDE_INSTALL/share/bf_rt_shared/*.json for more info
    def add_ports(self, port_list):
        self.logger.info("Bringing up ports:\n {}".format(pformat(port_list)))
        
        speed_conversion_table = {10: "BF_SPEED_10G",
                                  25: "BF_SPEED_25G",
                                  40: "BF_SPEED_40G",
                                  50: "BF_SPEED_50G",
                                  100: "BF_SPEED_100G"}
        
        fec_conversion_table = {'none': "BF_FEC_TYP_NONE",
                                'fec': "BF_FEC_TYP_FC",
                                'rs': "BF_FEC_TYP_RS"}
        
        # target all pipes on device 0
        target = self.gc.Target(device_id=0, pipe_id=0xffff)
        
        # get relevant table
        port_table = self.bfrt_info.table_get("$PORT")

        for (front_panel_port, lane, speed, fec) in port_list:
            self.logger.info("Adding port {}".format((front_panel_port, lane, speed, fec)))
            port_table.entry_add(
                target,
                [port_table.make_key([gc.KeyTuple('$DEV_PORT', self.get_dev_port(front_panel_port, lane))])],
                [port_table.make_data([gc.DataTuple('$SPEED', str_val=speed_conversion_table[speed]),
                                       gc.DataTuple('$FEC', str_val=fec_conversion_table[fec]),
                                       gc.DataTuple('$PORT_ENABLE', bool_val=True)])])
            
    # add one port
    def add_port(self, front_panel_port, lane, speed, fec):
        self.add_ports([(front_panel_port, lane, speed, fec)])
            
    # delete all ports
    def delete_all_ports(self):
        self.logger.info("Deleting all ports...")
        
        # target all pipes on device 0
        target = self.gc.Target(device_id=0, pipe_id=0xffff)
        
        # list of all possible external dev ports (don't touch internal ones)
        two_pipe_dev_ports = range(0,64) + range(128,192)
        four_pipe_dev_ports = two_pipe_dev_ports + range(256,320) + range(384,448)
        
        # get relevant table
        port_table = self.bfrt_info.table_get("$PORT")
        
        # delete all dev ports from largest device
        # (can't use the entry_get -> entry_del process for port_table like we can for normal tables)
        dev_ports = four_pipe_dev_ports
        port_table.entry_del(
            target,
            [port_table.make_key([self.gc.KeyTuple('$DEV_PORT', i)])
             for i in dev_ports])
            
            
    def __init__(self, gc, bfrt_info):
        # get logging, client, and global program info
        self.logger = logging.getLogger('Ports')
        self.gc = gc
        self.bfrt_info = bfrt_info
