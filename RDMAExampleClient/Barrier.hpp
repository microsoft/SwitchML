/*******************************************************************************
 * MICROSOFT CONFIDENTIAL & PROPRIETARY
 *
 * Copyright (c) 2019 Microsoft Corp.
 * All Rights Reserved.
 ******************************************************************************/

#ifndef __BARRIER__
#define __BARRIER__

#include <thread>
#include <mutex>
#include <condition_variable>

class Barrier {
private:
  const int num_participants;
  std::mutex mutex;
  std::condition_variable condition_variable;
  int count; /// number of participants outstanding
  bool flag; /// used to differentiate between adjacent barrier invocations
  
public:
  Barrier(const int num_participants)
    : num_participants(num_participants)
    , mutex()
    , condition_variable()
    , count(num_participants) // Initialize barrier to waiting state, expecting num_participants 
    , flag(false) // initial value of flag doesn't matter; only a change in value matters
  {
    // nothing to do here
  }

  void wait() {
    std::unique_lock<std::mutex> lock(mutex);
      
    // grab a copy of the current flag value
    const bool flag_copy = flag;
      
    // note this thread has arrived
    --count;
      
    if (count > 0) { 
      // if this thread is not the last one to arrive, wait for the
      // flag to change, indicating that the last thread has arrived
      while (flag_copy == flag) {
        condition_variable.wait(lock);
      }
    } else {
      // if this thread is the last one to arrive, flip the flag,
      // reset the count for the next iteration, and notify waiters
      flag = !flag;
      count = num_participants;
      condition_variable.notify_all();
    }
  }
};


#endif //  __BARRIER__
