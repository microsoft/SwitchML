// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef __CLIENTTHREAD__
#define __CLIENTTHREAD__

//#include "Endpoint.hpp"
#include "Reducer.hpp"
#include "TimeoutQueue.hpp"

// enable retransmission
#define ENABLE_RETRANSMISSION

// enable pool index debugging
//#define DEBUG_POOL_INDEX

DECLARE_int32(cores);
DECLARE_int32(slots_per_core);
DECLARE_int32(message_size);


class ClientThread {
private:
  Reducer * reducer;
  const int64_t thread_id;
  
  ibv_cq * completion_queue;
  std::vector<ibv_qp *> queue_pairs;
  std::vector<int> rkeys;

  std::vector<ibv_sge> send_sges;
  std::vector<ibv_send_wr> send_wrs;
  std::vector<ibv_recv_wr> recv_wrs;
  const int32_t base_pool_index;
  
#ifdef ENABLE_RETRANSMISSION
  TimeoutQueue timeouts;
  uint64_t timeout_ticks;
  uint64_t retransmission_count;
#endif
  
  std::vector<int64_t> indices;
  std::vector<float *> pointers;
  
  float * base_pointer;
  float * thread_start_pointer;
  float * thread_end_pointer;

  int64_t start_index;
  int64_t end_index;

  int64_t outstanding_operations;
  int64_t retransmissions;

  const int32_t pool_index_message_mask;

#ifdef DEBUG_POOL_INDEX
  std::vector<int32_t> pool_index_log;
#endif
  
  void post_initial_writes();
  void post_next_send_wr(const int i);
#ifdef ENABLE_RETRANSMISSION
  void repost_send_wr(const int i);
#endif
  void handle_recv_completion(const ibv_wc &, const uint64_t timestamp);
  void handle_write_completion(const ibv_wc &, const uint64_t timestamp);
  void run();
  
  void compute_thread_pointers();

#ifdef ENABLE_RETRANSMISSION
  void check_for_timeouts(const uint64_t timestamp);
#endif

public:
  ClientThread(Reducer * reducer, int64_t thread_id);

  void operator()();
};


#endif //  __CLIENTTHREAD__
