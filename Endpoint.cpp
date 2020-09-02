/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#include "Endpoint.hpp"
#include <sys/mman.h>

#include <x86intrin.h>
#include <thread>

extern "C" {
#include <hugetlbfs.h>
}

DEFINE_string(device, "mlx5_0", "Name of Verbs device");
DEFINE_int32(device_port, 1, "Port on Verbs device (usually 1-indexed, so should usually be 1)");
DEFINE_int32(gid_index, 3, "Verbs device GID index. 0: RoCEv1 with MAC-based GID, 1: RoCEv2 with MAC-based GID, 2: RoCEv1 with IP-based GID, 3: RoCEv2 with IP-based GIDPort on Verbs device");

Endpoint::Endpoint()
  : devices(nullptr)
  , num_devices(0)
  , device(nullptr)
  , device_name(nullptr)
  , device_guid(0)
  , device_attributes() // clear later
  , port(FLAGS_device_port) // port is generally 1-indexed
  , port_attributes() // clear later
  , gid_index(FLAGS_gid_index) // use RoCEv2 with IP-based GID
  , gid({.global = {0, 0}})
  , context(nullptr)
  , protection_domain(nullptr)
{
  std::memset(&device_attributes, 0, sizeof(ibv_device_attr));
  std::memset(&port_attributes, 0, sizeof(ibv_port_attr));


  // get device list
  devices = ibv_get_device_list(&num_devices);
  if (!devices)  {
    std::cerr << "Didn't find any Verbs-capable devices!";
    exit(1);
  }

  // search for device
  for(int i = 0; i < num_devices; ++i) {
    std::cout << "Found Verbs device " << ibv_get_device_name(devices[i]) 
              << " with guid " << (void*) be64toh(ibv_get_device_guid(devices[i])) 
              << std::endl;
    if ((num_devices == 1) || (FLAGS_device == ibv_get_device_name(devices[i])))  {
      // choose this device
      device = devices[i];
      device_name = ibv_get_device_name(device);
      device_guid = be64toh(ibv_get_device_guid(device) );
    }
  }
  
  // ensure we found a device
  if (!device)  {
    std::cerr << "Didn't find device " << FLAGS_device << "\n";
    exit(1);
  } else {
    std::cout << "Chose Verbs device " << ibv_get_device_name(device) << " gid index " << (int) gid_index << "\n";
  }

  // open device context and get device attributes
  context = ibv_open_device(device);
  if (!context)  {
    std::cerr << "Failed to get context for device " << device_name << "\n";
    exit(1);
  }
  int retval = ibv_query_device(context, &device_attributes);
  if (retval < 0)  {
    perror("Error getting device attributes");
    exit(1);
  }

  // choose a port on the device and get port attributes
  if (device_attributes.phys_port_cnt > 1)  {
    std::cout << (int) device_attributes.phys_port_cnt << " ports detected; using port " << (int) FLAGS_device_port << std::endl;
  }
  if (device_attributes.phys_port_cnt < FLAGS_device_port)  {
    std::cerr << "expected " << (int) FLAGS_device_port << " ports, but found " << (int) device_attributes.phys_port_cnt;
    exit(1);
  }
  port = FLAGS_device_port;
  retval = ibv_query_port(context, port, &port_attributes);
  if (retval < 0)  {
    perror("Error getting port attributes");
    exit(1);
  }

  // print GIDs
  for (int i = 0; i < port_attributes.gid_tbl_len; ++i) {
    retval = ibv_query_gid(context, port, i, &gid);
    if (retval < 0)  {
      perror("Error getting GID");
      exit(1);
    }
    if (gid.global.subnet_prefix != 0 || gid.global.interface_id !=0) {
      std::cout << "GID " << i << " is "
                << (void*) gid.global.subnet_prefix << " " << (void*) gid.global.interface_id
                << "\n";
    }
  }

  // get selected gid
  retval = ibv_query_gid(context, port, FLAGS_gid_index, &gid);
  if (retval < 0)  {
    perror("Error getting GID");
    exit(1);
  }
  if (0 == gid.global.subnet_prefix && 0 == gid.global.interface_id) {
    std::cerr << "Selected GID " << gid_index << " was all zeros; is interface down? Maybe try RoCEv1 GID index?" << std::endl;
    exit(1);
  }

  // create protection domain
  protection_domain = ibv_alloc_pd(context);
  if (!protection_domain)  {
    std::cerr << "Error getting protection domain!\n";
    exit(1);
  }

  /// until we can use NIC timestamps, store the CPU timestamp counter tick rate
  uint64_t start_ticks = __rdtsc();
  std::this_thread::sleep_for(std::chrono::seconds(1));
  uint64_t end_ticks = __rdtsc();
  ticks_per_sec = end_ticks - start_ticks;
}

