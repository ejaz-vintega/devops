#!/bin/bash

# Test script for server-setup.sh

# --- Global Test Counters & Flag ---
_TOTAL_TESTS=0
_PASSED_TESTS=0
_FAILED_TESTS=0
_CURRENT_TEST_HAS_FAILED=false

# --- Configuration ---
SERVER_SETUP_SCRIPT="./server-setup.sh" # Path to the script to be tested
MOCK_DIR="./mocks" # Directory to store mock scripts
LOG_FILE="test_run.log" # Log file for mock command calls

# --- Helper Functions ---

# Function to reset mocks and logs before each test
reset_test_env() {
    echo "Resetting test environment..." > $LOG_FILE
    # Create mock directory if it doesn't exist
    mkdir -p "$MOCK_DIR"
    # Remove old mock scripts if any
    rm -f "$MOCK_DIR"/*
    # Create essential mocks for general use
    create_essential_mocks
}

# Function to create essential mock commands
create_essential_mocks() {
    echo "Creating essential mock commands..." >> $LOG_FILE
    create_mock "apt-get"
    create_mock "npm"
    create_mock "git"
    create_mock "ssh-keyscan"
    create_mock "certbot"
    create_mock "service"
    create_mock "systemctl"
    create_mock "pm2"
    create_mock "gpg"
    create_mock "curl"
    create_mock "tee"
    create_mock "snap"
    create_mock "mkdir"
    create_mock "chown"
    # Define mock script content for cd, mkdir, rm, ln
    # Note: LOG_FILE and MOCK_DIR are global vars in test_server_setup.sh
    # They need to be accessed carefully within the mock scripts.
    # base_dir within mock scripts refers to the directory of test_server_setup.sh

    local cd_mock_script_content='
local base_dir="$(cd $(dirname "$0")/../)" # Relative to mock script, up to test_server_setup.sh dir
local log_file="$base_dir/'$LOG_FILE'" # Log file path
local mock_root_dir="$base_dir/'$MOCK_DIR'" # Mock root directory, MOCK_DIR is like "./mocks"

local target_dir="$1"
local actual_cd_path=""

# Log the attempt first
echo "Mock cd (override) attempt to cd to: $target_dir with args: $@" >> "$log_file"

# Define specific paths that should be sandboxed
if [[ "$target_dir" == "/etc/nginx/sites-available" || \
      "$target_dir" == "/etc/nginx/sites-enabled" || \
      "$target_dir" == "/etc/nginx" || \
      "$target_dir" == "/var/www" || \
      "$target_dir" == "/var/www/"* ]]; then
    actual_cd_path="$mock_root_dir${target_dir}"
    # Ensure the mock directory exists before trying to cd into it
    command mkdir -p "$actual_cd_path" # Use actual mkdir
    cd "$actual_cd_path"
    echo "Mock cd (override) actually changed directory to: $(pwd) (logical: $target_dir)" >> "$log_file"
else
    echo "Mock cd (override) called with unhandled path: $target_dir. Current PWD: $(pwd). Not changing directory." >> "$log_file"
fi
# cd does not have an explicit exit status in the mock
'
    create_mock "cd" "$cd_mock_script_content" "true"

    local mkdir_mock_script_content='
local base_dir="$(cd $(dirname "$0")/../)"
local log_file="$base_dir/'$LOG_FILE'"
local mock_root_dir="$base_dir/'$MOCK_DIR'"
echo "Mock mkdir (override) called with: $@" >> "$log_file"
for dir_path_arg in "$@"; do
  if [[ "$dir_path_arg" == -* ]]; then continue; fi # Handle options like -p
  local dir_path="$dir_path_arg"
  actual_path="$dir_path"
  if [[ "$dir_path" == /* ]]; then
      actual_path="$mock_root_dir${dir_path}"
  else
      # Resolve relative paths against current mock PWD, which should be a sandboxed path if cd mock worked
      actual_path="$(pwd)/${dir_path}"
  fi
  echo "Mock mkdir (override) creating (or ensuring existence of): $actual_path (logical: $dir_path)" >> "$log_file"
  command mkdir -p "$actual_path" # Use actual mkdir -p
done
exit 0
'
    create_mock "mkdir" "$mkdir_mock_script_content" "true"

    local rm_mock_script_content='
local base_dir="$(cd $(dirname "$0")/../)"
local log_file="$base_dir/'$LOG_FILE'"
local mock_root_dir="$base_dir/'$MOCK_DIR'"
echo "Mock rm (override) called with: $@" >> "$log_file"
for item_path_arg in "$@"; do
  if [[ "$item_path_arg" == -* ]]; then continue; fi # Skip options like -r, -f
  local item_path="$item_path_arg"
  actual_path="$item_path"
  if [[ "$item_path" == /* ]]; then
      actual_path="$mock_root_dir${item_path}"
  else
      actual_path="$(pwd)/${item_path}"
  fi
  echo "Mock rm (override) attempting to remove: $actual_path (logical: $item_path)" >> "$log_file"
  command rm -rf "$actual_path" # Use actual rm -rf
done
exit 0
'
    create_mock "rm" "$rm_mock_script_content" "true"

    local ln_mock_script_content='
local base_dir="$(cd $(dirname "$0")/../)"
local log_file="$base_dir/'$LOG_FILE'"
local mock_root_dir="$base_dir/'$MOCK_DIR'"
echo "Mock ln (override) called with: $@" >> "$log_file"
target_path=""
link_name=""
is_symbolic=false
# Simple loop for args; assumes -s is separate, target then link_name
# Does not handle -sTargetLink or other orderings robustly
for arg in "$@"; do
  if [[ "$arg" == "-s" ]]; then
    is_symbolic=true
  elif [ -z "$target_path" ]; then
    target_path="$arg"
  else
    link_name="$arg"
  fi
done

if [ -n "$target_path" ] && [ -n "$link_name" ]; then
  actual_target_path="$target_path"
  actual_link_name="$link_name"

  # Prepend mock_root_dir if paths are absolute
  if [[ "$target_path" == /* ]]; then actual_target_path="$mock_root_dir${target_path}"; fi
  if [[ "$link_name" == /* ]]; then actual_link_name="$mock_root_dir${link_name}"; fi
  # Relative paths are relative to the current PWD of the mock script

  echo "Mock ln (override) attempting: command ln ${is_symbolic:+-s} \"$actual_target_path\" \"$actual_link_name\"" >> "$log_file"
  if $is_symbolic; then
    command ln -s "$actual_target_path" "$actual_link_name"
  else
    command ln "$actual_target_path" "$actual_link_name"
  fi
else
  echo "Mock ln (override) could not parse target/link from: $@" >> "$log_file"
fi
exit 0
'
    create_mock "ln" "$ln_mock_script_content" "true"

    create_mock "sudo" # Ensures sudo is always available as a basic mock
}

# Function to create a mock command
# Usage: create_mock "command_name" ["mock_behavior_script_lines"] [is_full_script_override (true/false)]
create_mock() {
    local cmd_name="$1"
    local mock_script_lines="${2:-}"
    local is_full_override="${3:-false}"
    local mock_file_path="$MOCK_DIR/$cmd_name"

    echo "#!/bin/bash" > "$mock_file_path" # Start with shebang for all
    if [ "$is_full_override" = "true" ]; then
        echo "# Mock for $cmd_name (full override)" >> "$mock_file_path"
        # Ensure that variables like $LOG_FILE and $MOCK_DIR are correctly expanded if they are part of mock_script_lines
        # For full overrides, the script lines are responsible for their own logging and PATH.
        echo "$mock_script_lines" >> "$mock_file_path"
    else
        echo "# Mock for $cmd_name" >> "$mock_file_path"
        # Ensure log file path is robust, relative to the main test script directory
        echo "echo "Mock $cmd_name called with: \$@" >> "\$(cd \$(dirname "\$0")/../$LOG_FILE)"" >> "$mock_file_path"
        if [ -n "$mock_script_lines" ]; then
            echo "$mock_script_lines" >> "$mock_file_path"
        fi
        echo "export PATH=\$(cd \$(dirname "\$0") && pwd):\$PATH" >> "$mock_file_path"
        echo "exit 0" >> "$mock_file_path"
    fi
    chmod +x "$mock_file_path"
}

# Function to run server-setup.sh with predefined inputs
# Outputs the exit code of server-setup.sh
run_server_setup_with_inputs() {
    local inputs_string=""
    for input_line in "$@"; do
        inputs_string+="${input_line}\n"
    done

    echo "Running server-setup.sh with inputs:" >> "$LOG_FILE" # Log to main log
    printf "%s" "$inputs_string" >> "$LOG_FILE"
    echo "--- End of Inputs ---" >> "$LOG_FILE"

    (printf "%s" "$inputs_string" | PATH="$MOCK_DIR:$PATH" bash "$SERVER_SETUP_SCRIPT") > setup_output.log 2>&1
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo "server-setup.sh exited with code $exit_code. Output:" >> "$LOG_FILE"
        cat setup_output.log >> "$LOG_FILE"
    fi
    return $exit_code
}

# Function to assert the last command's exit code
# Usage: assert_exit_code <expected_code> <last_exit_code>
assert_exit_code() {
    local expected_code="$1"
    local last_exit_code="$2" # Passed in from $?
    if [ "$last_exit_code" -eq "$expected_code" ]; then
        echo "PASS: Script exited with expected code '$expected_code'."
    else
        echo "FAIL: Script exited with code '$last_exit_code', expected '$expected_code'."
        _CURRENT_TEST_HAS_FAILED=true
    fi
}

# Function to assert that a command was called (by checking the log)
# Usage: assert_command_called "command_name with_args"
assert_command_called() {
    local expected_call="$1"
    # Strip "Mock " prefix for searching if present, to be flexible
    local search_pattern="${expected_call#Mock }" 
    # Ensure we are searching for "Mock actual_command args"
    if [[ "$expected_call" != "Mock "* ]]; then
        search_pattern="Mock $expected_call"
    else
        # If user already provided "Mock ...", use it as is
        search_pattern="$expected_call"
    fi

    if grep -q -- "$search_pattern" "$LOG_FILE"; then # Use -- to handle patterns starting with -
        echo "PASS: Expected command pattern '$search_pattern' was found in log."
    else
        echo "FAIL: Expected command pattern '$search_pattern' was NOT found in log."
        _CURRENT_TEST_HAS_FAILED=true
    fi
}

# Function to assert that a file exists
# Usage: assert_file_exists "/path/to/file"
assert_file_exists() {
    local file_path="$1"
    local actual_path="$file_path"
    if [[ "$file_path" == /* ]]; then
        actual_path="$PWD/$MOCK_DIR$file_path"
    fi
    if [ -f "$actual_path" ]; then
        echo "PASS: File '$actual_path' (logical: '$file_path') exists."
    else
        echo "FAIL: File '$actual_path' (logical: '$file_path') does NOT exist."
        _CURRENT_TEST_HAS_FAILED=true
    fi
}

# Function to assert that a file contains specific content
# Usage: assert_file_contains "/path/to/file" "expected content"
assert_file_contains() {
    local file_path="$1"
    local expected_content="$2"
    local actual_path="$file_path"
    if [[ "$file_path" == /* ]]; then
        actual_path="$PWD/$MOCK_DIR$file_path"
    fi

    if [ ! -f "$actual_path" ]; then
        echo "FAIL: File '$actual_path' (logical: '$file_path') does not exist, cannot check content."
        _CURRENT_TEST_HAS_FAILED=true
        return
    fi

    if grep -q -- "$expected_content" "$actual_path"; then
        echo "PASS: File '$actual_path' (logical: '$file_path') contains expected content."
    else
        echo "FAIL: File '$actual_path' (logical: '$file_path') does NOT contain expected content: '$expected_content'."
        echo "------- FILE CONTENT START -------"
        cat "$actual_path"
        echo "------- FILE CONTENT END -------"
        _CURRENT_TEST_HAS_FAILED=true
    fi
}

# Function to assert that the main log file ($LOG_FILE) contains specific content
# Usage: assert_log_contains "expected content"
assert_log_contains() {
    local expected_content="$1"
    if grep -q -- "$expected_content" "$LOG_FILE"; then
        echo "PASS: Log file '$LOG_FILE' contains expected content: '$expected_content'."
    else
        echo "FAIL: Log file '$LOG_FILE' does NOT contain expected content: '$expected_content'."
        _CURRENT_TEST_HAS_FAILED=true
    fi
}

# Function to assert that the main log file ($LOG_FILE) does NOT contain specific content
# Usage: assert_log_does_not_contain "unexpected content"
assert_log_does_not_contain() {
    local unexpected_content="$1"
    if ! grep -q -- "$unexpected_content" "$LOG_FILE"; then
        echo "PASS: Log file '$LOG_FILE' does NOT contain unexpected content: '$unexpected_content'."
    else
        echo "FAIL: Log file '$LOG_FILE' CONTAINS unexpected content: '$unexpected_content'."
        _CURRENT_TEST_HAS_FAILED=true
    fi
}

# Function to assert that setup_output.log contains specific content
# Usage: assert_output_contains "expected content"
assert_output_contains() {
    local expected_content="$1"
    if grep -q -- "$expected_content" "setup_output.log"; then # Use -- for fixed string matching
        echo "PASS: Output contains expected content: '$expected_content'."
    else
        echo "FAIL: Output does NOT contain expected content: '$expected_content'."
        _CURRENT_TEST_HAS_FAILED=true
    fi
}

# Function to assert that setup_output.log does NOT contain specific content
# Usage: assert_output_does_not_contain "unexpected content"
assert_output_does_not_contain() {
    local unexpected_content="$1"
    if ! grep -q -- "$unexpected_content" "setup_output.log"; then # Use -- for fixed string matching
        echo "PASS: Output does not contain unexpected content: '$unexpected_content'."
    else
        echo "FAIL: Output CONTAINS unexpected content: '$unexpected_content'."
        _CURRENT_TEST_HAS_FAILED=true
    fi
}

# Wrapper function to run a single test case and track results
run_test_case() {
    local test_function_name="$1"
    echo "" # Add a blank line for readability
    echo "--------------------------------------------------"
    echo "Running Test Case: $test_function_name"
    echo "--------------------------------------------------"
    
    _TOTAL_TESTS=$((_TOTAL_TESTS + 1))
    _CURRENT_TEST_HAS_FAILED=false # Reset for the current test

    # Call the actual test function passed as argument
    "$test_function_name"
    
    if [ "$_CURRENT_TEST_HAS_FAILED" = true ]; then
        _FAILED_TESTS=$((_FAILED_TESTS + 1))
        echo "--------------------------------------------------"
        echo "Test Case Result: $test_function_name - FAIL"
        echo "--------------------------------------------------"
    else
        _PASSED_TESTS=$((_PASSED_TESTS + 1))
        echo "--------------------------------------------------"
        echo "Test Case Result: $test_function_name - PASS"
        echo "--------------------------------------------------"
    fi
}


# --- Test Cases ---

test_case_1_example() {
    echo "Running Test Case 1: Basic execution path..."
    reset_test_env

    declare -a inputs=(
        "20"                 # Node.js major version
        "myTestProject"      # Project name
        "0"                  # Optional software: none
        "192.168.1.100"      # Private IP
        "3000"               # Node port
        "v1"                 # Node dir
        "test.example.com"   # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    assert_command_called "sudo apt-get update"
    assert_command_called "apt-get update" 
    echo "Test Case 1 completed."
}

test_input_validation_optional_software_invalid_chars() {
    echo "Running Test Case: Optional Software - Invalid Characters..."
    reset_test_env

    declare -a inputs=(
        "20"                    # Node.js major version
        "testInvalidChars"      # Project name
        "a,b,c"                 # INVALID software choices (first attempt)
        "0"                     # VALID software choice (second attempt, to exit loop)
        "192.168.1.101"         # Private IP
        "3001"                  # Node port
        "v1invalid"             # Node dir
        "invalid.example.com"   # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    assert_output_contains "Invalid input format. Please use comma-separated numbers"
    assert_output_contains "No optional software selected." # Because "0" was provided next
    echo "Test Case completed."
}

test_input_validation_optional_software_out_of_range() {
    echo "Running Test Case: Optional Software - Out of Range..."
    reset_test_env

    declare -a inputs=(
        "20"                    # Node.js major version
        "testOutOfRange"        # Project name
        "1,4,2"                 # INVALID software choices (4 is out of range)
        "0"                     # VALID software choice (to exit loop)
        "192.168.1.102"         # Private IP
        "3002"                  # Node port
        "v1outofrange"          # Node dir
        "outofrange.example.com" # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    assert_output_contains "Invalid option: '4'."
    assert_output_contains "No optional software selected." # Because "0" was provided next
    echo "Test Case completed."
}

test_input_validation_optional_software_duplicates() {
    echo "Running Test Case: Optional Software - Duplicates..."
    reset_test_env

    declare -a inputs=(
        "20"                    # Node.js major version
        "testDuplicates"        # Project name
        "1,2,1"                 # INVALID software choices (1 is duplicated)
        "0"                     # VALID software choice (to exit loop)
        "192.168.1.103"         # Private IP
        "3003"                  # Node port
        "v1duplicates"          # Node dir
        "duplicates.example.com" # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    assert_output_contains "Duplicate option: '1'."
    assert_output_contains "No optional software selected." # Because "0" was provided next
    echo "Test Case completed."
}

test_input_validation_optional_software_empty_then_valid() {
    echo "Running Test Case: Optional Software - Empty then Valid..."
    reset_test_env

    declare -a inputs=(
        "20"                    # Node.js major version
        "testEmptyThenValid"    # Project name
        ""                      # INVALID software choices (first attempt - empty)
        "1,2"                   # VALID software choice (second attempt)
        "192.168.1.104"         # Private IP
        "3004"                  # Node port
        "v2emptyvalid"          # Node dir
        "emptyvalid.example.com" # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    assert_output_contains "Invalid input format. Please use comma-separated numbers" # For the empty input
    assert_output_contains "Selected options:"
    assert_output_contains "- MongoDB installation" # Note: server-setup.sh has "MonngoDb"
    assert_output_contains "- Redis cache installation"
    echo "Test Case completed."
}

test_input_validation_optional_software_valid_zero() {
    echo "Running Test Case: Optional Software - Valid Zero..."
    reset_test_env

    declare -a inputs=(
        "20"                # Node.js major version
        "testValidZero"     # Project name
        "0"                 # VALID software choice: none
        "192.168.1.105"     # Private IP
        "3005"              # Node port
        "v3zero"            # Node dir
        "zero.example.com"  # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    assert_output_contains "No optional software selected."
    assert_output_does_not_contain "Installing MonngoDb"
    assert_output_does_not_contain "Installing Redis"
    assert_output_does_not_contain "Starting git cloning process"
    echo "Test Case completed."
}

test_install_mongodb_selected() {
    echo "Running Test Case: Install MongoDB Selected..."
    reset_test_env

    declare -a inputs=(
        "20"                    # Node.js major version
        "mongoProject"          # Project name
        "1"                     # Optional software: MongoDB
        "192.168.1.110"         # Private IP
        "3010"                  # Node port
        "v1mongo"               # Node dir
        "mongo.example.com"     # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    assert_output_contains "Selected options:"
    assert_output_contains "- MongoDB installation"
    assert_output_contains "Installing MonngoDb"
    assert_command_called "sudo apt-get install -y mongodb-org"
    assert_command_called "sudo mkdir /data"
    assert_command_called "sudo mkdir /data/db"
    assert_command_called "service mongod start"
    assert_command_called "sudo systemctl enable mongod"
    assert_command_called "sudo systemctl start mongod"
    echo "Test Case completed."
}

test_install_redis_selected() {
    echo "Running Test Case: Install Redis Selected..."
    reset_test_env

    declare -a inputs=(
        "20"                    # Node.js major version
        "redisProject"          # Project name
        "2"                     # Optional software: Redis
        "192.168.1.111"         # Private IP
        "3011"                  # Node port
        "v1redis"               # Node dir
        "redis.example.com"     # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    assert_output_contains "Selected options:"
    assert_output_contains "- Redis cache installation"
    assert_output_contains "Installing Redis"
    assert_command_called "sudo npm install redis"
    echo "Test Case completed."
}

test_install_repository_selected() {
    echo "Running Test Case: Install Repository Selected..."
    reset_test_env

    declare -a inputs=(
        "20"                        # Node.js major version
        "repoProject"               # Project name
        "3"                         # Optional software: Repository
        "git@github.com:test/repo.git" # Repo URL
        "192.168.1.112"             # Private IP
        "3012"                      # Node port
        "v1repo"                    # Node dir
        "repo.example.com"          # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    assert_output_contains "Selected options:"
    assert_output_contains "- Clone repository"
    assert_output_contains "Starting git cloning process"
    assert_command_called "chmod 600 /root/.ssh/id_rsa" # Script uses /root/.ssh
    assert_command_called "ssh-keyscan github.com"
    assert_command_called "sudo git clone git@github.com:test/repo.git"
    echo "Test Case completed."
}

test_install_all_selected() {
    echo "Running Test Case: Install All Optional Software Selected..."
    reset_test_env

    declare -a inputs=(
        "20"                        # Node.js major version
        "allProject"                # Project name
        "1,2,3"                     # Optional software: All
        "git@github.com:test/all.git" # Repo URL
        "192.168.1.113"             # Private IP
        "3013"                      # Node port
        "v1all"                     # Node dir
        "all.example.com"           # Server name
    )

    run_server_setup_with_inputs "${inputs[@]}"
    
    # MongoDB assertions
    assert_output_contains "- MongoDB installation"
    assert_output_contains "Installing MonngoDb"
    assert_command_called "sudo apt-get install -y mongodb-org"
    assert_command_called "service mongod start"
    assert_command_called "sudo systemctl enable mongod"
    assert_command_called "sudo systemctl start mongod"

    # Redis assertions
    assert_output_contains "- Redis cache installation"
    assert_output_contains "Installing Redis"
    assert_command_called "sudo npm install redis"

    # Repository cloning assertions
    assert_output_contains "- Clone repository"
    assert_output_contains "Starting git cloning process"
    assert_command_called "chmod 600 /root/.ssh/id_rsa" # Script uses /root/.ssh
    assert_command_called "ssh-keyscan github.com"
    assert_command_called "sudo git clone git@github.com:test/all.git"
    echo "Test Case completed."
}


# --- Main Test Execution ---
echo "Starting tests for server-setup.sh..."

run_test_case "test_case_1_example"
run_test_case "test_input_validation_optional_software_invalid_chars"
run_test_case "test_input_validation_optional_software_out_of_range"
run_test_case "test_input_validation_optional_software_duplicates"
run_test_case "test_input_validation_optional_software_empty_then_valid"
run_test_case "test_input_validation_optional_software_valid_zero"
run_test_case "test_install_mongodb_selected"
run_test_case "test_install_redis_selected"
run_test_case "test_install_repository_selected"
run_test_case "test_install_all_selected"
run_test_case "test_nginx_configuration"
run_test_case "test_project_setup_and_startup"

# test_prereq_missing_id_rsa is skipped by not calling it via run_test_case
# If it were to be included and counted as skipped, run_test_case would need modification
# or the test function itself would need to adjust counters.
test_prereq_missing_id_rsa # Direct call, does not affect counters

run_test_case "test_prereq_node_exists"
run_test_case "test_prereq_nginx_exists_running"
run_test_case "test_prereq_nginx_exists_not_running"
run_test_case "test_prereq_git_exists"
run_test_case "test_prereq_npm_exists"


# --- Final Summary ---
echo ""
echo "=================================================="
echo "Test Summary"
echo "=================================================="
echo "Total Tests Run: $_TOTAL_TESTS"
echo "Passed: $_PASSED_TESTS"
echo "Failed: $_FAILED_TESTS"
echo "=================================================="

# Exit with a status code indicating overall success or failure
if [ "$_FAILED_TESTS" -gt 0 ]; then
    exit 1
else
    exit 0
fi
# --- End of Script ---
