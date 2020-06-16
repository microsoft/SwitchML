######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

class Ports(object):

    def __init__(self, gc, bfrt_info):
        # get logging, client, and global program info
        self.logger = logging.getLogger('Ports')
        self.gc = gc
        self.bfrt_info = bfrt_info

        # assume we have 4 pipes
        self.num_pipes = 4
        
        # target all pipes on device 0
        self.target = self.gc.Target(device_id=0, pipe_id=0xffff)
        
        # get port table
        self.port_table = self.bfrt_info.table_get("$PORT")

        # statistics table
        self.port_stats_table = self.bfrt_info.table_get("$PORT_STAT")

        # FP port to dev port lookup table
        self.port_hdl_info_table = self.bfrt_info.table_get("$PORT_HDL_INFO")

        # dev port to FP port reverse lookup table
        self.dev_port_to_fp_port = None

        # list of active ports
        self.active_ports = []

        # pktget table to configure recirculation
        self.pktgen_port_cfg_table = self.bfrt_info.table_get("$PKTGEN_PORT_CFG")

        
    # get dev port
    def get_dev_port(self, front_panel_port, lane):        
        # convert front-panel port to dev port
        resp = self.port_hdl_info_table.entry_get(
            self.target,
            [self.port_hdl_info_table.make_key([gc.KeyTuple('$CONN_ID', front_panel_port),
                                                gc.KeyTuple('$CHNL_ID', lane)])],
            {"from_hw": False})
        dev_port = next(resp)[0].to_dict()["$DEV_PORT"]
        #self.logger.debug("Got dev port {} for front panel port {}/{}".format(dev_port, front_panel_port, lane))

        return dev_port

    # get front panel port from dev port
    def get_fp_port(self, dev_port):
        # if we haven't filled the reverse mapping dict yet, do so
        if self.dev_port_to_fp_port is None:
            self.dev_port_to_fp_port = {}

            # get all ports
            resp = self.port_hdl_info_table.entry_get(
                self.target,
                [],
                {"from_hw": False})

            # fill in dictionary
            for v, k in resp:
                v = v.to_dict()
                k = k.to_dict()
                self.dev_port_to_fp_port[v['$DEV_PORT']] = (k['$CONN_ID']['value'], k['$CHNL_ID']['value'])

        # look up front panel port/lane from dev port
        return self.dev_port_to_fp_port[dev_port]


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
        
        for (front_panel_port, lane, speed, fec) in port_list:
            self.logger.info("Adding port {}".format((front_panel_port, lane, speed, fec)))
            self.port_table.entry_add(
                self.target,
                [self.port_table.make_key([gc.KeyTuple('$DEV_PORT', self.get_dev_port(front_panel_port, lane))])],
                [self.port_table.make_data([gc.DataTuple('$SPEED', str_val=speed_conversion_table[speed]),
                                            gc.DataTuple('$FEC', str_val=fec_conversion_table[fec]),
                                            gc.DataTuple('$AUTO_NEGOTIATION', 2), # disable autonegotiation
                                            gc.DataTuple('$PORT_ENABLE', bool_val=True)])])
        self.active_ports.append(self.get_dev_port(front_panel_port, lane))
        
    # add one port
    def add_port(self, front_panel_port, lane, speed, fec):
        dev_port = self.get_dev_port(front_panel_port, lane)
        if dev_port in self.active_ports:
            print("Port {}/{} already in active ports list; skipping.".format(front_panel_port, lane))
            return
        
        self.add_ports([(front_panel_port, lane, speed, fec)])

    # add one port
    def port_add(self, front_panel_port, lane, speed, fec):
        dev_port = self.get_dev_port(front_panel_port, lane)
        if dev_port in self.active_ports:
            print("Port {}/{} already in active ports list; skipping.".format(front_panel_port, lane))
            return

        self.add_ports([(front_panel_port, lane, speed, fec)])


    # delete all ports
    def delete_all_ports(self):
        self.logger.info("Deleting all ports...")
        
        # list of all possible external dev ports (don't touch internal ones)
        two_pipe_dev_ports = range(0,64) + range(128,192)
        four_pipe_dev_ports = two_pipe_dev_ports + range(256,320) + range(384,448)
        
        # delete all dev ports from largest device
        # (can't use the entry_get -> entry_del process for port_table like we can for normal tables)
        dev_ports = four_pipe_dev_ports
        self.port_table.entry_del(
            self.target,
            [self.port_table.make_key([self.gc.KeyTuple('$DEV_PORT', i)])
             for i in dev_ports])

    # delete one port
    def port_delete(self, front_panel_port, lane):
        # get dev port
        dev_port = self.get_dev_port(front_panel_port, lane)

        # remove from our local active port list
        self.active_ports.remove(dev_port)

        # remove on switch
        self.port_table.entry_del(
            self.target,
            [self.port_table.make_key([self.gc.KeyTuple('$DEV_PORT', dev_port)])])

    # print all ports
    def list_ports(self, port=None, lane=None):
        # if we specified a port, just list it; otherwise list all active
        if port:
            if not lane:
                lane = 0
            dev_port = self.get_dev_port(port, lane)
            dev_ports = [dev_port]

            if dev_port not in self.active_ports:
                print("Port {}/{} not active.".format(port, lane))
                return
        else:
            if self.active_ports:
                dev_ports = self.active_ports
            else:
                print("No ports active.")
                return
            
        # get port info
        result = self.port_table.entry_get(
            self.target,
            [self.port_table.make_key([gc.KeyTuple('$DEV_PORT', i)])
             for i in dev_ports],
            {'from_hw': False})

        # get stats
        stats_result = self.port_stats_table.entry_get(
            self.target,
            [self.port_stats_table.make_key([gc.KeyTuple('$DEV_PORT', i)])
             for i in dev_ports],
            {"from_hw": True})

        pprint(dev_ports)
        pprint(stats_result)
        
        # construct stats dict indexed by dev_port
        stats = {}
        for v, k in stats_result:
            v = v.to_dict()
            k = k.to_dict()
            dev_port = k['$DEV_PORT']['value']
            stats[dev_port] = v
            
        # combine keys and values into one list of dicts
        values = []
        for v, k in result:
            v = v.to_dict()
            k = k.to_dict()
            
            # insert dev_port into result dict
            dev_port = k['$DEV_PORT']['value']
            v['$DEV_PORT'] = dev_port

            # remove prefixes from FEC and SPEED
            v['$FEC'] = v['$FEC'][len('BF_FEC_TYP_'):]
            v['$SPEED'] = v['$SPEED'][len('BF_SPEED_'):]

            # copy in port stats
            v['bytes_received'] = stats[dev_port]['$OctetsReceivedinGoodFrames']
            v['packets_received'] = stats[dev_port]['$FramesReceivedOK']
            v['errors_received'] = stats[dev_port]['$FrameswithanyError']
            v['bytes_sent'] = stats[dev_port]['$OctetsTransmittedwithouterror']
            v['packets_sent'] = stats[dev_port]['$FramesTransmittedOK']

            # add to combined list
            values.append(v)
        
        # sort by front panel port/lane
        values.sort(key=lambda x: (x['$CONN_ID'], x['$CHNL_ID']))

        format_string = ("  {$PORT_NAME:>4} {$PORT_UP:2} {$IS_VALID:5} {$PORT_ENABLE:7} {$SPEED:>5} {$FEC:>4}" +
                         " {packets_sent:>16} {bytes_sent:>16} {packets_received:>16} {bytes_received:>16} {errors_received:>16}")
        header = {'$PORT_NAME': 'Port',
                  '$PORT_UP': 'Up',
                  '$IS_VALID': 'Valid',
                  '$PORT_ENABLE': 'Enabled',
                  '$SPEED': 'Speed',
                  '$FEC': ' FEC',
                  'bytes_received': 'Rx Bytes',
                  'bytes_sent': 'Tx Bytes',
                  'packets_received': 'Rx Packets',
                  'packets_sent': 'Tx Packets',
                  'errors_received': 'Rx Errors',
        }
        
        print(format_string.format(**header))
        for v in values:
            print(format_string.format(**v))
        
    def enable_additional_loopback_ports(self):
        # self.logger.info(pformat(self.bfrt_info.table_dict))
        # self.logger.info("------")
        # self.logger.info(pformat(self.pktgen_port_cfg_table.info.action_dict))
        # self.logger.info(pformat(self.pktgen_port_cfg_table.info.key_dict))
        # self.logger.info(pformat(self.pktgen_port_cfg_table.info.data_dict))

        print("Precheck")
        resp = self.pktgen_port_cfg_table.entry_get(
            self.target,
            [self.pktgen_port_cfg_table.make_key([gc.KeyTuple('dev_port', dev_port)])
             for dev_port in [64, 192, 320, 448]],
            {'from_hw': False})

        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()
            pprint((k, v))

        # print("Modifying")
        
        #for dev_port in [64, 192, 320, 448]:
        for dev_port in [192, 320, 448]:
        #for dev_port in [320]:
            print("Modifying port {}".format(dev_port))
            self.pktgen_port_cfg_table.entry_add(
                self.target,
                [self.pktgen_port_cfg_table.make_key([gc.KeyTuple('dev_port', dev_port)])],
                [self.pktgen_port_cfg_table.make_data([gc.DataTuple('recirculation_enable', bool_val=True)])])

        print("Checking")
        resp = self.pktgen_port_cfg_table.entry_get(
            self.target,
            [self.pktgen_port_cfg_table.make_key([gc.KeyTuple('dev_port', dev_port)])
             for dev_port in [64, 192, 320, 448]],
            {'from_hw': False})

        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()
            pprint((k, v))

        
            #for dev_port in [64, 192, 320, 448]:
        
        # move CPU ethernet port to loopback
        # self.port_table.entry_add(
        #     self.target,
        #     [self.port_table.make_key([gc.KeyTuple('$DEV_PORT', 64)])],
        #         [self.port_table.make_data([gc.DataTuple('$SPEED', str_val='BF_SPEED_100G'),
        #                                     gc.DataTuple('$FEC', str_val='BF_FEC_TYP_NONE'),
        #                                     gc.DataTuple('$LOOPBACK_MODE', str_val="BF_LPBK_MAC_NEAR"),
        #                                     gc.DataTuple('$PORT_ENABLE', bool_val=True)])])
        # self.active_ports.append(64)

        # # try CPU pcie port to loopback
        # self.port_table.entry_add(
        #     self.target,
        #     [self.port_table.make_key([gc.KeyTuple('$DEV_PORT', 320)])],
        #         [self.port_table.make_data([gc.DataTuple('$SPEED', str_val='BF_SPEED_100G'),
        #                                     gc.DataTuple('$FEC', str_val='BF_FEC_TYP_NONE'),
        #                                     gc.DataTuple('$LOOPBACK_MODE', str_val="BF_LPBK_MAC_NEAR"),
        #                                     gc.DataTuple('$PORT_ENABLE', bool_val=True)])])
        # self.active_ports.append(64)


        
        # for i in range(self.num_pipes):
        #     pipe_base = i << 7
        #     cpu_port = 64


    def print_port_stats(self):
        print("Port statistics:")

        #self.enable_additional_loopback_ports()
        
        port_list = self.active_ports

        # for i in range(self.num_pipes):
        #     pipe_base = i << 7
        #     # add dedicated recirc port for this pipe
        #     port_list.append(pipe_base + 68)
        
        # resp = self.port_stats_table.entry_get(
        #     self.target,
        #     [self.port_stats_table.make_key([gc.KeyTuple('$DEV_PORT', i)])
        #      for i in self.active_ports],
        #     {"from_hw": True})

        # for v, k in resp:
        #     v = v.to_dict()
        #     k = k.to_dict()
        #     print("Key:")
        #     pprint(k)
        #     print("Value:")
        #     pprint(v)
            
        #[],
        #    {from