Endpoint::~Endpoint() {
    if (protection_domain)  {
    int retval = ibv_dealloc_pd(protection_domain);
    if (retval < 0)  {
      perror("Error deallocating protection domain");
      exit(1);
    }
    protection_domain = nullptr;
  }

  if (context)  {
    int retval = ibv_close_device(context);
    if (retval < 0)  {
      perror("Error closing device context");
      exit(1);
    }
    context = nullptr;
  }

  if (devices)  {
    ibv_free_device_list(devices);
    devices = nullptr;
  }

  if (device)  {
    device = nullptr;
  }

}

ibv_mr * Endpoint::allocate_at_address(void * requested_address, size_t length) {
  // convert length from elements to bytes
  length *= sizeof(int32_t);

  // round up to default huge page size
  size_t hugepagesize = gethugepagesize();
  if (hugepagesize < 0) {
    std::cerr << "Error getting default huge page size" << std::endl;
    exit(1);
  }
  length = (length + (hugepagesize-1)) & ~(hugepagesize-1);
  
  // allocate
  void * buf = mmap(requested_address, length,
                    PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB | MAP_FIXED,
                    -1, 0);
  if (MAP_FAILED == buf || buf != requested_address) {
      perror("Error allocating memory region");
      exit(1);
  }

  // register
  ibv_mr * mr = ibv_reg_mr(protection_domain, buf, length,
                           (IBV_ACCESS_LOCAL_WRITE |
                            IBV_ACCESS_REMOTE_WRITE |
                            IBV_ACCESS_ZERO_BASED));
  if (!mr) {
      perror("Error registering memory region");
      exit(1);
  }

  return mr;
}

ibv_mr * Endpoint::allocate_zero_based(size_t length) {
  // convert length from elements to bytes
  length *= sizeof(int32_t);

  // round up to default huge page size
  size_t hugepagesize = gethugepagesize();
  if (hugepagesize < 0) {
    std::cerr << "Error getting default huge page size" << std::endl;
    exit(1);
  }
  length = (length + (hugepagesize-1)) & ~(hugepagesize-1);

  // allocate
  void * buf = mmap(NULL, length,
                    PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB,
                    -1, 0);
  if (MAP_FAILED == buf) {
      perror("Error allocating memory region");
      exit(1);
  }

  std::cout << "Buffer " << buf << " length " << length << std::endl;
  // register
  ibv_mr * mr = ibv_reg_mr(protection_domain, buf, length,
                           (IBV_ACCESS_LOCAL_WRITE |
                            IBV_ACCESS_REMOTE_WRITE |
                            IBV_ACCESS_ZERO_BASED));
  if (!mr) {
      perror("Error registering memory region");
      exit(1);
  }

  return mr;
}

void Endpoint::free(ibv_mr * mr) {
  // extract pointer from MR
  auto buf = mr->addr;
  auto len = mr->length;
  
  // deregister MR
  int retval = ibv_dereg_mr(mr);
  if (retval < 0)  {
      perror("Error deregistering memory region");
      exit(1);
  }
  
  // free MR
  retval = munmap(buf, len);
  if (retval < 0)  {
      perror("Error freeing memory region");
      exit(1);
  }
}


uint64_t Endpoint::get_mac() {
  ibv_gid mac_gid;
  int retval = ibv_query_gid(context, port, 0, &mac_gid);
  if (retval < 0)  {
    perror("Error getting GID for MAC address");
    exit(1);
  }
  
  uint64_t mac = 0;
  mac |= mac_gid.raw[8] ^ 2;
  mac <<= 8;
  mac |= mac_gid.raw[9];
  mac <<= 8;
  mac |= mac_gid.raw[10];
  mac <<= 8;
  mac |= mac_gid.raw[13];
  mac <<= 8;
  mac |= mac_gid.raw[14];
  mac <<= 8;
  mac |= mac_gid.raw[15];
  return mac;
}

uint32_t Endpoint::get_ipv4() {
  ibv_gid ipv4_gid;
  int retval = ibv_query_gid(context, port, 2, &ipv4_gid);
  if (retval < 0)  {
    perror("Error getting GID for IPv4 address");
    exit(1);
  }

  uint32_t ip = 0;
  ip |= ipv4_gid.raw[12];
  ip <<= 8;
  ip |= ipv4_gid.raw[13];
  ip <<= 8;
  ip |= ipv4_gid.raw[14];
  ip <<= 8;
  ip |= ipv4_gid.raw[15];
  return ip;
}
