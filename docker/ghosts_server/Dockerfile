FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN useradd -m -u 1000 appuser

COPY . .

RUN mkdir -p /app/ghosts && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 5000

ENV GHOSTS_DIR=/app/ghosts

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "main:app"]
