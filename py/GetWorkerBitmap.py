######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc


from Table import Table
from Worker import Worker, WorkerType

class GetWorkerBitmap(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(GetWorkerBitmap, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('GetWorkerBitmap')
        self.logger.info("Setting up get_worker_bitmap table...")
        

        # get this table
        self.table = self.bfrt_info.table_get("pipe.Ingress.get_worker_bitmap.get_worker_bitmap")

        # set format annotations
        self.table.info.key_field_annotation_add("hdr.ethernet.dst_addr", "mac")
        self.table.info.key_field_annotation_add("hdr.ethernet.src_addr", "mac")
        self.table.info.key_field_annotation_add("hdr.ipv4.dst_addr", "ipv4")
        self.table.info.key_field_annotation_add("hdr.ipv4.src_addr", "ipv4")

        # some handy constants
        self.all_zeros_mac_address = "00:00:00:00:00:00"
        self.all_ones_mac_address = "ff:ff:ff:ff:ff:ff"
        self.all_zeros_ip_address = "0.0.0.0"
        self.all_ones_ip_address = "255.255.255.255"

        # clear and add defaults
        self.clear()
        self.add_default_entries()

        
        
    def add_default_entries(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)


    # Add SwitchML UDP entry to table
    def add_udp_entry(self, switch_mac, switch_ip, switch_udp_port, switch_udp_mask,
                      worker_id, worker_mac, worker_ip, worker_bitmap, num_workers,
                      match_priority, switch_mgid, pool_base, pool_size):
        self.logger.info("Adding worker {} {}".format(worker_mac, worker_ip))

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # if IP address is all zeros, don't use
        if worker_ip == '0.0.0.0':
            worker_ip_mask = self.all_zeros_ip_address
        else:
            worker_ip_mask = self.all_ones_ip_address
            
        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', match_priority),
                                  # match on Ethernet addrs, IPs and port
                                  gc.KeyTuple('hdr.ipv4.src_addr',
                                              worker_ip,
                                              worker_ip_mask),
                                  gc.KeyTuple('hdr.ipv4.dst_addr',
                                              switch_ip,
                                              self.all_ones_ip_address),
                                  gc.KeyTuple('hdr.ethernet.src_addr',
                                              worker_mac,
                                              self.all_ones_mac_address),
                                  gc.KeyTuple('hdr.ethernet.dst_addr',
                                              switch_mac,
                                              self.all_ones_mac_address),
                                  gc.KeyTuple('hdr.udp.dst_port',
                                              switch_udp_port, # 16 bits
                                              switch_udp_mask),
                                  
                                  # allow packets with no parser errors or with partial headers only (bit 2)
                                  gc.KeyTuple('ig_prsr_md.parser_err',
                                              0x0002, # 16 bits
                                              #0xfffb),
                                              0x0000),

                                  # don't match on ingress port; accept packets from a particular
                                  # worker no matter which port it comes in on.
                                  gc.KeyTuple('ig_intr_md.ingress_port',
                                              0x000, # 9 bits
                                              0x000),
                                  
                                  gc.KeyTuple('hdr.ib_bth.partition_key',
                                              0x0000, # 16 bits
                                              0x0000),
                                  gc.KeyTuple('hdr.ib_bth.dst_qp',
                                              0x000000, # 24 bits
                                              0x000000)])],
            [self.table.make_data([gc.DataTuple('mgid', switch_mgid),
                                   gc.DataTuple('worker_type', WorkerType.SWITCHML_UDP),
                                   gc.DataTuple('worker_id', worker_id),
                                   gc.DataTuple('packet_type', 0x1), # packet_type_t.CONSUME
                                   gc.DataTuple('num_workers', num_workers),
                                   gc.DataTuple('worker_bitmap', worker_bitmap),
                                   gc.DataTuple('complete_bitmap', (1 << num_workers) - 1),
                                   gc.DataTuple('pool_base', pool_base), 
                                   gc.DataTuple('pool_size_minus_1', pool_size - 1)],
                             'Ingress.get_worker_bitmap.set_bitmap')])


    def print_counters(self):
        self.table.operations_execute(self.target, 'SyncCounters')
        resp = self.table.entry_get(
            self.target,
            flags={"from_hw": False})

        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()

            worker_ip = k['hdr.ipv4.src_addr']['value']
            worker_id = v['worker_id']
            worker_packets = v['$COUNTER_SPEC_PKTS']
            worker_bytes = v['$COUNTER_SPEC_BYTES']

            print("Received from worker {:2} at {:15}: {:10} packets, {:10} bytes".format(worker_id, worker_ip, worker_packets, worker_bytes))
            #print("key {}: value {}".format(pformat(k), pformat(v)))

    def clear_counters(self):
        self.logger.info("Clearing get_worker_bitmap counters...")
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
