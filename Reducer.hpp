/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#ifndef __REDUCER__
#define __REDUCER__

#include <infiniband/verbs.h>
#include <cstring>
#include <iostream>
#include <endian.h>
#include <gflags/gflags.h>

class Endpoint;

class Reducer {
private:

public:
  Reducer(Endpoint & e) { }
  //~Reducer();

  /// perform allreduce on a buffer
  void allreduce(ibv_mr * mr, void * address, size_t length) { }
};

#endif //  __REDUCER__
