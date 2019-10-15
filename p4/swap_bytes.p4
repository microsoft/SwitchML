/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _HTONNTOH_
#define _HTONNTOH_

// helper macro to swap bytes
#define BYTE_SWAP(NAME) \
(NAME[7:0] ++ NAME[15:8] ++ NAME[23:16] ++ NAME[31:24])

// TODO: ideally this would not swap values between words, but the
// compiler doesn't like that right now.
#define HTONNTOH(NN, AA, BB, CC, DD) \
    NN##.d##BB = BYTESWAP(NN##.d##AA); \
    NN##.d##AA = BYTESWAP(NN##.d##BB); \
    NN##.d##DD = BYTESWAP(NN##.d##CC); \
    NN##.d##CC = BYTESWAP(NN##.d##DD)

#endif /* _HTONNTOH_ */

