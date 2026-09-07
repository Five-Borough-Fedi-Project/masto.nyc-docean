FROM python:3.14-slim@sha256:cad9a2c871761c413caa6fdd6441c783451e740a48aaeba60ae62a8b53525ef6

WORKDIR /code

COPY ./requirements.txt /code/requirements.txt

RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

COPY ./app /code/app

# Default environment variables (can be overridden)
ENV MASTODON_HOSTNAME=""
ENV FRESHNESS_THRESHOLD="60"
ENV SAMPLE_SIZE="20"
ENV HEARTBEAT_URL=""

ENTRYPOINT ["python", "-m", "app.health_check"]
