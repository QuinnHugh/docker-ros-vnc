# This Dockerfile is used to build an ROS + VNC + Tensorflow image based on Ubuntu 18.04
FROM nvidia/cuda:10.0-cudnn7-devel-ubuntu18.04

LABEL maintainer "Henry Huang"
MAINTAINER Henry Huang "https://github.com/henry2423"
ENV REFRESHED_AT 2018-10-29

# Install sudo
RUN apt-get update && \
    apt-get install -y sudo \
    xterm \
    curl

# Configure user
ARG user=ros
ARG passwd=ros
ARG uid=1000
ARG gid=1000
ENV USER=$user
ENV PASSWD=$passwd
ENV UID=$uid
ENV GID=$gid
RUN groupadd $USER && \
    useradd --create-home --no-log-init -g $USER $USER && \
    usermod -aG sudo $USER && \
    echo "$PASSWD:$PASSWD" | chpasswd && \
    chsh -s /bin/bash $USER && \
    # Replace 1000 with your user/group id
    usermod  --uid $UID $USER && \
    groupmod --gid $GID $USER

### VNC Installation
LABEL io.k8s.description="VNC Container with ROS with Xfce window manager" \
      io.k8s.display-name="VNC Container with ROS based on Ubuntu" \
      io.openshift.expose-services="6901:http,5901:xvnc,6006:tnesorboard" \
      io.openshift.tags="vnc, ros, gazebo, tensorflow, ubuntu, xfce" \
      io.openshift.non-scalable=true

## Connection ports for controlling the UI:
# VNC port:5901
# noVNC webport, connect via http://IP:6901/?password=vncpassword
ENV DISPLAY=:1 \
    VNC_PORT=5901 \
    NO_VNC_PORT=6901
EXPOSE $VNC_PORT $NO_VNC_PORT

## Envrionment config
ENV VNCPASSWD=vncpassword
ENV HOME=/home/$USER \
    TERM=xterm \
    STARTUPDIR=/dockerstartup \
    INST_SCRIPTS=/home/$USER/install \
    NO_VNC_HOME=/home/$USER/noVNC \
    DEBIAN_FRONTEND=noninteractive \
    VNC_COL_DEPTH=24 \
    VNC_RESOLUTION=1920x1080 \
    VNC_PW=$VNCPASSWD \
    VNC_VIEW_ONLY=false
WORKDIR $HOME

## Add all install scripts for further steps
ADD ./src/common/install/ $INST_SCRIPTS/
ADD ./src/ubuntu/install/ $INST_SCRIPTS/
RUN find $INST_SCRIPTS -name '*.sh' -exec chmod a+x {} +

## Install some common tools
RUN $INST_SCRIPTS/tools.sh
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

## Install xvnc-server & noVNC - HTML5 based VNC viewer
RUN $INST_SCRIPTS/tigervnc.sh
RUN $INST_SCRIPTS/no_vnc.sh

## Install xfce UI
RUN $INST_SCRIPTS/xfce_ui.sh
ADD ./src/common/xfce/ $HOME/

## configure startup
RUN $INST_SCRIPTS/libnss_wrapper.sh
ADD ./src/common/scripts $STARTUPDIR
RUN $INST_SCRIPTS/set_user_permission.sh $STARTUPDIR $HOME


### ROS and Gazebo Installation
# Install other utilities
RUN apt-get update && \
    apt-get install -y vim \
    tmux \
    git \
    cmake libfreeimage-dev libfreeimageplus-dev \
    qt5-default freeglut3-dev libxi-dev libxmu-dev liblua5.2-dev \
    lua5.2 doxygen graphviz graphviz-dev asciidoc

# Install ROS
RUN sh -c 'echo "deb http://packages.ros.org/ros/ubuntu `lsb_release -cs` main" > /etc/apt/sources.list.d/ros-latest.list' && \
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key 421C365BD9FF1F717815A3895523BAEEB01FA116 && \
    apt-get update && apt-get install -y ros-melodic-desktop && \
    apt-get install -y python-rosinstall && \
    rosdep init

# Install Gazebo
RUN sh -c 'echo "deb http://packages.osrfoundation.org/gazebo/ubuntu-stable `lsb_release -cs` main" > /etc/apt/sources.list.d/gazebo-stable.list' && \
    wget http://packages.osrfoundation.org/gazebo.key -O - | sudo apt-key add - && \
    apt-get update && \
    apt-get install -y gazebo9 libgazebo9-dev && \
    apt-get install -y ros-melodic-gazebo-ros-pkgs ros-melodic-gazebo-ros-control

# Install argos
ADD ./argos3/ $HOME/argos3
ADD ./argos3-examples/ $HOME/argos3-examples
RUN cd $HOME/argos3 && \
    mkdir build && cd build && \
    cmake ../src && make && make doc && make install

# Setup ROS & argos
USER $USER
RUN rosdep fix-permissions && rosdep update
RUN echo "source /opt/ros/melodic/setup.bash" >> ~/.bashrc
RUN echo $(awk 'NR==3' ~/argos3/build/setup_env.sh) >> ~/.bashrc && \
    echo $(awk 'NR==5' ~/argos3/build/setup_env.sh) >> ~/.bashrc
RUN /bin/bash -c "source ~/.bashrc"

USER root
RUN cd $HOME/argos3-examples && \
    mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Debug .. && make 

# Expose Tensorboard
EXPOSE 6006

### Switch to root user to install additional software
USER $USER

ENTRYPOINT ["/dockerstartup/vnc_startup.sh"]
CMD ["--wait"]
