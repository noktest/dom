#!/bin/bash
internetconnection() {
  if ping -c 3 -W 10 -w 20 "8.8.8.8" || \
     ping -c 3 -W 10 -w 20 "1.1.1.1" || \
     ping -c 3 -W 10 -w 20 "8.8.4.4" ;  then
    echo "internet connection established"
    return 0
  fi

  echo "no internet connection"
  return 1
}
