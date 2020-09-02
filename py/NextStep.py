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
        self.table = self.bfrt_info.table_get("pipe.SwitchMLIngress.next_step.next_step")

        # get counters
        #self.consume_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.next_step.consume_counter")
        #self.harvest_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.next_step.harvest_counter")
        self.recirculate_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.next_step.recirculate_counter")
        self.broadcast_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.next_step.broadcast_counter")
        self.retransmit_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.next_step.retransmit_counter")
        self.drop_counter = self.bfrt_info.table_get("pipe.SwitchMLIngress.next_step.drop_counter")

        # clear and add defaults
        #self.clear()
        ##self.add_default_entries()

    def clear(self):
        # don't clear anything
        pass

    def clear_counters(self):
        self.logger.info("Clearing next_step counters...")

        # this should work, but it doesn't.
        #self.consume_counter.entry_del(self.target)
        #self.harvest_counter.entry_del(self.target)
        self.recirculate_counter.entry_del(self.target)
        self.broadcast_counter.entry_del(self.target)
        self.retransmit_counter.entry_del(self.target)
        self.drop_counter.entry_del(self.target)

        # so we'll clear them manually
        for counter in [#self.consume_counter,
                        #self.harvest_counter,
                        self.recirculate_counter,
                        self.broadcast_counter,
                        self.retransmit_counter,
                        self.drop_counter]:
            count = counter.info.size
            self.logger.info(
                "Clearing {} keys for counter table {}".format(count,
                                                               counter.info.name_get()))
            counter.entry_mod(
                self.target,
                [counter.make_key([gc.KeyTuple('$COUNTER_INDEX', i)])
                 for i in range(count)],
                [counter.make_data(
                    [gc.DataTuple('$COUNTER_SPEC_PKTS', 0)])] * count)


    # Print 
    def print_counters(self, start=0, count=8):
        counters = [#self.consume_counter,
                    #self.harvest_counter,
                    self.recirculate_counter,
                    self.broadcast_counter,
                    self.retransmit_counter,
                    self.drop_counter]

        count = count * 2 # double count to get both sets
        #values = [{}, {}, {}, {}, {}]
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

        print("                      " +
              #"      Consumed" +
              #"     Harvested" +
              "   Recirculated" +
              "      Broadcast" +
              "  Retransmitted " +
              "        Dropped")

        for index in range(start, start+count):
            #print("Pool index {:5} set {}: {:13}  {:13}  {:13}  {:13}  {:13}".format(
            print("Pool index {:5} set {}: {:13}  {:13}  {:13}  {:13}".format(
                index >> 1, index & 1,
                values[0][index],
                values[1][index],
                values[2][index],
                values[3][index]))
            

        # get direct counter
        print("Stuff!")
        self.table.operations_execute(self.target, 'SyncCounters')
        resp = self.table.entry_get(
            self.target)
        # ,
        #     [self.table.make_key([gc.KeyTuple('$COUNTER_INDEX', i)])
        #          for i in range(start, start+count)],
        #         flags={"from_hw": False})

        for v, k in resp:
            v = v.to_dict()
            k = k.to_dict()

            pprint((k, v))
