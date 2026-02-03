#!/usr/bin/env bash
# Shared library for Spot Placement Score operations
# Source this file from deployment scripts

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export GREY='\033[1;30m'
export NC='\033[0m' # No Color

# Default configuration
DEFAULT_REGIONS='["westus3"]'
DEFAULT_VM_SIZES='[{"sku": "Standard_D4as_v4"},{"sku": "Standard_D8as_v4"},{"sku": "Standard_D4as_v5"},{"sku": "Standard_D8as_v5"}]'
DEFAULT_VM_COUNT=10

#######################################
# Print a message with color
# Arguments:
#   $1 - Color code
#   $2 - Message
#######################################
print_msg() {
    local color="$1"
    local msg="$2"
    echo -e "${color}${msg}${NC}"
}

#######################################
# Print success message with checkmark
# Arguments:
#   $1 - Message
#######################################
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

#######################################
# Print info message
# Arguments:
#   $1 - Message
#######################################
print_info() {
    echo -e "${GREY}$1${NC}"
}

#######################################
# Print warning message
# Arguments:
#   $1 - Message
#######################################
print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

#######################################
# Print error message and exit
# Arguments:
#   $1 - Message
#   $2 - Exit code (default: 1)
#######################################
print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit "${2:-1}"
}

#######################################
# Print header banner
# Arguments:
#   $1 - Title
#######################################
print_header() {
    local title="$1"
    echo -e "${GREEN}========================================${NC}"
    echo -e "$title"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

#######################################
# Load configuration from environment or defaults
# Sets global variables: SUBSCRIPTION_ID, RESOURCE_GROUP, CLUSTER_NAME, etc.
# Arguments:
#   $1 - Default resource group name
#   $2 - Default cluster name
#######################################
load_config() {
    local default_rg="${1:-aks-sps-rg}"
    local default_cluster="${2:-aks-sps-cluster}"

    SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null)}
    RESOURCE_GROUP=${AZURE_RESOURCE_GROUP_NAME:-$default_rg}
    CLUSTER_NAME=${AZURE_AKS_CLUSTER_NAME:-$default_cluster}
    REGIONS=${PREFERRED_REGIONS:-$DEFAULT_REGIONS}
    SKU_SIZES=${PREFERRED_VM_SIZES:-$DEFAULT_VM_SIZES}
    VM_COUNT=${DESIRED_VM_COUNT:-$DEFAULT_VM_COUNT}

    # Extract first region for API location parameter
    API_LOCATION=$(echo "$REGIONS" | jq -r '.[0]')

    if [ -z "$SUBSCRIPTION_ID" ]; then
        print_error "SUBSCRIPTION_ID is not set and could not be determined from Azure CLI"
    fi
}

#######################################
# Print current configuration
#######################################
print_config() {
    print_info "✓ Subscription ID: ${SUBSCRIPTION_ID}"
    print_info "✓ Resource Group: ${RESOURCE_GROUP}"
    print_info "✓ Cluster Name: ${CLUSTER_NAME}"
    print_info "✓ Regions: ${REGIONS}"
    print_info "✓ SKU Sizes: ${SKU_SIZES}"
    print_info "✓ VM Count: ${VM_COUNT}"
    echo ""
}

#######################################
# Query Azure Spot Placement Score API
# Sets global variable: SCORE_RESULTS
#######################################
query_spot_placement_scores() {
    print_info "Querying Azure Spot Placement Score API..."
    
    SCORE_RESULTS=$(az compute-recommender spot-placement-score \
        --location "$API_LOCATION" \
        --subscription "$SUBSCRIPTION_ID" \
        --availability-zones true \
        --desired-locations "$REGIONS" \
        --desired-count "$VM_COUNT" \
        --desired-sizes "$SKU_SIZES" 2>&1)

    if [ -z "$SCORE_RESULTS" ]; then
        print_error "Failed to get spot placement scores from Azure API"
    fi

    if ! echo "$SCORE_RESULTS" | jq -e '.placementScores' >/dev/null 2>&1; then
        print_error "Invalid response from Azure API. Response: $SCORE_RESULTS"
    fi

    print_success "Successfully retrieved spot placement scores"
    echo ""
}

#######################################
# Process placement scores into categorized lists
# Sets global variables: HIGH_SKUS, MEDIUM_SKUS, LOW_SKUS, *_COUNT, *_DISPLAY
#######################################
process_placement_scores() {
    print_info "Processing placement scores..."

    # Get unique SKU names as JSON arrays
    HIGH_SKUS=$(echo "$SCORE_RESULTS" | jq -r '[.placementScores[] | select(.score == "High") | .sku] | unique')
    MEDIUM_SKUS=$(echo "$SCORE_RESULTS" | jq -r '[.placementScores[] | select(.score == "Medium") | .sku] | unique')
    LOW_SKUS=$(echo "$SCORE_RESULTS" | jq -r '[.placementScores[] | select(.score == "Low") | .sku] | unique')

    # Count unique VM sizes for each score level
    HIGH_COUNT=$(echo "$HIGH_SKUS" | jq 'length')
    MEDIUM_COUNT=$(echo "$MEDIUM_SKUS" | jq 'length')
    LOW_COUNT=$(echo "$LOW_SKUS" | jq 'length')

    # Get comma-separated SKU names for display
    HIGH_SKUS_DISPLAY=$(echo "$HIGH_SKUS" | jq -r 'join(", ")')
    MEDIUM_SKUS_DISPLAY=$(echo "$MEDIUM_SKUS" | jq -r 'join(", ")')
    LOW_SKUS_DISPLAY=$(echo "$LOW_SKUS" | jq -r 'join(", ")')

    print_success "Placement scores processed"
    echo ""
}

