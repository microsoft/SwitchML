// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _TYPES_
#define _TYPES_

#include "configuration.p4"

// Mirror types
#if __TARGET_TOFINO__ == 1
typedef bit<3> mirror_type_t;
#else
typedef bit<4> mirror_type_t;
#endif
const mirror_type_t MIRROR_TYPE_I2E = 1;
const mirror_type_t MIRROR_TYPE_E2E = 2;

// Ethernet-specific types
typedef bit<48> mac_addr_t;
typedef bit<16> ether_type_t;

// IPv4-specific types;
typedef bit<32> ipv4_addr_t;
enum bit<8> ip_protocol_t {
    ICMP = 1,
    TCP  = 6,
    UDP  = 17
}

// ARP-specific types
enum bit<16> arp_opcode_t {
    REQUEST = 1,
    REPLY   = 2
}

// ICMP-specific types
enum bit<8> icmp_type_t {
    ECHO_REPLY   = 0,
    ECHO_REQUEST = 8
}

// UDP-specific types;
typedef bit<16> udp_port_t;

// IB/RoCE-specific types:
typedef bit<128> ib_gid_t;
typedef bit<24> sequence_number_t;
typedef bit<24> queue_pair_t;
typedef bit<32> rkey_t;
typedef bit<64> addr_t;

// UC opcodes
enum bit<8> ib_opcode_t {
    UC_SEND_FIRST                = 8w0b00100000,
    UC_SEND_MIDDLE               = 8w0b00100001,
    UC_SEND_LAST                 = 8w0b00100010,
    UC_SEND_LAST_IMMEDIATE       = 8w0b00100011,
    UC_SEND_ONLY                 = 8w0b00100100,
    UC_SEND_ONLY_IMMEDIATE       = 8w0b00100101,
    UC_RDMA_WRITE_FIRST          = 8w0b00100110,
    UC_RDMA_WRITE_MIDDLE         = 8w0b00100111,
    UC_RDMA_WRITE_LAST           = 8w0b00101000,
    UC_RDMA_WRITE_LAST_IMMEDIATE = 8w0b00101001,
    UC_RDMA_WRITE_ONLY           = 8w0b00101010,
    UC_RDMA_WRITE_ONLY_IMMEDIATE = 8w0b00101011
}

// worker types
enum bit<2> worker_type_t {
    FORWARD_ONLY = 0,
    SWITCHML_UDP = 1,
    ROCEv2       = 2
}
typedef bit<16> worker_id_t; // Same as rid for worker; used when retransmitting RDMA packets
typedef bit<32> worker_bitmap_t;
struct worker_bitmap_pair_t {
    worker_bitmap_t first;
    worker_bitmap_t second;
}

// type to hold number of workers for a job
typedef bit<8> num_workers_t;
struct num_workers_pair_t {
    num_workers_t first;
    num_workers_t second;
}

// type used to index into register array
typedef bit<15> pool_index_t;
typedef bit<14> pool_index_by2_t;
typedef bit<16> worker_pool_index_t;

typedef bit<32> data_t;
struct data_pair_t {
    data_t first;
    data_t second;
}

typedef bit<32> significand_t;
struct significand_pair_t {
    significand_t first;
    significand_t second;
}

//typedef bit<8> exponent_t;
typedef bit<16> exponent_t;
struct exponent_pair_t {
    exponent_t first;
    exponent_t second;
}

// RDMA MTU (packet size). Matches ibv_mtu enum in verbs.h
enum bit<2> packet_size_t { // ibv_mtu would be bit<3>, but the larger sizes are not supported in the switch
    IBV_MTU_128  = 0, // not actually defined in IB, but maybe useful for no-recirculation tests
    IBV_MTU_256  = 1,
    IBV_MTU_512  = 2,
    IBV_MTU_1024 = 3
    // IBV_MTU_2048 = 4, // not supported in switch
    // IBV_MTU_4096 = 5  // not supported in switch
    
}

// make drop random value small enough to be used with gateway
// inequality comparisons.
//typedef bit<12> drop_random_value_t;
//typedef bit<11> drop_random_value_t;
//typedef bit<16> drop_probability_t;  // signed drop probability; set between 0 and 32767
//typedef bit<15> drop_random_value_t; // will be 0-extended to make positive random value
//typedef bit<12> drop_probability_t; // try to make this work with gateways
typedef bit<16> drop_probability_t;  // signed drop probability; set between 0 and 32767
//typedef int<16> drop_probability_t;  // signed drop probability; set between 0 and 32767

typedef bit<32> counter_t;

// debug packet ID type. Only 19 bits due to hash limitations in logging module.
typedef bit<19> debug_packet_id_t;

typedef bit<4> packet_type_underlying_t;
enum bit<4> packet_type_t {
    MIRROR     = 0x0,
    //CONSUME    = 0x1,
    //HARVEST    = 0x2,
    BROADCAST  = 0x1,
    RETRANSMIT = 0x2,
    IGNORE     = 0x3,

    CONSUME0   = 0x4, // pipe 0
    CONSUME1   = 0x5, // pipe 1
    CONSUME2   = 0x6, // pipe 2
    CONSUME3   = 0x7, // pipe 3
    
