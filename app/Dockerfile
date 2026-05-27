FROM python:3.12-slim

# Evita arquivos pyc e garante logs imediatos no stdout.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Cria identidade nao-root fixa para demonstrar runAsUser/runAsGroup no cluster.
RUN groupadd --gid 30001 appgroup \
    && useradd --uid 10001 --gid 30001 --no-create-home --shell /usr/sbin/nologin appuser

# Copia apenas dependencias primeiro para melhorar cache de build.
COPY requirements.txt /app/requirements.txt

# Instala apenas os pacotes necessarios para a API.
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copia o codigo da aplicacao.
COPY main.py /app/main.py

# Prepara diretorios didaticos:
# - /tmp para escrita temporaria
# - /data para testes com volume/permissoes
RUN mkdir -p /tmp /data \
    && chown -R 10001:30001 /tmp /data /app

# Processo final roda sem privilegios de root.
USER 10001:30001

EXPOSE 8080

# Uvicorn em 0.0.0.0 para funcionar localmente e no Kubernetes.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
