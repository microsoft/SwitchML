/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _FORWARD_
#define _FORWARD_

#include "configuration.p4"
#include "types.p4"
#include "headers.p4"

control Forward(
    in header_t hdr,
    inout ingress_metadata_t ig_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    action set_egress_port(bit<9> egress_port) {
        ig_tm_md.ucast_egress_port = egress_port;
    }
    
    action flood(MulticastGroupId_t flood_mgid) {
        ig_tm_md.mcast_grp_a = flood_mgid;
    }
    
    table forward {
        key = {
            hdr.ethernet.dst_addr : exact;
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
        forward.apply();
    }
}

#endif /* _FORWARD_ */
