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
from Packets import roce_opcode_s2n

class RoCESender(Table):

    def __init__(self, client, bfrt_info,
                 switch_mac, switch_ip,
                 message_length, # must be a power of 2
                 use_rdma_write = True, 
                 use_immediate  = True):
        # set up base class
        super(RoCESender, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('RoCESender')
        self.logger.info("Setting up RoCE sender...")
        
        self.switch_mac = switch_mac
        self.switch_ip = switch_ip
        self.message_length = message_length      # must be a power of 2
        self.first_last_mask = message_length - 1 # for this to work

        self.use_rdma_write = use_rdma_write
        self.use_immediate = use_immediate
        
        # compute correct opcodes and actions
        if self.use_rdma_write:
            self.first_opcode  = roce_opcode_s2n['UC_RDMA_WRITE_FIRST']
            self.first_action  = 'SwitchMLEgress.roce_sender.set_rdma_opcode'            
            self.middle_opcode = roce_opcode_s2n['UC_RDMA_WRITE_MIDDLE']
            self.middle_action = 'SwitchMLEgress.roce_sender.set_opcode'
            if self.use_immediate: 
                self.last_opcode = roce_opcode_s2n['UC_RDMA_WRITE_LAST_IMMEDIATE']
                self.last_action = 'SwitchMLEgress.roce_sender.set_immediate_opcode'            
                self.only_opcode = roce_opcode_s2n['UC_RDMA_WRITE_ONLY_IMMEDIATE']
                self.only_action = 'SwitchMLEgress.roce_sender.set_rdma_immediate_opcode'
            else:
                self.last_opcode   = roce_opcode_s2n['UC_RDMA_WRITE_LAST']
                self.last_action = 'SwitchMLEgress.roce_sender.set_opcode'
                self.only_opcode   = roce_opcode_s2n['UC_RDMA_WRITE_ONLY']
                self.only_action = 'SwitchMLEgress.roce_sender.set_rdma_opcode'
        else:
            self.first_opcode  = roce_opcode_s2n['UC_SEND_FIRST']
            self.first_action  = 'SwitchMLEgress.roce_sender.set_opcode'
            self.middle_opcode = roce_opcode_s2n['UC_SEND_MIDDLE']
            self.middle_action = 'SwitchMLEgress.roce_sender.set_opcode'
            if self.use_immediate: 
                self.last_opcode = roce_opcode_s2n['UC_SEND_LAST_IMMEDIATE']
                self.last_action = 'SwitchMLEgress.roce_sender.set_immediate_opcode'            
                self.only_opcode = roce_opcode_s2n['UC_SEND_ONLY_IMMEDIATE']
                self.only_action = 'SwitchMLEgress.roce_sender.set_immediate_opcode'            
            else:
                self.last_opcode = roce_opcode_s2n['UC_SEND_LAST']
                self.last_action = 'SwitchMLEgress.roce_sender.set_opcode'            
                self.only_opcode = roce_opcode_s2n['UC_SEND_ONLY']
                self.only_action = 'SwitchMLEgress.roce_sender.set_opcode'            

        # get tables
        self.switch_mac_and_ip   = self.bfrt_info.table_get("pipe.SwitchMLEgress.roce_sender.switch_mac_and_ip")
        self.create_roce_packet  = self.bfrt_info.table_get("pipe.SwitchMLEgress.roce_sender.create_roce_packet")
        self.fill_in_qpn_and_psn = self.bfrt_info.table_get("pipe.SwitchMLEgress.roce_sender.fill_in_qpn_and_psn")
        self.set_opcodes         = self.bfrt_info.table_get("pipe.SwitchMLEgress.roce_sender.set_opcodes")

        # add annotations
        self.switch_mac_and_ip.info.data_field_annotation_add("switch_mac", 'SwitchMLEgress.roce_sender.set_switch_mac_and_ip', "mac")
        self.switch_mac_and_ip.info.data_field_annotation_add("switch_ip",  'SwitchMLEgress.roce_sender.set_switch_mac_and_ip', "ipv4")
        self.create_roce_packet.info.data_field_annotation_add("dest_mac", 'SwitchMLEgress.roce_sender.fill_in_roce_fields', "mac")
        self.create_roce_packet.info.data_field_annotation_add("dest_ip",  'SwitchMLEgress.roce_sender.fill_in_roce_fields', "ipv4")
        self.create_roce_packet.info.data_field_annotation_add("dest_mac", 'SwitchMLEgress.roce_sender.fill_in_roce_write_fields', "mac")
        self.create_roce_packet.info.data_field_annotation_add("dest_ip",  'SwitchMLEgress.roce_sender.fill_in_roce_write_fields', "ipv4")

        # clear and add defaults
        self.clear()
        self.add_default_entries()

    def clear(self):
        self.switch_mac_and_ip.entry_del(self.target);
        self.switch_mac_and_ip.default_entry_reset(self.target);
        
        self.create_roce_packet.entry_del(self.target);
        self.create_roce_packet.default_entry_reset(self.target);

        self.fill_in_qpn_and_psn.entry_del(self.target);
        self.fill_in_qpn_and_psn.default_entry_reset(self.target);

        self.set_opcodes.entry_del(self.target);
        self.set_opcodes.default_entry_reset(self.target);

        
    def clear_workers(self):
        self.create_roce_packet.entry_del(self.target);
        self.create_roce_packet.default_entry_reset(self.target);

        self.fill_in_qpn_and_psn.entry_del(self.target);
        self.fill_in_qpn_and_psn.default_entry_reset(self.target);

        
    def add_default_entries(self):

        # set switch MAC/IP and message size and mask
        self.switch_mac_and_ip.default_entry_set(
            self.target,
            self.switch_mac_and_ip.make_data([gc.DataTuple('switch_mac', self.switch_mac),
                                              gc.DataTuple('switch_ip', self.switch_ip),
                                              #gc.DataTuple('base_opcode', self.base_opcode), 
                                              gc.DataTuple('message_length', self.message_length),
                                              gc.DataTuple('first_last_mask', self.first_last_mask)],
                                             'SwitchMLEgress.roce_sender.set_switch_mac_and_ip'))

        #
        # set opcode breakpoints based on message size
        #

        if self.message_length <= 256:
            # all messages are _ONLY messages
            self.set_opcodes.default_entry_set(
                self.target,
                self.set_opcodes.make_data([gc.DataTuple('opcode', self.only_opcode)],
                                           self.only_action))
        else:
            # divide messages into first, middle, and last by comparing with first_last_mask

            # if masked value is zero, it's a _FIRST packet
            self.set_opcodes.entry_add(
                self.target,
                [self.set_opcodes.make_key([gc.KeyTuple('eg_md.switchml_md.pool_index', 0x00000, self.first_last_mask)])],
                [self.set_opcodes.make_data([gc.DataTuple('opcode', self.first_opcode)],
                                            self.first_action)])

            # if masked value is equal to the mask, it's a _LAST packet
            self.set_opcodes.entry_add(
                self.target,
                [self.set_opcodes.make_key([gc.KeyTuple('eg_md.switchml_md.pool_index', 0x1ffff, self.first_last_mask)])],
                [self.set_opcodes.make_data([gc.DataTuple('opcode', self.last_opcode)],
                                            self.last_action)])

            # default is _MIDDLE
            self.set_opcodes.entry_add(
                self.target,
                [self.set_opcodes.make_data([gc.DataTuple('opcode', self.middle_opcode)],
                                            self.middle_action)])


    # simple version first, with one QP per worker
    def add_send_worker(self, rid, mac, ip, qpn, initial_psn, rkey=None):
        # first, add entry to fill in headers for RoCE packet
        self.create_roce_packet.entry_add(
        self.target,
            [self.create_roce_packet.make_key([gc.KeyTuple('eg_md.switchml_md.worker_id', rid)])],
            [self.create_roce_packet.make_data([gc.DataTuple('dest_mac', mac),
                                                gc.DataTuple('dest_ip', ip)],
                                               'SwitchMLEgress.roce_sender.fill_in_roce_fields')])

        # now, add entry to add QPN and PSN to packet
        self.fill_in_qpn_and_psn.entry_add(
            self.target,
            [self.fill_in_qpn_and_psn.make_key([gc.KeyTuple('eg_md.switchml_md.worker_id', rid),
                                                gc.KeyTuple('eg_md.switchml_md.pool_index', 0x00000, 0x00000)])],
            [self.fill_in_qpn_and_psn.make_data([gc.DataTuple('qpn', qpn),
                                                 gc.DataTuple('SwitchMLEgress.roce_sender.psn_register.f1', initial_psn)],
                                                'SwitchMLEgress.roce_sender.add_qpn_and_psn')])


    # RDMA write capable version
    # qpns_and_psns is a list of qpn, psn tuples
    def add_write_worker(self, rid, mac, ip, rkey, qpns_and_psns):
        # first, add entry to fill in headers for RoCE packet
        self.create_roce_packet.entry_add(
        self.target,
            [self.create_roce_packet.make_key([gc.KeyTuple('eg_md.switchml_md.worker_id', rid)])],
            [self.create_roce_packet.make_data([gc.DataTuple('dest_mac', mac),
                                                gc.DataTuple('dest_ip', ip),
                                                gc.DataTuple('base_addr', 0), # TODO: shouldn't need this when using 0-based addressing
                                                gc.DataTuple('rkey', rkey)],                                                
                                               'SwitchMLEgress.roce_sender.fill_in_roce_write_fields')])

        # now, add entry to add QPN and PSN to packet
        # each QPN handles both sets of a slot in the pool
        for index, (qpn, initial_psn) in enumerate(qpns_and_psns):
            print("Adding qpn {} and psn {} for index {}".format(qpn, initial_psn, index))
            self.fill_in_qpn_and_psn.entry_add(
                self.target,
                [self.fill_in_qpn_and_psn.make_key([gc.KeyTuple('eg_md.switchml_md.worker_id', rid),
                                                    gc.KeyTuple('eg_md.switchml_md.pool_index',
                                                                index << 1,
                                                                0x7ffe)])], # handle both sets of slot
                [self.fill_in_qpn_and_psn.make_data([gc.DataTuple('qpn', qpn),
                                                     gc.DataTuple('SwitchMLEgress.roce_sender.psn_register.f1', initial_psn)],
                                                    'SwitchMLEgress.roce_sender.add_qpn_and_psn')])










    def print_counters(self):
        self.create_roce_packet.operations_execute(self.target, 'SyncCounters')
        resp = self.create_roce_packet.entry_get(
            self.target,
            flags={"from_hw": False})

        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()
                
            #print("key {}: value {}".format(pformat(k), pformat(v)))

            worker_id = k['eg_md.switchml_md.worker_id']['value']
            worker_ip = v['dest_ip']
            worker_packets = v['$COUNTER_SPEC_PKTS']
            worker_bytes = v['$COUNTER_SPEC_BYTES']

            print("Sent to worker       {:2} at {:15}: {:10} packets, {:10} bytes".format(worker_id, worker_ip, worker_packets, worker_bytes))


    def clear_counters(self):
        self.logger.info("Clearing roce_sender counters...")
        self.create_roce_packet.operations_execute(self.target, 'SyncCounters')
        resp = self.create_roce_packet.entry_get(
            self.target,
            flags={"from_hw": False})

        keys = []
        values = []
        
        for v, k in resp:
            keys.append(k)

            v = v.to_dict()
            k = k.to_dict()

            values.append(
                self.create_roce_packet.make_data(
                    [gc.DataTuple('$COUNTER_SPEC_BYTES', 0),
                     gc.DataTuple('$COUNTER_SPEC_PKTS', 0)],
                    v['action_name']))

        self.create_roce_packet.entry_mod(
            self.target,
            keys,
            values)
        
