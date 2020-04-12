######################################################
#   Copyright (C) Microsoft. All rights reserved.    #
######################################################

# packet capture with SwitchML parsing

if __name__ == '__main__':
    import os
    import sys
    import random
    import argparse
    
    from pprint import pprint, pformat
    
    from scapy.all import *
    
    from Packets import *
    

    bind_layers(UDP, SwitchML, dport=4000)
    for i in range(0xf):
        bind_layers(UDP, SwitchML, dport=0xbee0+i)
    bind_layers(SwitchML, SwitchMLData64)
    bind_layers(SwitchMLData64, SwitchMLExponent)

    conf.color_theme = BrightTheme()

    argparser = argparse.ArgumentParser(description="SwitchML packet capture/parser")
    arggroup = argparser.add_mutually_exclusive_group(required=True)
    arggroup.add_argument('--pcap',      type=str, default=None, help='Path to pcap file to parse instead of capturing')
    arggroup.add_argument('--interface', type=str, default=None, help='Interface to capture from')
    args = argparser.parse_args()

    def output_packet(p):
        print("======================================================================")
        p.show()
        if 'Raw' in p:
            print("Raw     length: {}".format(len(p['Raw'])))
        if 'Padding' in p:
            print("Padding length: {}".format(len(p['Padding'])))
    
    if args.pcap is not None:
        p = rdpcap(args.pcap)
        print("Captured {} packets".format(len(p)))
        for i in p:
            output_packet(i)

    if args.interface is not None:
        sniff(iface=args.interface, filter="udp", prn=output_packet)
            
        
