######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from timeit import default_timer as timer

from Table import Table


class SignificandSum(Table):

    def __init__(self, client, bfrt_info, n):
        # set up base class
        super(SignificandSum, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('SignificandSum')
        self.logger.info("Setting up significand sum for index {}...".format(n))

        # if 0 == n:
        #     self.table    = self.bfrt_info.table_get("pipe.Ingress.sumXX.significand_sum")
        #     self.register = self.bfrt_info.table_get("pipe.Ingress.sumXX.significands")
        # else:
        #     self.table    = self.bfrt_info.table_get("pipe.Ingress.sum{:02d}.significand_sum".format(n))
        #     self.register = self.bfrt_info.table_get("pipe.Ingress.sum{:02d}.significands".format(n))
        self.table    = self.bfrt_info.table_get("pipe.Ingress.sum{:02d}.significand_sum".format(n))
        self.register = self.bfrt_info.table_get("pipe.Ingress.sum{:02d}.significands".format(n))

        # clear register
        self.clear()
        self.add_default_entries()
        
    def clear(self):
        # override base class method so we don't clear entries set by p4 code
        # just clear registers
        self.clear_registers()

    def clear_registers(self):
        self.logger.info("Clearing significand sum register...")

        # for each register in sum
        start = timer()
        self.register.entry_del(self.target)
        end = timer()
        self.logger.info("Cleared register in {} seconds...".format((end-start)))
        
        
    def add_default_entries(self):
        # all this is handled in the p4 code
        pass
