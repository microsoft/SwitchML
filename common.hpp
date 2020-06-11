/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#include <iostream>
#include <cstdlib>
#include <unistd.h>
#include <infiniband/verbs.h>
#include <mpi.h>

///
/// macro to deal with MPI errors
///
#define MPI_CHECK( mpi_call )                                           \
  do {                                                                  \
    int retval;                                                         \
    if( (retval = (mpi_call)) != 0 ) {                                  \
      char error_string[MPI_MAX_ERROR_STRING];                          \
      int length;                                                       \
      MPI_Error_string( retval, error_string, &length);                 \
      std::cerr << "MPI call failed: " #mpi_call ": "                   \
                << error_string << "\n";                                \
      exit(1);                                                          \
    }                                                                   \
  } while(0)

//std::ostream & operator<<(std::ostream & o, const ibv_send_wr & wr);

// this is to aid in debugging. It will 
inline void wait_for_attach() {
  volatile int i = 0;
  char hostname[256];
  gethostname(hostname, sizeof(hostname));
  printf("PID %d on %s ready for attach\n", getpid(), hostname);
  fflush(stdout);
  //pause();
  // while (0 == i) {
  //   sleep(1);
  // }
  sleep(10);
}


               