#######################################
# Display placement scores in a formatted table
#######################################
display_score_table() {
    print_warning "Placement Score Summary:"

    # Calculate dynamic column widths
    local col1_width=15  # Confidence
    local col2_width=15  # No. of Sizes
    local max_sku_len
    max_sku_len=$(printf "%s\n%s\n%s" "${#HIGH_SKUS_DISPLAY}" "${#MEDIUM_SKUS_DISPLAY}" "${#LOW_SKUS_DISPLAY}" | sort -nr | head -1)
    local col3_width=$((max_sku_len > 50 ? max_sku_len + 2 : 50))

    # Generate border lines dynamically
    local border_line
    border_line=$(printf "+%${col1_width}s+%${col2_width}s+%${col3_width}s+" | tr ' ' '-')

    # Print table with dynamic widths
    printf "%s\n" "$border_line"
    printf "| %-$((col1_width-2))s | %-$((col2_width-2))s | %-$((col3_width-2))s |\n" "Confidence" "No. of Sizes" "VM Sizes"
    printf "%s\n" "$border_line"
    printf "| ${GREEN}%-$((col1_width-2))s${NC} | %-$((col2_width-2))s | %-$((col3_width-2))s |\n" "High" "$HIGH_COUNT" "$HIGH_SKUS_DISPLAY"
    printf "| ${YELLOW}%-$((col1_width-2))s${NC} | %-$((col2_width-2))s | %-$((col3_width-2))s |\n" "Medium" "$MEDIUM_COUNT" "$MEDIUM_SKUS_DISPLAY"
    printf "| ${RED}%-$((col1_width-2))s${NC} | %-$((col2_width-2))s | %-$((col3_width-2))s |\n" "Low" "$LOW_COUNT" "$LOW_SKUS_DISPLAY"
    printf "%s\n" "$border_line"
    echo ""
}

#######################################
# Save spot placement scores to JSON file
# Arguments:
#   $1 - Output file path (default: spot-placement-scores.json)
#######################################
save_scores_to_file() {
    local output_file="${1:-spot-placement-scores.json}"
    print_info "Saving results to ${output_file}..."
    echo "$SCORE_RESULTS" | jq '.' > "$output_file"
    print_success "Results saved"
    echo ""
}

#######################################
# Configure kubectl context for AKS cluster
#######################################
configure_kubectl() {
    print_info "Configuring AKS credentials..."
    az account set --subscription "$SUBSCRIPTION_ID" > /dev/null
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing > /dev/null
    kubelogin convert-kubeconfig -l azurecli > /dev/null
    print_success "AKS credentials configured"
    echo ""
}

#######################################
# Apply a Kubernetes manifest
# Arguments:
#   $1 - Manifest file path
#   $2 - Dry run mode (true/false)
#######################################
apply_manifest() {
    local manifest_file="$1"
    local dry_run="${2:-false}"

    if [ "$dry_run" = "true" ]; then
        print_warning "[DRY RUN] Would apply manifest:"
        echo "---"
        cat "$manifest_file"
        echo "---"
    else
        print_info "Applying manifest to AKS cluster..."
        kubectl apply -f "$manifest_file"
        print_success "Manifest applied successfully"
    fi
    echo ""
}

#######################################
# Parse common CLI arguments
# Arguments:
#   All script arguments ($@)
# Sets global variables: DRY_RUN, VERBOSE, SHOW_HELP
#######################################
parse_args() {
    DRY_RUN=false
    VERBOSE=false
    SHOW_HELP=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                SHOW_HELP=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

#######################################
# Print usage information
# Arguments:
#   $1 - Script name
#   $2 - Description
#######################################
print_usage() {
    local script_name="$1"
    local description="$2"
    
    cat << EOF
${description}

Usage: ${script_name} [OPTIONS]

Options:
  -n, --dry-run    Preview changes without applying to cluster
  -v, --verbose    Enable verbose output
  -h, --help       Show this help message

Environment Variables:
  AZURE_SUBSCRIPTION_ID       Azure subscription ID (default: current subscription)
  AZURE_RESOURCE_GROUP_NAME   Resource group name
  AZURE_AKS_CLUSTER_NAME      AKS cluster name
  PREFERRED_REGIONS           JSON array of regions (default: ["westus3"])
  PREFERRED_VM_SIZES          JSON array of VM SKUs to assess
  DESIRED_VM_COUNT            Number of VMs for scoring (default: 10)

Examples:
  ${script_name}                     # Run with defaults
  ${script_name} --dry-run           # Preview without applying
  ${script_name} --verbose           # Detailed output

EOF
}
