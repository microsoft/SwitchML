# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import logging
import time
import sys
import os
from pprint import pprint

import random

from ptf import config
from ptf.thriftutils import *
from ptf.testutils import *

from bfruntime_client_base_tests import BfRuntimeTest
import bfrt_grpc.client as gc

# import SwitchML setup
from SwitchML.Job import Job
from SwitchML.Worker import Worker, WorkerType, PacketSize
from SwitchML.Packets import *

# import SwitchML test base class
from SwitchMLTest import *

import scapy
from scapy.layers.l2 import Ether

# init logging
logger = logging.getLogger('Test')
if not len(logger.handlers):
    logger.addHandler(logging.StreamHandler())

# log at info level
logging.basicConfig(level=logging.INFO)


class SingleWorkerSinglePacket(SwitchMLTest):
    """
    Recreate data corruption for bug report
    """

    def setUp(self):
        SwitchMLTest.setUp(self)
        
        # device ID: 0
        self.dev_id = 0

        # mac, ip, and udp port number that switch will respond to
        self.switch_mac           = "06:00:00:00:00:01"
        self.switch_ip            = "198.19.200.200"
        logger.info("Setting up job...")
        self.job = Job(gc, self.bfrt_info,
                       self.switch_ip, self.switch_mac)


        self.worker_rank = 0
        self.job_size = 1
        self.worker_mac = "b8:59:9f:c6:bc:ba"
        self.worker_ip = "198.19.200.50"
        self.worker_rkey = 0x110046
        self.worker_packet_size = PacketSize.IBV_MTU_1024
        self.worker_message_size = 1024
        self.worker_qpn = 0x5ec9
        self.worker_initial_psn = 0x2f63
        
        self.worker_front_panel_port = 1
        self.worker_front_panel_lane = 0
        self.worker_dev_port = self.job.ports.get_dev_port(self.worker_front_panel_port,
                                                           self.worker_front_panel_lane)
        self.job.port_add(self.worker_front_panel_port,
                          self.worker_front_panel_lane,
                          100,    # speed
                          'none') # fec
        self.job.mac_address_add(self.worker_mac,
                                 self.worker_front_panel_port,
                                 self.worker_front_panel_lane)

        #[1,0]<stdout>:Sending request <RDMAConnectRequest rank=0 size=1 mac=0xb8599fc6bcba ipv4=0xc613c832 rkey=0x110046 qpn=0x5ec9 psn=0x2f64>
        #worker_add_roce 0 1 b8:59:9f:c6:bc:ba 198.19.200.50 0x110046 256 256 0x5ec9 0x2f64

        self.job.worker_add_roce(self.worker_rank, self.job_size,
                                 self.worker_mac, self.worker_ip,
                                 self.worker_rkey,
                                 self.worker_packet_size, self.worker_message_size,
                                 [(self.worker_qpn, self.worker_initial_psn)])

    def runTest(self):
        packet_to_send = (Ether(dst=self.switch_mac, src=self.worker_mac) /
                          IP(dst=self.switch_ip, src=self.worker_ip, tos=2, flags="DF") /
                          UDP(dport=4791, sport=58543, chksum=0) /
                          IB_BTH(opcode=rdma_opcode_s2n['UC_RDMA_WRITE_ONLY_IMMEDIATE'],
                                 dst_qp=0x800000, psn=0) /
                          IB_RETH(addr=0x0000100000000000, rkey=0, len=1024) /
                          IB_IMM(imm=0x01020304) /
                          ##IB_Payload(data=[x << 24 + x << 16 + x << 8 + x for x in range(256)]) /
                          IB_Payload(data=[x for x in range(256)]) /
                          IB_ICRC(icrc=0x12345678))

        # compute checksums, etc.
        del packet_to_send.chksum
        packet_to_send = packet_to_send.__class__(bytes(packet_to_send))
        
        expected_packet = (Ether(dst=self.worker_mac, src=self.switch_mac) /
                           IP(dst=self.worker_ip, src=self.switch_ip, tos=2, flags="DF") /
                           UDP(dport=4791, sport=0x8000, chksum=0) / # sport is worker rank & 0x8000
                           IB_BTH(opcode=rdma_opcode_s2n['UC_RDMA_WRITE_ONLY_IMMEDIATE'],
                                  dst_qp=self.worker_qpn, psn=self.worker_initial_psn) /
                           IB_RETH(addr=0x0000100000000000, rkey=self.worker_rkey, len=1024) /
                           IB_IMM(imm=0x12345678) /
                           ##IB_Payload(data=[x << 24 + x << 16 + x << 8 + x for x in range(256)]) /
                           IB_Payload(data=[x for x in range(256)]) /
                           IB_ICRC(icrc=0x12345678))

        # compute checksums, etc.
        del expected_packet.chksum
        expected_packet = expected_packet.__class__(bytes(expected_packet))

        print("Sending packet:")
        #packet_to_send.show()
        send_packet(self, self.worker_dev_port, packet_to_send)

        print("Expecting packet:")
        #expected_packet.show()

        print("Waiting for response.")
        verify_packet(self, expected_packet, self.worker_dev_port)

        

            
        
