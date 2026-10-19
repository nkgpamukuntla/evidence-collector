# syntax=docker/dockerfile:1
# linux/arm64 only (R8). Pin both base images by digest before merging.
ARG PYTHON_VERSION=3.12
FROM ghcr.io/astral-sh/uv:0.8 AS uv

FROM python:${PYTHON_VERSION}-slim-bookworm AS build
COPY --from=uv /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY . .
RUN uv sync --frozen --no-dev

FROM python:${PYTHON_VERSION}-slim-bookworm
RUN useradd --uid 10001 --no-create-home app
WORKDIR /app
COPY --from=build --chown=app:app /app /app
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1
USER 10001
# TODO(dev): the process entry point does not exist yet. ECS passes the command per
# component (worker_command / evaluator_command / db_bootstrap_command).
CMD ["python", "-c", "raise SystemExit('no entry point yet')"]
