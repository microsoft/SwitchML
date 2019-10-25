
import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc


from Table import Table
from Worker import Worker

class GetWorkerBitmap(Table):

    def __init__(self, client, bfrt_info):
        # set up base class
        super(GetWorkerBitmap, self).__init__(client, bfrt_info)

        self.logger = logging.getLogger('GetWorkerBitmap')
        self.logger.info("Setting up get_worker_bitmap table...")
        

        # get this table
        self.table = self.bfrt_info.table_get("pipe.SwitchMLIngress.get_worker_bitmap.get_worker_bitmap")

        # set format annotations
        self.table.info.key_field_annotation_add("hdr.ethernet.dst_addr", "mac")
        self.table.info.key_field_annotation_add("hdr.ethernet.src_addr", "mac")
        self.table.info.key_field_annotation_add("hdr.ipv4.dst_addr", "ipv4")
        self.table.info.key_field_annotation_add("hdr.ipv4.src_addr", "ipv4")

        # some handy constants
        self.all_zeros_mac_address = "00:00:00:00:00:00"
        self.all_ones_mac_address = "ff:ff:ff:ff:ff:ff"
        self.all_zeros_ip_address = "0.0.0.0"
        self.all_ones_ip_address = "255.255.255.255"

        # clear and add defaults
        self.clear()
        self.add_default_entries()

        
        
    def add_default_entries(self):
        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        # add entry to forward non-matching packets with no parse errors
        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 2),
                                  # allow packets with no parser errors or with partial headers only (bit 2)
                                  gc.KeyTuple('ig_prsr_md.parser_err',
                                              0x0000, # 16 bits
                                              0xffff),

                                  # ignore all other key fields
                                  gc.KeyTuple('ig_intr_md.ingress_port',
                                              0x000, # 9 bits
                                              0x000),
                                  gc.KeyTuple('hdr.ipv4.src_addr',
                                              self.all_zeros_ip_address,
                                              self.all_zeros_ip_address),
                                  gc.KeyTuple('hdr.ipv4.dst_addr',
                                              self.all_zeros_ip_address,
                                              self.all_zeros_ip_address),
                                  gc.KeyTuple('hdr.ethernet.src_addr',
                                              self.all_zeros_mac_address,
                                              self.all_zeros_mac_address),
                                  gc.KeyTuple('hdr.ethernet.dst_addr',
                                              self.all_zeros_mac_address,
                                              self.all_zeros_mac_address),
                                  gc.KeyTuple('hdr.udp.dst_port',
                                              0x0000, # 16 bits
                                              0x0000),
                                  gc.KeyTuple('hdr.ib_bth.partition_key',
                                              0x0000, # 16 bits
                                              0x0000),
                                  gc.KeyTuple('hdr.ib_bth.dst_qp',
                                              0x000000, # 24 bits
                                              0x000000)])],
            [self.table.make_data([],
                                  'SwitchMLIngress.get_worker_bitmap.forward')])

        # add entry to drop all other packets
        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', self.lowest_priority - 1),
                                  # ignore all key fields
                                  gc.KeyTuple('ig_prsr_md.parser_err',
                                              0x0000, # 16 bits
                                              0x0000),
                                  gc.KeyTuple('ig_intr_md.ingress_port',
                                              0x000, # 9 bits
                                              0x000),
                                  gc.KeyTuple('hdr.ipv4.src_addr',
                                              self.all_zeros_ip_address,
                                              self.all_zeros_ip_address),
                                  gc.KeyTuple('hdr.ipv4.dst_addr',
                                              self.all_zeros_ip_address,
                                              self.all_zeros_ip_address),
                                  gc.KeyTuple('hdr.ethernet.src_addr',
                                              self.all_zeros_mac_address,
                                              self.all_zeros_mac_address),
                                  gc.KeyTuple('hdr.ethernet.dst_addr',
                                              self.all_zeros_mac_address,
                                              self.all_zeros_mac_address),
                                  gc.KeyTuple('hdr.udp.dst_port',
                                              0x0000, # 16 bits
                                              0x0000),
                                  gc.KeyTuple('hdr.ib_bth.partition_key',
                                              0x0000, # 16 bits
                                              0x0000),
                                  gc.KeyTuple('hdr.ib_bth.dst_qp',
                                              0x000000, # 24 bits
                                              0x000000)])],
            [self.table.make_data([],
                             'SwitchMLIngress.get_worker_bitmap.drop')])

        # # add default entry
        # # NOTE: not necessary because default action is const for this table
        # self.table.default_entry_set(
        #     target,
        #     self.table.make_data(data_field_list_in=[],
        #                           action_name='SwitchMLIngress.get_worker_bitmap.forward'))

    # Add SwitchML UDP entry to table
    def add_udp_entry(self, switch_mac, switch_ip, switch_udp_port, switch_udp_mask,
                      worker_mac, worker_ip, worker_bitmap, num_workers,
                      match_priority, switch_mgid, pool_base, pool_size):
        self.logger.info("Adding worker {} {}".format(worker_mac, worker_ip))

        # target all pipes on device 0
        target = gc.Target(device_id=0, pipe_id=0xffff)

        self.table.entry_add(
            target,
            [self.table.make_key([gc.KeyTuple('$MATCH_PRIORITY', match_priority),
                                  # match on Ethernet addrs, IPs and port
                                  gc.KeyTuple('hdr.ipv4.src_addr',
                                              worker_ip,
                                              self.all_ones_ip_address),
                                  gc.KeyTuple('hdr.ipv4.dst_addr',
                                              switch_ip,
                                              self.all_ones_ip_address),
                                  gc.KeyTuple('hdr.ethernet.src_addr',
                                              worker_mac,
                                              self.all_ones_mac_address),
                                  gc.KeyTuple('hdr.ethernet.dst_addr',
                                              switch_mac,
                                              self.all_ones_mac_address),
                                  gc.KeyTuple('hdr.udp.dst_port',
                                              switch_udp_port, # 16 bits
                                              switch_udp_mask),
                                  
                                  # allow packets with no parser errors or with partial headers only (bit 2)
                                  gc.KeyTuple('ig_prsr_md.parser_err',
                                              0x0002, # 16 bits
                                              #0xfffb),
                                              0x0000),

                                  # don't match on ingress port; accept packets from a particular
                                  # worker no matter which port it comes in on.
                                  gc.KeyTuple('ig_intr_md.ingress_port',
                                              0x000, # 9 bits
                                              0x000),
                                  
                                  gc.KeyTuple('hdr.ib_bth.partition_key',
                                              0x0000, # 16 bits
                                              0x0000),
                                  gc.KeyTuple('hdr.ib_bth.dst_qp',
                                              0x000000, # 24 bits
                                              0x000000)])],
            [self.table.make_data([gc.DataTuple('mgid', switch_mgid),
                                   gc.DataTuple('packet_type', 0x1), # packet_type_t.CONSUME
                                   gc.DataTuple('num_workers', num_workers),
                                   gc.DataTuple('worker_bitmap', worker_bitmap),
                                   gc.DataTuple('complete_bitmap', (1 << num_workers) - 1),
                                   gc.DataTuple('pool_base', pool_base), 
                                   gc.DataTuple('pool_size_minus_1', pool_size - 1)],
                             'SwitchMLIngress.get_worker_bitmap.set_bitmap')])

