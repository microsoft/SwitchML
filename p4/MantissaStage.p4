/********************************************************
*                                                       *
*   Copyright (C) Microsoft. All rights reserved.       *
*                                                       *
********************************************************/

#ifndef _MANTISSA_STAGE_
#define _MANTISSA_STAGE_

#include "types.p4"
#include "headers.p4"

#include "MantissaSum.p4"

// Mantissa stage value calculator
//
// Each control handles two mantissas.
control MantissaStage(
    inout mantissa_t mantissa0a,
    inout mantissa_t mantissa0b,
    inout mantissa_t mantissa1a,
    inout mantissa_t mantissa1b,
    inout mantissa_t mantissa2a,
    inout mantissa_t mantissa2b,
    inout mantissa_t mantissa3a,
    inout mantissa_t mantissa3b,
    in header_t hdr,
    inout ingress_metadata_t ig_md) {

    MantissaSum() sum0;
    MantissaSum() sum1;
    MantissaSum() sum2;
    MantissaSum() sum3;
    
    apply {
        sum0.apply(mantissa0a, mantissa0b, hdr, ig_md);
        sum1.apply(mantissa1a, mantissa1b, hdr, ig_md);
        sum2.apply(mantissa2a, mantissa2b, hdr, ig_md);
        sum3.apply(mantissa3a, mantissa3b, hdr, ig_md);
    }
}

#endif /* _MANTISSA_STAGE_ */
