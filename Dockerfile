FROM python:3.12-slim-bookworm as builder

# Mitigación OOM y Performance
ENV PIP_NO_CACHE_DIR=1
ENV PYTHONUNBUFFERED=1

USER root

# Instalación de dependencias del sistema optimizada
# Incluimos build-essential y librerías específicas para evitar recompilaciones costosas
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    pkg-config \
    python3-dev \
    python3-venv \
    software-properties-common \
    mariadb-client \
    libmariadb-dev \
    libmariadb-dev-compat \
    postgresql-client \
    libpq-dev \
    linkchecker \
    gettext-base \
    wget \
    curl \
    # Dependencias para Assets y PDF
    libfontconfig \
    libxrender1 \
    libxext6 \
    xvfb \
    wkhtmltopdf \
    # Frappe Dependencies (Pillow/Canvas support)
    libtiff5-dev \
    libjpeg62-turbo-dev \
    zlib1g-dev \
    libfreetype6-dev \
    liblcms2-dev \
    libwebp-dev \
    tcl8.6-dev \
    tk8.6-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libxcb1-dev \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install bench via pip (cache disabled by ENV)
RUN pip install frappe-bench

# Crear usuario Frappe
RUN groupadd -g 1000 frappe && useradd -u 1000 -g frappe -m -d /home/frappe frappe

USER frappe
WORKDIR /home/frappe

# Bench Init optimizado
# Usamos --frappe-branch para descargar directamente la versión correcta (ahorra bandwidth y tiempo)
RUN bench init --frappe-branch version-16 \
    --skip-redis-config-generation \
    --skip-assets \
    --python python3 \
    frappe-bench

WORKDIR /home/frappe/frappe-bench

# Instalación de Apps (Capa separada para caché)
COPY --chown=frappe:frappe apps.json apps.json

# Instalación explícita de Apps
RUN bench get-app --branch version-16 erpnext --resolve-deps && \
    bench get-app --branch version-16 hrms && \
    bench get-app --branch main crm && \
    bench get-app --branch develop payments && \
    bench get-app --branch main offsite_backups

# Build de Assets (Suele consumir mucha RAM, yarn cache limpio)
RUN yarn config set cache-folder /tmp/yarn-cache && \
    bench build && \
    rm -rf /tmp/yarn-cache

# Limpieza final de imagen (Multi-stage preparation)
RUN find . -name "*.pyc" -delete && \
    find . -name "__pycache__" -delete && \
    rm -rf apps/*/node_modules

# Exponer gunicorn
CMD ["/home/frappe/frappe-bench/env/bin/gunicorn", "-b", "0.0.0.0:8000", "-w", "4", "-t", "120", "--worker-tmp-dir", "/dev/shm", "--gthread", "--worker-class", "gthread", "--threads", "4", "frappe.app:application"]
