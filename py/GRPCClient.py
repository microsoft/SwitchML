######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat

import grpc

import SwitchML_pb2
import SwitchML_pb2_grpc

def run_test():
    with grpc.insecure_channel('localhost:50099') as channel:
        stub = SwitchML_pb2_grpc.RDMAServerStub(channel)
        response = stub.RDMAConnect(SwitchML_pb2.RDMAConnectRequest(
            hostname = "hello",
            gid = bytes([1,2,3,4,5,6,7,8]),
            rkey = 12345,
            qpns = [1, 2, 3, 4, 5],
            psns = [6, 7, 8, 9, 0]
        ))
        print("GRPC client received:\n{}".format(pformat(response)))

if __name__ == '__main__':
    logging.basicConfig()
    run_test()
            

