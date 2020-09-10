// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#ifndef __ENDPOINT__
#define __ENDPOINT__

#include <infiniband/verbs.h>
#include <cstring>
#include <iostream>
#include <endian.h>
#include <gflags/gflags.h>

class Endpoint {
  //private:
public: // TODO: undo this as much as necessary
  /// list of Verbs-capable devices
  ibv_device ** devices;
  int num_devices;
  
  /// info about chosen device
  ibv_device * device;
  const char * device_name;
  uint64_t device_guid; // big-endian
  ibv_device_attr device_attributes;
  
  /// info about chosen port
  uint8_t port; // port is generally 1-indexed
  ibv_port_attr port_attributes;
    
  /// GID of port
  uint8_t gid_index; // 0: RoCEv1 with MAC-based GID, 1:RoCEv2 with MAC-based GID, 2: RoCEv1 with IP-based GID, 3: RoCEv2 with IP-based GID
  ibv_gid gid;

  /// device context, used for most Verbs operations
  ibv_context * context;

  /// protection domain to go with context
  ibv_pd * protection_domain;

  /// until we can use NIC timestamps, store the CPU timestamp counter tick rate
  uint64_t ticks_per_sec;
  
  uint64_t get_mac();
  uint32_t get_ipv4();
  
public:
  Endpoint();
  ~Endpoint();

  /// allocate and register a memory region at a specific address. The
  /// call will fail if the allocation is not possible.
  ibv_mr * allocate_at_address(void * requested_address, size_t length);

  /// allocate a memory region using zero-based addressing. RDMA write
  /// operations will carry a byte offset into the region rather than
  /// a virtual address.
  ibv_mr * allocate_zero_based(size_t length);

  /// free a memory region allocated by one of the above calls.
  void free(ibv_mr * mr);
};


#endif //  __ENDPOINT__
