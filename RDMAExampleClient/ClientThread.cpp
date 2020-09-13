// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#include <thread>
#include <chrono>
#include <mutex>
#include <algorithm>
#include <sstream>

#include <x86intrin.h>

#include "Connections.hpp"
#include "ClientThread.hpp"

//#define DEBUG
//const bool DEBUG = true;
const bool DEBUG = false;

DEFINE_bool(connect_to_server, false, "By default, format packets for switch; if set, format for server for debugging.");
DEFINE_double(timeout, 0.001, "Retransmission timeout in seconds. Set to 0 to disable retransmission.");

ClientThread::ClientThread(Reducer * reducer, int64_t thread_id)
  : reducer(reducer)
  , thread_id(thread_id)
  , completion_queue(nullptr)
  , queue_pairs(FLAGS_slots_per_core, nullptr)
  , rkeys(FLAGS_slots_per_core, 0)
  , send_sges(FLAGS_slots_per_core)
  , send_wrs(FLAGS_slots_per_core)
  , recv_wrs(FLAGS_slots_per_core * 2)
  , base_pool_index(thread_id * FLAGS_slots_per_core) // first slot this thread is responsible for
#ifdef ENABLE_RETRANSMISSION
  , timeouts(FLAGS_slots_per_core)
  , timeout_ticks(0)
  , retransmission_count(0)
#endif
  , indices(FLAGS_slots_per_core, 0)
  , pointers(FLAGS_slots_per_core, nullptr)
  , base_pointer(nullptr)
  , thread_start_pointer(nullptr)
  , thread_end_pointer(nullptr)
  , start_index(0)
  , end_index(0)
  , outstanding_operations(0)
{
  std::cout << "Constructing thread " << thread_id << std::endl;

  // convert double timeout to timestamp count
  timeout_ticks = FLAGS_timeout * reducer->endpoint.ticks_per_sec;
  std::cout << "Timeout is " << FLAGS_timeout << " seconds, "
            << timeout_ticks << " ticks."
            << std::endl;
    
  // copy in connection info
  completion_queue = reducer->connections.completion_queues[thread_id];
  std::copy(&reducer->connections.queue_pairs[FLAGS_slots_per_core * thread_id],
            &reducer->connections.queue_pairs[FLAGS_slots_per_core * (thread_id + 1)],
            queue_pairs.begin());
  std::copy(&reducer->connections.rkeys[FLAGS_slots_per_core * thread_id],
            &reducer->connections.rkeys[FLAGS_slots_per_core * (thread_id + 1)],
            rkeys.begin());
  // for (int i = 0; i < FLAGS_slots_per_core; ++i) {
  //   std::cout << "Thread " << thread_id <<
  //             << " handling QP " << queue_pairs[i]->qp_num
  //             << std::endl;
  // }

  // initialize and post recv_wrs
  std::cout << "Posting initial receives..." << std::endl;
  for (int i = 0; i < FLAGS_slots_per_core; i++) {
    recv_wrs[i].wr_id = (thread_id << 16) | i;
    recv_wrs[i].next = nullptr;
    recv_wrs[i].sg_list = nullptr; // no receive data; just want completion
    recv_wrs[i].num_sge = 0;
    reducer->connections.post_recv(queue_pairs[i % FLAGS_slots_per_core], &recv_wrs[i]);
  }

  // initialize send_sges and send_wrs
  for (int i = 0; i < FLAGS_slots_per_core; i++) {
    // initialize SGE; just have to fill in address later
    send_sges[i].addr = 0;
    send_sges[i].length = FLAGS_message_size;
    send_sges[i].lkey = reducer->connections.memory_region->lkey;

    // initialize WR
    std::memset(&send_wrs[i], 0, sizeof(ibv_send_wr));
    send_wrs[i].wr_id = (thread_id << 16) | i;
    send_wrs[i].next = nullptr;
    send_wrs[i].sg_list = &send_sges[i];
    send_wrs[i].num_sge = 1;
    send_wrs[i].opcode = IBV_WR_RDMA_WRITE_WITH_IMM;
    //send_wrs[i].send_flags = IBV_SEND_SIGNALED; // TODO: do this periodically
    //send_wrs[i].send_flags = IBV_SEND_SIGNALED | IBV_SEND_FENCE; // TODO: do signal periodically
    send_wrs[i].send_flags = IBV_SEND_SIGNALED; // TODO: do signal periodically

    send_wrs[i].wr.rdma.remote_addr = 0; // will be filled in later

    // compute shifted pool index. LSB is slot flag. Set slot flag to
    // 1 initially; will be flipped to 0 before the first message is
    // posted.
    uint32_t shifted_pool_index = (((FLAGS_slots_per_core * thread_id + i)     // base message-sized pool index
                                    * (FLAGS_message_size / FLAGS_packet_size) // shifted to convert to packet-sized pool index
                                    * 2)                                       // leave space for slot bit
                                   | 1);                                       // set slot bit initially

    if (!FLAGS_connect_to_server) {
      // write shifted pool index into lower 15 bits of rkey.
      std::cout << "Using rkey " << shifted_pool_index << " for remote rkey " << rkeys[i] << std::endl;
      send_wrs[i].wr.rdma.rkey = shifted_pool_index;
    } else {
      // use remote rkey for debugging
      send_wrs[i].wr.rdma.rkey = rkeys[i];
    }
    
    // for debugging, write shifted pool index into immediate field.
    send_wrs[i].imm_data = shifted_pool_index;
  }  
}

