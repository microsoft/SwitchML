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
    out ingress_metadata_t ig_md,
    out ingress_intrinsic_metadata_t ig_intr_md) {
    Checksum() ipv4_checksum;
    Checksum() udp_checksum;

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
            ETHERTYPE_SWITCHML   : parse_switchml;
            default : accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        ipv4_checksum.add(hdr.ipv4);
        ig_md.checksum_err_ipv4 = ipv4_checksum.verify();
        udp_checksum.subtract({hdr.ipv4.src_addr});
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOL_UDP : parse_udp;
            default         : accept;
        }
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        udp_checksum.subtract({hdr.udp.checksum});
        udp_checksum.subtract({hdr.udp.src_port});
        ig_md.checksum_udp_tmp = udp_checksum.get();
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

    state parse_switchml {
        pkt.extract(hdr.switchml);
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
    in ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    Checksum() ipv4_checksum;
    //Checksum() udp_checksum;

    apply {
        hdr.ipv4.hdr_checksum = ipv4_checksum.update({
                hdr.ipv4.version,
                hdr.ipv4.ihl,
                hdr.ipv4.diffserv,
                hdr.ipv4.total_len,
                hdr.ipv4.identification,
                hdr.ipv4.flags,
                hdr.ipv4.frag_offset,
                hdr.ipv4.ttl,
                hdr.ipv4.protocol,
                hdr.ipv4.src_addr,
                hdr.ipv4.dst_addr});
        // skip UDP checksum until we can ensure it's correct
        hdr.udp.checksum = 0; 
        // hdr.udp.checksum = udp_checksum.update(data = {
        //         hdr.ipv4.src_addr,
        //         hdr.udp.src_port,
        //         ig_md.checksum_udp_tmp
        //     }, zeros_as_ones = true);
        pkt.emit(hdr);
    }
}

parser SwitchMLEgressParser(
    packet_in pkt,
    out header_t hdr,
    out egress_metadata_t eg_md,
    out egress_intrinsic_metadata_t eg_intr_md) {

    Checksum() ipv4_checksum;
    Checksum() udp_checksum;

    state start {
        pkt.extract(eg_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_ROCEv1     : parse_ib_grh;
            ETHERTYPE_IPV4       : parse_ipv4;
            ETHERTYPE_SWITCHML   : parse_switchml;
            default : accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        ipv4_checksum.add(hdr.ipv4);
        eg_md.checksum_err_ipv4 = ipv4_checksum.verify();
        udp_checksum.subtract({hdr.ipv4.src_addr});
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOL_UDP : parse_udp;
            default         : accept;
        }
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        udp_checksum.subtract({hdr.udp.checksum});
        udp_checksum.subtract({hdr.udp.src_port});
        eg_md.checksum_udp_tmp = udp_checksum.get();
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

    state parse_switchml {
        pkt.extract(hdr.switchml);
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

control SwitchMLEgressDeparser(
    packet_out pkt,
    inout header_t hdr,
    in egress_metadata_t eg_md,
    in egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md) {

    Checksum() ipv4_checksum;
    //Checksum() udp_checksum;

    apply {
        hdr.ipv4.hdr_checksum = ipv4_checksum.update({
                hdr.ipv4.version,
                hdr.ipv4.ihl,
                hdr.ipv4.diffserv,
                hdr.ipv4.total_len,
                hdr.ipv4.identification,
                hdr.ipv4.flags,
                hdr.ipv4.frag_offset,
                hdr.ipv4.ttl,
                hdr.ipv4.protocol,
                hdr.ipv4.src_addr,
                hdr.ipv4.dst_addr});
        // skip UDP checksum until we can ensure it's correct
        hdr.udp.checksum = 0; 
        // hdr.udp.checksum = udp_checksum.update(data = {
        //         hdr.ipv4.src_addr,
        //         hdr.udp.src_port,
        //         ig_md.checksum_udp_tmp
        //     }, zeros_as_ones = true);
        pkt.emit(hdr);
    }
}
#endif /* _PARSERS_ */
