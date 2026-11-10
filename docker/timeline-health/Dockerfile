FROM python:3.15-slim@sha256:65a65fc7b30b06cb6df4930fd4650697cb23f4c2698ab81fc87e4b031bc36928

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
