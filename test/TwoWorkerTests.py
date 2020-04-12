######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

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

from scapy.all import *

# import SwitchML setup
from SwitchML.Job import Job
from SwitchML.Worker import Worker, WorkerType
from SwitchML.Packets import make_switchml_udp

# import SwitchML test base class
from SwitchMLTest import *

# init logging
logger = logging.getLogger('Test')
if not len(logger.handlers):
    logger.addHandler(logging.StreamHandler())

# log at info level
logging.basicConfig(level=logging.INFO)


class TwoWorkerTest(SwitchMLTest):
    """
    Base class for 2-worker SwitchML tests
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

        self.all_workers = [
            # Two UDP workers
            Worker(mac="b8:83:03:73:a6:a0", ip="198.19.200.49", udp_port=12345, front_panel_port=1, lane=0, speed=10, fec='none'),
            Worker(mac="b8:83:03:74:01:8c", ip="198.19.200.50", udp_port=12345, front_panel_port=1, lane=1, speed=10, fec='none'),
            # A non-SwitchML worker
            Worker(mac="b8:83:03:74:01:c4", ip="198.19.200.48", front_panel_port=1, lane=2, speed=10, fec='none'),
        ]
        self.switchml_workers = [w for w in self.all_workers if w.worker_type is not WorkerType.FORWARD_ONLY]
                                                                             
        self.job = Job(gc, self.bfrt_info,
                       self.switch_ip, self.switch_mac, self.switch_udp_port, self.switch_udp_port_mask, 
                       self.all_workers)

        # make packets for set 0
        ((self.pktW0S0, self.expected_pktW0S0),
         (self.pktW1S0, self.expected_pktW1S0)) = self.make_switchml_packets(self.switchml_workers,
                                                                             0x0000, 1, self.switch_udp_port)

        # make packets for set 1
        ((self.pktW0S1, self.expected_pktW0S1),
         (self.pktW1S1, self.expected_pktW1S1)) = self.make_switchml_packets(self.switchml_workers,
                                                                             0x8000, 1, self.switch_udp_port)
        
        # make additional packets with different values to verify slot reuse
        ((self.pktW0S0x3, self.expected_pktW0S0x3),
         (self.pktW1S0x3, self.expected_pktW1S0x3)) = self.make_switchml_packets(self.switchml_workers,
                                                                                 0x0000, 3, self.switch_udp_port)
        ((self.pktW0S1x3, self.expected_pktW0S1x3),
         (self.pktW1S1x3, self.expected_pktW1S1x3)) = self.make_switchml_packets(self.switchml_workers,
                                                                                 0x8000, 3, self.switch_udp_port)

        # make packets for the next slot with different ports
        ((self.pktW0S0p1, self.expected_pktW0S0p1),
         (self.pktW1S0p1, self.expected_pktW1S0p1)) = self.make_switchml_packets(self.switchml_workers,
                                                                                 0x0001, 1, self.switch_udp_port+1)
        ((self.pktW0S1p1, self.expected_pktW0S1p1),
         (self.pktW1S1p1, self.expected_pktW1S1p1)) = self.make_switchml_packets(self.switchml_workers,
                                                                                 0x8001, 1, self.switch_udp_port+1)
        self.pktW0S0p1['UDP'].sport          = self.pktW0S0p1['UDP'].sport + 1
        self.pktW1S0p1['UDP'].sport          = self.pktW1S0p1['UDP'].sport + 1
        self.pktW0S1p1['UDP'].sport          = self.pktW0S1p1['UDP'].sport + 1
        self.pktW1S1p1['UDP'].sport          = self.pktW1S1p1['UDP'].sport + 1
        self.expected_pktW0S0p1['UDP'].dport = self.expected_pktW0S0p1['UDP'].dport + 1
        self.expected_pktW1S0p1['UDP'].dport = self.expected_pktW1S0p1['UDP'].dport + 1
        self.expected_pktW0S1p1['UDP'].dport = self.expected_pktW0S1p1['UDP'].dport + 1
        self.expected_pktW1S1p1['UDP'].dport = self.expected_pktW1S1p1['UDP'].dport + 1
 
class BasicReduction(TwoWorkerTest):
    """
    Test basic operation of a single slot.
    """

    def runTest(self):
        # do a straightforward reduction in the first slot
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)

class RetransmitAfterReduction(TwoWorkerTest):
    """
    Ensure we can retransmit from a slot after it has received all
    updates and before its paired slot has received its first update.

    """

    def runTest(self):
        # first do a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)

        # try retransmission from second worker
        send_packet(self, 1, self.pktW1S0)
        verify_packet(self, self.expected_pktW1S0, 1)

        # try retransmission from second worker again
        send_packet(self, 1, self.pktW1S0)
        verify_packet(self, self.expected_pktW1S0, 1)

        # try retransmission from second worker one more time
        send_packet(self, 1, self.pktW1S0)
        verify_packet(self, self.expected_pktW1S0, 1)

        # try retransmission from first worker
        send_packet(self, 0, self.pktW0S0)
        verify_packet(self, self.expected_pktW0S0, 0)

        # try retransmission from first worker again
        send_packet(self, 0, self.pktW0S0)
        verify_packet(self, self.expected_pktW0S0, 0)

class OtherSetReduction(TwoWorkerTest):
    """
    Test basic operation of a single slot, starting from the second
    set instead of the first.
    """

    def runTest(self):
        # do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1)

        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)

class BothSetsReduction(TwoWorkerTest):
    """
    Test basic operation of a pair of sets in a slot.
    """

    def runTest(self):
        # do a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)

        # now do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1x3)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1x3)

        verify_packet(self, self.expected_pktW0S1x3, 0)
        verify_packet(self, self.expected_pktW1S1x3, 1)
        

class SlotReuse(TwoWorkerTest):
    """
    Test basic slot reuse.
    """

    def runTest(self):
        # do a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)

        # now do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1)

        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        
        # now reduce in first set again
        send_packet(self, 0, self.pktW0S0x3)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0x3)

        verify_packet(self, self.expected_pktW0S0x3, 0)
        verify_packet(self, self.expected_pktW1S0x3, 1)

        # now reduce in second set again
        send_packet(self, 0, self.pktW0S1x3)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1x3)

        verify_packet(self, self.expected_pktW0S1x3, 0)
        verify_packet(self, self.expected_pktW1S1x3, 1)

class IgnoreRetransmissions(TwoWorkerTest):
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

        # ensure that we still get the correct answer
        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        
class RetransmitFromPreviousSet(TwoWorkerTest):
    """
    Ensure that retransmissions to a previously-aggregated set generate replies.
    """

    def runTest(self):
        # start by doing a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1)

        # check the answer
        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)

        # now, half-complete reduction in the first set
        send_packet(self, 1, self.pktW1S0x3)
        
        # verify we can still retransmit from the second set
        send_packet(self, 0, self.pktW0S1)
        verify_packet(self, self.expected_pktW0S1, 0)

        # try again
        send_packet(self, 0, self.pktW0S1)
        verify_packet(self, self.expected_pktW0S1, 0)

        # try again one more time
        send_packet(self, 0, self.pktW0S1)
        verify_packet(self, self.expected_pktW0S1, 0)

        # ensure we get no other packets.
        verify_no_other_packets(self)

        
class SlotReuseAndRetransmit(TwoWorkerTest):
    """
    Test basic slot reuse.
    """

    def runTest(self):
        # do a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)

        # now do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S1)

        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        
        # now reduce in first set again
        send_packet(self, 0, self.pktW0S0x3)
        verify_no_other_packets(self)
        
        send_packet(self, 1, self.pktW1S0x3)

        verify_packet(self, self.expected_pktW0S0x3, 0)
        verify_packet(self, self.expected_pktW1S0x3, 1)

        # now half-complete reduction in second set again
        send_packet(self, 1, self.pktW1S1x3)
        verify_no_other_packets(self)

        # and verify we can retransmit from first set
        send_packet(self, 0, self.pktW0S0x3)
        verify_packet(self, self.expected_pktW0S0x3, 0)


class NonSwitchML(TwoWorkerTest):
    """
    Test forwarding non-SwitchML traffic
    """

    def runTest(self):
        p = (Ether(dst=self.all_workers[1].mac, src=self.all_workers[0].mac) /
             IP(dst=self.all_workers[1].ip, src=self.all_workers[0].ip) /
             "012345678901234567890123456789")

        send_packet(self, 0, p)
        verify_packet(self, p, 1)

        send_packet(self, 1, p)
        verify_packet(self, p, 1)

        send_packet(self, 2, p)
        verify_packet(self, p, 1)

        q = (Ether(dst=self.all_workers[2].mac, src=self.all_workers[0].mac) /
             IP(dst=self.all_workers[2].ip, src=self.all_workers[0].ip) /
             "012345678901234567890123456789")

        send_packet(self, 0, q)
        verify_packet(self, q, 2)

        send_packet(self, 1, q)
        verify_packet(self, q, 2)

        send_packet(self, 2, q)
        verify_packet(self, q, 2)

class DifferentPortsReduction(TwoWorkerTest):
    """
    Test reductions leveraging port masks in the switch to do core steering.
    """

    def runTest(self):
        # do a straightforward reduction in the first set of slot 0
        send_packet(self, 0, self.pktW0S0)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)

        # do a straightforward reduction in the first set of slot 1 with different ports
        send_packet(self, 0, self.pktW0S0p1)
        verify_no_other_packets(self)

        send_packet(self, 1, self.pktW1S0p1)

        verify_packet(self, self.expected_pktW0S0p1, 0)
        verify_packet(self, self.expected_pktW1S0p1, 1)
        
        self.pktW0S0p1.show()
        self.pktW1S0p1.show()
        self.expected_pktW0S0p1.show()
        self.expected_pktW1S0p1.show()
        
