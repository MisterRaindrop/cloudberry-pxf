#!/bin/bash
set -eo pipefail

echo "=== Starting Cloudberry and PXF Build Process ==="

# Force Java 11 environment
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH=$JAVA_HOME/bin:$PATH
echo "Using Java version: $(java -version 2>&1 | head -1)"

# Initialize container environment (skip if fails in CI)
echo "Initializing container environment..."
if ! su - gpadmin -c '/tmp/init_system.sh' 2>/dev/null; then
    echo "Warning: Container initialization failed, continuing with manual setup..."
    # Manual setup for CI environments
    mkdir -p /home/gpadmin
    chown -R gpadmin:gpadmin /home/gpadmin
    chmod 755 /home/gpadmin
fi

# Create build directories
mkdir -p build-logs/details
chown -R gpadmin:gpadmin .
chmod -R 755 .
chmod 777 build-logs

echo "=== Step 1: Setup Cloudberry source ==="
echo "Cloning Cloudberry source from GitHub"
if [ ! -d "cloudberry" ]; then
    git clone --depth 1 --recurse-submodules https://github.com/apache/cloudberry.git cloudberry
    chown -R gpadmin:gpadmin cloudberry
    chmod -R 755 cloudberry
fi
cd cloudberry

echo "=== Step 2: Configure Cloudberry ==="
mkdir -p build-logs build-logs/details
chmod 777 build-logs

# Configure Cloudberry
if [ -f "devops/build/automation/cloudberry/scripts/configure-cloudberry.sh" ]; then
    echo "Found configure script, running configuration..."
    chmod +x devops/build/automation/cloudberry/scripts/configure-cloudberry.sh
    if ! time su - gpadmin -c "
        cd $(pwd)
        export SRC_DIR=$(pwd)
        export ENABLE_DEBUG=false
        ./devops/build/automation/cloudberry/scripts/configure-cloudberry.sh
    "; then
        echo "Configure script failed"
        exit 1
    fi
else
    echo "Configure script not found, running basic configure..."
    su - gpadmin -c "
        cd $(pwd)
        ./configure --prefix=/usr/local/cloudberry-db --enable-debug=no || echo 'Configure completed with warnings'
    "
fi

# echo "=== Step 3: Build Cloudberry ==="
# if [ -f "devops/build/automation/cloudberry/scripts/build-cloudberry.sh" ]; then
#     echo "Found build script, running build..."
#     chmod +x devops/build/automation/cloudberry/scripts/build-cloudberry.sh
#     if ! time su - gpadmin -c "
#         cd $(pwd)
#         export SRC_DIR=$(pwd)
#         ./devops/build/automation/cloudberry/scripts/build-cloudberry.sh
#     "; then
#         echo "Build script failed"
#         exit 1
#     fi
# else
#     echo "Build script not found, running basic make..."
#     su - gpadmin -c "
#         cd $(pwd)
#         make -j$(nproc) || echo 'Build completed with warnings'
#         make install || echo 'Install completed with warnings'
#     "
# fi

# echo "=== Step 4: Create Cloudberry demo cluster ==="
# su - gpadmin -c "
#     set -eo pipefail
#     cd $(pwd)
#     export SRC_DIR=$(pwd)
#     export NUM_PRIMARY_MIRROR_PAIRS=1
#     chmod +x devops/build/automation/cloudberry/scripts/create-cloudberry-demo-cluster.sh
#     ./devops/build/automation/cloudberry/scripts/create-cloudberry-demo-cluster.sh
# "

# echo "=== Step 5: Verify Cloudberry cluster ==="
# su - gpadmin -c "
#     source /usr/local/cloudberry-db/cloudberry-env.sh
#     source $(pwd)/gpAux/gpdemo/gpdemo-env.sh
#     gpstate -s
#     psql -d postgres -c 'SELECT version();'
#     psql -d postgres -c 'SELECT * FROM gp_segment_configuration;'
# "

# cd /workspace

# echo "=== Step 6: Setup PXF source ==="
# if [ "$USE_LOCAL_SOURCE" = "true" ] && [ -d "/workspace/cloudberry-pxf" ]; then
#     echo "Using local PXF source from volume mount"
#     chown -R gpadmin:gpadmin /workspace/cloudberry-pxf
#     cd /workspace/cloudberry-pxf
# else
#     echo "Cloning PXF source from GitHub"
#     if [ ! -d "cloudberry-pxf" ]; then
#         # Clone PXF from the current repository context if available, otherwise from GitHub
#         if [ -n "${GITHUB_REPOSITORY}" ]; then
#             git clone --depth 1 https://github.com/${GITHUB_REPOSITORY}.git cloudberry-pxf
#         else
#             git clone --depth 1 https://github.com/apache/cloudberry-pxf.git cloudberry-pxf
#         fi
#         chown -R gpadmin:gpadmin cloudberry-pxf
#     fi
#     cd cloudberry-pxf
# fi

# echo "=== Step 7: Build and Install PXF ==="
# su - gpadmin -c "
#     set -eo pipefail
#     export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
#     export PATH=\$JAVA_HOME/bin:\$PATH
#     export GPHOME=/usr/local/cloudberry-db
#     export PATH=\$GPHOME/bin:\$PATH
#     source \$GPHOME/cloudberry-env.sh

#     cd /workspace/cloudberry-pxf

#     # Set Go environment
#     export GOPATH=\$HOME/go
#     export PATH=\$PATH:/usr/local/go/bin:\$GOPATH/bin
#     mkdir -p \$GOPATH
#     export PXF_HOME=/usr/local/pxf
#     mkdir -p \$PXF_HOME

#     # Build all PXF components
#     make all

#     # Install PXF
#     make install

#     # Set up PXF environment

#     export PXF_BASE=\$HOME/pxf-base
#     export PATH=\$PXF_HOME/bin:\$PATH

#     # Initialize PXF
#     pxf prepare
#     pxf start

#     # Verify PXF is running
#     pxf status
# "

# echo "=== Cloudberry and PXF Build Complete ==="
# echo "Cloudberry cluster is running and PXF service is started"
# echo "Ready for testing!"
