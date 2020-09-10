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
from SwitchML.Worker import Worker
from SwitchML.Packets import make_switchml_udp, make_switchml_rdma

# import SwitchML test base class
from SwitchMLTest import *

# init logging
logger = logging.getLogger('Test')
if not len(logger.handlers):
    logger.addHandler(logging.StreamHandler())

# log at info level
logging.basicConfig(level=logging.INFO)


class RDMAThreeWorkerTest(SwitchMLTest):
    """
    Base class for 3-worker SwitchML tests using RDMA
    """

    def setUp(self):
        SwitchMLTest.setUp(self)
        
        # device ID: 0
        self.dev_id = 0

        # mac, ip, and udp port number that switch will respond to
        self.switch_mac           = "06:00:00:00:00:01"
        self.switch_ip            = "198.19.200.200"
        self.switch_udp_port      = 0xbee0
        self.switch_udp_port_mask = 0xfff0
        self.switch_mgid          = 1234

        self.workers = [Worker(mac="b8:83:03:73:a6:a0", ip="198.19.200.49", roce_base_qpn=0, front_panel_port=1, lane=0, speed=10, fec='none'),
                        Worker(mac="b8:83:03:74:01:8c", ip="198.19.200.50", roce_base_qpn=0, front_panel_port=1, lane=1, speed=10, fec='none'),
                        Worker(mac="b8:83:03:74:02:9a", ip="198.19.200.48", roce_base_qpn=0, front_panel_port=1, lane=2, speed=10, fec='none')]
        
        self.job = Job(gc, self.bfrt_info,
                       self.switch_ip, self.switch_mac, self.switch_udp_port, self.switch_udp_port_mask, self.workers)

        # make packets for set 0
        ((self.pktW0S0, self.expected_pktW0S0),
         (self.pktW1S0, self.expected_pktW1S0),
         (self.pktW2S0, self.expected_pktW2S0)) = self.make_switchml_packets(self.workers, 0x0000, 1, self.switch_udp_port)

        # make packets for set 1
        ((self.pktW0S1, self.expected_pktW0S1),
         (self.pktW1S1, self.expected_pktW1S1),
         (self.pktW2S1, self.expected_pktW2S1)) = self.make_switchml_packets(self.workers, 0x8000, 1, self.switch_udp_port)
        
        # make additional packets with different values to verify slot reuse
        ((self.pktW0S0x3, self.expected_pktW0S0x3),
         (self.pktW1S0x3, self.expected_pktW1S0x3),
         (self.pktW2S0x3, self.expected_pktW2S0x3)) = self.make_switchml_packets(self.workers, 0x0000, 3, self.switch_udp_port)
        ((self.pktW0S1x3, self.expected_pktW0S1x3),
         (self.pktW1S1x3, self.expected_pktW1S1x3),
         (self.pktW2S1x3, self.expected_pktW2S1x3)) = self.make_switchml_packets(self.workers, 0x8000, 3, self.switch_udp_port)


 
class BasicReduction(RDMAThreeWorkerTest):
    """
    Test basic operation of a single slot.
    """

    def runTest(self):
        # do a straightforward reduction in the first set of the first slot.
        send_packet(self, 0, self.pktW0S0)
        send_packet(self, 1, self.pktW1S0)
        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

class RetransmitAfterReduction(RDMAThreeWorkerTest):
    """
    Ensure we can retransmit from a set after it has received all
    updates and before its paired set has received its first update.

    """

    def runTest(self):
        # firstdo a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0)
        verify_no_other_packets(self)

        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

        # try retransmission from second worker
        send_packet(self, 1, self.pktW1S0)
        self.expected_pktW1S0['IB_BTH'].psn = 1
        verify_packet(self, self.expected_pktW1S0, 1)

        # try retransmission from second worker again
        send_packet(self, 1, self.pktW1S0)
        self.expected_pktW1S0['IB_BTH'].psn = 2
        verify_packet(self, self.expected_pktW1S0, 1)

        # try retransmission from second worker one more time
        send_packet(self, 1, self.pktW1S0)
        self.expected_pktW1S0['IB_BTH'].psn = 3        
        verify_packet(self, self.expected_pktW1S0, 1)

        # try retransmission from first worker
        send_packet(self, 0, self.pktW0S0)
        self.expected_pktW0S0['IB_BTH'].psn = 1
        verify_packet(self, self.expected_pktW0S0, 0)

        # try retransmission from first worker again
        send_packet(self, 0, self.pktW0S0)
        self.expected_pktW0S0['IB_BTH'].psn = 2
        verify_packet(self, self.expected_pktW0S0, 0)

        # try retransmission from third worker
        send_packet(self, 0, self.pktW2S0)
        self.expected_pktW2S0['IB_BTH'].psn = 1
        verify_packet(self, self.expected_pktW2S0, 0)

class OtherSetReduction(RDMAThreeWorkerTest):
    """
    Test basic operation of a single slot, starting from the second
    set instead of the first.
    """

    def runTest(self):
        # do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1)
        verify_no_other_packets(self)
        
        send_packet(self, 2, self.pktW2S1)

        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        verify_packet(self, self.expected_pktW2S1, 2)

