#!/usr/bin/env bash
set -euo pipefail

# ——————————————————————————
# Hardcoded settings (modify as needed)
CONFIG_SRC="wct-sim-drift-deposplat_test.jsonnet"
EXT_CODE="elecGain=14"
Date="09072025"
THRESHOLD=100
MODEL="mobilenetv3"
RESULT_DIR="/exp/dune/data/users/hnam/wire-cell-hnam/larwc/wire-cell-cfg/pgrapher/experiment/pdhd/${MODEL}_thr${THRESHOLD}"
ANGLES=(0 10 20 30 40 50 60 70 80 85)
# ——————————————————————————

# Create the result directory if it doesn't exist
mkdir -p "${RESULT_DIR}"

for ANG in "${ANGLES[@]}"; do
  echo "=== Running simulation with angleXZ_deg=${ANG}° ==="

  # 1) Generate a temporary Jsonnet config file with the updated angle
  TMP_CFG="cfg_angle${ANG}.jsonnet"
  sed -e "s/^local angleXZ_deg = .*/local angleXZ_deg = ${ANG};/" \
      "${CONFIG_SRC}" > "${TMP_CFG}"

  # 2) Run the Wire-Cell simulation
  /usr/bin/time -v wire-cell -l stdout "${TMP_CFG}" --ext-code "${EXT_CODE}"

  # 3) Move the generated magnify root file to the result directory
  MAG="pdhd-sim-check-deposplat_apa_01_trk_xz${ANG}_${Date}.root"
  if [[ -f "${MAG}" ]]; then
    mv "${MAG}" "${RESULT_DIR}/"
    echo "Moved ${MAG} to ${RESULT_DIR}/"
  else
    echo "Warning: ${MAG} not found"
  fi

  # 4) Remove the temporary Jsonnet file
  rm -f "${TMP_CFG}"
done

echo
echo "All done! Root files are in: ${RESULT_DIR}"