    HARVEST0   = 0x8, // pipe 3
    HARVEST1   = 0x9, // pipe 3
    HARVEST2   = 0xa, // pipe 2
    HARVEST3   = 0xb, // pipe 2
    HARVEST4   = 0xc, // pipe 1
    HARVEST5   = 0xd, // pipe 1
    HARVEST6   = 0xe, // pipe 0
    HARVEST7   = 0xf  // pipe 0
}

// port metadata, used for drop simulation
struct port_metadata_t {
    drop_probability_t ingress_drop_probability;
    drop_probability_t egress_drop_probability;
}


// SwitchML metadata header; bridged for recirculation (and not exposed outside the switch).
// We should keep this + the RDMA or UDP metadata headers <= 28 bytes to avoid impacting non-SwitchML minimum size packets.
header switchml_md_h {

    // byte 0
    
    MulticastGroupId_t mgid; // 16 bits
    
    // byte 2
    
    worker_id_t worker_id; // 16 bits
    
    // byte 4
    
    // which pool element are we talking about?
    @padding
    bit<1> _pad7;
    pool_index_t pool_index; // Index of pool elements, including both sets. 1 + 15 = 16 bits

    // byte 6

    @padding
    bit<2> _pad0;
    queue_pair_index_t recirc_port_selector; // 2 + 9 + 5 = 16 bits

    // byte 8
    
    num_workers_t num_workers; // 8 bits

    // byte 9
    
    packet_size_t packet_size;
    worker_type_t worker_type; // is this RDMA or UDP?
    packet_type_t packet_type; // 2 + 2 + 4 = 8 bits    

    // byte 10
    
    bool simulate_egress_drop;
    @padding
    bit<6> _pad5;
    PortId_t ingress_port; // 7 + 9 = 16 bits

    // byte 12

    bool eth_hdr_len_field_high_order_bit; // make sure this bit is set to 1 to avoid problems with MAC loopback
    @padding
    bit<4> _pad8;
    debug_packet_id_t debug_packet_id; // 5 + 19 = 24 bits

    // byte 15

    // @padding
    // bit<6> _pad6;
    // bool first_packet;
    // bool last_packet;
}
//switchml_md_h switchml_md_initializer = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

// Header added to UDP packets. This padding seems necessary to get
// the design to compile.
header switchml_udp_md_h {
    bit<16> src_port;
    bit<16> dst_port;

    bit<32> tsi;
    
    bit<4> msg_type;
    @padding
    bit<4> _pad0;

    @padding
    bit<4> _pad1;
    bit<12> opcode;
}

// Header added to RDMA packets.
header switchml_rdma_md_h {
    @padding
    bit<6> _pad;
    bool first_packet; // set both for only packets
    bool last_packet;
    
    // // min message len is 256 bytes
    // // max is 4*(22528/2)*256, or 4*11264*256 (all pipes and pool indices for one slot)
    bit<24> len; // store only as many bits as we care about
    bit<64> addr; // TODO: make this an index rather than an address
}

// header prepended to mirrored debug packets
header switchml_debug_h {
    // ethernet header
    mac_addr_t dst_addr;    
    mac_addr_t src_addr;
    bit<16>    ether_type; // 14 bytes
}

// Metadata for ingress stage
@pa_container_size("ingress", "ig_md.worker_bitmap", 32) // to deal with assignments in RDMAReceiver/GetWorkerBitmap
@flexible
struct ingress_metadata_t {
    switchml_md_h switchml_md;
    switchml_rdma_md_h switchml_rdma_md;
    switchml_udp_md_h switchml_udp_md;
    
    // this bitmap has one bit set for the current packet's worker
    worker_bitmap_t worker_bitmap;

    // bitmap before the current worker is ORed in
    worker_bitmap_t worker_bitmap_before;

    // 0 if first packet, 1 if last packet
    num_workers_t first_last_flag;

    // 0 if packet is first packet; non-zero if retransmission
    worker_bitmap_t map_result;

    // check how many slots remain in this job's pool
    worker_pool_index_t pool_remaining;

    // checksum stuff
    bool checksum_err_ipv4;
    bool update_ipv4_checksum;

    port_metadata_t port_metadata;
}
//const ingress_metadata_t ingress_metadata_initializer = {{0, 0, true, 0, 0, packet_type_t.IGNORE, 0, 0, 0, 0, 0, 0}, 0, 0, 0, 0, 0, false, 0, 0};

// Metadata for egress stage
struct egress_metadata_t {
    switchml_md_h switchml_md;
    switchml_rdma_md_h switchml_rdma_md;
    switchml_udp_md_h switchml_udp_md;
    switchml_debug_h switchml_debug;
    
    // checksum stuff
    bool checksum_err_ipv4;
    bool update_ipv4_checksum;
}
//const egress_metadata_t egress_metadata_initializer = {{0, 0, true, 0, 0, packet_type_t.IGNORE, 0, 0, 0, 0, 0, 0}, false, false, 0, 0 };

#endif /* _TYPES_ */
