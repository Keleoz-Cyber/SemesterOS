FROM python:3.12-slim
WORKDIR /app
COPY services/api/requirements.lock ./requirements.lock
RUN pip install --no-cache-dir -r requirements.lock
COPY services/api/app ./app
COPY services/api/alembic ./alembic
COPY services/api/alembic.ini ./alembic.ini
RUN useradd --create-home appuser
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
