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

// types related to registers
typedef bit<32> index_t;
typedef bit<2>  opcode_t;
const opcode_t OPCODE_WRITE     = 2w0;
const opcode_t OPCODE_ADD_READ0 = 2w1;
const opcode_t OPCODE_MAX_READ0 = 2w2;
const opcode_t OPCODE_READ1     = 2w3;

typedef bit<32> data_t;
struct data_pair_t {
    data_t first;
    data_t second;
}

typedef bit<8> exponent_t;
struct exponent_pair_t {
    exponent_t first;
    exponent_t second;
}

// Metadata for ingress stage
struct metadata_t {
    opcode_t opcode;
    index_t address;
    // Nothing yet
}

#endif /* _TYPES_ */
