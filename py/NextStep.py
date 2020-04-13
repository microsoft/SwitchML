######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from Table import Table


class NextStep(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(NextStep, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('NextStep')
        self.logger.info("Setting up next_step table...")
        
        # get table
        self.table = self.bfrt_info.table_get("pipe.SwitchMLIngress.switchml_next_step.next_step")
        
        self.recirculate_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.switchml_next_step.recirculate_counter")
        self.broadcast_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.switchml_next_step.broadcast_counter")
        self.retransmit_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.switchml_next_step.retransmit_counter")
        self.drop_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.switchml_next_step.drop_counter")

        # clear and add defaults
        #self.clear()
        ##self.add_default_entries()

    def clear_counters(self):
        self.logger.info("Clearing next_step counters...")
        self.recirculate_counter.entry_del(self.target)
        self.broadcast_counter.entry_del(self.target)
        self.retransmit_counter.entry_del(self.target)
        self.drop_counter.entry_del(self.target)
        
    # Print 
    def print_counters(self, start=0, count=8):
        counters = [self.recirculate_counter,
                    self.broadcast_counter,
                    self.retransmit_counter,
                    self.drop_counter]

        values = [{}, {}, {}, {}]
        
        for counter_id, counter in enumerate(counters):
            counter.operations_execute(self.target, 'Sync')
            resp = counter.entry_get(
                self.target,
                [counter.make_key([gc.KeyTuple('$COUNTER_INDEX', i)])
                 for i in range(start, start+count)],
                flags={"from_hw": False})

            for v, k in resp:
                v = v.to_dict()
                k = k.to_dict()

                #pprint((counter_id, k, v))
                pool_index = k['$COUNTER_INDEX']['value']
                value = v['$COUNTER_SPEC_PKTS']
                values[counter_id][pool_index] = value

        print("                   Recirculated      Broadcast  Retransmitted        Dropped")
        for index in range(start, start+count):
            print("Pool index {:5}: {:13}  {:13}  {:13}  {:13}".format(index,
                                                                       values[0][index],
                                                                       values[1][index],
                                                                       values[2][index],
                                                                       values[3][index]))
