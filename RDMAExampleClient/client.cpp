// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#include "common.hpp"
#include "Endpoint.hpp"
#include "Connections.hpp"
#include "Reducer.hpp"

#include <gflags/gflags.h>

#include <mpi.h>

#include <iostream>
#include <iomanip>
#include <chrono>
#include <cmath>

#include <arpa/inet.h>

DEFINE_int32(warmup,     0, "Number of warmup iterations to run before timing.");
DEFINE_int32(iters,      1, "Number of timed iterations to run.");
DEFINE_int64(length, 65536, "Length of buffer to reduce in 4-byte int32s.");

DEFINE_bool(wait, false, "Wait after start for debugger to attach.");

DEFINE_bool(test_grpc, false, "Just test GRPC at localhost and exit.");

DEFINE_bool(print_array, false, "Print entire array.");
DEFINE_bool(verbose_errors, false, "Print each individual array element that was incorrectly aggregated.");
DEFINE_int32(max_errors, 16, "Max number of errors to print.");
DEFINE_bool(check_every_time, false, "Check array every time.");

void initialize(int rank, int size, int * buf, size_t buffer_length) {
  for (int64_t i = 0; i < buffer_length; ++i) {
    if (0 == (i % (FLAGS_packet_size / sizeof(int)))) {
      buf[i] = 0x11223344;
    // } else if (0 == (i % 2)) {
    //   buf[i] = (i+1) / (FLAGS_packet_size / sizeof(int));
    // } else {
    //   buf[i] = -(i-1) / (FLAGS_packet_size / sizeof(int));
    // }
    // } else if (5 == (i % 64)) {
    //   buf[i] = 0;
    } else if (0 == (i % 2)) {
      buf[i] = -i; //-i;
    } else {
      buf[i] = -i;
    }

    // convert to network byte order
    buf[i] = htonl(buf[i]);
  }
}

int check(int rank, int size, int iters, int * buf, size_t buffer_length) {
  // generate multiplier by computing size ^ (FLAGS_warmup + iters)
  // do it by hand with integers rather than with std::pow to avoid
  // double<->int conversion edge cases.
  int32_t multiplier = 1;
  int32_t base = size;
  uint32_t exponent = FLAGS_warmup + iters;
  while (exponent) {
      if (exponent & 1) {
        multiplier *= base;
      }
      exponent >>= 1;
      base *= base;
  }

  if (FLAGS_print_array || FLAGS_verbose_errors) {
    std::cout << "For iteration " << iters << " multiplier is " << multiplier << std::endl;
  }
  
  size_t error_count = 0;
  for (int i = 0; i < FLAGS_length; ++i) {
    // convert to host byte order
    int received = ntohl(buf[i]);

    // figure out what we sent in the first iteration
    int original = 0;
    if (0 == (i % (FLAGS_packet_size / sizeof(int)))) {
      original = 0x11223344;
    // } else if (0 == (i % 2)) {
    //   original = (i+1) / (FLAGS_packet_size / sizeof(int));
    // } else {
    //   original = -(i-1) / (FLAGS_packet_size / sizeof(int));
    // }
    // } else if (5 == (i % 64)) { // BUG: this element is corrupt in current design?
    //   buf[i] = 0;
    } else if (0 == (i % 2)) {
      original = -i; //-i;
    } else {
      original = -i;
    }
    
    // use that to compute expected reduction value after however many iterations we did
    int expected = original * multiplier;


    if (FLAGS_print_array) {
      if (rank == 0) {
        std::cout << std::setw(10) << i
                  << ": original " << std::setw(10) << original
                  << "/0x" << std::setw(8) << std::hex << original << std::dec
                  << " expected " << std::setw(10) << expected
                  << "/0x" << std::setw(8) << std::hex << expected << std::dec
                  << ", got " << std::setw(10) << received
                  << "/0x" << std::setw(8) << std::hex << received << std::dec;
        if (received != expected) {
          std::cout << " MISMATCH!";
        }
        std::cout << std::endl;
      }
    }

    // check for mismatches
    if (received != expected) {
      ++error_count;
      if (FLAGS_verbose_errors && (error_count < FLAGS_max_errors)) {
        std::cout << "After " << iters << " iterations, mismatch at index " << i
                  << ": original " << original << "/0x" << std::hex << original << std::dec
                  << " expected " << expected << "/0x" << std::hex << expected << std::dec
                  << ", got " << received << "/0x" << std::hex << received << std::dec
                  << " difference " << received - expected << "/0x" << std::hex << received - expected << std::dec
                  << std::endl;
      } else if ((FLAGS_max_errors > 0) && (error_count == FLAGS_max_errors)) {
        std::cout << "Stopping after printing " << FLAGS_max_errors << " errors." << std::endl;
      }
    }
  }

  if (error_count == 0) {
    std::cout << "No errors detected after " << iters << " iters." << std::endl;
  } else {
    std::cout << "ERROR: after " << iters << " iters, incorrect values in " << error_count
              << " of " << FLAGS_length
              << " elements."
              << std::endl;
  }

  return error_count;
}

int main(int argc, char * argv[]) {
  gflags::ParseCommandLineFlags(&argc, &argv, true);

  if (FLAGS_wait) {
    wait_for_attach();
  }

  // Set up MPI context for exchanging RDMA context information.
  std::cout << "Initializing MPI..." << std::endl;
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
  //const size_t buffer_length = 1L << 30; // # of floats
  auto mr = e.allocate_at_address((void*) 0x0000100000000000,
                                  buffer_length);

  // // allocate buffer using zero-based addressing (doesn't work yet)
  // auto mr = e.allocate_zero_based(buffer_length);

  // initialize vector with something easy to identify
  initialize(rank, size, (int*) mr->addr, buffer_length);
  
  // Connect to other nodes and exchange memory region info
  Connections c(e, mr, rank, size);
  c.connect();
  
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
  int overall_error_count = 0;
  for (int i = 0; i < FLAGS_iters; ++i) {
    auto start_time = std::chrono::high_resolution_clock::now();
    r.allreduce_inplace(mr, (float*) mr->addr, FLAGS_length);
    auto end_time = std::chrono::high_resolution_clock::now();

    uint64_t time_difference_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - start_time).count();
    uint64_t min_time_difference_ns = 0;
    MPI_CHECK(MPI_Allreduce(&time_difference_ns, &min_time_difference_ns, 1, MPI_UINT64_T, MPI_MAX, MPI_COMM_WORLD));
    if (0 == rank) {
      double rate_in_Gbps = 8.0 * FLAGS_length * sizeof(int32_t) / time_difference_ns;
      std::cout << "Iteration " << i << ": "
                << FLAGS_length * sizeof(int32_t) << " bytes in "
                << time_difference_ns << " ns == "
                << rate_in_Gbps << " Gbps goodput\n";

    }
    if (FLAGS_check_every_time) {
      std::cout << "Checking for errors." << std::endl;
      overall_error_count += check(rank, size, i+1,  (int*) mr->addr, FLAGS_length);
    }
  }

  //
  // verify (if we didn't do it every time)
  //
  if (FLAGS_check_every_time) {
    if (overall_error_count) {
      std::cout << "Found a total of " << overall_error_count << " mismatches." << std::endl;
    } else {
      std::cout << "No errors found in any iteration." << std::endl;
    }
  } else {
    //std::cout << "Checking for errors." << std::endl;
    check(rank, size, FLAGS_iters, (int*) mr->addr, FLAGS_length);
  }

  //
  // shutdown
  //

  MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
  MPI_CHECK(MPI_Finalize());
    
  //std::cout << "Done.\n";
  e.free(mr);
  return 0;
}
