/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#include "common.hpp"
#include "Connections.hpp"
#include <mpi.h>

DEFINE_bool(use_rc, false, "RDMA connection type: if set, use RC; otherwise default to UC.");
DEFINE_int32(mtu, 256, "RDMA packet MTU: one of 256, 512, 1024, 2048, or 4096.");
             
DEFINE_int32(cores, 1, "Number of cores used for communication."); // TODO: choose sane default
DEFINE_int32(slots_per_core, 1, "How many slots per core should we use?"); // TODO: choose sane default

DEFINE_string(servers, "", "Comma-separated list of IP addresses (not hostnames) for servers/switches to be used for this reduction.");
DEFINE_int32(message_size, 4096, "Max size of each RDMA message in bytes");
DEFINE_int32(packet_size,   256, "Max size of each RDMA packet in bytes");

void Connections::set_up_queue_pairs() {
  // See section 3.5 of the RDMA Aware Networks Programming User
  // Manual for more details on queue pair bringup.

  // Create shared completion queues, one per core.
  std::cout << "Creating completion queues...\n";
  for (int i = 0; i < FLAGS_cores; ++i) {
    completion_queues[i] = create_completion_queue();
  }

  // Create queue pairs, one per slot. Spread queue pairs across cores
  // in a blocked approach, with core 0 having QPs 0 to n-1, core 1
  // having QPs n to 2n-1, core 2 having QPs 2n to 3n-1, etc.
  std::cout << "Creating queue pairs...\n";
  for (int i = 0; i < FLAGS_cores * FLAGS_slots_per_core; ++i) {
    // use the completion queue associated with the core for this queue pair.
    ibv_cq * completion_queue_for_qp = completion_queues[i / FLAGS_slots_per_core];
    queue_pairs[i] = create_queue_pair(completion_queue_for_qp);
  }

  // Move queue pairs to INIT. This generates a local queue pair number.
  std::cout << "Moving queue pairs to INIT...\n";
  for (int i = 0; i < FLAGS_cores * FLAGS_slots_per_core; ++i) {
    move_to_init(i);
  }

  // At this point we can post receive buffers. In theory, we
  // *should* do so before we move queues to RTR, but as long as we
  // have some other syncronization mechanism that will keep other
  // parties from sending before we're ready, it's okay not to.

  // In order to move the queues to RTR, we now need to exhange GID,
  // queue pair numbers, and initial packet sequence numbers with
  // our neighbors.
  std::cout << "Exchanging connection info...\n";
  exchange_connection_info();

  // copy/initialize rkeys
  for (int i = 0; i < FLAGS_cores * FLAGS_slots_per_core; ++i) {
    rkeys[i] = neighbor_rkeys[i];
  }
  
  // Move queue pairs to RTR. After this, we're ready to receive.
  std::cout << "Moving queue pairs to RTR...\n";
  for (int i = 0; i < FLAGS_cores * FLAGS_slots_per_core; ++i) {
    move_to_rtr(i);
  }
  
  // Move queue pairs to RTS. After this, we're ready to send.
  std::cout << "Moving queue pairs to RTS...\n";
  for (int i = 0; i < FLAGS_cores * FLAGS_slots_per_core; ++i) {
    move_to_rts(i);
  }
}

// create shared completion queues, one per core.
ibv_cq * Connections::create_completion_queue() {
  ibv_cq * completion_queue = ibv_create_cq(endpoint.context,
                                            completion_queue_depth,
                                            NULL,  // no user context
                                            NULL,  // no completion channel
                                            0);    // no completion channel vector
  if (!completion_queue) {
    std::cerr << "Error creating completion queue!\n";
    exit(1);
  }
  
  return completion_queue;
}

// first, create queue pair (starts in RESET state)
ibv_qp * Connections::create_queue_pair(ibv_cq * completion_queue) {
  ibv_qp_init_attr init_attributes;
  std::memset(&init_attributes, 0, sizeof(ibv_qp_init_attr));
  
  // use shared completion queue
  init_attributes.send_cq = completion_queue;
  init_attributes.recv_cq = completion_queue;
  
  // use whatever type of queue pair we selected
  init_attributes.qp_type = qp_type;
      
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
  if (!queue_pair) {
    std::cerr << "Error creating queue pair!\n";
    exit(1);
  }

  std::cout << "Created queue pair " << queue_pair
            << " QPN 0x" << std::hex << queue_pair->qp_num
            << ".\n";

  return queue_pair;
}

