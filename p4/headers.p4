// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _HEADERS_
#define _HEADERS_

#include "types.p4"

header ethernet_h {
    mac_addr_t dst_addr;
    mac_addr_t src_addr;
    bit<16>    ether_type;
}
const ether_type_t ETHERTYPE_IPV4          = 16w0x0800;
const ether_type_t ETHERTYPE_ARP           = 16w0x0806;
const ether_type_t ETHERTYPE_ROCEv1        = 16w0x8915;
const ether_type_t ETHERTYPE_SWITCHML_BASE = 16w0xbee0;
const ether_type_t ETHERTYPE_SWITCHML_MASK = 16w0xfff0;

header ipv4_h {
    bit<4>        version;
    bit<4>        ihl;
    bit<8>        diffserv;
    bit<16>       total_len;
    bit<16>       identification;
    bit<3>        flags;
    bit<13>       frag_offset;
    bit<8>        ttl;
    ip_protocol_t protocol;
    bit<16>       hdr_checksum;
    ipv4_addr_t   src_addr;
    ipv4_addr_t   dst_addr;
}

header icmp_h {
    icmp_type_t msg_type;
    bit<8>      msg_code;
    bit<16>     checksum;
}

header arp_h {
    bit<16>       hw_type;
    ether_type_t  proto_type;
    bit<8>        hw_addr_len;
    bit<8>        proto_addr_len;
    arp_opcode_t  opcode;
} 

header arp_ipv4_h {
    mac_addr_t   src_hw_addr;
    ipv4_addr_t  src_proto_addr;
    mac_addr_t   dst_hw_addr;
    ipv4_addr_t  dst_proto_addr;
}

header udp_h {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> length;
    bit<16> checksum;
}
const udp_port_t UDP_PORT_ROCEV2        =   4791;
const udp_port_t UDP_PORT_SWITCHML_BASE = 0xbee0;
const udp_port_t UDP_PORT_SWITCHML_MASK = 0xfff0;

// SwitchML header
//@pa_container_size("ingress", "hdr.switchml.pool_index", 32)
header switchml_h {
    bit<4> msgType;
    bit<12> unused;
    bit<32> tsi;
    bit<16> pool_index;
}

// // InfiniBand-RoCE Global Routing Header
// header ib_grh_h {
//     bit<4>   ipver;
//     bit<8>   tclass;
//     bit<20>  flowlabel;
//     bit<16>  paylen;
//     bit<8>   nxthdr;
//     bit<8>   hoplmt;
//     ib_gid_t sgid;
//     ib_gid_t dgid;
// }

// InfiniBand-RoCE Base Transport Header
//@pa_container_size("ingress", "hdr.ib_bth.dst_qp", 16, 16)
header ib_bth_h {
    ib_opcode_t       opcode;
    bit<1>            se;
    bit<1>            migration_req;
    bit<2>            pad_count;
    bit<4>            transport_version;
    bit<16>           partition_key;
    bit<1>            f_res1;
    bit<1>            b_res1;
    bit<6>            reserved;
    queue_pair_t      dst_qp;
    bit<1>            ack_req;
    bit<7>            reserved2;
    sequence_number_t psn;
}

// Make sure QP number and PSN are in 32-bit containers for register ops
//@pa_container_size("ingress", "hdr.ib_bth.dst_qp", 32)
@pa_container_size("ingress", "hdr.ib_bth.psn", 32)

// InfiniBand-RoCE RDMA Extended Transport Header
header ib_reth_h {
    bit<64> addr;
    bit<32> r_key;
    bit<32> len;
}


@pa_container_size("egress", "hdr.ib_immediate.immediate", 16, 8, 8)

// InfiniBand-RoCE Immediate Header
header ib_immediate_h {
    bit<32> immediate;
}

// InfiniBand-RoCE ICRC Header
header ib_icrc_h {
    bit<32> icrc;
}

// 2-byte exponent header (assuming exponent_t is bit<16>)
header exponents_h {
    exponent_t e0;
}

// 128-byte data header
@pa_container_size("ingress", "hdr.d1.d00", 16, 16) // BUG: works around weird bug that zeros out half of this container
header data_h {
    data_t d00;
    data_t d01;
    data_t d02;
    data_t d03;
    data_t d04;
    data_t d05;
    data_t d06;
    data_t d07;
    data_t d08;
    data_t d09;
    data_t d10;
    data_t d11;
    data_t d12;
    data_t d13;
    data_t d14;
    data_t d15;
    data_t d16;
    data_t d17;
    data_t d18;
    data_t d19;
    data_t d20;
    data_t d21;
    data_t d22;
    data_t d23;
    data_t d24;
    data_t d25;
    data_t d26;
    data_t d27;
    data_t d28;
    data_t d29;
    data_t d30;
    data_t d31;
}


// Full header stack
struct header_t {
    // used only for mirroring packets
    switchml_debug_h switchml_debug;

    // normal headers
    ethernet_h     ethernet;
    arp_h          arp;
    arp_ipv4_h     arp_ipv4;
    ipv4_h         ipv4;
    icmp_h         icmp;
    udp_h          udp;
    switchml_h     switchml;
    // ib_grh_h       ib_grh;
    ib_bth_h       ib_bth;
    ib_reth_h      ib_reth;
    ib_immediate_h ib_immediate;
    // two 128-byte data headers to support harvesting 256 bytes with recirculation.
    data_h         d0;
    data_h         d1;
    // TODO: move exponents before data once daiet code supports it
    exponents_h    exponents;
    ib_icrc_h      ib_icrc;
}

#endif /* _HEADERS_ */