void ClientThread::operator()() {
  std::cout << "Running thread " << thread_id << std::endl;
  while (true) { 
    // wait at barrier to start
    reducer->barrier.wait();

    // if a shutdown is signaled, halt
    if (reducer->shutdown) {
      std::cout << "Thread " << thread_id << " shutting down." << std::endl;
      return;
    }

    //
    // start reduction
    //
    compute_thread_pointers();

    // std::string s;
    // std::stringstream ss(s);
    // ss << "Thread " << thread_id
    //    << " (" << std::this_thread::get_id() << ")"
    //    << " reduction " << reducer->reduction_id
    //    << " sending from " << thread_start_pointer
    //    << " to " << thread_end_pointer
    //    << " of " << reducer->src_buffer
    //    << " length " << (void*) reducer->length << " floats"
    //    << std::endl;
    // std::cout << ss.str();

    post_initial_writes();
    run();


    //std::cout << "Thread " << thread_id << ": All operations complete." << std::endl;
    
    // wait at barrier again to indicate reduction is complete
    reducer->barrier.wait();
  }
}


void ClientThread::post_initial_writes() {
  if (DEBUG) std::cout << "Posting initial writes...." << std::endl;

  for (int i = 0; i < FLAGS_slots_per_core; ++i) {
    post_next_send_wr(i);
  }
}

void ClientThread::post_next_send_wr(int i) {
  if (pointers[i] < thread_end_pointer) {
    // point at start of this message's data
    send_sges[i].addr = (intptr_t) pointers[i];

    // figure out how big this message should be
    uint32_t truncated_message_length = (thread_end_pointer - pointers[i]) * sizeof(float);
    send_sges[i].length = std::min((uint32_t) FLAGS_message_size,
                                   truncated_message_length);

    // set packet-scale pool index in lower 15 bits of rkey. The pool
    // index is calculated in construtor; here we just flip the slot
    // bit. (slot bit is initialized to 1 in constructor, so first
    // packet will have slot 0 after this flip)
    if (!FLAGS_connect_to_server) {
      send_wrs[i].wr.rdma.rkey ^= 1; // flip slot bit in LSB
    } else {
      // use immediate instead for debugging
      send_wrs[i].imm_data ^= 1; // flip slot bit in LSB
    }
    
    //set destination address
    // if we use buffers allocated at the same address on each node
    send_wrs[i].wr.rdma.remote_addr = (intptr_t) pointers[i];
    // // if we use 0-indexed memory regions
    // send_wrs[i].wr.remote_addr = (intptr_t) indices[i];

#ifdef ENABLE_RETRANSMISSION
    if (DEBUG) std::cout << "Removing " << i << " from timeout queue." << std::endl;
    // remove from timeout queue
    timeouts.remove(i);
#endif
    
    // post
    if (DEBUG) std::cout << ">>>>>>>>>>>>>>>>              Thread " << thread_id
                         << " QP " << queue_pairs[i]->qp_num
                         << " index " << i 
                         << " posting send from " << (void*) send_sges[i].addr
                         << " len " << (void*) send_sges[i].length
                         << " slot " << (void*) (send_wrs[i].wr.rdma.rkey & 1)
                         << " rkey " << (void*) send_wrs[i].wr.rdma.rkey
                 //<< " qp " << send_wrs[i].
                         << std::endl;
    reducer->connections.post_send(queue_pairs[i], &send_wrs[i]);
    if (DEBUG) std::cout << "Posting send successful...." << std::endl;
    
    // increment pointer and indices
    // increment by number of floats per message * number of slots this core is handling
    pointers[i] += FLAGS_slots_per_core * (FLAGS_message_size / sizeof(float)); // TODO: correct?
    indices[i]  += FLAGS_slots_per_core * (FLAGS_message_size / sizeof(float));

    
    // record that this send was enqueued.
    //
    // TODO: ideally this would be done on the completion, but I don't
    // want to have to disambiguate between the initial send and
    // retransmissions.
    --outstanding_operations;
  }
}

