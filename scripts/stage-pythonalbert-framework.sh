#!/bin/sh
set -euo pipefail

if [ "${PLATFORM_NAME:-}" != "macosx" ]; then
  echo "Skipping pythonAlbert runtime staging for PLATFORM_NAME=${PLATFORM_NAME:-unknown}"
  exit 0
fi

SRC_RUNTIME_DIR="${SRCROOT}/python-runtime"
SRC_LIBPY="$(find "${SRC_RUNTIME_DIR}/lib" -maxdepth 1 -type f -name 'libpython3*.dylib' | sort | head -n 1)"
SRC_INCLUDE_DIR="$(find "${SRC_RUNTIME_DIR}/include" -maxdepth 1 -type d -name 'python3*' | sort | head -n 1)"

FRAMEWORK_DIR="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
DEST_BIN="${FRAMEWORK_DIR}/${EXECUTABLE_NAME}"
DEST_RESOURCES_DIR="${FRAMEWORK_DIR}/Resources"
DEST_RUNTIME_DIR="${DEST_RESOURCES_DIR}/python-runtime"
DEST_HEADERS_DIR="${FRAMEWORK_DIR}/Headers"
DEST_MODULES_DIR="${FRAMEWORK_DIR}/Modules"
DEST_STAMP="${DEST_RESOURCES_DIR}/.pythonalbert_staged"

echo "Staging pythonAlbert framework payload..."
echo "SRC_RUNTIME_DIR=${SRC_RUNTIME_DIR}"
echo "FRAMEWORK_DIR=${FRAMEWORK_DIR}"

if [ ! -d "${SRC_RUNTIME_DIR}" ]; then
  echo "ERROR: python runtime source folder not found: ${SRC_RUNTIME_DIR}"
  exit 1
fi

if [ -z "${SRC_LIBPY}" ] || [ ! -f "${SRC_LIBPY}" ]; then
  echo "ERROR: No libpython3*.dylib found under ${SRC_RUNTIME_DIR}/lib"
  exit 1
fi

mkdir -p "${DEST_RUNTIME_DIR}" "${DEST_HEADERS_DIR}" "${DEST_MODULES_DIR}"

# Copy full runtime payload into framework resources.
rsync -a --delete "${SRC_RUNTIME_DIR}/" "${DEST_RUNTIME_DIR}/"

# Replace framework binary with libpython so the framework exposes a real shared library.
cp -f "${SRC_LIBPY}" "${DEST_BIN}"
chmod 755 "${DEST_BIN}"
/usr/bin/install_name_tool -id "@rpath/${WRAPPER_NAME}/Versions/A/${EXECUTABLE_NAME}" "${DEST_BIN}" || true

# Expose CPython headers from the bundled runtime.
if [ -z "${SRC_INCLUDE_DIR}" ] || [ ! -d "${SRC_INCLUDE_DIR}" ]; then
  echo "ERROR: No python3* include directory found under ${SRC_RUNTIME_DIR}/include"
  exit 1
fi
rsync -a "${SRC_INCLUDE_DIR}/" "${DEST_HEADERS_DIR}/"

# Add a module map so C/ObjC consumers can include Python.h from the framework.
cat > "${DEST_MODULES_DIR}/module.modulemap" <<EOF
framework module pythonAlbert {
  umbrella header "Python.h"
  export *
  module * { export * }
}
EOF

# Sign nested native code inside runtime; Xcode will sign the framework bundle afterwards.
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
  echo "Signing nested python runtime binaries with ${EXPANDED_CODE_SIGN_IDENTITY}"

  if [ -d "${DEST_RUNTIME_DIR}" ]; then
    find "${DEST_RUNTIME_DIR}" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 | \
      xargs -0 -I{} /usr/bin/codesign --force --timestamp=none --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "{}" || true

    if [ -d "${DEST_RUNTIME_DIR}/bin" ]; then
      find "${DEST_RUNTIME_DIR}/bin" -maxdepth 1 -type f -print0 | \
        xargs -0 -I{} /usr/bin/codesign --force --timestamp=none --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "{}" || true
    fi
  fi
else
  echo "Skipping nested runtime signing (no signing identity)."
fi

touch "${DEST_STAMP}"

echo "pythonAlbert framework staging complete."
