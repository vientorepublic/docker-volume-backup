#!/bin/bash
# Docker Volume Backup & Restore Utility

set -euo pipefail

# Configuration
BACKUP_IMAGE="busybox"
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

usage() {
    cat << EOF
Docker Volume Backup & Restore Utility

Usage:
    $0 backup <volume_name> [output_file]
    $0 restore <volume_name> <input_file>
    $0 -h|--help

Commands:
    backup      Create a compressed backup of a Docker volume
    restore     Restore a Docker volume from a backup file

Options:
    -h, --help  Show this help message
    -v          Verbose output

Examples:
    $0 backup my_volume
    $0 backup my_volume custom_backup.tar.gz
    $0 restore my_volume my_volume_backup_20241007_143022.tar.gz

EOF
    exit "${1:-0}"
}

check_dependencies() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker is not running or not accessible"
        exit 1
    fi
}

validate_volume_name() {
    local volume_name="$1"
    if [[ ! "$volume_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        log_error "Invalid volume name: '$volume_name'. Volume names must start with alphanumeric character and contain only letters, numbers, underscores, periods, and hyphens."
        exit 1
    fi
}

validate_filename() {
    local filename="$1"
    # Check for path traversal attempts and invalid characters
    if [[ "$filename" =~ \.\./|^/|[\|\;\&\$\`\\] ]]; then
        log_error "Invalid filename: '$filename'. Filename contains potentially dangerous characters."
        exit 1
    fi
}

volume_exists() {
    local volume_name="$1"
    docker volume inspect "$volume_name" &> /dev/null
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        backup|restore)
            COMMAND="$1"
            shift
            break
            ;;
        *)
            log_error "Unknown option: $1"
            usage 1
            ;;
    esac
done

if [[ -z "${COMMAND:-}" ]]; then
    log_error "No command specified"
    usage 1
fi

if [[ $# -lt 1 ]]; then
    log_error "Volume name is required"
    usage 1
fi

VOLUME=$1
shift

# Validate inputs
check_dependencies
validate_volume_name "$VOLUME"

case "$COMMAND" in
    backup)
        OUTPUT_FILE=${1:-"${VOLUME}_backup_$(date +%Y%m%d_%H%M%S).tar.gz"}
        validate_filename "$OUTPUT_FILE"
        
        # Check if volume exists
        if ! volume_exists "$VOLUME"; then
            log_error "Volume '$VOLUME' does not exist"
            log_info "Available volumes:"
            docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.CreatedAt}}"
            exit 1
        fi

        # Check if output file already exists
        if [[ -f "$OUTPUT_FILE" ]]; then
            log_warn "Output file '$OUTPUT_FILE' already exists and will be overwritten"
        fi

        log_info "Backing up volume '$VOLUME' to '$OUTPUT_FILE'..."
        
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "Using Docker image: $BACKUP_IMAGE"
            log_info "Volume mount: $VOLUME:/volume"
            log_info "Backup directory: $(pwd):/backup"
        fi

        # Perform backup
        if docker run --rm \
            -v "${VOLUME}:/volume:ro" \
            -v "$(pwd):/backup" \
            ${BACKUP_IMAGE} \
            sh -c "tar czf /backup/${OUTPUT_FILE} -C /volume . 2>/dev/null || { echo 'Backup failed' >&2; exit 1; }"; then
            
            # Verify backup was created and has content
            if [[ -f "$OUTPUT_FILE" ]] && [[ -s "$OUTPUT_FILE" ]]; then
                local file_size=$(du -h "$OUTPUT_FILE" | cut -f1)
                log_info "Backup complete: $OUTPUT_FILE (${file_size})"
                
                if [[ "$VERBOSE" == "true" ]]; then
                    log_info "Backup contents:"
                    tar -tzf "$OUTPUT_FILE" | head -10
                    local total_files=$(tar -tzf "$OUTPUT_FILE" | wc -l)
                    if [[ $total_files -gt 10 ]]; then
                        log_info "... and $((total_files - 10)) more files"
                    fi
                fi
            else
                log_error "Backup file was not created or is empty"
                exit 1
            fi
        else
            log_error "Backup operation failed"
            exit 1
        fi
        ;;

    restore)
        if [[ $# -lt 1 ]]; then
            log_error "Input file is required for restore operation"
            usage 1
        fi
        
        INPUT_FILE=$1
        validate_filename "$INPUT_FILE"
        
        # Check if input file exists and is readable
        if [[ ! -f "$INPUT_FILE" ]]; then
            log_error "Input file '$INPUT_FILE' not found"
            exit 1
        fi
        
        if [[ ! -r "$INPUT_FILE" ]]; then
            log_error "Input file '$INPUT_FILE' is not readable"
            exit 1
        fi

        # Validate backup file format
        if ! tar -tzf "$INPUT_FILE" &>/dev/null; then
            log_error "Input file '$INPUT_FILE' is not a valid tar.gz archive"
            exit 1
        fi

        # Warn if volume already exists
        if volume_exists "$VOLUME"; then
            log_warn "Volume '$VOLUME' already exists. Contents will be replaced."
        else
            log_info "Creating new volume '$VOLUME'..."
            if ! docker volume create "${VOLUME}" >/dev/null; then
                log_error "Failed to create volume '$VOLUME'"
                exit 1
            fi
        fi

        log_info "Restoring '$INPUT_FILE' into volume '$VOLUME'..."
        
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "Archive contents preview:"
            tar -tzf "$INPUT_FILE" | head -10
            local total_files=$(tar -tzf "$INPUT_FILE" | wc -l)
            if [[ $total_files -gt 10 ]]; then
                log_info "... and $((total_files - 10)) more files"
            fi
        fi

        # Perform restore
        if docker run --rm \
            -v "${VOLUME}:/volume" \
            -v "$(pwd):/backup:ro" \
            ${BACKUP_IMAGE} \
            sh -c "cd /volume && tar xzf /backup/${INPUT_FILE} 2>/dev/null || { echo 'Restore failed' >&2; exit 1; }"; then
            
            log_info "Restore complete: $VOLUME"
            
            if [[ "$VERBOSE" == "true" ]]; then
                log_info "Verifying restored volume..."
                docker run --rm -v "${VOLUME}:/volume:ro" ${BACKUP_IMAGE} \
                    sh -c "echo 'Files in volume:'; find /volume -type f | head -5; echo 'Total files:'; find /volume -type f | wc -l"
            fi
        else
            log_error "Restore operation failed"
            exit 1
        fi
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage 1
        ;;
esac
