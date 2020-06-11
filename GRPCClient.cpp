/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#include "GRPCClient.hpp"

#include <memory>
#include <string>

#include <grpcpp/grpcpp.h>

#include "SwitchML.grpc.pb.h"

// using grpc::Channel;
// using grpc::ClientContext;
// using grpc::Status;
// using SwitchML::RDMAConnectRequest;
// using SwitchML::RDMAConnectResponse;
// using SwitchML::RDMAServer;


GRPCClient::GRPCClient(std::shared_ptr<grpc::Channel> channel)
  : stub(SwitchML::RDMAServer::NewStub(channel))
{ }

void GRPCClient::RDMAConnect(const SwitchML::RDMAConnectRequest & request,
                             SwitchML::RDMAConnectResponse * response) {
  grpc::ClientContext context;
  grpc::Status status = stub->RDMAConnect(&context, request, response);
  if (!status.ok()) {
    std::cerr << "Error contacting coordinator: "
              << status.error_code() << ": "
              << status.error_message()
              << std::endl;
    exit(1);
  }
}

std::ostream & operator<<(std::ostream & s, const SwitchML::RDMAConnectRequest & r) {
  s << "<RDMAConnectRequest" << std::hex
    << " rank=" << r.my_rank()
    << " size=" << r.job_size()
    << " mac=0x" << r.mac()
    << " ipv4=0x" << r.ipv4()
    << " rkey=0x" << r.rkey();
  for (int i = 0; i < r.qpns_size(); ++i) {
    s << " qpn=0x" << r.qpns(i) << " psn=0x" << r.psns(i);
  }
  return s << ">";
}

std::ostream & operator<<(std::ostream & s, const SwitchML::RDMAConnectResponse & r) {
  s << "<RDMAConnectResponse" << std::hex;
  for (int i = 0; i < r.macs_size(); ++i) {
    s << " mac=0x" << r.macs(i)
      << " ipv4=0x" << r.ipv4s(i)
      << " rkey=0x" << r.rkeys(i);
  }
  for (int i = 0; i < r.qpns_size(); ++i) {
    s << " qpn=0x" << r.qpns(i) << " psn=0x" << r.psns(i);
  }
  return s << ">";
}
