# =============================================================================
# STAR BUILDING SERVICES - Custom ERPNext v16 Image
# Patrón: Oficial frappe_docker (layered)
# Referencia: github.com/frappe/frappe_docker/images/layered/Containerfile
#
# INVARIANTES:
# - NO se ejecuta bench init manualmente sin --apps_path
# - frappe/build:version-16 ya incluye bench, pip, nvm, node, yarn
# - frappe/base:version-16 es la imagen runtime limpia
# - Se usa cp -L para des-referenciar symlinks en assets
# =============================================================================

# -----------------------------------------------------------------------------
# STAGE 1: builder
# Base: frappe/build (tiene todas las herramientas de compilación)
# Descarga e instala todas las apps desde apps.json en un bench fresco
# -----------------------------------------------------------------------------
FROM frappe/build:version-16 AS builder

ARG FRAPPE_PATH=https://github.com/frappe/frappe
ARG FRAPPE_BRANCH=version-16
ARG APPS_JSON_BASE64

USER root

# Decodificar apps.json desde ARG base64
RUN if [ -n "${APPS_JSON_BASE64}" ]; then \
      mkdir -p /opt/frappe && \
      echo "${APPS_JSON_BASE64}" | base64 -d > /opt/frappe/apps.json && \
      echo "--- apps.json decodificado ---" && \
      cat /opt/frappe/apps.json; \
    fi

USER frappe

# Control de memoria para Node (crítico en runners con RAM limitada)
ENV NODE_OPTIONS="--max-old-space-size=4096"

# bench init con --apps_path instala frappe + todas las apps del JSON en un solo paso
# --no-procfile, --no-backups y --skip-redis-config-generation reducen trabajo innecesario
RUN export APP_INSTALL_ARGS="" && \
    if [ -n "${APPS_JSON_BASE64}" ]; then \
      export APP_INSTALL_ARGS="--apps_path=/opt/frappe/apps.json"; \
    fi && \
    bench init ${APP_INSTALL_ARGS} \
      --frappe-branch=${FRAPPE_BRANCH} \
      --frappe-path=${FRAPPE_PATH} \
      --no-procfile \
      --no-backups \
      --skip-redis-config-generation \
      --verbose \
      /home/frappe/frappe-bench && \
    cd /home/frappe/frappe-bench && \
    echo '{"socketio_port": 9000, "redis_cache": "redis://localhost:13000", "redis_queue": "redis://localhost:11000", "redis_socketio": "redis://localhost:13000"}' > sites/common_site_config.json && \
    find apps -mindepth 1 -path "*/.git" | xargs rm -fr

# Compilar assets JS/CSS para todas las apps instaladas
# NODE_OPTIONS ya está seteado arriba
RUN cd /home/frappe/frappe-bench && bench build --hard-link

# Des-referenciar symlinks en assets ANTES de copiar al stage final
# cp -L es OBLIGATORIO para evitar broken symlinks en la imagen Alpine/runtime
RUN cp -rL /home/frappe/frappe-bench/sites/assets /tmp/assets-resolved

# -----------------------------------------------------------------------------
# STAGE 2: backend (imagen final de producción)
# Base: frappe/base (runtime limpio sin herramientas de compilación)
# -----------------------------------------------------------------------------
FROM frappe/base:version-16 AS backend

USER frappe

# Copiar el bench completo (apps + virtualenv python + configuración)
COPY --from=builder --chown=frappe:frappe \
    /home/frappe/frappe-bench \
    /home/frappe/frappe-bench

# Reemplazar assets con la versión des-referenciada (sin symlinks rotos)
RUN rm -rf /home/frappe/frappe-bench/sites/assets
COPY --from=builder --chown=frappe:frappe \
    /tmp/assets-resolved \
    /home/frappe/frappe-bench/sites/assets

WORKDIR /home/frappe/frappe-bench

# Volúmenes estándar de frappe_docker
VOLUME [ \
  "/home/frappe/frappe-bench/sites", \
  "/home/frappe/frappe-bench/sites/assets", \
  "/home/frappe/frappe-bench/logs" \
]
