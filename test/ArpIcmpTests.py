######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

"""
This is a test for SwitchML RDMA.
"""

import unittest
import logging 
import grpc   
import pdb

import ptf
from ptf.testutils import *
from bfruntime_client_base_tests import BfRuntimeTest
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc

import time
import sys
import os
from pprint import pprint, pformat

import random

from SwitchML.Packets import make_switchml_rdma, roce_opcode_s2n
from SwitchML.ARPandICMP import ARPandICMP
from SwitchML.Job import Job
from SwitchML.Worker import Worker

# init logging
logger = logging.getLogger('Test')
if not len(logger.handlers):
    logger.addHandler(logging.StreamHandler())

# log at info level
logging.basicConfig(level=logging.INFO)


class SwitchMLTest(BfRuntimeTest):

    def setUp(self):
        self.client_id = 0
        self.p4_name   = "switchml"
        self.dev       = 0
        self.dev_tgt   = gc.Target(self.dev, pipe_id=0xFFFF)
        
        BfRuntimeTest.setUp(self, self.client_id, self.p4_name)
        
        self.bfrt_info = self.interface.bfrt_info_get()
        self.target    = gc.Target(device_id=0, pipe_id=0xffff)

        self.job = None

    def tearDown(self):
        self.cleanUp()
        BfRuntimeTest.tearDown(self)

    def cleanUp(self):
        try:
            if self.job is not None:
                self.job.clear_all()
        except Exception as e:
            print("Error cleaning up: {}".format(e))


class ARPTest(SwitchMLTest):
    """
    SwitchML ARP tests
    """

    def setUp(self):
        SwitchMLTest.setUp(self)
        
        # device ID: 0
        self.dev_id = 0
        
        # mac, ip, and udp port number that switch will respond to
        self.switch_mac           = "06:00:00:00:00:01"
        self.switch_ip            = "198.19.200.200"
        self.roce_port            = 4791
        self.switch_qpn           = 12345
        self.switch_udp_port      = 0xbee0
        self.switch_udp_port_mask = 0xfff0
        self.switch_mgid          = 1234

        self.worker_mac           = "b8:59:9f:c6:bc:ba"
        self.worker_ip            = "198.19.200.50"
        self.worker_port          = 55555

        self.broadcast_mac        = "ff:ff:ff:ff:ff:ff"
        
        #self.arp_and_icmp = ARPandICMP(gc, self.bfrt_info, self.switch_mac, self.switch_ip)
        self.job = Job(gc, self.bfrt_info,
                       self.switch_ip, self.switch_mac, self.switch_udp_port, self.switch_udp_port_mask, 
                       [Worker(mac=self.worker_mac, ip=self.worker_ip, udp_port=12345, front_panel_port=1, lane=0, speed=10, fec='none'),
                        Worker(mac="b8:83:03:74:01:8c", ip="198.19.200.50", udp_port=23456, front_panel_port=1, lane=1, speed=10, fec='none')])


        


class ArpRequest(ARPTest):
    """
    Test basic operation of a single ARP request.
    """

    def runTest(self):
        pkt = (Ether(src=self.worker_mac, dst=self.broadcast_mac) /
               ARP(op="who-has", hwsrc=self.worker_mac, pdst=self.switch_ip))

        expected = (Ether(src=self.switch_mac, dst=self.worker_mac) /
                    ARP(op="is-at",
                        hwsrc=self.switch_mac, hwdst=self.worker_mac,
                        psrc=self.switch_ip, pdst=self.worker_ip))

        send_packet(self, 0, pkt)
        verify_packet(self, expected, 0)

class OtherArpRequest(ARPTest):
    """
    Ensure an ARP for something other than the switch gets broadcast out the non-requesting port.
    """

    def runTest(self):
        pkt = (Ether(src=self.worker_mac, dst=self.broadcast_mac) /
               ARP(op="who-has", hwsrc=self.worker_mac, pdst="198.19.200.201"))

        expected = (Ether(src=self.worker_mac, dst=self.broadcast_mac) /
                    ARP(op="who-has", hwsrc=self.worker_mac, pdst="198.19.200.201"))

        send_packet(self, 0, pkt)
        verify_packet(self, expected, 1)
        verify_no_other_packets(self)

class PingRequest(ARPTest):
    """
    Test basic operation of a single ARP request.
    """

    def runTest(self):
        pkt = (Ether(src=self.worker_mac, dst=self.switch_mac) /
               IP(src=self.worker_ip, dst=self.switch_ip) /
               ICMP(type="echo-request"))

        expected = (Ether(src=self.switch_mac, dst=self.worker_mac) /
                    IP(src=self.switch_ip, dst=self.worker_ip) /
                    ICMP(type="echo-reply", chksum=0))

        send_packet(self, 0, pkt)
        verify_packet(self, expected, 0)
        
class OtherPingRequest(ARPTest):
    """
    Test basic operation of a single ARP request.
    """

    def runTest(self):
        pkt = (Ether(src=self.worker_mac, dst=self.switch_mac) /
               IP(src=self.worker_ip, dst="198.19.200.201") /
               ICMP(type="echo-request"))

        send_packet(self, 0, pkt)
        verify_no_other_packets(self)
        
