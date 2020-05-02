/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#include "Endpoint.hpp"
#include "Reducer.hpp"

#include <gflags/gflags.h>

#include <iostream>
#include <chrono>

DEFINE_int32(warmup,   0, "Number of warmup iterations to run before timing.");
DEFINE_int32(iters,    1, "Number of timed iterations to run.");
DEFINE_int64(size, 65536, "Size of buffer to reduce.");

int main(int argc, char * argv[]) {
  gflags::ParseCommandLineFlags(&argc, &argv, true);

  // Initialize RDMA NIC
  Endpoint e;

  // Connect to other nodes
  Reducer r(e);

  //
  // allocate buffer that's registered with the NIC
  //
  
  // allocate buffer at same address on each node
  auto mr = e.allocate_at_address((void*) 0x0000100000000000, FLAGS_size);

  // // allocate buffer using zero-based addressing
  // // auto mr = e.allocate_zero_based(FLAGS_size);

  //
  // perform reduction
  //
  
  // perform warmup iterations
  std::cout << "Starting warmup iterations...\n";
  for (int i = 0; i < FLAGS_warmup; ++i) {
    r.allreduce(mr, mr->addr, FLAGS_size);
  }

  // perform timed iterations
  std::cout << "Starting timed iterations...\n";
  for (int i = 0; i < FLAGS_iters; ++i) {
    auto start_time = std::chrono::high_resolution_clock::now();
    r.allreduce(mr, mr->addr, FLAGS_size);
    auto end_time = std::chrono::high_resolution_clock::now();

    auto time_difference_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - start_time).count();
    double rate_in_Gbps = 8.0 * FLAGS_size / time_difference_ns;

    std::cout << "Iteration " << i << ": "
              << FLAGS_size << " bytes in "
              << time_difference_ns << " ns == "
              << rate_in_Gbps << " Gbps\n";
  }

  //
  // shutdown
  //
  
  std::cout << "Done.\n";
  e.free(mr);
  return 0;
}
