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
        self.server = None
        self.server = grpc.server(futures.ThreadPoolExecutor(max_workers=8))
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
                
                # switch QPNs are just the indices into the pool.
                qpns  = [((1 + request.my_rank) << 16) + i for i, qpn in enumerate(request.qpns)],
                
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
            

