# poetry.lock is the only record of what this image installs. It used to be
# exported by hand to a requirements.txt that Renovate then bumped line by line,
# which let the two drift and once paired pydantic 2.14.1 with the pydantic-core
# that 2.13.5 pins, so the image would not build. Exporting here means the
# resolver's answer is what gets installed.
FROM python:3.14@sha256:504679006065cdab9a85e983e269140d3c5a279492395a6863b25b1ffb377f86 AS requirements

RUN pip install --no-cache-dir poetry==2.5.1 poetry-plugin-export==1.10.1

WORKDIR /src

COPY ./pyproject.toml ./poetry.lock /src/

RUN poetry export --without-hashes --only main -o requirements.txt

FROM python:3.14@sha256:504679006065cdab9a85e983e269140d3c5a279492395a6863b25b1ffb377f86

WORKDIR /code

COPY --from=requirements /src/requirements.txt /code/requirements.txt

RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

COPY ./app /code/app

CMD ["python", "-m", "uvicorn", "app.welcome:app", "--host", "0.0.0.0", "--port", "80"]
