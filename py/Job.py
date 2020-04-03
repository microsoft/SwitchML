######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc
import sys
import os
import signal

import readline
from cmd import Cmd


# import table definitions
from GetWorkerBitmap import GetWorkerBitmap, Worker
from UpdateAndCheckWorkerBitmap import UpdateAndCheckWorkerBitmap
from CountWorkers import CountWorkers
from ExponentMax import ExponentMax
from SignificandStage import SignificandStage
from SetDstAddr import SetDstAddr
from PRE import PRE
from NonSwitchMLForward import NonSwitchMLForward
from Worker import Worker
from Ports import Ports
from ARPandICMP import ARPandICMP
from RoCESender import RoCESender

class Job(Cmd, object):

    #
    # command interface helpers
    #
    
    def parse_arg(self, arg):
        'Convert arg string to tuple'
        return tuple(arg.split())
        
    def run(self):
        while True:
            try:
                self.cmdloop()
            except KeyboardInterrupt:
                sys.stdout.write('<KeyboardInterrupt>\n')

    def emptyline(self):
        'Do nothing when empty line entered at command prompt.'
        pass

    #
    # commands
    #
    
    def do_exit(self, args):
        'Exit program.'
        # exit (bug workaround)
        os.kill(os.getpid(), signal.SIGTERM)
        # never reached
        return -1

    def do_EOF(self, args):
        'Exit on EOF.'
        print "Exiting on EOF."
        return self.do_exit(args)

    def do_clear(self, arg):
        'Clear all registers.'
        print "Clearing all registers..."
        self.clear_registers()
        print "Registers cleared."


    def do_reset(self, arg):
        'Reinitialize all switch state.'
        self.configure_job()

    #
    # state management for job
    #

    def clear_registers(self):
        for x in self.registers_to_clear:
            x.clear_registers()

    def clear_all(self):
        for x in self.tables_to_clear:
            x.clear()
    
    def configure_job(self):
        self.tables_to_clear    = []
        self.registers_to_clear = []

        # clear and reset everything to defaults
        self.clear_all()
        
        # first, delete all old ports and add new ports for all workers
        self.ports = Ports(self.gc, self.bfrt_info)
        self.ports.delete_all_ports()

        # we allocate each worker its own rid.
        for index, worker in enumerate(self.workers):
            worker.rid = index
            worker.xid = index
            self.ports.add_port(worker.front_panel_port, worker.lane, worker.speed, worker.fec)
        
        # set switch IP and MAC and enable ARP/ICMP responder
        self.arp_and_icmp = ARPandICMP(self.gc, self.bfrt_info, self.switch_mac, self.switch_ip)
        
        # add workers to worker bitmap table
        self.get_worker_bitmap = GetWorkerBitmap(self.gc, self.bfrt_info)
        self.tables_to_clear.append(self.get_worker_bitmap)
        match_priority = 10       # not sure if this matters
        pool_base = 0             # TODO: for now, support only one pool at base index 0
        pool_size = 22528         # TODO: for now, use entire switch for single pool
        worker_mask = 0x00000001  # initial worker mask

        # get workers that are enabled as SwitchML workers by having a UDP port or RoCE QPN set
        switchml_workers = [w for w in self.workers if w.udp_port is not None or w.roce_qpn is not None]
        num_switchml_workers = len(switchml_workers)
        if num_switchml_workers > 32:
            log.error("Current design supports only 32 workers per job; you requested {}".format(num_switchml_workers))

        for worker in switchml_workers:
            if worker.udp_port is not None:
                # SwitchML-UDP worker
                self.get_worker_bitmap.add_udp_entry(self.switch_mac, self.switch_ip, self.switch_udp_port, self.switch_udp_port_mask,
                                                     worker.rid, worker.worker_type, worker.mac, worker.ip, worker_mask, num_switchml_workers,
                                                     match_priority, self.switchml_workers_mgid, pool_base, pool_size)
                # shift mask one bit to left for next worker
                worker_mask = worker_mask << 1
            elif worker.roce_qpn is not None:
                # TODO: update for RoCE
                self.get_worker_bitmap.add_udp_entry(self.switch_mac, self.switch_ip, self.switch_udp_port, self.switch_udp_port_mask,
                                                     worker.rid, worker.worker_type, worker.mac, worker.ip, worker_mask, num_switchml_workers,
                                                     match_priority, self.switchml_workers_mgid, pool_base, pool_size)
                # shift mask one bit to left for next worker
                worker_mask = worker_mask << 1
            else:
                # non-SwitchML worker; shouldn't be able to get here
                log.error("Why are we trying to create a SwitchML entry for a non-SwitchML worker?")

        
        # add update rules for bitmap and clear register
        self.update_and_check_worker_bitmap = UpdateAndCheckWorkerBitmap(self.gc, self.bfrt_info)
        self.registers_to_clear.append(self.update_and_check_worker_bitmap)
        
        # add rules for worker count and clear register
        self.count_workers = CountWorkers(self.gc, self.bfrt_info)
        self.registers_to_clear.append(self.count_workers)
        
        # add rules for exponent max calculation and clear register
        self.exponent_max = ExponentMax(self.gc, self.bfrt_info)
        self.registers_to_clear.append(self.exponent_max)
        
        # add rules for data registers and clear registers
        self.significands_00_01_02_03 = SignificandStage(self.gc, self.bfrt_info,  0,  1,  2,  3)
        self.registers_to_clear.append(self.significands_00_01_02_03)
        self.significands_04_05_06_07 = SignificandStage(self.gc, self.bfrt_info,  4,  5,  6,  7)
        self.registers_to_clear.append(self.significands_04_05_06_07)
        self.significands_08_09_10_11 = SignificandStage(self.gc, self.bfrt_info,  8,  9, 10, 11)
        self.registers_to_clear.append(self.significands_08_09_10_11)
        self.significands_12_13_14_15 = SignificandStage(self.gc, self.bfrt_info, 12, 13, 14, 15)
        self.registers_to_clear.append(self.significands_12_13_14_15)
        self.significands_16_17_18_19 = SignificandStage(self.gc, self.bfrt_info, 16, 17, 18, 19)
        self.registers_to_clear.append(self.significands_16_17_18_19)
        self.significands_20_21_22_23 = SignificandStage(self.gc, self.bfrt_info, 20, 21, 22, 23)
        self.registers_to_clear.append(self.significands_20_21_22_23)
        self.significands_24_25_26_27 = SignificandStage(self.gc, self.bfrt_info, 24, 25, 26, 27)
        self.registers_to_clear.append(self.significands_24_25_26_27)
        self.significands_28_29_30_31 = SignificandStage(self.gc, self.bfrt_info, 28, 29, 30, 31)
        self.registers_to_clear.append(self.significands_28_29_30_31)
    
        #
        # configure multicast group
        #
        
        # add workers to multicast groups.
        self.pre = PRE(self.gc, self.bfrt_info, self.ports)
        # add workers
        self.pre.add_workers(self.switchml_workers_mgid, switchml_workers,
                             self.all_ports_mgid, self.workers)

        
        # add workers to non-switchml forwarding table
        self.non_switchml_forward = NonSwitchMLForward(self.gc, self.bfrt_info, self.ports)
        self.non_switchml_forward.add_workers(self.all_ports_mgid, self.workers)
        
        # now add workers to set_dst_addr table in egress
        self.set_dst_addr = SetDstAddr(self.gc, self.bfrt_info, self.switch_mac, self.switch_ip)
        self.tables_to_clear.append(self.set_dst_addr)
        self.roce_sender = RoCESender(self.gc, self.bfrt_info,
                                      self.switch_mac, self.switch_ip,
                                      message_length = 256)#self.message_length)
        self.tables_to_clear.append(self.roce_sender)
        for worker in self.workers:
            if worker.udp_port is not None:
                # SwitchML-UDP worker
                self.set_dst_addr.add_udp_entry(worker.rid, worker.mac, worker.ip)
            elif worker.roce_qpn is not None:
                # SwitchML-RoCE worker
                self.roce_sender.add_worker(worker.rid, worker.mac, worker.ip,
                                            worker.roce_qpn, worker.roce_initial_psn)
            else:
                # not a SwitchML UDP or RoCE worker, so ignore
                pass
                

        # should already be done
        #self.clear_registers()

    
    def __init__(self, gc, bfrt_info,
                 switch_ip, switch_mac, switch_udp_port, switch_udp_port_mask, workers):
        # call Cmd constructor
        super(Job, self).__init__()
        self.intro = "SwitchML command loop. Use 'help' or '?' to list commands."
        self.prompt = "-> "

        # capture connection state
        self.gc = gc
        self.bfrt_info = bfrt_info

        # check that this job can be configured
        if len(workers) > 32:
            logger.error("Sorry, can't support more than 32 workers in the current design.")
        
        # capture job state
        self.switch_ip = switch_ip
        self.switch_mac = switch_mac
        self.switch_udp_port = switch_udp_port
        self.switch_udp_port_mask = switch_udp_port_mask
        self.workers = workers

        # set swithcml MGID and all nodes MGID
        self.switchml_workers_mgid = 0x1234
        self.all_ports_mgid = 0x1235

        # allocate storage
        self.registers_to_clear = []
        self.tables_to_clear    = []
        
        # configure job
        self.configure_job()


