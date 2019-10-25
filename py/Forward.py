
import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from Table import Table


class Forward(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(Forward, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('Forward')
        self.logger.info("Setting up forward table...")
        
        # get this table
        self.table = self.bfrt_info.table_get("pipe.SwitchMLIngress.forward.forward")

        # set format annotations
        self.table.info.header_field_annotation_add("hdr.ethernet_dst_addr", "mac")

        # clear and add defaults
        self.clear()
        self.add_default_entries()

        
    def add_default_entries(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # nothing to do for this table!
        pass

    # Add SwitchML UDP entry to table
    def add_udp_entry(self, worker_mac, worker_ip, worker_rid, worker_dev_port):
        self.logger.info("Adding worker {} {} at rid {} port {}".format(worker_mac, worker_ip, worker_rid, worker_dev_port))

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', 10),
                                  # match on egress RID and port
                                  gc.KeyTuple('eg_intr_md.egress_rid',
                                              worker_rid, # 16 bits
                                              0xffff),
                                  gc.KeyTuple('eg_intr_md.egress_port',
                                              worker_dev_port, # 9 bits
                                              0x1ff)])],
            [self.table.make_data([gc.DataTuple('eth_dst_addr', worker_mac),
                                   gc.DataTuple('ip_dst_addr', worker_ip)],
                                  'SwitchMLIngress.forward.forward_for_SwitchML_UDP')])

