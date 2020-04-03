/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _CONFIGURATION_
#define _CONFIGURATION_

#include "types.p4"

#ifdef SWITCHML_TEST
const int register_size = 4;  // Smaller register size for speedier model setup
#else
//const int register_size = 22528;  // 22528 is theoretical max. Must be multiple of 2.
const int register_size = 4096;
#endif

const int max_num_workers = 32;  // currently limited to the width of a register

const int num_slots = register_size / 2; // Each slot has two registers

// how many destination queue pairs do we support across all workers??
const int max_num_queue_pairs = max_num_workers * 128; //1024;

// Exclusion ID value to use when we don't want to exclude any nodes
// during multicast. Used because we use 0 for an actual exclusion ID.
const bit<16> null_level1_exclusion_id = 0xffff;

#endif /* _CONFIGURATION_ */
