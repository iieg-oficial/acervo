FROM python:3.13-alpine

RUN python -m pip uninstall -y -q pip

WORKDIR /app

COPY ontoy_server.py /app/ontoy_server.py

USER 65534:65534

EXPOSE 8088

CMD ["python", "/app/ontoy_server.py"]
