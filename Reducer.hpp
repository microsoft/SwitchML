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
#include <vector>
#include <string>
#include <sstream>

#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>

#include "Endpoint.hpp"

DEFINE_int32(cores, 1, "Number of cores used for communication.");
DEFINE_int32(slots_per_core, 64, "How many slots per core should we use?");

DEFINE_string(servers, "", "Comma-separated list of IP addresses (not hostnames) for servers/switches to be used for this reduction.");


class Reducer {
private:
  Endpoint & endpoint;

  /// constants for initializing queues
  static const int completion_queue_depth       = 256;  // how many send + receive completions should we support?
  static const int send_queue_depth             = 16;   // how many operations per queue should we be able to enqueue at a time?
  static const int receive_queue_depth          = 1;    // only need 1 if we're just using non-immediate RDMA ops
  static const int scatter_gather_element_count = 1;    // how many SGE's do we allow per operation?
  static const int max_inline_data              = 16;   // how much inline data should we support?
  static const int max_dest_rd_atomic           = 0;    // how many outstanding reads/atomic ops are allowed? (remote end of qp, limited by card)
  static const int max_rd_atomic                = 0;    // how many outstanding reads/atomic ops are allowed? (local end of qp, limited by card)
  static const int min_rnr_timer                = 0x12; // from Mellanox RDMA-Aware Programming manual; probably don't need to touch
  static const int timeout                      = 14;   // from Mellanox RDMA-Aware Programming manual; probably don't need to touch
  static const int retry_count                  = 7;    // from Mellanox RDMA-Aware Programming manual; probably don't need to touch
  static const int rnr_retry                    = 7;    // from Mellanox RDMA-Aware Programming manual; probably don't need to touch

  /// completion queue, shared across all QPs
  ibv_cq * completion_queue;

