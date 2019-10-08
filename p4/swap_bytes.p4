/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _HTONNTOH_
#define _HTONNTOH_

// helper macro to swap bytes
#define SWAP_BYTES(NAME) \
NAME = (NAME[7:0] ++ NAME[15:8] ++ NAME[23:16] ++ NAME[31:24])

#define DEFINE_SWAP_BYTES(NAME) \
action NAME##_swap_bytes1() { \
    SWAP_BYTES(hdr.d0.d00); \
    SWAP_BYTES(hdr.d0.d01); \
    SWAP_BYTES(hdr.d0.d02); \
    SWAP_BYTES(hdr.d0.d03); \
    SWAP_BYTES(hdr.d0.d04); \
    SWAP_BYTES(hdr.d0.d05); \
    SWAP_BYTES(hdr.d0.d06); \
    SWAP_BYTES(hdr.d0.d07); \
    SWAP_BYTES(hdr.d0.d08); \
    SWAP_BYTES(hdr.d0.d09); \
    SWAP_BYTES(hdr.d0.d10); \
    SWAP_BYTES(hdr.d0.d11); \
    SWAP_BYTES(hdr.d0.d12); \
    SWAP_BYTES(hdr.d0.d13); \
    SWAP_BYTES(hdr.d0.d14); \
    SWAP_BYTES(hdr.d0.d15); \
    SWAP_BYTES(hdr.d0.d16); \
    SWAP_BYTES(hdr.d0.d17); \
    SWAP_BYTES(hdr.d0.d18); \
    SWAP_BYTES(hdr.d0.d19); \
    SWAP_BYTES(hdr.d0.d20); \
    SWAP_BYTES(hdr.d0.d21); \
    SWAP_BYTES(hdr.d0.d22); \
    SWAP_BYTES(hdr.d0.d23); \
 \
    SWAP_BYTES(hdr.d1.d00); \
    SWAP_BYTES(hdr.d1.d01); \
    SWAP_BYTES(hdr.d1.d02); \
    SWAP_BYTES(hdr.d1.d03); \
    SWAP_BYTES(hdr.d1.d04); \
    SWAP_BYTES(hdr.d1.d05); \
    SWAP_BYTES(hdr.d1.d06); \
    SWAP_BYTES(hdr.d1.d07); \
    SWAP_BYTES(hdr.d1.d08); \
    SWAP_BYTES(hdr.d1.d09); \
    SWAP_BYTES(hdr.d1.d10); \
    SWAP_BYTES(hdr.d1.d11); \
    SWAP_BYTES(hdr.d1.d12); \
    SWAP_BYTES(hdr.d1.d13); \
    SWAP_BYTES(hdr.d1.d14); \
    SWAP_BYTES(hdr.d1.d15); \
    SWAP_BYTES(hdr.d1.d16); \
    SWAP_BYTES(hdr.d1.d17); \
    SWAP_BYTES(hdr.d1.d18); \
    SWAP_BYTES(hdr.d1.d19); \
    SWAP_BYTES(hdr.d1.d20); \
    SWAP_BYTES(hdr.d1.d21); \
    SWAP_BYTES(hdr.d1.d22); \
    SWAP_BYTES(hdr.d1.d23); \
} \
 \ 
table NAME##_swap_bytes1_tbl { \
    actions = { NAME##_swap_bytes1; } \
    const default_action = NAME##_swap_bytes1(); \
} \
 \
action NAME##_swap_bytes2() { \
    SWAP_BYTES(hdr.d0.d24); \
    SWAP_BYTES(hdr.d0.d25); \
    SWAP_BYTES(hdr.d0.d26); \
    SWAP_BYTES(hdr.d0.d27); \
    SWAP_BYTES(hdr.d0.d28); \
    SWAP_BYTES(hdr.d0.d29); \
    SWAP_BYTES(hdr.d0.d30); \
    SWAP_BYTES(hdr.d0.d31); \
 \
    SWAP_BYTES(hdr.d1.d24); \
    SWAP_BYTES(hdr.d1.d25); \
    SWAP_BYTES(hdr.d1.d26); \
    SWAP_BYTES(hdr.d1.d27); \
    SWAP_BYTES(hdr.d1.d28); \
    SWAP_BYTES(hdr.d1.d29); \
    SWAP_BYTES(hdr.d1.d30); \
    SWAP_BYTES(hdr.d1.d31); \
} \
 \
table NAME##_swap_bytes2_tbl { \
    actions = { NAME##_swap_bytes2; } \
    const default_action = NAME##_swap_bytes2(); \
}

#define APPLY_SWAP_BYTES1(NAME) \
NAME##_swap_bytes1_tbl.apply()

// curiously, this triggers a compiler bug when I use it in ingress
#define APPLY_SWAP_BYTES2(NAME) \
NAME##_swap_bytes2_tbl.apply()

#endif /* _HTONNTOH_ */

