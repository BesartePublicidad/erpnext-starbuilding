FROM undo1/frappe-custom:v16.0.0

ARG FRAPPE_BRANCH=version-16
ARG PYTHON_VERSION=3.12
ARG NODE_VERSION=20
ARG APPS_JSON_BASE64

USER root

# Install dependencies and tools
RUN apt-get update && apt-get install -y \
    curl \
    git \
    python3-dev \
    python3-setuptools \
    python3-pip \
    python3-venv \
    software-properties-common \
    mariadb-client \
    libmariadb-dev \
    xvfb \
    libfontconfig \
    wkhtmltopdf \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

USER frappe

COPY --chown=frappe:frappe apps.json /opt/frappe/apps.json

RUN cd /home/frappe/frappe-bench && \
    bench get-app --branch version-16 erpnext && \
    bench get-app --branch version-16 hrms && \
    bench get-app --branch main crm && \
    bench get-app --branch develop payments && \
    bench get-app --branch main offsite_backups

RUN cd /home/frappe/frappe-bench && \
    bench build

WORKDIR /home/frappe/frappe-bench
