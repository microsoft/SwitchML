/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _CONFIGURATION_
#define _CONFIGURATION_

#include "types.p4"

// constants
const int register_size = 22528;  // 22528 is theoretical max.
const int max_num_workers = 32;  // currently limited to the width of a register

const int num_pools = register_size;
const int num_slots = 2 * num_pools;

// Uncomment to do hton()/ntoh() for data on switch
// NOTE: ntoh() not currently working properly
//#define INCLUDE_SWAP_BYTES

// Packet format selector
// Uncomment only one of these
#define SWITCHML_FORMAT
//#define ROCE_FORMAT

#endif /* _CONFIGURATION_ */
