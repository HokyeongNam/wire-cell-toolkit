#!/usr/bin/env bash
set -euo pipefail

# 0. 사용자 설치 경로
export PERFTOOLS_PREFIX=/exp/dune/data/users/hnam/demo/gperftools/install
export UNWIND_PREFIX=/exp/dune/data/users/hnam/demo/libunwind/install
export PPROF_PREFIX=/exp/dune/data/users/hnam/demo/go/bin

# 런타임에 로드할 라이브러리 검색 경로
export LD_LIBRARY_PATH="$PERFTOOLS_PREFIX/lib:$UNWIND_PREFIX/lib:$LD_LIBRARY_PATH"
export PATH="$PERFTOOLS_PREFIX/bin:$PPROF_PREFIX:$PATH"

# 1. Locate the executable
PROGRAM_PATH="$(which wire-cell)"
if [[ -z "$PROGRAM_PATH" ]]; then
  echo "Error: 'lar' executable not found in PATH." >&2
  exit 1
fi

# 2. Define profiling output filenames
CPU_PROFILE="cpu.prof"
HEAP_PROFILE="mem.prof"

# 3. Use our locally built gperftools
LIB_PROFILER="$PERFTOOLS_PREFIX/lib/libprofiler.so.0"
LIB_TCMALLOC="$PERFTOOLS_PREFIX/lib/libtcmalloc.so.4"

if [[ -z "$LIB_PROFILER" || -z "$LIB_TCMALLOC" ]]; then
  echo "Error: could not locate libprofiler.so or libtcmalloc.so" >&2
  exit 1
fi

# 4. Configuration and input files
#FHICL_FILE="my_standard_reco_stage2_calibration_protodunehd_keepup_dnnroi.fcl"
CONFIG_FILE="wct-sim-drift-deposplat_test.jsonnet"
#INPUT_FILE="../../../../data/stage1/run027673/np04hd_raw_run027673_0000_dataflow0_datawriter_0_20240704T050545_reco_stage1.root"

# 5. Run the program under CPU and memory profiler
echo "Program:    $PROGRAM_PATH"
#echo "Config file:$FHICL_FILE"
echo "Config file:$CONFIG_FILE"
#echo "Input file: $INPUT_FILE"
echo "Profiler:   $LIB_PROFILER"
echo "TCMalloc:   $LIB_TCMALLOC"

#echo "Running lar under CPU profiler"
#export CPUPROFILE="$CPU_PROFILE"
#LD_PRELOAD="$LIB_PROFILER" \
#  "$PROGRAM_PATH" -n1 -c "$FHICL_FILE" -s "$INPUT_FILE"
#ls -l ${CPU_PROFILE}*
#echo "Profiles written to ${CPU_PROFILE}"

#echo "Running lar under memory profiler"
#export HEAPPROFILE="$HEAP_PROFILE"
#LD_PRELOAD="$LIB_TCMALLOC" \
#  "$PROGRAM_PATH" -n1 -c "$FHICL_FILE" -s "$INPUT_FILE"
#ls -l ${HEAP_PROFILE}.*.heap
#echo "Profiles written to ${HEAP_PROFILE}.heap.*"

echo "Running wire-cell under memory profiler"
export HEAPPROFILE="$HEAP_PROFILE"
LD_PRELOAD="$LIB_TCMALLOC" \
  "$PROGRAM_PATH" -l stdout "$CONFIG_FILE" --ext-code elecGain=14
ls -l ${HEAP_PROFILE}.*.heap
echo "Profiles written to ${HEAP_PROFILE}.heap.*"

#6. Detect command and Generate report
PPROF_CMD="$(command -v google-pprof || command -v pprof || true)"

#BIN_DIR="$(dirname "$(which lar)")"
#LIB_DIRS="/cvmfs/larsoft.opensciencegrid.org/products/art/v3_14_04/slf7.x86_64.e26.prof/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/boost/v1_82_0/Linux64bit+3.10-2.17-e26-prof/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/canvas/v3_16_04/slf7.x86_64.e26.prof/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/cetlib_except/v1_09_01/slf7.x86_64.e26.prof/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/cetlib/v3_18_02/slf7.x86_64.e26.prof/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/clhep/v2_4_7_1/Linux64bit+3.10-2.17-e26-prof/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/fhiclcpp/v4_18_04/slf7.x86_64.e26.prof/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/gcc/v12_1_0/Linux64bit+3.10-2.17/lib64"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/hep_concurrency/v1_09_02/slf7.x86_64.e26.prof/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/messagefacility/v2_10_05/slf7.x86_64.e26.prof/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/sqlite/v3_40_01_00/Linux64bit+3.10-2.17/lib"
#LIB_DIRS="$LIB_DIRS:/cvmfs/larsoft.opensciencegrid.org/products/tbb/v2021_9_0/Linux64bit+3.10-2.17-e26/lib"
#LIB_DIRS="$LIB_DIRS:/lib64"
#LIB_DIRS="$LIB_DIRS:/exp/dune/data/users/hnam/demo/wire-cell-toolkit/install/lib"
#export PPROF_BINARY_PATH="$BIN_DIR:$LIB_DIRS"

if [[ -n "$PPROF_CMD" ]]; then
  echo "Generating PDF reports using $PPROF_CMD"

#  # Generate CPU profile report
#  "$PPROF_CMD" --pdf "$PROGRAM_PATH" "$CPU_PROFILE" > cpu_profile.pdf
#  echo "CPU profile report saved as cpu_profile.pdf"

  # Generate memory (heap) profile report
  LATEST_HEAP="$(ls -1 ${HEAP_PROFILE}.*.heap 2>/dev/null | sort | tail -n1 || true)"
  if [[ -n "$LATEST_HEAP" ]]; then
    echo "Latest heap is ${LATEST_HEAP}"
    #"$PPROF_CMD" --pdf "$PROGRAM_PATH" "$LATEST_HEAP" > mem_profile.pdf
    "$PPROF_CMD" --pdf "$PROGRAM_PATH" mem.prof.0056.heap > mem_profile.pdf
    echo "Memory profile report saved as mem_profile.pdf"
  else
    echo "No heap profile file found; skipping memory report"
  fi
else
  echo "pprof tool not found; skipping PDF report generation"
fi

# 7. Create a timestamped results directory and move profiles into it
#RESULT_DIR="gperftools_profiles_$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="gperftools_profiles_$(date +%Y%m%d)"
mkdir -p "$RESULT_DIR"
#mv ${CPU_PROFILE}* ${HEAP_PROFILE}*.*.heap "$RESULT_DIR"/
#echo "All profiling outputs have been moved to $RESULT_DIR"
echo "Profiling session completed"
