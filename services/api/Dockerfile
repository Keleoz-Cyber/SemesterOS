FROM python:3.12-slim
WORKDIR /app
ARG DEBIAN_MIRROR_HOST=deb.debian.org
ARG PIP_INDEX_URL=https://pypi.org/simple
RUN sed -i "s|http://deb.debian.org|https://${DEBIAN_MIRROR_HOST}|g" /etc/apt/sources.list.d/debian.sources \
    && apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*
COPY services/api/requirements.lock ./requirements.lock
RUN pip install --no-cache-dir --index-url "${PIP_INDEX_URL}" -r requirements.lock
COPY services/api/app ./app
COPY services/api/alembic ./alembic
COPY services/api/alembic.ini ./alembic.ini
RUN useradd --create-home appuser && mkdir -p /app/.local-data/media && chown -R appuser:appuser /app
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
