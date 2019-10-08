/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _HEADERS_
#define _HEADERS_

#include "types.p4"

header ethernet_h {
    mac_addr_t dst_addr;
    mac_addr_t src_addr;
    bit<16>    ether_type;
}
const ether_type_t ETHERTYPE_IPV4     = 16w0x0800;
const ether_type_t ETHERTYPE_ARP      = 16w0x0806;
const ether_type_t ETHERTYPE_ROCEv1   = 16w0x8915;
const ether_type_t ETHERTYPE_SWITCHML = 16w0xbee0;

header ipv4_h {
    bit<4>       version;
    bit<4>       ihl;
    bit<8>       diffserv;
    bit<16>      total_len;
    bit<16>      identification;
    bit<3>       flags;
    bit<13>      frag_offset;
    bit<8>       ttl;
    bit<8>       protocol;
    bit<16>      hdr_checksum;
    ipv4_addr_t  src_addr;
    ipv4_addr_t  dst_addr;
}
const ip_protocol_t IP_PROTOCOL_ICMP = 1;
const ip_protocol_t IP_PROTOCOL_TCP = 6;
const ip_protocol_t IP_PROTOCOL_UDP = 17;

header udp_h {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> length;
    bit<16> checksum;
}
const udp_port_t UDP_PORT_ROCEV2   = 4791;
const udp_port_t UDP_PORT_SWITCHML = 0xbee0;

// SwitchML header for use in non-RDMA mode
header switchml_h {
    bit<32> tsi;
    bit<16> pool_index;
}


// InfiniBand-RoCE Global Routing Header
header ib_grh_h {
    bit<4>   ipver;
    bit<8>   tclass;
    bit<20>  flowlabel;
    bit<16>  paylen;
    bit<8>   nxthdr;
    bit<8>   hoplmt;
    ib_gid_t sgid;
    ib_gid_t dgid;
}

// InfiniBand-RoCE Base Transport Header
header ib_bth_h {
    bit<8>  opcode;
    bit<1>  se;
    bit<1>  migration_req;
    bit<2>  pad_count;
    bit<4>  transport_version;
    bit<16> partition_key;
    bit<1>  f_res1;
    bit<1>  b_res1;
    bit<6>  reserved;
    bit<24> dst_qp;
    bit<1>  ack_req;
    bit<7>  reserved2;
    bit<24> psn;
}

// 4-byte exponent header
header exponent_h {
    exponent_t e0;
    exponent_t e1;
    exponent_t e2;
    exponent_t e3;
}

// 128-byte data header
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
    ethernet_h ethernet;
    ipv4_h     ipv4;
    udp_h      udp;
    switchml_h switchml;
    ib_grh_h   ib_grh;
    ib_bth_h   ib_bth;
    // two 128-byte data headers to support harvesting 256 bytes with recirculation.
    // (plus two expoonent headers)
    exponent_h e0;
    data_h     d0;
    exponent_h e1;
    data_h     d1;
}

#endif /* _HEADERS_ */
