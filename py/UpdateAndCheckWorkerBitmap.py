######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc


from Table import Table


class UpdateAndCheckWorkerBitmap(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(UpdateAndCheckWorkerBitmap, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('UpdateAndCheckWorkerBitmap')
        self.logger.info("Setting up update_and_check_worker_bitmap table...")
        
        # get this table
        self.table    = self.bfrt_info.table_get("pipe.Ingress.update_and_check_worker_bitmap.update_and_check_worker_bitmap")
        self.register = self.bfrt_info.table_get("pipe.Ingress.update_and_check_worker_bitmap.worker_bitmap")

        # clear and add defaults
        self.clear() # don't clear entries from p4 code; just clear registers
        self.add_default_entries()

    def clear(self):
        # override base class method so we don't clear entries set by p4 code
        # just clear registers
        self.clear_registers()

    def clear_registers(self):
        self.logger.info("Clearing bitmap registers...")

        # clear all register entries
        self.register.entry_del(self.target)
        
        
    def add_default_entries(self):
        # all these are set in the p4 code now
        pass
    

    def show_bitmaps(self, start=0, count=8):
        resp = self.register.entry_get(
            self.target,
            [self.register.make_key([gc.KeyTuple('$REGISTER_INDEX', i)])
             for i in range(start, start+count)],
            flags={"from_hw": True})

        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()

            #print k, v
            pool_index = k['$REGISTER_INDEX']['value']
            set0 = v['Ingress.update_and_check_worker_bitmap.worker_bitmap.first'][0]
            set1 = v['Ingress.update_and_check_worker_bitmap.worker_bitmap.second'][0]
            print("Pool index 0x{:04x}: set 0: 0x{:08x} set 1:0x{:08x}".format(pool_index, set0, set1))

    def show_weird_bitmaps(self):
        resp = self.register.entry_get(
            self.target,
            [],
            flags={"from_hw": True})

        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()

            pool_index = k['$REGISTER_INDEX']['value']
            set0 = v['Ingress.update_and_check_worker_bitmap.worker_bitmap.first'][0]
            set1 = v['Ingress.update_and_check_worker_bitmap.worker_bitmap.second'][0]

            if set0 is not 0 and set1 is not 0:
                print("Pool index 0x{:04x}: set 0: 0x{:08x} set 1:0x{:08x}".format(pool_index, set0, set1))
