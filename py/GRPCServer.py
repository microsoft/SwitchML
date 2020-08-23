######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
from concurrent import futures
import grpc
import ipaddress

import SwitchML_pb2
import SwitchML_pb2_grpc

#from Worker import Worker


class GRPCServer(SwitchML_pb2_grpc.RDMAServerServicer):

    def __init__(self, ip = '[::]', port = 50099):
        # limit concurrency to 1 to avoid synchronization problems in the BF-RT interface
        self.server = grpc.server(futures.ThreadPoolExecutor(max_workers=1))
        SwitchML_pb2_grpc.add_RDMAServerServicer_to_server(self, self.server)
        self.server.add_insecure_port('{}:{}'.format(ip, port))

        #def 

    def serve(self, job):
        self.server.start()
        self.job = job
        
    def wait(self):
        if self.server:
            self.server.wait_for_termination()
        
    def RDMAConnect(self, request, context):
        print("Got request:\n{}\n from rank {} mac {} with context:\n{}".format(
            pformat(request),
            request.my_rank,
            hex(request.mac),
            pformat(context)))

        # convert to mac string
        mac_hex = "{:012x}".format(request.mac)
        mac_str = ':'.join(mac_hex[i:i+2] for i in range(0, len(mac_hex), 2))
        
        # convert to IP string
        ipv4_str = ipaddress.ip_address(request.ipv4).__str__()
        pprint(ipv4_str)
        
        if self.job:
            if request.my_rank == 0:
                # if this is the first message, clear out old worker state
                # first. workers must synchronize to ensure this happens
                # before remaining worker requests are sent.
                self.job.worker_clear_all()
                
            # now add new worker.
            self.job.worker_add_roce(request.my_rank,
                                     request.job_size,
                                     mac_str,
                                     ipv4_str,
                                     request.rkey,
                                     request.message_size,
                                     zip(request.qpns, request.psns))
            
            # form response
            response = SwitchML_pb2.RDMAConnectResponse(
                # switch address
                macs  = [int(self.job.switch_mac.replace(':', ''), 16)],
                ipv4s = [int(ipaddress.ip_address(unicode(self.job.switch_ip)))],
                
                # mirror this worker's rkey, since the switch doesn't care
                rkeys = [request.rkey],
                
                # Switch QPNs are used for two purposes:
                # 1. Indexing into the PSN registers
                # 2. Differentiating between processes running on the same server
                # 
                # Additionally, there are two restrictions:
                #
                # 1. In order to make debugging easier, we should
                # avoid QPN 0 (sometimes used for management) and QPN
                # 0xffffff (sometimes used for multicast) because
                # Wireshark decodes them improperly, even when the NIC
                # treats them properly.
                #
                # 2. Due to the way the switch sends aggregated
                # packets that are part of a message, only one message
                # should be in flight at a time on a given QPN to
                # avoid reordering packets. The clients will take care
                # of this as long as we give them as many QPNs as they
                # give us.
                #
                # Thus, we construct QPNs as follows.
                # - Bit 23 is always 1. This ensures we avoid QPN 0.
                # - Bits 22 through 16 are the rank of the
                #   client. Since we only support 32 clients per
                #   aggregation in the current design, we will never
                #   use QPN 0xffffff.
                # - Bits 15 through 0 are just the index of the queue;
                #   if 4 queues are requested, these bits will
                #   represent 0, 1, 2, and 3.
                #
                # So if a client with rank 3 sends us a request with 4
                # QPNs, we will reply with QPNs 0x830000, 0x830001,
                # 0x830002, and 0x830003.
                qpns  = [0x800000 | (request.my_rank << 16) | i
                         for i, qpn in enumerate(request.qpns)],
                
                # initial QPNs don't matter; they're overwritten by each _FIRST or _ONLY packet.
                psns  = [i for i, qpn in enumerate(request.qpns)])
            
            return response

        else:
            return SwitchML_pb2.RDMAConnectResponse(
                job_id = request.job_id,
                macs = [request.mac],
                ipv4s = [request.ipv4],
                rkeys = [request.rkey])
                
    

if __name__ == '__main__':
    logging.basicConfig()
    grpc_server = GRPCServer()
    grpc_server.serve(None)
    grpc_server.wait()
            

