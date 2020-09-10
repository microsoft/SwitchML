## Copyright (c) Microsoft Corporation.
## Licensed under the MIT License.

TARGET=client
OBJECTS=client.o Endpoint.o Connections.o Reducer.o ClientThread.o GRPCClient.o SwitchML.pb.o SwitchML.grpc.pb.o
GENERATED=SwitchML.pb.h SwitchML.grpc.pb.h SwitchML.pb.cc SwitchML.grpc.pb.cc

PROTOS_PATH = ../protos
vpath %.proto $(PROTOS_PATH)

CPPFLAGS+=`pkg-config --cflags protobuf grpc`
CXXFLAGS+=-std=c++14 -g -MMD -O3
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


HOSTS=prometheus35,prometheus36,prometheus37,prometheus38,prometheus39,prometheus40,prometheus41,prometheus42,prometheus43,prometheus44,prometheus45,prometheus46,prometheus47,prometheus48,prometheus49,prometheus50
NUM_PROCS=2

runswitch:: $(TARGET)
	bash ../counterdiff.sh mpirun --host $(HOSTS) -np $(NUM_PROCS) --mca pml ucx -x UCX_TLS=tcp -x UCX_NET_DEVICES=eno5 --map-by core --bind-to none --tag-output ./$< --server 7170c $(ARGS)


debug:: $(TARGET)
	mpirun -mca mpi_abort_delay 10 --host $(HOSTS) -np $(NUM_PROCS) --mca pml ucx -x UCX_TLS=tcp -x UCX_NET_DEVICES=eno5 --map-by core --bind-to none --tag-output ./$< --server 7170c $(ARGS)


#
# automatic dependence stuff
#

realclean:: clean
	rm -rf *.d

deps:: $(GENERATED) $(OBJECTS)

-include *.d