class BothSetsReduction(RDMAThreeWorkerTest):
    """
    Test basic operation of a pair of sets.
    """

    def runTest(self):
        # do a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0)
        verify_no_other_packets(self)

        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

        # now do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1x3)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1x3)
        verify_no_other_packets(self)

        send_packet(self, 2, self.pktW2S1x3)

        self.expected_pktW0S1x3['IB_BTH'].psn = 1
        self.expected_pktW1S1x3['IB_BTH'].psn = 1
        self.expected_pktW2S1x3['IB_BTH'].psn = 1

        verify_packet(self, self.expected_pktW0S1x3, 0)
        verify_packet(self, self.expected_pktW1S1x3, 1)
        verify_packet(self, self.expected_pktW2S1x3, 2)
                

class SlotReuse(RDMAThreeWorkerTest):
    """
    Test basic slot reuse.
    """

    def runTest(self):
        # do a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0)
        verify_no_other_packets(self)

        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

        # now do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1)
        verify_no_other_packets(self)

        send_packet(self, 2, self.pktW2S1)

        self.expected_pktW0S1['IB_BTH'].psn = 1
        self.expected_pktW1S1['IB_BTH'].psn = 1
        self.expected_pktW2S1['IB_BTH'].psn = 1

        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        verify_packet(self, self.expected_pktW2S1, 2)
                
        # now reduce in first set again
        send_packet(self, 0, self.pktW0S0x3)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0x3)
        verify_no_other_packets(self)

        send_packet(self, 2, self.pktW2S0x3)

        self.expected_pktW0S0x3['IB_BTH'].psn = 2
        self.expected_pktW1S0x3['IB_BTH'].psn = 2
        self.expected_pktW2S0x3['IB_BTH'].psn = 2
        
        verify_packet(self, self.expected_pktW0S0x3, 0)
        verify_packet(self, self.expected_pktW1S0x3, 1)
        verify_packet(self, self.expected_pktW2S0x3, 2)

        # now reduce in second set again
        send_packet(self, 0, self.pktW0S1x3)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1x3)
        verify_no_other_packets(self)

        send_packet(self, 2, self.pktW2S1x3)

        self.expected_pktW0S1x3['IB_BTH'].psn = 3
        self.expected_pktW1S1x3['IB_BTH'].psn = 3
        self.expected_pktW2S1x3['IB_BTH'].psn = 3

        verify_packet(self, self.expected_pktW0S1x3, 0)
        verify_packet(self, self.expected_pktW1S1x3, 1)
        verify_packet(self, self.expected_pktW2S1x3, 2)

class IgnoreRetransmissions(RDMAThreeWorkerTest):
    """
    Ensure that retransmissions during reduction are ignored.
    """

    def runTest(self):
        # half-complete reduction in set 1
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        # make sure retransmissions to that set from the same worker are ignored
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        # now finish aggregation
        send_packet(self, 1, self.pktW1S1)
        verify_no_other_packets(self)

        send_packet(self, 2, self.pktW2S1)

        # ensure that we still get the correct answer
        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        verify_packet(self, self.expected_pktW2S1, 2)
        
class RetransmitFromPreviousSet(RDMAThreeWorkerTest):
    """
    Ensure that retransmissions to a previously-aggregated set generate replies.
    """

    def runTest(self):
        # do a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)
        
        send_packet(self, 1, self.pktW1S0)
        verify_no_other_packets(self)
        
        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

        # now do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)
        
        send_packet(self, 1, self.pktW1S1)
        verify_no_other_packets(self)
        
        send_packet(self, 2, self.pktW2S1)

        self.expected_pktW0S1['IB_BTH'].psn = 1
        self.expected_pktW1S1['IB_BTH'].psn = 1
        self.expected_pktW2S1['IB_BTH'].psn = 1

        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        verify_packet(self, self.expected_pktW2S1, 2)
                
        # now reduce in first set again
        send_packet(self, 0, self.pktW0S0x3)
        verify_no_other_packets(self)
        
        send_packet(self, 1, self.pktW1S0x3)
        verify_no_other_packets(self)

        send_packet(self, 2, self.pktW2S0x3)

        self.expected_pktW0S0x3['IB_BTH'].psn = 2
        self.expected_pktW1S0x3['IB_BTH'].psn = 2
        self.expected_pktW2S0x3['IB_BTH'].psn = 2

        verify_packet(self, self.expected_pktW0S0x3, 0)
        verify_packet(self, self.expected_pktW1S0x3, 1)
        verify_packet(self, self.expected_pktW2S0x3, 2)

        # now half-complete reduction in second set again
        send_packet(self, 1, self.pktW1S1x3)
        verify_no_other_packets(self)

        # and verify we can retransmit from first set
        send_packet(self, 0, self.pktW0S0x3)
        self.expected_pktW0S0x3['IB_BTH'].psn = 3
        verify_packet(self, self.expected_pktW0S0x3, 0)

        send_packet(self, 2, self.pktW2S0x3)
        self.expected_pktW2S0x3['IB_BTH'].psn = 3
        verify_packet(self, self.expected_pktW2S0x3, 2)
