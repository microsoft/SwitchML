/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _NON_SWITCHML_FORWARD_
#define _NON_SWITCHML_FORWARD_

#include "configuration.p4"
#include "types.p4"
#include "headers.p4"

control NonSwitchMLForward(
    in header_t hdr,
    in ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    action set_egress_port(bit<9> egress_port) {
        ig_tm_md.ucast_egress_port = egress_port;
    }
    
    action flood(MulticastGroupId_t flood_mgid) {
        ig_tm_md.mcast_grp_a = flood_mgid;
    }
    
    table forward {
        key = {
            //ig_md.switchml_md.packet_type : exact;
            hdr.ethernet.dst_addr         : exact;
            //hdr.ethernet.ether_type       : exact;
        }
        actions = {
            set_egress_port;
            flood;
        }

        // // TODO: is this a good idea? Should we finish this and add MAC learning?
        //const default_action = flood;
        
        size = max_num_workers;
    }

    apply {
        // if this isn't a SwitchML packet, and if the ARP/ICMP
        // responder hasn't already handled it, forward.
        if ((ig_md.switchml_md.packet_type == packet_type_t.IGNORE) &&
            (ig_tm_md.bypass_egress == 0)) { // set by ARP responder
            forward.apply();
        }
    }
}

#endif /* _NON_SWITCHML_FORWARD_ */
