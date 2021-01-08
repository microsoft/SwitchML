// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _PARSERS_
#define _PARSERS_

#include "types.p4"
#include "headers.p4"

parser IngressParser(
    packet_in pkt,
    out header_t hdr,
    out ingress_metadata_t ig_md,
    out ingress_intrinsic_metadata_t ig_intr_md) {

    Checksum() ipv4_checksum;

    state start {
        pkt.extract(ig_intr_md);
        // initialize things that we expect to be initialized; skip things that will be initialized later in the parse. 
        ig_md.worker_bitmap = 0;
        ig_md.worker_bitmap_before = 0;
        ig_md.first_last_flag = 0xff; // initialize first_last_flag to something other than 0 or 1
        ig_md.map_result = 0;
        ig_md.checksum_err_ipv4 = false;
        ig_md.update_ipv4_checksum = false;

        transition select(ig_intr_md.resubmit_flag) {
            1 : parse_resubmit;
            default : parse_port_metadata;
        }
    }

    state parse_resubmit {
        // Resubmission not currently used; just skip header
        // assume recirculated packets will never be resubmitted for now
        #if __TARGET_TOFINO__ == 2
        pkt.advance(192);
        #else
    	pkt.advance(64);
        #endif
        transition parse_ethernet;
    }

    state parse_port_metadata {
        // parse port metadata
        ig_md.port_metadata = port_metadata_unpack<port_metadata_t>(pkt);

        // decide what to do with recirculated packets now
        transition select(ig_intr_md.ingress_port) {
            64: parse_recirculate; // pipe 0 CPU port
            68: parse_recirculate; // pipe 0 recirc port
            //448: parse_recirculate; // pipe 3 first recirc port
            //452: parse_recirculate; // pipe 3 second recirc port
            320: parse_ethernet; // pipe 2 CPU port
            //444: parse_recirculate;
            //0x000 &&& 0x180: parse_recirculate; // all pipe 0 ports
            0x080 &&& 0x180: parse_recirculate; // all pipe 1 ports
            0x100 &&& 0x180: parse_recirculate; // all pipe 2 ports
            0x180 &&& 0x180: parse_recirculate; // all pipe 3 ports
            default:  parse_ethernet;
        }
    }

    state parse_recirculate {
        // parse switchml metadata and mark as recirculated
        pkt.extract(ig_md.switchml_md);
        transition select(ig_md.switchml_md.worker_type, ig_md.switchml_md.packet_type) {
            (worker_type_t.ROCEv2, packet_type_t.CONSUME0)       : parse_rdma_consume;
            (worker_type_t.ROCEv2, packet_type_t.CONSUME1)       : parse_rdma_consume;
            (worker_type_t.ROCEv2, packet_type_t.CONSUME2)       : parse_rdma_consume;
            (worker_type_t.ROCEv2, packet_type_t.CONSUME3)       : parse_rdma_consume;
            (worker_type_t.SWITCHML_UDP, packet_type_t.CONSUME0) : parse_udp_consume;
            (worker_type_t.SWITCHML_UDP, packet_type_t.CONSUME1) : parse_udp_consume;
            (worker_type_t.SWITCHML_UDP, packet_type_t.CONSUME2) : parse_udp_consume;
            (worker_type_t.SWITCHML_UDP, packet_type_t.CONSUME3) : parse_udp_consume;
            (worker_type_t.ROCEv2, _)                            : parse_rdma_harvest;
            (worker_type_t.SWITCHML_UDP, _)                      : parse_udp_harvest;
        }
    }
    
    state parse_udp_consume {
        pkt.extract(ig_md.switchml_udp_md);
        pkt.extract(ig_md.switchml_exponents_md);
        transition parse_consume;
    }

    state parse_udp_harvest {
        pkt.extract(ig_md.switchml_udp_md);
        pkt.extract(ig_md.switchml_exponents_md);
        transition parse_harvest;
    }

    state parse_rdma_consume {
        pkt.extract(ig_md.switchml_rdma_md);
        pkt.extract(ig_md.switchml_exponents_md);
        transition parse_consume;
    }

    state parse_rdma_harvest {
        pkt.extract(ig_md.switchml_rdma_md);
        pkt.extract(ig_md.switchml_exponents_md);
        transition parse_harvest;
    }

    state parse_consume {
        pkt.extract(hdr.d0);
        pkt.extract(hdr.d1);
        transition accept;
    }

    state parse_harvest {
        // one of these will be filled in by the pipeline, and the other set invalid
        hdr.d0.setValid();
        hdr.d1.setValid();
        transition accept;
    }
    
    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_ARP                                       : parse_arp;
            // ETHERTYPE_ROCEv1                                    : parse_ib_grh;
            ETHERTYPE_IPV4                                      : parse_ipv4;
            // ETHERTYPE_SWITCHML_BASE &&& ETHERTYPE_SWITCHML_MASK : parse_switchml;
            default : accept_non_switchml;
        }
    }

    state parse_arp {
        pkt.extract(hdr.arp);
        transition select(hdr.arp.hw_type, hdr.arp.proto_type) {
            (0x0001, ETHERTYPE_IPV4) : parse_arp_ipv4;
            default: accept_non_switchml;
        }
    }

    state parse_arp_ipv4 {
        pkt.extract(hdr.arp_ipv4);
        transition accept_non_switchml;
    }        

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        ipv4_checksum.add(hdr.ipv4);
        ig_md.checksum_err_ipv4 = ipv4_checksum.verify();
        ig_md.update_ipv4_checksum = false;
        
        // parse only non-fragmented IP packets with no options
        transition select(hdr.ipv4.ihl, hdr.ipv4.frag_offset, hdr.ipv4.protocol) {
            (5, 0, ip_protocol_t.ICMP) : parse_icmp;
            (5, 0, ip_protocol_t.UDP)  : parse_udp;
            default                    : accept_non_switchml;
        }
    }

    state parse_icmp {
        pkt.extract(hdr.icmp);
        transition accept_non_switchml;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition select(hdr.udp.dst_port) {
            UDP_PORT_ROCEV2                                   : parse_ib_bth;
            UDP_PORT_SWITCHML_BASE &&& UDP_PORT_SWITCHML_MASK : parse_switchml;
            default                                           : accept_non_switchml;
        }
    }

    // state parse_ib_grh {
    //     pkt.extract(hdr.ib_grh);
    //     transition parse_ib_bth;
    // }

    state parse_ib_bth {
        pkt.extract(hdr.ib_bth);
        ig_md.switchml_md.setValid();
        ig_md.switchml_md = switchml_md_initializer;
        ig_md.switchml_md.packet_type = packet_type_t.CONSUME0;
        ig_md.switchml_rdma_md.setValid();
        ig_md.switchml_rdma_md = switchml_rdma_md_initializer;

        // for now, also extract empty exponent header
        // TODO: deal with in CONSUME0 and HARVEST7 only, in pipline
        ig_md.switchml_exponents_md.setValid();
        ig_md.switchml_exponents_md = switchml_exponents_md_initializer;
        
        transition select(hdr.ib_bth.opcode) {
            // include only UC operations here
            ib_opcode_t.UC_SEND_FIRST                : parse_ib_payload;
            ib_opcode_t.UC_SEND_MIDDLE               : parse_ib_payload;
            ib_opcode_t.UC_SEND_LAST                 : parse_ib_payload;
            ib_opcode_t.UC_SEND_LAST_IMMEDIATE       : parse_ib_immediate;
            ib_opcode_t.UC_SEND_ONLY                 : parse_ib_payload;
            ib_opcode_t.UC_SEND_ONLY_IMMEDIATE       : parse_ib_immediate;
            ib_opcode_t.UC_RDMA_WRITE_FIRST          : parse_ib_reth;
            ib_opcode_t.UC_RDMA_WRITE_MIDDLE         : parse_ib_payload;
            ib_opcode_t.UC_RDMA_WRITE_LAST           : parse_ib_payload;
            ib_opcode_t.UC_RDMA_WRITE_LAST_IMMEDIATE : parse_ib_immediate;
            ib_opcode_t.UC_RDMA_WRITE_ONLY           : parse_ib_reth;
            ib_opcode_t.UC_RDMA_WRITE_ONLY_IMMEDIATE : parse_ib_reth_immediate;
            default : accept;
        }
    }

    state parse_ib_immediate {
        pkt.extract(hdr.ib_immediate);
        transition parse_ib_payload;
    }

    state parse_ib_reth {
        pkt.extract(hdr.ib_reth);
        transition parse_ib_payload;
    }

    state parse_ib_reth_immediate {
        pkt.extract(hdr.ib_reth);
        pkt.extract(hdr.ib_immediate);
        transition parse_ib_payload;
    }

    // mark as @critical to ensure minimum cycles for extraction
    // TODO: BUG: re-enable after compiler bug fix
    //@critical
    state parse_ib_payload {
        pkt.extract(hdr.d0);
        pkt.extract(hdr.d1);
        //pkt.extract(hdr.ib_icrc); // do NOT extract ICRC, since this might be in the middle of a >256B packet. 
        transition accept;
    }
    
    // mark as @critical to ensure minimum cycles for extraction
    // TODO: BUG: re-enable after compiler bug fix
    //@critical
    state parse_switchml {
        pkt.extract(hdr.switchml);
        pkt.extract(hdr.d0);
        pkt.extract(hdr.d1);
        pkt.extract(hdr.exponents); // TODO: move exponents before data once daiet code supports it
        // at this point we know this is a SwitchML packet that wasn't recirculated, so mark it for consumption.
        ig_md.switchml_md.setValid();
        ig_md.switchml_md = switchml_md_initializer;
        ig_md.switchml_md.packet_type = packet_type_t.CONSUME0;
        transition accept;
    }


    state accept_non_switchml {
        ig_md.switchml_md.setValid();
        ig_md.switchml_md = switchml_md_initializer;
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE; // assume non-SwitchML packet
        transition accept;
    }
    
}

