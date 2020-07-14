/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#ifndef __CLIENTTHREAD__
#define __CLIENTTHREAD__

//#include "Endpoint.hpp"
#include "Reducer.hpp"

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
  
  std::vector<int64_t> indices;
  std::vector<float *> pointers;
  
  float * base_pointer;
  float * thread_start_pointer;
  float * thread_end_pointer;

  int64_t start_index;
  int64_t end_index;

  int64_t outstanding_operations;
  
  void post_initial_writes();
  void post_next_send_wr(int i);
  void handle_recv_completion(const ibv_wc &);
  void handle_write_completion(const ibv_wc &);
  void run();
  
  void compute_thread_pointers();
  
public:
  ClientThread(Reducer * reducer, int64_t thread_id);

  void operator()();
};


#endif //  __CLIENTTHREAD__
