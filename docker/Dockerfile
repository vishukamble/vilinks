FROM python:3.12-slim

# Basic runtime env
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Create non-root user
RUN useradd -m -u 10001 appuser

# Install deps
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r /app/requirements.txt

# Copy app
COPY app /app/app
COPY templates /app/templates
COPY static /app/static
COPY app.py /app/app.py

# Data dir for sqlite
RUN mkdir -p /data && chown -R appuser:appuser /data

# App config defaults (can be overridden by docker-compose)
ENV VILINKS_PORT=8765 \
    VILINKS_BIND=0.0.0.0 \
    VILINKS_DB=/data/vilinks.db \
    VILINKS_PREFIX=vi

EXPOSE 8765

USER appuser

CMD ["python", "/app/app.py"]