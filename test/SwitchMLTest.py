######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

"""
This is the base class for testing SwitchML.

Much of the SwitchML configuration code is in the ../py directory; we
import that by having a symlink named SwitchML in this directory, so
that we can import from SwitchML.*.
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

# import SwitchML job setup
from SwitchML.Job import Job
from SwitchML.Worker import Worker, WorkerType
from SwitchML.Packets import make_switchml_udp, make_switchml_rdma, roce_opcode_s2n

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

    def make_switchml_packets(self, workers, pool_index, value_multiplier, dst_port):
        packets = []
        scaled_value_multiplier = value_multiplier * len(workers)
        for w in workers:
            if w.worker_type is WorkerType.SWITCHML_UDP:
                p = make_switchml_udp(src_mac=w.mac,
                                      src_ip=w.ip,
                                      dst_mac=self.switch_mac,
                                      dst_ip=self.switch_ip,
                                      src_port=w.udp_port,
                                      dst_port=dst_port,
                                      pool_index=pool_index,
                                      value_multiplier=value_multiplier)
                e = make_switchml_udp(src_mac=self.switch_mac,
                                      src_ip=self.switch_ip,
                                      dst_mac=w.mac,
                                      dst_ip=w.ip,
                                      src_port=dst_port,
                                      dst_port=w.udp_port,
                                      pool_index=pool_index,
                                      checksum=0,
                                      value_multiplier=scaled_value_multiplier)
                packets.append( (p, e) )
            elif w.worker_type is WorkerType.ROCEv2:
                p = make_switchml_rdma(src_mac=w.mac, # TODO: make RDMA when ready
                                       src_ip=w.ip,
                                       dst_mac=self.switch_mac,
                                       dst_ip=self.switch_ip,
                                       src_port=0x1234,
                                       opcode=roce_opcode_s2n['UC_RDMA_WRITE_ONLY_IMMEDIATE'],
                                       dst_qp=w.roce_base_qpn + pool_index,
                                       value_multiplier=value_multiplier)
                e = make_switchml_rdma(src_mac=self.switch_mac,
                                       src_ip=self.switch_ip,
                                       dst_mac=w.mac,
                                       dst_ip=w.ip,
                                       src_port=0x2345,
                                       opcode=roce_opcode_s2n['UC_RDMA_WRITE_ONLY_IMMEDIATE'],
                                       dst_qp=w.roce_base_qpn + pool_index,
                                       value_multiplier=scaled_value_multiplier)
                packets.append( (p, e) )
            
        return tuple(packets)
