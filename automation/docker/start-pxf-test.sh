#!/bin/bash
set -eo pipefail

echo "=== Starting PXF Test Environment ==="

# Build images if needed
if [ "$1" = "--rebuild" ]; then
    echo "Force rebuilding images..."
    docker-compose build --no-cache
else
    echo "Building images (if needed)..."
    docker-compose build
fi

# Start services
echo "Starting services with docker-compose..."
docker-compose up -d

echo "Waiting for services to be ready..."
echo "- Hadoop services starting..."
docker-compose logs -f singlecluster &
HADOOP_PID=$!

# Wait for Hadoop services to be healthy
echo "Waiting for Hadoop services to be healthy..."
timeout 300 bash -c 'until docker-compose ps singlecluster | grep -q "healthy"; do sleep 10; echo "Still waiting for Hadoop..."; done'

# Kill the log following process
kill $HADOOP_PID 2>/dev/null || true

echo "- Cloudberry and PXF services should be starting automatically..."

echo "=== PXF Test Environment Started ==="
echo ""
echo "Services:"
echo "  - Hadoop services: http://localhost:9870 (HDFS), http://localhost:8088 (YARN)"
echo "  - HBase Master: http://localhost:16010"
echo ""
echo "To connect to Cloudberry:"
echo "  docker exec -it cloudberry-pxf su - gpadmin"
echo ""
echo "To run PXF tests:"
echo "  docker exec -it cloudberry-pxf /usr/local/bin/test-pxf.sh"
echo ""
echo "To stop services:"
echo "  docker-compose down"
echo ""
echo "Usage:"
echo "  $0           # Build and start (incremental build)"
echo "  $0 --rebuild # Force rebuild all images from scratch"
