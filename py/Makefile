# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# this makefile exists only to compile the protobuf/GRPC server files

PYTHON=python3
PROTO_PATH=../protos
TARGETS=

SwitchML_pb2.py SwitchML_pb2_grpc.py: $(PROTO_PATH)/SwitchML.proto
	$(PYTHON) -m grpc_tools.protoc -I$(PROTO_PATH) --python_out=. --grpc_python_out=. $<