control IngressDeparser(
    packet_out pkt,
    inout header_t hdr,
    in ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    Checksum() ipv4_checksum;
    Mirror() mirror;

    apply {
        if (ig_md.update_ipv4_checksum) {
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
        }
        pkt.emit(ig_md.switchml_md);
        pkt.emit(ig_md.switchml_rdma_md);
        pkt.emit(ig_md.switchml_udp_md);
        pkt.emit(ig_md.switchml_exponents_md);
        pkt.emit(hdr);
    }
}

parser EgressParser(
    packet_in pkt,
    out header_t hdr,
    out egress_metadata_t eg_md,
    out egress_intrinsic_metadata_t eg_intr_md) {

    state start {
        pkt.extract(eg_intr_md);
        //eg_md = egress_metadata_initializer;
        // all egress packets in this design have a SwitchML metadata header.
        // TODO: BUG: compiler bug workaround; remove this when fixed
        transition select(eg_intr_md.pkt_length) {
            0 : parse_switchml_md;
            _ : parse_switchml_md;
        }
        //transition parse_switchml_md;
    }

    state parse_switchml_md {
        pkt.extract(eg_md.switchml_md);
        transition select(eg_md.switchml_md.worker_type, eg_md.switchml_md.packet_type) {
            (_, packet_type_t.MIRROR)       : accept;
            (worker_type_t.SWITCHML_UDP, _) : parse_switchml_udp_md;
            (worker_type_t.ROCEv2, _)       : parse_switchml_rdma_md;
            default                         : accept;
        }
    }

    state parse_switchml_udp_md {
        pkt.extract(eg_md.switchml_udp_md);
        pkt.extract(eg_md.switchml_exponents_md);
        transition accept;
    }

    state parse_switchml_rdma_md {
        pkt.extract(eg_md.switchml_rdma_md);
        pkt.extract(eg_md.switchml_exponents_md);
        transition accept;
    }
}

control EgressDeparser(
    packet_out pkt,
    inout header_t hdr,
    in egress_metadata_t eg_md,
    in egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md) {

    Checksum() ipv4_checksum;

    apply {
        if (eg_md.update_ipv4_checksum) {
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
        }
        // TODO: skip UDP checksum for now.
        //hdr.udp.checksum = 0; 

        // if packet is mirrored, emit debug header + metadata headers
        pkt.emit(eg_md.switchml_debug);
        pkt.emit(eg_md.switchml_md);
        //pkt.emit(eg_md.switchml_udp_md); // Emitting this leads to allocation problems.
        //pkt.emit(eg_md.switchml_rdma_md);  // Emitting this leads to allocation problems.
        
        pkt.emit(hdr);
    }
}


#endif /* _PARSERS_ */
