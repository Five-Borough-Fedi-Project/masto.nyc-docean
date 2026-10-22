FROM python:3.15-slim@sha256:490c3463f3766091067a01528e6be3208104eebcca11a306beab5de9672ee893

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
