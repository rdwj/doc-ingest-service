FROM registry.access.redhat.com/ubi9/python-311:latest

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

USER 1001

EXPOSE 8001

ENV PYTHONUNBUFFERED=1
ENV APP_MODULE=src.main:app

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8001"]
