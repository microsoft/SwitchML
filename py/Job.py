# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import logging
from pprint import pprint, pformat
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import grpc
import sys
import os
import signal
import yaml
import time
import traceback
import readline
from cmd import Cmd
from concurrent import futures
import re

# import table definitions
from GetWorkerBitmap import GetWorkerBitmap
from Worker import Worker, PacketSize
from UpdateAndCheckWorkerBitmap import UpdateAndCheckWorkerBitmap
from CountWorkers import CountWorkers
from ExponentMax import ExponentMax
from SignificandStage import SignificandStage
from SignificandSum import SignificandSum
from SetDstAddr import SetDstAddr
from PRE import PRE
from NonSwitchMLForward import NonSwitchMLForward
from Worker import Worker, WorkerType
from Ports import Ports
from ARPandICMP import ARPandICMP
from RDMASender import RDMASender
from RDMAReceiver import RDMAReceiver
from NextStep import NextStep
from Mirror import Mirror
from DropSimulator import DropSimulator
from DebugLog import DebugLog

# import RPC server
from GRPCServer import GRPCServer

class Job(Cmd, object):

    # initialize constants
    hex_digit_pair_re = '[0-9a-fA-F][0-9a-fA-F]'
    mac_address_re = ':'.join([hex_digit_pair_re] * 6)
    ipv4_address_re = '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'

    #
    # command interface helpers
    #
    
    def parse_arg(self, arg):
        'Convert arg string to tuple'
        return tuple(arg.split())

    def run_command_loop(self):
        while True:
            try:
                self.cmdloop()
            except KeyboardInterrupt:
                sys.stdout.write('<KeyboardInterrupt>\n')
            except Exception as e:
                print("Got exception: {}".format(traceback.format_exc()))
                print("Continuing...")
    
    def run(self):
        with futures.ThreadPoolExecutor(max_workers=1) as executor:
            # start CLI
            command_loop_future = executor.submit(self.run_command_loop)

            while command_loop_future.running():
                #self.mac_learning.poll()
                time.sleep(1)

            # wait for CLI to exit
            executor.shutdown()
            

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

    def do_clear_all(self, arg):
        'Clear all registers, counters, and tables.'
        print "Clearing all registers, counters, and tables..."
        # self.clear_registers()
        # self.clear_counters()
        # self.clear_tables()
        self.clear_all()
        print "Registers, counters, and tables cleared."
        
    def do_bitmaps(self, arg):
        'Show the bitmaps for the first n slots. 8 is default, or specify a count.'

        try:
            start = 0
            count = 16
            
            args = arg.split(' ')
            
            if len(args) == 1 and args[0] is not '':
                count = int(args[0], 0)
                if count <= 0:
                    count = 1
            elif len(args) == 2:
                start = int(args[0], 0)
                count = int(args[1], 0)
                    
            if self.update_and_check_worker_bitmap is not None:
                self.update_and_check_worker_bitmap.show_bitmaps(start=start, count=count)
        except:
            print "Didn't understand that. Continuing...."

    def do_log_dump(self, arg):
        'Dump log of recent packets.'
        
        self.debug_log.print_log()

    def do_log_save(self, arg):
        'Save log of recent packets to file.'
        
        self.debug_log.save_log(arg)

    def do_log_clear(self, arg):
        'Clear log of recent packets.'
        
        self.debug_log.clear_log()

            
    def do_bitmaps_weirdness_search(self, arg):
        'Show any bitmaps where both sets are nonzero.'
        
        if self.update_and_check_worker_bitmap is not None:
            self.update_and_check_worker_bitmap.show_weird_bitmaps()

    def do_get_counters(self, arg):
        'Show counters. For pool index counters, we show the first 16 slots by default. You can specify a count or a starting index and count.'

        try:
            # get start and count for pool index counters
            start = 0
            count = 16
            
            args = arg.split(' ')
            
            if len(args) == 1 and args[0] is not '':
                count = int(args[0], 0)
                if count <= 0:
                    count = 1
            elif len(args) == 2:
                start = int(args[0], 0)
                count = int(args[1], 0)

            # now print counters
            self.get_worker_bitmap.print_counters()
            self.rdma_receiver.print_counters()
            self.set_dst_addr.print_counters()
            self.rdma_sender.print_counters()

            print("Showing {} pool index counters starting from {}.".format(count, start)) 
            self.next_step.print_counters(start, count)

            self.ports.print_port_stats()
            
        except Exception as e:
            print "Oops: {}".format(traceback.format_exc())

    def do_queue_pair_counters(self, arg):
        'Show queue pair counters. We show the first 8 as default; you can specify a count, start point and count.'

        # get start and count for pool index counters
        start = 0
        count = 8
            
        args = arg.split(' ')
            
        if len(args) == 1 and args[0] is not '':
            count = int(args[0], 0)
            if count <= 0:
                count = 1
        elif len(args) == 2:
            start = int(args[0], 0)
            count = int(args[1], 0)

        print("Showing {} queue pair counters starting from {}.".format(count, start))
        self.rdma_receiver.get_queue_pair_counters(start, count)
                
        
    def do_clear_counters(self, arg):
        'Clear counters.'
        self.clear_counters()
        self.port_clear_counters()

    def do_timing_loop(self, arg):
        'Time table updates.'
        self.non_switchml_forward.timing_loop()


    #
    # commands to manipulate ports
    #
        
    def do_port_add(self, arg):
        "Add a port. Usage: port_add <front panel port>/<lane> <speed: 10, 25, 40, 50, or 100> <error correction: none, rs, or fc>"

        try:
            result = re.match('([0-9]+)/?([0-9]?) *([0-9]*) *(.*)', arg)

            if result and result.group(1):
                port = int(result.group(1))
                if not (1 <= port and port <= 64): raise Exception("Port number invalid.")
            else:
                raise Exception("Port number invalid.")

            if result.group(2):
                lane = int(result.group(2))
                if lane not in range(0,4): raise Exception("Lane too big.")
            else:
                print("Assuming lane 0.")
                lane = 0

            if result.group(3):
                speed = int(result.group(3))
                if speed not in [10, 25, 40, 50, 100]: raise Exception("Speed invalid.")
            else:
                print("Assuming speed 100.")
                speed = 100

            if result.group(4):
                fec = result.group(4)
                if fec not in ['none', 'fc', 'rs']: raise Exception("Error correction invalid.")
            else:
                print("Assuming fec none.")
                fec = 'none'

        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_port_add.__doc__))
            return
            
        print("Configuring port {}/{} speed {} fec {}.".format(port, lane, speed, fec))
        self.port_add(port, lane, speed, fec)

        
    def do_port_del(self, arg):
        "Delete a port. Usage: port_del <front panel port>/<lane>"
        
        try:
            result = re.match('([0-9]+)/?([0-9]?)', arg)

            if result and result.group(1):
                port = int(result.group(1))
                if not (1 <= port and port <= 64): raise Exception("Port number invalid.")
            else:
                raise Exception("Port number invalid.")

            if result.group(2):
                lane = int(result.group(2))
                if lane not in range(0,4): raise Exception("Lane too big.")
            else:
                print("Assuming lane 0.")
                lane = 0

        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_port_del.__doc__))
            return
            
        print("Deleting port {}/{}.".format(port, lane))
        self.port_del(port, lane)
    
        
    def do_port_list(self, arg):
        "List active ports."

        port = None
        lane = None

        if arg != '':
            try:
                result = re.match('([0-9]+)/?([0-9]?)', arg)

                if result and result.group(1):
                    port = int(result.group(1))
                    if not (1 <= port and port <= 64): raise Exception("Port number invalid.")
                else:
                    raise Exception("Port number invalid.")

                if result.group(2):
                    lane = int(result.group(2))
                    if lane not in range(0,4): raise Exception("Lane too big.")
                else:
                    print("Assuming lane 0.")
                    lane = 0
                
            except Exception as e:
                print("Error: {}".format(traceback.format_exc()))
                print("Usage:\n   {}".format(self.do_port_list.__doc__))
                return
            
        self.ports.list_ports(port, lane)

    def do_port_file(self, arg):
        "Add ports from yaml file. Does not clear ports before adding. Usage: do_port_load_file <filename>"

        try:
            self.port_load_file(arg)

        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_port_file.__doc__))
            return

    def do_port_clear_all(self, arg):
        "Clear all active ports."

        try:
            self.port_clear_all()

        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_port_clear_all.__doc__))
            return

        
    def do_port_clear_counters(self, arg):
        "Clear counters on ports."

        try:
            self.port_clear_counters()

        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_port_clear_counters.__doc__))
            return

    #
    # hacky recirc port commands
    # TODO: replace this once BFRT-GRPC can properly enable the secondary recirc ports.
    #
    def do_alternate_recirc_port_enable(self, arg):
        """Enable alternate recirc port for HARVEST4 pass in pipe 1. Usage: do_alternate_recirc_port_enable [<optional port, default 192>]

           NOTE:
           For port 192, you must "remove" the ports in the CLI before this code will work right now.
           bf-sde.port_mgr> bf_port_rmv 0 1 64
        """

        try:
            alternate_recirc_port = int(arg)
        except:
            alternate_recirc_port = 192

        self.ports.enable_alternate_recirc_port()
        self.next_step.enable_alternate_recirc_port(alternate_recirc_port)

    def do_alternate_recirc_port_disable(self, arg):
        'Disable alternate recirc port in pipe 1 (dev port 192).'
        self.next_step.disable_alternate_recirc_port()
        self.ports.disable_alternate_recirc_port()

        
    #
    # commands to manipulate switch address
    #
    
    def do_set_switch_address(self, arg):
        "Set switch MAC and IP to be used for SwitchML. Usage: set_address <MAC address> <IPv4 address>"

        try:
            self.switch_mac, self.switch_ip = arg.split()
            
            self.arp_and_icmp.print_switch_mac_and_ip(self.switch_mac, self.switch_ip)
            
        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_port_list.__doc__))
            return

    def do_get_switch_address(self, arg):
        "Print switch MAC and IP used for SwitchML."
        self.arp_and_icmp.print_switch_mac_and_ip()
        

    #
    # commands to manipulate non-switchml endpoints
    #
        
    def do_mac_address_add(self, arg):
        "Add non-SwitchML MAC address forwarding entry to the switch. Usage: mac_address_add <MAC address> <Front-panel port>/<lane>"

        try:
            result = re.match('({}) +([0-9]+)/?([0-3]?)'.format(self.mac_address_re), arg)

            if result and result.group(1):
                mac_address = result.group(1)
            else:
                raise Exception("MAC address invalid: '{}'".format(arg))
            
            if result.group(2):
                port = int(result.group(2))
                if not (1 <= port and port <= 64): raise Exception("Port number invalid.")
            else:
                raise Exception("MAC address invalid.")

            if result.group(3):
                lane = int(result.group(3))
                if lane not in range(0,4): raise Exception("Lane too big.")
            else:
                print("Assuming lane 0.")
                lane = 0
            
        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_mac_address_add.__doc__))
            return

        self.mac_address_add(mac_address, port, lane)
        
    
    def do_mac_address_del(self, arg):
        "Remove non-SwitchML MAC address forwarding entry from the switch. Usage: mac_address_del <MAC address>"

        self.mac_address_del(arg)

    def do_mac_address_list(self, arg):
        "Print MAC addresses. Usage: mac_address_del [<MAC address>]"

        self.mac_address_list(arg)
        
    #
    # commands to manipulate switchml  enpoints
    #

    def do_worker_clear_all(self, arg):
        "Clear all active SwitchML workers."

        try:
            self.worker_clear_all()

        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_worker_clear_all.__doc__))
            return


    def do_worker_add_udp(self, arg):
        'Add a UDP SwitchML worker. Usage: worker_add_udp <worker rank> <total number of workers> <MAC address> <IP address>'
        try:
            result = arg.split()

            rank = int(result[0], 0)
            count = int(result[1], 0)
            mac = result[2]
            ip = result[3]
            
            self.worker_add_udp(rank, count, mac, ip)

        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_worker_add_udp.__doc__))
            return

        
    def do_worker_add_roce(self, arg):
        'Add a RoCEv2 SwitchML worker. Usage: worker_add_roce <worker rank> <total number of workers> <MAC address> <IP address> <Rkey> <Packet size> <Message size> <list of QPN and PSNs>'
        try:
            result = arg.split()
            
            rank = int(result[0], 0)
            count = int(result[1], 0)
            mac = result[2]
            ip = result[3]
            rkey = int(result[4], 0)

            # convert to enum
            packet_size = int(result[5], 0)
            if packet_size == 128:
                packet_size = PacketSize.IBV_MTU_128
            elif packet_size == 256:
                packet_size = PacketSize.IBV_MTU_256
            elif packet_size == 512:
                packet_size = PacketSize.IBV_MTU_512
            elif packet_size == 1024:
                packet_size = PacketSize.IBV_MTU_1024
            
            message_size = int(result[6], 0)

            # read rest of arg list, constructing tuples of alternating arguments
            qpns_and_psns = [(int(qpn, 0), int(psn, 0)) for qpn, psn in zip(result[7::2], result[8::2])]

            # add worker
            self.worker_add_roce(rank, count, mac, ip, rkey, packet_size, message_size, qpns_and_psns)

        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_worker_add_roce.__doc__))
            return

    def do_worker_list(self, arg):
        'List all workers.'
        self.worker_list()

    def do_worker_file(self, arg):
        'Load SwitchML job configuration from file. Usage: worker_file <filename>'
        self.worker_load_file(arg)

    def do_worker_del(self, arg):
        'Remove worker. Usage: worker_del <worker id>'
        self.worker_del(int(arg, 0))

    #
    # drop simulator
    #
    def do_drop_probability(self, arg):
        'Set drop probability for drop simulator. Usage: drop_probability <ingress drop probability> <egress drop probability>'

        try:
            result = arg.split()
            
            try:
                ingress_drop_probability = float(result[0])
            except:
                ingress_drop_probability = 0.0

            try:
                egress_drop_probability = float(result[1])
            except:
                egress_drop_probability = 0.0

            print("Setting drop probabilities. Ingress: {} Egress: {}".format(ingress_drop_probability, egress_drop_probability))
            self.drop_simulator.set_drop_probabilities(ingress_drop_probability, egress_drop_probability)

        except Exception as e:
            print("Error: {}".format(traceback.format_exc()))
            print("Usage:\n   {}".format(self.do_worker_add_roce.__doc__))
            return

    def do_get_drop_probability(self, arg):
        'Get drop probability currently set in drop simulator.'
        self.drop_simulator.print_drop_probabilities()
        
    #
    # state management for job
    #

    def clear_registers(self):
        for x in self.registers_to_clear:
            x.clear_registers()

    def clear_counters(self):
        for x in self.counters_to_clear:
            try:
                x.clear_counters()
            except Exception as e:
                print("Oops: {}".format(traceback.format_exc()))

    def clear_all(self):
        # clear_registers()
        # clear_counters()
        for x in self.tables_to_clear:
            x.clear()


                

    def mac_address_add(self, mac, port, lane):
        self.non_switchml_forward.worker_add(mac, port, lane)
    
    def mac_address_del(self, mac):
        self.non_switchml_forward.worker_del(mac)
    
    def mac_address_list(self, mac):
        self.non_switchml_forward.worker_print(mac)
    
    def mac_address_clear_all(self):
        self.non_switchml_forward.worker_clear_all(mac)


    
    
    def port_add(self, port, lane, speed, fec):
        self.ports.port_add(port, lane, speed, fec)
        dev_port = self.ports.get_dev_port(port, lane)
        self.pre.worker_add(self.all_ports_mgid, 0x8000 + dev_port, port, lane)

    def port_del(self, port, lane):
        self.ports.port_delete(port, lane)
        dev_port = self.ports.get_dev_port(port, lane)
        self.pre.worker_del(self.all_ports_mgid, 0x8000 + dev_port)

    def port_clear_all(self):
        self.ports.delete_all_ports()
        self.pre.worker_clear_all(self.all_ports_mgid)

    def port_clear_counters(self):
        self.ports.clear_counters()

    def port_load_file(self, ports_file):
        with open(ports_file) as f:
            ports = yaml.safe_load(f)
            
            for dev_port, v in ports['switch']['forward'].items():
                
                # get front panel port from dev port in file
                fp_port, fp_lane = self.ports.get_fp_port(dev_port)

                # get speed
                speed = int(v['speed'].upper().replace('G','').strip())

                # if file has fec information, grab it
                if 'fec' in v:
                    fec = v['fec'].lower()
                else:
                    fec = 'none'

                # add port
                self.port_add(fp_port, fp_lane, speed, fec)

                # get MAC
                mac = v['mac']
                self.mac_address_add(mac, fp_port, fp_lane)
    
    def worker_add_udp(self,
                       worker_rank, worker_count,
                       worker_mac, worker_ip):
        
        if worker_count > 32:
            print("Current design supports only 32 SwitchML workers per job; you requested {}".format(worker_count))
            return

        worker_rid = worker_rank
        worker_mask = 1 << worker_rank
        worker_type = WorkerType.SWITCHML_UDP

        # add to ingress pipeline
        self.get_worker_bitmap.add_udp_entry(
            # destination address for packets
            self.switch_mac,
            self.switch_ip,
            self.switch_udp_port,
            self.switch_udp_port_mask,
            
            # worker info
            worker_rid,
            worker_mac,
            worker_ip,
            worker_mask,
            
            # total number of workers
            worker_count,
            
            # match priority. TODO: remove, since it's not important
            10,
            
            # multicast group for switchml
            self.switchml_workers_mgid,
            
            # pool base and size. TODO: fix when supported by design
            0, 22528)
        
        # add to multicast group
        port, lane = self.non_switchml_forward.worker_port_get(worker_mac)
        self.pre.worker_add(self.switchml_workers_mgid, worker_rid, port, lane)
        
        # add to egress pipeline
        self.set_dst_addr.add_udp_entry(worker_rid, worker_mac, worker_ip)


    # add a ROCEv2 worker.
    # worker_qpns_and_psns is a list of qpn, psn tuples
    def worker_add_roce(self,
                        worker_rank, worker_count,
                        worker_mac, worker_ip, worker_rkey,
                        worker_packet_size, worker_message_size,
                        worker_qpns_and_psns):

        if worker_count > 32:
            print("Current design supports only 32 SwitchML workers per job; you requested {}".format(worker_count))
            return

        worker_rid = worker_rank
        worker_mask = 1 << worker_rank
        worker_type = WorkerType.SWITCHML_UDP

        # add to ingress pipeline
        self.rdma_receiver.add_entry(
            # destination address for packets
            self.switch_mac,
            self.switch_ip,
            self.switch_partition_key,
            self.switchml_workers_mgid,

            # worker info
            worker_ip,
            worker_rid,
            worker_mask,
            worker_packet_size,

            # total number of workers
            worker_count)

        # add to multicast group
        port, lane = self.non_switchml_forward.worker_port_get(worker_mac)
        self.pre.worker_add(self.switchml_workers_mgid, worker_rid, port, lane)

        pprint(worker_mac)
        pprint(worker_ip)
        pprint(worker_qpns_and_psns)
        
        # add to egress pipeline
        self.rdma_sender.add_write_worker(worker_rid, worker_mac, worker_ip, worker_rkey,
                                          worker_packet_size, worker_message_size,
                                          worker_qpns_and_psns)

    
    def worker_del(self):
        print("Unimplemented.")


    def worker_list(self):
        self.get_worker_bitmap.print_counters()
        self.rdma_receiver.print_counters()
        self.set_dst_addr.print_counters()
        self.rdma_sender.print_counters()


    def worker_clear_all(self):
        self.get_worker_bitmap.clear()
        self.rdma_receiver.clear()
        self.clear_registers()
        self.clear_counters()
        self.pre.worker_clear_all(self.switchml_workers_mgid)
        self.set_dst_addr.clear_udp_entries()
        self.rdma_sender.clear_workers()
        self.drop_simulator.clear()

        self.debug_log.clear_log()
        #self.debug_log.clear_log()
        #self.debug_log.clear_log()
        #self.debug_log.clear_log()
        #self.debug_log.clear_log()

    def worker_load_file(self, filename):
        # clear out previous job
        self.worker_clear_all()

        # load current job
        with open(filename) as f:
            job = yaml.safe_load(f)
            switchml = job['switch']['switchML']

            # are we using the dev_port list format?
            if 'workers_ports' in switchml:
                ports = job['switch']['switchML']['workers_ports']
                for i, dev_port in enumerate(ports):
                    fp_port, fp_lane = self.ports.get_fp_port(dev_port)            
                    macs = self.non_switchml_forward.get_macs_on_port(fp_port, fp_lane)

                    if not macs:
                        print("Port {}/{} (dev_port {}) not currently configured.".format(fp_port, fp_lane, dev_port))
                        return
                    
                    # assume we only have one mac per port
                    mac = macs[0]

                    # add with no IP
                    self.worker_add_udp(i, len(ports), mac, '0.0.0.0')
                    

    def get_workers_from_files(self, ports_file, job_file):
        workers = []

        # get worker ports involved in SwitchML job
        with open(job_file) as f:
            job = yaml.safe_load(f)
            worker_ports = job['switch']['switchML']['workers_ports']

        # get info on all ports
        with open(ports_file) as f:
            ports = yaml.safe_load(f)

        # create list of Worker objects from ports
        for dev_port, v in ports['switch']['forward'].items():
            fp_port, fp_lane = self.ports.get_fp_port(dev_port)
            speed = int(v['speed'].upper().replace('G','').strip())

            # args for non-SwitchML worker
            args = {'mac': v['mac'].strip(),
                    'ip': v['ip'].strip(),
                    'front_panel_port': fp_port,
                    'lane': fp_lane,
                    'speed': speed,
                    'fec': 'none'}

            # if this worker is part of the job, mark it as such
            if dev_port in worker_ports:
                args['udp_port'] = 12345 # fake port to set type to SwitchML

            # add this worker to list
            workers.append(Worker(**args))

        # return list of workers
        return workers
        

    def __init__(self, gc, bfrt_info,
                 switch_ip, switch_mac, switch_udp_port=0xbee0, switch_udp_port_mask=0xfff0,
                 workers=None, ports_file=None, job_file=None):
        
        # call Cmd constructor
        super(Job, self).__init__()
        self.intro = "SwitchML command loop. Use 'help' or '?' to list commands."
        self.prompt = "-> "

        # capture connection state
        self.gc = gc
        self.bfrt_info = bfrt_info

        # set up RPC server
        self.grpc_server = GRPCServer()


        # self.thrift_connection = ThriftInterface('switchml', '127.0.0.1')
        # self.thrift_client = self.thrift_connection.setup()

        # self.conn_mgr = self.thrift_connection.conn_mgr
        # self.sess_hdl = self.thrift_connection.conn_mgr.client_init()

        # print('Connected to Device %d, Session %d' % (self.dev_id, self.sess_hdl))


        
        # set up ports object
        self.ports = Ports(self.gc, self.bfrt_info)
        self.ports.enable_loopback_ports()
        
        # capture job state
        self.switch_mac = switch_mac
        self.switch_ip = switch_ip
        self.switch_udp_port = switch_udp_port
        self.switch_udp_port_mask = switch_udp_port_mask
        self.switch_partition_key = 0xffff

        
        self.workers = workers

        # set swithcml MGID and all nodes MGID
        self.switchml_workers_mgid = 0x1234
        self.all_ports_mgid = 0x1235

        # allocate storage
        self.registers_to_clear = []
        self.tables_to_clear    = []
        self.counters_to_clear = []

        #
        # create objects for each block
        #
        
        self.arp_and_icmp = ARPandICMP(self.gc, self.bfrt_info)
        
        self.get_worker_bitmap = GetWorkerBitmap(self.gc, self.bfrt_info)
        self.tables_to_clear.append(self.get_worker_bitmap)
        self.counters_to_clear.append(self.get_worker_bitmap)

        self.rdma_receiver = RDMAReceiver(self.gc, self.bfrt_info)
        self.tables_to_clear.append(self.rdma_receiver)
        self.counters_to_clear.append(self.rdma_receiver)

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
        self.significands = []
        for i in range(32):
            x = SignificandSum(self.gc, self.bfrt_info, i)
            self.significands.append(x)
            self.registers_to_clear.append(x)
            
        # self.significands_00_01_02_03 = SignificandStage(self.gc, self.bfrt_info,  0,  1,  2,  3)
        # self.registers_to_clear.append(self.significands_00_01_02_03)
        # self.significands_04_05_06_07 = SignificandStage(self.gc, self.bfrt_info,  4,  5,  6,  7)
        # self.registers_to_clear.append(self.significands_04_05_06_07)
        # self.significands_08_09_10_11 = SignificandStage(self.gc, self.bfrt_info,  8,  9, 10, 11)
        # self.registers_to_clear.append(self.significands_08_09_10_11)
        # self.significands_12_13_14_15 = SignificandStage(self.gc, self.bfrt_info, 12, 13, 14, 15)
        # self.registers_to_clear.append(self.significands_12_13_14_15)
        # self.significands_16_17_18_19 = SignificandStage(self.gc, self.bfrt_info, 16, 17, 18, 19)
        # self.registers_to_clear.append(self.significands_16_17_18_19)
        # self.significands_20_21_22_23 = SignificandStage(self.gc, self.bfrt_info, 20, 21, 22, 23)
        # self.registers_to_clear.append(self.significands_20_21_22_23)
        # self.significands_24_25_26_27 = SignificandStage(self.gc, self.bfrt_info, 24, 25, 26, 27)
        # self.registers_to_clear.append(self.significands_24_25_26_27)
        # self.significands_28_29_30_31 = SignificandStage(self.gc, self.bfrt_info, 28, 29, 30, 31)
        # self.registers_to_clear.append(self.significands_28_29_30_31)

        # add workers to multicast groups.
        self.cpu_port = 320 # dev port for CPU mirroring
        self.pre = PRE(self.gc, self.bfrt_info, self.ports,
                       self.switchml_workers_mgid, self.all_ports_mgid,
                       self.cpu_port)

        self.mirror = Mirror(self.gc, self.bfrt_info, self.cpu_port)

        # set up drop simulator
        self.drop_simulator = DropSimulator(self.gc, self.bfrt_info)
        self.tables_to_clear.append(self.drop_simulator)

        # setup debug log
        self.debug_log = DebugLog(self.gc, self.bfrt_info)
        self.tables_to_clear.append(self.debug_log)
        self.registers_to_clear.append(self.debug_log)
        
        # set up counters in next step table
        self.next_step = NextStep(self.gc, self.bfrt_info)
        self.tables_to_clear.append(self.next_step)
        
        # add workers to non-switchml forwarding table
        self.non_switchml_forward = NonSwitchMLForward(self.gc, self.bfrt_info, self.ports, self.all_ports_mgid)

        # now add workers to set_dst_addr table in egress
        self.set_dst_addr = SetDstAddr(self.gc, self.bfrt_info, self.switch_mac, self.switch_ip)
        self.tables_to_clear.append(self.set_dst_addr)
        self.counters_to_clear.append(self.set_dst_addr)

        self.rdma_sender = RDMASender(self.gc, self.bfrt_info,
                                      self.switch_mac, self.switch_ip)
                                      #message_size = 1 << 12,
                                      #message_size = 1 << 10, #32768, #16384, #4096, #1024,
                                      #message_size = 1 << 11,
                                      #packet_size = 256)
        self.tables_to_clear.append(self.rdma_sender)
        self.counters_to_clear.append(self.rdma_sender)

        # do this last to print more cleanly
        self.counters_to_clear.append(self.next_step)

        # # configure job
        # self.configure_job()

        # If list of worker objects isn't provided, expect to load worker info from yaml files
        if self.workers:
            for worker in self.workers:
                self.port_add(worker.front_panel_port, worker.lane, worker.speed, worker.fec)
                self.mac_address_add(worker.mac, worker.front_panel_port, worker.lane)
        elif ports_file:
            self.port_load_file(ports_file)

        if self.switch_mac and self.switch_ip:
            self.arp_and_icmp.add_switch_mac_and_ip(self.switch_mac, self.switch_ip)

            
        # start listening for RPCs
        self.grpc_server.serve(self)
