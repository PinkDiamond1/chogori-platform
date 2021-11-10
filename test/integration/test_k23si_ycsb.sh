#!/bin/bash
topname=$(dirname "$0")
cd ${topname}/../..
set -e
CPODIR=/tmp/___cpo_integ_test
rm -rf ${CPODIR}
EPS="tcp+k2rpc://0.0.0.0:10000"

PERSISTENCE=tcp+k2rpc://0.0.0.0:12001
CPO=tcp+k2rpc://0.0.0.0:9000
TSO=tcp+k2rpc://0.0.0.0:13000
COMMON_ARGS="--enable_tx_checksum true --thread-affinity false"

# start nodepool on 1 cores
./build/src/k2/cmd/nodepool/nodepool -c1 --tcp_endpoints ${EPS} --k23si_persistence_endpoint ${PERSISTENCE} ${COMMON_ARGS} --prometheus_port 63001 --k23si_cpo_endpoint ${CPO} --tso_endpoint ${TSO} --memory=3G --partition_request_timeout=6s &
nodepool_child_pid=$!

# start persistence on 1 cores
./build/src/k2/cmd/persistence/persistence -c1 --tcp_endpoints ${PERSISTENCE} ${COMMON_ARGS} --prometheus_port 63002 &
persistence_child_pid=$!

# start tso on 2 cores
./build/src/k2/cmd/tso/tso -c2 --tcp_endpoints ${TSO} 13001 ${COMMON_ARGS} --prometheus_port 63003 &
tso_child_pid=$!

./build/src/k2/cmd/controlPlaneOracle/cpo_main -c2 --tcp_endpoints ${CPO} --data_dir ${CPODIR} --txn_heartbeat_deadline=10s --enable_tx_checksum true --reactor-backend epoll --prometheus_port 63000 --assignment_timeout=1s --nodepool_endpoints ${EPS} --tso_endpoints ${TSO} --persistence_endpoints ${PERSISTENCE} &
cpo_child_pid=$!


function finish {
  rv=$?
  # cleanup code
  rm -rf ${CPODIR}

  kill ${nodepool_child_pid}
  echo "Waiting for nodepool child pid: ${nodepool_child_pid}"
  wait ${nodepool_child_pid}

  kill ${cpo_child_pid}
  echo "Waiting for cpo child pid: ${cpo_child_pid}"
  wait ${cpo_child_pid}

  kill ${persistence_child_pid}
  echo "Waiting for persistence child pid: ${persistence_child_pid}"
  wait ${persistence_child_pid}

  kill ${tso_child_pid}
  echo "Waiting for tso child pid: ${tso_child_pid}"
  wait ${tso_child_pid}
  echo ">>>> Test ${0} finished with code ${rv}"
}
trap finish EXIT

sleep 2

echo ">>> Starting load ..."
./build/src/k2/cmd/ycsb/ycsb_client -c1 --tcp_remotes ${EPS} --cpo ${CPO} --tso_endpoint ${TSO} --data_load true --prometheus_port 63100 ${COMMON_ARGS} --memory=512M --partition_request_timeout=6s --dataload_txn_timeout=600s --num_concurrent_txns=2 --num_records=500 --num_records_insert=100 --request_dist="latest"

sleep 1

echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
echo ">>> Starting benchmark Workload D..."
./build/src/k2/cmd/ycsb/ycsb_client -c1 --tcp_remotes ${EPS} --cpo ${CPO} --tso_endpoint ${TSO} --data_load false --prometheus_port 63100 ${COMMON_ARGS} --memory=512M --partition_request_timeout=6s --num_concurrent_txns=1 --num_records=500 --num_records_insert=100 --test_duration=200ms --ops_per_txn=1 --read_proportion=95 --update_proportion=0 --scan_proportion=0 --insert_proportion=5 --request_dist="latest"
