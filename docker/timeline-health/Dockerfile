FROM python:3.12-slim

WORKDIR /code

COPY ./requirements.txt /code/requirements.txt

RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

COPY ./app /code/app

# Default environment variables (can be overridden)
ENV MASTODON_HOSTNAME=""
ENV FRESHNESS_THRESHOLD="60"
ENV HEARTBEAT_URL=""

ENTRYPOINT ["python", "-m", "app.health_check"]
