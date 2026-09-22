FROM python:3.14-slim@sha256:caaf356f40667c496d405780745b9ac25771c189a51dfcc42430d531ea09f8a2

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