// then, move queue pair to INIT
void Connections::move_to_init(int i) {
  ibv_qp_attr attributes;
  std::memset(&attributes, 0, sizeof(attributes));
  attributes.qp_state = IBV_QPS_INIT;
  attributes.port_num = endpoint.port;
  attributes.pkey_index = 0;
  attributes.qp_access_flags = (IBV_ACCESS_LOCAL_WRITE |
                                IBV_ACCESS_REMOTE_WRITE);
  std::cout << "Moving queue pair " << queue_pairs[i] << " to INIT...\n";
  int retval = ibv_modify_qp(queue_pairs[i], &attributes,
                             IBV_QP_STATE |
                             IBV_QP_PORT |
                             IBV_QP_PKEY_INDEX |
                             IBV_QP_ACCESS_FLAGS);
  if (retval < 0) {
    perror("Error setting queue pair to INIT");
    exit(1);
  }
}

// now, move queue pair to Ready-To-Receive (RTR) state
void Connections::move_to_rtr(int i) {
  std::cout << "Connecting QP 0x" << std::hex << queue_pairs[i]->qp_num
            << " with remote QP 0x" << std::hex << neighbor_qpns[i]
            << " initial PSN " << neighbor_psns[i]
            << std::endl;
  
  ibv_qp_attr attributes;
  std::memset(&attributes, 0, sizeof(attributes));
  attributes.qp_state           = IBV_QPS_RTR;
  attributes.dest_qp_num        = neighbor_qpns[i];
  attributes.rq_psn             = neighbor_psns[i];
  attributes.max_dest_rd_atomic = max_dest_rd_atomic; // used only for RC
  attributes.min_rnr_timer      = min_rnr_timer;      // used only for RC
  
  // what packet size do we want?
  attributes.path_mtu = mtu;
  
  attributes.ah_attr.is_global     = 1; 
  attributes.ah_attr.dlid          = endpoint.port_attributes.lid; // not really necessary since using RoCE, not IB, and is_global is set
  attributes.ah_attr.sl            = 0;
  attributes.ah_attr.src_path_bits = 0;
  attributes.ah_attr.port_num      = endpoint.port;
  
  attributes.ah_attr.grh.dgid                      = neighbor_gids[i];
  attributes.ah_attr.grh.sgid_index                = endpoint.gid_index;
  attributes.ah_attr.grh.flow_label                = 0;
  attributes.ah_attr.grh.hop_limit                 = 0xFF;
  attributes.ah_attr.grh.traffic_class             = 1;
  
  int retval = ibv_modify_qp(queue_pairs[i], &attributes,
                             IBV_QP_STATE |
                             IBV_QP_PATH_MTU |
                             IBV_QP_DEST_QPN |
                             IBV_QP_RQ_PSN |
                             IBV_QP_AV |
                             (qp_type == IBV_QPT_RC ?
                              (IBV_QP_MAX_DEST_RD_ATOMIC |
                               IBV_QP_MIN_RNR_TIMER)
                              : 0)
                             );
  if (retval < 0) {
    perror("Error setting queue pair to RTR");
    exit(1);
  }
}

// finally, move queue to Ready-To-Send (RTS) state
void Connections::move_to_rts(int i) {
  ibv_qp_attr attributes;
  std::memset(&attributes, 0, sizeof(attributes));
  attributes.qp_state = IBV_QPS_RTS;
  attributes.sq_psn = queue_pairs[i]->qp_num/2; // use QPN/2 as initial PSN for testing
  attributes.timeout = timeout;             // used only for RC
  attributes.retry_cnt = retry_count;       // used only for RC
  attributes.rnr_retry = rnr_retry;         // used only for RC
  attributes.max_rd_atomic = max_rd_atomic; // used only for RC
  int retval = ibv_modify_qp(queue_pairs[i], &attributes,
                             IBV_QP_STATE |
                             IBV_QP_SQ_PSN |
                             (qp_type == IBV_QPT_RC ?
                              (IBV_QP_TIMEOUT |
                               IBV_QP_RETRY_CNT |
                               IBV_QP_RNR_RETRY |
                               IBV_QP_MAX_QP_RD_ATOMIC)
                              : 0));
  if (retval < 0) {
    perror("Error setting queue pair to RTR");
    exit(1);
  }
}

