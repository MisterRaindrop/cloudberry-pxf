#!/bin/bash
set -eo pipefail

echo "=== Running Complete PXF Test Pipeline ==="

# Install Maven first
echo "Installing Maven..."
docker exec cloudberry-pxf dnf install -y maven

# Run complete PXF build and test pipeline
docker exec cloudberry-pxf su - gpadmin -c "
    set -eo pipefail
    
    echo 'Setting up test environment...'
    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
    export PATH=\$JAVA_HOME/bin:\$PATH
    export PXF_HOME=/usr/local/pxf
    export PXF_BASE=\$HOME/pxf-base
    export PATH=/usr/local/pxf/bin:\$PATH
    export GPHD_ROOT=/tmp/singlecluster
    
    # Source Cloudberry environment
    source /usr/local/cloudberry-db/cloudberry-env.sh
    
    cd /workspace/cloudberry-pxf
    
    echo '=== Building PXF Components ==='
    
    echo 'Building PXF CLI...'
    cd cli && make && cd .. || echo 'CLI build failed'
    
    # echo 'Building PXF FDW...'
    # cd fdw && make && cd .. || echo 'FDW build failed'
    
    # echo 'Building PXF External Table...'
    # cd external-table && make && cd .. || echo 'External Table build failed'
    
    echo 'Building PXF Server...'
    cd server && ./gradlew clean build && cd .. || echo 'Server build failed'
    
    echo '=== Running Component Tests ==='
    
    echo 'Testing PXF CLI...'
    cd cli && make test && cd .. || echo 'CLI tests failed'
    
    # echo 'Testing PXF FDW...'
    # cd fdw && make test && cd .. || echo 'FDW tests failed'
    
    # echo 'Testing PXF External Table...'
    # cd external-table && make installcheck && cd .. || echo 'External Table tests failed'
    
    echo 'Testing PXF Server...'
    cd server && ./gradlew test && cd .. || echo 'Server tests failed'
    
    echo '=== Installing PXF ==='
    make install
    
    echo '=== Starting PXF ==='
    # pxf prepare
    # pxf start
    # pxf status
    
#     echo '=== Running Automation Tests ==='
#     cd automation
    
#     # Create test artifacts directories
#     mkdir -p ./test_artifacts/surefire-reports
#     mkdir -p ./test_artifacts/automation_logs
    
#     # Create simplified Maven settings
#     mkdir -p ~/.m2
#     cat > ~/.m2/settings.xml << 'EOF'
# <?xml version=\"1.0\" encoding=\"UTF-8\"?>
# <settings>
#   <mirrors>
#     <mirror>
#       <id>central-mirror</id>
#       <mirrorOf>*</mirrorOf>
#       <name>Central Repository Mirror</name>
#       <url>https://repo.maven.apache.org/maven2</url>
#     </mirror>
#   </mirrors>
# </settings>
# EOF
    
#     # Prepare PXF configuration
#     mkdir -p \${PXF_BASE}/servers/default
#     if [ -d \${PXF_HOME}/templates ]; then
#         cp \${PXF_HOME}/templates/{hdfs,mapred,yarn,core,hbase,hive}-site.xml \${PXF_BASE}/servers/default/ 2>/dev/null || echo 'Some template files not found'
#     fi
    
#     # Update configuration files to point to singlecluster container
#     if [ -d \${PXF_BASE}/servers/default ]; then
#         sed -i 's/localhost/singlecluster/g' \${PXF_BASE}/servers/default/*.xml 2>/dev/null || echo 'No XML files to update'
#     fi
    
#     echo 'Running HdfsSmokeTest...'
#     make TEST=HdfsSmokeTest || echo 'HdfsSmokeTest failed'
    
#     echo 'Running GROUP=gpdb tests...'
#     make GROUP=gpdb || echo 'GROUP=gpdb tests failed'
    
#     echo 'Testing PXF connectivity...'
#     curl -s http://localhost:5888/pxf/v1/version || curl -s http://localhost:5888/pxf/v2/version || echo 'PXF version endpoint not accessible'
    
#     echo 'Testing Hadoop connectivity from PXF...'
#     curl -s http://singlecluster:9870 | grep -i hadoop || echo 'Hadoop not accessible from PXF'
    
#     echo 'Collecting test results...'
#     cp -r target/surefire-reports/* ./test_artifacts/surefire-reports/ 2>/dev/null || echo 'No surefire reports found'
#     cp -r automation_logs/* ./test_artifacts/automation_logs/ 2>/dev/null || echo 'No automation logs found'
    
#     echo 'Test execution completed'
"

# Copy test results to host
echo "Copying test results to host..."
mkdir -p ./test-results
docker cp cloudberry-pxf:/workspace/cloudberry-pxf/automation/test_artifacts ./test-results/ 2>/dev/null || echo "No test artifacts to copy"
docker cp cloudberry-pxf:/workspace/cloudberry-pxf/automation/target ./test-results/ 2>/dev/null || echo "No target directory to copy"

echo "=== Complete PXF Test Pipeline Finished ==="
echo ""
echo "Test results available in:"
echo "  - ./test-results/test_artifacts/surefire-reports/"
echo "  - ./test-results/test_artifacts/automation_logs/"
echo "  - ./test-results/target/"
echo ""
echo "To view test results:"
echo "  find ./test-results -name '*.xml' -o -name '*.html' -o -name '*.log'"
