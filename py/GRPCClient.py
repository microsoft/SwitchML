######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat

import grpc

import SwitchML_pb2
import SwitchML_pb2_grpc

def run_test():
    #with grpc.insecure_channel('127.0.0.1:50099') as channel:
    with grpc.insecure_channel('localhost:50099') as channel:
        stub = SwitchML_pb2_grpc.RDMAServerStub(channel)
        print("Sending request")

        job_size = 1
        for rank in range(job_size):
            response = stub.RDMAConnect(SwitchML_pb2.RDMAConnectRequest(
                job_id = 12345,
                my_rank = rank,
                job_size = job_size,
                mac = 0,
                ipv4 = 0,
                rkey = 12345,
                message_size = 1024,
                qpns = [1, 2, 3, 4, 5],
                psns = [6, 7, 8, 9, 0]
            ))
            print("GRPC client received:\n{}".format(pformat(response)))

if __name__ == '__main__':
    logging.basicConfig()
    run_test()
            