// Exchange queue pair information
// TODO: this is currently a hack for testing. I'm exchanging this
// data in a more-complex-than-necessary way, since for testing I'm
// currently limiting this to 2 processes.
void Connections::exchange_connection_info() {
  // get MPI job geometry
  int rank = 0;
  int size = 0;
  MPI_CHECK(MPI_Comm_rank(MPI_COMM_WORLD, &rank));
  MPI_CHECK(MPI_Comm_size(MPI_COMM_WORLD, &size));

  // if (size != 2) {
  //   std::cerr << "Job size must be 2 for the current codebase." << std::endl;
  //   exit(1);
  // }

  std::cout << "Rank " << rank << " of size " << size << " running.\n";
  
  // collect my qpns and psns to be exchanged
  std::vector<uint32_t> local_qpns(queue_pairs.size());
  for (int i = 0; i < queue_pairs.size(); ++i) {
    local_qpns[i] = queue_pairs[i]->qp_num; // assigned by library at creation
  }

  // initialize local PSNs to QPN/2 for debugging
  std::vector<uint32_t> local_psns(queue_pairs.size());
  for (int i = 0; i < queue_pairs.size(); ++i) {
    local_psns[i] = queue_pairs[i]->qp_num / 2;
  }

  // allocate temporary storage for remote data
  std::vector<ibv_gid> remote_gids(size);
  std::vector<int32_t> remote_rkeys(size);
  std::vector<uint32_t> remote_qpns(size * queue_pairs.size());
  std::vector<uint32_t> remote_psns(size * queue_pairs.size());

  // allgather GIDs
  MPI_CHECK(MPI_Allgather(&endpoint.gid.raw[0],   16, MPI_UINT8_T,
                          &remote_gids[0].raw[0], 16, MPI_UINT8_T,
                          MPI_COMM_WORLD));

  // allgather rkeys
  MPI_CHECK(MPI_Allgather(&memory_region->rkey, 1, MPI_UINT32_T,
                          &remote_rkeys[0],     1, MPI_UINT32_T,
                          MPI_COMM_WORLD));

  // allgather QPNs
  MPI_CHECK(MPI_Allgather(&local_qpns[0],  queue_pairs.size(), MPI_UINT32_T,
                          &remote_qpns[0], queue_pairs.size(), MPI_UINT32_T,
                          MPI_COMM_WORLD));

  // allgather PSNs
  MPI_CHECK(MPI_Allgather(&local_psns[0],  queue_pairs.size(), MPI_UINT32_T,
                          &remote_psns[0], queue_pairs.size(), MPI_UINT32_T,
                          MPI_COMM_WORLD));

  for (int i = 0; i < local_qpns.size(); ++i) {
    std::cout << "Local QPN 0x" << std::hex << local_qpns[i]
              << " PSN 0x" << std::hex << local_psns[i]
              << std::endl;
  }
  
  for (int i = 0; i < remote_qpns.size(); ++i) {
    std::cout << "Index " << i
              << " Remote QPN 0x" << std::hex << remote_qpns[i]
              << " PSN 0x" << std::hex << remote_psns[i]
              << std::endl;
  }
  
  std::cout << "Copying\n";
  std::cout << neighbor_gids.size() << " "
            << neighbor_qpns.size() << " "
            << neighbor_psns.size() << " "
            << size << " "
            << rank << " "
            << ((size-1)-rank) << " "
            << remote_gids.size() << " "
            << remote_qpns.size() << " "
            << remote_psns.size() << " "
            << remote_qpns.size() << " "
            << remote_psns.size() << " "
            << std::endl;

  // check received data
  for (int j = 0; j < size; ++j) {
    std::cout << "Neighbor " << j
              << " GID " << (void*) remote_gids[j].global.subnet_prefix
              << "/" << (void*) remote_gids[j].global.interface_id
              << " rkey " << std::hex << remote_rkeys[j];
    for (int i = 0; i < queue_pairs.size(); ++i) {
      int index = j * queue_pairs.size() + i;
      std::cout << " index " << index
                << " QPN " << remote_qpns[index]
                << " PSN " << remote_psns[index];
    }
    std::cout << std::endl;
  }
  
  // now, copy remote data to our neigbor arrays to continue queue pair setup
  for (int i = 0; i < queue_pairs.size(); ++i) {
    int neighbor_rank = (size-1) - rank;
    int neighbor_index = neighbor_rank * queue_pairs.size() + i;
    neighbor_gids[i] = remote_gids[neighbor_rank];
    neighbor_rkeys[i] = remote_rkeys[neighbor_rank];
    neighbor_qpns[i] = remote_qpns[neighbor_index];
    neighbor_psns[i] = remote_psns[neighbor_index];
  }

  std::cout << "Barrier\n";
  MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
}

 

// resolve server addresses to IPs and form GUIDs for talking to
// switch(es) that don't normally generate their own GUIDs.
//
// NOTE: this is a hack. all this code is just to parse IP addresses
// from the command line so we can form GIDs. Eventually we'll need to
// exchange this data over MPI or some other transport.
void Connections::resolve_server_addresses_to_gids() {
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
}
