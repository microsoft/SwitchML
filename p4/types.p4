/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _TYPES_
#define _TYPES_

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

typedef bit<16> drop_random_value_t;

enum bit<3> packet_type_t {
    IGNORE     = 0x0,
    CONSUME    = 0x1,
    HARVEST    = 0x2,
    BROADCAST  = 0x3,
    RETRANSMIT = 0x4
}

// SwitchML metadata header; bridged for recirculation (and not exposed outside the switch)
// We should keep this <= 28 bytes to avoid impacting non-SwitchML minimum size packets.
//@pa_container_size("ingress", "ig_md.switchml_md.dst_port_qpn", 16, 16)
//@pa_container_size("egress", "eg_md.switchml_md.dst_port_qpn", 16, 16)

@flexible
header switchml_md_h {
    MulticastGroupId_t mgid;

    @padding
    bit<5> pad2;
    
    PortId_t ingress_port;

    @padding
    bit<5> pad;

    // is this RDMA or UDP?
    worker_type_t worker_type;
    worker_id_t worker_id;

    // dest port or QPN to be used for responses
    bit<16> dst_port;
    
    // what should we do with this packet?
    packet_type_t packet_type;

    // which pool element are we talking about?
    pool_index_t pool_index; // Index of pool elements, including both sets.


    // random number used to simulated packet drops
    drop_random_value_t drop_random_value;

    // 0 if packet is first packet; non-zero if retransmission
    worker_bitmap_t map_result;

    // 0 if first packet, 1 if last packet
    num_workers_t first_last_flag;

    // bitmaps before and after the current worker is ORed in
    worker_bitmap_t worker_bitmap_before;
    worker_bitmap_t worker_bitmap_after;
}
//switchml_md_h switchml_md_initializer = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

// Metadata for ingress stage
struct ingress_metadata_t {
    switchml_md_h switchml_md;
    
    // this bitmap has one bit set for the current packet's worker
    // communication between get_worker_bitmap and update_and_check_worker_bitmap; not used in harvest
    worker_bitmap_t worker_bitmap;
    
    // this bitmap shows the way the bitmap should look when complete
    // communication between get_worker_bitmap and update_and_check_worker_bitmap; not used in harvest
    worker_bitmap_t complete_bitmap;

    // how many workers in job?
    // communication between get_worker_bitmap and count_workers; not used in harvest
    num_workers_t num_workers;

    // set if index is in set1
    // communication between get_worker_bitmap and update_and_check_worker_bitmap; not used in harvest
    bit<1> pool_set;

    // check how many slots remain in this job's pool
    worker_pool_index_t pool_remaining;

    // checksum stuff
    bool checksum_err_ipv4;
    bool update_ipv4_checksum;

    // switch MAC and IP
    mac_addr_t switch_mac;
    ipv4_addr_t switch_ip;
}
//const ingress_metadata_t ingress_metadata_initializer = {{0, 0, true, 0, 0, packet_type_t.IGNORE, 0, 0, 0, 0, 0, 0}, 0, 0, 0, 0, 0, false, 0, 0};

// Metadata for egress stage
struct egress_metadata_t {
    switchml_md_h switchml_md;
    
    // checksum stuff
    bool checksum_err_ipv4;
    bool update_ipv4_checksum;

    pool_index_t pool_index_mask;
    pool_index_t masked_pool_index;
    
    // switch MAC and IP
    mac_addr_t switch_mac;
    ipv4_addr_t switch_ip;
}
//const egress_metadata_t egress_metadata_initializer = {{0, 0, true, 0, 0, packet_type_t.IGNORE, 0, 0, 0, 0, 0, 0}, false, false, 0, 0 };

#endif /* _TYPES_ */
