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
typedef bit<16> worker_pool_index_t;
//typedef bit<32> pool_index_t;

// types related to registers
enum bit<2> opcode_t {
    NOP         = 0x0,
    WRITE_READ0 = 0x1,
    OP_READ0    = 0x2,
    READ1       = 0x3
}

typedef bit<32> data_t;
struct data_pair_t {
    data_t first;
    data_t second;
}

typedef bit<32> mantissa_t;
struct mantissa_pair_t {
    mantissa_t first;
    mantissa_t second;
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

// Metadata for ingress stage
struct ingress_metadata_t {
    
    // is this a consume or harvest packet?
    bool harvest;

    // what type type should the return packet be?
    packet_type_t packet_type;
    opcode_t opcode;
    
    // variables for detecting aggregation completion
    worker_bitmap_t worker_bitmap;
    worker_bitmap_t worker_bitmap_before;
    worker_bitmap_t worker_bitmap_after;
    worker_bitmap_t map_result;
    worker_bitmap_t complete_bitmap;

    num_workers_t num_workers;
    
    bit<1> pool_set;  // set if index is in set1
    //bit<1> set_offset;
    worker_pool_index_t pool_remaining;
    pool_index_t pool_index;

    num_workers_t first_last_flag;
    
    // checksum stuff
    bit<16> checksum_ipv4_tmp;
    bit<16> checksum_udp_tmp;
    bool checksum_upd_ipv4;
    bool checksum_upd_udp;
    bool checksum_err_ipv4;
}

// Metadata for egress stage
struct egress_metadata_t {
    // checksum stuff
    bit<16> checksum_ipv4_tmp;
    bit<16> checksum_udp_tmp;
    bool checksum_upd_ipv4;
    bool checksum_upd_udp;
    bool checksum_err_ipv4;
}

#endif /* _TYPES_ */
