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

# import SwitchML setup
from SwitchML.Job import Job
from SwitchML.Worker import Worker
from SwitchML.Packets import make_switchml_udp

# import SwitchML test base class
from SwitchMLTest import *

# init logging
logger = logging.getLogger('Test')
if not len(logger.handlers):
    logger.addHandler(logging.StreamHandler())

# log at info level
logging.basicConfig(level=logging.INFO)


class ThreeWorkerTest(SwitchMLTest):
    """
    Base class for 3-worker SwitchML tests
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

        self.job = Job(gc, self.bfrt_info,
                       self.switch_ip, self.switch_mac, self.switch_udp_port, self.switch_udp_port_mask, self.switch_mgid,
                       [Worker(mac="b8:83:03:73:a6:a0", ip="198.19.200.49", udp_port=12345, front_panel_port=1, lane=0, speed=10, fec='none'),
                        Worker(mac="b8:83:03:74:01:8c", ip="198.19.200.50", udp_port=23456, front_panel_port=1, lane=1, speed=10, fec='none'),
                        Worker(mac="b8:83:03:74:02:9a", ip="198.19.200.48", udp_port=34567, front_panel_port=1, lane=2, speed=10, fec='none')])

        # make packets for set 0
        self.pktW0S0 = make_switchml_udp(src_mac="b8:83:03:73:a6:a0",
                                         src_ip="198.19.200.49",
                                         dst_mac="06:00:00:00:00:01",
                                         dst_ip="198.19.200.200",
                                         src_port=12345,
                                         dst_port=0xbee0,
                                         pool_index=0)
        self.pktW1S0 = make_switchml_udp(src_mac="b8:83:03:74:01:8c",
                                         src_ip="198.19.200.50",
                                         dst_mac="06:00:00:00:00:01",
                                         dst_ip="198.19.200.200",
                                         src_port=23456,
                                         dst_port=0xbee0,
                                         pool_index=0)
        self.pktW2S0 = make_switchml_udp(src_mac="b8:83:03:74:02:9a",
                                         src_ip="198.19.200.48",
                                         dst_mac="06:00:00:00:00:01",
                                         dst_ip="198.19.200.200",
                                         src_port=34567,
                                         dst_port=0xbee0,
                                         pool_index=0)
        self.expected_pktW0S0 = make_switchml_udp(src_mac="06:00:00:00:00:01",
                                                  src_ip="198.19.200.200",
                                                  dst_mac="b8:83:03:73:a6:a0",
                                                  dst_ip="198.19.200.49",
                                                  src_port=0xbee0,
                                                  dst_port=12345,
                                                  pool_index=0,
                                                  value_multiplier=3,
                                                  checksum=0)
        self.expected_pktW1S0 = make_switchml_udp(src_mac="06:00:00:00:00:01",
                                                  src_ip="198.19.200.200",
                                                  dst_mac="b8:83:03:74:01:8c",
                                                  dst_ip="198.19.200.50",
                                                  src_port=0xbee0,
                                                  dst_port=23456,
                                                  pool_index=0,
                                                  value_multiplier=3,
                                                  checksum=0)
        self.expected_pktW2S0 = make_switchml_udp(src_mac="06:00:00:00:00:01",
                                                  src_ip="198.19.200.200",
                                                  dst_mac="b8:83:03:74:02:9a",
                                                  dst_ip="198.19.200.48",
                                                  src_port=0xbee0,
                                                  dst_port=34567,
                                                  pool_index=0,
                                                  value_multiplier=3,
                                                  checksum=0)
        # make packets for set 1
        self.pktW0S1 = copy.deepcopy(self.pktW0S0)
        self.pktW1S1 = copy.deepcopy(self.pktW1S0)
        self.pktW2S1 = copy.deepcopy(self.pktW2S0)
        self.expected_pktW0S1 = copy.deepcopy(self.expected_pktW0S0)
        self.expected_pktW1S1 = copy.deepcopy(self.expected_pktW1S0)
        self.expected_pktW2S1 = copy.deepcopy(self.expected_pktW2S0)
        self.pktW0S1['SwitchML'].pool_index = 1
        self.pktW1S1['SwitchML'].pool_index = 1
        self.pktW2S1['SwitchML'].pool_index = 1
        self.expected_pktW0S1['SwitchML'].pool_index = 1
        self.expected_pktW1S1['SwitchML'].pool_index = 1
        self.expected_pktW2S1['SwitchML'].pool_index = 1

 
class BasicReduction(ThreeWorkerTest):
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

class RetransmitAfterReduction(ThreeWorkerTest):
    """
    Ensure we can retransmit from a set after it has received all
    updates and before its paired set has received its first update.

    """

    def runTest(self):
        # firstdo a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        send_packet(self, 1, self.pktW1S0)
        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

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

        # try retransmission from third worker
        send_packet(self, 0, self.pktW2S0)
        verify_packet(self, self.expected_pktW2S0, 0)

class OtherSetReduction(ThreeWorkerTest):
    """
    Test basic operation of a single slot, starting from the second
    set instead of the first.
    """

    def runTest(self):
        # do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        send_packet(self, 1, self.pktW1S1)
        send_packet(self, 2, self.pktW2S1)

        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        verify_packet(self, self.expected_pktW2S1, 2)

class BothSetsReduction(ThreeWorkerTest):
    """
    Test basic operation of a pair of sets.
    """

    def runTest(self):
        # do a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        send_packet(self, 1, self.pktW1S0)
        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

        # now do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        send_packet(self, 1, self.pktW1S1)
        send_packet(self, 2, self.pktW2S1)

        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        verify_packet(self, self.expected_pktW2S1, 2)
                

class SlotReuse(ThreeWorkerTest):
    """
    Test basic slot reuse.
    """

    def runTest(self):
        # do a straightforward reduction in the first set
        send_packet(self, 0, self.pktW0S0)
        send_packet(self, 1, self.pktW1S0)
        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

        # now do a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        send_packet(self, 1, self.pktW1S1)
        send_packet(self, 2, self.pktW2S1)

        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        verify_packet(self, self.expected_pktW2S1, 2)
                
        # now reduce in first set again
        send_packet(self, 0, self.pktW0S0)
        send_packet(self, 1, self.pktW1S0)
        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

        # now reduce in second set again
        send_packet(self, 0, self.pktW0S0)
        send_packet(self, 1, self.pktW1S0)
        send_packet(self, 2, self.pktW2S0)

        verify_packet(self, self.expected_pktW0S0, 0)
        verify_packet(self, self.expected_pktW1S0, 1)
        verify_packet(self, self.expected_pktW2S0, 2)

class IgnoreRetransmissions(ThreeWorkerTest):
    """
    Ensure that retransmissions during reduction are ignored.
    """

    def runTest(self):
        # half-complete reduction in set 1
        send_packet(self, 0, self.pktW0S1)

        # make sure retransmissions to that set from the same worker are ignored
        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        send_packet(self, 0, self.pktW0S1)
        verify_no_other_packets(self)

        # now finish aggregation
        send_packet(self, 1, self.pktW1S1)
        send_packet(self, 2, self.pktW2S1)

        # ensure that we still get the correct answer
        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        verify_packet(self, self.expected_pktW2S1, 2)
        
class RetransmitFromPreviousSet(ThreeWorkerTest):
    """
    Ensure that retransmissions to a previously-aggregated set generate replies.
    """

    def runTest(self):
        # start by doing a straightforward reduction in the second set
        send_packet(self, 0, self.pktW0S1)
        send_packet(self, 1, self.pktW1S1)
        send_packet(self, 2, self.pktW2S1)

        # check the answer
        verify_packet(self, self.expected_pktW0S1, 0)
        verify_packet(self, self.expected_pktW1S1, 1)
        verify_packet(self, self.expected_pktW2S1, 2)

        # now, half-complete reduction in the first set
        send_packet(self, 1, self.pktW1S0)
        
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
        
