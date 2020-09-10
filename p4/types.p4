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
enum bit<3> packet_size_t {
    IBV_MTU_128  = 0, // not actually defined in IB, but useful for no recirculation tests
    IBV_MTU_256  = 1,
    IBV_MTU_512  = 2,
    IBV_MTU_1024 = 3
}

// make drop random value small enough to be used with gateway
// inequality comparisons.
//typedef bit<12> drop_random_value_t;
//typedef bit<11> drop_random_value_t;
//typedef bit<16> drop_probability_t;  // signed drop probability; set between 0 and 32767
typedef bit<15> drop_random_value_t; // will be 0-extended to make positive random value
typedef bit<16> drop_probability_t;  // signed drop probability; set between 0 and 32767

typedef bit<32> counter_t;

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

// SwitchML metadata header; bridged for recirculation (and not exposed outside the switch)
// We should keep this <= 28 bytes to avoid impacting non-SwitchML minimum size packets.
//@pa_container_size("ingress", "ig_md.switchml_md.dst_port_qpn", 16, 16)
//@pa_container_size("egress", "eg_md.switchml_md.dst_port_qpn", 16, 16)

//@pa_container_size("egress", "eg_md.switchml_md.pool_index", 32)
//@pa_container_size("ingress", "ig_md.switchml_md.pool_index", 16)

@flexible
header switchml_md_h {
    MulticastGroupId_t mgid;

    //bit<16> ingress_port;
    //bit<16> recirc_port_selector;
    queue_pair_index_t recirc_port_selector;
    //bit<8> ingress_port; // GRR

    // @padding
    // bit<5> pad;

    packet_size_t packet_size;

    // is this RDMA or UDP?
    worker_type_t worker_type;
    worker_id_t worker_id;

    // dest port or QPN to be used for responses
    bit<16> src_port;
    bit<16> dst_port;

    // what should we do with this packet?
    packet_type_t packet_type;

    // which pool element are we talking about?
    pool_index_t pool_index; // Index of pool elements, including both sets.

    // 0 if first packet, 1 if last packet
    num_workers_t first_last_flag;


    // // random number used to simulated packet drops
    //drop_random_value_t drop_random_value;

    // 0 if packet is first packet; non-zero if retransmission
    worker_bitmap_t map_result;

    // bitmaps before and after the current worker is ORed in
    worker_bitmap_t worker_bitmap_before;
    //worker_bitmap_t worker_bitmap_after;

    // tsi used to fill in switchml header (or RoCE address later)
    bit<32> tsi;
    bit<12> unused;

    // @padding
    // bit<5> pad2;
    
    PortId_t ingress_port;
    //bit<64> rdma_addr;
}
//switchml_md_h switchml_md_initializer = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

@flexible
header switchml_rdma_md_h {
    bool first_packet; // set both for only packets
    bool last_packet;
    // // min message len is 256 bytes
    // // max is (22528/2)*256, or 11264*256 (all pool indices for one slot)
    // bit<14> message_len_by256; // only store relevant bits
    bit<64> rdma_addr; // TODO: make this an index rather than an address
}

// header prepended to mirrored debug packets
// must be 32 or fewer bytes 
header switchml_debug_h {
    // ethernet header
    mac_addr_t dst_addr;    
    mac_addr_t src_addr;
    bit<16>    ether_type; // 14 bytes

    
    worker_id_t worker_id; // 2 bytes
    bit<1> padding;
    pool_index_t pool_index; // 2 bytes
    
    // 0 if first packet, 1 if last packet
    num_workers_t first_last_flag; // 1 byte

    //num_workers_t num_workers; // 1 byte (ingress only)

    // // debug info
    // bit<6> unused;
    // packet_type_t packet_type; // 3 bits
}

// Metadata for ingress stage
@flexible
struct ingress_metadata_t {
    switchml_md_h switchml_md;
    switchml_rdma_md_h switchml_rdma_md;
    
    // this bitmap has one bit set for the current packet's worker
    // communication between get_worker_bitmap and update_and_check_worker_bitmap; not used in harvest
    worker_bitmap_t worker_bitmap;

    // // this bitmap shows the way the bitmap should look when complete
    // // communication between get_worker_bitmap and update_and_check_worker_bitmap; not used in harvest
    // worker_bitmap_t complete_bitmap; // TODO: probably delete this

    // how many workers in job?
    // communication between get_worker_bitmap and count_workers; not used in harvest
    num_workers_t num_workers;

    // check how many slots remain in this job's pool
    worker_pool_index_t pool_remaining;

    // set if index is in set1
    // communication between get_worker_bitmap and update_and_check_worker_bitmap; not used in harvest
    bit<1> pool_set;

    // checksum stuff
    bool checksum_err_ipv4;
    bool update_ipv4_checksum;

    MirrorId_t mirror_session;
    bit<16> mirror_ether_type;

    // switch MAC and IP
    mac_addr_t switch_mac;
    ipv4_addr_t switch_ip;

    // signed difference between rng and drop probability for this worker; negative means we should drop
    drop_probability_t drop_calculation;
}
//const ingress_metadata_t ingress_metadata_initializer = {{0, 0, true, 0, 0, packet_type_t.IGNORE, 0, 0, 0, 0, 0, 0}, 0, 0, 0, 0, 0, false, 0, 0};

// Metadata for egress stage
struct egress_metadata_t {
    switchml_md_h switchml_md;
    switchml_rdma_md_h switchml_rdma_md;
    
    // checksum stuff
    bool checksum_err_ipv4;
    bool update_ipv4_checksum;

    // pool_index_t pool_index_mask;
    // pool_index_t masked_pool_index;
    
    // // switch MAC and IP
    // mac_addr_t switch_mac;
    // ipv4_addr_t switch_ip;
}
//const egress_metadata_t egress_metadata_initializer = {{0, 0, true, 0, 0, packet_type_t.IGNORE, 0, 0, 0, 0, 0, 0}, false, false, 0, 0 };

#endif /* _TYPES_ */
