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
    //ParserCounter() counter;

    state start {
        pkt.extract(ig_intr_md);
        //ig_md = ingress_metadata_initializer;
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
        // skip port metadata header
        #if __TARGET_TOFINO__ == 2
        pkt.advance(192);
        #else
        pkt.advance(64);
        #endif
        // decide what to do with recirculated packets now
        //counter.set(8w0);
        transition select(ig_intr_md.ingress_port) {
            // not currently using PCIe CPU port for recirculation; just parse ethernet
            64: parse_recirculate;
            68: parse_recirculate;
            320: parse_ethernet;
            0x080 &&& 0x180: parse_recirculate;
            0x100 &&& 0x180: parse_recirculate;
            0x180 &&& 0x180: parse_recirculate;
            default:  parse_ethernet;
        }
        // transition select(ig_intr_md.ingress_port) {
        //     // not currently using PCIe CPU port for recirculation; just parse ethernet
        //     320 &&& 0x1ff: parse_ethernet;

        //     // Always parse ethernet on the pipe 0 front panel ports
        //     0x0 &&& 0x1c0: parse_ethernet;
            
        //     // for everything else, treat as recirculated this
        //     // includes ports 64 and 68 on pipe 0, and all other ports
        //     // on all other pipes to support 1024B packets.
        //     default:  parse_recirculate;
        // }
    }

    state parse_recirculate {
        // parse switchml metadata and mark as recirculated
        pkt.extract(ig_md.switchml_md);
        pkt.extract(ig_md.switchml_rdma_md);
        //ig_md.switchml_md.packet_type = packet_type_t.HARVEST7; // already set before recirculation
        //counter.set(8w1);  // remember we don't need to parse 
        //hdr.d1.setValid(); // this will be filled in by the pipeline
        // now parse the rest of the packet
        transition select(ig_md.switchml_md.worker_type, ig_md.switchml_md.packet_type) {
            (worker_type_t.SWITCHML_UDP, _)                : parse_bare_harvest_packet; // only 256B packets are supported, so go parse harvest
            (worker_type_t.ROCEv2, packet_type_t.CONSUME0) : parse_bare_consume_packet; 
            (worker_type_t.ROCEv2, packet_type_t.CONSUME1) : parse_bare_consume_packet; 
            (worker_type_t.ROCEv2, packet_type_t.CONSUME2) : parse_bare_consume_packet; 
            (worker_type_t.ROCEv2, packet_type_t.CONSUME3) : parse_bare_consume_packet; 
            default : parse_bare_harvest_packet; // default to parsing for harvests
        }
    }

    state parse_bare_harvest_packet {
        // one of these will be filled in by the pipeline, and the other set invalid
        hdr.d0.setValid();
        hdr.d1.setValid();
        transition accept;
    }

    state parse_bare_consume_packet {
        // extract the next data headers in packet
        pkt.extract(hdr.d0);
        pkt.extract(hdr.d1);
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

    state parse_ib_payload {
        pkt.extract(hdr.d0);
        pkt.extract(hdr.d1);
        //pkt.extract(hdr.ib_icrc); // do NOT extract ICRC, since this might be in the middle of a >256B packet. 
        ig_md.switchml_md.setValid();
        ig_md.switchml_md.packet_type = packet_type_t.CONSUME0;
        ig_md.switchml_rdma_md.setValid();
        transition accept;
    }
    
    state parse_switchml {
        pkt.extract(hdr.switchml);
        // TODO: move exponents before data once daiet code supports it
        transition parse_data0;
    }

    // TODO: move exponents back here once daiet code supports it
    // state parse_exponents {
    //     pkt.extract(hdr.exponents);
    //     transition parse_data0;
    // }

    // mark as @critical to ensure minimum cycles for extraction
    // TODO: BUG: re-enable after compiler bug fix
    //@critical
    state parse_data0 {
        pkt.extract(hdr.d0);
        // // was this packet recirculated?
        // transition select(counter.is_zero()) { // 0 ==> not recirculated
        //     true  : parse_data1; // not recirculated; continue parsing and set packet type
        //     _     : accept;      // recirculated; SwitchML packet type already set
        // }
        transition parse_data1; // not recirculated; continue parsing and set packet type
    }

    // mark as @critical to ensure minimum cycles for extraction
    // TODO: BUG: re-enable after compiler bug fix
    //@critical
    state parse_data1 {
        pkt.extract(hdr.d1);
        pkt.extract(hdr.exponents); // TODO: move exponents before data once daiet code supports it
        // at this point we know this is a SwitchML packet that wasn't recirculated, so mark it for consumption.
        ig_md.switchml_md.setValid();
        ig_md.switchml_md.packet_type = packet_type_t.CONSUME0;
        ig_md.switchml_rdma_md.setValid();
        transition accept;
    }


    state accept_non_switchml {
        ig_md.switchml_md.setValid();
        ig_md.switchml_md.packet_type = packet_type_t.IGNORE; // assume non-SwitchML packet
        ig_md.switchml_rdma_md.setValid();
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
        // TODO: skip UDP checksum for now. Fix if needed and cost reasonable.
        //hdr.udp.checksum = 0; 

        // if (ig_dprsr_md.mirror_type == MIRROR_TYPE_I2E) {
        //     // mirror.emit<ethernet_h>(ig_md.mirror_session,
        //     //     {hdr.ethernet.src_addr, hdr.ethernet.dst_addr, hdr.ethernet.ether_type});
        //     // mirror.emit<switchml_debug_h>(ig_md.mirror_session, {
        //     //         ig_md.switch_mac,
        //     //         ig_md.switch_mac,
        //     //         ig_md.mirror_ether_type,
        //     //         ig_md.switchml_md.worker_id,
        //     //         ig_md.switchml_md.pool_index,
        //     //         ig_md.switchml_md.first_last_flag,
        //     //         ig_md.num_workers,
        //     //         0,
        //     //         ig_md.switchml_md.packet_type
        //     //     });

        //     //mirror.emit<switchml_md_h>(ig_md.mirror_session, ig_md.switchml_md);

        //     mirror.emit<switchml_md_h>(ig_md.mirror_session, {
        //             ig_md.switchml_md.mgid,
        //             ig_md.switchml_md.ingress_port,
        //             ig_md.switchml_md.worker_type,
        //             ig_md.switchml_md.worker_id,
        //             ig_md.switchml_md.src_port,
        //             ig_md.switchml_md.dst_port,
        //             //ig_md.switchml_md.packet_type,
        //             packet_type_t.MIRROR,
        //             ig_md.switchml_md.pool_index,
        //             ig_md.switchml_md.first_last_flag,
        //             ig_md.switchml_md.map_result,
        //             ig_md.switchml_md.worker_bitmap_before,
        //             ig_md.switchml_md.tsi,
        //             ig_md.switchml_md.unused});
        // }
        
        pkt.emit(ig_md.switchml_md);
        pkt.emit(ig_md.switchml_rdma_md);
        pkt.emit(hdr);
    }
}

