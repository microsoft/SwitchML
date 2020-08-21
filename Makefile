#############################################################################
# MICROSOFT CONFIDENTIAL & PROPRIETARY
# 
# Copyright (c) 2019 Microsoft Corp.
# All Rights Reserved.
#############################################################################

TARGET=client
OBJECTS=client.o Endpoint.o Connections.o Reducer.o ClientThread.o GRPCClient.o SwitchML.pb.o SwitchML.grpc.pb.o
GENERATED=SwitchML.pb.h SwitchML.grpc.pb.h SwitchML.pb.cc SwitchML.grpc.pb.cc

SERVER_TARGET=server
SERVER_OBJECTS=server.o Endpoint.o Connections.o ServerThread.o GRPCClient.o SwitchML.pb.o SwitchML.grpc.pb.o

PROTOS_PATH = ../protos
vpath %.proto $(PROTOS_PATH)

CPPFLAGS+=`pkg-config --cflags protobuf grpc`
CXXFLAGS+=-std=c++14 -g -MMD -O1
LDFLAGS+= -L/usr/local/lib `pkg-config --libs protobuf grpc++` \
	-pthread \
	-Wl,--no-as-needed -lgrpc++_reflection -Wl,--as-needed \
	-ldl \
	-libverbs \
	-lgflags \
	-lhugetlbfs

PROTOC = protoc
GRPC_CPP_PLUGIN = grpc_cpp_plugin
GRPC_CPP_PLUGIN_PATH ?= `which $(GRPC_CPP_PLUGIN)`

$(TARGET): $(OBJECTS)
	mpicxx $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

$(SERVER_TARGET): $(SERVER_OBJECTS)
	mpicxx $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.cpp Makefile
	mpicxx $(CXXFLAGS) -c -o $@ $<

.PRECIOUS: %.grpc.pb.cc
%.grpc.pb.cc %.grpc.pb.h: %.proto
	$(PROTOC) -I $(PROTOS_PATH) --grpc_out=. --plugin=protoc-gen-grpc=$(GRPC_CPP_PLUGIN_PATH) $<

.PRECIOUS: %.pb.cc
%.pb.cc %.pb.h: %.proto
	$(PROTOC) -I $(PROTOS_PATH) --cpp_out=. $<

clean::
	rm -f $(TARGET) $(OBJECTS) *.o *.pb.cc *.pb.h

#run:: umr-sender
#run:: mpiuc
# run:: mpitest
# 	mpirun --host prometheus42,prometheus50 -np 2 --tag-output ./$< $(COUNT) $(SIZE)

HOSTS=prometheus47,prometheus49
#HOSTS=prometheus50,prometheus47
#HOSTS=prometheus49,prometheus49
NUM_PROCS=2

#HOSTS=prometheus50,prometheus50,prometheus50,prometheus50
#NUM_PROCS=1

ARGS=--length=64
# $(COUNT) $(SIZE)
run:: $(TARGET)
	mpirun --host $(HOSTS) -np 2 --tag-output ./$< $(ARGS)

runswitch:: $(TARGET)
	bash ../counterdiff.sh mlx5_0 mpirun --host $(HOSTS) -np $(NUM_PROCS) --mca btl tcp,self  --map-by core --bind-to none --tag-output ./$< --server 7170c $(ARGS)


debug:: $(TARGET)
	mpirun -mca mpi_abort_delay 10 --host $(HOSTS) -np 2 --tag-output ./$< $(ARGS)
#	mpirun --host $(HOSTS) -np 2 --tag-output ./$< $(ARGS)


#
# automatic dependence stuff
#

realclean:: clean
	rm -rf *.d

deps:: $(GENERATED) $(OBJECTS)

-include *.d

