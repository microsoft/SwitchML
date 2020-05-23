/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#include "Reducer.hpp"
#include "ClientThread.hpp"

Reducer::Reducer(Connections & c)
  : connections(c)
  , endpoint(c.endpoint)
  , threads()
  , barrier(FLAGS_cores + 1) // FLAGS_cores worker threads plus master thread
  , shutdown(false)
  , src_buffer(nullptr)
  , dst_buffer(nullptr)
  , length(0)
  , dst_mr(nullptr)
  , reduction_id(-1) // incremented before first use, so initialize to -1
{
  unsigned int n = std::thread::hardware_concurrency();
  std::cout << n << " concurrent threads are supported.\n";

  // start threads
  for (int64_t thread_id = 0; thread_id < FLAGS_cores; ++thread_id) {
    std::cout << "Spawning thread " << thread_id << "\n";
    threads.push_back(std::thread(ClientThread(this, thread_id)));
  }
}

Reducer::~Reducer() {
  // tell threads to exit
  shutdown = true;
  barrier.wait();
  
  // wait for threads to exit
  for (auto & thread : threads) {
    thread.join();
  }
}

void Reducer::allreduce_inplace(ibv_mr * mr, float * address, int64_t len) {
  // set up input data for worker threads
  src_buffer   = address;
  dst_buffer   = address;
  length       = len;
  dst_mr       = mr;
  ++reduction_id;

  // enter barrier to start worker threads
  barrier.wait();

  // worker threads now compute
  
  // enter barrier to wait for worker threads to complete, and we're done
  barrier.wait();
}
