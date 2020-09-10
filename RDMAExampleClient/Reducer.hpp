/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#ifndef __REDUCER__
#define __REDUCER__

#include <thread>
#include <chrono>
#include <mutex>
#include <condition_variable>
#include <sstream>

#include "Endpoint.hpp"
#include "Connections.hpp"
#include "Barrier.hpp"

class ClientThread;

class Reducer {
private:
  Connections & connections;
  Endpoint & endpoint;

  std::vector<std::thread> threads;
  Barrier barrier;
  
  bool shutdown;      /// flag to signal to workers that they should shut down
  float * src_buffer; /// pointer to current buffer being reduced
  float * dst_buffer; /// pointer to current buffer being reduced
  int64_t length;     /// number of floats
  ibv_mr * dst_mr;    /// MR for dest buffer
  int64_t reduction_id; /// ID of this reduction
  
  friend class ClientThread;
  
public:
  Reducer(Connections & c);

  ~Reducer();

  /// perform allreduce on a buffer
  void allreduce_inplace(ibv_mr * mr, float * address, int64_t len);
};

#endif //  __REDUCER__
