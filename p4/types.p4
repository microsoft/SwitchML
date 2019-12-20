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
typedef bit<8> ip_protocol_t;

// UDP-specific types;
typedef bit<16> udp_port_t;

// IB/RoCE-specific types:
typedef bit<128> ib_gid_t;

// worker types
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
typedef bit<17> pool_index_t;
typedef bit<16> pool_index_by2_t;
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

enum bit<2> packet_type_t {
    IGNORE  = 0x0,
    CONSUME = 0x1,
    HARVEST = 0x2,
    EGRESS  = 0x3
}

// SwitchML metadata header; bridged for recirculation (and not exposed outside the switch)
//@pa_container_size("ingress", "ig_md.switchml_md.pool_index", 32)
//@pa_container_size("egress", "eg_md.switchml_md.pool_index", 32)
header switchml_md_h {
    MulticastGroupId_t mgid;

    @padding
    bit<7> pad2;
    
    PortId_t ingress_port;

    @padding
    bit<5> pad;

    // what should we do with this packet?
    packet_type_t packet_type;

    // which pool element are we talking about?
    pool_index_t pool_index; // Index of pool element, including both sets.


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
}

// Metadata for egress stage
struct egress_metadata_t {
    switchml_md_h switchml_md;
    
    // checksum stuff
    bool checksum_err_ipv4;
}

#endif /* _TYPES_ */
