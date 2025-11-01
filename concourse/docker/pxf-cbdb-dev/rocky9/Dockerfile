FROM apache/incubator-cloudberry:cbdb-build-rocky9-latest

# Ensure we're running as root for package installation
USER root

# Install additional dependencies for PXF build and test
RUN dnf install -y --allowerasing \
    rpm maven golang gcc gcc-c++ curl-devel postgresql-devel \
    make coreutils findutils git wget tar gzip which \
    rpm-build rpm-devel libtool autoconf automake \
    nmap-ncat java-11-openjdk-devel

# Remove any existing Java installations and force Java 11
RUN dnf remove -y java-*-openjdk-headless java-*-openjdk || true
RUN dnf install -y java-11-openjdk java-11-openjdk-devel

# Set Java environment
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk
ENV PATH=$JAVA_HOME/bin:$PATH

# Verify Java version
RUN java -version && javac -version

# Copy build scripts
COPY build-cloudberry-pxf.sh /usr/local/bin/
COPY test-pxf.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/build-cloudberry-pxf.sh /usr/local/bin/test-pxf.sh

# Set working directory
WORKDIR /workspace

# Default command
#CMD ["/usr/local/bin/build-cloudberry-pxf.sh"]
CMD ["/bin/bash", "-c", "/usr/local/bin/build-cloudberry-pxf.sh && tail -f /dev/null"]
