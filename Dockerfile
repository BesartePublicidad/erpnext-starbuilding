FROM frappe/bench:latest as builder

USER root
RUN apt-get update && apt-get install -y \
    python3-dev python3-venv git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe/frappe-bench

# Initialize bench (since base image might be bare)
# Note: frappe/bench:latest usually has bench installed but we need a bench directory structure.
# Often the base image expects a volume mount or init. We will simulate init.
# However, standard practice for custom image is to START from a clean python/node image and install bench.
# Reverting to Python 3.12 Slim + Node 20 base for maximum control and stability (B.L.A.S.T.)

FROM python:3.12-slim-bookworm as base

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    mariadb-client \
    postgresql-client \
    gettext-base \
    wget \
    # for frappe
    libtiff5-dev \
    libjpeg62-turbo-dev \
    zlib1g-dev \
    libfreetype6-dev \
    liblcms2-dev \
    libwebp-dev \
    tcl8.6-dev \
    tk8.6-dev \
    python3-tk \
    libharfbuzz-dev \
    libfribidi-dev \
    libxcb1-dev \
    # for pdf
    libfontconfig \
    libxrender1 \
    libxext6 \
    # nodejs
    curl \
    && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install bench
RUN pip install frappe-bench

# Create generic user
RUN groupadd -g 1000 frappe && useradd -u 1000 -g frappe -m -d /home/frappe frappe
USER frappe
WORKDIR /home/frappe

# Initialize bench
RUN bench init --skip-redis-config-generation --skip-assets --python python3 frappe-bench

WORKDIR /home/frappe/frappe-bench

# Get Apps (Manual Fetch for Control)
# We use --resolve-deps to fetch dependencies if needed, but we explicitly list them below
RUN bench get-app --branch version-16 https://github.com/frappe/frappe
RUN bench get-app --branch version-16 https://github.com/frappe/erpnext --resolve-deps
RUN bench get-app --branch version-16 https://github.com/frappe/hrms
RUN bench get-app --branch main https://github.com/frappe/crm
RUN bench get-app --branch develop https://github.com/frappe/payments
RUN bench get-app --branch main https://github.com/frappe/offsite_backups

# Build Assets
RUN bench build

# Cleanup to reduce size (Multi-stage optimization)
# (Here we keep it single stage for now to ensure debugging is easier if it fails again, 
# but clean up cache)
RUN find . -name "*.pyc" -delete && \
    find . -name "__pycache__" -delete && \
    rm -rf apps/*/node_modules

# Verify apps.json exists (create it from installed apps list or copy ours)
COPY --chown=frappe:frappe apps.json /home/frappe/frappe-bench/apps.json

CMD ["/home/frappe/frappe-bench/env/bin/gunicorn", "-b", "0.0.0.0:8000", "-w", "4", "-t", "120", "--worker-tmp-dir", "/dev/shm", "--gthread", "--worker-class", "gthread", "--threads", "4", "frappe.app:application"]
