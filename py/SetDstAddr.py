######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from Table import Table


class SetDstAddr(Table):

    def __init__(self, client, bfrt_info, switch_mac, switch_ip):
        # set up base class
        super(SetDstAddr, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('SetDstAddr')
        self.logger.info("Setting up set_dst_addr table...")
        
        self.switch_mac = switch_mac
        self.switch_ip = switch_ip

        # get these tables
        self.switch_mac_and_ip = self.bfrt_info.table_get("pipe.SwitchMLEgress.set_dst_addr.switch_mac_and_ip")
        self.table = self.bfrt_info.table_get("pipe.SwitchMLEgress.set_dst_addr.set_dst_addr")

        # set format annotations
        self.switch_mac_and_ip.info.data_field_annotation_add("switch_mac", 'SwitchMLEgress.set_dst_addr.set_switch_mac_and_ip', "mac")
        self.switch_mac_and_ip.info.data_field_annotation_add("switch_ip",  'SwitchMLEgress.set_dst_addr.set_switch_mac_and_ip', "ipv4")
        self.table.info.data_field_annotation_add("ip_dst_addr",  'SwitchMLEgress.set_dst_addr.set_dst_addr_for_SwitchML_UDP', "ipv4")
        self.table.info.data_field_annotation_add("eth_dst_addr", 'SwitchMLEgress.set_dst_addr.set_dst_addr_for_SwitchML_UDP', "mac")

        # clear and add defaults
        self.clear()
        self.add_default_entries()

    def clear(self):
        self.table.entry_del(self.target)
        self.switch_mac_and_ip.entry_del(self.target)
        
    def add_default_entries(self):
        # set switch MAC/IP and message size and mask
        self.switch_mac_and_ip.default_entry_set(
            self.target,
            self.switch_mac_and_ip.make_data([gc.DataTuple('switch_mac', self.switch_mac),
                                              gc.DataTuple('switch_ip', self.switch_ip)],
                                             'SwitchMLEgress.set_dst_addr.set_switch_mac_and_ip'))

    def clear_udp_entries(self):
        self.table.entry_del(self.target)

    # Add SwitchML UDP entry to table
    def add_udp_entry(self, worker_rid, worker_mac, worker_ip):
        self.logger.info("Adding worker {} {} at rid {}".format(worker_mac, worker_ip, worker_rid))

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('eg_md.switchml_md.worker_id',
                                              worker_rid)])],
            [self.table.make_data([gc.DataTuple('eth_dst_addr', worker_mac),
                                   gc.DataTuple('ip_dst_addr', worker_ip)],
                                  'SwitchMLEgress.set_dst_addr.set_dst_addr_for_SwitchML_UDP')])

    def print_counters(self):
        self.table.operations_execute(self.target, 'SyncCounters')
        resp = self.table.entry_get(
            self.target,
            flags={"from_hw": False})

        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()
            
            worker_id = k['eg_md.switchml_md.worker_id']['value']
            worker_ip = v['ip_dst_addr']
            worker_packets = v['$COUNTER_SPEC_PKTS']
            worker_bytes = v['$COUNTER_SPEC_BYTES']
            
            print("Sent to worker       {:2} at {:15}: {:10} packets, {:10} bytes".format(worker_id, worker_ip, worker_packets, worker_bytes))
            #print("key {}: value {}".format(pformat(k), pformat(v)))
            
    def clear_counters(self):
        self.logger.info("Clearing set_dst_addr counters...")
        self.table.operations_execute(self.target, 'SyncCounters')
        resp = self.table.entry_get(
            self.target,
            flags={"from_hw": False})

        keys = []
        values = []
        
        for v, k in resp:
            keys.append(k)

            v = v.to_dict()
            k = k.to_dict()

            values.append(
                self.table.make_data(
                    [gc.DataTuple('$COUNTER_SPEC_BYTES', 0),
                     gc.DataTuple('$COUNTER_SPEC_PKTS', 0)],
                    v['action_name']))

        self.table.entry_mod(
            self.target,
            keys,
            values)
            