#ifdef ENABLE_RETRANSMISSION
void ClientThread::repost_send_wr(int i) {
  // count retransmission
  ++retransmissions;

  // ensure this WR is removed from timeout queue
  if (DEBUG) std::cout << "Removing " << i << " from timeout queue before reposting." << std::endl;
  timeouts.remove(i);

  // repost
  if (DEBUG) std::cout << ">>>>>>>>>>>>>>>>              Thread " << thread_id
               //std::cout << ">>>>>>>>>>>>>>>>              Thread " << thread_id
                       << " QP " << queue_pairs[i]->qp_num
                       << " index " << i
                       << " re-posting send from " << (void*) send_sges[i].addr
                       << " len " << (void*) send_sges[i].length
                       << " slot " << (void*) (send_wrs[i].wr.rdma.rkey & 1)
                       << " rkey " << (void*) send_wrs[i].wr.rdma.rkey
                       << " retransmissions " << retransmissions
                       << std::endl;
  reducer->connections.post_send(queue_pairs[i], &send_wrs[i]);

  // count retransmission
  ++retransmission_count;
  
  if (DEBUG) std::cout << "Re-posting send successful...." << std::endl;
}
#endif

void ClientThread::handle_recv_completion(const ibv_wc & wc, const uint64_t timestamp) {
  if (DEBUG) std::cout << "Got RECV completion for " << (void*) wc.wr_id
                       << " for QP " << wc.qp_num
                       << " source " << wc.src_qp
                       << std::endl;
  
  // get QP index
  int qp_index = (wc.wr_id & 0xffff) % FLAGS_slots_per_core;

  // repost recv wr
  reducer->connections.post_recv(queue_pairs[qp_index], &recv_wrs[qp_index]);

  // post next send wr for this slot
  post_next_send_wr(qp_index);

  // record that this receive completed
  --outstanding_operations;
}

void ClientThread::handle_write_completion(const ibv_wc & wc, const uint64_t timestamp) {
  if (DEBUG) std::cout << "Got WRITE completion for " << (void*) wc.wr_id
                       << " for QP " << wc.qp_num
                       << " source " << wc.src_qp
                       << std::endl;

  // get QP index
  int qp_index = (wc.wr_id & 0xffff) % FLAGS_slots_per_core;

#ifdef ENABLE_RETRANSMISSION
  if (DEBUG) std::cout << "Adding " << qp_index
                       << " to timeout queue at timestamp " << timestamp
                       << "." << std::endl;
  // add to timeout queue
  timeouts.push(qp_index, timestamp);
#endif
}

#ifdef ENABLE_RETRANSMISSION
void ClientThread::check_for_timeouts(const uint64_t timestamp) {
  int qp_index = -1;
  uint64_t old_timestamp = 0;

  //if (DEBUG) std::cout << "Checking for timeouts at timestamp " << timestamp << std::endl;
  
  // get oldest queue entry
  std::tie(qp_index, old_timestamp) = timeouts.bottom();
  
  // if entry has timed out
  if ((qp_index != -1) &&
      (timestamp - old_timestamp > timeout_ticks)) {
    if (DEBUG) std::cout << "Detected timeout for  " << qp_index
                         << " at " << old_timestamp
                         << " difference " << timestamp - old_timestamp
                         << " compared with " << timeout_ticks
                         << ": " << ((timestamp - old_timestamp) > timeout_ticks)
                         << "; reposting...."
                         << std::endl;
    repost_send_wr(qp_index);
  }
}
#endif

