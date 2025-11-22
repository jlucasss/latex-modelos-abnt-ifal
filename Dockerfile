FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    bash curl git nodejs npm python3 perl make \
    latexmk \
    texlive \
    texlive-lang-portuguese \
    texlive-latex-extra \
    texlive-fonts-extra \
    texlive-publishers \
    texlive-science \
    texlive-xetex \
    # Instalar code-server
    && curl -fsSL https://raw.githubusercontent.com/coder/code-server/main/install.sh | sh \
    # Instalar extensão no code-server para ver pdf
    && code-server --install-extension mathematic.vscode-pdf \
    ## Remove
    && rm -rf /var/lib/apt/lists/*

# Definir diretório de trabalho
WORKDIR /home/abc/workspace/meus-trabalhos

EXPOSE 8443
CMD ["code-server", "--bind-addr", "0.0.0.0:8443", "--auth", "password", "/home/abc/workspace/meus-trabalhos"]
