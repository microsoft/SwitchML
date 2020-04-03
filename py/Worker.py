######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc

from enum import Enum

class WorkerType(Enum):
    FORWARD_ONLY = 0
    SWITCHML_UDP = 1
    ROCEv2       = 2

class Worker(object):

    # set either UDP port or RoCE QPN to use as SwitchML worker;
    # otherwise the info here will just activate a switch port to
    # enable forwarding of non-SwitchML traffic.
    def __init__(self,
                 mac, ip,                               # MAC and IP addresses of worker
                 front_panel_port, lane, speed, fec,    # switch port configuration parameters
                 worker_type=None,                      # You can set this explicitly, or set implicitly by setting udp_port or roce_qpn
                 udp_port=None,                         # for SwitchML-UDP workers, set destination UDP port
                 roce_qpn=None, roce_initial_psn=0):    # for RoCE workers, set destination QP number (and maybe the initial PSN)
        self.mac = mac
        self.ip = ip
        self.front_panel_port = front_panel_port
        self.lane = lane
        self.speed = speed
        self.fec = fec

        self.worker_type = worker_type

        self.udp_port = udp_port
        if udp_port is not None and self.worker_type is None:
            self.worker_type = WorkerType.SWITCHML_UDP
            
        self.roce_qpn = roce_qpn
        self.roce_initial_psn = roce_initial_psn
        if roce_qpn is not None and self.worker_type is None:
            self.worker_type = WorkerType.ROCEv2

        # assume forward only if we haven't set worker type
        if self.worker_type is None:
            self.worker_type = WorkerType.FORWARD_ONLY
            
        # things not set by default
        self.rid = None
        self.xid = None

    def __str__(self):
        return "<Worker {}>".format(self.__dict__)
