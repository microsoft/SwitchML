// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef __CONNECTIONS__
#define __CONNECTIONS__

#include <infiniband/verbs.h>
#include <cstring>
#include <iostream>
#include <endian.h>
#include <gflags/gflags.h>
#include <vector>
#include <string>
#include <sstream>

#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>

#include <errno.h>
#include <unistd.h>

#include "Endpoint.hpp"
#include "GRPCClient.hpp"

DECLARE_bool(use_rc);

DECLARE_int32(cores);
DECLARE_int32(slots_per_core);

DECLARE_int32(message_size);
DECLARE_int32(packet_size);

DECLARE_string(server);
DECLARE_int32(port);

class Connections {
  //private:
public: // TODO: undo this as much as necessary

  /// information about local NIC
  Endpoint & endpoint;

  /// GRPC client to talk to coordinator
  GRPCClient grpc_client;
  
  /// constants for initializing queues
  static const int completion_queue_depth       = 256;  // need to handle concurrent send and receive completions on each queue
  static const int send_queue_depth             = 128;  // need to be able to post a send before we've processed the previous one's completion
  static const int receive_queue_depth          = 128;  // need to be able to receive immediate value notifications
  static const int scatter_gather_element_count = 1;    // how many SGE's do we allow per operation?
  static const int max_inline_data              = 16;   // how much inline data should we support?
  static const int max_dest_rd_atomic           = 0;    // how many outstanding reads/atomic ops are allowed? (remote end of qp, limited by card)
  static const int max_rd_atomic                = 0;    // how many outstanding reads/atomic ops are allowed? (local end of qp, limited by card)
  static const int min_rnr_timer                = 0x12; // from Mellanox RDMA-Aware Programming manual, for RC only; probably don't need to touch
  static const int timeout                      = 14;   // from Mellanox RDMA-Aware Programming manual, for RC only; probably don't need to touch
  static const int retry_count                  = 7;    // from Mellanox RDMA-Aware Programming manual, for RC only; probably don't need to touch
  static const int rnr_retry                    = 7;    // from Mellanox RDMA-Aware Programming manual, for RC only; probably don't need to touch

  /// Type of queue pair: RC or UC
  const ibv_qp_type qp_type;
  const ibv_mtu mtu;

  /// local memory region
  ibv_mr * memory_region;

  /// job geometry
  const int rank;
  const int size;
  uint64_t job_id;
  
  /// completion queues
  std::vector<ibv_cq*> completion_queues;

  /// one QP per slot
  std::vector<ibv_qp*> queue_pairs;
  std::vector<int32_t> rkeys;

  // functions to connect queue pairs
  void initialize_queue_pairs();
  void connect_queue_pairs();
  ibv_cq * create_completion_queue();
  ibv_qp * create_queue_pair(ibv_cq * completion_queue);

  void move_to_init(int);
  void move_to_rtr(int);
  void move_to_rts(int);

  // allow subclassing with different exchange methods
  virtual void exchange_connection_info();
  
  void resolve_server_addresses_to_gids();

  // data about neighbor queue pairs
  std::vector<ibv_gid> neighbor_gids;
  std::vector<uint32_t> neighbor_qpns;
  std::vector<uint32_t> neighbor_psns;
  std::vector<int32_t> neighbor_rkeys;

  
public:
  Connections(Endpoint & e, ibv_mr * mr, const int rank, const int size)
    : endpoint(e)
    , grpc_client(grpc::CreateChannel(FLAGS_server + ":" + std::to_string(FLAGS_port),
                                      grpc::InsecureChannelCredentials()))
    , qp_type(FLAGS_use_rc ? IBV_QPT_RC : IBV_QPT_UC) // default to UC; use RC if specified
    , mtu(FLAGS_packet_size >= 4096 ? IBV_MTU_4096 :
          FLAGS_packet_size >= 2048 ? IBV_MTU_2048 :
          FLAGS_packet_size >= 1024 ? IBV_MTU_1024 :
          FLAGS_packet_size >=  512 ? IBV_MTU_512 :
          IBV_MTU_256)
    , memory_region(mr)
    , rank(rank)
    , size(size)
    , job_id(-1)
    , completion_queues(FLAGS_cores, nullptr) // one completion queue per core
    , queue_pairs(FLAGS_cores * FLAGS_slots_per_core, nullptr) // create one queue pair per slot
    , rkeys(queue_pairs.size(), 0) // one rkey per queue pair to support parameter servers
    , neighbor_rkeys(FLAGS_cores * FLAGS_slots_per_core, 0)  // create one rkey per slot so we can use parameter servers
    , neighbor_gids(FLAGS_cores * FLAGS_slots_per_core)  // create one gid per slot so we can use parameter servers
    , neighbor_qpns(FLAGS_cores * FLAGS_slots_per_core, 0)
    , neighbor_psns(FLAGS_cores * FLAGS_slots_per_core, 0)
  {
    // do this later to support server overload
    //set_up_queue_pairs();
  }

  void connect() {
    initialize_queue_pairs();

    // In order to move the queues to RTR, we now need to exhange GID,
    // queue pair numbers, and initial packet sequence numbers with
    // our neighbors.
    exchange_connection_info();
    
    connect_queue_pairs();
  }

  static uint32_t gid_to_ipv4(const ibv_gid gid);
  static uint64_t gid_to_mac(const ibv_gid gid);
  static ibv_gid ipv4_to_gid(const int32_t ip);
  static ibv_gid mac_to_gid(const uint64_t mac);

  static void post_recv(ibv_qp * qp, ibv_recv_wr * wr) {
    ibv_recv_wr * bad_wr = nullptr;
    
    int retval = ibv_post_recv(qp, wr, &bad_wr);
    if (retval < 0) {
      std::cerr << "Error " << retval << " posting receive WR startgin at WR " << wr << " id " << (void*) wr->wr_id << std::endl;
      perror( "Error posting receive WR" );
      throw;
      exit(1);
    }
    
    if (bad_wr) {
      std::cerr << "Error posting receive WR at WR " << bad_wr << " id " << (void*) bad_wr->wr_id << std::endl;
      throw;
      exit(1);
    }
  }

  static void post_send(ibv_qp * qp, ibv_send_wr * wr) {
    ibv_send_wr * bad_wr = nullptr;

    int retval = ibv_post_send(qp, wr, &bad_wr);
    if (retval < 0) {
      std::cerr << "Error " << retval
                << " posting send WR starting at WR " << wr
                << " id " << (void*) wr->wr_id
                << ": " << strerror(errno)
                << std::endl;
      throw;
      exit(1);
    }
    
    if (bad_wr) {
      std::cerr << "Hmm. Error posting send WR at WR " << bad_wr
                << " id " << (void*) bad_wr->wr_id
                << " starting at WR " << wr
                << std::endl;
      throw;
      exit(1);
    }
  }

};

#endif //  __CONNECTIONS__
