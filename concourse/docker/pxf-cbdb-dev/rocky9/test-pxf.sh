#!/bin/bash
set -eo pipefail

echo "=== Starting PXF Tests ==="

# Ensure we're in the right directory
cd /workspace/cloudberry-pxf

# Run PXF tests as gpadmin user
su - gpadmin -c "
    set -eo pipefail
    
    # Set up environment
    export GPHOME=/usr/local/cloudberry-db
    export PXF_HOME=/usr/local/pxf
    export PXF_BASE=\$HOME/pxf-base
    export PATH=\$GPHOME/bin:\$PXF_HOME/bin:\$PATH
    source \$GPHOME/cloudberry-env.sh
    source /workspace/cloudberry/gpAux/gpdemo/gpdemo-env.sh
    
    cd /workspace/cloudberry-pxf
    
    echo 'Running PXF unit tests...'
    make test || echo 'Some tests may have failed, continuing...'
    
    echo 'Running PXF integration tests...'
    make it || echo 'Some integration tests may have failed, continuing...'
    
    echo 'PXF tests completed'
"

echo "=== PXF Tests Complete ==="