  /// one QP per slot
  std::vector<ibv_qp*> queue_pairs;

public:
  Reducer(Endpoint & e)
    : endpoint(e)
    , completion_queue(nullptr)
    , queue_pairs()
  {
    // create shared completion queue
    completion_queue = ibv_create_cq(endpoint.context,
                                     completion_queue_depth,
                                     NULL,  // no user context
                                     NULL,  // no completion channel
                                     0);    // no completion channel vector
    if( !completion_queue ) {
      std::cerr << "Error creating completion queue!\n";
      exit(1);
    }

    // resolve server addresses to IPs and form GUIDs
    //
    // NOTE: this is a hack. all this code is just to parse IP
    // addresses from the command line so we can form GIDs. Ideally
    // we'd exchange this data over MPI or some other transport.
    std::stringstream server_stream(FLAGS_servers);
    std::vector<ibv_gid> server_gids;

    if (endpoint.gid_index != 3) {
      std::cerr << "Error: don't yet know how to form GIDs for non-UDP or non-IP-based GIDs (indexes other than 3)" << std::endl;
      exit(1);
    }
    
    while (server_stream.good()) {
      std::string server_name;
      std::getline(server_stream, server_name, ',');
      if (!server_name.empty()) {
        std::cout << "Found server IP " << server_name << "\n";

        // convert name to IP
        const addrinfo hints = {
          .ai_flags = (AI_V4MAPPED | AI_ADDRCONFIG | AI_NUMERICHOST),
          .ai_family = AF_INET, // IPv4 only for now
          .ai_socktype = 0,
          .ai_protocol = 0,
          .ai_addrlen = 0,
          .ai_addr = nullptr,
          .ai_canonname = nullptr,
          .ai_next = nullptr
        };
        addrinfo * result = nullptr;
        int retval = getaddrinfo(server_name.c_str(), nullptr, &hints, &result);
        if (retval != 0) {
          std::cerr << "Error getting address for " << server_name
                    << ": " << gai_strerror(retval)
                    << std::endl;
          exit(1);
        }

        uint64_t addr;
        for (addrinfo * rp = result; rp != nullptr; rp = rp->ai_next) {
          if (rp->ai_addr->sa_family == AF_INET) {
            auto addr_p = (sockaddr_in*) rp->ai_addr;
            addr = addr_p->sin_addr.s_addr;
            break;
            // std::cout << "Got addr len " << rp->ai_addrlen
            //           << " addr family " << (void*) addr_p->sin_addr.s_addr
            //           << " next " << rp->ai_next
            //           << "\n";
          }
        }
        freeaddrinfo(result);

        // convert IP to GID
        ibv_gid gid = {
          .global = {
            .subnet_prefix = 0,
            .interface_id = (addr << 32) | 0x00000000ffff0000
          }
        };

        // std::cout << "Got GID "
        //           << (void*) gid.global.subnet_prefix << " " << (void*) gid.global.interface_id
        //           << "\n";
        server_gids.push_back(gid);
      }
    }
    
    // create queue pairs---one per slot
    for (int i = 0; i < FLAGS_cores * FLAGS_slots_per_core; ++i) {

      //
      // first, create queue pair
      //
      
      ibv_qp_init_attr init_attributes;
      std::memset( &init_attributes, 0, sizeof( ibv_qp_init_attr ) );

      // use shared completion queue
      init_attributes.send_cq = completion_queue;
      init_attributes.recv_cq = completion_queue;

      // use "unreliable connected" model so we can ignore other side
      init_attributes.qp_type = IBV_QPT_UC;

      // only issue send completions if requested
      init_attributes.sq_sig_all = false;

      // set queue depths and WR parameters accoring to constants declared earlier
      init_attributes.cap.max_send_wr     = send_queue_depth;
      init_attributes.cap.max_recv_wr     = receive_queue_depth;
      init_attributes.cap.max_send_sge    = scatter_gather_element_count;
      init_attributes.cap.max_recv_sge    = scatter_gather_element_count;
      init_attributes.cap.max_inline_data = max_inline_data;

      // create queue pair
      ibv_qp * queue_pair = ibv_create_qp(endpoint.protection_domain, &init_attributes);
      if( !queue_pair ) {
        std::cerr << "Error creating queue pair!\n";
        exit(1);
      }

      //
      // next, move queue pair to INIT state
      //
      
      ibv_qp_attr attributes;
      std::memset(&attributes, 0, sizeof(attributes));

      // move to INIT
      attributes.qp_state = IBV_QPS_INIT;
      attributes.port_num = endpoint.port;
      attributes.pkey_index = 0;
      attributes.qp_access_flags = (IBV_ACCESS_LOCAL_WRITE |
                                    IBV_ACCESS_REMOTE_WRITE);
      int retval = ibv_modify_qp( queue_pair, &attributes,
                                  IBV_QP_STATE |
                                  IBV_QP_PORT |
                                  IBV_QP_PKEY_INDEX |
                                  IBV_QP_ACCESS_FLAGS );
      if( retval < 0 ) {
        perror( "Error setting queue pair to INIT" );
        exit(1);
      }
  
      /// in theory, we need to post an empty receive WR to proceed, but
      /// when we're doing RDMA-only stuff it seems to work without one.
      // bare_receives[i].wr_id = 0xdeadbeef;
      // bare_receives[i].next = NULL;
      // bare_receives[i].sg_list = NULL;
      // bare_receives[i].num_sge = 0;
      // post_receive( i, &bare_receives[i] );

      //
      // now, move queue pair to Ready-To-Receive state
      //
      
      // move to RTR
      std::memset(&attributes, 0, sizeof(attributes));
      attributes.qp_state           = IBV_QPS_RTR;
      attributes.dest_qp_num        = i; //remote_qp_num;
      attributes.rq_psn             = 0; //remote_psn;
      attributes.max_dest_rd_atomic = max_dest_rd_atomic;
      attributes.min_rnr_timer      = min_rnr_timer;

      // what packet size do we want?
      attributes.path_mtu = IBV_MTU_256;
      //attributes.path_mtu = IBV_MTU_512;
      //attributes.path_mtu = IBV_MTU_1024;

      attributes.ah_attr.is_global     = 1;
      attributes.ah_attr.dlid          = endpoint.port_attributes.lid; // not really necessary since using RoCE, not IB
      attributes.ah_attr.sl            = 0;
      attributes.ah_attr.src_path_bits = 0;
      attributes.ah_attr.port_num      = endpoint.port;

      attributes.ah_attr.grh.dgid                      = server_gids[i % server_gids.size()]; // round-robin through given GIDs
      attributes.ah_attr.grh.sgid_index                = endpoint.gid_index;
      attributes.ah_attr.grh.flow_label                = 0;
      attributes.ah_attr.grh.hop_limit                 = 0xFF;
      attributes.ah_attr.grh.traffic_class             = 1;
  
      retval = ibv_modify_qp( queue_pair, &attributes,
                              IBV_QP_STATE |
                              IBV_QP_PATH_MTU |
                              IBV_QP_DEST_QPN |
                              IBV_QP_RQ_PSN |
                              //IBV_QP_MAX_DEST_RD_ATOMIC | // uncomment this for RC
                              //IBV_QP_MIN_RNR_TIMER |      // uncomment this for RC
                              IBV_QP_AV
                              );
      if( retval < 0 ) {
        perror( "Error setting queue pair to RTR" );
        exit(1);
      }

      //
      // finally, move queue to Ready-To-Send state
      //
  
      // move to RTS
      std::memset(&attributes, 0, sizeof(attributes));
      attributes.qp_state = IBV_QPS_RTS;
      attributes.timeout = timeout;
      attributes.retry_cnt = retry_count;
      attributes.rnr_retry = rnr_retry;
      attributes.sq_psn = 0; //local_psn;
      attributes.max_rd_atomic = max_rd_atomic;
      retval = ibv_modify_qp( queue_pair, &attributes,
                              IBV_QP_STATE |
                              //IBV_QP_TIMEOUT |           // uncomment this for RC
                              //IBV_QP_RETRY_CNT |         // uncomment this for RC
                              //IBV_QP_RNR_RETRY |         // uncomment this for RC
                              //IBV_QP_MAX_QP_RD_ATOMIC |  // uncomment this for RC
                              IBV_QP_SQ_PSN );
      if( retval < 0 ) {
        perror( "Error setting queue pair to RTR" );
        exit(1);
      }

      // queue pair is ready. add to set of queue pairs
      queue_pairs.push_back(queue_pair);
    }
  }
  
  //~Reducer();

  /// perform allreduce on a buffer
  void allreduce(ibv_mr * mr, void * address, size_t length) { }
};

#endif //  __REDUCER__
