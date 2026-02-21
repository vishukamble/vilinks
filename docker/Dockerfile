FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN useradd -m -u 10001 appuser

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r /app/requirements.txt

COPY app /app/app
COPY app.py /app/app.py

RUN mkdir -p /data && chown -R appuser:appuser /data

ENV VILINKS_PORT=8765 \
    VILINKS_BIND=0.0.0.0 \
    VILINKS_DB=/data/vilinks.db \
    VILINKS_PREFIX=vi

EXPOSE 8765
USER appuser

CMD ["python", "/app/app.py"]