parser EgressParser(
    packet_in pkt,
    out header_t hdr,
    out egress_metadata_t eg_md,
    out egress_intrinsic_metadata_t eg_intr_md) {

    //Checksum() ipv4_checksum;

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
        // parse switchml metadata and mark as egress
        pkt.extract(eg_md.switchml_md);
        // now parse the rest of the packet
        //transition parse_ethernet;
        transition select(eg_md.switchml_md.packet_type) {
            packet_type_t.MIRROR : accept;
            default              : parse_switchml_rdma_md;
        }
        //transition accept;
    }

    state parse_switchml_rdma_md {
        pkt.extract(eg_md.switchml_rdma_md); // TODO: only set and parse when needed
        transition accept;
    }

    // state parse_ethernet {
    //     pkt.extract(hdr.ethernet);
    //     transition select(hdr.ethernet.ether_type) {
    //         // ETHERTYPE_ROCEv1                                    : parse_ib_grh;
    //         ETHERTYPE_IPV4                                      : parse_ipv4;
    //         ETHERTYPE_SWITCHML_BASE &&& ETHERTYPE_SWITCHML_MASK : parse_switchml;
    //         default                                             : accept;
    //     }
    // }

    // state parse_ipv4 {
    //     pkt.extract(hdr.ipv4);
    //     ipv4_checksum.add(hdr.ipv4);
    //     eg_md.checksum_err_ipv4 = ipv4_checksum.verify();
    //     eg_md.update_ipv4_checksum = false;
        
    //     transition select(hdr.ipv4.protocol) {
    //         ip_protocol_t.UDP : parse_udp;
    //         default           : accept;
    //     }
    // }

    // state parse_udp {
    //     pkt.extract(hdr.udp);
    //     transition select(hdr.udp.dst_port) {
    //         UDP_PORT_ROCEV2                                   : parse_ib_bth;
    //         UDP_PORT_SWITCHML_BASE &&& UDP_PORT_SWITCHML_MASK : parse_switchml;
    //         default                                           : accept;
    //     }
    // }

    // // state parse_ib_grh {
    // //     pkt.extract(hdr.ib_grh);
    // //     transition parse_ib_bth;
    // // }

    // state parse_ib_bth {
    //     pkt.extract(hdr.ib_bth);
    //     transition accept;
    // }

    // state parse_switchml {
    //     pkt.extract(hdr.switchml);
    //     transition parse_exponents;
    // }

    // state parse_exponents {
    //     pkt.extract(hdr.exponents);
    //     // don't parse data in egress to save on PHV space
    //     transition accept;
    // }
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

        pkt.emit(hdr);
    }
}


#endif /* _PARSERS_ */
