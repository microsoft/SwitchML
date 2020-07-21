/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#include "common.hpp"
#include "Endpoint.hpp"
#include "Connections.hpp"
#include "Reducer.hpp"

#include <gflags/gflags.h>

#include <mpi.h>

#include <iostream>
#include <chrono>

#include <arpa/inet.h>

DEFINE_int32(warmup,     0, "Number of warmup iterations to run before timing.");
DEFINE_int32(iters,      1, "Number of timed iterations to run.");
DEFINE_int64(length, 65536, "Length of buffer to reduce in 4-byte int32s.");

DEFINE_bool(wait, false, "Wait after start for debugger to attach.");

DEFINE_bool(test_grpc, false, "Just test GRPC at localhost and exit.");

int main(int argc, char * argv[]) {
  gflags::ParseCommandLineFlags(&argc, &argv, true);

  if (FLAGS_wait) {
    wait_for_attach();
  }

  // Set up MPI context for exchanging RDMA context information.
  MPI_CHECK(MPI_Init(&argc, &argv)); 

  // get MPI job geometry
  int rank = 0;
  MPI_CHECK(MPI_Comm_rank(MPI_COMM_WORLD, &rank));
  int size = 0;
  MPI_CHECK(MPI_Comm_size(MPI_COMM_WORLD, &size));

  // Initialize RDMA NIC
  Endpoint e;

  //
  // allocate buffer that's registered with the NIC
  //
  
  // allocate buffer at same address on each node
  const size_t buffer_length = 1L << 28; // # of floats
  auto mr = e.allocate_at_address((void*) 0x0000100000000000,
                                  buffer_length);

  // // allocate buffer using zero-based addressing
  // auto mr = e.allocate_zero_based(1L << 28);

  // initialize vector with something easy to identify
  int * buf = (int*) mr->addr;
  for (size_t i = 0; i < buffer_length; ++i) {
    if (0 == (i % (FLAGS_packet_size / sizeof(int)))) {
      buf[i] = 0x11223344;
    } else if (0 == (i % 2)) {
      buf[i] = i / (FLAGS_packet_size / sizeof(int));
    } else {
      buf[i] = -i / (FLAGS_packet_size / sizeof(int));
    }

    // convert to network byte order
    buf[i] = htonl(buf[i]);
  }

  
  // Connect to other nodes and exchange memory region info
  Connections c(e, mr, rank, size);

  //
  // perform reduction
  //
  Reducer r(c);

  // perform warmup iterations
  std::cout << "Starting warmup iterations...\n";
  for (int i = 0; i < FLAGS_warmup; ++i) {
    r.allreduce_inplace(mr, (float*) mr->addr, FLAGS_length);
  }

  // perform timed iterations
  std::cout << "Starting timed iterations...\n";
  for (int i = 0; i < FLAGS_iters; ++i) {
    auto start_time = std::chrono::high_resolution_clock::now();
    r.allreduce_inplace(mr, (float*) mr->addr, FLAGS_length);
    auto end_time = std::chrono::high_resolution_clock::now();

    auto time_difference_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - start_time).count();
    double rate_in_Gbps = 8.0 * FLAGS_length / time_difference_ns;

    std::cout << "Iteration " << i << ": "
              << FLAGS_length * sizeof(int32_t) << " bytes in "
              << time_difference_ns << " ns == "
              << rate_in_Gbps << " Gbps\n";
  }

  //
  // shutdown
  //

  MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
  MPI_CHECK(MPI_Finalize());
    
  std::cout << "Done.\n";
  e.free(mr);
  return 0;
}
