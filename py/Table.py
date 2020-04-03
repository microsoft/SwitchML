######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

class Table(object):

    def __init__(self, client, bfrt_info):
        # get logging, client, and global program info
        self.logger = logging.getLogger('Table')
        self.gc = client
        self.bfrt_info = bfrt_info

        # target all pipes on device 0
        self.target = gc.Target(device_id=0, pipe_id=0xffff)

        # child clases must set table
        self.table = None

        # lowest possible  priority for ternary match rules
        self.lowest_priority = 1 << 24
        

    def clear(self):
        """Remove all existing entries in table."""
        if self.table is not None:
            self.table.entry_del(self.target)

            # # try to reinsert default entry if it exists
            # try:
            #     self.table.default_entry_reset(self.target)
            # except:
            #     pass
            