class SingleWorkerSinglePacketRetransmit(SwitchMLTest):
    """
    Recreate data corruption for bug report
    """

    def setUp(self):
        SwitchMLTest.setUp(self)
        
        # device ID: 0
        self.dev_id = 0

        # mac, ip, and udp port number that switch will respond to
        self.switch_mac           = "06:00:00:00:00:01"
        self.switch_ip            = "198.19.200.200"
        logger.info("Setting up job...")
        self.job = Job(gc, self.bfrt_info,
                       self.switch_ip, self.switch_mac)


        self.worker_rank = 0
        self.job_size = 1
        self.worker_mac = "b8:59:9f:c6:bc:ba"
        self.worker_ip = "198.19.200.50"
        self.worker_rkey = 0x110046
        self.worker_packet_size = PacketSize.IBV_MTU_1024
        self.worker_message_size = 1024
        self.worker_qpn = 0x5ec9
        self.worker_initial_psn = 0x2f65
        
        self.worker_front_panel_port = 1
        self.worker_front_panel_lane = 0
        self.worker_dev_port = self.job.ports.get_dev_port(self.worker_front_panel_port,
                                                           self.worker_front_panel_lane)
        self.job.port_add(self.worker_front_panel_port,
                          self.worker_front_panel_lane,
                          100,    # speed
                          'none') # fec
        self.job.mac_address_add(self.worker_mac,
                                 self.worker_front_panel_port,
                                 self.worker_front_panel_lane)

        #[1,0]<stdout>:Sending request <RDMAConnectRequest rank=0 size=1 mac=0xb8599fc6bcba ipv4=0xc613c832 rkey=0x110046 qpn=0x5ec9 psn=0x2f64>
        #worker_add_roce 0 1 b8:59:9f:c6:bc:ba 198.19.200.50 0x110046 256 256 0x5ec9 0x2f64

        self.job.worker_add_roce(self.worker_rank, self.job_size,
                                 self.worker_mac, self.worker_ip,
                                 self.worker_rkey,
                                 self.worker_packet_size, self.worker_message_size,
                                 [(self.worker_qpn, self.worker_initial_psn)])

    def runTest(self):
        packet_to_send = (Ether(dst=self.switch_mac, src=self.worker_mac) /
                          IP(dst=self.switch_ip, src=self.worker_ip, tos=2, flags="DF") /
                          UDP(dport=4791, sport=58543, chksum=0) /
                          IB_BTH(opcode=rdma_opcode_s2n['UC_RDMA_WRITE_ONLY_IMMEDIATE'],
                                 dst_qp=0x800000, psn=0) /
                          IB_RETH(addr=0x0000100000000000, rkey=0, len=1024) /
                          IB_IMM(imm=0x01020304) /
                          IB_Payload(data=[x for x in range(256)]) /
                          IB_ICRC(icrc=0x12345678))

        # compute checksums, etc.
        del packet_to_send.chksum
        packet_to_send = packet_to_send.__class__(bytes(packet_to_send))
        
        expected_packet = (Ether(dst=self.worker_mac, src=self.switch_mac) /
                           IP(dst=self.worker_ip, src=self.switch_ip, tos=2, flags="DF") /
                           UDP(dport=4791, sport=0x8000, chksum=0) / # sport is worker rank & 0x8000
                           IB_BTH(opcode=rdma_opcode_s2n['UC_RDMA_WRITE_ONLY_IMMEDIATE'],
                                  dst_qp=self.worker_qpn, psn=self.worker_initial_psn ) /
                           IB_RETH(addr=0x0000100000000000, rkey=self.worker_rkey, len=1024) /
                           IB_IMM(imm=0x12345678) /
                           IB_Payload(data=[x for x in range(256)]) /
                           IB_ICRC(icrc=0x12345678))

        # compute checksums, etc.
        del expected_packet.chksum
        expected_packet = expected_packet.__class__(bytes(expected_packet))

        # retransmitted packet
        expected_packet2 = expected_packet.copy()
        expected_packet2[IB_BTH].psn += 1
        
        print("Sending packet:")
        #packet_to_send.show()
        send_packet(self, self.worker_dev_port, packet_to_send)

        print("Expecting packet:")
        #expected_packet.show()

        print("Waiting for response.")
        verify_packet(self, expected_packet, self.worker_dev_port)

        print("Sending packet again:")
        #packet_to_send.show()
        send_packet(self, self.worker_dev_port, packet_to_send)

        print("Expecting packet again:")
        #expected_packet.show()

        print("Waiting for response.")
        verify_packet(self, expected_packet2, self.worker_dev_port)

        

            
        
