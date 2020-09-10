// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef _CONFIGURATION_
#define _CONFIGURATION_

// Register size.
// Register size be multiple of 2.

#ifdef SWITCHML_TEST
// Smaller register size for speedier model setup
const int register_size = 512;
const int register_size_log2 = 9;
#else
// 22528 is max stateful 64b registers per stage in Tofino 1.
// This is enough for a single 2.75MB message in flight when using 2 slots.
//const int register_size = 22528;
//const int register_size_log2 = 15;

// 16384 is the largest power-of-two stateful 64b register size per stage in Tofino 1.
// This is enough for a single 2MB message in flight when using 2 slots.
const int register_size = 16384;
const int register_size_log2 = 14;

// // Smaller size for faster setup. This is enough for a single 512KB
// // message in flight when using 2 slots.
// const int register_size = 4096;
// const int register_size_log2 = 12;

// const int register_size = 1024;
// const int register_size_log2 = 10;
#endif

// Each slot has two registers
const int num_slots      = register_size / 2;
const int num_slots_log2 = register_size_log2 / 2;


// max number of SwitchML workers we support
const int max_num_workers = 32;  // currently limited to the width of a register
const int max_num_workers_log2 = 5;  // log base 2 of max_num_workers

// max number of non-SwitchML endpoints we support
const int max_num_non_switchml = 1024; 

// how many destination queue pairs do we support across all workers??
const int max_num_queue_pairs_per_worker = 512;
const int max_num_queue_pairs_per_worker_log2 = 9;
// const int max_num_queue_pairs_per_worker = 256;
// const int max_num_queue_pairs_per_worker_log2 = 8;
const int max_num_queue_pairs = max_num_queue_pairs_per_worker * max_num_workers;
const int max_num_queue_pairs_log2 = max_num_queue_pairs_per_worker_log2 + max_num_workers_log2;
typedef bit<(max_num_workers_log2 + max_num_queue_pairs_per_worker_log2)> queue_pair_index_t;

// Exclusion ID value to use when we don't want to exclude any nodes
// during multicast. Used because we use 0 for an actual exclusion ID.
const bit<16> null_level1_exclusion_id = 0xffff;

#endif /* _CONFIGURATION_ */
