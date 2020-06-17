/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#include "common.hpp"
#include "Connections.hpp"
#include <mpi.h>
#include <chrono>

DEFINE_bool(use_rc, false, "RDMA connection type: if set, use RC; otherwise default to UC.");
DEFINE_int32(mtu, 256, "RDMA packet MTU: one of 256, 512, 1024, 2048, or 4096.");
             
DEFINE_int32(cores, 1, "Number of cores used for communication."); // TODO: choose sane default
DEFINE_int32(slots_per_core, 1, "How many slots per core should we use?"); // TODO: choose sane default

DEFINE_int32(message_size, 4096, "Max size of each RDMA message in bytes");
DEFINE_int32(packet_size,   256, "Max size of each RDMA packet in bytes");

DEFINE_string(server, "localhost", "Name of GRPC server of coordinator.");
DEFINE_int32(port, 50099, "GRPC server port on coordinator.");

//
// some helper functions
//


uint32_t gid_to_ipv4(const ibv_gid gid) {
  uint32_t ip = 0;
  ip |= gid.raw[12];
  ip <<= 8;
  ip |= gid.raw[13];
  ip <<= 8;
  ip |= gid.raw[14];
  ip <<= 8;
  ip |= gid.raw[15];
  return ip;
}

uint64_t gid_to_mac(const ibv_gid gid) {
  uint64_t mac = 0;
  mac |= gid.raw[8]^ 2;
  mac <<= 8;
  mac |= gid.raw[9];
  mac <<= 8;
  mac |= gid.raw[10];
  mac <<= 8;
  mac |= gid.raw[13];
  mac <<= 8;
  mac |= gid.raw[14];
  mac <<= 8;
  mac |= gid.raw[15];
  return mac;
}

ibv_gid ipv4_to_gid(const int32_t ip) {
  ibv_gid gid;
  gid.global.subnet_prefix = 0;
  gid.global.interface_id = 0;
  gid.raw[10] = 0xff;
  gid.raw[11] = 0xff;
  gid.raw[12] = (ip >> 24) & 0xff;
  gid.raw[13] = (ip >> 16) & 0xff;
  gid.raw[14] = (ip >>  8) & 0xff;
  gid.raw[15] = (ip >>  0) & 0xff;
  return gid;
}

ibv_gid mac_to_gid(const uint64_t mac) {
  ibv_gid gid;
  gid.global.subnet_prefix = 0x80fe;
  gid.global.interface_id = 0;
  gid.raw[ 8] = ((mac >> 40) & 0xff) ^ 2;
  gid.raw[ 9] = (mac >> 32) & 0xff;
  gid.raw[10] = (mac >> 24) & 0xff;
  gid.raw[11] = 0xff;
  gid.raw[12] = 0xfe;
  gid.raw[13] = (mac >> 16) & 0xff;
  gid.raw[14] = (mac >>  8) & 0xff;
  gid.raw[15] = (mac >>  0) & 0xff;
  return gid;
}


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
void Connections::exchange_connection_info() {
  std::cout << "Rank " << rank << " of size " << size << " requesting connection to switch.\n";

  // compute ID for this job
  uint64_t job_id = 0;

  // combine timestamp + host GID
  if (0 == rank) {
    job_id = endpoint.gid.global.subnet_prefix;
    auto current_time = std::chrono::high_resolution_clock::now();
    auto time_since_epoch = current_time.time_since_epoch();
    auto nanoseconds_since_epoch = std::chrono::duration_cast<std::chrono::nanoseconds>(time_since_epoch);
    job_id ^= nanoseconds_since_epoch.count();
    std::cout << "Job id is " << (void*) job_id << std::endl;
  }

  // broadcast job id to other nodes in job
  MPI_CHECK(MPI_Bcast(&job_id, 1, MPI_UINT64_T, 0, MPI_COMM_WORLD));
  
  // send connection request to coordinator
  SwitchML::RDMAConnectRequest request;
  request.set_job_id(job_id);
  request.set_my_rank(rank);
  request.set_job_size(size);
  request.set_mac(endpoint.get_mac());
  request.set_ipv4(endpoint.get_ipv4());
  request.set_rkey(memory_region->rkey);

  for (int i = 0; i < queue_pairs.size(); ++i) {
    request.add_qpns(queue_pairs[i]->qp_num);
    request.add_psns(queue_pairs[i]->qp_num / 2); // for debugging
  }

  std::cout << "Sending request " << request << std::endl;

  SwitchML::RDMAConnectResponse response;
  if (0 == rank) { // first worker clears switch state before processing the request
    grpc_client.RDMAConnect(request, &response);
    MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
  } else { // remaining workers process switch state after the first one is done.
    MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
    grpc_client.RDMAConnect(request, &response);
  }

  std::cout << "Rank " << rank << " got response " << response << std::endl;

  // ensure switch has gotten all workers' job state before proceeding.
  MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
  
  // now, copy remote data to our neigbor arrays to continue queue pair setup
  for (int i = 0; i < queue_pairs.size(); ++i) {
    if (endpoint.gid_index >= 2) { // IPv4-based GID
      neighbor_gids[i] = ipv4_to_gid(response.ipv4s(i % response.ipv4s_size()));
    } else {
      neighbor_gids[i] = mac_to_gid(response.macs(i % response.macs_size()));
    }
    neighbor_rkeys[i] = response.rkeys(i % response.rkeys_size());
    neighbor_qpns[i] = response.qpns(i);
    neighbor_psns[i] = response.psns(i);
  }

  std::cout << "Barrier\n";
  MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
}

 
