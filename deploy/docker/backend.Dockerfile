ARG PYTHON_IMAGE=python:3.12-slim
FROM ${PYTHON_IMAGE}
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY pyproject.toml /app/
COPY src/serving/medical_rag /app/src/serving/medical_rag
RUN --mount=type=cache,target=/root/.cache/pip pip install ".[api]" \
    && useradd --uid 1000 --create-home appuser
USER appuser
EXPOSE 8000
CMD ["uvicorn", "medical_rag.backend.api:app", "--host", "0.0.0.0", "--port", "8000"]
