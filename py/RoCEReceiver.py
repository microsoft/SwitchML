######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc
import struct

from Table import Table
from Worker import Worker, WorkerType, PacketSize
from Packets import roce_opcode_s2n

class RoCEReceiver(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(RoCEReceiver, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('RoCEReceiver')
        self.logger.info("Setting up receive_roce table...")
        

        # get this table
        self.table = self.bfrt_info.table_get("pipe.Ingress.roce_receiver.receive_roce")
        self.rdma_packet_counter = self.bfrt_info.table_get("pipe.Ingress.roce_receiver.rdma_packet_counter")
        self.rdma_message_counter = self.bfrt_info.table_get("pipe.Ingress.roce_receiver.rdma_message_counter")
        self.rdma_sequence_violation_counter = self.bfrt_info.table_get("pipe.Ingress.roce_receiver.rdma_sequence_violation_counter")
        
        # set format annotations
        self.table.info.key_field_annotation_add("hdr.ipv4.dst_addr", "ipv4")
        self.table.info.key_field_annotation_add("hdr.ipv4.src_addr", "ipv4")

        # clear and add defaults
        self.clear()

        # only const defaults
        #self.add_default_entries()

    def clear(self):
        if self.table is not None:
            self.table.entry_del(self.target)
            
        if self.rdma_message_counter is not None:
            # # this doesn't work yet!
            #self.rdma_message_counter.entry_del(self.target)
            #self.rdma_sequence_violation_counter.entry_del(self.target)

            # generate clear operations for both message and sequence violation countsers
            
            #keys_resp = self.rdma_message_counter.entry_get(self.target)

            packet_keys = []
            packet_values = []
            message_keys = []
            message_values = []
            sequence_violation_keys = []
            sequence_violation_values = []
            for i in range(self.rdma_message_counter.info.size):
                packet_keys.append(self.rdma_packet_counter.make_key([gc.KeyTuple('$COUNTER_INDEX', i)]))
                packet_values.append(self.rdma_packet_counter.make_data([gc.DataTuple('$COUNTER_SPEC_PKTS', 0)]))
                message_keys.append(self.rdma_message_counter.make_key([gc.KeyTuple('$COUNTER_INDEX', i)]))
                message_values.append(self.rdma_message_counter.make_data([gc.DataTuple('$COUNTER_SPEC_PKTS', 0)]))
                sequence_violation_keys.append(self.rdma_sequence_violation_counter.make_key([gc.KeyTuple('$COUNTER_INDEX', i)]))
                sequence_violation_values.append(self.rdma_sequence_violation_counter.make_data([gc.DataTuple('$COUNTER_SPEC_PKTS', 0)]))

            self.rdma_packet_counter.entry_add(
                self.target,
                packet_keys,
                packet_values)

            self.rdma_message_counter.entry_add(
                self.target,
                message_keys,
                message_values)

            self.rdma_sequence_violation_counter.entry_add(
                self.target,
                sequence_violation_keys,
                sequence_violation_values)


        
    # Add SwitchML RoCE v2 entry to table
    def add_entry(self, switch_mac, switch_ip, switch_partition_key, switch_mgid,
                  worker_ip, worker_rid, worker_bitmap, worker_packet_size,
                  num_workers):
        self.logger.info("Adding RoCE worker {}".format(worker_ip))

        if worker_rid >= 0x8000:
            self.logger.error("Worker RID {} too large; only 32K workers supported by this code.".format(worker_rid))

        if num_workers > 0x8000:
            self.logger.error("Worker count {} too large; only 32K workers supported by this code.".format(num_workers))

        # add entry for each opcode for each worker
        for opcode, action in [
                # (roce_opcode_s2n['UC_SEND_FIRST'],  'Ingress.roce_receiver.first_packet'),
                # (roce_opcode_s2n['UC_SEND_MIDDLE'], 'Ingress.roce_receiver.middle_packet'),
                # (roce_opcode_s2n['UC_SEND_LAST'],   'Ingress.roce_receiver.last_packet'),
                # (roce_opcode_s2n['UC_SEND_ONLY'],   'Ingress.roce_receiver.only_packet'),
                # (roce_opcode_s2n['UC_SEND_LAST_IMMEDIATE'],   'Ingress.roce_receiver.last_packet'),
                # (roce_opcode_s2n['UC_SEND_ONLY_IMMEDIATE'],   'Ingress.roce_receiver.only_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_FIRST'],  'Ingress.roce_receiver.first_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_MIDDLE'], 'Ingress.roce_receiver.middle_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_LAST'],   'Ingress.roce_receiver.last_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_ONLY'],   'Ingress.roce_receiver.only_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_LAST_IMMEDIATE'],   'Ingress.roce_receiver.last_packet'),
                (roce_opcode_s2n['UC_RDMA_WRITE_ONLY_IMMEDIATE'],   'Ingress.roce_receiver.only_packet')]:
            qpn_top_bits = 0x800000 | ((worker_rid & 0xff) << 16)
            self.table.entry_add(
                self.target,
                [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', 10), # doesn't matter
                                      # match on Ethernet addrs, IPs and port
                                      gc.KeyTuple('hdr.ipv4.src_addr',
                                                  worker_ip),
                                      gc.KeyTuple('hdr.ipv4.dst_addr',
                                                  switch_ip),
                                      gc.KeyTuple('hdr.ib_bth.partition_key',
                                                  switch_partition_key),
                                      gc.KeyTuple('hdr.ib_bth.opcode',
                                                  opcode),
                                      gc.KeyTuple('hdr.ib_bth.dst_qp',
                                                  qpn_top_bits,   # match on top bits of QP to allow for multiple clients on same machine.
                                                  0xff0000)])],
                [self.table.make_data([gc.DataTuple('mgid', switch_mgid),
                                       gc.DataTuple('worker_type', WorkerType.ROCEv2),
                                       # gc.DataTuple('worker_id', struct.pack('@H', worker_rid)),
                                       # gc.DataTuple('num_workers', struct.pack('@H', num_workers)),
                                       gc.DataTuple('worker_id',  worker_rid),
                                       gc.DataTuple('num_workers', num_workers),
                                       gc.DataTuple('packet_size', worker_packet_size),
                                       gc.DataTuple('worker_bitmap', worker_bitmap)],
                                      action)])

            # clear counters
            self.table.entry_mod(
                self.target,
                [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', 10),
                                      # match on Ethernet addrs, IPs and port
                                      gc.KeyTuple('hdr.ipv4.src_addr',
                                                  worker_ip),
                                      gc.KeyTuple('hdr.ipv4.dst_addr',
                                                  switch_ip),
                                      gc.KeyTuple('hdr.ib_bth.partition_key',
                                                  switch_partition_key),
                                      gc.KeyTuple('hdr.ib_bth.opcode',
                                                  opcode),
                                      gc.KeyTuple('hdr.ib_bth.dst_qp',
                                                  qpn_top_bits,   # match on top bits of QP to allow for multiple clients on same machine.
                                                  0xff0000)])],
                [self.table.make_data([gc.DataTuple('$COUNTER_SPEC_BYTES', 0),
                                       gc.DataTuple('$COUNTER_SPEC_PKTS', 0)],
                                      action)])


    def print_counters(self):
        self.table.operations_execute(self.target, 'SyncCounters')
        resp = self.table.entry_get(
            self.target,
            flags={"from_hw": False})

        ips = {}
        total_packets = {}
        total_bytes = {}
        #total_messages = {}
        
        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()

            #print("key {}: value {}".format(pformat(k), pformat(v)))
            
            worker_ip = k['hdr.ipv4.src_addr']['value']
            worker_id = v['worker_id']
            worker_packets = v['$COUNTER_SPEC_PKTS']
            worker_bytes = v['$COUNTER_SPEC_BYTES']

            if worker_id not in ips:
                ips[worker_id] = worker_ip
                total_packets[worker_id] = worker_packets
                total_bytes[worker_id]   = worker_bytes
            else:
                total_packets[worker_id] = total_packets[worker_id] + worker_packets
                total_bytes[worker_id]   = total_bytes[worker_id] + worker_bytes

        for i, p in total_packets.items():
            ip = ips[i]
            b = total_bytes[i]
            print("Received from worker {:2} at {:15}: {:10} packets, {:10} bytes".format(i, ip, p, b))


    #def get_queue_pair_counters(self, start=None, count=None):
    def get_queue_pair_counters(self, start=0, count=8):
        # get other per-queue-pair info
        self.rdma_packet_counter.operations_execute(self.target, 'Sync')
        self.rdma_message_counter.operations_execute(self.target, 'Sync')
        self.rdma_sequence_violation_counter.operations_execute(self.target, 'Sync')

        packets_resp = self.rdma_packet_counter.entry_get(
            self.target,
            [self.rdma_packet_counter.make_key([gc.KeyTuple('$COUNTER_INDEX', i)])
             for i in range(start, start+count)],
            flags={"from_hw": True})
        messages_resp = self.rdma_message_counter.entry_get(
            self.target,
            [self.rdma_message_counter.make_key([gc.KeyTuple('$COUNTER_INDEX', i)])
             for i in range(start, start+count)],
            flags={"from_hw": True})
        sequence_violations_resp = self.rdma_sequence_violation_counter.entry_get(
            self.target,
            [self.rdma_sequence_violation_counter.make_key([gc.KeyTuple('$COUNTER_INDEX', i)])
             for i in range(start, start+count)],
            flags={"from_hw": True})
        # else:
        #     r1 = self.rdma_message_counter.entry_get(
        #         self.target,
        #         flags={"from_hw": False})
        #     r2 = self.rdma_sequence_violation_counter.entry_get(
        #         self.target,
        #         flags={"from_hw": False})

        packets = {}
        messages = {}
        sequence_violations = {}
        
        for v, k in packets_resp:
            v = v.to_dict()
            k = k.to_dict()
            packets[k['$COUNTER_INDEX']['value']] = v['$COUNTER_SPEC_PKTS']

        for v, k in messages_resp:
            v = v.to_dict()
            k = k.to_dict()
            messages[k['$COUNTER_INDEX']['value']] = v['$COUNTER_SPEC_PKTS']

        for v, k in sequence_violations_resp:
            v = v.to_dict()
            k = k.to_dict()
            sequence_violations[k['$COUNTER_INDEX']['value']] = v['$COUNTER_SPEC_PKTS']

        print("Queue Pair Number Packets     Messages   Sequence Violations")
        for i in messages:
            print("{:>16} {:>10} {:>10} {:>20}".format(i, packets[i], messages[i], sequence_violations[i]))

            
    def clear_counters(self):
        self.logger.info("Clearing roce_receiver counters...")
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

        self.rdma_message_counter.entry_del(self.target)
        self.rdma_sequence_violation_counter.entry_del(self.target)
