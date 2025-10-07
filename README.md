# Docker Volume Backup & Restore Utility

A simple and efficient shell script for backing up and restoring Docker volumes using tar compression.

## Features

- Fast backup and restore operations using `busybox` container
- Compressed backups using gzip
- Simple command-line interface
- Automatic timestamp generation for backup files
- Error handling and validation
- Uses lightweight `busybox` image for operations

## Prerequisites

- Docker installed and running
- Bash shell environment
- Sufficient disk space for backup files

## Installation

1. Download the script:

   ```bash
   curl -O https://raw.githubusercontent.com/your-repo/docker-volume-backup/main/docker-volume-backup.sh
   ```

2. Make it executable:

   ```bash
   chmod +x docker-volume-backup.sh
   ```

3. (Optional) Move to a directory in your PATH:
   ```bash
   sudo mv docker-volume-backup.sh /usr/local/bin/docker-volume-backup
   ```

## Usage

### Backup a Volume

```bash
./docker-volume-backup.sh backup <volume_name> [output_file]
```

**Parameters:**

- `volume_name`: Name of the Docker volume to backup
- `output_file` (optional): Custom name for the backup file

**Examples:**

```bash
# Backup with auto-generated filename
./docker-volume-backup.sh backup my_volume

# Backup with custom filename
./docker-volume-backup.sh backup my_volume my_custom_backup.tar.gz
```

The script will create a compressed tar.gz file containing all the data from the specified volume.

### Restore a Volume

```bash
./docker-volume-backup.sh restore <volume_name> <input_file>
```

**Parameters:**

- `volume_name`: Name of the Docker volume to restore to
- `input_file`: Path to the backup file to restore from

**Example:**

```bash
./docker-volume-backup.sh restore my_volume my_volume_backup_20251007_143022.tar.gz
```

The script will:

1. Create the volume if it doesn't exist
2. Extract the backup data into the volume
3. Preserve file permissions and structure

## How It Works

The utility uses Docker containers to perform backup and restore operations:

1. **Backup Process:**

   - Mounts the source volume to `/volume` in a `busybox` container
   - Mounts current directory to `/backup` for output
   - Creates a compressed tar archive of the volume contents

2. **Restore Process:**
   - Creates the target volume if it doesn't exist
   - Mounts the target volume and backup directory
   - Extracts the tar archive into the volume

## File Naming Convention

When no output filename is specified, backups are automatically named using the pattern:

```
<volume_name>_backup_<YYYYMMDD_HHMMSS>.tar.gz
```

Example: `my_volume_backup_20251007_143022.tar.gz`

## Examples

### Complete Backup Workflow

```bash
# List existing volumes
docker volume ls

# Backup a volume
./docker-volume-backup.sh backup postgres_data

# Verify backup file was created
ls -la *.tar.gz

# Restore to a new volume
./docker-volume-backup.sh restore postgres_data_restored postgres_data_backup_20251007_143022.tar.gz
```

### Backup Multiple Volumes

```bash
#!/bin/bash
# Script to backup multiple volumes

volumes=("postgres_data" "redis_data" "app_uploads")

for volume in "${volumes[@]}"; do
    echo "Backing up $volume..."
    ./docker-volume-backup.sh backup "$volume"
done
```

## Error Handling

The script includes error handling for common scenarios:

- Invalid number of arguments
- Missing backup files during restore
- Docker command failures (via `set -e`)

## Troubleshooting

### Common Issues

1. **Permission Denied:**

   ```bash
   chmod +x docker-volume-backup.sh
   ```

2. **Docker Not Found:**

   - Ensure Docker is installed and running
   - Check if your user is in the docker group

3. **Volume Not Found:**

   - Verify the volume name: `docker volume ls`
   - Volume will be created automatically during restore

4. **Backup File Not Found:**
   - Check the file path and name
   - Ensure the file exists in the current directory

### Verification

To verify a backup was successful:

```bash
# Check backup file size
ls -lh your_backup.tar.gz

# List contents without extracting
tar -tzf your_backup.tar.gz | head -20
```

## Limitations

- Requires the volume to be unmounted or services stopped for consistent backups
- Backup size depends on volume content (no incremental backup)
- Uses `busybox` image which must be available or will be downloaded

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is open source and available under the [MIT License](LICENSE).

## Security Considerations

- The script runs Docker containers with volume mounts
- Ensure backup files are stored securely
- Consider encrypting sensitive backup data
- Regular cleanup of old backup files is recommended

---

**Note:** Always test backup and restore procedures in a non-production environment first.
