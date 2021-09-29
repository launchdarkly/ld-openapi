#!/usr/bin/env bash
set -e

# run-scripts-for-targets SCRIPTS_DIR VERSION MESSAGE TARGET_NAMES...
# For every NAME in TARGET_NAMES, if a script NAME.sh exists in SCRIPTS_DIR,
# runs that script with the parameters BUILD_DIR NAME VERSION-- where BUILD_DIR
# is targets/build/api-client-NAME, which we copy from targets/api-client-NAME
# so that any files created by the script won't be accidentally committed to
# the source repo.

scripts_dir=$1
version=$2
message=$3
shift
shift
shift
target_names="$@"

temp_dir=$(mktemp -d)
trap "rm -rf ${temp_dir}" EXIT

for target_name in ${target_names}; do
  script_path=${scripts_dir}/${target_name}.sh

  if [ -f "${script_path}" ]; then
    echo
    echo "*** ${message} for ${target_name}..."
    repo_name=api-client-${target_name}
    build_dir=targets/build/${repo_name}
    if [ ! -d "${build_dir}" ]; then
      mkdir -p ${build_dir}
      cp -r targets/${repo_name}/. ${build_dir}
    fi

    ${script_path} ${build_dir} ${target_name} ${version}
  fi
done
