# Copyright (C) Tom Porter
# Distributed under the MIT license (see LICENSE for details)


##################################################
# ubuntu-base image
#
# Image contains key Linux libraries, config and 
# environment variables to be used as a base for 
# other images.
# 
ARG ROOT_CONTAINER=ubuntu:20.04
FROM ${ROOT_CONTAINER} as ubuntu-base

LABEL maintainer="Tom Porter"

ENV SHELL=/bin/bash \
    DEBIAN_FRONTEND=noninteractive \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8

# build utils
RUN apt-get update && apt-get install -y --no-install-recommends \
    # build utils
    build-essential \
    ca-certificates \
    curl \
    git \
    locales \
    sudo \
    tini \
    wget \
    \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    # fix locales and permissions
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen

# For security, this Dockerfile uses a non-root user with sudo access.
# On Linux, the container user's GID/UIDs will be updated to match your local UID/GID if using VSCode.
# See https://aka.ms/vscode-remote/containers/non-root-user for details.
ARG USERNAME=standard
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    # [Optional] Add sudo support. Omit if you don't need to install software after connecting.
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    \
    # Let the installed vscode extensions persist between rebuilds
    # See: https://code.visualstudio.com/docs/remote/containers-advanced#_avoiding-extension-reinstalls-on-container-rebuild
    && mkdir -p /home/$USERNAME/.vscode-server/extensions \
    && chown -R $USERNAME /home/$USERNAME/.vscode-server


# install python and poetry package manager
ARG POETRY_VERSION=1.1.6 
ENV \
    # do not buffer output
    PYTHONUNBUFFERED=1 \
    # prevents python creating .pyc files
    PYTHONDONTWRITEBYTECODE=1 \
    \
    # pip
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    \
    # python install path
    PYSETUP_PATH="/opt/pysetup" \
    \
    # poetry configuration
    # https://python-poetry.org/docs/configuration/#using-environment-variables
    # installs poetry to this location
    POETRY_HOME="/opt/poetry" \
    # create a virtual environment in project's root named `.venv`
    POETRY_VIRTUALENVS_CREATE=true \
    POETRY_VIRTUALENVS_IN_PROJECT=true \
    POETRY_VIRTUALENVS_PATH="/opt/pysetup/.venv" \
    # do not ask any interactive question
    POETRY_NO_INTERACTION=1

# add poetry to path
ENV PATH="${POETRY_HOME}/bin:${POETRY_VIRTUALENVS_PATH}/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    # python3
    python3-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    \
    # python package management (pip and poetry)
    && curl -sSL https://bootstrap.pypa.io/get-pip.py | python3 \
    && curl -sSL https://raw.githubusercontent.com/sdispater/poetry/master/get-poetry.py | python3


# download and install spark
ARG APACHE_SPARK_VERSION=3.1.1 
ARG HADOOP_VERSION=3.2 
ARG OPENJDK_VERSION=13
ENV \
    # spark
    # SPARK_OPTS="--driver-java-options=-Xms1024M --driver-java-options=-Xmx4096M --driver-java-options=-Dlog4j.logLevel=info" \
    SPARK_HOME=/opt/spark

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates-java \
    openjdk-${OPENJDK_VERSION}-jre-headless \
    \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV PATH="${SPARK_HOME}/bin:$PATH"

# local tarball extraction installation
#
ADD build_files/spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz /tmp
RUN mv /tmp/spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION} ${SPARK_HOME}

# remote installation
#
# RUN wget https://archive.apache.org/dist/spark/spark-${APACHE_SPARK_VERSION}/spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz \
#     && tar -xvf spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz \
#     && mv spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}/ ${SPARK_HOME} \
#     && rm -rf spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz


##################################################
# python-base
# 
# Image contains the non-dev Python packages 
# installed through the poetry package manager
# 
FROM ubuntu-base AS python-base

# libraries required for pymc3
RUN apt-get update && apt-get install -y --no-install-recommends \
    # pymc3
    libblas-dev \
    libnetcdf-dev \
    # numba
    llvm-10-dev \
    \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    # install runtime dependencies for poetry uses $POETRY_VIRTUALENVS_IN_PROJECT internally
    && pip3 install --upgrade pip setuptools wheel

ENV LLVM_CONFIG=/usr/bin/llvm-config-10

WORKDIR $PYSETUP_PATH
COPY pyproject.toml poetry.lock ./
RUN poetry install --no-dev

# activate virtualenv
ENV VIRTUAL_ENV=${POETRY_VIRTUALENVS_PATH}


##################################################
# development
#
# Image contains a development build that includes
# Jupyter, standard Python dev packages,
# add uses a non-root user.
#
FROM python-base AS development

# copy in our built poetry + venv
COPY --chown=standard:standard --from=python-base /opt /opt

# add nodejs for Jupyter Lab extensions
RUN apt-get update \
    && curl -sL https://deb.nodesource.com/setup_14.x | sudo bash - \
    && apt-get install -y --no-install-recommends nodejs

# TODO: jupyter lab extension installation

# quicker install as runtime deps are already installed
WORKDIR $PYSETUP_PATH
RUN poetry install

USER $USERNAME

ENTRYPOINT ["tini", "--"]
CMD ["jupyter lab --port=8888 --ip=0.0.0.0 --token=token"]