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

        # child clases must set table
        self.table = None

        # lowest possible  priority for ternary match rules
        self.lowest_priority = 1 << 24
        

    def clear(self):
        """Remove all existing entries in table."""
        if self.table is not None:
            # target all pipes on device 0
            target = gc.Target(device_id=0, pipe_id=0xffff)

            # get all keys in table
            resp = self.table.entry_get(target, [], {"from_hw": False})

            # delete all keys in table
            for _, key in resp:
                if key:
                    self.table.entry_del(target, [key])

        # # try to reinsert default entry if it exists
        # try:
        #     self.table.default_entry_reset(target)
        # except:
        #     pass
            
