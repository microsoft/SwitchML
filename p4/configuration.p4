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
const int register_size = 22528;  // 22528 is theoretical max. Must be multiple of 2.
#endif

const int max_num_workers = 32;  // currently limited to the width of a register

const int num_slots = register_size / 2; // Each slot has two registers

#endif /* _CONFIGURATION_ */
