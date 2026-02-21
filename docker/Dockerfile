FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY app /app/app
COPY templates /app/templates
COPY static /app/static
COPY app.py /app/app.py

ENV VILINKS_PORT=8765
ENV VILINKS_BIND=0.0.0.0
ENV VILINKS_DB=/data/vilinks.db
ENV VILINKS_BASE_HOST=vi

EXPOSE 8765

CMD ["python", "/app/app.py"]
