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

