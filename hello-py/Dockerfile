# Warms the same Python packages the session's Python service needs. Same
# base image, same ENV/WORKDIR, and requirements.txt has the same content as
# the real one (Docker's cache for COPY is keyed on file content, not path),
# so the pip install layer carries over on the day. Nothing here runs the
# real program.

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

CMD ["python", "-c", "import platform; print('hello from python:3.12-slim'); print('ARCH=' + platform.machine())"]
