ARG PYTHON_IMAGE=python:3.12-slim
FROM ${PYTHON_IMAGE}
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY pyproject.toml /app/
COPY src/serving/medical_rag /app/src/serving/medical_rag
RUN --mount=type=cache,target=/root/.cache/pip pip install ".[ui]" \
    && useradd --uid 1000 --create-home appuser
USER appuser
EXPOSE 8501
CMD ["streamlit", "run", "src/serving/medical_rag/frontend/app.py", "--server.address=0.0.0.0", "--server.port=8501", "--browser.gatherUsageStats=false"]
