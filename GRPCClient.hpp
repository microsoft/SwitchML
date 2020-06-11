/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#ifndef __GRPCCLIENT__
#define __GRPCCLIENT__

#include <iostream>

#include <grpcpp/grpcpp.h>

#include "SwitchML.grpc.pb.h"

class GRPCClient {
private:
  std::unique_ptr<SwitchML::RDMAServer::Stub> stub;
  
public:
  GRPCClient(std::shared_ptr<grpc::Channel> channel);
  void RDMAConnect(const SwitchML::RDMAConnectRequest & request,
                   SwitchML::RDMAConnectResponse * response);
};

std::ostream & operator<<(std::ostream & s, const SwitchML::RDMAConnectRequest & r);
std::ostream & operator<<(std::ostream & s, const SwitchML::RDMAConnectResponse & r);

#endif //  __GRPCCLIENT__
