# Start from the official Ubuntu Bionic (18.04 LTS) image
FROM ubuntu:bionic

# Install any extra things we might need 
# added items suggested on https://openfoam.org/download/source/software-for-compilation/
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && \
    apt-get install -y \
                tzdata \
                vim \
                ssh \
                sudo \
                wget \
                paraview \
                software-properties-common \
                build-essential flex bison git-core cmake zlib1g-dev libboost-system-dev \
                libboost-thread-dev libopenmpi-dev openmpi-bin gnuplot libreadline-dev libncurses-dev libxt-dev \
                libqt5x11extras5-dev libxt-dev qt5-default qttools5-dev curl \
                lsb-release tk8.6 debhelper chrpath tcl tcl8.5 flex gfortran dpatch libgfortran3 \
                automake bison m4 autoconf tk autotools-dev graphviz net-tools iproute2 ; \
		rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-c"]

# Copy in minimal LSF components for openMPI build.
ADD lsf /tmp/lsf

# Setup the temporary LSF paths
ARG LSF_ENVDIR=/tmp/lsf/conf
ARG LSF_LIBDIR=/tmp/lsf/10.1/lib

ARG OF_VER="v1912"
WORKDIR /opt
# Download latest OpenFOAM, ThirdParty tarballs
RUN wget https://sourceforge.net/projects/openfoam/files/$OF_VER/OpenFOAM-$OF_VER.tgz
RUN wget https://sourceforge.net/projects/openfoam/files/$OF_VER/ThirdParty-$OF_VER.tgz 

# Expand tarballs
RUN tar -zxf OpenFOAM-$OF_VER.tgz
RUN tar -zxf ThirdParty-$OF_VER.tgz

ARG OMPI_VER="4.0.3"
# Download openMPI
WORKDIR /opt/ThirdParty-$OF_VER
RUN wget https://www.open-mpi.org/software/ompi/v4.0/downloads/openmpi-$OMPI_VER.tar.gz 
RUN tar zxvf openmpi-$OMPI_VER.tar.gz

# Configure OPENMPI with LSF
WORKDIR /opt/ThirdParty-$OF_VER
RUN echo "export WM_MPLIB=OPENMPI" >> /opt/OpenFOAM-$OF_VER/etc/prefs.sh && \
    echo "FOAM_MPI=openmpi-$OMPI_VER" > /opt/OpenFOAM-$OF_VER/etc/config.sh/openmpi && \
    sed 's/sge/lsf --disable-getpwuid/g' makeOPENMPI > makeOPENMPI.lsf && \
    source /opt/OpenFOAM-$OF_VER/etc/bashrc && \
    chmod +x makeOPENMPI.lsf && \
    ./makeOPENMPI.lsf

# Compile OpenFOAM
WORKDIR /opt/OpenFOAM-$OF_VER
RUN source /opt/OpenFOAM-$OF_VER/etc/bashrc && \
    ./Allwmake -j

# Compile Pstream
WORKDIR /opt/OpenFOAM-$OF_VER/src/Pstream
RUN source /opt/OpenFOAM-$OF_VER/etc/bashrc && \
  ./Allwmake

# Install hello_world as a test app
RUN mkdir /tmp/hello-world
WORKDIR /tmp/hello-world
RUN git clone https://github.com/wesleykendall/mpitutorial && \
    source /opt/OpenFOAM-$OF_VER/etc/bashrc && \
    cd mpitutorial/tutorials/mpi-hello-world/code && \
    make && \
    cp /tmp/hello-world/mpitutorial/tutorials/mpi-hello-world/code/mpi_hello_world /usr/local/bin

# Cleaup tarballs
WORKDIR /opt
RUN rm OpenFOAM-$OF_VER.tgz
RUN rm ThirdParty-$OF_VER.tgz
RUN rm -f /opt/ThirdParty-$OF_VER/openmpi-$OMPI_VER.tar.gz
RUN rm -rf /tmp/lsf
RUN rm -rf /tmp/hello-world

# Add OpenFOAM bashrc to system /etc/bash.bashrc
RUN echo "source /opt/OpenFOAM-$OF_VER/etc/bashrc" >> /etc/bash.bashrc

# Create symlink from sh to bash (instead of dash)
WORKDIR /bin
RUN rm sh
RUN ln -s /bin/bash /bin/sh

# Setup an easy mpi path
RUN source /opt/OpenFOAM-$OF_VER/etc/bashrc && ln -s ${MPI_ARCH_PATH} /usr/local/mpi
ENV PATH=/usr/local/mpi/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/mpi/lib64:$LD_LIBRARY_PATH

# Create a new user called foam
RUN useradd --user-group --create-home --shell /bin/bash foam && \
    echo "foam ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set the default container user to foam
USER foam

WORKDIR /opt
