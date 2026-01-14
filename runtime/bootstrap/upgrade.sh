#! /bin/bash

LATEST_RUNTIME_VERSION="260101"

VERSION_FILE="/opt/execution_runtime_version.txt"
OPENHANDS_TIME_VERSION="250501" # very old version from openhands
PRIMITIVE_TIME_VERSION="251201" # the version before we introduced the version tracking
FIRST_TIME_VERSION="260101" # the first version with version tracking

CURRENT_VERSION=$PRIMITIVE_TIME_VERSION

if [ -f "$VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat "$VERSION_FILE")
else
    if [ ! -f "/kepilot/micromamba/bin/micromamba" ]; then
        CURRENT_VERSION=$OPENHANDS_TIME_VERSION
    fi
fi

# a function to pull the latest code from the openhands repository
pull_latest_code() {
    echo "Pulling latest code from openhands repository..."

    url="git@github.com:nenus-ai/oais.git"
    branch="mvp"

    cd /kepilot/code
    if [ ! -d "/kepilot/code/openhands" ]; then
        git clone -b $branch $url
    else
        cd /kepilot/code/openhands
        git checkout .
        git clean -fd
        git fetch origin $branch:$branch
        git checkout $branch
        git pull origin $branch
    fi

    cp /kepilot/code/openhands/pyproject.toml  /kepilot/code/openhands/poetry.lock /kepilot/code/
    chmod a+rwx /kepilot/code/openhands/__init__.py
}

if [ "$CURRENT_VERSION" -eq "$OPENHANDS_TIME_VERSION" ]; then
    echo "Detected very old version from openhands ($CURRENT_VERSION). Upgrading..."

    export POETRY_VIRTUALENVS_PATH="/kepilot/poetry"
    export MAMBA_ROOT_PREFIX=/kepilot/micromamba
    export OPENVSCODE_SERVER_ROOT=/kepilot/.openvscode-server

    # setup_base_system
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/kepilot/bin" sh
    export PATH="/kepilot/bin:${PATH}"

    mkdir -p /kepilot && \
    mkdir -p /kepilot/logs && \
    mkdir -p /kepilot/poetry

    # Install micromamba
    mkdir -p /kepilot/micromamba/bin && \
        /bin/bash -c "PREFIX_LOCATION=/kepilot/micromamba BIN_FOLDER=/kepilot/micromamba/bin INIT_YES=no CONDA_FORGE_YES=yes $(curl -L https://micro.mamba.pm/install.sh)" && \
        /kepilot/micromamba/bin/micromamba config remove channels defaults && \
        /kepilot/micromamba/bin/micromamba config list

    # Create the kepilot virtual environment and install poetry and python
    /kepilot/micromamba/bin/micromamba create -n kepilot -y && \
        /kepilot/micromamba/bin/micromamba install -n kepilot -c conda-forge poetry python=3.12 -y

    if [ -d /kepilot/code ]; then rm -rf /kepilot/code;

    # install_dependencies
    mkdir -p /kepilot/code && cd /kepilot/code

    /kepilot/micromamba/bin/micromamba config set changeps1 False && \
    /kepilot/micromamba/bin/micromamba run -n kepilot poetry config virtualenvs.path /kepilot/poetry && \
    /kepilot/micromamba/bin/micromamba run -n kepilot poetry env use python3.12

    /kepilot/micromamba/bin/micromamba run -n kepilot poetry install --only main --no-interaction --no-root
    /kepilot/micromamba/bin/micromamba run -n kepilot poetry install --only runtime --no-interaction --no-root

    /kepilot/micromamba/bin/micromamba run -n kepilot poetry run pip install playwright && \
    /kepilot/micromamba/bin/micromamba run -n kepilot poetry run playwright install --with-deps chromium

    /kepilot/micromamba/bin/micromamba run -n kepilot poetry run python -c "import sys; print('OH_INTERPRETER_PATH=' + sys.executable)" >> /etc/environment && \
    chmod -R g+rws /kepilot/poetry && \
    mkdir -p /kepilot/workspace && chmod -R g+rws,o+rw /kepilot/workspace

    /kepilot/micromamba/bin/micromamba run -n kepilot poetry cache clear --all . -n && \
    /kepilot/micromamba/bin/micromamba clean --all

    # Copy Project source files
    if [ -d /kepilot/code/openhands ]; then rm -rf /kepilot/code/openhands; fi

    pull_latest_code()

    # install_vscode_extensions
    mkdir -p ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-hello-world && \
    cp -r /kepilot/code/openhands/runtime/utils/vscode-extensions/hello-world/* ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-hello-world/

    mkdir -p ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-memory-monitor && \
    cp -r /kepilot/code/openhands/runtime/utils/vscode-extensions/memory-monitor/* ${OPENVSCODE_SERVER_ROOT}/extensions/kepilot-memory-monitor/
fi

echo "Upgrading execution runtime from version $CURRENT_VERSION to $LATEST_RUNTIME_VERSION..."

if [ "$CURRENT_VERSION" -lt "$FIRST_TIME_VERSION" ]; then
    apt-get install -y --no-install-recommends libgl1
    apt-get install -y fonts-unifont fonts-ubuntu || apt-get install -y ttf-unifont ttf-ubuntu-font-family
    /kepilot/micromamba/bin/micromamba run -n kepilot poetry run playwright install --with-deps chromium || \
        (apt-get install -y libnss3 libnspr4 libatk1.0-0 libatspi2.0-0 libxcomposite1 libxdamage1 libxrandr2 libxkbcommon0 && \
        /kepilot/micromamba/bin/micromamba run -n kepilot poetry run playwright install chromium)
fi

pull_latest_code()

# write the latest version to the version file
echo "$LATEST_RUNTIME_VERSION" > "$VERSION_FILE"