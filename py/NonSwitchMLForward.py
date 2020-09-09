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

    def __init__(self, client, bfrt_info, ports, mgid):
        # set up base class
        super(NonSwitchMLForward, self).__init__(client, bfrt_info)

        # capture Ports class for front panel port converstion
        self.ports = ports

        # mgid for non-SwitchML broadcast
        self.mgid = mgid

        self.logger = logging.getLogger('NonSwitchMLForward')
        self.logger.info("Setting up forward table...")
        
        # get this table
        self.table = self.bfrt_info.table_get("pipe.Ingress.non_switchml_forward.forward")

        # set format annotations
        self.table.info.key_field_annotation_add("hdr.ethernet.dst_addr", "mac")

        # keep set of mac addresses so we can delete them all without deleting the flood rule
        self.mac_addresses = {}
        
        # clear and add defaults
        self.clear()
        self.add_default_entries()

        
    def add_default_entries(self):
        # add broadcast entry
        self.table.entry_add(
            self.target,
            [self.table.make_key([gc.KeyTuple('hdr.ethernet.dst_addr',
                                              "ff:ff:ff:ff:ff:ff")])],
            [self.table.make_data([gc.DataTuple('flood_mgid', self.mgid)],
                                  'Ingress.non_switchml_forward.flood')])


    def worker_add(self, mac_address, front_panel_port, lane):
        dev_port = self.ports.get_dev_port(front_panel_port, lane)
        try:
            self.table.entry_add(
                self.target,
                [self.table.make_key([gc.KeyTuple('hdr.ethernet.dst_addr',
                                                  mac_address)])],
                [self.table.make_data([gc.DataTuple('egress_port', dev_port)],
                                      'Ingress.non_switchml_forward.set_egress_port')])
            self.mac_addresses[mac_address] = front_panel_port, lane
        except Exception as e:
            print("Error adding {} at {}/{}: {}".format(mac_address, front_panel_port, lane, e))

        
    def worker_del(self, mac_address):
        self.table.entry_del(
            self.target,
            [self.table.make_key([gc.KeyTuple('hdr.ethernet.dst_addr',
                                              mac_address)])])
        del self.mac_addresses[mac_address]

    def worker_print(self, requested_mac_address=None):
        print("  MAC address       Front panel port")

        if requested_mac_address:
            port, lane = self.mac_addresses[requested_mac_address]
            print("  {:>17} {:>2}/{}".format(requested_mac_address, port, lane))
        else:
            for mac_address, (port, lane) in self.mac_addresses.items():
                print("  {:>17} {:>2}/{}".format(mac_address, port, lane))

    def get_macs_on_port(self, fp_port, fp_lane):
        results = []
        for mac_address, (port, lane) in self.mac_addresses.items():
            print('checking {} {}/{} against {}/{}'.format(mac_address, port, lane, fp_port, fp_lane))
            if port == fp_port and lane == fp_lane:
                results.append(mac_address)

        return results
    
    def worker_clear_all(self):
        self.table.entry_add(
            self.target,
            [self.table.make_key([gc.KeyTuple('hdr.ethernet.dst_addr',
                                              mac_address)])
             for mac_address in self.mac_addresses])
        self.mac_addresses.clear()

    def worker_port_get(self, mac):
        if mac not in self.mac_addresses:
            raise Exception("Error: MAC address not configured on switch.")
        return self.mac_addresses[mac]
    
    def add_workers(self, switch_mgid, workers):
        for worker in workers:
            dev_port = self.ports.get_dev_port(worker.front_panel_port, worker.lane)
            self.table.entry_add(
                self.target,
                [self.table.make_key([gc.KeyTuple('hdr.ethernet.dst_addr',
                                                  worker.mac)])],
                [self.table.make_data([gc.DataTuple('egress_port', dev_port)],
                                      'Ingress.non_switchml_forward.set_egress_port')])

    def timing_loop(self):
        from backports.time_perf_counter import perf_counter
            
        # initialize
        self.table.entry_add(
            self.target,
            [self.table.make_key([gc.KeyTuple('hdr.ethernet.dst_addr',
                                              "00:11:22:33:44:55")])],
            [self.table.make_data([gc.DataTuple('egress_port', 0)],
                                  'Ingress.non_switchml_forward.set_egress_port')])

        count = 1000000
        start = perf_counter()
        for i in range(count):
            self.table.entry_mod(
                self.target,
                [self.table.make_key([gc.KeyTuple('hdr.ethernet.dst_addr',
                                                  "00:11:22:33:44:55")])],
                [self.table.make_data([gc.DataTuple('egress_port', 0)],
                                      'Ingress.non_switchml_forward.set_egress_port')])
        end = perf_counter()
        rate = count / (end - start)

        print("{} mods in {:02f} seconds: {:02f} m/s".format(count, end-start, rate))
