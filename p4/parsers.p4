/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _PARSERS_
#define _PARSERS_

#include "types.p4"
#include "headers.p4"

parser SwitchMLIngressParser(
    packet_in pkt,
    out header_t hdr,
    out metadata_t ig_md,
    out ingress_intrinsic_metadata_t ig_intr_md) {
    state start {
        pkt.extract(ig_intr_md);
        transition select(ig_intr_md.resubmit_flag) {
            1       : parse_resubmit;
            default : parse_port_metadata;
        }
    }

    state parse_resubmit {
        // Not currently used; just skip
        #if __TARGET_TOFINO__ == 2
        pkt.advance(192);
        #else
    	pkt.advance(64);
        #endif
        transition parse_ethernet;
    }

    state parse_port_metadata {
        #if __TARGET_TOFINO__ == 2
        pkt.advance(192);
        #else
        pkt.advance(64);
        #endif
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_ROCEv1     : parse_ib_grh;
            ETHERTYPE_IPV4       : parse_ipv4;
            default : accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOL_UDP : parse_udp;
            default         : accept;
        }
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition select(hdr.udp.dst_port) {
            UDP_PORT_ROCEV2 : parse_ib_bth;
            default : accept;
        }
    }

    state parse_ib_grh {
        pkt.extract(hdr.ib_grh);
        transition parse_ib_bth;
    }

    state parse_ib_bth {
        pkt.extract(hdr.ib_bth);
        transition parse_data0;
    }

    // mark as @critical to ensure minimum cycles for extraction
    @critical
    state parse_data0 {
        pkt.extract(hdr.d0);
        transition parse_data1;
    }

    // mark as @critical to ensure minimum cycles for extraction
    @critical
    state parse_data1 {
        pkt.extract(hdr.d1);
        transition accept;
    }

}

control SwitchMLIngressDeparser(
    packet_out pkt,
    inout header_t hdr,
    in metadata_t ig_md,
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {
    apply {
        pkt.emit(hdr);
    }
}

parser SwitchMLEgressParser(
    packet_in pkt,
    out header_t hdr,
    out metadata_t ig_md,
    out egress_intrinsic_metadata_t eg_intr_md) {
    state start {
        // do nothing in Egress
        transition accept;
    }
}

control SwitchMLEgressDeparser(
    packet_out pkt,
    inout header_t hdr,
    in metadata_t ig_md,
    in egress_intrinsic_metadata_for_deparser_t ig_intr_dprs_md) {
    apply {
        // do nothing in Egress
    }
}
#endif /* _PARSERS_ */