void ClientThread::run() {
  const int max_entries = FLAGS_slots_per_core;
  std::vector<ibv_wc> completions(max_entries);

  while (outstanding_operations > 0) {
#ifdef ENABLE_RETRANSMISSION
    // get current timestamp counter value
    // TODO: have NIC generate timestamps
    const uint64_t timestamp = __rdtsc();
#else
    const uint64_t timestamp = 0;
#endif
    
    // check for completions
    int retval = ibv_poll_cq(completion_queue, max_entries, &completions[0]);

    if (retval < 0) {
      std::cerr << "Failed polling completion queue with status " << retval << std::endl;
      exit(1);
    } else if (retval > 0) {
      if (DEBUG) std::cout << "Got " << retval << " completions." << std::endl;
      for (int i = 0; i < retval; ++i) {
        if (completions[i].status != IBV_WC_SUCCESS) {
          std::cerr << "Got eror completion for " << (void*) completions[i].wr_id
                    << " with status " << ibv_wc_status_str(completions[i].status)
                    << std::endl;
          exit(1);
        } else {
          // success! 
          if (completions[i].opcode & IBV_WC_RECV) { // match on any RECV completion
            handle_recv_completion(completions[i], timestamp);
          } else if (completions[i].opcode == IBV_WC_RDMA_WRITE) { // this includes RDMA_WRITE_WITH_IMM
            handle_write_completion(completions[i], timestamp);
          } else {
            std::cerr << "Got unknown successful completion with ID " << (void*) completions[i].wr_id
                      << " for QP " << completions[i].qp_num
                      << " source " << completions[i].src_qp
                      << "; continuing..."
                      << std::endl;
            //exit(1);
          }
        } 
      }
    }

#ifdef ENABLE_RETRANSMISSION
    if (timeout_ticks != 0) {
      check_for_timeouts(timestamp);
    }
#endif
  }
}


void ClientThread::compute_thread_pointers() {
  // round up message count for non-multiple-of-message-size buffers,
  // and send 1 message even if length is 0 for barrier
  const int64_t total_messages = ((reducer->length * (int64_t) sizeof(float) - 1) / FLAGS_message_size) + 1;


  const int64_t total_slots = FLAGS_cores * FLAGS_slots_per_core;
  
  // threads send a base number of messages, plus an adjustment
  // to capture non-FLAGS_cores-divisible message counts
  const int64_t base_messages_per_thread = total_messages / FLAGS_cores; //total_slots;
  const int64_t adjustment               = total_messages % FLAGS_cores; //total_slots;
        
  // this thread sends total_messages / FLAGS_cores messages,
  // plus one more to spread the adjustment evenly over threads
  // as necessary, starting from thread 0
  const int64_t adjusted_messages_per_thread = (base_messages_per_thread +
                                                (thread_id < adjustment));

  // this thread's first message index is the base index, plus
  // the adjustments required by the previous threads
  const int64_t start_message_index = ((thread_id * base_messages_per_thread) +
                                       std::min(thread_id, adjustment));

  // this is 1+ the last message index we will reduce
  const int64_t end_message_index = start_message_index + adjusted_messages_per_thread;

  // compute pointers into buffer, ensuring that we don't run
  // off the end of the buffer with the last message
  base_pointer = reducer->src_buffer;
  thread_start_pointer = reducer->src_buffer + (start_message_index * FLAGS_message_size / sizeof(float));
  thread_end_pointer   = std::min(thread_start_pointer + (end_message_index * FLAGS_message_size / sizeof(float)),
                                  reducer->src_buffer + reducer->length);

  // initialize per-slot indices/pointers for this thread
  for (int i = 0; i < FLAGS_slots_per_core; ++i) {
    indices[i] = start_message_index + i;
    pointers[i] = thread_start_pointer + i * FLAGS_message_size / sizeof(float);

    // std::cout << " thread_id: " << thread_id
    //           << " total_messages: " << total_messages
    //           << " base_messages_per_thread: " << base_messages_per_thread
    //           << " adjustment: " << adjustment
    //           << " adjusted_messages_per_thread: " << adjusted_messages_per_thread
    //           << " start_message_index: " << start_message_index
    //           << " end_message_index: " << end_message_index
    //           << " outstanding_operations: " << outstanding_operations
    //           << " slot: " << i
    //           << " index: " << indices[i]
    //           << " start_pointer: " << pointers[i]
    //           << " end pointer: " << thread_end_pointer
    //           << std::endl;

  }

  // initialize count of expected sends and receives
  // (don't really need to count sends, since they're followed by receives, but whatever)
  outstanding_operations = 2 * (end_message_index - start_message_index);

  std::cout << " thread_id: " << thread_id
            << " total_messages: " << total_messages
            << " base_messages_per_thread: " << base_messages_per_thread
            << " adjustment: " << adjustment
            << " adjusted_messages_per_thread: " << adjusted_messages_per_thread
            << " start_message_index: " << start_message_index
            << " end_message_index: " << end_message_index
            << " outstanding_operations: " << outstanding_operations
#ifdef ENABLE_RETRANSMISSION
            << " retransmissions so far: " << retransmission_count
#endif
            << std::endl;
}

